import Fluent
import Foundation
import Vapor
import WebcamKit

/// `swift run WebcamServer discover` searches YouTube for live cameras and adds new ones.
/// Needs `YOUTUBE_API_KEY`. A search costs 100 of the 10,000 free quota units per day.
struct DiscoverCommand: AsyncCommand {
    struct Signature: CommandSignature {}

    var help: String { "Finds live webcams on YouTube." }

    func run(using context: CommandContext, signature: Signature) async throws {
        guard let key = Environment.get("YOUTUBE_API_KEY") else {
            context.console.error("YOUTUBE_API_KEY is missing")
            return
        }
        let app = context.application
        var known = Set(try await WebcamModel.query(on: app.db).all().map { ImportService.urlKey($0.originalURL) })
        var created = 0, searches = 0

        for search in YouTubeDiscovery.searches {
            // Most likely the daily quota; everything found so far stays.
            guard let found = try? await YouTubeDiscovery.search(search, key: key, client: app.client) else {
                context.console.error("Stopped after \(searches) searches")
                break
            }
            searches += 1
            for cam in found where known.insert(ImportService.urlKey(cam.originalURL)).inserted {
                let model = WebcamModel()
                model.source = WebcamSource.youtube.rawValue
                model.apply(cam)
                model.lastChecked = Date()
                try await model.create(on: app.db)
                created += 1
            }
        }
        context.console.print("\(searches) searches, \(created) new YouTube cameras")
    }
}

enum YouTubeDiscovery {
    struct City: Sendable {
        let name: String
        let latitude: Double
        let longitude: Double
    }

    struct Search: Sendable {
        let query: String
        /// Set for a search about one city; its results must name that city.
        var city: City? = nil
    }

    static let searches: [Search] = cities.map { Search(query: "\($0.name) live cam", city: $0) } + [
        "EarthCam live", "explore.org live cam", "harbor live webcam", "airport live webcam",
        "volcano live webcam", "beach live webcam", "ski resort live webcam", "Webcam live Deutschland",
    ].map { Search(query: $0) }

    static func search(_ search: Search, key: String, client: any Client) async throws -> [ImportedWebcam] {
        let query = search.query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let searchURL = "https://www.googleapis.com/youtube/v3/search?part=id&type=video&eventType=live&maxResults=50&q=\(query)&key=\(key)"
        let ids = try await JSONDecoder().decode(SearchResponse.self, from: body(of: searchURL, client: client))
            .items.compactMap(\.id.videoId)
        guard !ids.isEmpty else { return [] }
        let videosURL = "https://www.googleapis.com/youtube/v3/videos?part=snippet,status,recordingDetails&id=\(ids.joined(separator: ","))&key=\(key)"
        return try await parseVideos(body(of: videosURL, client: client), city: search.city)
    }

    private static func body(of url: String, client: any Client) async throws -> Data {
        let response = try await client.get(URI(string: url), headers: ImportHTTP.headers)
        // The key is part of the URL, so it must not end up in an error message.
        guard response.status == .ok, let buffer = response.body else {
            throw ImportError.badResponse(url: "googleapis.com", status: response.status.code)
        }
        return Data(buffer.readableBytesView)
    }

    static func parseVideos(_ data: Data, city: City?) throws -> [ImportedWebcam] {
        try JSONDecoder().decode(VideosResponse.self, from: data).items.compactMap { video in
            guard video.snippet.liveBroadcastContent == "live", video.status.embeddable != false,
                  looksLikeCamera(video.snippet.title) else { return nil }
            let place = placeInTitle(video.snippet.title)
            let position: (Double, Double, Bool)
            if let exact = video.recordingDetails?.location, let lat = exact.latitude, let lon = exact.longitude {
                position = (lat, lon, false)
            } else if let named = place ?? city.flatMap({ video.snippet.title.localizedCaseInsensitiveContains($0.name) ? $0 : nil }) {
                position = (named.latitude, named.longitude, true)
            } else {
                return nil
            }
            // Cameras placed by city name would sit on one point, which a cluster can never split.
            let offset = position.2 ? spread(for: video.id) : (0, 0)
            return ImportedWebcam(
                title: video.snippet.title,
                latitude: position.0 + offset.0,
                longitude: position.1 + offset.1,
                originalURL: "https://www.youtube.com/watch?v=\(video.id)",
                streamURL: "https://www.youtube-nocookie.com/embed/\(video.id)",
                streamType: .youtube
            )
        }
    }

