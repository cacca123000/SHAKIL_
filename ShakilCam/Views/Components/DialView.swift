import SwiftUI

/// Horizontal ruler you scrub with a finger, like a lens ring. Snaps to discrete
/// stops with a haptic tick on each one.
struct DialView: View {
    let values: [Double]
    let selectedIndex: Int
    var majorEvery: Int = 3
    var tint: Color = Theme.accent
    let label: (Double) -> String
    let onChange: (Int) -> Void

    @State private var dragStart: CGFloat?
    @State private var livePosition: CGFloat?
    @State private var lastEmitted: Int?

    private let spacing: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let mid = geo.size.width / 2
            Canvas { context, size in
                guard !values.isEmpty else { return }
                let position = livePosition ?? CGFloat(selectedIndex)
                let visible = Int(size.width / spacing / 2) + 2
                let low = max(0, Int(position) - visible)
                let high = min(values.count - 1, Int(position) + visible)
                guard low <= high else { return }

                for i in low...high {
                    let x = mid + (CGFloat(i) - position) * spacing
                    let isMajor = i % majorEvery == 0 || i == values.count - 1
                    let fade = max(0.12, 1 - abs(x - mid) / mid)
                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: 6))
                    tick.addLine(to: CGPoint(x: x, y: isMajor ? 24 : 15))
                    context.stroke(
                        tick,
                        with: .color(.white.opacity(Double(fade) * (isMajor ? 0.95 : 0.45))),
                        lineWidth: isMajor ? 1.4 : 1
                    )
                    if isMajor {
                        context.draw(
                            Text(label(values[i]))
                                .font(Theme.mono(9, .medium))
                                .foregroundStyle(Color.white.opacity(Double(fade) * 0.85)),
                            at: CGPoint(x: x, y: 36)
                        )
                    }
                }
            }
            .overlay(alignment: .top) {
                // Center index
                VStack(spacing: 0) {
                    Triangle()
                        .fill(tint)
                        .frame(width: 9, height: 6)
                    Rectangle()
                        .fill(tint)
                        .frame(width: 2, height: 22)
                }
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.18),
                        .init(color: .black, location: 0.82),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStart == nil {
                            dragStart = CGFloat(selectedIndex)
                            lastEmitted = selectedIndex
                        }
                        let start = dragStart ?? CGFloat(selectedIndex)
                        let raw = start - value.translation.width / spacing
                        let clamped = min(max(raw, 0), CGFloat(max(values.count - 1, 0)))
                        livePosition = clamped
                        let index = Int(clamped.rounded())
                        if index != lastEmitted {
                            lastEmitted = index
                            Haptics.selection()
                            onChange(index)
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            livePosition = nil
                        }
                        dragStart = nil
                        lastEmitted = nil
                    }
            )
        }
        .frame(height: 46)
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
