import Foundation
import Vapor
import WebcamKit

/// Finland's road weather cameras from Fintraffic's open Digitraffic service (CC BY 4.0).
/// Each station has a few fixed views; each view is its own still, renewed every few minutes.
struct DigitrafficImporter: WebcamImporter {
    let source = WebcamSource.digitraffic
    static let url = "https://tie.digitraffic.fi/api/weathercam/v1/stations"

    func fetch(using client: any Client) async throws -> [ImportedWebcam] {
        var headers = ImportHTTP.headers
        // Digitraffic asks clients to name themselves and to accept compressed answers.
        headers.add(name: "Digitraffic-User", value: "WebcamGlobe")
        headers.add(name: "Accept-Encoding", value: "gzip")
        let response = try await client.get(URI(string: Self.url), headers: headers)
        return try Self.parse(ImportHTTP.body(of: response, url: Self.url))
    }

    static func parse(_ data: Data) throws -> [ImportedWebcam] {
        try JSONDecoder().decode(Collection.self, from: data).features.flatMap { station -> [ImportedWebcam] in
            guard station.geometry.coordinates.count >= 2 else { return [] }
            let presets = station.properties.presets.filter(\.inCollection)
            return presets.enumerated().map { index, preset in
                let image = "https://weathercam.digitraffic.fi/\(preset.id).jpg"
                return ImportedWebcam(
                    title: title(station.properties.name, view: presets.count > 1 ? index + 1 : nil),
                    latitude: station.geometry.coordinates[1],
                    longitude: station.geometry.coordinates[0],
                    countryCode: "FI",
                    originalURL: image,
                    streamURL: image,
                    streamType: .image,
                    isOnline: station.properties.collectionStatus == "GATHERING",
                    thumbnailURL: image
                )
            }
        }
    }

    /// Names look like "vt1_Espoo_Kehä_III": the road first, then the place.
    static func title(_ name: String, view: Int?) -> String {
        var parts = name.split(separator: "_").map(String.init)
        var road: String?
        if let first = parts.first, first.range(of: #"^(vt|kt|st|mt|yt)\d+$"#, options: .regularExpression) != nil {
            road = first.replacingOccurrences(of: #"^[a-z]+"#, with: "Tie ", options: .regularExpression)
            parts.removeFirst()
        }
        var title = parts.joined(separator: " ")
        if title.isEmpty { title = name }
        if let road { title += " (\(road))" }
        if let view { title += " · Blick \(view)" }
        return title
    }

    private struct Collection: Decodable { let features: [Feature] }
    private struct Feature: Decodable {
        let geometry: Geometry
        let properties: Properties
    }
    private struct Geometry: Decodable { let coordinates: [Double] }
    private struct Properties: Decodable {
        let name: String
        let collectionStatus: String?
        let presets: [Preset]
    }
    private struct Preset: Decodable {
        let id: String
        let inCollection: Bool
    }
}