    static func looksLikeCamera(_ title: String) -> Bool {
        let lower = title.lowercased()
        guard ["cam", "live view", "livestream view", "kamera"].contains(where: lower.contains) else { return false }
        let excluded = [
            "music", "lofi", "lo-fi", "radio", "gaming", "gameplay", "news", "sermon", "church service", "mass ",
            "trading", "bitcoin", "crypto", "podcast", "camp ", "cambodia", "cameroon", "camera roll", "asmr",
            "slot", "casino", "chat", "nachrichten",
        ]
        return !excluded.contains(where: lower.contains)
    }

    static func placeInTitle(_ title: String) -> City? {
        cities.first { title.localizedCaseInsensitiveContains($0.name) }
    }

    /// Same video, same small offset of up to about 2 km, so a camera doesn't jump between runs.
    static func spread(for id: String) -> (Double, Double) {
        let bytes = Array(id.utf8)
        func part(_ step: Int) -> Double {
            let sum = bytes.enumerated().reduce(0) { $0 + Int($1.element) * ($1.offset + step) }
            return Double(sum % 41 - 20) / 1000
        }
        return (part(1), part(3))
    }

    private struct SearchResponse: Decodable {
        struct Item: Decodable {
            struct ID: Decodable { let videoId: String? }
            let id: ID
        }
        let items: [Item]
    }

    private struct VideosResponse: Decodable {
        struct Item: Decodable {
            struct Snippet: Decodable {
                let title: String
                let liveBroadcastContent: String
            }
            struct Status: Decodable { let embeddable: Bool? }
            struct Recording: Decodable { let location: Location? }
            struct Location: Decodable {
                let latitude: Double?
                let longitude: Double?
            }
            let id: String
            let snippet: Snippet
            let status: Status
            let recordingDetails: Recording?
        }
        let items: [Item]
    }

