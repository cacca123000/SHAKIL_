import CoreImage
import SwiftUI

private let assistPrefix = "assist."

enum GridStyle: String, CaseIterable, Identifiable {
    case off, thirds, golden, cross
    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .thirds: return "Terzi"
        case .golden: return "Aurea"
        case .cross: return "Centro"
        }
    }
}

enum FrameGuide: String, CaseIterable, Identifiable {
    case off, scope, flat, square, social, portrait
    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .scope: return "2.39:1"
        case .flat: return "1.85:1"
        case .square: return "1:1"
        case .social: return "4:5"
        case .portrait: return "9:16"
        }
    }

    /// Width / height of the guide in landscape terms (nil = off).
    var ratio: CGFloat? {
        switch self {
        case .off: return nil
        case .scope: return 2.39
        case .flat: return 1.85
        case .square: return 1
        case .social: return 4.0 / 5.0
        case .portrait: return 9.0 / 16.0
        }
    }
}

enum HistogramMode: String, CaseIterable, Identifiable {
    case off, luma, rgb
    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .luma: return "Luma"
        case .rgb: return "RGB"
        }
    }
}

enum PeakingColor: String, CaseIterable, Identifiable {
    case red, green, yellow, cyan
    var id: String { rawValue }

    var color: Color {
        switch self {
        case .red: return Color(red: 1, green: 0.2, blue: 0.2)
        case .green: return Color(red: 0.2, green: 1, blue: 0.3)
        case .yellow: return Color(red: 1, green: 0.9, blue: 0)
        case .cyan: return Color(red: 0.1, green: 0.9, blue: 1)
        }
    }

    var ciColor: CIColor {
        switch self {
        case .red: return CIColor(red: 1, green: 0.15, blue: 0.15)
        case .green: return CIColor(red: 0.2, green: 1, blue: 0.3)
        case .yellow: return CIColor(red: 1, green: 0.9, blue: 0)
        case .cyan: return CIColor(red: 0.1, green: 0.9, blue: 1)
        }
    }
}

/// Viewfinder tools ("assist"). Persisted in UserDefaults.
final class AssistSettings: ObservableObject {
    @Published var grid: GridStyle { didSet { store(grid.rawValue, "grid") } }
    @Published var showLevel: Bool { didSet { store(showLevel, "level") } }
    @Published var histogram: HistogramMode { didSet { store(histogram.rawValue, "histogram") } }
    @Published var peaking: Bool { didSet { store(peaking, "peaking") } }
    @Published var peakingColor: PeakingColor { didSet { store(peakingColor.rawValue, "peakingColor") } }
    @Published var zebra: Bool { didSet { store(zebra, "zebra") } }
    @Published var zebraThreshold: Double { didSet { store(zebraThreshold, "zebraThreshold") } }
    @Published var falseColor: Bool { didSet { store(falseColor, "falseColor") } }
    @Published var frameGuide: FrameGuide { didSet { store(frameGuide.rawValue, "frameGuide") } }
    @Published var logViewLUT: Bool { didSet { store(logViewLUT, "logViewLUT") } }
    @Published var look: LookPreset { didSet { store(look.rawValue, "look") } }
    @Published var showConsole: Bool { didSet { store(showConsole, "console") } }

    private let defaults = UserDefaults.standard

    init() {
        let d = UserDefaults.standard
        func string(_ key: String) -> String? { d.string(forKey: assistPrefix + key) }
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            d.object(forKey: assistPrefix + key) == nil ? fallback : d.bool(forKey: assistPrefix + key)
        }

        grid = string("grid").flatMap(GridStyle.init(rawValue:)) ?? .thirds
        showLevel = bool("level", true)
        histogram = string("histogram").flatMap(HistogramMode.init(rawValue:)) ?? .luma
        peaking = bool("peaking", false)
        peakingColor = string("peakingColor").flatMap(PeakingColor.init(rawValue:)) ?? .red
        zebra = bool("zebra", false)
        let zebraValue = d.double(forKey: assistPrefix + "zebraThreshold")
        zebraThreshold = zebraValue == 0 ? 0.95 : zebraValue
        falseColor = bool("falseColor", false)
        frameGuide = string("frameGuide").flatMap(FrameGuide.init(rawValue:)) ?? .off
        logViewLUT = bool("logViewLUT", true)
        look = string("look").flatMap(LookPreset.init(rawValue:)) ?? .natural
        showConsole = bool("console", true)
    }

    /// True when the viewfinder must be rendered through Core Image instead of the
    /// plain system preview layer.
    func needsProcessedPreview(profile: ColorProfile, mode: CaptureMode) -> Bool {
        peaking || zebra || falseColor || look != .natural
            || (mode == .video && profile == .appleLog && logViewLUT)
    }

    /// True when any tool needs raw video frames.
    func needsFrames(profile: ColorProfile, mode: CaptureMode) -> Bool {
        histogram != .off || needsProcessedPreview(profile: profile, mode: mode)
    }

    func resetAll() {
        grid = .thirds
        showLevel = true
        histogram = .luma
        peaking = false
        peakingColor = .red
        zebra = false
        zebraThreshold = 0.95
        falseColor = false
        frameGuide = .off
        logViewLUT = true
        look = .natural
        showConsole = true
    }

    private func store(_ value: Any, _ key: String) {
        defaults.set(value, forKey: assistPrefix + key)
    }
}
