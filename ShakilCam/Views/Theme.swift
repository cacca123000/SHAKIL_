import SwiftUI

/// Visual language: pure black, signal-yellow accent, monospaced readouts,
/// frosted glass panels and hairline borders.
enum Theme {
    static let accent = Color(red: 1.0, green: 0.80, blue: 0.04)
    static let rec = Color(red: 1.0, green: 0.23, blue: 0.19)
    static let ok = Color(red: 0.25, green: 0.88, blue: 0.45)
    static let cyan = Color(red: 0.30, green: 0.85, blue: 1.0)
    static let log = Color(red: 0.72, green: 0.52, blue: 1.0)

    static let panel = Color.white.opacity(0.07)
    static let panelStrong = Color.white.opacity(0.12)
    static let hairline = Color.white.opacity(0.14)
    static let secondaryText = Color.white.opacity(0.55)
    static let tertiaryText = Color.white.opacity(0.35)

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func profileColor(_ profile: ColorProfile) -> Color {
        switch profile {
        case .sdr: return .white
        case .hlg: return accent
        case .appleLog: return log
        }
    }
}

/// Frosted capsule used for small pills and badges.
struct GlassCapsule: ViewModifier {
    var highlighted = false

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(highlighted ? Theme.accent.opacity(0.8) : Theme.hairline, lineWidth: 0.6))
    }
}

struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 0.6)
            )
    }
}

extension View {
    func glassCapsule(highlighted: Bool = false) -> some View {
        modifier(GlassCapsule(highlighted: highlighted))
    }

    func glassPanel(cornerRadius: CGFloat = 18) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius))
    }

    /// Keeps icons upright when the phone is turned sideways.
    func uprightRotation(_ degrees: Double) -> some View {
        rotationEffect(.degrees(degrees))
    }
}

/// Round icon button with a glass background.
struct IconButton: View {
    let symbol: String
    var tint: Color = .white
    var active = false
    var size: CGFloat = 38
    var rotation: Double = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(active ? Color.black : tint)
                .frame(width: size, height: size)
                .background {
                    if active {
                        Circle().fill(Theme.accent)
                    } else {
                        Circle().fill(.ultraThinMaterial)
                    }
                }
                .overlay(Circle().strokeBorder(active ? Color.clear : Theme.hairline, lineWidth: 0.6))
                .uprightRotation(rotation)
        }
        .buttonStyle(PressableStyle())
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Small uppercase label + value badge, e.g. "ISO 400".
struct Badge: View {
    let text: String
    var color: Color = .white
    var filled = false

    var body: some View {
        Text(text)
            .font(Theme.mono(10, .bold))
            .foregroundStyle(filled ? Color.black : color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(filled ? color : color.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(color.opacity(filled ? 0 : 0.45), lineWidth: 0.6)
            )
    }
}
