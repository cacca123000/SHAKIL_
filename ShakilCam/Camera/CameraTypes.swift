import AVFoundation
import CoreGraphics
import Foundation

// MARK: - Capture mode

enum CaptureMode: String, Codable, CaseIterable, Identifiable {
    case photo, video
    var id: String { rawValue }
    var title: String { self == .photo ? "FOTO" : "VIDEO" }
}

// MARK: - Lenses

enum LensKind: String, Codable {
    case ultraWide, wide, telephoto, front

    var name: String {
        switch self {
        case .ultraWide: return "Ultra grandangolo"
        case .wide: return "Grandangolo"
        case .telephoto: return "Teleobiettivo"
        case .front: return "Frontale"
        }
    }
}

struct Lens: Identifiable, Equatable {
    let device: AVCaptureDevice
    let kind: LensKind
    /// Optical zoom relative to the main (wide) camera, e.g. 0.5, 1, 3, 5.
    let magnification: Double

    var id: String { device.uniqueID }

    var shortTitle: String {
        if kind == .front { return "F" }
        return magnification < 1 ? ".5" : Format.zoom(magnification, withSuffix: false)
    }
}

// MARK: - Video options

enum VideoResolution: String, Codable, CaseIterable, Identifiable {
    case hd720, hd1080, uhd4K
    var id: String { rawValue }

    var title: String {
        switch self {
        case .hd720: return "720p"
        case .hd1080: return "1080p"
        case .uhd4K: return "4K"
        }
    }

    /// Landscape (sensor native) dimensions.
    var width: Int32 {
        switch self {
        case .hd720: return 1280
        case .hd1080: return 1920
        case .uhd4K: return 3840
        }
    }

    var height: Int32 {
        switch self {
        case .hd720: return 720
        case .hd1080: return 1080
        case .uhd4K: return 2160
        }
    }
}

enum FrameRates {
    static let all: [Int] = [24, 25, 30, 48, 50, 60, 120, 240]
}

enum VideoCodec: String, Codable, CaseIterable, Identifiable {
    case hevc, h264, proRes
    var id: String { rawValue }

    var title: String {
        switch self {
        case .hevc: return "HEVC"
        case .h264: return "H.264"
        case .proRes: return "ProRes"
        }
    }

    var subtitle: String {
        switch self {
        case .hevc: return "File leggeri, 10 bit, ottima qualità"
        case .h264: return "Massima compatibilità, 8 bit"
        case .proRes: return "Qualità da cinema, file enormi"
        }
    }

    /// Codec types to try, best first.
    var candidates: [AVVideoCodecType] {
        switch self {
        case .hevc: return [.hevc]
        case .h264: return [.h264]
        case .proRes: return [.proRes422HQ, .proRes422, .proRes422LT]
        }
    }

    /// Rough bits per pixel per frame, used to estimate the recording time left.
    var bitsPerPixel: Double {
        switch self {
        case .hevc: return 0.1
        case .h264: return 0.2
        case .proRes: return 3.3
        }
    }
}

enum ColorProfile: String, Codable, CaseIterable, Identifiable {
    case sdr, hlg, appleLog
    var id: String { rawValue }

    var title: String {
        switch self {
        case .sdr: return "SDR"
        case .hlg: return "HDR"
        case .appleLog: return "LOG"
        }
    }

    var longTitle: String {
        switch self {
        case .sdr: return "Rec.709 SDR"
        case .hlg: return "HDR HLG (Dolby Vision)"
        case .appleLog: return "Apple Log"
        }
    }

    var subtitle: String {
        switch self {
        case .sdr: return "Colori standard, pronti da pubblicare"
        case .hlg: return "Alta gamma dinamica, luci brillanti"
        case .appleLog: return "Immagine piatta con la massima gamma dinamica: da gradare in post"
        }
    }

    var colorSpace: AVCaptureColorSpace {
        switch self {
        case .sdr: return .sRGB
        case .hlg: return .HLG_BT2020
        case .appleLog: return .appleLog
        }
    }
}

enum Stabilization: String, Codable, CaseIterable, Identifiable {
    case off, standard, cinematic, cinematicExtended
    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .standard: return "Standard"
        case .cinematic: return "Cinema"
        case .cinematicExtended: return "Cinema+"
        }
    }

    var mode: AVCaptureVideoStabilizationMode {
        switch self {
        case .off: return .off
        case .standard: return .standard
        case .cinematic: return .cinematic
        case .cinematicExtended: return .cinematicExtended
        }
    }
}

