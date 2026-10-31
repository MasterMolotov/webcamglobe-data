import Fluent
import Foundation
import WebcamKit

final class WebcamModel: Model, @unchecked Sendable {
    static let schema = "webcams"

    @ID(key: .id) var id: UUID?
    @Field(key: "title") var title: String
    @Field(key: "latitude") var latitude: Double
    @Field(key: "longitude") var longitude: Double
    @OptionalField(key: "country_code") var countryCode: String?
    @Field(key: "source") var source: String
    @Field(key: "original_url") var originalURL: String
    @OptionalField(key: "stream_url") var streamURL: String?
    @Field(key: "stream_type") var streamType: String
    @Field(key: "is_online") var isOnline: Bool
    @OptionalField(key: "last_checked") var lastChecked: Date?
    @OptionalField(key: "thumbnail_url") var thumbnailURL: String?

    init() {}

    init(from request: CreateWebcamRequest, source: WebcamSource) {
        self.title = request.title
        self.latitude = request.latitude
        self.longitude = request.longitude
        self.countryCode = request.countryCode
        self.source = source.rawValue
        self.originalURL = request.originalURL.absoluteString
        self.streamURL = request.streamURL?.absoluteString
        self.streamType = (request.streamType ?? .unknown).rawValue
        self.isOnline = true
    }

    /// Converts to the shared API type. Returns nil for rows with invalid stored values.
    func toDTO() -> Webcam? {
        guard let id, let original = URL(string: originalURL) else { return nil }
        return Webcam(
            id: id,
            title: title,
            latitude: latitude,
            longitude: longitude,
            countryCode: countryCode,
            source: WebcamSource(rawValue: source) ?? .manual,
            originalURL: original,
            streamURL: streamURL.flatMap(URL.init(string:)),
            streamType: StreamType(rawValue: streamType) ?? .unknown,
            isOnline: isOnline,
            lastChecked: lastChecked,
            thumbnailURL: thumbnailURL.flatMap(URL.init(string:))
        )
    }
}
