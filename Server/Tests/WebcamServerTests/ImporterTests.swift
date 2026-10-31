@testable import WebcamServer
import Fluent
import WebcamKit
import XCTVapor

final class ImporterTests: XCTestCase {
    func testCaltransPrefersStreamAndSkipsMissingData() throws {
        let json = #"""
        {"data":[
          {"cctv":{"inService":"true","location":{"locationName":"A","latitude":"34.1","longitude":"-118.2"},
           "imageData":{"streamingVideoURL":"https://x/a.m3u8","static":{"currentImageURL":"https://x/a.jpg"}}}},
          {"cctv":{"inService":"false","location":{"locationName":"B","latitude":"34.2","longitude":"-118.3"},
           "imageData":{"streamingVideoURL":"Not Reported","static":{"currentImageURL":"https://x/b.jpg"}}}},
          {"cctv":{"inService":"true","location":{"locationName":"C","latitude":"Not Reported","longitude":"-118"},
           "imageData":{"streamingVideoURL":"","static":{"currentImageURL":"https://x/c.jpg"}}}}
        ]}
        """#
        let cams = try CaltransImporter.parse(Data(json.utf8))
        XCTAssertEqual(cams.map(\.title), ["A", "B"])
        XCTAssertEqual(cams[0].streamType, .hls)
        XCTAssertEqual(cams[1].streamType, .image)
        XCTAssertFalse(cams[1].isOnline)
    }

    func testWikidataPoint() {
        let point = WikidataImporter.parsePoint("Point(2.29 48.85)")
        XCTAssertEqual(point?.latitude, 48.85)
        XCTAssertEqual(point?.longitude, 2.29)
        XCTAssertNil(WikidataImporter.parsePoint("<http://www.wikidata.org/entity/Q405> Point(1 2)"))
    }

    func testOSMUsesCenterAndNormalizesURL() throws {
        let json = #"""
        {"elements":[
          {"type":"way","center":{"lat":47.0,"lon":11.0},"tags":{"name":"Hütte","contact:webcam":"example.com/cam;https://b.example"}},
          {"type":"node","lat":1.0,"lon":2.0,"tags":{"webcam":"not a url"}}
        ]}
        """#
        let cams = try OpenStreetMapImporter.parse(Data(json.utf8))
        XCTAssertEqual(cams.count, 1)
        XCTAssertEqual(cams[0].originalURL, "https://example.com/cam")
        XCTAssertEqual(cams[0].latitude, 47.0)
    }

    func testStoreUpdatesDeduplicatesAndRemoves() async throws {
        let app = try await Application.make(.testing)
        do {
            try await configure(app)
            func cam(_ url: String, _ lat: Double, type: StreamType = .webpage) -> ImportedWebcam {
                ImportedWebcam(title: url, latitude: lat, longitude: 80, originalURL: url, streamType: type)
            }
            var s = try await ImportService.store(
                [cam("https://a.example", 10), cam("https://b.example", 10.0001), cam("https://c.example/i.jpg", 10.0001, type: .image)],
                source: .wikidata, on: app.db)
            XCTAssertEqual(s, ImportSummary(created: 2, updated: 0, skippedDuplicates: 1, removed: 0))

            s = try await ImportService.store([cam("http://www.a.example/", 10)], source: .wikidata, on: app.db)
            XCTAssertEqual(s, ImportSummary(created: 0, updated: 1, skippedDuplicates: 0, removed: 1))

            // Another source cannot take over an entry; an empty feed removes nothing.
            s = try await ImportService.store([cam("https://a.example", 10)], source: .openStreetMap, on: app.db)
            XCTAssertEqual(s.skippedDuplicates, 1)
            s = try await ImportService.store([], source: .wikidata, on: app.db)
            XCTAssertEqual(s.removed, 0)
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }
}
