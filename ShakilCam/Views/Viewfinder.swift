import SwiftUI

/// The live image plus every overlay drawn on top of it.
struct ViewfinderView: View {
    @EnvironmentObject private var camera: CameraController
    @EnvironmentObject private var assists: AssistSettings
    @EnvironmentObject private var motion: MotionManager

    var body: some View {
        ZStack {
            CameraPreview(camera: camera)

            Group {
                if assists.grid != .off {
                    GridOverlay(style: assists.grid)
                }
                if assists.frameGuide != .off {
                    FrameGuideOverlay(guide: assists.frameGuide, landscape: motion.isLandscape)
                }
                if assists.showLevel {
                    LevelOverlay()
                }
                if let indicator = camera.focusIndicator {
                    FocusReticle(indicator: indicator)
                        .id(indicator.id)
                }
            }
            .allowsHitTesting(false)

            overlaysLayer
                .allowsHitTesting(false)

            if camera.isRecording {
                RecordingFrame()
                    .allowsHitTesting(false)
            }

            if let countdown = camera.countdown {
                Text("\(countdown)")
                    .font(.system(size: 140, weight: .thin, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 20)
                    .uprightRotation(motion.iconRotation)
                    .id(countdown)
                    .transition(.scale(scale: 1.6).combined(with: .opacity))
                    .allowsHitTesting(false)
            }

            Color.black
                .opacity(camera.shutterBlink ? 0.85 : 0)
                .animation(.easeOut(duration: 0.12), value: camera.shutterBlink)
                .allowsHitTesting(false)

            if camera.isReconfiguring {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    ProgressView()
                        .tint(Theme.accent)
                }
                .transition(.opacity)
                .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: camera.countdown)
        .task(id: camera.focusIndicator?.id) {
            guard let indicator = camera.focusIndicator, !indicator.locked else { return }
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            await MainActor.run {
                if camera.focusIndicator?.id == indicator.id {
                    withAnimation(.easeOut(duration: 0.3)) { camera.focusIndicator = nil }
                }
            }
        }
    }

    /// Histogram, console, badges and legends.
    private var overlaysLayer: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                if assists.histogram != .off, camera.analysisAvailable {
                    HistogramView(mode: assists.histogram)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    ForEach(activeAssistBadges, id: \.self) { badge in
                        Badge(text: badge, color: badge.hasPrefix("LUT") ? Theme.log : Theme.accent)
                    }
                    if camera.aeAfLocked {
                        Badge(text: "AE/AF LOCK", color: Theme.accent, filled: true)
                    }
                    if !camera.analysisAvailable, assistsWanted {
                        Badge(text: "ASSIST OFF · PRORES", color: Theme.secondaryText)
                    }
                }
            }
            .padding(10)
            .padding(.top, camera.settings.mode == .video ? 92 : 0)

            Spacer()

            HStack(alignment: .bottom) {
                if assists.showConsole {
                    ConsoleOverlay()
                }
                Spacer()
                if assists.falseColor, camera.analysisAvailable {
                    FalseColorLegend()
                }
            }
            .padding(10)
            .padding(.bottom, camera.settings.mode == .video ? 250 : 64)
        }
    }

    private var assistsWanted: Bool {
        assists.peaking || assists.zebra || assists.falseColor || assists.histogram != .off
    }

    private var activeAssistBadges: [String] {
        guard camera.analysisAvailable else { return [] }
        var items: [String] = []
        if camera.settings.mode == .video, camera.settings.profile == .appleLog, assists.logViewLUT {
            items.append("LUT 709")
        }
        if assists.look != .natural { items.append(assists.look.title.uppercased()) }
        if assists.peaking { items.append("PEAKING") }
        if assists.zebra { items.append("ZEBRA \(Int(assists.zebraThreshold * 100))%") }
        if assists.falseColor { items.append("FALSI COLORI") }
        return items
    }
}

