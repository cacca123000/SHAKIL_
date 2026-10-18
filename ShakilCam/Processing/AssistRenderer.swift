import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Immutable copy of the assist settings, taken on the main thread each frame.
struct AssistSnapshot {
    var applyLogLUT = false
    var look: LookPreset = .natural
    var peaking = false
    var peakingColor: CIColor = CIColor(red: 1, green: 0.15, blue: 0.15)
    var zebra = false
    var zebraThreshold: Float = 0.95
    var falseColor = false
}

/// Builds the Core Image graph for the processed viewfinder. All filters run on the
/// GPU at screen resolution, in a context with color management disabled so the
/// math works directly on the camera's code values.
enum AssistRenderer {
    static func process(_ input: CIImage, _ s: AssistSnapshot) -> CIImage {
        var image = input

        if s.applyLogLUT {
            image = applyCube(image, data: ColorCubes.appleLogToRec709)
        }
        if let cube = ColorCubes.cube(for: s.look) {
            image = applyCube(image, data: cube)
        }

        let base = image

        if s.falseColor {
            let map = CIFilter.colorMap()
            map.inputImage = base
            map.gradientImage = ColorCubes.falseColorGradient
            image = map.outputImage?.cropped(to: base.extent) ?? image
        }

        if s.zebra {
            image = zebra(over: image, source: base, threshold: s.zebraThreshold)
        }

        if s.peaking {
            image = peaking(over: image, source: base, color: s.peakingColor)
        }

        return image
    }

    static func applyCube(_ image: CIImage, data: Data) -> CIImage {
        let cube = CIFilter.colorCube()
        cube.inputImage = image
        cube.cubeDimension = Float(ColorCubes.size)
        cube.cubeData = data
        return cube.outputImage ?? image
    }

    private static func luma(_ image: CIImage) -> CIImage {
        let controls = CIFilter.colorControls()
        controls.inputImage = image
        controls.saturation = 0
        controls.brightness = 0
        controls.contrast = 1
        return controls.outputImage ?? image
    }

    /// Diagonal stripes over areas brighter than `threshold`.
    private static func zebra(over image: CIImage, source: CIImage, threshold: Float) -> CIImage {
        let extent = source.extent

        let thresholdFilter = CIFilter.colorThreshold()
        thresholdFilter.inputImage = luma(source)
        thresholdFilter.threshold = threshold
        guard let mask = thresholdFilter.outputImage else { return image }

        let stripes = CIFilter.stripesGenerator()
        stripes.color0 = CIColor(red: 1, green: 1, blue: 1)
        stripes.color1 = CIColor(red: 0.05, green: 0.05, blue: 0.05)
        stripes.width = 5
        stripes.sharpness = 0.9
        stripes.center = .zero
        guard let pattern = stripes.outputImage?
            .transformed(by: CGAffineTransform(rotationAngle: .pi / 4))
            .cropped(to: extent)
        else { return image }

        let blend = CIFilter.blendWithMask()
        blend.inputImage = pattern
        blend.backgroundImage = image
        blend.maskImage = mask
        return blend.outputImage?.cropped(to: extent) ?? image
    }

    /// Colors the sharpest edges, i.e. what is in focus.
    private static func peaking(over image: CIImage, source: CIImage, color: CIColor) -> CIImage {
        let extent = source.extent

        let edges = CIFilter.edges()
        edges.inputImage = luma(source).clampedToExtent()
        edges.intensity = 6
        guard let edgeImage = edges.outputImage?.cropped(to: extent) else { return image }

        let thresholdFilter = CIFilter.colorThreshold()
        thresholdFilter.inputImage = luma(edgeImage)
        thresholdFilter.threshold = 0.35
        guard let mask = thresholdFilter.outputImage else { return image }

        let solid = CIImage(color: color).cropped(to: extent)
        let blend = CIFilter.blendWithMask()
        blend.inputImage = solid
        blend.backgroundImage = image
        blend.maskImage = mask
        return blend.outputImage?.cropped(to: extent) ?? image
    }
}
