import SwiftUI

struct CameraScreen: View {
    @EnvironmentObject private var camera: CameraController
    @State private var activeControl: ProControl?
    @State private var showSettings = false
    @State private var showAssists = false
    @State private var showGallery = false

    var body: some View {
        GeometryReader { geo in
            let isPhoto = camera.settings.mode == .photo
            let width = geo.size.width
            let previewHeight = min(width / (isPhoto ? 3.0 / 4.0 : 9.0 / 16.0), geo.size.height)

            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()

                ViewfinderView()
                    .frame(width: width, height: previewHeight)
                    .clipShape(RoundedRectangle(cornerRadius: isPhoto ? 6 : 0, style: .continuous))
                    .padding(.top, isPhoto ? 64 : 0)
                    .animation(.spring(response: 0.45, dampingFraction: 0.85), value: isPhoto)

                VStack(spacing: 0) {
                    TopBar(showSettings: $showSettings, showAssists: $showAssists)
                        .background(alignment: .top) {
                            LinearGradient(colors: [.black.opacity(isPhoto ? 1 : 0.6), .clear],
                                           startPoint: .top, endPoint: .bottom)
                                .frame(height: 150)
                                .ignoresSafeArea()
                                .allowsHitTesting(false)
                        }
                    Spacer(minLength: 0)
                    BottomControls(activeControl: $activeControl, showGallery: $showGallery)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAssists) {
            AssistSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .fullScreenCover(isPresented: $showGallery) {
            GalleryView()
        }
        .onChange(of: camera.settings.mode) { _, _ in
            withAnimation { activeControl = nil }
        }
    }
}

// MARK: - Top bar

struct TopBar: View {
    @EnvironmentObject private var camera: CameraController
    @EnvironmentObject private var telemetry: CameraTelemetry
    @EnvironmentObject private var assists: AssistSettings
    @EnvironmentObject private var motion: MotionManager
    @Binding var showSettings: Bool
    @Binding var showAssists: Bool

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                leftControls
                Spacer(minLength: 4)
                centerStatus
                Spacer(minLength: 4)
                IconButton(symbol: "camera.filters", active: assistsActive, rotation: motion.iconRotation) {
                    Haptics.light()
                    showAssists = true
                }
                IconButton(symbol: "gearshape.fill", rotation: motion.iconRotation) {
                    Haptics.light()
                    showSettings = true
                }
                .disabled(camera.isRecording)
            }
            TelemetryStrip()
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
    }

    private var assistsActive: Bool {
        assists.peaking || assists.zebra || assists.falseColor || assists.look != .natural || assists.frameGuide != .off
    }

    @ViewBuilder
    private var leftControls: some View {
        HStack(spacing: 8) {
            if camera.settings.mode == .photo {
                if camera.capabilities.hasFlash {
                    IconButton(symbol: camera.settings.flash.symbol,
                               tint: camera.settings.flash == .off ? .white : Theme.accent,
                               rotation: motion.iconRotation) {
                        Haptics.light()
                        let next = camera.settings.flash.next
                        camera.update { $0.flash = next }
                        camLog("Flash: \(next.rawValue.uppercased())")
                    }
                }
                IconButton(symbol: camera.settings.timer == .off ? "timer" : "timer.circle.fill",
                           tint: camera.settings.timer == .off ? .white : Theme.accent,
                           rotation: motion.iconRotation) {
                    Haptics.light()
                    let next = camera.settings.timer.next
                    camera.update { $0.timer = next }
                    camLog("Autoscatto: \(next.title)")
                }
                .overlay(alignment: .bottomTrailing) {
                    if camera.settings.timer != .off {
                        Text("\(camera.settings.timer.rawValue)")
                            .font(Theme.mono(8, .heavy))
                            .foregroundStyle(.black)
                            .padding(2)
                            .background(Circle().fill(Theme.accent))
                            .offset(x: 2, y: 2)
                    }
                }
            } else {
                if camera.capabilities.hasTorch {
                    IconButton(symbol: camera.torchOn ? "flashlight.on.fill" : "flashlight.off.fill",
                               active: camera.torchOn, rotation: motion.iconRotation) {
                        Haptics.light()
                        camera.toggleTorch()
                    }
                }
                AudioMeter(level: telemetry.audioLevel, peak: telemetry.audioPeak, enabled: camera.settings.audioEnabled)
            }
        }
    }

