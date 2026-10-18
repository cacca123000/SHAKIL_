import AVKit
import SwiftUI

/// Photos and videos taken in this session. Everything is also in the Photos app.
struct GalleryView: View {
    @EnvironmentObject private var camera: CameraController
    @Environment(\.dismiss) private var dismiss
    @State private var selected: CapturedMedia?

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 3)]

    var body: some View {
        NavigationStack {
            Group {
                if camera.captures.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 46, weight: .thin))
                            .foregroundStyle(Theme.accent)
                        Text("Ancora nessuno scatto")
                            .font(Theme.rounded(17, .bold))
                        Text("Foto e video di questa sessione appaiono qui.\nSono salvati anche nell'app Foto.")
                            .font(.system(size: 13))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 3) {
                            ForEach(camera.captures) { media in
                                Button {
                                    selected = media
                                } label: {
                                    GalleryCell(media: media)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 3)
                    }
                }
            }
            .background(Color.black)
            .navigationTitle("Sessione · \(camera.captures.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Chiudi") { dismiss() }
                        .tint(Theme.accent)
                }
            }
            .navigationDestination(item: $selected) { media in
                MediaDetailView(media: media)
            }
        }
        .preferredColorScheme(.dark)
    }
}

extension CapturedMedia: Hashable {
    static func == (lhs: CapturedMedia, rhs: CapturedMedia) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct GalleryCell: View {
    let media: CapturedMedia

    var body: some View {
        Color.black
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let thumbnail = media.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: media.kind == .video ? "video" : "photo")
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .clipped()
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 3) {
                    if media.kind == .video {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9))
                    }
                    if media.rawURL != nil {
                        Text("RAW")
                            .font(Theme.mono(8, .heavy))
                    }
                }
                .foregroundStyle(.white)
                .padding(4)
                .shadow(radius: 3)
            }
            .overlay(alignment: .topTrailing) {
                if media.savedToPhotos {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.ok)
                        .padding(4)
                }
            }
    }
}

struct MediaDetailView: View {
    let media: CapturedMedia
    @State private var player: AVPlayer?
    @State private var fullImage: UIImage?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                switch media.kind {
                case .photo:
                    if let image = fullImage ?? media.thumbnail {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                    }
                case .video:
                    if let player {
                        VideoPlayer(player: player)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 10) {
                FlowChips(items: media.details.filter { !$0.isEmpty })
                HStack {
                    Label(media.savedToPhotos ? "Salvato in Foto" : "Solo nell'app",
                          systemImage: media.savedToPhotos ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(media.savedToPhotos ? Theme.ok : Theme.accent)
                    Spacer()
                    Text(Format.bytes(MediaLibrary.fileSize(media.url) + (media.rawURL.map(MediaLibrary.fileSize) ?? 0)))
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(16)
            .background(Theme.panel)
        }
        .background(Color.black)
        .navigationTitle(media.date.formatted(date: .omitted, time: .standard))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: media.url)
            }
        }
        .task {
            switch media.kind {
            case .video:
                player = AVPlayer(url: media.url)
            case .photo:
                let url = media.url
                let image = await Task.detached(priority: .userInitiated) {
                    MediaLibrary.thumbnail(for: url, maxPixel: 2400)
                }.value
                fullImage = image
            }
        }
        .onDisappear { player?.pause() }
    }
}

/// Wrapping row of metadata chips.
struct FlowChips: View {
    let items: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items.indices, id: \.self) { index in
                    Text(items[index])
                        .font(Theme.mono(11, .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Theme.panelStrong))
                }
            }
        }
    }
}