struct CameraPreview: UIViewRepresentable {
    let camera: CameraController

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        camera.attach(previewView: view)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

// MARK: - Grid

struct GridOverlay: View {
    let style: GridStyle

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { path in
                func vertical(_ x: CGFloat) {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: h))
                }
                func horizontal(_ y: CGFloat) {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: w, y: y))
                }
                switch style {
                case .off:
                    break
                case .thirds:
                    for f: CGFloat in [1.0 / 3.0, 2.0 / 3.0] {
                        vertical(w * f)
                        horizontal(h * f)
                    }
                case .golden:
                    for f: CGFloat in [0.382, 0.618] {
                        vertical(w * f)
                        horizontal(h * f)
                    }
                case .cross:
                    let c = CGPoint(x: w / 2, y: h / 2)
                    path.move(to: CGPoint(x: c.x - 18, y: c.y))
                    path.addLine(to: CGPoint(x: c.x + 18, y: c.y))
                    path.move(to: CGPoint(x: c.x, y: c.y - 18))
                    path.addLine(to: CGPoint(x: c.x, y: c.y + 18))
                    for f: CGFloat in [1.0 / 3.0, 2.0 / 3.0] {
                        vertical(w * f)
                        horizontal(h * f)
                    }
                }
            }
            .stroke(Color.white.opacity(0.32), lineWidth: 0.6)
        }
    }
}

// MARK: - Frame guides

struct FrameGuideOverlay: View {
    let guide: FrameGuide
    let landscape: Bool

    var body: some View {
        GeometryReader { geo in
            if let ratio = guide.ratio {
                let size = geo.size
                let r = landscape ? 1 / ratio : ratio
                let rect = fit(r, in: size)
                ZStack {
                    Path { path in
                        path.addRect(CGRect(origin: .zero, size: size))
                        path.addRect(rect)
                    }
                    .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))

                    Rectangle()
                        .strokeBorder(Theme.accent.opacity(0.75), lineWidth: 1)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)

                    Text(guide.title)
                        .font(Theme.mono(9, .bold))
                        .foregroundStyle(Theme.accent)
                        .padding(4)
                        .position(x: rect.minX + 24, y: rect.minY + 12)
                }
            }
        }
    }

    private func fit(_ ratio: CGFloat, in size: CGSize) -> CGRect {
        var w = size.width
        var h = w / ratio
        if h > size.height {
            h = size.height
            w = h * ratio
        }
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }
}

// MARK: - Level

struct LevelOverlay: View {
    @EnvironmentObject private var motion: MotionManager
    @EnvironmentObject private var horizon: LevelModel

    var body: some View {
        let level = horizon.isLevel
        let color = level ? Theme.accent : Color.white.opacity(0.85)
        ZStack {
            // Fixed reference marks for the current orientation.
            HStack(spacing: 150) {
                Capsule().frame(width: 18, height: 1.5)
                Capsule().frame(width: 18, height: 1.5)
            }
            .foregroundStyle(color.opacity(0.7))
            .rotationEffect(.degrees(motion.iconRotation))

            // Horizon line that follows gravity.
            HStack(spacing: 8) {
                Capsule().frame(width: 52, height: 1.5)
                Circle().stroke(lineWidth: 1.5).frame(width: 8, height: 8)
                Capsule().frame(width: 52, height: 1.5)
            }
            .foregroundStyle(color)
            .rotationEffect(.degrees(level ? motion.iconRotation : -horizon.gravityAngle))

            if !level && !horizon.isFlat {
                Text(String(format: "%.1f°", abs(horizon.tilt)))
                    .font(Theme.mono(10, .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .offset(y: 18)
                    .rotationEffect(.degrees(motion.iconRotation))
            }
        }
        .opacity(horizon.isFlat ? 0 : 1)
        .animation(.easeOut(duration: 0.2), value: level)
    }
}

// MARK: - Focus reticle

struct FocusReticle: View {
    let indicator: FocusIndicator
    @State private var appeared = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(Theme.accent, lineWidth: 1.2)
                .frame(width: 74, height: 74)
            // Edge ticks
            ForEach(0..<4) { i in
                Rectangle()
                    .fill(Theme.accent)
                    .frame(width: 1.2, height: 7)
                    .offset(y: -33.5)
                    .rotationEffect(.degrees(Double(i) * 90))
            }
            if indicator.locked {
                Text("BLOCCO AE/AF")
                    .font(Theme.mono(9, .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 3))
                    .offset(y: -52)
            }
        }
        .scaleEffect(appeared ? 1 : 1.45)
        .opacity(appeared ? 1 : 0)
        .position(indicator.point)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) { appeared = true }
        }
    }
}

