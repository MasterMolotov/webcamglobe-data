import AsyncHTTPClient
import Fluent
import Foundation
import NIOCore
import Vapor
import WebcamKit

struct ProbeOutcome: Sendable {
    var classification: Classification?
    var isOnline: Bool
}

struct ProbeSummary: Sendable {
    var checked = 0
    var online = 0
    var byType: [StreamType: Int] = [:]
}

enum ProbeService {
    private static let maxBytes = 512 * 1024
    private static let youtubePageBytes = 4 * 1024 * 1024
    private static let timeoutSeconds: Int64 = 20
    private static let concurrentHosts = 16

    /// These answers mean "not for bots", not "gone"; the page may still work in a web view.
    private static let blockedStatuses: Set<UInt> = [401, 403, 405, 406, 429, 451]

    /// Checks webcams one at a time per host, so no single server gets hammered.
    static func run(_ webcams: [WebcamModel], app: Application) async throws -> ProbeSummary {
        let byHost = Dictionary(grouping: webcams) { URL(string: $0.streamURL ?? $0.originalURL)?.host ?? "" }
        var pending = Array(byHost.values)[...]
        var summary = ProbeSummary()

        try await withThrowingTaskGroup(of: [WebcamModel].self) { group in
            func addNext() {
                guard let cams = pending.popFirst() else { return }
                group.addTask {
                    for cam in cams {
                        let outcome = await probe(cam, client: app.http.client.shared)
                        cam.applyProbe(outcome, now: Date())
                        try await cam.save(on: app.db)
                    }
                    return cams
                }
            }
            for _ in 0..<concurrentHosts { addNext() }
            while let cams = try await group.next() {
                for cam in cams {
                    summary.checked += 1
                    if cam.isOnline { summary.online += 1 }
                    summary.byType[StreamType(rawValue: cam.streamType) ?? .unknown, default: 0] += 1
                }
                addNext()
            }
        }
        return summary
    }

    private static func probe(_ cam: WebcamModel, client: HTTPClient) async -> ProbeOutcome {
        // Direct feeds only need a reachability check on their stream.
        let isDirect = ["image", "hls", "mjpeg"].contains(cam.streamType)
        let target = isDirect ? (cam.streamURL ?? cam.originalURL) : cam.originalURL
        guard ProbeClassifier.isPublicWebURL(target) else {
            return ProbeOutcome(classification: nil, isOnline: false)
        }
        // YouTube pages say little to a plain client; a link to a video is enough.
        if let youtube = ProbeClassifier.youtubeEmbed(in: target) {
            guard let isLive = await isLiveOnYouTube(embed: youtube, client: client) else {
                return ProbeOutcome(classification: nil, isOnline: true)
            }
            return ProbeOutcome(
                classification: Classification(streamType: isLive ? .youtube : .webpage, streamURL: isLive ? youtube : nil),
                isOnline: true
            )
        }
        guard let fetched = await fetch(target, client: client) else {
            return await fallbackToStill(for: cam, client: client)
        }
        if blockedStatuses.contains(fetched.status) {
            return ProbeOutcome(classification: nil, isOnline: true)
        }
        guard (200..<400).contains(fetched.status) else {
            return await fallbackToStill(for: cam, client: client)
        }
        if isDirect { return ProbeOutcome(classification: nil, isOnline: true) }

        var result = ProbeClassifier.classify(url: target, contentType: fetched.contentType, body: fetched.body)
        if result.streamType == .webpage, result.candidateHLS == nil,
           let found = await searchFrames(of: String(decoding: fetched.body, as: UTF8.self), base: target, depth: 2, client: client) {
            result = Classification(streamType: found.streamType, streamURL: found.streamURL,
                                    thumbnailURL: result.thumbnailURL ?? found.thumbnailURL, candidateHLS: found.candidateHLS)
        }
        // Page links often contain expired stream tokens, so only trust ones that answer.
        if let candidate = result.candidateHLS, ProbeClassifier.isPublicWebURL(candidate),
           let stream = await fetch(candidate, client: client), (200..<300).contains(stream.status),
           String(decoding: stream.body, as: UTF8.self).hasPrefix("#EXTM3U") {
            result = Classification(streamType: .hls, streamURL: candidate, thumbnailURL: result.thumbnailURL)
        }
        // Pages often embed an ordinary video that has nothing to do with the camera.
        if result.streamType == .youtube, let embed = result.streamURL {
            guard let isLive = await isLiveOnYouTube(embed: embed, client: client) else {
                return ProbeOutcome(classification: nil, isOnline: true)
            }
            if !isLive {
                result = Classification(streamType: .webpage, streamURL: nil, thumbnailURL: result.thumbnailURL)
            }
        }
        return ProbeOutcome(classification: result, isOnline: true)
    }

