import AVFoundation
import UIKit

/// Manual controls: exposure, white balance, focus, zoom, torch, tap to focus.
/// Public methods are called on the main thread; device work hops to `sessionQueue`.
extension CameraController {
    // MARK: - Exposure

    func setISO(_ iso: Double) {
        if !exposureManual {
            manualShutter = clampShutter(telemetry.shutter)
            exposureManual = true
            camLog("Esposizione manuale")
        }
        manualISO = iso
        applyCustomExposure()
    }

    func setShutter(_ seconds: Double) {
        if !exposureManual {
            manualISO = telemetry.iso > 0 ? telemetry.iso : manualISO
            exposureManual = true
            camLog("Esposizione manuale")
        }
        manualShutter = seconds
        applyCustomExposure()
    }

    private func clampShutter(_ value: Double) -> Double {
        guard let first = shutterStops.first, let last = shutterStops.last, value > 0 else { return 1.0 / 60 }
        return min(max(value, first), last)
    }

    func applyCustomExposure() {
        let iso = Float(manualISO)
        let seconds = manualShutter
        let maxForVideo = settings.mode == .video ? 1 / Double(settings.fps) : .infinity
        sessionQueue.async { [self] in
            withDeviceLock { device in
                guard device.isExposureModeSupported(.custom) else { return }
                let format = device.activeFormat
                let clampedISO = min(max(iso, format.minISO), format.maxISO)
                let minDuration = format.minExposureDuration
                var maxDuration = format.maxExposureDuration
                if maxForVideo.isFinite, maxDuration.seconds > maxForVideo {
                    maxDuration = CMTime(seconds: maxForVideo, preferredTimescale: 1_000_000)
                }
                let duration: CMTime
                if seconds <= minDuration.seconds {
                    duration = minDuration
                } else if seconds >= maxDuration.seconds {
                    duration = maxDuration
                } else {
                    duration = CMTime(seconds: seconds, preferredTimescale: 1_000_000)
                }
                device.setExposureModeCustom(duration: duration, iso: clampedISO, completionHandler: nil)
            }
        }
    }

    func setExposureAuto() {
        guard exposureManual || aeAfLocked else { return }
        exposureManual = false
        aeAfLocked = false
        camLog("Esposizione automatica")
        sessionQueue.async { [self] in
            withDeviceLock { device in
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
            }
        }
    }

    func setExposureBias(_ ev: Double) {
        let value = Float(ev)
        sessionQueue.async { [self] in
            withDeviceLock { device in
                let clamped = min(max(value, device.minExposureTargetBias), device.maxExposureTargetBias)
                device.setExposureTargetBias(clamped, completionHandler: nil)
            }
        }
    }

    // MARK: - White balance

