import FuelstatCore
import SwiftUI
import UIKit

/// Caches vehicle photos in memory and on disk.
///
/// Photos come from signed addresses that change daily, but the file behind them never changes, so the cache is
/// keyed by file name (see `ImageCacheKey`). The disk cache lives in Caches, so iOS may clear it when space is low.
actor ImageCache {
    static let shared = ImageCache()

    private let memory = NSCache<NSString, UIImage>()
    private let directory: URL
    private var running: [String: Task<UIImage?, Never>] = [:]

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("vehicle-images", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        memory.countLimit = 100
    }

    func image(for url: URL) async -> UIImage? {
        let key = ImageCacheKey.key(for: url)
        if let image = memory.object(forKey: key as NSString) { return image }
        if let task = running[key] { return await task.value }

        let file = directory.appendingPathComponent(key)
        let task = Task<UIImage?, Never> {
            if let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
                return image
            }
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = UIImage(data: data) else { return nil }
            try? data.write(to: file, options: .atomic)
            return image
        }
        running[key] = task
        let image = await task.value
        running[key] = nil
        if let image { memory.setObject(image, forKey: key as NSString) }
        return image
    }

    /// Stores a photo the user just uploaded, so it shows immediately without downloading it again.
    func store(_ image: UIImage, data: Data, for url: URL) {
        let key = ImageCacheKey.key(for: url)
        memory.setObject(image, forKey: key as NSString)
        try? data.write(to: directory.appendingPathComponent(key), options: .atomic)
    }
}

/// Vehicle photo from the API, or a symbol for the fuel type while loading or without a photo.
struct VehiclePhoto: View {
    let url: URL?
    let fuelType: RemoteFuelType

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(.tint.opacity(0.12))
                Image(systemName: fuelType.symbol)
                    .font(.title2)
                    .foregroundStyle(.tint)
            }
        }
        .clipped()
        .accessibilityHidden(true)
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            image = await ImageCache.shared.image(for: url)
        }
    }
}