// MARK: - Histogram

struct HistogramView: View {
    @EnvironmentObject private var model: HistogramModel
    let mode: HistogramMode

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Canvas { context, size in
                guard let h = model.value else { return }
                // Quarter lines
                for f: CGFloat in [0.25, 0.5, 0.75] {
                    var line = Path()
                    line.move(to: CGPoint(x: size.width * f, y: 0))
                    line.addLine(to: CGPoint(x: size.width * f, y: size.height))
                    context.stroke(line, with: .color(.white.opacity(0.12)), lineWidth: 0.5)
                }
                switch mode {
                case .off:
                    break
                case .luma:
                    context.fill(area(h.luma, size), with: .color(.white.opacity(0.85)))
                case .rgb:
                    context.blendMode = .plusLighter
                    context.fill(area(h.red, size), with: .color(Color(red: 1, green: 0.2, blue: 0.2).opacity(0.75)))
                    context.fill(area(h.green, size), with: .color(Color(red: 0.2, green: 1, blue: 0.3).opacity(0.75)))
                    context.fill(area(h.blue, size), with: .color(Color(red: 0.25, green: 0.45, blue: 1).opacity(0.75)))
                }
            }
            .frame(width: 132, height: 54)
            .padding(6)

            if let h = model.value {
                HStack(spacing: 3) {
                    if h.clippedShadows > 0.02 { Circle().fill(Theme.cyan).frame(width: 5, height: 5) }
                    if h.clippedHighlights > 0.01 { Circle().fill(Theme.rec).frame(width: 5, height: 5) }
                }
                .padding(5)
            }
        }
        .background(Color.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
    }

    private func area(_ values: [Float], _ size: CGSize) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        path.move(to: CGPoint(x: 0, y: size.height))
        for (i, v) in values.enumerated() {
            let x = size.width * CGFloat(i) / CGFloat(values.count - 1)
            let y = size.height * (1 - CGFloat(v))
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        return path
    }
}

// MARK: - Console

struct ConsoleOverlay: View {
    @EnvironmentObject private var log: CameraLog

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle().fill(Theme.ok).frame(width: 5, height: 5)
                Text("LIVE LOG")
                    .font(Theme.mono(8, .bold))
                    .foregroundStyle(Theme.ok)
            }
            .padding(.bottom, 1)
            ForEach(log.entries.suffix(5)) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(entry.level.tag)
                        .font(Theme.mono(8, .bold))
                        .foregroundStyle(entry.level.color)
                    Text(entry.message)
                        .font(Theme.mono(9))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(8)
        .frame(maxWidth: 250, alignment: .leading)
        .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
        .animation(.easeOut(duration: 0.2), value: log.entries.last?.id)
    }
}

// MARK: - False color key

struct FalseColorLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(ColorCubes.falseColorLegend) { item in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(red: item.red, green: item.green, blue: item.blue))
                        .frame(width: 10, height: 10)
                    Text(item.label)
                        .font(Theme.mono(8, .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .padding(7)
        .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Recording frame

struct RecordingFrame: View {
    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .strokeBorder(Theme.rec.opacity(pulse ? 0.9 : 0.45), lineWidth: 2)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
            }
    }
}