    func setWhiteBalance(temperature: Double? = nil, tint: Double? = nil) {
        if !whiteBalanceManual {
            manualTemperature = telemetry.temperature
            manualTint = telemetry.tint
            whiteBalanceManual = true
            camLog("Bilanciamento del bianco manuale")
        }
        if let temperature { manualTemperature = temperature }
        if let tint { manualTint = tint }
        let values = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
            temperature: Float(manualTemperature), tint: Float(manualTint)
        )
        sessionQueue.async { [self] in
            withDeviceLock { device in
                guard device.isLockingWhiteBalanceWithCustomDeviceGainsSupported else { return }
                let gains = Self.clamp(device.deviceWhiteBalanceGains(for: values), max: device.maxWhiteBalanceGain)
                device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
            }
        }
    }

    func setWhiteBalanceAuto() {
        guard whiteBalanceManual else { return }
        whiteBalanceManual = false
        camLog("Bilanciamento del bianco automatico")
        sessionQueue.async { [self] in
            withDeviceLock { device in
                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                }
            }
        }
    }

    private static func clamp(_ gains: AVCaptureDevice.WhiteBalanceGains, max maxGain: Float) -> AVCaptureDevice.WhiteBalanceGains {
        var g = gains
        g.redGain = min(max(g.redGain, 1), maxGain)
        g.greenGain = min(max(g.greenGain, 1), maxGain)
        g.blueGain = min(max(g.blueGain, 1), maxGain)
        return g
    }

    // MARK: - Focus

    func setLensPosition(_ position: Double) {
        if !focusManual {
            focusManual = true
            camLog("Messa a fuoco manuale")
        }
        manualLensPosition = position
        let value = Float(min(max(position, 0), 1))
        sessionQueue.async { [self] in
            withDeviceLock { device in
                guard device.isLockingFocusWithCustomLensPositionSupported else { return }
                device.setFocusModeLocked(lensPosition: value, completionHandler: nil)
            }
        }
    }

    func setFocusAuto() {
        guard focusManual || aeAfLocked else { return }
        focusManual = false
        aeAfLocked = false
        camLog("Autofocus continuo")
        sessionQueue.async { [self] in
            withDeviceLock { device in
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
                }
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
            }
        }
    }

    /// Tap on the viewfinder: focus and meter on that point, keep tracking.
    func focus(at viewPoint: CGPoint) {
        guard let layer = previewView?.previewLayer else { return }
        let devicePoint = layer.captureDevicePointConverted(fromLayerPoint: viewPoint)
        guard (0...1).contains(devicePoint.x), (0...1).contains(devicePoint.y) else { return }
        focusIndicator = FocusIndicator(point: viewPoint, locked: false)
        aeAfLocked = false
        focusManual = false
        let keepExposure = exposureManual
        Haptics.light()
        sessionQueue.async { [self] in
            withDeviceLock { device in
                if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = .continuousAutoFocus
                }
                if !keepExposure, device.isExposurePointOfInterestSupported,
                   device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = .continuousAutoExposure
                }
                device.isSubjectAreaChangeMonitoringEnabled = true
            }
        }
    }

    /// Long press: focus and expose on the point, then lock both (AE/AF LOCK).
    func lockFocusAndExposure(at viewPoint: CGPoint) {
        guard let layer = previewView?.previewLayer else { return }
        let devicePoint = layer.captureDevicePointConverted(fromLayerPoint: viewPoint)
        guard (0...1).contains(devicePoint.x), (0...1).contains(devicePoint.y) else { return }
        focusIndicator = FocusIndicator(point: viewPoint, locked: true)
        aeAfLocked = true
        focusManual = false
        exposureManual = false
        Haptics.heavy()
        camLog("Blocco AE/AF")
        sessionQueue.async { [self] in
            withDeviceLock { device in
                if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = .autoExpose
                }
                device.isSubjectAreaChangeMonitoringEnabled = false
            }
        }
    }

    /// The scene changed a lot: go back to center-weighted continuous AF/AE.
    func subjectAreaDidChange() {
        guard !aeAfLocked, !focusManual else { return }
        focusIndicator = nil
        let keepExposure = exposureManual
        sessionQueue.async { [self] in
            withDeviceLock { device in
                let center = CGPoint(x: 0.5, y: 0.5)
                if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusPointOfInterest = center
                    device.focusMode = .continuousAutoFocus
                }
                if !keepExposure, device.isExposurePointOfInterestSupported,
                   device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposurePointOfInterest = center
                    device.exposureMode = .continuousAutoExposure
                }
                device.isSubjectAreaChangeMonitoringEnabled = false
            }
        }
    }

    // MARK: - Zoom

    func setZoom(_ factor: Double, animated: Bool = false) {
        let target = min(max(factor, zoomStops.first ?? 1), zoomStops.last ?? 1)
        sessionQueue.async { [self] in
            withDeviceLock { device in
                let z = min(max(CGFloat(target), device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
                if animated {
                    device.ramp(toVideoZoomFactor: z, withRate: 6)
                } else {
                    device.videoZoomFactor = z
                }
            }
        }
    }

    func handlePinch(scale: CGFloat, state: UIGestureRecognizer.State) {
        switch state {
        case .began:
            zoomAtPinchStart = telemetry.zoom
        case .changed:
            setZoom(zoomAtPinchStart * Double(scale))
        default:
            break
        }
    }

    // MARK: - Torch (video light)

    func toggleTorch() {
        guard capabilities.hasTorch else { return }
        let on = !torchOn
        torchOn = on
        camLog(on ? "Torcia accesa" : "Torcia spenta")
        sessionQueue.async { [self] in
            withDeviceLock { device in
                guard device.hasTorch else { return }
                if on, device.isTorchModeSupported(.on) {
                    try? device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
                } else if device.isTorchModeSupported(.off) {
                    device.torchMode = .off
                }
            }
        }
    }

    // MARK: - Reset

    func resetManualControls() {
        setExposureAuto()
        setWhiteBalanceAuto()
        setFocusAuto()
        setExposureBias(0)
        setZoom(1, animated: true)
        camLog("Controlli manuali azzerati")
    }

    // MARK: - Helpers (session queue)

    func withDeviceLock(_ body: (AVCaptureDevice) -> Void) {
        guard let device = sessionDevice else { return }
        do {
            try device.lockForConfiguration()
            body(device)
            device.unlockForConfiguration()
        } catch {
            camLog("Impossibile bloccare la fotocamera: \(error.localizedDescription)", .error)
        }
    }
}

/// Haptic feedback, safe to trigger from any thread.
enum Haptics {
    static func light() { impact(.light) }
    static func medium() { impact(.medium) }
    static func heavy() { impact(.heavy) }
    static func rigid() { impact(.rigid) }

    static func selection() {
        DispatchQueue.main.async { UISelectionFeedbackGenerator().selectionChanged() }
    }

    static func success() {
        DispatchQueue.main.async { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }

    static func warning() {
        DispatchQueue.main.async { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    }

    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        DispatchQueue.main.async { UIImpactFeedbackGenerator(style: style).impactOccurred() }
    }
}
