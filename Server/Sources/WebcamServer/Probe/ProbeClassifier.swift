import Foundation
import WebcamKit

/// What a URL turned out to be. Contains no networking so it can be tested directly.
struct Classification: Equatable, Sendable {
    var streamType: StreamType
    var streamURL: String?
    var thumbnailURL: String? = nil
    /// HLS link found inside a page; still has to be verified.
    var candidateHLS: String? = nil
}

enum ProbeClassifier {
    static func classify(url: String, contentType: String?, body: Data) -> Classification {
        if let youtube = youtubeEmbed(in: url) {
            return Classification(streamType: .youtube, streamURL: youtube)
        }
        let type = (contentType ?? "").lowercased()
        if type.hasPrefix("image/") {
            return Classification(streamType: .image, streamURL: url, thumbnailURL: url)
        }
        if type.hasPrefix("multipart/x-mixed-replace") {
            return Classification(streamType: .mjpeg, streamURL: url)
        }
        let text = String(decoding: body, as: UTF8.self)
        if type.contains("mpegurl") || text.hasPrefix("#EXTM3U") {
            return Classification(streamType: .hls, streamURL: url)
        }
        guard type.contains("html") || type.isEmpty else {
            return Classification(streamType: .unknown, streamURL: nil)
        }
        return classifyPage(url: url, html: text)
    }

    private static func classifyPage(url: String, html: String) -> Classification {
        let thumbnail = firstMatch(ogImagePattern, in: html, group: 1).flatMap { resolve($0, against: url) }
        if let youtube = youtubeEmbed(in: html) {
            return Classification(streamType: .youtube, streamURL: youtube, thumbnailURL: thumbnail)
        }
        let candidate = firstMatch(hlsPattern, in: html, group: 0)?.replacingOccurrences(of: "&amp;", with: "&")
        return Classification(streamType: .webpage, streamURL: nil, thumbnailURL: thumbnail, candidateHLS: candidate)
    }

    /// Finds a specific YouTube video or channel stream. Search pages don't count.
    static func youtubeEmbed(in text: String) -> String? {
        if let path = firstMatch(youtubeEmbedPattern, in: text, group: 1) {
            return "https://www.youtube-nocookie.com/embed/" + path.replacingOccurrences(of: "&amp;", with: "&")
        }
        if let id = firstMatch(youtubeVideoPattern, in: text, group: 1) {
            return "https://www.youtube-nocookie.com/embed/" + id
        }
        return nil
    }

    /// The YouTube page that reveals whether an embed is live at the moment.
    static func youtubeStatusPage(forEmbed embed: String) -> String? {
        guard let path = embed.components(separatedBy: "/embed/").last, !path.isEmpty else { return nil }
        if let channel = path.components(separatedBy: "channel=").dropFirst().first {
            return "https://www.youtube.com/channel/\(channel)/live"
        }
        return "https://www.youtube.com/watch?v=\(path)"
    }

    static func isLiveYouTubePage(_ body: Data) -> Bool {
        let page = String(decoding: body, as: UTF8.self)
        // Some owners forbid embedding; such a stream runs but can't play in the app.
        return page.contains(#""isLive":true"#) && !page.contains(#""playableInEmbed":false"#)
    }

    /// Open data can point anywhere; never let it make the server call its own network.
    static func isPublicWebURL(_ raw: String) -> Bool {
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let host = url.host?.lowercased(), !host.isEmpty
        else { return false }
        if host == "localhost" || host.hasSuffix(".local") || host.hasSuffix(".localhost") || host.contains(":") {
            return false
        }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4 else { return true }
        switch (octets[0], octets[1]) {
        case (0, _), (10, _), (127, _), (169, 254), (192, 168): return false
        case (172, 16...31), (100, 64...127): return false
        default: return true
        }
    }

    private static func resolve(_ value: String, against base: String) -> String? {
        URL(string: value, relativeTo: URL(string: base))?.absoluteURL.absoluteString
    }

    private static func firstMatch(_ pattern: NSRegularExpression, in text: String, group: Int) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = pattern.firstMatch(in: text, range: range),
              let result = Range(match.range(at: group), in: text) else { return nil }
        return String(text[result])
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static let hlsPattern = regex(#"https?://[^"'\s<>\\]+\.m3u8[^"'\s<>\\]*"#)
    private static let youtubeEmbedPattern = regex(#"youtube(?:-nocookie)?\.com/embed/((?:live_stream\?channel=[\w-]+)|[\w-]{11})"#)
    private static let youtubeVideoPattern = regex(#"(?:youtube\.com/watch\?v=|youtu\.be/)([\w-]{11})"#)
    private static let ogImagePattern = regex(#"<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']"#)
}