/// One supported (resolution, fps, profile) combination of the current lens.
struct VideoCombo: Hashable {
    let resolution: VideoResolution
    let fps: Int
    let profile: ColorProfile
}

// MARK: - Photo options

enum PhotoFormat: String, Codable, CaseIterable, Identifiable {
    case heif, jpeg, raw, proRAW
    var id: String { rawValue }

    var title: String {
        switch self {
        case .heif: return "HEIF"
        case .jpeg: return "JPEG"
        case .raw: return "RAW"
        case .proRAW: return "ProRAW"
        }
    }

    var subtitle: String {
        switch self {
        case .heif: return "Qualità alta, metà spazio del JPEG"
        case .jpeg: return "Compatibile ovunque"
        case .raw: return "DNG grezzo del sensore + HEIF"
        case .proRAW: return "DNG Apple con elaborazione computazionale"
        }
    }

    var isRAW: Bool { self == .raw || self == .proRAW }
}

enum PhotoResolution: String, Codable, CaseIterable, Identifiable {
    case standard, maximum
    var id: String { rawValue }
    var title: String { self == .standard ? "12 MP" : "MAX" }
}

enum FlashSetting: String, Codable, CaseIterable, Identifiable {
    case off, auto, on
    var id: String { rawValue }

    var mode: AVCaptureDevice.FlashMode {
        switch self {
        case .off: return .off
        case .auto: return .auto
        case .on: return .on
        }
    }

    var symbol: String {
        switch self {
        case .off: return "bolt.slash.fill"
        case .auto: return "bolt.badge.automatic.fill"
        case .on: return "bolt.fill"
        }
    }

    var next: FlashSetting {
        switch self {
        case .off: return .auto
        case .auto: return .on
        case .on: return .off
        }
    }
}

enum SelfTimer: Int, Codable, CaseIterable, Identifiable {
    case off = 0, three = 3, ten = 10
    var id: Int { rawValue }
    var title: String { self == .off ? "Off" : "\(rawValue)s" }

    var next: SelfTimer {
        switch self {
        case .off: return .three
        case .three: return .ten
        case .ten: return .off
        }
    }
}

// MARK: - Persisted settings

struct CameraSettings: Codable, Equatable {
    var mode: CaptureMode = .photo
    var preferredLens: LensKind = .wide

    var resolution: VideoResolution = .uhd4K
    var fps: Int = 30
    var codec: VideoCodec = .hevc
    var profile: ColorProfile = .sdr
    var stabilization: Stabilization = .standard
    var audioEnabled = true

    var photoFormat: PhotoFormat = .heif
    var photoResolution: PhotoResolution = .standard
    var flash: FlashSetting = .off
    var timer: SelfTimer = .off

    private static let key = "camera.settings.v1"

    static func load() -> CameraSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(CameraSettings.self, from: data)
        else { return CameraSettings() }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

/// What the current lens can do. Recomputed whenever the lens changes.
struct LensCapabilities {
    var combos: Set<VideoCombo> = []
    var codecs: [VideoCodec] = [.hevc, .h264]
    var photoFormats: [PhotoFormat] = [.heif, .jpeg]
    var stabilizations: [Stabilization] = [.off]
    var supportsMaxPhotoResolution = false
    var hasFlash = false
    var hasTorch = false
    var supportsManualFocus = false
    var supportsManualExposure = false
    var supportsManualWhiteBalance = false

    func supports(_ resolution: VideoResolution) -> Bool {
        combos.contains { $0.resolution == resolution }
    }

    func supports(_ resolution: VideoResolution, fps: Int) -> Bool {
        combos.contains { $0.resolution == resolution && $0.fps == fps }
    }

    func supports(_ resolution: VideoResolution, fps: Int, profile: ColorProfile) -> Bool {
        combos.contains(VideoCombo(resolution: resolution, fps: fps, profile: profile))
    }

    func supportsAnywhere(_ profile: ColorProfile) -> Bool {
        combos.contains { $0.profile == profile }
    }
}

// MARK: - Manual control discrete stops

enum Stops {
    static let iso: [Double] = [
        25, 32, 40, 50, 64, 80, 100, 125, 160, 200, 250, 320, 400, 500, 640, 800,
        1000, 1250, 1600, 2000, 2500, 3200, 4000, 5000, 6400, 8000, 10000, 12800,
    ]