    /// Players often sit in a frame inside a frame; looks a few levels down for anything playable.
    private static func searchFrames(of html: String, base: String, depth: Int, client: HTTPClient) async -> Classification? {
        guard depth > 0 else { return nil }
        for frame in ProbeClassifier.iframeURLs(in: html, base: base) where ProbeClassifier.isPublicWebURL(frame) {
            guard let inner = await fetch(frame, client: client), (200..<300).contains(inner.status) else { continue }
            let found = ProbeClassifier.classify(url: frame, contentType: inner.contentType, body: inner.body)
            if found.streamType != .webpage && found.streamType != .unknown && found.streamType != .image || found.candidateHLS != nil {
                return found
            }
            if found.streamType == .webpage,
               let deeper = await searchFrames(of: String(decoding: inner.body, as: UTF8.self), base: frame, depth: depth - 1, client: client) {
                return deeper
            }
        }
        return nil
    }

    /// Only a stream that is running right now counts; finished streams stay available as plain videos.
    /// Returns nil when YouTube gave no real answer, as it does when it rate-limits; that says nothing about the stream.
    private static func isLiveOnYouTube(embed: String, client: HTTPClient) async -> Bool? {
        // The official API isn't rate-limited like the pages, but it only knows single videos.
        if let key = Environment.get("YOUTUBE_API_KEY"), let id = ProbeClassifier.youtubeVideoID(forEmbed: embed) {
            let url = "https://www.googleapis.com/youtube/v3/videos?part=snippet,status&id=\(id)&key=\(key)"
            guard let fetched = await fetch(url, client: client, maxBytes: youtubePageBytes),
                  fetched.status == 200 else { return nil }
            return ProbeClassifier.isLiveYouTubeAPIResponse(fetched.body)
        }
        guard let page = ProbeClassifier.youtubeStatusPage(forEmbed: embed),
              let fetched = await fetch(page, client: client, maxBytes: youtubePageBytes),
              ProbeClassifier.isYouTubeVideoPage(fetched.body) else { return nil }
        return ProbeClassifier.isLiveYouTubePage(fetched.body)
    }

    /// Many traffic cameras keep publishing stills after their video stream is gone.
    private static func fallbackToStill(for cam: WebcamModel, client: HTTPClient) async -> ProbeOutcome {
        guard cam.streamType == StreamType.hls.rawValue, let still = cam.thumbnailURL,
              ProbeClassifier.isPublicWebURL(still),
              let fetched = await fetch(still, client: client), (200..<300).contains(fetched.status),
              fetched.contentType?.lowercased().hasPrefix("image/") == true
        else { return ProbeOutcome(classification: nil, isOnline: false) }
        return ProbeOutcome(
            classification: Classification(streamType: .image, streamURL: still, thumbnailURL: still),
            isOnline: true
        )
    }

    private struct Fetched: Sendable {
        var status: UInt
        var contentType: String?
        var body: Data
    }

    /// Reads only the start of the response: MJPEG streams never end.
    private static func fetch(_ url: String, client: HTTPClient, maxBytes: Int = maxBytes) async -> Fetched? {
        var request = HTTPClientRequest(url: url)
        request.headers.add(name: "User-Agent", value: "WebcamGlobe/0.1 (personal project)")
        request.headers.add(name: "Accept", value: "*/*")
        let finalRequest = request

        return await withTaskGroup(of: Fetched?.self) { group in
            group.addTask {
                do {
                    let response = try await client.execute(finalRequest, timeout: .seconds(timeoutSeconds))
                    var body = Data()
                    for try await var chunk in response.body {
                        body.append(contentsOf: chunk.readBytes(length: chunk.readableBytes) ?? [])
                        if body.count >= maxBytes { break }
                    }
                    return Fetched(status: response.status.code, contentType: response.headers.first(name: "content-type"), body: body)
                } catch {
                    return nil
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds) * 1_000_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

extension WebcamModel {
    func applyProbe(_ outcome: ProbeOutcome, now: Date) {
        isOnline = outcome.isOnline
        lastChecked = now
        guard let result = outcome.classification else { return }
        streamType = result.streamType.rawValue
        streamURL = result.streamURL
        if let thumbnail = result.thumbnailURL { thumbnailURL = thumbnail }
    }
}
