@testable import WebcamServer
import WebcamKit
import XCTVapor

final class WebcamRoutesTests: XCTestCase {
    private var app: Application!

    override func setUp() async throws {
        app = try await Application.make(.testing)
        try await configure(app)
    }

    override func tearDown() async throws {
        try await app.asyncShutdown()
        app = nil
    }

    func testSeedIsLoaded() async throws {
        try await app.test(.GET, "webcams") { res async throws in
            XCTAssertEqual(res.status, .ok)
            XCTAssertFalse(try res.content.decode([Webcam].self).isEmpty)
        }
    }

    func testBoundingBoxFilters() async throws {
        // Roughly Germany: Zugspitze only.
        try await app.test(.GET, "webcams?bbox=47,5.5,55.1,15.5") { res async throws in
            let cams = try res.content.decode([Webcam].self)
            XCTAssertEqual(cams.map(\.title), ["Zugspitze"])
        }
    }

    func testAntimeridianBox() async throws {
        try await app.test(.GET, "webcams?bbox=-40,150,-30,-170") { res async throws in
            let cams = try res.content.decode([Webcam].self)
            XCTAssertEqual(cams.map(\.title), ["Sydney Harbour"])
        }
    }

    func testInvalidBoundingBox() async throws {
        try await app.test(.GET, "webcams?bbox=1,2,3") { res async in
            XCTAssertEqual(res.status, .badRequest)
        }
    }

    func testCreateAndDuplicate() async throws {
        let body = CreateWebcamRequest(
            title: "Test", latitude: 52.5, longitude: 13.4,
            originalURL: URL(string: "https://example.com/cam.jpg")!, streamType: .image
        )
        try await app.test(.POST, "webcams", beforeRequest: { try $0.content.encode(body) }) { res async in
            XCTAssertEqual(res.status, .created)
        }
        try await app.test(.POST, "webcams", beforeRequest: { try $0.content.encode(body) }) { res async in
            XCTAssertEqual(res.status, .conflict)
        }
    }
}
