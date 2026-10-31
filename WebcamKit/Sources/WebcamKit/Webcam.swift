import Foundation

/// How a webcam's content has to be played back.
public enum StreamType: String, Codable, Sendable, CaseIterable {
    /// Still image that is refreshed periodically.
    case image
    /// Motion JPEG (`multipart/x-mixed-replace`).
    case mjpeg
    /// HTTP Live Streaming (`.m3u8`).
    case hls
    /// YouTube live stream, played in the official embed player.
    case youtube
    /// Only a web page is known; shown in a web view as fallback.
    case webpage
    /// Not classified yet.
    case unknown
}

/// Where a webcam entry came from.
public enum WebcamSource: String, Codable, Sendable, CaseIterable {
    case manual
    case openStreetMap
    case wikidata
    case autobahn
    case us511
    case caltrans
    case youtube
}

/// A webcam as delivered by the API.
public struct Webcam: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var title: String
    public var latitude: Double
    public var longitude: Double
    public var countryCode: String?
    public var source: WebcamSource
    /// URL as found in the source (often a web page).
    public var originalURL: URL
    /// Directly playable URL, if known.
    public var streamURL: URL?
    public var streamType: StreamType
    public var isOnline: Bool
    public var lastChecked: Date?
    public var thumbnailURL: URL?

    public init(
        id: UUID = UUID(),
        title: String,
        latitude: Double,
        longitude: Double,
        countryCode: String? = nil,
        source: WebcamSource,
        originalURL: URL,
        streamURL: URL? = nil,
        streamType: StreamType = .unknown,
        isOnline: Bool = true,
        lastChecked: Date? = nil,
        thumbnailURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.latitude = latitude
        self.longitude = longitude
        self.countryCode = countryCode
        self.source = source
        self.originalURL = originalURL
        self.streamURL = streamURL
        self.streamType = streamType
        self.isOnline = isOnline
        self.lastChecked = lastChecked
        self.thumbnailURL = thumbnailURL
    }
}

/// Request body for adding a webcam by hand.
public struct CreateWebcamRequest: Codable, Sendable {
    public var title: String
    public var latitude: Double
    public var longitude: Double
    public var countryCode: String?
    public var originalURL: URL
    public var streamURL: URL?
    public var streamType: StreamType?

    public init(
        title: String,
        latitude: Double,
        longitude: Double,
        countryCode: String? = nil,
        originalURL: URL,
        streamURL: URL? = nil,
        streamType: StreamType? = nil
    ) {
        self.title = title
        self.latitude = latitude
        self.longitude = longitude
        self.countryCode = countryCode
        self.originalURL = originalURL
        self.streamURL = streamURL
        self.streamType = streamType
    }
}

/// Geographic bounding box, encoded as `south,west,north,east` in query strings.
public struct BoundingBox: Sendable, Hashable {
    public var south: Double
    public var west: Double
    public var north: Double
    public var east: Double

    public init(south: Double, west: Double, north: Double, east: Double) {
        self.south = south
        self.west = west
        self.north = north
        self.east = east
    }

    /// Parses `south,west,north,east`. Returns nil for malformed or out-of-range input.
    public init?(queryValue: String) {
        let parts = queryValue.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 4 else { return nil }
        let (s, w, n, e) = (parts[0], parts[1], parts[2], parts[3])
        guard (-90...90).contains(s), (-90...90).contains(n), s <= n,
              (-180...180).contains(w), (-180...180).contains(e) else { return nil }
        self.init(south: s, west: w, north: n, east: e)
    }

    public var queryValue: String { "\(south),\(west),\(north),\(east)" }

    /// True if the box crosses the antimeridian (west > east).
    public var crossesAntimeridian: Bool { west > east }

    public func contains(latitude: Double, longitude: Double) -> Bool {
        guard (south...north).contains(latitude) else { return false }
        return crossesAntimeridian
            ? longitude >= west || longitude <= east
            : (west...east).contains(longitude)
    }
}