    @ViewBuilder
    private var centerStatus: some View {
        if camera.isRecording {
            HStack(spacing: 6) {
                BlinkingDot()
                Text(Format.timecode(telemetry.recordedSeconds, fps: camera.settings.fps))
                    .font(Theme.mono(15, .bold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(Theme.rec.opacity(0.9)))
        } else {
            Button {
                Haptics.light()
                showSettings = true
            } label: {
                HStack(spacing: 5) {
                    ForEach(statusItems, id: \.text) { item in
                        Text(item.text)
                            .font(Theme.mono(11, .bold))
                            .foregroundStyle(item.color)
                        if item.text != statusItems.last?.text {
                            Circle().fill(Theme.tertiaryText).frame(width: 2.5, height: 2.5)
                        }
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .glassCapsule()
            }
            .buttonStyle(PressableStyle())
        }
    }

    private struct StatusItem {
        let text: String
        let color: Color
    }

    private var statusItems: [StatusItem] {
        let s = camera.settings
        switch s.mode {
        case .photo:
            var format = s.photoFormat.title
            if s.photoFormat == .raw { format = "RAW+HEIF" }
            return [
                StatusItem(text: format, color: s.photoFormat.isRAW ? Theme.accent : .white),
                StatusItem(text: "\(camera.photoMegapixels)MP", color: .white),
                StatusItem(text: "P3", color: Theme.secondaryText),
            ]
        case .video:
            return [
                StatusItem(text: s.resolution.title, color: .white),
                StatusItem(text: "\(s.fps)", color: s.fps >= 100 ? Theme.accent : .white),
                StatusItem(text: (camera.activeCodec ?? s.codec).title, color: camera.activeCodec == .proRes ? Theme.accent : .white),
                StatusItem(text: s.profile.title, color: Theme.profileColor(s.profile)),
            ]
        }
    }
}

/// Battery, storage, temperature and lens info.
struct TelemetryStrip: View {
    @EnvironmentObject private var camera: CameraController
    @EnvironmentObject private var telemetry: CameraTelemetry

    var body: some View {
        HStack(spacing: 10) {
            item(symbol: batterySymbol, text: "\(Int((telemetry.batteryLevel * 100).rounded()))%",
                 color: telemetry.batteryLevel < 0.2 && !telemetry.batteryCharging ? Theme.rec : .white)

            if camera.settings.mode == .video {
                item(symbol: "internaldrive", text: Format.duration(minutes: camera.estimatedMinutesLeft(freeBytes: telemetry.freeBytes)))
            } else {
                item(symbol: "internaldrive", text: Format.bytes(telemetry.freeBytes))
            }

            if telemetry.thermal == .serious || telemetry.thermal == .critical {
                item(symbol: "thermometer.high", text: telemetry.thermal == .critical ? "CRITICO" : "CALDO", color: Theme.rec)
            }

            Spacer()

            if let lens = camera.currentLens {
                Text(lens.kind.name.uppercased())
                    .font(Theme.rounded(8.5, .heavy))
                    .tracking(0.8)
                    .foregroundStyle(Theme.tertiaryText)
            }
            if camera.settings.mode == .video, camera.settings.stabilization != .off {
                item(symbol: "hand.raised.fingers.spread", text: camera.settings.stabilization.title.uppercased())
            }
        }
        .padding(.horizontal, 4)
    }

    private var batterySymbol: String {
        if telemetry.batteryCharging { return "battery.100.bolt" }
        switch telemetry.batteryLevel {
        case ..<0.15: return "battery.0"
        case ..<0.4: return "battery.25"
        case ..<0.65: return "battery.50"
        case ..<0.9: return "battery.75"
        default: return "battery.100"
        }
    }

    private func item(symbol: String, text: String, color: Color = .white) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 9.5, weight: .semibold))
            Text(text)
                .font(Theme.mono(9.5, .semibold))
        }
        .foregroundStyle(color.opacity(0.8))
    }
}

struct AudioMeter: View {
    let level: Double
    let peak: Double
    let enabled: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: enabled ? "mic.fill" : "mic.slash.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(enabled ? Color.white : Theme.rec)
            if enabled {
                VStack(spacing: 2) {
                    bar(level)
                    bar(peak)
                }
                .frame(width: 44)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 38)
        .glassCapsule()
    }

    private func bar(_ value: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                Capsule()
                    .fill(LinearGradient(colors: [Theme.ok, Theme.accent, Theme.rec],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * value)
                    .animation(.linear(duration: 0.1), value: value)
            }
        }
        .frame(height: 3)
    }
}

struct BlinkingDot: View {
    @State private var on = true

    var body: some View {
        Circle()
            .fill(.white)
            .frame(width: 8, height: 8)
            .opacity(on ? 1 : 0.2)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { on = false }
            }
    }
}

// MARK: - Bottom controls

struct BottomControls: View {
    @EnvironmentObject private var camera: CameraController
    @EnvironmentObject private var telemetry: CameraTelemetry
    @EnvironmentObject private var motion: MotionManager
    @Binding var activeControl: ProControl?
    @Binding var showGallery: Bool

