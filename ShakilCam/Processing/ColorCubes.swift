import CoreImage
import Foundation
import simd

/// Creative looks. Shown live in the viewfinder and baked into HEIF/JPEG photos.
enum LookPreset: String, CaseIterable, Identifiable {
    case natural, tealOrange, warmFilm, noir, bleach, cool

    var id: String { rawValue }

    var title: String {
        switch self {
        case .natural: return "Naturale"
        case .tealOrange: return "Teal & Orange"
        case .warmFilm: return "Pellicola"
        case .noir: return "Noir"
        case .bleach: return "Bleach"
        case .cool: return "Notte Blu"
        }
    }

    var subtitle: String {
        switch self {
        case .natural: return "Nessun filtro"
        case .tealOrange: return "Look blockbuster: ombre fredde, pelle calda"
        case .warmFilm: return "Toni caldi e neri morbidi"
        case .noir: return "Bianco e nero ad alto contrasto"
        case .bleach: return "Desaturato e contrastato"
        case .cool: return "Atmosfera fredda notturna"
        }
    }
}

/// Generates 3D LUTs in code so the app ships without any external .cube file.
enum ColorCubes {
    static let size = 33

    /// Apple Log (BT.2020) → Rec.709 display LUT used as a monitoring "view assist".
    static let appleLogToRec709: Data = makeCube { rgb in
        var linear = SIMD3<Float>(appleLogToLinear(rgb.x), appleLogToLinear(rgb.y), appleLogToLinear(rgb.z))
        linear = bt2020ToBt709 * linear
        linear = simd_max(linear, SIMD3<Float>(repeating: 0))
        let toned = SIMD3<Float>(filmic(linear.x * 0.8), filmic(linear.y * 0.8), filmic(linear.z * 0.8))
        return SIMD3<Float>(srgbEncode(toned.x), srgbEncode(toned.y), srgbEncode(toned.z))
    }

    private static var lookCache: [LookPreset: Data] = [:]
    private static let lock = NSLock()

    static func cube(for look: LookPreset) -> Data? {
        guard look != .natural else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let cached = lookCache[look] { return cached }
        let data = makeCube { lookTransform(look, $0) }
        lookCache[look] = data
        return data
    }

    // MARK: - Looks (operate on display-referred, gamma encoded values)

    private static func lookTransform(_ look: LookPreset, _ c: SIMD3<Float>) -> SIMD3<Float> {
        let luma = simd_dot(c, SIMD3<Float>(0.2126, 0.7152, 0.0722))
        switch look {
        case .natural:
            return c
        case .tealOrange:
            let shadowTint = SIMD3<Float>(-0.04, 0.03, 0.08) * (1 - luma)
            let highlightTint = SIMD3<Float>(0.07, 0.02, -0.06) * luma
            var out = c + shadowTint + highlightTint
            out = mix(SIMD3<Float>(repeating: luma), out, t: 1.15)
            return sCurve(out, amount: 0.25)
        case .warmFilm:
            var out = c * SIMD3<Float>(1.06, 1.0, 0.9)
            out = out * 0.92 + 0.05 // lifted blacks, softer whites
            out = mix(SIMD3<Float>(repeating: luma), out, t: 0.9)
            return sCurve(out, amount: 0.15)
        case .noir:
            let bw = SIMD3<Float>(repeating: simd_dot(c, SIMD3<Float>(0.3, 0.6, 0.1)))
            return sCurve(bw, amount: 0.6)
        case .bleach:
            let desat = mix(SIMD3<Float>(repeating: luma), c, t: 0.45)
            return sCurve(desat, amount: 0.5)
        case .cool:
            var out = c * SIMD3<Float>(0.88, 0.97, 1.12)
            out = mix(SIMD3<Float>(repeating: luma), out, t: 0.85)
            return sCurve(out * 0.95, amount: 0.2)
        }
    }

