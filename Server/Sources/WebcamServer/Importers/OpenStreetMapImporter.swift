import Foundation
import Vapor
import WebcamKit

/// OSM objects tagged with a public webcam link. The public Overpass server is
/// often busy and not meant for frequent automated use, so run this rarely.
struct OpenStreetMapImporter: WebcamImporter {
    let source = WebcamSource.openStreetMap

    private static let endpoint = "https://overpass-api.de/api/interpreter"
    private static let query = #"[out:json][timeout:150];(nwr["contact:webcam"];nwr["webcam"];);out center tags;"#

    func fetch(using client: any Client) async throws -> [ImportedWebcam] {
        var delay: UInt64 = 30
        for attempt in 1...4 {
            let response = try await client.post(URI(string: Self.endpoint), headers: ImportHTTP.headers) { req in
                req.timeout = .seconds(180)
                try req.content.encode(["data": Self.query], as: .urlEncodedForm)
            }
            if response.status == .ok || attempt == 4 {
                return try Self.parse(ImportHTTP.body(of: response, url: Self.endpoint))
            }
            try await Task.sleep(nanoseconds: delay * 1_000_000_000)
            delay *= 2
        }
        return []
    }

    static func parse(_ data: Data) throws -> [ImportedWebcam] {
        try JSONDecoder().decode(Result.self, from: data).elements.compactMap { element in
            guard let latitude = element.lat ?? element.center?.lat,
                  let longitude = element.lon ?? element.center?.lon,
                  let raw = element.tags["contact:webcam"] ?? element.tags["webcam"],
                  let url = normalizedWebURL(raw) else { return nil }
            return ImportedWebcam(
                title: element.tags["name"] ?? "Webcam",
                latitude: latitude,
                longitude: longitude,
                countryCode: element.tags["addr:country"],
                originalURL: url
            )
        }
    }

    private struct Result: Decodable { let elements: [Element] }
    private struct Element: Decodable {
        let lat: Double?
        let lon: Double?
        let center: Center?
        let tags: [String: String]
    }
    private struct Center: Decodable { let lat: Double; let lon: Double }
}
