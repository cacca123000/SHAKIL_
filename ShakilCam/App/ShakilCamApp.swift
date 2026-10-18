import SwiftUI

@main
struct ShakilCamApp: App {
    @StateObject private var camera = CameraController()
    @StateObject private var assists = AssistSettings()
    @StateObject private var motion = MotionManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(camera)
                .environmentObject(camera.telemetry)
                .environmentObject(camera.histogram)
                .environmentObject(assists)
                .environmentObject(motion)
                .environmentObject(motion.level)
                .environmentObject(CameraLog.shared)
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
                .onAppear {
                    camera.attach(assists: assists)
                    motion.start()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                camera.resume()
                motion.start()
            case .background:
                camera.suspend()
                motion.stop()
            default:
                break
            }
        }
    }
}

/// Decides between the permission screen and the camera.
struct RootView: View {
    @EnvironmentObject private var camera: CameraController

    var body: some View {
        Group {
            switch camera.authorization {
            case .authorized:
                CameraScreen()
            case .denied:
                PermissionView()
            case .unknown:
                SplashView()
            }
        }
        .task { await camera.requestAccessAndStart() }
    }
}
