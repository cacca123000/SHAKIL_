import AVFoundation
import Combine
import SwiftUI
import UIKit

enum CameraAuthorization {
    case unknown, authorized, denied
}

struct FocusIndicator: Equatable {
    let id = UUID()
    let point: CGPoint
    let locked: Bool
}

/// Live readings refreshed 10×/s. Kept separate from `CameraController` so only the
/// views that show numbers re-render that often.
final class CameraTelemetry: ObservableObject {
    @Published var iso: Double = 0
    @Published var shutter: Double = 0
    @Published var temperature: Double = 5500
    @Published var tint: Double = 0
    @Published var lensPosition: Double = 0
    @Published var exposureOffset: Double = 0
    @Published var exposureBias: Double = 0
    @Published var zoom: Double = 1
    @Published var isAdjustingFocus = false
    @Published var recordedSeconds: Double = 0
    @Published var audioLevel: Double = 0
    @Published var audioPeak: Double = 0
    @Published var batteryLevel: Double = 1
    @Published var batteryCharging = false
    @Published var freeBytes: Int64 = 0
    @Published var thermal: ProcessInfo.ThermalState = .nominal
}

/// Owns the AVCaptureSession. All session/device work happens on `sessionQueue`;
/// every `@Published` property is only written on the main thread.
final class CameraController: NSObject, ObservableObject {
    // MARK: Published state (main thread)

    @Published private(set) var authorization: CameraAuthorization = .unknown
    @Published var settings = CameraSettings.load()
    @Published var capabilities = LensCapabilities()
    @Published var lenses: [Lens] = []
    @Published var currentLens: Lens?
    @Published var isRunning = false
    @Published var isReconfiguring = true
    @Published var isRecording = false
    @Published var shutterBlink = false
    @Published var countdown: Int?
    @Published var captures: [CapturedMedia] = []
    @Published var processedPreviewActive = false
    @Published var analysisAvailable = true
    @Published var activeCodec: VideoCodec?
    @Published var photoMegapixels: Int = 12
    @Published var systemControlsActive = false
    @Published var focusIndicator: FocusIndicator?

    // Manual controls
    @Published var exposureManual = false
    @Published var manualISO: Double = 100
    @Published var manualShutter: Double = 1.0 / 60
    @Published var whiteBalanceManual = false
    @Published var manualTemperature: Double = 5600
    @Published var manualTint: Double = 0
    @Published var focusManual = false
    @Published var manualLensPosition: Double = 0.5
    @Published var aeAfLocked = false
    @Published var torchOn = false
    @Published var isoStops: [Double] = Stops.iso
    @Published var shutterStops: [Double] = Stops.shutter
    @Published var evStops: [Double] = [0]
    @Published var zoomStops: [Double] = [1]

    let telemetry = CameraTelemetry()
    let histogram = HistogramModel()
    let frameProcessor = FrameProcessor()

    // MARK: Capture pipeline (session queue)

    let session = AVCaptureSession()
    let sessionQueue = DispatchQueue(label: "cam.session", qos: .userInitiated)
    let photoOutput = AVCapturePhotoOutput()
    let movieOutput = AVCaptureMovieFileOutput()
    let videoDataOutput = AVCaptureVideoDataOutput()
    var videoInput: AVCaptureDeviceInput?
    var audioInput: AVCaptureDeviceInput?
    var sessionDevice: AVCaptureDevice?
    var sessionLenses: [Lens] = []
    var isConfigured = false
    var photoProcessors: [Int64: PhotoCaptureProcessor] = [:]
    var bayerRAWSupport: [String: Bool] = [:]
    var proResSeen: Set<String> = []
    var cachedPhotoFormats: [PhotoFormat] = [.heif, .jpeg]

    // MARK: Main thread helpers

    weak var previewView: PreviewView?
    weak var assists: AssistSettings?
    var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    var cancellables = Set<AnyCancellable>()
    var telemetryTimer: Timer?
    var countdownTimer: Timer?
    var zoomAtPinchStart: Double = 1
    var lastBackLens: LensKind = .wide
    var telemetryTick = 0

    override init() {
        super.init()
        frameProcessor.onHistogram = { [weak self] value in
            self?.histogram.value = value
        }
        observeNotifications()
        camLog("Shakil Cam avviata — \(UIDevice.current.model), iOS \(UIDevice.current.systemVersion)")
    }

    // MARK: - Lifecycle

    func attach(assists: AssistSettings) {
        guard self.assists !== assists else { return }
        self.assists = assists
        assists.objectWillChange
            .sink { [weak self] _ in
                // objectWillChange fires before the new value is stored.
                DispatchQueue.main.async { self?.updateFrameRouting() }
            }
            .store(in: &cancellables)
        updateFrameRouting()
    }