    static let cities: [City] = [
        City(name: "Berlin", latitude: 52.52, longitude: 13.405), City(name: "Hamburg", latitude: 53.55, longitude: 9.99),
        City(name: "München", latitude: 48.137, longitude: 11.575), City(name: "Köln", latitude: 50.938, longitude: 6.96),
        City(name: "Frankfurt", latitude: 50.11, longitude: 8.68), City(name: "Dresden", latitude: 51.05, longitude: 13.74),
        City(name: "Wien", latitude: 48.208, longitude: 16.373), City(name: "Zürich", latitude: 47.377, longitude: 8.54),
        City(name: "London", latitude: 51.507, longitude: -0.128), City(name: "Paris", latitude: 48.857, longitude: 2.352),
        City(name: "Amsterdam", latitude: 52.37, longitude: 4.895), City(name: "Brussels", latitude: 50.85, longitude: 4.35),
        City(name: "Madrid", latitude: 40.417, longitude: -3.703), City(name: "Barcelona", latitude: 41.385, longitude: 2.173),
        City(name: "Lisbon", latitude: 38.722, longitude: -9.139), City(name: "Rome", latitude: 41.903, longitude: 12.496),
        City(name: "Venice", latitude: 45.44, longitude: 12.316), City(name: "Naples", latitude: 40.852, longitude: 14.268),
        City(name: "Athens", latitude: 37.984, longitude: 23.728), City(name: "Istanbul", latitude: 41.008, longitude: 28.978),
        City(name: "Prague", latitude: 50.075, longitude: 14.437), City(name: "Budapest", latitude: 47.498, longitude: 19.04),
        City(name: "Warsaw", latitude: 52.23, longitude: 21.012), City(name: "Stockholm", latitude: 59.329, longitude: 18.069),
        City(name: "Oslo", latitude: 59.914, longitude: 10.752), City(name: "Copenhagen", latitude: 55.676, longitude: 12.568),
        City(name: "Helsinki", latitude: 60.17, longitude: 24.938), City(name: "Reykjavik", latitude: 64.147, longitude: -21.942),
        City(name: "Dublin", latitude: 53.35, longitude: -6.26), City(name: "Edinburgh", latitude: 55.953, longitude: -3.188),
        City(name: "New York", latitude: 40.758, longitude: -73.985), City(name: "Las Vegas", latitude: 36.115, longitude: -115.173),
        City(name: "Miami", latitude: 25.79, longitude: -80.13), City(name: "Chicago", latitude: 41.878, longitude: -87.63),
        City(name: "Los Angeles", latitude: 34.052, longitude: -118.244), City(name: "San Francisco", latitude: 37.775, longitude: -122.419),
        City(name: "Seattle", latitude: 47.606, longitude: -122.332), City(name: "New Orleans", latitude: 29.958, longitude: -90.065),
        City(name: "Honolulu", latitude: 21.307, longitude: -157.858), City(name: "Toronto", latitude: 43.653, longitude: -79.383),
        City(name: "Vancouver", latitude: 49.283, longitude: -123.121), City(name: "Montreal", latitude: 45.502, longitude: -73.567),
        City(name: "Mexico City", latitude: 19.433, longitude: -99.133), City(name: "Cancun", latitude: 21.161, longitude: -86.851),
        City(name: "Havana", latitude: 23.114, longitude: -82.367), City(name: "Rio de Janeiro", latitude: -22.907, longitude: -43.173),
        City(name: "Sao Paulo", latitude: -23.551, longitude: -46.633), City(name: "Buenos Aires", latitude: -34.604, longitude: -58.382),
        City(name: "Santiago", latitude: -33.449, longitude: -70.669), City(name: "Lima", latitude: -12.046, longitude: -77.043),
        City(name: "Bogota", latitude: 4.711, longitude: -74.072), City(name: "Tokyo", latitude: 35.676, longitude: 139.65),
        City(name: "Osaka", latitude: 34.694, longitude: 135.502), City(name: "Kyoto", latitude: 35.012, longitude: 135.768),
        City(name: "Seoul", latitude: 37.567, longitude: 126.978), City(name: "Beijing", latitude: 39.904, longitude: 116.407),
        City(name: "Shanghai", latitude: 31.23, longitude: 121.474), City(name: "Hong Kong", latitude: 22.319, longitude: 114.169),
        City(name: "Taipei", latitude: 25.033, longitude: 121.565), City(name: "Bangkok", latitude: 13.756, longitude: 100.502),
        City(name: "Singapore", latitude: 1.352, longitude: 103.82), City(name: "Bali", latitude: -8.409, longitude: 115.189),
        City(name: "Manila", latitude: 14.6, longitude: 120.984), City(name: "Mumbai", latitude: 19.076, longitude: 72.878),
        City(name: "Delhi", latitude: 28.614, longitude: 77.209), City(name: "Dubai", latitude: 25.205, longitude: 55.271),
        City(name: "Jerusalem", latitude: 31.778, longitude: 35.235), City(name: "Mecca", latitude: 21.423, longitude: 39.826),
        City(name: "Cairo", latitude: 30.044, longitude: 31.236), City(name: "Cape Town", latitude: -33.925, longitude: 18.424),
        City(name: "Johannesburg", latitude: -26.204, longitude: 28.047), City(name: "Nairobi", latitude: -1.292, longitude: 36.822),
        City(name: "Sydney", latitude: -33.869, longitude: 151.209), City(name: "Melbourne", latitude: -37.814, longitude: 144.963),
        City(name: "Auckland", latitude: -36.849, longitude: 174.763),
    ]
}
