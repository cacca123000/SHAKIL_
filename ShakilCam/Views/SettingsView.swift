import AVFoundation
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var camera: CameraController
    @EnvironmentObject private var assists: AssistSettings
    @EnvironmentObject private var log: CameraLog
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    videoSection
                    photoSection
                    moreSection
                    footer
                }
                .padding(16)
            }
            .background(Color.black)
            .navigationTitle("Impostazioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                        .font(Theme.rounded(15, .bold))
                        .tint(Theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Video

    private var videoSection: some View {
        let s = camera.settings
        let caps = camera.capabilities
        return SettingsCard(title: "VIDEO", symbol: "video.fill") {
            OptionGroup(title: "Risoluzione", detail: "Più pixel = più dettaglio e file più grandi.") {
                SegmentedChips(options: VideoResolution.allCases, selection: binding(\.resolution),
                               isEnabled: { caps.supports($0) }) { $0.title }
            }
            OptionGroup(title: "Fotogrammi al secondo",
                        detail: "24 = look cinema · 30 = standard · 60 = fluido · 120/240 = slow motion.") {
                ScrollView(.horizontal, showsIndicators: false) {
                    SegmentedChips(options: FrameRates.all.map(FPSOption.init), selection: fpsBinding,
                                   isEnabled: { caps.supports(s.resolution, fps: $0.value) }) { "\($0.value)" }
                }
            }
            OptionGroup(title: "Profilo colore", detail: s.profile.subtitle) {
                SegmentedChips(options: ColorProfile.allCases, selection: binding(\.profile),
                               isEnabled: { caps.supportsAnywhere($0) }) { $0.title }
                if !caps.supports(s.resolution, fps: s.fps, profile: s.profile) {
                    Label("Questa combinazione verrà adattata automaticamente.", systemImage: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accent)
                }
                if !caps.supportsAnywhere(.appleLog) {
                    Text("Apple Log richiede iPhone 15 Pro o successivo.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
            OptionGroup(title: "Codec", detail: s.codec.subtitle) {
                SegmentedChips(options: VideoCodec.allCases, selection: binding(\.codec),
                               isEnabled: { caps.codecs.contains($0) }) { $0.title }
                if s.codec == .proRes {
                    Text("Con ProRes gli strumenti di analisi live (istogramma, zebra, peaking, LUT) vengono messi in pausa da iOS.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accent)
                }
            }
            OptionGroup(title: "Stabilizzazione", detail: "Cinema+ è la più forte ma ritaglia di più l'immagine.") {
                SegmentedChips(options: Stabilization.allCases, selection: binding(\.stabilization),
                               isEnabled: { caps.stabilizations.contains($0) }) { $0.title }
            }
            Toggle(isOn: binding(\.audioEnabled)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Registra audio")
                        .font(Theme.rounded(14, .bold))
                    Text("Usa il microfono del telefono.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .tint(Theme.accent)
        }
        .disabled(camera.isRecording)
    }

    // MARK: Photo

    private var photoSection: some View {
        let s = camera.settings
        let caps = camera.capabilities
        return SettingsCard(title: "FOTO", symbol: "camera.fill") {
            OptionGroup(title: "Formato", detail: s.photoFormat.subtitle) {
                SegmentedChips(options: PhotoFormat.allCases, selection: binding(\.photoFormat),
                               isEnabled: { caps.photoFormats.contains($0) }) { $0.title }
            }
            OptionGroup(title: "Risoluzione", detail: caps.supportsMaxPhotoResolution
                        ? "MAX usa tutti i pixel del sensore (fino a 48 MP)."
                        : "Questo obiettivo scatta a 12 MP.") {
                SegmentedChips(options: PhotoResolution.allCases, selection: binding(\.photoResolution),
                               isEnabled: { $0 == .standard || caps.supportsMaxPhotoResolution }) { $0.title }
            }
            OptionGroup(title: "Flash", detail: "Auto lo usa solo quando serve.") {
                SegmentedChips(options: FlashSetting.allCases, selection: binding(\.flash),
                               isEnabled: { _ in caps.hasFlash }) { $0.rawValue.capitalized }
            }
            OptionGroup(title: "Autoscatto", detail: "Conto alla rovescia prima dello scatto.") {
                SegmentedChips(options: SelfTimer.allCases, selection: binding(\.timer)) { $0.title }
            }
        }
    }

    // MARK: More

    private var moreSection: some View {
        SettingsCard(title: "ALTRO", symbol: "ellipsis.circle.fill") {
            NavigationLink {
                LogView()
            } label: {
                SettingsLinkRow(symbol: "terminal.fill", title: "Log della fotocamera",
                                detail: "\(log.entries.count) eventi registrati", tint: Theme.ok)
            }
            NavigationLink {
                GuideView()
            } label: {
                SettingsLinkRow(symbol: "book.fill", title: "Guida alle funzioni",
                                detail: "Cosa fa ogni pulsante, spiegato semplice", tint: Theme.cyan)
            }
            NavigationLink {
                DeviceInfoView()
            } label: {
                SettingsLinkRow(symbol: "cpu.fill", title: "Info fotocamera",
                                detail: "Obiettivi, formati e capacità del tuo iPhone", tint: Theme.log)
            }
            Button {
                Haptics.medium()
                assists.resetAll()
                camera.resetManualControls()
            } label: {
                SettingsLinkRow(symbol: "arrow.counterclockwise", title: "Ripristina strumenti",
                                detail: "Riporta mirino e controlli manuali ai valori di base", tint: Theme.rec,
                                showsChevron: false)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("SHAKIL CAM")
                .font(Theme.rounded(12, .heavy))
                .tracking(3)
                .foregroundStyle(Theme.accent)
            Text("Versione \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                .font(Theme.mono(10))
                .foregroundStyle(Theme.tertiaryText)
        }
        .padding(.top, 8)
    }

    // MARK: Bindings

    private func binding<Value>(_ keyPath: WritableKeyPath<CameraSettings, Value>) -> Binding<Value> {
        Binding(
            get: { camera.settings[keyPath: keyPath] },
            set: { newValue in camera.update { $0[keyPath: keyPath] = newValue } }
        )
    }

    private var fpsBinding: Binding<FPSOption> {
        Binding(
            get: { FPSOption(value: camera.settings.fps) },
            set: { option in camera.update { $0.fps = option.value } }
        )
    }
}

struct FPSOption: Identifiable, Hashable {
    let value: Int
    var id: Int { value }
}

// MARK: - Building blocks

struct SettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
                Text(title)
                    .font(Theme.rounded(11, .heavy))
                    .tracking(1.6)
            }
            .foregroundStyle(Theme.accent)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
    }
}

struct OptionGroup<Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.rounded(14, .bold))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
    }
}

struct SettingsLinkRow: View {
    let symbol: String
    let title: String
    let detail: String
    let tint: Color
    var showsChevron = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.rounded(14, .bold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Log

struct LogView: View {
    @EnvironmentObject private var log: CameraLog
    @State private var filter: LogFilter = .all

    enum LogFilter: String, CaseIterable, Identifiable {
        case all, captures, problems
        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "Tutto"
            case .captures: return "Scatti"
            case .problems: return "Problemi"
            }
        }

        func includes(_ level: CameraLog.Level) -> Bool {
            switch self {
            case .all: return true
            case .captures: return level == .capture
            case .problems: return level == .warning || level == .error
            }
        }
    }

    var body: some View {
        let entries = log.entries.filter { filter.includes($0.level) }
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(entries) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(entry.time)
                                .font(Theme.mono(10))
                                .foregroundStyle(Theme.tertiaryText)
                            Text(entry.level.tag)
                                .font(Theme.mono(10, .heavy))
                                .foregroundStyle(entry.level.color)
                            Text(entry.message)
                                .font(Theme.mono(11))
                                .foregroundStyle(.white.opacity(0.9))
                                .textSelection(.enabled)
                        }
                        .id(entry.id)
                    }
                    if entries.isEmpty {
                        Text("Nessun evento")
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.tertiaryText)
                            .padding(.top, 40)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(14)
            }
            .background(Color.black)
            .onAppear {
                if let last = entries.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
            .onChange(of: log.entries.last?.id) { _, id in
                if let id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
            }
        }
        .safeAreaInset(edge: .top) {
            SegmentedChips(options: LogFilter.allCases, selection: $filter) { $0.title }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
        }
        .navigationTitle("Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: log.exportText) {
                    Image(systemName: "square.and.arrow.up")
                }
                Button(role: .destructive) {
                    log.clear()
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
    }
}

// MARK: - Guide

struct GuideView: View {
    private struct GuideItem: Identifiable {
        let symbol: String
        let title: String
        let text: String
        var id: String { title }
    }

    private struct GuideSection: Identifiable {
        let title: String
        let items: [GuideItem]
        var id: String { title }
    }

    private let sections: [GuideSection] = [
        GuideSection(title: "SCATTO", items: [
            GuideItem(symbol: "circle.inset.filled", title: "Pulsante di scatto",
                 text: "In FOTO scatta, in VIDEO avvia e ferma la registrazione. Funzionano anche i tasti del volume e il tasto Fotocamera."),
            GuideItem(symbol: "arrow.left.and.right", title: "FOTO / VIDEO",
                 text: "Tocca la modalità o scorri col dito sopra le scritte."),
            GuideItem(symbol: "timer", title: "Autoscatto",
                 text: "3 o 10 secondi di conto alla rovescia. Tocca di nuovo lo scatto per annullare."),
            GuideItem(symbol: "bolt.fill", title: "Flash e torcia",
                 text: "Nelle foto: Off / Auto / On. Nei video diventa una torcia sempre accesa."),
        ]),
        GuideSection(title: "CONTROLLI MANUALI", items: [
            GuideItem(symbol: "plusminus.circle", title: "EV",
                 text: "Schiarisce o scurisce mantenendo l'esposizione automatica."),
            GuideItem(symbol: "camera.aperture", title: "ISO",
                 text: "Sensibilità del sensore. Alto = più luce ma più grana."),
            GuideItem(symbol: "timer", title: "Shutter",
                 text: "Tempo di scatto. Nei video la regola d'oro è 1/(2×fps): il pulsante 180° lo imposta da solo."),
            GuideItem(symbol: "thermometer.sun", title: "WB",
                 text: "Bilanciamento del bianco in Kelvin, con preset per sole, nuvole, tungsteno…"),
            GuideItem(symbol: "scope", title: "Focus",
                 text: "Messa a fuoco manuale. Tocca lo schermo per l'autofocus su un punto, tieni premuto per bloccare AE/AF."),
            GuideItem(symbol: "plus.magnifyingglass", title: "Zoom",
                 text: "Pizzica lo schermo o usa la ghiera. I pulsanti .5 / 1 / 3 cambiano obiettivo fisico."),
            GuideItem(symbol: "arrow.counterclockwise", title: "AUTO",
                 text: "Riporta tutti i controlli in automatico. A = automatico, M = manuale."),
        ]),
        GuideSection(title: "VIDEO PRO", items: [
            GuideItem(symbol: "camera.filters", title: "Apple Log",
                 text: "Registra un'immagine piatta con la massima gamma dinamica, da colorare in post (DaVinci, Final Cut). Serve iPhone 15 Pro o successivo."),
            GuideItem(symbol: "sun.max.fill", title: "HDR",
                 text: "Video HDR HLG con luci brillanti, pronto per schermi HDR."),
            GuideItem(symbol: "film", title: "ProRes",
                 text: "Codec da cinema con qualità altissima. Occupa tantissimo spazio."),
            GuideItem(symbol: "hand.raised.fingers.spread", title: "Stabilizzazione",
                 text: "Standard, Cinema o Cinema+ per riprese a mano fluide."),
            GuideItem(symbol: "waveform", title: "Audio meter",
                 text: "Barre verdi-gialle-rosse: se arrivano al rosso l'audio distorce."),
        ]),
        GuideSection(title: "STRUMENTI MIRINO", items: [
            GuideItem(symbol: "chart.bar.xaxis", title: "Istogramma",
                 text: "Grafico della luce. Il pallino rosso indica zone bruciate, quello azzurro ombre chiuse."),
            GuideItem(symbol: "line.diagonal", title: "Zebra",
                 text: "Righe sulle zone troppo luminose."),
            GuideItem(symbol: "paintpalette", title: "Falsi colori",
                 text: "Verde = esposizione perfetta del grigio medio, rosa = pelle, giallo/rosso = troppa luce."),
            GuideItem(symbol: "sparkles", title: "Focus peaking",
                 text: "Colora ciò che è a fuoco."),
            GuideItem(symbol: "wand.and.stars", title: "Look",
                 text: "Filtri cinematografici: salvati nelle foto, solo anteprima nei video."),
            GuideItem(symbol: "level", title: "Livella e griglia",
                 text: "Per foto dritte e composizioni equilibrate."),
            GuideItem(symbol: "terminal", title: "Console log",
                 text: "Mostra in tempo reale cosa sta facendo la fotocamera. La cronologia completa è in Impostazioni → Log."),
        ]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(section.title)
                            .font(Theme.rounded(10, .heavy))
                            .tracking(1.6)
                            .foregroundStyle(Theme.accent)
                        ForEach(section.items) { item in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: item.symbol)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(Theme.rounded(14, .bold))
                                    Text(item.text)
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(Theme.secondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.panel))
                }
            }
            .padding(16)
        }
        .background(Color.black)
        .navigationTitle("Guida")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Device info

