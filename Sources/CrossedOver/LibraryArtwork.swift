import ImageIO
import SwiftUI

/// Serial background decoding keeps disk access and first-draw decompression
/// out of SwiftUI layout. Shared bounded storage also survives lazy-row reuse.
actor LibraryArtworkCache {
    static let shared = LibraryArtworkCache()
    private let cache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 64; cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()
    private var missing: [String: Date] = [:]

    func image(at path: String) -> CGImage? {
        if let image = cache.object(forKey: path as NSString) { return image }
        if let retry = missing[path], retry > Date() { return nil }
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: 640
              ] as CFDictionary) else {
            if missing.count >= 256 { missing.removeAll(keepingCapacity: true) }
            missing[path] = Date().addingTimeInterval(30)
            return nil
        }
        missing.removeValue(forKey: path)
        cache.setObject(image, forKey: path as NSString, cost: image.bytesPerRow * image.height)
        return image
    }
}

struct LibraryArtwork<Content: View>: View {
    let path: String?
    var preview: CGImage?
    @ViewBuilder var content: (CGImage?) -> Content
    @State private var image: CGImage?
    @State private var loadedPath: String?

    var body: some View {
        content(preview ?? (loadedPath == path ? image : nil))
            .task(id: path, priority: .utility) {
                guard preview == nil, let path else { return }
                let decoded = await LibraryArtworkCache.shared.image(at: path)
                guard !Task.isCancelled else { return }
                image = decoded; loadedPath = path
            }
    }
}
