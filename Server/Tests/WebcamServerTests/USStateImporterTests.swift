import XCTest
@testable import WebcamServer

final class USStateImporterTests: XCTestCase {
    func testCARSSeparatesStreamsAndStillsAndSkipsMissingLocations() throws {
        let json = """
        [{"public":true,"name":"I-35","location":{"latitude":44.0,"longitude":-93.0},
          "views":[{"name":"N","type":"WMP","url":"https://x/a/playlist.m3u8","videoPreviewUrl":"https://x/a.jpg"},
                   {"name":"S","type":"STILL_IMAGE","url":"https://x/b"}]},
         {"public":true,"name":"Nowhere","location":{"latitude":0,"longitude":0},
          "views":[{"name":"N","type":"STILL_IMAGE","url":"https://x/c"}]}]
        """
        let cams = try USStateImporter.parseCARS(Data(json.utf8))
        XCTAssertEqual(cams.map(\.streamType), [.hls, .image])
        XCTAssertEqual(cams[0].title, "I-35 – N")
        XCTAssertEqual(cams[0].thumbnailURL, "https://x/a.jpg")
    }

    func testPortalIgnoresStreamsThatNeedALogin() throws {
        let json = """
        {"recordsTotal":2,"data":[
          {"location":"A","latLng":{"geography":{"wellKnownText":"POINT (-90.5 30.25)"}},
           "images":[{"description":"Open","imageUrl":"/map/Cctv/1","videoUrl":"https://x/1.m3u8","isVideoAuthRequired":false}]},
          {"location":"B","latLng":{"geography":{"wellKnownText":"POINT (-91 31)"}},
           "images":[{"description":"Locked","imageUrl":"/map/Cctv/2","videoUrl":"https://x/2.m3u8","isVideoAuthRequired":true}]}]}
        """
        let page = try USStateImporter.parsePortal(Data(json.utf8), portal: "https://p")
        XCTAssertEqual(page.total, 2)
        XCTAssertEqual(page.cameras[0].streamType, .hls)
        XCTAssertEqual(page.cameras[0].latitude, 30.25)
        XCTAssertEqual(page.cameras[0].longitude, -90.5)
        XCTAssertEqual(page.cameras[0].thumbnailURL, "https://p/map/Cctv/1")
        XCTAssertEqual(page.cameras[1].streamType, .image)
        XCTAssertEqual(page.cameras[1].originalURL, "https://p/map/Cctv/2")
    }
}
