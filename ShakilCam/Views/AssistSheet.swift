import SwiftUI

/// Viewfinder tools, each with a one-line explanation of what it does.
struct AssistSheet: View {
    @EnvironmentObject private var assists: AssistSettings
    @EnvironmentObject private var camera: CameraController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Strumenti mirino")
                            .font(Theme.rounded(22, .heavy))
                        Text("Aiuti visivi da professionista. Non finiscono nel file, tranne i Look nelle foto.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    Button("Reset") {
                        Haptics.medium()
                        assists.resetAll()
                    }
                    .font(Theme.rounded(12, .bold))
                    .tint(Theme.accent)
                }

                if !camera.analysisAvailable {
                    Label("Con il codec ProRes iOS non permette l'analisi live: istogramma, peaking, zebra, falsi colori e LUT sono in pausa.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.accent)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accent.opacity(0.12)))
                }

                section("ESPOSIZIONE") {
                    AssistRow(symbol: "chart.bar.xaxis", title: "Istogramma",
                              detail: "Distribuzione della luce: picchi a destra = rischio bruciato, a sinistra = ombre chiuse.") {
                        SegmentedChips(options: HistogramMode.allCases, selection: $assists.histogram) { $0.title }
                    }
                    AssistRow(symbol: "line.diagonal", title: "Zebra",
                              detail: "Righe diagonali sulle zone più luminose della soglia: lì stai perdendo dettaglio.") {
                        Toggle("", isOn: $assists.zebra).labelsHidden().tint(Theme.accent)
                    }
                    if assists.zebra {
                        HStack {
                            Text("Soglia")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.secondaryText)
                            Slider(value: $assists.zebraThreshold, in: 0.7...1.0, step: 0.05)
                                .tint(Theme.accent)
                            Text("\(Int(assists.zebraThreshold * 100))%")
                                .font(Theme.mono(12, .bold))
                                .frame(width: 44, alignment: .trailing)
                        }
                        .padding(.leading, 40)
                    }
                    AssistRow(symbol: "paintpalette", title: "Falsi colori",
                              detail: "Colora l'immagine per livello di luce: verde = grigio medio, rosa = pelle, rosso = bruciato.") {
                        Toggle("", isOn: $assists.falseColor).labelsHidden().tint(Theme.accent)
                    }
                }

                section("MESSA A FUOCO") {
                    AssistRow(symbol: "sparkles", title: "Focus peaking",
                              detail: "Evidenzia i bordi nitidi: quello che si colora è a fuoco.") {
                        Toggle("", isOn: $assists.peaking).labelsHidden().tint(Theme.accent)
                    }
                    if assists.peaking {
                        HStack(spacing: 12) {
                            Text("Colore")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.secondaryText)
                            ForEach(PeakingColor.allCases) { color in
                                Button {
                                    assists.peakingColor = color
                                } label: {
                                    Circle()
                                        .fill(color.color)
                                        .frame(width: 22, height: 22)
                                        .overlay(Circle().strokeBorder(.white, lineWidth: assists.peakingColor == color ? 2 : 0))
                                }
                            }
                        }
                        .padding(.leading, 40)
                    }
                }

                section("COLORE") {
                    AssistRow(symbol: "camera.filters", title: "LUT Log → Rec.709",
                              detail: "Mentre registri in Apple Log vedi l'immagine con colori normali. Il file resta Log.") {
                        Toggle("", isOn: $assists.logViewLUT).labelsHidden().tint(Theme.log)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Look")
                                    .font(Theme.rounded(14, .bold))
                                Text(assists.look.subtitle + (assists.look == .natural ? "" : " · Salvato nelle foto HEIF/JPEG, solo anteprima nei video."))
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(LookPreset.allCases) { look in
                                    LookChip(look: look, selected: assists.look == look) {
                                        Haptics.selection()
                                        assists.look = look
                                        camLog("Look → \(look.title)")
                                    }
                                }
                            }
                        }
                    }
                }

                section("COMPOSIZIONE") {
                    AssistRow(symbol: "squareshape.split.3x3", title: "Griglia",
                              detail: "Regola dei terzi, sezione aurea o mirino centrale.") {
                        EmptyView()
                    }
                    SegmentedChips(options: GridStyle.allCases, selection: $assists.grid) { $0.title }
                        .padding(.leading, 40)
                    AssistRow(symbol: "level", title: "Livella",
                              detail: "Linea dell'orizzonte: diventa gialla quando il telefono è dritto.") {
                        Toggle("", isOn: $assists.showLevel).labelsHidden().tint(Theme.accent)
                    }
                    AssistRow(symbol: "rectangle.dashed", title: "Guide di formato",
                              detail: "Oscura i bordi per inquadrare in cinemascope, quadrato o formato social.") {
                        EmptyView()
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        SegmentedChips(options: FrameGuide.allCases, selection: $assists.frameGuide) { $0.title }
                    }
                    .padding(.leading, 40)
                }

                section("SISTEMA") {
                    AssistRow(symbol: "terminal", title: "Console log",
                              detail: "Mostra in diretta ogni azione della fotocamera: formati, errori, scatti.") {
                        Toggle("", isOn: $assists.showConsole).labelsHidden().tint(Theme.ok)
                    }
                }
            }
            .padding(20)
        }
        .preferredColorScheme(.dark)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(Theme.rounded(10, .heavy))
                .tracking(1.4)
                .foregroundStyle(Theme.tertiaryText)
            content()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
    }
}

