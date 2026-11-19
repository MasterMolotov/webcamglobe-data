import Foundation
import Vapor
import WebcamKit

/// British Columbia's highway cameras from DriveBC; stills renewed every few minutes.
struct DriveBCImporter: WebcamImporter {
    let source = WebcamSource.driveBC
    static let url = "https://www.drivebc.ca/api/webcams/"

    func fetch(using client: any Client) async throws -> [ImportedWebcam] {
        let response = try await client.get(URI(string: Self.url), headers: ImportHTTP.headers)
        return try Self.parse(ImportHTTP.body(of: response, url: Self.url))
    }

    static func parse(_ data: Data) throws -> [ImportedWebcam] {
        try JSONDecoder().decode([Camera].self, from: data).compactMap { cam in
            guard cam.should_appear != false, cam.location.coordinates.count >= 2 else { return nil }
            // The feed adds a cache-busting time to the image link; the plain link always gives the newest picture.
            let image = "https://www.drivebc.ca/images/\(cam.id).jpg"
            let name = cam.name_override?.isEmpty == false ? cam.name_override! : cam.name
            let caption = cam.caption_override?.isEmpty == false ? cam.caption_override : cam.caption
            return ImportedWebcam(
                title: caption.map { "\(name) – \($0)" } ?? name,
                latitude: cam.location.coordinates[1],
                longitude: cam.location.coordinates[0],
                countryCode: "CA",
                originalURL: image,
                streamURL: image,
                streamType: .image,
                isOnline: cam.is_on != false && cam.marked_stale != true,
                thumbnailURL: image
            )
        }
    }

    private struct Camera: Decodable {
        let id: Int
        let name: String
        let name_override: String?
        let caption: String?
        let caption_override: String?
        let is_on: Bool?
        let should_appear: Bool?
        let marked_stale: Bool?
        let location: Point
    }
    private struct Point: Decodable { let coordinates: [Double] }
}
