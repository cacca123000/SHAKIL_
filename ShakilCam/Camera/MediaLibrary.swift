import AVFoundation
import ImageIO
import Photos
import UIKit

/// A photo or video taken in this session (kept locally for the in-app gallery;
/// every capture is also saved to the Photos library).
struct CapturedMedia: Identifiable {
    enum Kind { case photo, video }

    let id = UUID()
    let kind: Kind
    let url: URL
    let rawURL: URL?
    let thumbnail: UIImage?
    let date: Date
    let details: [String]
    var savedToPhotos: Bool
}

enum MediaLibrary {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Captures", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Removes files from previous sessions so the cache does not grow forever.
    static func purgeOldFiles() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files {
            try? fm.removeItem(at: file)
        }
    }

    static func newFileURL(_ ext: String) -> URL {
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        return directory.appendingPathComponent("SHK_\(stamp)_\(UUID().uuidString.prefix(4)).\(ext)")
    }

    static func requestAddPermission(_ completion: @escaping (Bool) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            completion(true)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                DispatchQueue.main.async {
                    completion(newStatus == .authorized || newStatus == .limited)
                }
            }
        default:
            completion(false)
        }
    }

    static func savePhoto(processedURL: URL?, rawURL: URL?, completion: @escaping (Bool, Error?) -> Void) {
        requestAddPermission { granted in
            guard granted else {
                completion(false, nil)
                return
            }
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                if let processedURL {
                    request.addResource(with: .photo, fileURL: processedURL, options: nil)
                    if let rawURL {
                        request.addResource(with: .alternatePhoto, fileURL: rawURL, options: nil)
                    }
                } else if let rawURL {
                    request.addResource(with: .photo, fileURL: rawURL, options: nil)
                }
            }, completionHandler: { success, error in
                DispatchQueue.main.async { completion(success, error) }
            })
        }
    }

    static func saveVideo(_ url: URL, completion: @escaping (Bool, Error?) -> Void) {
        requestAddPermission { granted in
            guard granted else {
                completion(false, nil)
                return
            }
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .video, fileURL: url, options: nil)
            }, completionHandler: { success, error in
                DispatchQueue.main.async { completion(success, error) }
            })
        }
    }

    /// Fast thumbnail for HEIF, JPEG and DNG files.
    static func thumbnail(for url: URL, maxPixel: Int = 600) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    static func videoThumbnail(for url: URL) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 600, height: 600)
        guard let result = try? await generator.image(at: .zero) else { return nil }
        return UIImage(cgImage: result.image)
    }

    static func fileSize(_ url: URL) -> Int64 {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return Int64(size)
    }

    /// Free space usable for new recordings.
    static func availableBytes() -> Int64 {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }
}