struct AssistRow<Accessory: View>: View {
    let symbol: String
    let title: String
    let detail: String
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.rounded(14, .bold))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            accessory()
        }
    }
}

/// Row of capsule buttons acting as a segmented control.
struct SegmentedChips<Option: Identifiable & Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    var isEnabled: (Option) -> Bool = { _ in true }
    let title: (Option) -> String

    init(options: [Option], selection: Binding<Option>,
         isEnabled: @escaping (Option) -> Bool = { _ in true },
         title: @escaping (Option) -> String) {
        self.options = options
        self._selection = selection
        self.isEnabled = isEnabled
        self.title = title
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options) { option in
                let selected = option == selection
                let enabled = isEnabled(option)
                Button {
                    guard enabled else { return }
                    Haptics.selection()
                    selection = option
                } label: {
                    Text(title(option))
                        .font(Theme.mono(11.5, .bold))
                        .foregroundStyle(selected ? Color.black : (enabled ? Color.white : Theme.tertiaryText))
                        .strikethrough(!enabled, color: Theme.tertiaryText)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(selected ? Theme.accent : Theme.panelStrong))
                }
                .buttonStyle(PressableStyle())
                .disabled(!enabled)
            }
        }
    }
}

struct LookChip: View {
    let look: LookPreset
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(gradient)
                    .frame(width: 62, height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(selected ? Theme.accent : Theme.hairline, lineWidth: selected ? 2 : 0.6)
                    )
                Text(look.title)
                    .font(Theme.rounded(9.5, .bold))
                    .foregroundStyle(selected ? Theme.accent : .white.opacity(0.8))
                    .lineLimit(1)
            }
        }
        .buttonStyle(PressableStyle())
    }

    private var gradient: LinearGradient {
        let colors: [Color]
        switch look {
        case .natural: colors = [Color(white: 0.25), Color(white: 0.6)]
        case .tealOrange: colors = [Color(red: 0.05, green: 0.35, blue: 0.4), Color(red: 1, green: 0.6, blue: 0.3)]
        case .warmFilm: colors = [Color(red: 0.35, green: 0.25, blue: 0.15), Color(red: 1, green: 0.85, blue: 0.6)]
        case .noir: colors = [.black, .white]
        case .bleach: colors = [Color(red: 0.25, green: 0.27, blue: 0.27), Color(red: 0.8, green: 0.8, blue: 0.75)]
        case .cool: colors = [Color(red: 0.02, green: 0.05, blue: 0.2), Color(red: 0.4, green: 0.6, blue: 0.9)]
        }
        return LinearGradient(colors: colors, startPoint: .bottomLeading, endPoint: .topTrailing)
    }
}
