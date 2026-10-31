import Foundation
import Vapor
import WebcamKit

/// A webcam as found in an external source, before it is stored.
struct ImportedWebcam: Sendable, Equatable {
    var title: String
    var latitude: Double
    var longitude: Double
    var countryCode: String? = nil
    var originalURL: String
    var streamURL: String? = nil
    var streamType: StreamType = .webpage
    var isOnline: Bool = true
    var thumbnailURL: String? = nil
}

protocol WebcamImporter: Sendable {
    var source: WebcamSource { get }
    func fetch(using client: any Client) async throws -> [ImportedWebcam]
}

enum ImportError: Error, CustomStringConvertible {
    case badResponse(url: String, status: UInt)

    var description: String {
        switch self {
        case let .badResponse(url, status): "HTTP \(status) from \(url)"
        }
    }
}

enum ImportHTTP {
    /// Wikidata and Overpass ask automated clients to identify themselves.
    static let headers: HTTPHeaders = ["User-Agent": "WebcamGlobe/0.1 (personal project)"]

    static func body(of response: ClientResponse, url: String) throws -> Data {
        guard response.status == .ok, let buffer = response.body else {
            throw ImportError.badResponse(url: url, status: response.status.code)
        }
        return Data(buffer.readableBytesView)
    }
}

/// Returns the first http(s) URL in a tag value, adding a scheme if it is missing.
func normalizedWebURL(_ raw: String) -> String? {
    guard var value = raw.split(separator: ";").first?.trimmingCharacters(in: .whitespaces), !value.isEmpty else {
        return nil
    }
    if !value.contains("://") { value = "https://" + value }
    guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
          scheme == "http" || scheme == "https", url.host != nil else { return nil }
    return value
}
