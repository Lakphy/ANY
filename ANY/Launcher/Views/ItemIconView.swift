import AppKit
import SwiftUI

struct ItemIconView: View {
    let icon: ItemIcon
    let size: CGFloat

    var body: some View {
        switch icon {
        case .symbol(let name):
            let shape = RoundedRectangle(cornerRadius: Theme.Radius.tile(size), style: .continuous)
            Image(systemName: name)
                .font(.system(size: size * 0.48, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color.primary.opacity(0.85))
                .frame(width: size, height: size)
                .background(.fill.secondary, in: shape)
                .overlay(shape.strokeBorder(.separator, lineWidth: 0.5))
        case .file(let path):
            Image(nsImage: IconCache.shared.icon(forFile: path))
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        case .image(let image):
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        case .emoji(let emoji):
            Text(emoji)
                .font(.system(size: size * 0.8))
                .frame(width: size, height: size)
        }
    }
}

final class IconCache {
    static let shared = IconCache()

    private let cache = NSCache<NSString, NSImage>()

    func icon(forFile path: String) -> NSImage {
        if let cached = cache.object(forKey: path as NSString) { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(image, forKey: path as NSString)
        return image
    }
}
