import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UIKit

/// Delegate for one photo capture. Collects the processed image and the optional
/// RAW (DNG), applies the selected look, writes the files and reports back.
final class PhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate {
    struct Result {
        let processedURL: URL?
        let rawURL: URL?
        let thumbnail: UIImage?
        let details: [String]
    }

    private let processedCodec: AVVideoCodecType
    private let look: LookPreset
    private let willCapture: () -> Void
    private let completion: (Result?, Error?) -> Void

    private var processedData: Data?
    private var rawData: Data?
    private var metadata: [String: Any] = [:]
    private var captureError: Error?

    init(processedCodec: AVVideoCodecType, look: LookPreset,
         willCapture: @escaping () -> Void,
         completion: @escaping (Result?, Error?) -> Void) {
        self.processedCodec = processedCodec
        self.look = look
        self.willCapture = willCapture
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        willCapture()
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            captureError = error
            return
        }
        if photo.isRawPhoto {
            rawData = photo.fileDataRepresentation()
        } else {
            processedData = photo.fileDataRepresentation()
            metadata = photo.metadata
        }
        if metadata.isEmpty {
            metadata = photo.metadata
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error = error ?? captureError {
            completion(nil, error)
            return
        }
        let dimensions = resolvedSettings.photoDimensions
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            var processed = processedData
            if let data = processed, look != .natural {
                processed = LookBaker.apply(look, to: data, heif: processedCodec == .hevc) ?? data
            }

            var processedURL: URL?
            if let processed {
                let url = MediaLibrary.newFileURL(processedCodec == .hevc ? "heic" : "jpg")
                if (try? processed.write(to: url)) != nil { processedURL = url }
            }
            var rawURL: URL?
            if let rawData {
                let url = MediaLibrary.newFileURL("dng")
                if (try? rawData.write(to: url)) != nil { rawURL = url }
            }
            guard processedURL != nil || rawURL != nil else {
                completion(nil, nil)
                return
            }

            let thumbnail = (processedURL ?? rawURL).flatMap { MediaLibrary.thumbnail(for: $0) }
            completion(Result(
                processedURL: processedURL,
                rawURL: rawURL,
                thumbnail: thumbnail,
                details: details(dimensions: dimensions)
            ), nil)
        }
    }

    private func details(dimensions: CMVideoDimensions) -> [String] {
        var items: [String] = []
        let exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any]
        if let iso = (exif?[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber])?.first {
            items.append("ISO \(iso.intValue)")
        }
        if let exposure = exif?[kCGImagePropertyExifExposureTime as String] as? Double {
            items.append(Format.shutter(exposure))
        }
        if let aperture = exif?[kCGImagePropertyExifFNumber as String] as? Double {
            items.append(String(format: "ƒ%.1f", aperture))
        }
        if let focal = exif?[kCGImagePropertyExifFocalLenIn35mmFilm as String] as? NSNumber {
            items.append("\(focal.intValue)mm")
        }
        let megapixels = Double(dimensions.width) * Double(dimensions.height) / 1_000_000
        if megapixels > 0 {
            items.append(String(format: "%.0f MP", megapixels.rounded()))
        }
        var format = processedCodec == .hevc ? "HEIF" : "JPEG"
        if rawData != nil { format = processedData != nil ? "RAW+\(format)" : "RAW" }
        items.append(format)
        if look != .natural { items.append(look.title) }
        return items
    }
}

/// Bakes a creative look into a HEIF/JPEG while keeping its metadata.
enum LookBaker {
    private static let context = CIContext()

    static func apply(_ look: LookPreset, to data: Data, heif: Bool) -> Data? {
        guard let cube = ColorCubes.cube(for: look),
              let input = CIImage(data: data, options: [.applyOrientationProperty: true])
        else { return nil }

        let filter = CIFilter.colorCubeWithColorSpace()
        filter.inputImage = input
        filter.cubeDimension = Float(ColorCubes.size)
        filter.cubeData = cube
        filter.colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        guard let output = filter.outputImage else { return nil }

        // The pixels are now upright: reset the orientation tags.
        var properties = input.properties
        properties[kCGImagePropertyOrientation as String] = 1
        if var tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            tiff[kCGImagePropertyTIFFOrientation as String] = 1
            properties[kCGImagePropertyTIFFDictionary as String] = tiff
        }
        let tagged = output.settingProperties(properties)

        let colorSpace = input.colorSpace
            ?? CGColorSpace(name: CGColorSpace.displayP3)
            ?? CGColorSpaceCreateDeviceRGB()
        let quality = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
        if heif {
            return context.heifRepresentation(of: tagged, format: .RGBA8, colorSpace: colorSpace, options: [quality: 0.9])
        }
        return context.jpegRepresentation(of: tagged, colorSpace: colorSpace, options: [quality: 0.92])
    }
}