    var body: some View {
        VStack(spacing: 10) {
            if let control = activeControl {
                DialPanel(control: control) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { activeControl = nil }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if camera.currentLens?.kind != .front, camera.lenses.filter({ $0.kind != .front }).count > 1 {
                LensSelector()
            }

            ProChipsRow(active: $activeControl)

            ModePicker()

            HStack {
                GalleryThumbnail(onTap: { showGallery = true })
                    .uprightRotation(motion.iconRotation)
                Spacer()
                ShutterButton(
                    mode: camera.settings.mode,
                    isRecording: camera.isRecording,
                    countdownActive: camera.countdown != nil
                ) {
                    camera.shutterPressed()
                }
                Spacer()
                IconButton(symbol: "arrow.triangle.2.circlepath", size: 50, rotation: motion.iconRotation) {
                    Haptics.light()
                    camera.flipCamera()
                }
                .disabled(camera.isRecording || !camera.lenses.contains { $0.kind == .front })
                .opacity(camera.isRecording ? 0.35 : 1)
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 6)
        }
        .padding(.top, 14)
        .background(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.75), .black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

struct LensSelector: View {
    @EnvironmentObject private var camera: CameraController
    @EnvironmentObject private var telemetry: CameraTelemetry
    @EnvironmentObject private var motion: MotionManager

    var body: some View {
        HStack(spacing: 4) {
            ForEach(camera.lenses.filter { $0.kind != .front }) { lens in
                let selected = lens == camera.currentLens
                Button {
                    Haptics.light()
                    if selected {
                        camera.setZoom(1, animated: true)
                    } else {
                        camera.selectLens(lens)
                    }
                } label: {
                    Text(selected ? Format.zoom(lens.magnification * telemetry.zoom) : lens.shortTitle)
                        .font(Theme.mono(selected ? 12 : 11, .bold))
                        .foregroundStyle(selected ? Theme.accent : .white)
                        .frame(width: selected ? 44 : 34, height: selected ? 44 : 34)
                        .background(Circle().fill(Color.black.opacity(selected ? 0.6 : 0.4)))
                        .uprightRotation(motion.iconRotation)
                }
                .buttonStyle(PressableStyle())
                .disabled(camera.isRecording)
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.black.opacity(0.35)))
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.5))
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: camera.currentLens?.id)
    }
}

struct ModePicker: View {
    @EnvironmentObject private var camera: CameraController

    var body: some View {
        HStack(spacing: 30) {
            ForEach(CaptureMode.allCases) { mode in
                let selected = camera.settings.mode == mode
                Button {
                    Haptics.selection()
                    camera.setMode(mode)
                } label: {
                    VStack(spacing: 4) {
                        Text(mode.title)
                            .font(Theme.rounded(13, .heavy))
                            .tracking(2)
                            .foregroundStyle(selected ? Theme.accent : .white.opacity(0.55))
                        Circle()
                            .fill(selected ? Theme.accent : .clear)
                            .frame(width: 4, height: 4)
                    }
                }
                .buttonStyle(.plain)
                .disabled(camera.isRecording)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    guard !camera.isRecording else { return }
                    if value.translation.width < -30 { camera.setMode(.video) }
                    if value.translation.width > 30 { camera.setMode(.photo) }
                }
        )
        .animation(.easeOut(duration: 0.2), value: camera.settings.mode)
    }
}

struct ShutterButton: View {
    let mode: CaptureMode
    let isRecording: Bool
    let countdownActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(Color.white, lineWidth: 4)
                    .frame(width: 80, height: 80)
                if mode == .photo {
                    Circle()
                        .fill(countdownActive ? Theme.accent : Color.white)
                        .frame(width: 66, height: 66)
                    if countdownActive {
                        Image(systemName: "xmark")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.black)
                    }
                } else {
                    RoundedRectangle(cornerRadius: isRecording ? 8 : 33, style: .continuous)
                        .fill(Theme.rec)
                        .frame(width: isRecording ? 32 : 66, height: isRecording ? 32 : 66)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isRecording)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: mode)
        }
        .buttonStyle(ShutterPressStyle())
        .accessibilityLabel(mode == .photo ? "Scatta foto" : (isRecording ? "Ferma registrazione" : "Avvia registrazione"))
    }
}

struct ShutterPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct GalleryThumbnail: View {
    @EnvironmentObject private var camera: CameraController
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.panel)
                if let thumbnail = camera.captures.first?.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .id(camera.captures.first?.id)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(width: 50, height: 50)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if !camera.captures.isEmpty {
                    Text("\(camera.captures.count)")
                        .font(Theme.mono(9, .heavy))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Theme.accent))
                        .offset(x: 6, y: -6)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: camera.captures.first?.id)
        }
        .buttonStyle(PressableStyle())
    }
}
