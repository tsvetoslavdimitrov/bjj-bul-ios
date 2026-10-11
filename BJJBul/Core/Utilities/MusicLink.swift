import Foundation

/// Song links (Spotify, Apple Music, YouTube Music, Deezer): detection and rich metadata
/// via the providers' public oEmbed endpoints, falling back to Open Graph tags. Links only; no audio.
enum MusicLink {
    static func provider(for url: URL) -> MusicProvider? {
        guard let host = url.host?.lowercased() else { return nil }
        if host == "open.spotify.com" || host == "spotify.link" { return .spotify }
        if host == "music.apple.com" { return .appleMusic }
        if host == "music.youtube.com" || host == "youtube.com" || host == "www.youtube.com" || host == "youtu.be" {
            return .youtubeMusic
        }
        if host.hasSuffix("deezer.com") || host == "deezer.page.link" { return .deezer }
        return nil
    }

    /// Finds the first supported https link in free text (users often paste "Check this out https://...").
    static func extract(from text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = detector?.matches(in: text, options: [], range: range) ?? []
        for match in matches {
            if let url = match.url, url.scheme == "https", provider(for: url) != nil {
                return url
            }
        }
        return nil
    }

    private struct OEmbed: Decodable {
        let title: String?
        let author_name: String?
        let thumbnail_url: String?
    }

    static func fetchMetadata(for url: URL) async -> MusicAttachment {
        var result = MusicAttachment(url: url, title: nil, artist: nil, artworkURL: nil)
        if let endpoint = oEmbedEndpoint(for: url), let embed = await fetchOEmbed(endpoint) {
            result.title = embed.title
            result.artist = embed.author_name
            result.artworkURL = embed.thumbnail_url.flatMap { URL(string: $0) }
        }
        if result.title == nil || result.artworkURL == nil {
            let og = await fetchOpenGraph(url)
            if result.title == nil { result.title = og.title }
            if result.artist == nil { result.artist = og.description }
            if result.artworkURL == nil { result.artworkURL = og.image }
        }
        // Keep only https artwork (the database rejects others).
        if let art = result.artworkURL, art.scheme != "https" { result.artworkURL = nil }
        return result
    }

    private static func oEmbedEndpoint(for url: URL) -> URL? {
        guard let provider = provider(for: url) else { return nil }
        var components: URLComponents?
        switch provider {
        case .spotify:
            components = URLComponents(string: "https://open.spotify.com/oembed")
            components?.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
        case .youtubeMusic:
            // YouTube's oEmbed understands www.youtube.com links; music.youtube.com shares the same video ids.
            var link = url.absoluteString
            link = link.replacingOccurrences(of: "music.youtube.com", with: "www.youtube.com")
            components = URLComponents(string: "https://www.youtube.com/oembed")
            components?.queryItems = [URLQueryItem(name: "url", value: link), URLQueryItem(name: "format", value: "json")]
        case .deezer:
            components = URLComponents(string: "https://api.deezer.com/oembed")
            components?.queryItems = [URLQueryItem(name: "url", value: url.absoluteString), URLQueryItem(name: "format", value: "json")]
        case .appleMusic:
            return nil // No public oEmbed without a developer token; Open Graph works.
        }
        return components?.url
    }

    private static func fetchOEmbed(_ endpoint: URL) async -> OEmbed? {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 8
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(OEmbed.self, from: data)
    }

    private static func fetchOpenGraph(_ url: URL) async -> (title: String?, description: String?, image: URL?) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data.prefix(300_000), encoding: .utf8) else { return (nil, nil, nil) }
        let image = meta("og:image", in: html).flatMap { URL(string: $0) }
        return (meta("og:title", in: html), meta("og:description", in: html), image)
    }

    /// Reads <meta property="og:x" content="..."> (attribute order may vary).
    static func meta(_ property: String, in html: String) -> String? {
        let patterns = [
            "<meta[^>]+property=\"\(property)\"[^>]+content=\"([^\"]*)\"",
            "<meta[^>]+content=\"([^\"]*)\"[^>]+property=\"\(property)\"",
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            if let match = regex.firstMatch(in: html, options: [], range: range),
               let valueRange = Range(match.range(at: 1), in: html) {
                let value = String(html[valueRange])
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .replacingOccurrences(of: "&quot;", with: "\"")
                    .replacingOccurrences(of: "&#39;", with: "'")
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }
}
