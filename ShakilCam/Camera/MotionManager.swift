import CoreMotion
import Foundation
import SwiftUI

/// Fast-changing horizon data (30×/s). Only the level overlay observes it.
final class LevelModel: ObservableObject {
    /// Angle of gravity in the screen plane, in degrees. 0 = upright portrait,
    /// -90 = rotated counter-clockwise (landscape left), +90 = landscape right.
    @Published fileprivate(set) var gravityAngle: Double = 0
    @Published fileprivate(set) var isFlat = false

    /// Deviation from the nearest level orientation, in degrees.
    var tilt: Double {
        let snapped = (gravityAngle / 90).rounded() * 90
        return gravityAngle - snapped
    }

    var isLevel: Bool { abs(tilt) < 1.0 && !isFlat }
}

/// Reads gravity to drive the horizon level and to rotate the UI icons when the
/// phone is turned sideways (the interface itself stays locked in portrait).
final class MotionManager: ObservableObject {
    /// Rotation to apply to icons/text so they stay upright for the user.
    /// Changes only when the phone is turned, so observing it is cheap.
    @Published private(set) var iconRotation: Double = 0

    let level = LevelModel()

    private let manager = CMMotionManager()
    private var isRunning = false

    var isLandscape: Bool { abs(abs(iconRotation) - 90) < 1 }

    func start() {
        guard !isRunning, manager.isDeviceMotionAvailable else { return }
        isRunning = true
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let g = motion?.gravity else { return }
            let level = self.level

            let flat = abs(g.z) > 0.85
            if level.isFlat != flat { level.isFlat = flat }
            guard !flat else { return }

            let angle = atan2(g.x, -g.y) * 180 / .pi
            // Light smoothing so the level does not jitter.
            var delta = angle - level.gravityAngle
            if delta > 180 { delta -= 360 }
            if delta < -180 { delta += 360 }
            var smoothed = level.gravityAngle + delta * 0.35
            if smoothed > 180 { smoothed -= 360 }
            if smoothed < -180 { smoothed += 360 }
            if abs(smoothed - level.gravityAngle) > 0.05 { level.gravityAngle = smoothed }

            let rotation: Double
            switch angle {
            case -45...45: rotation = 0
            case -135 ..< -45: rotation = 90
            case 45...135: rotation = -90
            default: rotation = 180
            }
            if rotation != self.iconRotation {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    self.iconRotation = rotation
                }
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        manager.stopDeviceMotionUpdates()
    }
}
