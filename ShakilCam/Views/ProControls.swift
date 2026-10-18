import SwiftUI

/// The manual controls shown as chips above the shutter.
enum ProControl: String, CaseIterable, Identifiable {
    case ev, iso, shutter, whiteBalance, focus, zoom
    var id: String { rawValue }

    var chipTitle: String {
        switch self {
        case .ev: return "EV"
        case .iso: return "ISO"
        case .shutter: return "SHUTTER"
        case .whiteBalance: return "WB"
        case .focus: return "FOCUS"
        case .zoom: return "ZOOM"
        }
    }

    var title: String {
        switch self {
        case .ev: return "Compensazione esposizione"
        case .iso: return "ISO · Sensibilità"
        case .shutter: return "Tempo di scatto"
        case .whiteBalance: return "Bilanciamento del bianco"
        case .focus: return "Messa a fuoco manuale"
        case .zoom: return "Zoom"
        }
    }

    var help: String {
        switch self {
        case .ev: return "Rende l'immagine più chiara (+) o più scura (−) lasciando l'automatico al lavoro."
        case .iso: return "Più alto = più luce ma più rumore. Tienilo basso quando puoi."
        case .shutter: return "Veloce congela il movimento, lento crea scie. Nei video: 2× i fps (regola dei 180°)."
        case .whiteBalance: return "Kelvin bassi = immagine più fredda, alti = più calda. Scegli un preset o scorri."
        case .focus: return "Scorri per mettere a fuoco a mano. Attiva il peaking per vedere cosa è nitido."
        case .zoom: return "Zoom digitale sull'obiettivo attivo. Usa i pulsanti .5 / 1 / 3 per cambiare obiettivo."
        }
    }

    var symbol: String {
        switch self {
        case .ev: return "plusminus.circle"
        case .iso: return "camera.aperture"
        case .shutter: return "timer"
        case .whiteBalance: return "thermometer.sun"
        case .focus: return "scope"
        case .zoom: return "plus.magnifyingglass"
        }
    }
}

// MARK: - Chips row

struct ProChipsRow: View {
    @EnvironmentObject private var camera: CameraController
    @EnvironmentObject private var telemetry: CameraTelemetry
    @Binding var active: ProControl?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(ProControl.allCases) { control in
                    ProChip(
                        title: control.chipTitle,
                        value: value(for: control),
                        isManual: isManual(control),
                        isSelected: active == control,
                        isAvailable: isAvailable(control)
                    ) {
                        Haptics.light()
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            active = active == control ? nil : control
                        }
                    }
                }
                Button {
                    Haptics.medium()
                    camera.resetManualControls()
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 13, weight: .bold))
                        Text("AUTO")
                            .font(Theme.rounded(8, .heavy))
                    }
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 46, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.panel))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.6))
                }
                .buttonStyle(PressableStyle())
            }
            .padding(.horizontal, 14)
        }
    }

    private func value(for control: ProControl) -> String {
        switch control {
        case .ev:
            return Format.ev(telemetry.exposureBias)
        case .iso:
            return Format.iso(camera.exposureManual ? camera.manualISO : telemetry.iso)
        case .shutter:
            return Format.shutter(camera.exposureManual ? camera.manualShutter : telemetry.shutter)
        case .whiteBalance:
            return Format.kelvin(camera.whiteBalanceManual ? camera.manualTemperature : telemetry.temperature)
        case .focus:
            return camera.focusManual ? Format.focus(camera.manualLensPosition) : (camera.aeAfLocked ? "LOCK" : "AF")
        case .zoom:
            return Format.zoom((camera.currentLens?.magnification ?? 1) * telemetry.zoom)
        }
    }

    private func isManual(_ control: ProControl) -> Bool {
        switch control {
        case .ev: return abs(telemetry.exposureBias) > 0.05
        case .iso, .shutter: return camera.exposureManual
        case .whiteBalance: return camera.whiteBalanceManual
        case .focus: return camera.focusManual || camera.aeAfLocked
        case .zoom: return telemetry.zoom > 1.01
        }
    }

    private func isAvailable(_ control: ProControl) -> Bool {
        let caps = camera.capabilities
        switch control {
        case .iso, .shutter: return caps.supportsManualExposure
        case .whiteBalance: return caps.supportsManualWhiteBalance
        case .focus: return caps.supportsManualFocus
        case .ev, .zoom: return true
        }
    }
}

struct ProChip: View {
    let title: String
    let value: String
    let isManual: Bool
    let isSelected: Bool
    let isAvailable: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                HStack(spacing: 3) {
                    Text(title)
                        .font(Theme.rounded(8.5, .heavy))
                        .tracking(0.6)
                    Text(isManual ? "M" : "A")
                        .font(Theme.mono(7.5, .heavy))
                        .padding(.horizontal, 2.5)
                        .background(
                            RoundedRectangle(cornerRadius: 2)
                                .fill(isManual ? (isSelected ? Color.black.opacity(0.25) : Theme.accent.opacity(0.25)) : Color.white.opacity(0.12))
                        )
                }
                .foregroundStyle(isSelected ? Color.black.opacity(0.75) : Theme.secondaryText)