struct DeviceInfoView: View {
    @EnvironmentObject private var camera: CameraController

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(camera.lenses) { lens in
                    lensCard(lens)
                }
            }
            .padding(16)
        }
        .background(Color.black)
        .navigationTitle("Info fotocamera")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func lensCard(_ lens: Lens) -> some View {
        let device = lens.device
        let format = device.activeFormat
        let combos = CameraController.videoCombos(for: device)
        let maxFPS = combos.map(\.fps).max() ?? 0
        let has4K = combos.contains { $0.resolution == .uhd4K }
        let hasLog = combos.contains { $0.profile == .appleLog }
        let hasHDR = combos.contains { $0.profile == .hlg }
        let rows: [(String, String)] = [
            ("Modello", device.localizedName),
            ("Zoom", Format.zoom(lens.magnification)),
            ("ISO", "\(Int(format.minISO)) – \(Int(format.maxISO))"),
            ("Tempi", "\(Format.shutter(format.minExposureDuration.seconds)) – \(Format.shutter(format.maxExposureDuration.seconds))"),
            ("Apertura", String(format: "ƒ%.2f", device.lensAperture)),
            ("Video max", "\(has4K ? "4K" : "1080p") · fino a \(maxFPS) fps"),
            ("HDR HLG", hasHDR ? "Sì" : "No"),
            ("Apple Log", hasLog ? "Sì" : "No"),
            ("Fuoco manuale", device.isLockingFocusWithCustomLensPositionSupported ? "Sì" : "No"),
            ("Flash / Torcia", "\(device.hasFlash ? "Sì" : "No") / \(device.hasTorch ? "Sì" : "No")"),
            ("Formati", "\(device.formats.count)"),
        ]
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(lens.kind.name.uppercased())
                    .font(Theme.rounded(11, .heavy))
                    .tracking(1.4)
                    .foregroundStyle(Theme.accent)
                Spacer()
                if lens == camera.currentLens {
                    Badge(text: "IN USO", color: Theme.ok, filled: true)
                }
            }
            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]
                HStack {
                    Text(row.0)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Text(row.1)
                        .font(Theme.mono(12, .semibold))
                        .foregroundStyle(row.1 == "Sì" ? Theme.ok : .white)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.panel))
    }
}