    /// Called by the SwiftUI viewfinder once its UIView exists.
    func attach(previewView: PreviewView) {
        self.previewView = previewView
        previewView.previewLayer.session = session
        previewView.metalView.frameSource = frameProcessor
        previewView.metalView.snapshotProvider = { [weak self] in
            self?.assistSnapshot() ?? AssistSnapshot()
        }
        previewView.onTap = { [weak self] point in self?.focus(at: point) }
        previewView.onLongPress = { [weak self] point in self?.lockFocusAndExposure(at: point) }
        previewView.onPinch = { [weak self] scale, state in self?.handlePinch(scale: scale, state: state) }
        previewView.onHardwareShutter = { [weak self] in self?.shutterPressed() }
        configurePreviewConnection()
        rebuildRotationCoordinator()
        updateFrameRouting()
    }

    func requestAccessAndStart() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        var granted = status == .authorized
        if status == .notDetermined {
            granted = await AVCaptureDevice.requestAccess(for: .video)
        }
        if granted, AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            let mic = await AVCaptureDevice.requestAccess(for: .audio)
            camLog(mic ? "Microfono autorizzato" : "Microfono negato: video senza audio", mic ? .success : .warning)
        }
        let isGranted = granted
        let requested = await MainActor.run { () -> CameraSettings in
            self.authorization = isGranted ? .authorized : .denied
            return self.settings
        }
        if isGranted {
            camLog("Accesso fotocamera concesso", .success)
            startSession(requested)
        } else {
            camLog("Accesso alla fotocamera negato", .error)
        }
    }

    private func startSession(_ requested: CameraSettings) {
        sessionQueue.async { [self] in
            if !isConfigured {
                configureSession(with: requested)
            }
            if isConfigured, !session.isRunning {
                session.startRunning()
                camLog(session.isRunning ? "Sessione avviata" : "La sessione non è partita", session.isRunning ? .success : .error)
            }
            let running = session.isRunning
            DispatchQueue.main.async {
                self.isRunning = running
                self.startTelemetry()
            }
        }
    }

    func resume() {
        guard authorization == .authorized else { return }
        startSession(settings)
    }

    func suspend() {
        cancelCountdown()
        if isRecording { stopRecording() }
        stopTelemetry()
        sessionQueue.async { [self] in
            if session.isRunning {
                session.stopRunning()
                camLog("Sessione in pausa (app in background)")
            }
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    // MARK: - Settings

    /// Changes settings and reconfigures the session when needed.
    func update(_ change: (inout CameraSettings) -> Void) {
        var new = settings
        change(&new)
        guard new != settings else { return }
        let old = settings
        settings = new
        new.save()
        if Self.needsReconfiguration(old, new) {
            reconfigure(new)
        }
    }

    /// Only settings that affect the active mode require touching the session.
    private static func needsReconfiguration(_ a: CameraSettings, _ b: CameraSettings) -> Bool {
        if a.mode != b.mode || a.preferredLens != b.preferredLens { return true }
        switch b.mode {
        case .photo:
            return a.photoFormat != b.photoFormat || a.photoResolution != b.photoResolution
        case .video:
            return a.resolution != b.resolution || a.fps != b.fps || a.codec != b.codec
                || a.profile != b.profile || a.stabilization != b.stabilization
                || a.audioEnabled != b.audioEnabled
        }
    }

    func reconfigure(_ requested: CameraSettings) {
        guard !isRecording else { return }
        withAnimation(.easeIn(duration: 0.15)) { isReconfiguring = true }
        if torchOn { torchOn = false }
        sessionQueue.async { [self] in
            guard isConfigured, let lens = pickLens(for: requested) else { return }
            applyConfiguration(lens: lens, settings: requested)
        }
    }

    func setMode(_ mode: CaptureMode) {
        guard mode != settings.mode, !isRecording else { return }
        cancelCountdown()
        camLog("Modalità → \(mode.title)")
        update { $0.mode = mode }
    }

    func selectLens(_ lens: Lens) {
        guard !isRecording, lens != currentLens else { return }
        if lens.kind != .front { lastBackLens = lens.kind }
        camLog("Obiettivo → \(lens.kind.name) (\(Format.zoom(lens.magnification)))")
        update { $0.preferredLens = lens.kind }
    }

    func flipCamera() {
        guard !isRecording else { return }
        if currentLens?.kind == .front {
            let back = lenses.first { $0.kind == lastBackLens } ?? lenses.first { $0.kind == .wide }
            if let back { selectLens(back) }
        } else if let front = lenses.first(where: { $0.kind == .front }) {
            selectLens(front)
        }
    }

    // MARK: - Session configuration (session queue)

    private func configureSession(with requested: CameraSettings) {
        MediaLibrary.purgeOldFiles()
        session.automaticallyConfiguresCaptureDeviceForWideColor = false

        sessionLenses = discoverLenses()
        guard let lens = pickLens(for: requested) else {
            camLog("Nessuna fotocamera disponibile su questo dispositivo", .error)
            return
        }
        let found = sessionLenses.map { "\($0.kind.name) \(Format.zoom($0.magnification))" }.joined(separator: ", ")
        camLog("Obiettivi trovati: \(found)")

        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        if videoDataOutput.availableVideoPixelFormatTypes.contains(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
            videoDataOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            ]
        }
        videoDataOutput.setSampleBufferDelegate(frameProcessor, queue: frameProcessor.queue)

        isConfigured = true
        let lenses = sessionLenses
        DispatchQueue.main.async { self.lenses = lenses }
        applyConfiguration(lens: lens, settings: requested)
    }

    func pickLens(for settings: CameraSettings) -> Lens? {
        sessionLenses.first { $0.kind == settings.preferredLens }
            ?? sessionLenses.first { $0.kind == .wide }
            ?? sessionLenses.first
    }

    private func discoverLenses() -> [Lens] {
        let back = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera],
            mediaType: .video, position: .back
        ).devices
        let front = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .front
        ).devices

        let wide = back.first { $0.deviceType == .builtInWideAngleCamera }
        let wideFOV = Double(wide?.activeFormat.videoFieldOfView ?? 70)

        var result: [Lens] = []
        for device in back {
            switch device.deviceType {
            case .builtInUltraWideCamera:
                result.append(Lens(device: device, kind: .ultraWide, magnification: 0.5))
            case .builtInWideAngleCamera:
                result.append(Lens(device: device, kind: .wide, magnification: 1))
            case .builtInTelephotoCamera:
                let fov = Double(device.activeFormat.videoFieldOfView)
                let ratio = tan(wideFOV / 2 * .pi / 180) / tan(max(fov, 1) / 2 * .pi / 180)
                let snapped = [2, 2.5, 3, 4, 5].min { abs($0 - ratio) < abs($1 - ratio) } ?? ratio
                result.append(Lens(device: device, kind: .telephoto, magnification: snapped))
            default:
                break
            }
        }
        result.sort { $0.magnification < $1.magnification }
        if let frontDevice = front.first {
            result.append(Lens(device: frontDevice, kind: .front, magnification: 1))
        }
        return result
    }

    func applyConfiguration(lens: Lens, settings requested: CameraSettings) {
        var s = requested
        s.preferredLens = lens.kind
        let device = lens.device
        let lensChanged = sessionDevice != device

        session.beginConfiguration()

        // Video input
        if lensChanged {
            if let videoInput {
                session.removeInput(videoInput)
                self.videoInput = nil
            }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(input) {
                    session.addInput(input)
                    videoInput = input
                } else {
                    camLog("Impossibile collegare \(lens.kind.name)", .error)
                }
            } catch {
                camLog("Errore obiettivo: \(error.localizedDescription)", .error)
            }
            sessionDevice = device
        }

        // Audio input (video only)
        let wantsAudio = s.mode == .video && s.audioEnabled
            && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        if wantsAudio, audioInput == nil {
            if let mic = AVCaptureDevice.default(for: .audio),
               let input = try? AVCaptureDeviceInput(device: mic),
               session.canAddInput(input) {
                session.addInput(input)
                audioInput = input
            } else {
                camLog("Microfono non disponibile", .warning)
            }
        } else if !wantsAudio, let audioInput {
            session.removeInput(audioInput)
            self.audioInput = nil
        }

        // Outputs. ProRes cannot run next to a video data output, so the live
        // analysis tools are switched off in that case.
        let analysisAllowed = !(s.mode == .video && s.codec == .proRes)
        setOutput(photoOutput, attached: s.mode == .photo)
        setOutput(movieOutput, attached: s.mode == .video)
        setOutput(videoDataOutput, attached: analysisAllowed)

        // Format
        if s.mode == .photo {
            if session.canSetSessionPreset(.photo) {
                session.sessionPreset = .photo
            }
        } else {
            s = configureVideoFormat(device: device, settings: s)
        }

        if lensChanged {
            configureSystemControls(for: device)
        }

        session.commitConfiguration()

        // Post-commit tuning (needs the final active format)
        var codec: VideoCodec?
        if s.mode == .photo {
            configurePhotoOutput(device: device, settings: &s)
        } else {
            codec = configureMovieOutput(device: device, settings: &s)
            if codec != .proRes, !session.outputs.contains(videoDataOutput) {
                session.beginConfiguration()
                setOutput(videoDataOutput, attached: true)
                session.commitConfiguration()
            }
        }
        configureDataOutputConnection(front: lens.kind == .front)

        let caps = computeCapabilities(device: device, mode: s.mode)
        let ranges = computeRanges(device: device, settings: s)
        let analysis = session.outputs.contains(videoDataOutput)
        let megapixels = Int((Double(photoOutput.maxPhotoDimensions.width) * Double(photoOutput.maxPhotoDimensions.height) / 1_000_000).rounded())
        let applied = s
        let appliedCodec = codec

        camLog(describe(applied, lens: lens, codec: codec), .success)

        DispatchQueue.main.async { [self] in
            if applied != settings {
                settings = applied
                applied.save()
            }
            capabilities = caps
            currentLens = lens
            analysisAvailable = analysis
            activeCodec = appliedCodec
            photoMegapixels = max(megapixels, 1)
            isoStops = ranges.iso
            shutterStops = ranges.shutter
            evStops = ranges.ev
            zoomStops = ranges.zoom
            if lensChanged {
                exposureManual = false
                whiteBalanceManual = false
                focusManual = false
                aeAfLocked = false
                torchOn = false
                rebuildRotationCoordinator()
            } else if exposureManual {
                // Format changes reset the exposure; re-apply the manual values.
                applyCustomExposure()
            }
            configurePreviewConnection()
            updateFrameRouting()
            withAnimation(.easeOut(duration: 0.3)) { isReconfiguring = false }
        }
    }

    private func setOutput(_ output: AVCaptureOutput, attached: Bool) {
        let isAttached = session.outputs.contains(output)
        if attached, !isAttached {
            if session.canAddOutput(output) {
                session.addOutput(output)
            } else {
                camLog("Impossibile aggiungere \(type(of: output))", .warning)
            }
        } else if !attached, isAttached {
            session.removeOutput(output)
        }
    }

    // MARK: Video format

    private func configureVideoFormat(device: AVCaptureDevice, settings: CameraSettings) -> CameraSettings {
        var s = settings
        let combos = Self.videoCombos(for: device)

        if !combos.contains(VideoCombo(resolution: s.resolution, fps: s.fps, profile: s.profile)) {
            let original = s
            s = Self.closestCombo(to: s, in: combos)
            camLog("\(Self.short(original)) non supportato da questo obiettivo → \(Self.short(s))", .warning)
        }

        guard let format = Self.bestFormat(device: device, settings: s) else {
            camLog("Nessun formato video compatibile trovato", .error)
            return s
        }

        do {
            try device.lockForConfiguration()
            device.activeFormat = format
            if format.supportedColorSpaces.contains(s.profile.colorSpace) {
                device.activeColorSpace = s.profile.colorSpace
            }
            let duration = CMTime(value: 1, timescale: CMTimeScale(s.fps))
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            device.unlockForConfiguration()
        } catch {
            camLog("Configurazione formato fallita: \(error.localizedDescription)", .error)
        }
        return s
    }

    static func videoCombos(for device: AVCaptureDevice) -> Set<VideoCombo> {
        var combos = Set<VideoCombo>()
        for format in device.formats {
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard let resolution = VideoResolution.allCases.first(where: {
                $0.width == dims.width && $0.height == dims.height
            }) else { continue }
            let profiles = ColorProfile.allCases.filter { format.supportedColorSpaces.contains($0.colorSpace) }
            for fps in FrameRates.all {
                let ok = format.videoSupportedFrameRateRanges.contains {
                    Double(fps) >= $0.minFrameRate - 0.01 && Double(fps) <= $0.maxFrameRate + 0.01
                }
                guard ok else { continue }
                for profile in profiles {
                    combos.insert(VideoCombo(resolution: resolution, fps: fps, profile: profile))
                }
            }
        }
        return combos
    }

    /// Keeps as much of the request as possible: profile first, then resolution, then fps.
    private static func closestCombo(to s: CameraSettings, in combos: Set<VideoCombo>) -> CameraSettings {
        var out = s
        func nearestFPS(_ candidates: [Int]) -> Int? {
            candidates.min { abs($0 - s.fps) < abs($1 - s.fps) }
        }
        let sameProfileAndRes = combos.filter { $0.profile == s.profile && $0.resolution == s.resolution }.map(\.fps)
        if let fps = nearestFPS(sameProfileAndRes) {
            out.fps = fps
            return out
        }
        let sameProfile = combos.filter { $0.profile == s.profile }
        if let resolution = VideoResolution.allCases.reversed().first(where: { r in sameProfile.contains { $0.resolution == r } }) {
            out.resolution = resolution
            out.fps = nearestFPS(sameProfile.filter { $0.resolution == resolution }.map(\.fps)) ?? 30
            return out
        }
        out.profile = .sdr
        let sdr = combos.filter { $0.profile == .sdr }
        if let resolution = VideoResolution.allCases.reversed().first(where: { r in sdr.contains { $0.resolution == r } }) {
            out.resolution = resolution
            out.fps = nearestFPS(sdr.filter { $0.resolution == resolution }.map(\.fps)) ?? 30
        }
        return out
    }

    private static let tenBit420: Set<OSType> = [
        kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
        kCVPixelFormatType_420YpCbCr10BiPlanarFullRange,
    ]
    private static let tenBit422: Set<OSType> = [
        kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange,
        kCVPixelFormatType_422YpCbCr10BiPlanarFullRange,
    ]

    private static func bestFormat(device: AVCaptureDevice, settings s: CameraSettings) -> AVCaptureDevice.Format? {
        let fps = Double(s.fps)
        let candidates = device.formats.filter { format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard dims.width == s.resolution.width, dims.height == s.resolution.height else { return false }
            guard format.supportedColorSpaces.contains(s.profile.colorSpace) else { return false }
            return format.videoSupportedFrameRateRanges.contains {
                fps >= $0.minFrameRate - 0.01 && fps <= $0.maxFrameRate + 0.01
            }
        }

        func score(_ format: AVCaptureDevice.Format) -> Int {
            let subtype = CMFormatDescriptionGetMediaSubType(format.formatDescription)
            var value = 0
            if s.profile == .sdr {
                if subtype == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange { value += 60 }
                if subtype == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange { value += 50 }
            } else {
                if tenBit420.contains(subtype) { value += s.codec == .proRes ? 90 : 100 }
                if tenBit422.contains(subtype) { value += s.codec == .proRes ? 110 : 40 }
            }
            if !format.isVideoBinned { value += 20 }
            if format.isVideoStabilizationModeSupported(s.stabilization.mode) { value += 10 }
            return value
        }

        return candidates.max { score($0) < score($1) }
    }

    /// Picks the codec and stabilization for the movie output. Returns the codec in use.
    private func configureMovieOutput(device: AVCaptureDevice, settings s: inout CameraSettings) -> VideoCodec? {
        guard let connection = movieOutput.connection(with: .video) else { return nil }
        let available = movieOutput.availableVideoCodecTypes
        var chosen: VideoCodec?
        var type: AVVideoCodecType?

        for codec in [s.codec] + VideoCodec.allCases.filter({ $0 != s.codec }) {
            if let match = codec.candidates.first(where: { available.contains($0) }) {
                chosen = codec
                type = match
                break
            }
        }
        if let chosen, chosen != s.codec {
            camLog("\(s.codec.title) non disponibile con questo formato → \(chosen.title)", .warning)
            s.codec = chosen
        }
        if let type {
            movieOutput.setOutputSettings([AVVideoCodecKey: type], for: connection)
        }

        if connection.isVideoStabilizationSupported {
            var mode = s.stabilization.mode
            if !device.activeFormat.isVideoStabilizationModeSupported(mode) {
                mode = device.activeFormat.isVideoStabilizationModeSupported(.standard) ? .standard : .off
                if s.stabilization != .off {
                    camLog("Stabilizzazione \(s.stabilization.title) non supportata qui", .warning)
                }
            }
            connection.preferredVideoStabilizationMode = mode
        }
        return chosen
    }

    // MARK: Photo output

    private func configurePhotoOutput(device: AVCaptureDevice, settings s: inout CameraSettings) {
        guard session.outputs.contains(photoOutput) else { return }
        // Wide color for photos.
        do {
            try device.lockForConfiguration()
            if device.activeFormat.supportedColorSpaces.contains(.P3_D65) {
                device.activeColorSpace = .P3_D65
            }
            device.unlockForConfiguration()
        } catch {
            camLog("Spazio colore foto non impostato: \(error.localizedDescription)", .warning)
        }

        // RAW support is only reported correctly while ProRAW is off.
        if !photoOutput.isAppleProRAWEnabled {
            bayerRAWSupport[device.uniqueID] = photoOutput.availableRawPhotoPixelFormatTypes
                .contains { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }
        }
        if s.photoFormat == .proRAW, !photoOutput.isAppleProRAWSupported {
            camLog("ProRAW non supportato da questo obiettivo → HEIF", .warning)
            s.photoFormat = .heif
        }
        if s.photoFormat == .raw, bayerRAWSupport[device.uniqueID] != true {
            camLog("RAW non supportato da questo obiettivo → HEIF", .warning)
            s.photoFormat = .heif
        }
        let wantsProRAW = s.photoFormat == .proRAW
        if photoOutput.isAppleProRAWSupported, photoOutput.isAppleProRAWEnabled != wantsProRAW {
            session.beginConfiguration()
            photoOutput.isAppleProRAWEnabled = wantsProRAW
            session.commitConfiguration()
        }

        let dimensions = device.activeFormat.supportedMaxPhotoDimensions
        func area(_ d: CMVideoDimensions) -> Int { Int(d.width) * Int(d.height) }
        let largest = dimensions.max { area($0) < area($1) }
        let standard = dimensions.filter { area($0) <= 12_600_000 }.max { area($0) < area($1) }
            ?? dimensions.min { area($0) < area($1) }
        let wantsMax = s.photoResolution == .maximum && s.photoFormat != .raw
        if let target = wantsMax ? largest : standard {
            photoOutput.maxPhotoDimensions = target
        }
        photoOutput.maxPhotoQualityPrioritization = .quality
    }

    // MARK: Connections

    private func configureDataOutputConnection(front: Bool) {
        frameProcessor.orientation = front ? .leftMirrored : .right
        guard let connection = videoDataOutput.connection(with: .video) else { return }
        if connection.isVideoRotationAngleSupported(0) {
            connection.videoRotationAngle = 0
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
    }

    /// Main thread. The UI is locked to portrait, so the preview is always rotated 90°.
    func configurePreviewConnection() {
        guard let connection = previewView?.previewLayer.connection else { return }
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }

    /// Main thread.
    func rebuildRotationCoordinator() {
        guard let device = currentLens?.device else { return }
        rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewView?.previewLayer)
    }

    var captureRotationAngle: CGFloat {
        rotationCoordinator?.videoRotationAngleForHorizonLevelCapture ?? 90
    }

    // MARK: Camera Control button (iPhone 16 and later)

    private func configureSystemControls(for device: AVCaptureDevice) {
        guard #available(iOS 18.0, *) else { return }
        guard session.supportsControls else { return }
        session.setControlsDelegate(self, queue: sessionQueue)
        for control in session.controls {
            session.removeControl(control)
        }
        let zoom = AVCaptureSystemZoomSlider(device: device)
        let bias = AVCaptureSystemExposureBiasSlider(device: device)
        for control in [zoom, bias] as [AVCaptureControl] where session.canAddControl(control) {
            session.addControl(control)
        }
    }

    // MARK: Capabilities

    private func computeCapabilities(device: AVCaptureDevice, mode: CaptureMode) -> LensCapabilities {
        var caps = LensCapabilities()
        caps.combos = Self.videoCombos(for: device)

        var codecs: [VideoCodec] = [.hevc, .h264]
        if mode == .video {
            let available = movieOutput.availableVideoCodecTypes
            codecs = VideoCodec.allCases.filter { codec in
                codec.candidates.contains { available.contains($0) }
            }
            if codecs.contains(.proRes) { proResSeen.insert(device.uniqueID) }
        }
        // ProRes may be offered by other formats even if not by the current one.
        if !codecs.contains(.proRes),
           proResSeen.contains(device.uniqueID) || Self.deviceSupportsProRes(device) {
            codecs.append(.proRes)
        }
        caps.codecs = codecs

        if mode == .photo {
            var formats: [PhotoFormat] = []
            if photoOutput.availablePhotoCodecTypes.contains(.hevc) { formats.append(.heif) }
            formats.append(.jpeg)
            if bayerRAWSupport[device.uniqueID] == true { formats.append(.raw) }
            if photoOutput.isAppleProRAWSupported { formats.append(.proRAW) }
            cachedPhotoFormats = formats
        }
        caps.photoFormats = cachedPhotoFormats

        caps.stabilizations = Stabilization.allCases.filter {
            $0 == .off || device.activeFormat.isVideoStabilizationModeSupported($0.mode)
        }
        let maxArea = device.activeFormat.supportedMaxPhotoDimensions
            .map { Int($0.width) * Int($0.height) }.max() ?? 0
        caps.supportsMaxPhotoResolution = maxArea > 13_000_000
        caps.hasFlash = device.hasFlash
        caps.hasTorch = device.hasTorch
        caps.supportsManualFocus = device.isLockingFocusWithCustomLensPositionSupported
        caps.supportsManualExposure = device.isExposureModeSupported(.custom)
        caps.supportsManualWhiteBalance = device.isLockingWhiteBalanceWithCustomDeviceGainsSupported
        return caps
    }

    private static func deviceSupportsProRes(_ device: AVCaptureDevice) -> Bool {
        device.formats.contains { tenBit422.contains(CMFormatDescriptionGetMediaSubType($0.formatDescription)) }
    }

    private struct Ranges {
        var iso: [Double]
        var shutter: [Double]
        var ev: [Double]
        var zoom: [Double]
    }

    private func computeRanges(device: AVCaptureDevice, settings s: CameraSettings) -> Ranges {
        let format = device.activeFormat
        let minISO = Double(format.minISO)
        let maxISO = Double(format.maxISO)
        var iso = Stops.iso.filter { $0 > minISO * 1.05 && $0 < maxISO * 0.95 }
        iso.insert(minISO.rounded(), at: 0)
        iso.append(maxISO.rounded())

        let minShutter = format.minExposureDuration.seconds
        var maxShutter = format.maxExposureDuration.seconds
        if s.mode == .video {
            maxShutter = min(maxShutter, 1 / Double(s.fps))
        }
        var shutter = Stops.shutter.filter { $0 >= minShutter && $0 <= maxShutter + 0.000_01 }
        if shutter.isEmpty { shutter = [maxShutter] }

        let ev = Stops.ev(range: device.minExposureTargetBias...device.maxExposureTargetBias)
        let maxZoom = min(Double(device.maxAvailableVideoZoomFactor), device.position == .front ? 5 : 10)
        let zoom = Stops.zoom(max: max(maxZoom, 1))
        return Ranges(iso: iso, shutter: shutter, ev: ev, zoom: zoom)
    }

    // MARK: Descriptions for the log

    private static func short(_ s: CameraSettings) -> String {
        "\(s.resolution.title) \(s.fps)fps \(s.profile.title)"
    }

    private func describe(_ s: CameraSettings, lens: Lens, codec: VideoCodec?) -> String {
        switch s.mode {
        case .photo:
            return "Config FOTO · \(lens.kind.name) · \(s.photoFormat.title) · \(s.photoResolution.title)"
        case .video:
            return "Config VIDEO · \(lens.kind.name) · \(s.resolution.title) \(s.fps)fps · \(codec?.title ?? "?") · \(s.profile.longTitle) · Stab. \(s.stabilization.title)"
        }
    }

    // MARK: - Frame routing (main thread)

    func updateFrameRouting() {
        guard let assists else { return }
        let profile = settings.profile
        let mode = settings.mode
        let processed = analysisAvailable && assists.needsProcessedPreview(profile: profile, mode: mode)
        let needsFrames = analysisAvailable && assists.needsFrames(profile: profile, mode: mode)
        if processedPreviewActive != processed { processedPreviewActive = processed }
        previewView?.metalView.setActive(processed)
        frameProcessor.histogramEnabled = assists.histogram != .off
        if assists.histogram == .off || !analysisAvailable, histogram.value != nil {
            histogram.value = nil
        }
        sessionQueue.async { [self] in
            if let connection = videoDataOutput.connection(with: .video), connection.isEnabled != needsFrames {
                connection.isEnabled = needsFrames
            }
        }
    }

    /// Main thread, called by the Metal view every frame.
    func assistSnapshot() -> AssistSnapshot {
        guard let assists else { return AssistSnapshot() }
        var s = AssistSnapshot()
        s.applyLogLUT = settings.mode == .video && settings.profile == .appleLog && assists.logViewLUT
        s.look = assists.look
        s.peaking = assists.peaking
        s.peakingColor = assists.peakingColor.ciColor
        s.zebra = assists.zebra
        s.zebraThreshold = Float(assists.zebraThreshold)
        s.falseColor = assists.falseColor
        return s
    }

    // MARK: - Telemetry (main thread)

    func startTelemetry() {
        guard telemetryTimer == nil else { return }
        UIDevice.current.isBatteryMonitoringEnabled = true
        telemetryTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.pollTelemetry()
        }
    }

    func stopTelemetry() {
        telemetryTimer?.invalidate()
        telemetryTimer = nil
    }

    private func pollTelemetry() {
        guard let device = currentLens?.device else { return }
        let t = telemetry

        let iso = Double(device.iso)
        if abs(t.iso - iso) > 0.5 { t.iso = iso }
        let shutter = device.exposureDuration.seconds
        if shutter.isFinite, abs(t.shutter - shutter) > 0.000_001 { t.shutter = shutter }

        let wb = device.temperatureAndTintValues(for: device.deviceWhiteBalanceGains)
        let temperature = Double(wb.temperature)
        let tint = Double(wb.tint)
        if temperature.isFinite, abs(t.temperature - temperature) > 15 { t.temperature = temperature }
        if tint.isFinite, abs(t.tint - tint) > 1 { t.tint = tint }

        let lens = Double(device.lensPosition)
        if abs(t.lensPosition - lens) > 0.004 { t.lensPosition = lens }
        let offset = Double(device.exposureTargetOffset)
        if offset.isFinite, abs(t.exposureOffset - offset) > 0.03 { t.exposureOffset = offset }
        let bias = Double(device.exposureTargetBias)
        if abs(t.exposureBias - bias) > 0.01 { t.exposureBias = bias }
        let zoom = Double(device.videoZoomFactor)
        if abs(t.zoom - zoom) > 0.01 { t.zoom = zoom }
        if t.isAdjustingFocus != device.isAdjustingFocus { t.isAdjustingFocus = device.isAdjustingFocus }

        if isRecording {
            let seconds = movieOutput.recordedDuration.seconds
            if seconds.isFinite { t.recordedSeconds = seconds }
        } else if t.recordedSeconds != 0 {
            t.recordedSeconds = 0
        }

        if settings.mode == .video, let channel = movieOutput.connection(with: .audio)?.audioChannels.first {
            let level = max(0, min(1, (Double(channel.averagePowerLevel) + 50) / 50))
            let peak = max(0, min(1, (Double(channel.peakHoldLevel) + 50) / 50))
            if abs(t.audioLevel - level) > 0.01 { t.audioLevel = level }
            if abs(t.audioPeak - peak) > 0.01 { t.audioPeak = peak }
        } else if t.audioLevel != 0 {
            t.audioLevel = 0
            t.audioPeak = 0
        }

        telemetryTick += 1
        if telemetryTick % 20 == 1 {
            let battery = Double(UIDevice.current.batteryLevel)
            t.batteryLevel = battery < 0 ? 1 : battery
            let state = UIDevice.current.batteryState
            t.batteryCharging = state == .charging || state == .full
            t.freeBytes = MediaLibrary.availableBytes()
            t.thermal = ProcessInfo.processInfo.thermalState
        }
    }

    /// Estimated minutes of video that still fit on the device.
    func estimatedMinutesLeft(freeBytes: Int64) -> Double {
        let s = settings
        let pixels = Double(s.resolution.width) * Double(s.resolution.height)
        let codec = activeCodec ?? s.codec
        let bitsPerSecond = pixels * Double(s.fps) * codec.bitsPerPixel + 256_000
        return Double(freeBytes) * 8 / bitsPerSecond / 60
    }

    // MARK: - Notifications

    private func observeNotifications() {
        let center = NotificationCenter.default
        center.addObserver(forName: Notification.Name("AVCaptureSessionRuntimeErrorNotification"),
                           object: session, queue: .main) { [weak self] note in
            let error = note.userInfo?["AVCaptureSessionErrorKey"] as? NSError
            camLog("Errore sessione: \(error?.localizedDescription ?? "sconosciuto")", .error)
            if error?.code == AVError.Code.mediaServicesWereReset.rawValue {
                camLog("Servizi media riavviati: riparto", .warning)
                self?.resume()
            }
        }
        center.addObserver(forName: Notification.Name("AVCaptureSessionWasInterruptedNotification"),
                           object: session, queue: .main) { note in
            let raw = note.userInfo?["AVCaptureSessionInterruptionReasonKey"] as? Int ?? 0
            let reason: String
            switch AVCaptureSession.InterruptionReason(rawValue: raw) {
            case .videoDeviceNotAvailableInBackground: reason = "app in background"
            case .audioDeviceInUseByAnotherClient: reason = "microfono usato da un'altra app"
            case .videoDeviceInUseByAnotherClient: reason = "fotocamera usata da un'altra app"
            case .videoDeviceNotAvailableWithMultipleForegroundApps: reason = "multitasking"
            case .videoDeviceNotAvailableDueToSystemPressure: reason = "surriscaldamento"
            default: reason = "motivo sconosciuto"
            }
            camLog("Sessione interrotta: \(reason)", .warning)
        }
        center.addObserver(forName: Notification.Name("AVCaptureSessionInterruptionEndedNotification"),
                           object: session, queue: .main) { _ in
            camLog("Interruzione terminata", .success)
        }
        center.addObserver(forName: AVCaptureDevice.subjectAreaDidChangeNotification,
                           object: nil, queue: .main) { [weak self] _ in
            self?.subjectAreaDidChange()
        }
        center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification,
                           object: nil, queue: .main) { _ in
            let state = ProcessInfo.processInfo.thermalState
            switch state {
            case .serious: camLog("Temperatura alta: possibili cali di prestazioni", .warning)
            case .critical: camLog("Temperatura critica! Lascia raffreddare il telefono", .error)
            default: camLog("Temperatura nella norma")
            }
        }
    }
}

// MARK: - Camera Control delegate

@available(iOS 18.0, *)
extension CameraController: AVCaptureSessionControlsDelegate {
    func sessionControlsDidBecomeActive(_ session: AVCaptureSession) {
        camLog("Tasto Fotocamera attivo")
    }

    func sessionControlsWillEnterFullscreenAppearance(_ session: AVCaptureSession) {
        DispatchQueue.main.async { self.systemControlsActive = true }
    }

    func sessionControlsWillExitFullscreenAppearance(_ session: AVCaptureSession) {
        DispatchQueue.main.async { self.systemControlsActive = false }
    }

    func sessionControlsDidBecomeInactive(_ session: AVCaptureSession) {
        DispatchQueue.main.async { self.systemControlsActive = false }
    }
}
