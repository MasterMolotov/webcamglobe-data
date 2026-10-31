import Foundation
import Vapor
import WebcamKit

/// Items with a "webcam page URL" (P4238) and coordinates.
struct WikidataImporter: WebcamImporter {
    let source = WebcamSource.wikidata

    private static let query = """
    SELECT ?itemLabel ?url ?coord WHERE {
      ?item wdt:P4238 ?url; wdt:P625 ?coord.
      SERVICE wikibase:label { bd:serviceParam wikibase:language "de,en". }
    }
    """

    func fetch(using client: any Client) async throws -> [ImportedWebcam] {
        var components = URLComponents(string: "https://query.wikidata.org/sparql")!
        components.queryItems = [.init(name: "query", value: Self.query), .init(name: "format", value: "json")]
        let url = components.string!
        let response = try await client.get(URI(string: url), headers: ImportHTTP.headers)
        return try Self.parse(ImportHTTP.body(of: response, url: "query.wikidata.org"))
    }

    static func parse(_ data: Data) throws -> [ImportedWebcam] {
        try JSONDecoder().decode(Result.self, from: data).results.bindings.compactMap { row in
            guard let url = normalizedWebURL(row.url.value),
                  let (latitude, longitude) = parsePoint(row.coord.value) else { return nil }
            return ImportedWebcam(title: row.itemLabel.value, latitude: latitude, longitude: longitude, originalURL: url)
        }
    }

    /// Parses `Point(lon lat)`. Coordinates on other globes carry a prefix and are rejected.
    static func parsePoint(_ wkt: String) -> (latitude: Double, longitude: Double)? {
        guard wkt.hasPrefix("Point("), wkt.hasSuffix(")") else { return nil }
        let parts = wkt.dropFirst(6).dropLast().split(separator: " ").compactMap { Double($0) }
        guard parts.count == 2, (-90...90).contains(parts[1]), (-180...180).contains(parts[0]) else { return nil }
        return (parts[1], parts[0])
    }

    private struct Result: Decodable { let results: Results }
    private struct Results: Decodable { let bindings: [Row] }
    private struct Row: Decodable { let itemLabel: Value; let url: Value; let coord: Value }
    private struct Value: Decodable { let value: String }
}
