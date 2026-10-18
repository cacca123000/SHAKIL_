import AVFoundation
import CoreImage
import Foundation
import QuartzCore

/// Histogram bins, normalised 0...1. Published ~10 times per second.
struct Histogram: Equatable {
    static let bins = 64
    var luma: [Float]
    var red: [Float]
    var green: [Float]
    var blue: [Float]
    /// Fraction of pixels that are clipped (pure white / pure black).
    var clippedHighlights: Float
    var clippedShadows: Float
}

final class HistogramModel: ObservableObject {
    @Published var value: Histogram?
}

/// Receives frames from AVCaptureVideoDataOutput. Keeps the newest frame for the
/// processed viewfinder and computes a live histogram.
final class FrameProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let queue = DispatchQueue(label: "cam.frames", qos: .userInitiated)

    /// Orientation that turns the sensor (landscape) buffer upright in portrait.
    var orientation: CGImagePropertyOrientation {
        get { lock.withLock { _orientation } }
        set { lock.withLock { _orientation = newValue } }
    }

    var histogramEnabled: Bool {
        get { lock.withLock { _histogramEnabled } }
        set { lock.withLock { _histogramEnabled = newValue } }
    }

    var onHistogram: ((Histogram) -> Void)?

    private let lock = NSLock()
    private var _orientation: CGImagePropertyOrientation = .right
    private var _histogramEnabled = true
    private var latest: CIImage?
    private var lastHistogramTime: CFTimeInterval = 0
    private var frameCount = 0

    private let analysisContext = CIContext(options: [
        .workingColorSpace: NSNull(),
        .outputColorSpace: NSNull(),
        .cacheIntermediates: false,
    ])
    private let analysisWidth = 160
    private let analysisHeight = 90
    private lazy var analysisBuffer = [UInt8](repeating: 0, count: analysisWidth * analysisHeight * 4)

    /// Newest upright frame, or nil if none arrived yet.
    func latestImage() -> CIImage? {
        lock.withLock { latest }
    }

    func reset() {
        lock.withLock { latest = nil }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let raw = CIImage(cvPixelBuffer: pixelBuffer, options: [.colorSpace: NSNull()])
        let upright = raw.oriented(orientation)
        let image = upright.transformed(by: CGAffineTransform(
            translationX: -upright.extent.minX, y: -upright.extent.minY
        ))
        lock.withLock { latest = image }

        frameCount += 1
        let now = CACurrentMediaTime()
        if histogramEnabled, now - lastHistogramTime > 0.1 {
            lastHistogramTime = now
            computeHistogram(raw)
        }
    }

    private func computeHistogram(_ image: CIImage) {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return }
        let scaled = image.transformed(by: CGAffineTransform(
            scaleX: CGFloat(analysisWidth) / extent.width,
            y: CGFloat(analysisHeight) / extent.height
        ))
        let bounds = CGRect(x: scaled.extent.minX, y: scaled.extent.minY,
                            width: CGFloat(analysisWidth), height: CGFloat(analysisHeight))

        let count = Histogram.bins
        var r = [Float](repeating: 0, count: count)
        var g = [Float](repeating: 0, count: count)
        var b = [Float](repeating: 0, count: count)
        var y = [Float](repeating: 0, count: count)
        var highs = 0
        var lows = 0

        analysisBuffer.withUnsafeMutableBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            analysisContext.render(scaled, toBitmap: base, rowBytes: analysisWidth * 4,
                                   bounds: bounds, format: .RGBA8, colorSpace: nil)
        }

        let pixels = analysisWidth * analysisHeight
        let shift = 256 / count
        for i in 0..<pixels {
            let o = i * 4
            let rv = Int(analysisBuffer[o])
            let gv = Int(analysisBuffer[o + 1])
            let bv = Int(analysisBuffer[o + 2])
            let lv = (rv * 54 + gv * 183 + bv * 19) >> 8
            r[rv / shift] += 1
            g[gv / shift] += 1
            b[bv / shift] += 1
            y[min(lv, 255) / shift] += 1
            if lv >= 252 { highs += 1 }
            if lv <= 3 { lows += 1 }
        }

        func normalise(_ values: [Float]) -> [Float] {
            // sqrt keeps small peaks visible next to big ones.
            let peak = values.max() ?? 1
            guard peak > 0 else { return values }
            return values.map { ($0 / peak).squareRoot() }
        }

        let histogram = Histogram(
            luma: normalise(y), red: normalise(r), green: normalise(g), blue: normalise(b),
            clippedHighlights: Float(highs) / Float(pixels),
            clippedShadows: Float(lows) / Float(pixels)
        )
        if let onHistogram {
            DispatchQueue.main.async { onHistogram(histogram) }
        }
    }
}
