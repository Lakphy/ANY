import AppKit

enum SystemActions {
    struct AppleScriptError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func lockScreen() {
        typealias LockScreen = @convention(c) () -> Void
        let loginFramework = "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login"
        if let handle = dlopen(loginFramework, RTLD_NOW), let symbol = dlsym(handle, "SACLockScreenImmediate") {
            unsafeBitCast(symbol, to: LockScreen.self)()
        } else {
            runProcess("/usr/bin/pmset", arguments: ["displaysleepnow"])
        }
    }

    static func sleep() {
        runProcess("/usr/bin/pmset", arguments: ["sleepnow"])
    }

    static func startScreenSaver() {
        NSWorkspace.shared.open(URL(filePath: "/System/Library/CoreServices/ScreenSaverEngine.app"))
    }

    static func toggleDarkMode() throws {
        try runAppleScript("""
        tell application "System Events" to tell appearance preferences to set dark mode to not dark mode
        """)
    }

    static func emptyTrash() throws {
        try runAppleScript(#"tell application "Finder" to empty trash"#)
    }

    static func restart() throws {
        try runAppleScript(#"tell application "System Events" to restart"#)
    }

    static func shutDown() throws {
        try runAppleScript(#"tell application "System Events" to shut down"#)
    }

    private static func runAppleScript(_ source: String) throws {
        var errorInfo: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "AppleScript 执行失败"
            throw AppleScriptError(message: message)
        }
    }

    private static func runProcess(_ path: String, arguments: [String]) {
        _ = try? Process.run(URL(filePath: path), arguments: arguments)
    }
}
