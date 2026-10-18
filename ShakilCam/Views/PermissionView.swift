import SwiftUI

struct PermissionView: View {
    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            ApertureLogo(size: 92)
            VStack(spacing: 8) {
                Text("Serve la fotocamera")
                    .font(Theme.rounded(24, .heavy))
                Text("Shakil Cam ha bisogno dell'accesso alla fotocamera per funzionare. Il microfono serve per l'audio dei video, la libreria Foto per salvare i tuoi scatti.")
                    .font(.system(size: 14))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 30)
            }
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Apri Impostazioni")
                    .font(Theme.rounded(16, .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(Theme.accent))
            }
            .buttonStyle(PressableStyle())
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }
}

struct SplashView: View {
    @State private var spin = false

    var body: some View {
        VStack(spacing: 18) {
            ApertureLogo(size: 76)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .animation(.linear(duration: 6).repeatForever(autoreverses: false), value: spin)
            Text("SHAKIL CAM")
                .font(Theme.rounded(15, .heavy))
                .tracking(5)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .onAppear { spin = true }
    }
}

/// Six-blade aperture drawn in code (same motif as the app icon).
struct ApertureLogo: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Theme.accent, lineWidth: size * 0.06)
            ForEach(0..<6) { i in
                BladeShape()
                    .fill(Theme.accent.opacity(i % 2 == 0 ? 1 : 0.75))
                    .rotationEffect(.degrees(Double(i) * 60))
            }
            .padding(size * 0.14)
            Circle()
                .fill(Color.black)
                .frame(width: size * 0.22, height: size * 0.22)
        }
        .frame(width: size, height: size)
    }
}

struct BladeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        var path = Path()
        path.move(to: CGPoint(x: c.x + r * 0.12, y: c.y - r * 0.2))
        path.addLine(to: CGPoint(x: c.x + r * 0.2, y: c.y - r))
        path.addQuadCurve(to: CGPoint(x: c.x + r * 0.86, y: c.y - r * 0.5),
                          control: CGPoint(x: c.x + r * 0.62, y: c.y - r * 0.92))
        path.closeSubpath()
        return path
    }
}
