import SwiftUI
import AVKit

/// Video in a post: starts muted when visible, speaker button for sound, full controls from VideoPlayer.
struct PostVideoView: View {
    let url: URL
    @State private var player: AVPlayer?
    @State private var isMuted = true

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let player {
                VideoPlayer(player: player)
            } else {
                Rectangle().fill(Color.black)
            }
            Button {
                isMuted.toggle()
                player?.isMuted = isMuted
                if !isMuted { player?.play() }
            } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(Circle().fill(Color.black.opacity(0.55)))
            }
            .buttonStyle(.borderless)
            .padding(8)
            .accessibilityLabel(Text(isMuted ? "post.video.unmute" : "post.video.mute"))
        }
        .onAppear {
            if player == nil {
                let newPlayer = AVPlayer(url: url)
                newPlayer.isMuted = true
                player = newPlayer
            }
            player?.isMuted = isMuted
            player?.play()
        }
        .onDisappear {
            player?.pause()
        }
    }
}

/// Rich song card (artwork, title, artist, provider). Tapping opens the music app or the web link.
struct MusicCardView: View {
    let music: MusicAttachment

    var body: some View {
        Link(destination: music.url) {
            HStack(spacing: 12) {
                AsyncImage(url: music.artworkURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ZStack {
                        Color.secondary.opacity(0.2)
                        Image(systemName: "music.note").foregroundStyle(.secondary)
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: music.title ?? music.url.host ?? "")
                        .font(.subheadline)
                        .bold()
                        .lineLimit(2)
                        .foregroundStyle(Color.primary)
                    if let artist = music.artist, !artist.isEmpty {
                        Text(verbatim: artist)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                    if let provider = music.provider {
                        Label(provider.displayName, systemImage: "music.note")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}