    private static func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        a + (b - a) * t
    }

    private static func sCurve(_ c: SIMD3<Float>, amount: Float) -> SIMD3<Float> {
        func curve(_ x: Float) -> Float {
            let x = min(max(x, 0), 1)
            let s = x * x * (3 - 2 * x) // smoothstep
            return x + (s - x) * amount
        }
        return SIMD3<Float>(curve(c.x), curve(c.y), curve(c.z))
    }

    // MARK: - Apple Log math (from Apple's "Apple Log Profile" white paper)

    private static let r0: Float = -0.05641088
    private static let rt: Float = 0.01
    private static let c: Float = 47.28711236
    private static let beta: Float = 0.00964052
    private static let gamma: Float = 0.08550479
    private static let delta: Float = 0.69336945

    private static func appleLogToLinear(_ p: Float) -> Float {
        let pt = c * (rt - r0) * (rt - r0)
        if p < 0 { return r0 }
        if p < pt { return (p / c).squareRoot() + r0 }
        return pow(2, (p - delta) / gamma) - beta
    }

    private static let bt2020ToBt709 = simd_float3x3(rows: [
        SIMD3<Float>(1.6605, -0.5876, -0.0728),
        SIMD3<Float>(-0.1246, 1.1329, -0.0083),
        SIMD3<Float>(-0.0182, -0.1006, 1.1187),
    ])

    /// ACES filmic approximation (Narkowicz).
    private static func filmic(_ x: Float) -> Float {
        let a: Float = 2.51, b: Float = 0.03, c: Float = 2.43, d: Float = 0.59, e: Float = 0.14
        return min(max((x * (a * x + b)) / (x * (c * x + d) + e), 0), 1)
    }

    private static func srgbEncode(_ x: Float) -> Float {
        let x = min(max(x, 0), 1)
        return x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055
    }

    // MARK: - Cube builder

    private static func makeCube(_ transform: (SIMD3<Float>) -> SIMD3<Float>) -> Data {
        let n = size
        var values = [Float](repeating: 0, count: n * n * n * 4)
        var i = 0
        let scale = 1 / Float(n - 1)
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    let input = SIMD3<Float>(Float(r), Float(g), Float(b)) * scale
                    let out = transform(input)
                    values[i] = min(max(out.x, 0), 1)
                    values[i + 1] = min(max(out.y, 0), 1)
                    values[i + 2] = min(max(out.z, 0), 1)
                    values[i + 3] = 1
                    i += 4
                }
            }
        }
        return values.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    // MARK: - False color

    /// 256×1 gradient used with CIColorMap: maps luminance (IRE) to warning colors.
    static let falseColorGradient: CIImage = {
        var bytes = [UInt8](repeating: 255, count: 256 * 4)
        for i in 0..<256 {
            let ire = Double(i) / 255 * 100
            let gray = UInt8(Double(i) * 0.75)
            let rgb: (UInt8, UInt8, UInt8)
            switch ire {
            case ..<2.5: rgb = (128, 0, 200) // crushed blacks: purple
            case ..<10: rgb = (20, 70, 255) // near black: blue
            case 38..<44: rgb = (40, 210, 60) // 18% gray: green
            case 52..<58: rgb = (255, 120, 180) // skin tones: pink
            case 90..<97: rgb = (255, 225, 0) // near clipping: yellow
            case 97...: rgb = (255, 30, 30) // clipped: red
            default: rgb = (gray, gray, gray)
            }
            bytes[i * 4] = rgb.0
            bytes[i * 4 + 1] = rgb.1
            bytes[i * 4 + 2] = rgb.2
            bytes[i * 4 + 3] = 255
        }
        return CIImage(
            bitmapData: Data(bytes),
            bytesPerRow: 256 * 4,
            size: CGSize(width: 256, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )
    }()

    struct LegendItem: Identifiable {
        let label: String
        let red: Double
        let green: Double
        let blue: Double
        var id: String { label }
    }

    /// Legend entries for the false color key shown on screen.
    static let falseColorLegend: [LegendItem] = [
        LegendItem(label: "Clip", red: 1, green: 0.12, blue: 0.12),
        LegendItem(label: "Alte", red: 1, green: 0.88, blue: 0),
        LegendItem(label: "Pelle", red: 1, green: 0.47, blue: 0.7),
        LegendItem(label: "18%", red: 0.16, green: 0.82, blue: 0.24),
        LegendItem(label: "Basse", red: 0.08, green: 0.27, blue: 1),
        LegendItem(label: "Nero", red: 0.5, green: 0, blue: 0.78),
    ]
}