                Text(value)
                    .font(Theme.mono(13.5, .semibold))
                    .foregroundStyle(isSelected ? Color.black : (isManual ? Theme.accent : Color.white))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
            }
            .frame(minWidth: 60)
            .frame(height: 44)
            .padding(.horizontal, 7)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Theme.accent : Theme.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isManual && !isSelected ? Theme.accent.opacity(0.55) : Theme.hairline, lineWidth: 0.7)
            )
            .opacity(isAvailable ? 1 : 0.35)
        }
        .buttonStyle(PressableStyle())
        .disabled(!isAvailable)
    }
}

// MARK: - Dial panel

struct DialPanel: View {
    @EnvironmentObject private var camera: CameraController
    @EnvironmentObject private var telemetry: CameraTelemetry
    @EnvironmentObject private var assists: AssistSettings
    let control: ProControl
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Text(control.help)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            extraRow
            dial
        }
        .padding(14)
        .glassPanel(cornerRadius: 20)
        .padding(.horizontal, 12)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: control.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text(control.title.uppercased())
                .font(Theme.rounded(11, .heavy))
                .tracking(0.8)
                .foregroundStyle(.white)
            Spacer()
            Text(bigValue)
                .font(Theme.mono(17, .bold))
                .foregroundStyle(isManual ? Theme.accent : .white)
                .contentTransition(.numericText())
            if control != .zoom && control != .ev {
                Button {
                    Haptics.light()
                    setAuto()
                } label: {
                    Text("AUTO")
                        .font(Theme.rounded(10, .heavy))
                        .foregroundStyle(isManual ? Color.white : Color.black)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(isManual ? Theme.panelStrong : Theme.accent))
                }
                .buttonStyle(PressableStyle())
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Theme.panel))
            }
            .buttonStyle(PressableStyle())
        }
    }

    // MARK: Extra rows

    @ViewBuilder
    private var extraRow: some View {
        switch control {
        case .iso, .shutter:
            HStack(spacing: 10) {
                ExposureMeter(offset: telemetry.exposureOffset)
                if control == .shutter, camera.settings.mode == .video {
                    let angle = shutterAngle
                    Text("\(Int(angle.rounded()))°")
                        .font(Theme.mono(11, .bold))
                        .foregroundStyle(abs(angle - 180) < 15 ? Theme.ok : .white)
                    Button("180°") {
                        let target = 1 / (2 * Double(camera.settings.fps))
                        let index = Stops.nearestIndex(in: camera.shutterStops, to: target)
                        if camera.shutterStops.indices.contains(index) {
                            camera.setShutter(camera.shutterStops[index])
                        }
                        Haptics.medium()
                    }
                    .font(Theme.rounded(10, .heavy))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Theme.ok))
                }
            }
        case .whiteBalance:
            HStack(spacing: 6) {
                ForEach(WhiteBalancePreset.all) { preset in
                    let selected = camera.whiteBalanceManual && abs(camera.manualTemperature - preset.temperature) < 1
                    Button {
                        Haptics.light()
                        camera.setWhiteBalance(temperature: preset.temperature, tint: 0)
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: preset.symbol)
                                .font(.system(size: 13))
                            Text(preset.id)
                                .font(Theme.rounded(8, .bold))
                        }
                        .foregroundStyle(selected ? Color.black : Color.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 9).fill(selected ? Theme.accent : Theme.panel))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        case .focus:
            HStack {
                Toggle(isOn: $assists.peaking) {
                    Label("Focus peaking", systemImage: "sparkles")
                        .font(Theme.rounded(11, .bold))
                }
                .toggleStyle(.button)
                .tint(Theme.accent)
                Spacer()
                if telemetry.isAdjustingFocus {
                    Text("AF…")
                        .font(Theme.mono(10, .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
        case .ev:
            if camera.exposureManual {
                Label("Con ISO e tempo manuali la compensazione non ha effetto: premi AUTO.", systemImage: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accent)
            }
        case .zoom:
            EmptyView()
        }
    }

    // MARK: Dial

    @ViewBuilder
    private var dial: some View {
        switch control {
        case .ev:
            DialView(
                values: camera.evStops,
                selectedIndex: Stops.nearestIndex(in: camera.evStops, to: telemetry.exposureBias),
                majorEvery: 3,
                label: { Format.ev($0) },
                onChange: { camera.setExposureBias(camera.evStops[$0]) }
            )
        case .iso:
            DialView(
                values: camera.isoStops,
                selectedIndex: Stops.nearestIndex(in: camera.isoStops, to: camera.exposureManual ? camera.manualISO : telemetry.iso),
                majorEvery: 3,
                label: { Format.iso($0) },
                onChange: { camera.setISO(camera.isoStops[$0]) }
            )
        case .shutter:
            DialView(
                values: camera.shutterStops,
                selectedIndex: Stops.nearestIndex(in: camera.shutterStops, to: camera.exposureManual ? camera.manualShutter : telemetry.shutter),
                majorEvery: 3,
                label: { Format.shutter($0) },
                onChange: { camera.setShutter(camera.shutterStops[$0]) }
            )
        case .whiteBalance:
            DialView(
                values: Stops.temperature,
                selectedIndex: Stops.nearestIndex(in: Stops.temperature, to: camera.whiteBalanceManual ? camera.manualTemperature : telemetry.temperature),
                majorEvery: 10,
                label: { "\(Int($0))" },
                onChange: { camera.setWhiteBalance(temperature: Stops.temperature[$0]) }
            )
        case .focus:
            DialView(
                values: Stops.focus,
                selectedIndex: Stops.nearestIndex(in: Stops.focus, to: camera.focusManual ? camera.manualLensPosition : telemetry.lensPosition),
                majorEvery: 10,
                label: { $0 == 0 ? "VICINO" : Format.focus($0) },
                onChange: { camera.setLensPosition(Stops.focus[$0]) }
            )
        case .zoom:
            let magnification = camera.currentLens?.magnification ?? 1
            DialView(
                values: camera.zoomStops,
                selectedIndex: Stops.nearestIndex(in: camera.zoomStops, to: telemetry.zoom),
                majorEvery: 5,
                label: { Format.zoom($0 * magnification) },
                onChange: { camera.setZoom(camera.zoomStops[$0]) }
            )
        }
    }

    // MARK: Helpers

    private var isManual: Bool {
        switch control {
        case .ev: return abs(telemetry.exposureBias) > 0.05
        case .iso, .shutter: return camera.exposureManual
        case .whiteBalance: return camera.whiteBalanceManual
        case .focus: return camera.focusManual
        case .zoom: return telemetry.zoom > 1.01
        }
    }

    private var bigValue: String {
        switch control {
        case .ev: return Format.ev(telemetry.exposureBias) + " EV"
        case .iso: return Format.iso(camera.exposureManual ? camera.manualISO : telemetry.iso)
        case .shutter: return Format.shutter(camera.exposureManual ? camera.manualShutter : telemetry.shutter)
        case .whiteBalance: return Format.kelvin(camera.whiteBalanceManual ? camera.manualTemperature : telemetry.temperature)
        case .focus: return camera.focusManual ? Format.focus(camera.manualLensPosition) : "AF " + Format.focus(telemetry.lensPosition)
        case .zoom: return Format.zoom((camera.currentLens?.magnification ?? 1) * telemetry.zoom)
        }
    }

    private var shutterAngle: Double {
        let seconds = camera.exposureManual ? camera.manualShutter : telemetry.shutter
        return seconds * Double(camera.settings.fps) * 360
    }

    private func setAuto() {
        switch control {
        case .iso, .shutter: camera.setExposureAuto()
        case .whiteBalance: camera.setWhiteBalanceAuto()
        case .focus: camera.setFocusAuto()
        case .ev: camera.setExposureBias(0)
        case .zoom: camera.setZoom(1, animated: true)
        }
    }
}

/// Light meter: how far the current exposure is from what the camera thinks is correct.
struct ExposureMeter: View {
    let offset: Double

    var body: some View {
        HStack(spacing: 6) {
            Text("ESPOSIMETRO")
                .font(Theme.rounded(8, .heavy))
                .foregroundStyle(Theme.tertiaryText)
            GeometryReader { geo in
                let w = geo.size.width
                let clamped = min(max(offset, -3), 3)
                ZStack(alignment: .leading) {
                    ForEach(-3...3, id: \.self) { stop in
                        Rectangle()
                            .fill(Color.white.opacity(stop == 0 ? 0.8 : 0.3))
                            .frame(width: 1, height: stop == 0 ? 10 : 6)
                            .position(x: w / 2 + CGFloat(stop) / 6 * w, y: 6)
                    }
                    Circle()
                        .fill(abs(clamped) < 0.35 ? Theme.ok : Theme.accent)
                        .frame(width: 7, height: 7)
                        .position(x: w / 2 + CGFloat(clamped) / 6 * w, y: 6)
                        .animation(.easeOut(duration: 0.15), value: clamped)
                }
            }
            .frame(height: 12)
            Text(Format.ev(offset))
                .font(Theme.mono(10, .bold))
                .foregroundStyle(abs(offset) < 0.35 ? Theme.ok : Theme.accent)
                .frame(width: 38, alignment: .trailing)
        }
    }
}