    /// Denominators of 1/x second shutter speeds, then whole fractions above 1/4s.
    static let shutter: [Double] = [
        1.0 / 8000, 1.0 / 6400, 1.0 / 5000, 1.0 / 4000, 1.0 / 3200, 1.0 / 2500, 1.0 / 2000,
        1.0 / 1600, 1.0 / 1250, 1.0 / 1000, 1.0 / 800, 1.0 / 640, 1.0 / 500, 1.0 / 400,
        1.0 / 320, 1.0 / 250, 1.0 / 200, 1.0 / 160, 1.0 / 125, 1.0 / 100, 1.0 / 96, 1.0 / 80,
        1.0 / 60, 1.0 / 50, 1.0 / 48, 1.0 / 40, 1.0 / 30, 1.0 / 25, 1.0 / 24, 1.0 / 20,
        1.0 / 15, 1.0 / 13, 1.0 / 10, 1.0 / 8, 1.0 / 6, 1.0 / 5, 1.0 / 4, 0.3, 0.4, 0.5,
        0.6, 0.8, 1.0,
    ]

    static func ev(range: ClosedRange<Float>) -> [Double] {
        let lower = max(Double(range.lowerBound), -3)
        let upper = min(Double(range.upperBound), 3)
        var values: [Double] = []
        var v = (lower * 3).rounded(.up) / 3
        while v <= upper + 0.0001 {
            values.append((v * 100).rounded() / 100)
            v += 1.0 / 3
        }
        return values.isEmpty ? [0] : values
    }

    static let temperature: [Double] = stride(from: 2000.0, through: 10000.0, by: 100).map { $0 }
    static let tint: [Double] = stride(from: -100.0, through: 100.0, by: 5).map { $0 }
    static let focus: [Double] = stride(from: 0.0, through: 1.0, by: 0.01).map { ($0 * 100).rounded() / 100 }

    static func zoom(max: Double) -> [Double] {
        stride(from: 1.0, through: max, by: 0.1).map { ($0 * 10).rounded() / 10 }
    }

    static func nearestIndex(in values: [Double], to target: Double) -> Int {
        guard !values.isEmpty else { return 0 }
        var best = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (i, v) in values.enumerated() {
            let d = abs(v - target)
            if d < bestDistance {
                bestDistance = d
                best = i
            }
        }
        return best
    }
}

struct WhiteBalancePreset: Identifiable {
    let id: String
    let symbol: String
    let temperature: Double

    static let all: [WhiteBalancePreset] = [
        .init(id: "Tungsteno", symbol: "lightbulb.fill", temperature: 3200),
        .init(id: "Neon", symbol: "light.panel.fill", temperature: 4000),
        .init(id: "Sole", symbol: "sun.max.fill", temperature: 5600),
        .init(id: "Nuvoloso", symbol: "cloud.fill", temperature: 6500),
        .init(id: "Ombra", symbol: "building.fill", temperature: 7500),
    ]
}

// MARK: - Formatting helpers

enum Format {
    static func shutter(_ seconds: Double) -> String {
        guard seconds > 0 else { return "--" }
        if seconds >= 0.3 {
            return String(format: seconds >= 1 ? "%.0f\"" : "%.1f\"", seconds)
        }
        return "1/\(Int((1 / seconds).rounded()))"
    }

    static func iso(_ value: Double) -> String { "\(Int(value.rounded()))" }

    static func ev(_ value: Double) -> String {
        let v = (value * 10).rounded() / 10
        if v == 0 { return "±0.0" }
        return String(format: "%+.1f", v)
    }

    static func kelvin(_ value: Double) -> String { "\(Int((value / 50).rounded() * 50))K" }

    static func zoom(_ value: Double, withSuffix: Bool = true) -> String {
        let rounded = (value * 10).rounded() / 10
        let text = rounded == rounded.rounded() ? String(format: "%.0f", rounded) : String(format: "%.1f", rounded)
        return withSuffix ? text + "×" : text
    }

    static func focus(_ value: Double) -> String {
        if value >= 0.99 { return "∞" }
        return String(format: "%.2f", value)
    }

    static func timecode(_ seconds: Double, fps: Int) -> String {
        let total = max(0, seconds)
        let h = Int(total) / 3600
        let m = (Int(total) % 3600) / 60
        let s = Int(total) % 60
        let f = Int((total - total.rounded(.down)) * Double(max(fps, 1)))
        return String(format: "%02d:%02d:%02d:%02d", h, m, s, f)
    }

    static func duration(minutes: Double) -> String {
        guard minutes.isFinite, minutes > 0 else { return "--" }
        if minutes >= 60 {
            return String(format: "%dh %02dm", Int(minutes) / 60, Int(minutes) % 60)
        }
        return String(format: "%.0f min", minutes.rounded(.down))
    }

    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}
