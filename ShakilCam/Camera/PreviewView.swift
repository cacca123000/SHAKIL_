import AVFoundation
import AVKit
import CoreImage
import MetalKit
import UIKit

/// Viewfinder: the system preview layer (zero-cost, HDR aware) with a Metal view on
/// top that takes over when a processed preview (LUT, peaking, zebra…) is needed.
final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // layerClass guarantees the type.
        layer as! AVCaptureVideoPreviewLayer
    }

    let metalView = MetalPreviewView()

    var onTap: ((CGPoint) -> Void)?
    var onLongPress: ((CGPoint) -> Void)?
    var onPinch: ((CGFloat, UIGestureRecognizer.State) -> Void)?
    var onHardwareShutter: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        previewLayer.videoGravity = .resizeAspect

        metalView.isHidden = true
        metalView.isUserInteractionEnabled = false
        addSubview(metalView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.55
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        addGestureRecognizer(tap)
        addGestureRecognizer(longPress)
        addGestureRecognizer(pinch)

        // Volume buttons (and Camera Control on iPhone 16+) act as the shutter.
        if #available(iOS 17.2, *) {
            let interaction = AVCaptureEventInteraction(handler: { [weak self] event in
                if event.phase == .ended {
                    self?.onHardwareShutter?()
                }
            })
            addInteraction(interaction)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        metalView.frame = bounds
    }

    /// Rectangle actually covered by the video inside this view (aspect fit).
    var videoRect: CGRect {
        previewLayer.layerRectConverted(fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        onTap?(gesture.location(in: self))
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            onLongPress?(gesture.location(in: self))
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        onPinch?(gesture.scale, gesture.state)
    }
}

/// Renders the newest camera frame through `AssistRenderer` with Core Image + Metal.
final class MetalPreviewView: MTKView, MTKViewDelegate {
    weak var frameSource: FrameProcessor?
    /// Called on the main thread for every rendered frame.
    var snapshotProvider: (() -> AssistSnapshot)?

    private let commandQueue: MTLCommandQueue?
    private let ciContext: CIContext?
    private let deviceRGB = CGColorSpaceCreateDeviceRGB()

    init() {
        let device = MTLCreateSystemDefaultDevice()
        let queue = device?.makeCommandQueue()
        commandQueue = queue
        if let queue {
            ciContext = CIContext(mtlCommandQueue: queue, options: [
                .workingColorSpace: NSNull(),
                .cacheIntermediates: false,
            ])
        } else {
            ciContext = nil
        }
        super.init(frame: .zero, device: device)
        framebufferOnly = false
        colorPixelFormat = .bgra8Unorm
        enableSetNeedsDisplay = false
        preferredFramesPerSecond = 30
        isPaused = true
        backgroundColor = .black
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        delegate = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setActive(_ active: Bool) {
        guard active != !isHidden else { return }
        isHidden = !active
        isPaused = !active
        if !active { frameSource?.reset() }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let ciContext,
              let commandQueue,
              let source = frameSource?.latestImage(),
              let drawable = currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer()
        else { return }

        let target = drawableSize
        guard target.width > 0, target.height > 0, source.extent.width > 0 else { return }

        // Aspect-fit exactly like the preview layer (.resizeAspect).
        let scale = min(target.width / source.extent.width, target.height / source.extent.height)
        var image = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        image = image.transformed(by: CGAffineTransform(
            translationX: (target.width - image.extent.width) / 2 - image.extent.minX,
            y: (target.height - image.extent.height) / 2 - image.extent.minY
        ))

        if let snapshot = snapshotProvider?() {
            image = AssistRenderer.process(image, snapshot)
        }

        let bounds = CGRect(origin: .zero, size: target)
        let background = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: bounds)
        let output = image.composited(over: background)

        ciContext.render(output, to: drawable.texture, commandBuffer: commandBuffer,
                         bounds: bounds, colorSpace: deviceRGB)
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
