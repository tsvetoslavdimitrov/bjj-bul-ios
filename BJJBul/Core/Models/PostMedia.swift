import Foundation

enum PostMediaKind: String, Hashable {
    case image, video
}

/// Media ready to upload from the composer (images already JPEG-compressed, videos already exported to MP4).
struct ComposerMedia: Identifiable, Hashable {
    let id = UUID()
    var kind: PostMediaKind
    var data: Data
    /// Small preview (JPEG) for the composer strip.
    var thumbnail: Data?
}

enum MusicProvider: String, Hashable {
    case spotify, appleMusic, youtubeMusic, deezer

    var displayName: String {
        switch self {
        case .spotify: return "Spotify"
        case .appleMusic: return "Apple Music"
        case .youtubeMusic: return "YouTube Music"
        case .deezer: return "Deezer"
        }
    }
}

struct MusicAttachment: Hashable {
    var url: URL
    var title: String?
    var artist: String?
    var artworkURL: URL?

    var provider: MusicProvider? { MusicLink.provider(for: url) }
}

extension Post {
    static func isVideoURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "mp4" || ext == "mov" || ext == "m4v"
    }
}
