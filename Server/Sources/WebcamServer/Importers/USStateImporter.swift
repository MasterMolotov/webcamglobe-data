import Foundation
import Vapor
import WebcamKit

/// Camera lists behind the public traffic maps of US states. These are not official
/// APIs, so one state failing only loses that state; all failing is reported as an error.
struct USStateImporter: WebcamImporter {
    let source = WebcamSource.us511

    /// States on the "CARS" platform.
    private static let carsStates = ["mn", "ia"]
    /// States on the "511" platform, paged in steps of `pageSize`.
    private static let portals = ["https://511la.org"]
    private static let pageSize = 100

    func fetch(using client: any Client) async throws -> [ImportedWebcam] {
        var result: [ImportedWebcam] = []
        var lastError: (any Error)?
        for state in Self.carsStates {
            do {
                let url = "https://\(state)tg.carsprogram.org/cameras_v1/api/cameras"
                // The first connection of a run sometimes hangs until it times out.
                let response: ClientResponse
                do {
                    response = try await client.get(URI(string: url), headers: ImportHTTP.headers)
                } catch {
                    response = try await client.get(URI(string: url), headers: ImportHTTP.headers)
                }
                result += try Self.parseCARS(ImportHTTP.body(of: response, url: url))
            } catch {
                lastError = error
            }
        }
        for portal in Self.portals {
            do {
                result += try await fetchPortal(portal, using: client)
            } catch {
                lastError = error
            }
        }
        // Returning a partial list is fine, but the store would delete the missing states' cameras.
        if let lastError { throw lastError }
        return result
    }

    private func fetchPortal(_ portal: String, using client: any Client) async throws -> [ImportedWebcam] {
        var result: [ImportedWebcam] = []
        var start = 0
        while true {
            let query = #"{"columns":[],"order":[],"start":\#(start),"length":\#(Self.pageSize),"search":{"value":""}}"#
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
            let url = "\(portal)/List/GetData/Cameras?query=\(encoded)&lang=en"
            let response = try await client.get(URI(string: url), headers: ImportHTTP.headers)
            let page = try Self.parsePortal(ImportHTTP.body(of: response, url: url), portal: portal)
            result += page.cameras
            start += Self.pageSize
            if page.isEmpty || start >= page.total { return result }
        }
    }

    static func parseCARS(_ data: Data) throws -> [ImportedWebcam] {
        try JSONDecoder().decode([CARSCamera].self, from: data).flatMap { cam -> [ImportedWebcam] in
            guard cam.public != false, cam.location.latitude != 0, cam.location.longitude != 0 else { return [] }
            let views = cam.views ?? []
            return views.compactMap { view in
                guard let url = view.url, url.hasPrefix("http") else { return nil }
                let isStream = url.contains(".m3u8")
                guard isStream || view.type == "STILL_IMAGE" else { return nil }
                let viewName = views.count > 1 ? view.name : nil
                return ImportedWebcam(
                    title: viewName.map { $0 == cam.name ? cam.name : "\(cam.name) – \($0)" } ?? cam.name,
                    latitude: cam.location.latitude,
                    longitude: cam.location.longitude,
                    countryCode: "US",
                    originalURL: url,
                    streamURL: url,
                    streamType: isStream ? .hls : .image,
                    thumbnailURL: isStream ? view.videoPreviewUrl : url
                )
            }
        }
    }

    static func parsePortal(_ data: Data, portal: String) throws -> (cameras: [ImportedWebcam], total: Int, isEmpty: Bool) {
        let feed = try JSONDecoder().decode(PortalFeed.self, from: data)
        let cameras = feed.data.flatMap { site -> [ImportedWebcam] in
            guard let point = site.latLng?.geography?.wellKnownText, let (latitude, longitude) = parsePoint(point) else {
                return []
            }
            return (site.images ?? []).compactMap { image in
                guard image.disabled != true, image.blocked != true else { return nil }
                let still = image.imageUrl.map { $0.hasPrefix("http") ? $0 : portal + $0 }
                // A stream that wants a login is of no use, but its still image is.
                let stream = image.isVideoAuthRequired == true || image.videoDisabled == true ? nil : image.videoUrl
                let video = stream.flatMap { $0.hasPrefix("http") ? $0 : nil }
                guard let address = video ?? still else { return nil }
                return ImportedWebcam(
                    title: image.description ?? site.location ?? "Webcam",
                    latitude: latitude,
                    longitude: longitude,
                    countryCode: "US",
                    originalURL: address,
                    streamURL: address,
                    streamType: video == nil ? .image : .hls,
                    thumbnailURL: still
                )
            }
        }
        return (cameras, feed.recordsTotal, feed.data.isEmpty)
    }

    /// `POINT (-80.89 26.17)`: longitude comes first.
    static func parsePoint(_ text: String) -> (latitude: Double, longitude: Double)? {
        guard let open = text.firstIndex(of: "("), let close = text.firstIndex(of: ")"), open < close else { return nil }
        let parts = text[text.index(after: open)..<close].split(separator: " ").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return (parts[1], parts[0])
    }

    private struct CARSCamera: Decodable {
        let `public`: Bool?
        let name: String
        let location: CARSLocation
        let views: [CARSView]?
    }
    private struct CARSLocation: Decodable {
        let latitude: Double
        let longitude: Double
    }
    private struct CARSView: Decodable {
        let name: String?
        let type: String?
        let url: String?
        let videoPreviewUrl: String?
    }
    private struct PortalFeed: Decodable {
        let recordsTotal: Int
        let data: [PortalSite]
    }
    private struct PortalSite: Decodable {
        let location: String?
        let latLng: PortalLatLng?
        let images: [PortalImage]?
    }
    private struct PortalLatLng: Decodable { let geography: PortalGeography? }
    private struct PortalGeography: Decodable { let wellKnownText: String? }
    private struct PortalImage: Decodable {
        let description: String?
        let imageUrl: String?
        let videoUrl: String?
        let isVideoAuthRequired: Bool?
        let videoDisabled: Bool?
        let disabled: Bool?
        let blocked: Bool?
    }
}
