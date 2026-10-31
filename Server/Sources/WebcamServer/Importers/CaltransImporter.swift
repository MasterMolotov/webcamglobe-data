import Foundation
import Vapor
import WebcamKit

/// California's open traffic camera feeds, one file per district.
struct CaltransImporter: WebcamImporter {
    let source = WebcamSource.caltrans

    func fetch(using client: any Client) async throws -> [ImportedWebcam] {
        var result: [ImportedWebcam] = []
        for district in 1...12 {
            let url = "https://cwwp2.dot.ca.gov/data/d\(district)/cctv/cctvStatusD\(String(format: "%02d", district)).json"
            let response = try await client.get(URI(string: url), headers: ImportHTTP.headers)
            result += try Self.parse(ImportHTTP.body(of: response, url: url))
        }
        return result
    }

    static func parse(_ data: Data) throws -> [ImportedWebcam] {
        try JSONDecoder().decode(Feed.self, from: data).data.compactMap { entry in
            let cam = entry.cctv
            guard let latitude = Double(cam.location.latitude),
                  let longitude = Double(cam.location.longitude),
                  let image = normalizedURLIfWeb(cam.imageData.static.currentImageURL)
            else { return nil }
            let stream = normalizedURLIfWeb(cam.imageData.streamingVideoURL)
            return ImportedWebcam(
                title: cam.location.locationName,
                latitude: latitude,
                longitude: longitude,
                countryCode: "US",
                originalURL: image,
                streamURL: stream ?? image,
                streamType: stream == nil ? .image : .hls,
                isOnline: cam.inService == "true",
                thumbnailURL: image
            )
        }
    }

    /// The feed uses values like "Not Reported" for missing URLs.
    private static func normalizedURLIfWeb(_ value: String?) -> String? {
        guard let value, value.hasPrefix("http") else { return nil }
        return value
    }

    private struct Feed: Decodable { let data: [Entry] }
    private struct Entry: Decodable { let cctv: Camera }
    private struct Camera: Decodable {
        let inService: String
        let location: Location
        let imageData: ImageData
    }
    private struct Location: Decodable {
        let locationName: String
        let latitude: String
        let longitude: String
    }
    private struct ImageData: Decodable {
        let streamingVideoURL: String?
        let `static`: StaticImage
    }
    private struct StaticImage: Decodable { let currentImageURL: String? }
}
