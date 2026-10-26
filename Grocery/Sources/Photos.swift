import SwiftUI
import UIKit

/// Item photos, shrunk and kept next to the rest of the app's data.
enum PhotoStore {
    private static let cache = NSCache<NSString, UIImage>()

    /// Saves a picked photo as a small JPEG and returns its file name.
    static func save(_ data: Data) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        let longest: CGFloat = 600
        let scale = min(1, longest / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpeg = resized.jpegData(compressionQuality: 0.7) else { return nil }
        let name = "\(UUID().uuidString).jpg"
        do { try jpeg.write(to: Storage.photos.appending(path: name), options: .atomic) } catch { return nil }
        return name
    }

    static func image(named name: String) -> UIImage? {
        if let cached = cache.object(forKey: name as NSString) { return cached }
        guard let image = UIImage(contentsOfFile: Storage.photos.appending(path: name).path) else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }

    static func remove(_ name: String) {
        cache.removeObject(forKey: name as NSString)
        try? FileManager.default.removeItem(at: Storage.photos.appending(path: name))
    }
}

struct ItemThumbnail: View {
    let name: String
    var size: CGFloat = 40

    var body: some View {
        if let image = PhotoStore.image(named: name) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
        }
    }
}
