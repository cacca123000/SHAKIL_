import AVFoundation
import UIKit

/// Shutter, self-timer, photo capture and video recording.
extension CameraController {
    // MARK: - Shutter

    func shutterPressed() {
        guard isRunning, !isReconfiguring else { return }
        switch settings.mode {
        case .photo:
            if countdown != nil {
                cancelCountdown()
            } else if settings.timer != .off {
                startCountdown()
            } else {
                capturePhoto()
            }
        case .video:
            if isRecording { stopRecording() } else { startRecording() }
        }
    }

    // MARK: - Self timer

    private func startCountdown() {
        countdown = settings.timer.rawValue
        camLog("Autoscatto: \(settings.timer.rawValue) secondi")
        Haptics.light()
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.countdownTick()
        }
    }

    private func countdownTick() {
        guard let current = countdown else {
            cancelCountdown()
            return
        }
        if current <= 1 {
            countdownTimer?.invalidate()
            countdownTimer = nil
            countdown = nil
            capturePhoto()
        } else {
            countdown = current - 1
            Haptics.light()
        }
    }

    func cancelCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        if countdown != nil {
            countdown = nil
            camLog("Autoscatto annullato", .warning)
        }
    }

    // MARK: - Photo

    func capturePhoto() {
        guard settings.mode == .photo else { return }
        let requested = settings
        let angle = captureRotationAngle
        let look = assists?.look ?? .natural
        let lensName = currentLens?.kind.name ?? ""

        sessionQueue.async { [self] in
            guard session.outputs.contains(photoOutput),
                  let connection = photoOutput.connection(with: .video) else {
                camLog("Uscita foto non pronta", .error)
                return
            }
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }

            let (photoSettings, codec, isRAW) = makePhotoSettings(requested)
            let id = photoSettings.uniqueID
            let processor = PhotoCaptureProcessor(
                processedCodec: codec,
                look: isRAW ? .natural : look,
                willCapture: { [weak self] in self?.blinkShutter() },
                completion: { [weak self] result, error in
                    self?.photoFinished(id: id, result: result, error: error, format: requested.photoFormat, lensName: lensName)
                }
            )
            photoProcessors[id] = processor
            photoOutput.capturePhoto(with: photoSettings, delegate: processor)
        }
    }

    /// Session queue.
    private func makePhotoSettings(_ s: CameraSettings) -> (AVCapturePhotoSettings, AVVideoCodecType, Bool) {
        let useHEVC = s.photoFormat != .jpeg && photoOutput.availablePhotoCodecTypes.contains(.hevc)
        let codec: AVVideoCodecType = useHEVC ? .hevc : .jpeg
        var photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: codec])
        var isRAW = false

        if s.photoFormat.isRAW {
            let wantsProRAW = s.photoFormat == .proRAW
            let rawType = photoOutput.availableRawPhotoPixelFormatTypes.first { type in
                wantsProRAW ? AVCapturePhotoOutput.isAppleProRAWPixelFormat(type)
                    : AVCapturePhotoOutput.isBayerRAWPixelFormat(type)
            }
            if let rawType {
                photoSettings = AVCapturePhotoSettings(rawPixelFormatType: rawType, processedFormat: [AVVideoCodecKey: codec])
                isRAW = true
            } else {
                camLog("\(s.photoFormat.title) non disponibile ora: salvo solo \(useHEVC ? "HEIF" : "JPEG")", .warning)
            }
        }

        if !(isRAW && s.photoFormat == .raw) {
            photoSettings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
        }
        if let device = sessionDevice, device.hasFlash, photoOutput.supportedFlashModes.contains(s.flash.mode) {
            photoSettings.flashMode = s.flash.mode
        }
        if !isRAW {
            photoSettings.photoQualityPrioritization = photoOutput.maxPhotoQualityPrioritization
        }
        return (photoSettings, codec, isRAW)
    }

    private func blinkShutter() {
        Haptics.rigid()
        DispatchQueue.main.async { [self] in
            shutterBlink = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.shutterBlink = false
            }
        }
    }

    private func photoFinished(id: Int64, result: PhotoCaptureProcessor.Result?, error: Error?, format: PhotoFormat, lensName: String) {
        sessionQueue.async { [self] in photoProcessors[id] = nil }

        guard let result else {
            camLog("Scatto fallito: \(error?.localizedDescription ?? "nessun dato")", .error)
            Haptics.warning()
            return
        }

        DispatchQueue.main.async { [self] in
            let mainURL = result.processedURL ?? result.rawURL
            guard let mainURL else { return }
            let media = CapturedMedia(
                kind: .photo, url: mainURL, rawURL: result.rawURL, thumbnail: result.thumbnail,
                date: Date(), details: [lensName] + result.details, savedToPhotos: false
            )
            captures.insert(media, at: 0)
            let size = Format.bytes(MediaLibrary.fileSize(mainURL) + (result.rawURL.map(MediaLibrary.fileSize) ?? 0))
            camLog("Foto \(format.title) · \(result.details.prefix(3).joined(separator: " · ")) · \(size)", .capture)

            MediaLibrary.savePhoto(processedURL: result.processedURL, rawURL: result.rawURL) { [weak self] success, error in
                self?.markSaved(media.id, success: success, error: error)
            }
        }
    }

    private func markSaved(_ id: UUID, success: Bool, error: Error?) {
        if success {
            if let index = captures.firstIndex(where: { $0.id == id }) {
                captures[index].savedToPhotos = true
            }
            camLog("Salvato nella libreria Foto", .success)
        } else if let error {
            camLog("Salvataggio in Foto fallito: \(error.localizedDescription)", .error)
        } else {
            camLog("Accesso a Foto negato: il file resta solo nell'app", .warning)
        }
    }

    // MARK: - Video

    func startRecording() {
        guard settings.mode == .video, !isRecording else { return }
        let angle = captureRotationAngle
        let summary = "\(settings.resolution.title) \(settings.fps)fps · \((activeCodec ?? settings.codec).title) · \(settings.profile.longTitle)"
        Haptics.medium()
        sessionQueue.async { [self] in
            guard session.outputs.contains(movieOutput), !movieOutput.isRecording,
                  let connection = movieOutput.connection(with: .video) else {
                camLog("Uscita video non pronta", .error)
                return
            }
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
            let url = MediaLibrary.newFileURL("mov")
            movieOutput.startRecording(to: url, recordingDelegate: self)
            camLog("● REC — \(summary)", .capture)
        }
    }

    func stopRecording() {
        Haptics.medium()
        sessionQueue.async { [self] in
            if movieOutput.isRecording {
                movieOutput.stopRecording()
            }
        }
    }
}

