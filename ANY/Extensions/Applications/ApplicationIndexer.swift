import Foundation

nonisolated struct InstalledApp: Sendable {
    let name: String
    let fileName: String
    let path: String
    let bundleID: String?
}

/// Scans the standard application folders. Runs off the main actor.
nonisolated enum ApplicationIndexer {
    private static let maxDepth = 3

    static let searchRoots = [
        URL(filePath: "/Applications"),
        URL(filePath: "/System/Applications"),
        URL(filePath: "/System/Library/CoreServices/Applications"),
        URL.homeDirectory.appending(path: "Applications"),
    ]

    static func scan() -> [InstalledApp] {
        let fileManager = FileManager.default
        let roots = searchRoots
        let extras = [URL(filePath: "/System/Library/CoreServices/Finder.app")]

        var seenBundleIDs = Set<String>()
        var seenPaths = Set<String>()
        var seenNames = Set<String>()
        var apps: [InstalledApp] = []

        // Roots are ordered by priority, so the first app seen with a given name wins.
        func add(_ url: URL) {
            var path = url.resolvingSymlinksInPath().path(percentEncoded: false)
            if path.hasSuffix("/") { path.removeLast() }
            guard seenPaths.insert(path).inserted else { return }
            let bundleID = Bundle(url: url)?.bundleIdentifier
            if let bundleID, !seenBundleIDs.insert(bundleID).inserted { return }

            let fileName = url.deletingPathExtension().lastPathComponent
            var name = fileManager.displayName(atPath: path)
            if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
            guard seenNames.insert(name.lowercased()).inserted else { return }
            apps.append(InstalledApp(name: name, fileName: fileName, path: path, bundleID: bundleID))
        }

        for root in roots {
            // System apps like Safari are hidden-flagged symlinks into a Cryptex, which the
            // enumerator below skips; list each root's top level directly to catch them.
            let topLevel = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            topLevel.filter { $0.pathExtension == "app" }.forEach(add)

            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            while let url = enumerator.nextObject() as? URL {
                if enumerator.level > maxDepth {
                    enumerator.skipDescendants()
                    continue
                }
                if url.pathExtension == "app" {
                    add(url)
                }
            }
        }
        extras.filter { fileManager.fileExists(atPath: $0.path(percentEncoded: false)) }.forEach(add)

        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