// MARK: - Recording delegate

extension CameraController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        DispatchQueue.main.async {
            self.isRecording = true
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        let seconds = output.recordedDuration.seconds
        var success = true
        if let error = error as NSError? {
            success = (error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) ?? false
            if !success {
                camLog("Registrazione interrotta: \(error.localizedDescription)", .error)
            }
        }

        guard success else {
            DispatchQueue.main.async {
                self.isRecording = false
                UIApplication.shared.isIdleTimerDisabled = false
            }
            try? FileManager.default.removeItem(at: outputFileURL)
            return
        }

        DispatchQueue.main.async { [self] in
            isRecording = false
            UIApplication.shared.isIdleTimerDisabled = false

            let fps = settings.fps
            let details = [
                currentLens?.kind.name ?? "",
                settings.resolution.title, "\(fps) fps",
                (activeCodec ?? settings.codec).title, settings.profile.title,
                Format.timecode(seconds, fps: fps),
            ]
            let size = Format.bytes(MediaLibrary.fileSize(outputFileURL))
            camLog("■ STOP — \(Format.timecode(seconds, fps: fps)) · \(size)", .capture)

            Task {
                let thumbnail = await MediaLibrary.videoThumbnail(for: outputFileURL)
                DispatchQueue.main.async { [self] in
                    let media = CapturedMedia(
                        kind: .video, url: outputFileURL, rawURL: nil, thumbnail: thumbnail,
                        date: Date(), details: details, savedToPhotos: false
                    )
                    captures.insert(media, at: 0)
                    MediaLibrary.saveVideo(outputFileURL) { [weak self] success, error in
                        self?.markSaved(media.id, success: success, error: error)
                    }
                }
            }
        }
    }
}
