import XCTest
@testable import WebcamServer

final class YouTubeDiscoveryTests: XCTestCase {
    func testTitleFilter() {
        XCTAssertTrue(YouTubeDiscovery.looksLikeCamera("Tokyo Shibuya Live Cam"))
        XCTAssertFalse(YouTubeDiscovery.looksLikeCamera("Lofi Tokyo cam music"))
        XCTAssertFalse(YouTubeDiscovery.looksLikeCamera("Tokyo street walk"))
    }

    func testVideosNeedAPlaceAndEmbedding() throws {
        let json = """
        {"items":[
          {"id":"aaaaaaaaaaa","snippet":{"title":"Tokyo live cam","liveBroadcastContent":"live"},"status":{"embeddable":true}},
          {"id":"bbbbbbbbbbb","snippet":{"title":"Somewhere live cam","liveBroadcastContent":"live"},"status":{"embeddable":true}},
          {"id":"ccccccccccc","snippet":{"title":"Somewhere cam","liveBroadcastContent":"live"},"status":{"embeddable":true},
           "recordingDetails":{"location":{"latitude":10.5,"longitude":20.5}}},
          {"id":"ddddddddddd","snippet":{"title":"Tokyo cam","liveBroadcastContent":"live"},"status":{"embeddable":false}},
          {"id":"eeeeeeeeeee","snippet":{"title":"Tokyo cam","liveBroadcastContent":"none"},"status":{"embeddable":true}}]}
        """
        let cams = try YouTubeDiscovery.parseVideos(Data(json.utf8), city: nil)
        XCTAssertEqual(cams.map(\.originalURL), [
            "https://www.youtube.com/watch?v=aaaaaaaaaaa",
            "https://www.youtube.com/watch?v=ccccccccccc",
        ])
        XCTAssertEqual(cams[0].latitude, 35.676, accuracy: 0.03)
        XCTAssertEqual(cams[1].latitude, 10.5)
        XCTAssertEqual(cams[1].streamURL, "https://www.youtube-nocookie.com/embed/ccccccccccc")
    }

    func testDelawareAndMissouri() throws {
        let delaware = #"{"videoCameras":[{"urls":{"m3u8s":"https://x/1.m3u8"},"title":"DE 1","lat":39.0,"lon":-75.4,"enabled":true},{"urls":{"m3u8s":"https://x/2.m3u8"},"title":"Off","lat":39.0,"lon":-75.4,"enabled":false}]}"#
        XCTAssertEqual(try USStateImporter.parseDelaware(Data(delaware.utf8)).map(\.title), ["DE 1"])
        let missouri = #"[{"location":"I-70","x":-90.4,"y":38.4,"html":"https://x/3.m3u8"},{"location":"None","x":-90.4,"y":38.4,"html":null}]"#
        let cams = try USStateImporter.parseMissouri(Data(missouri.utf8))
        XCTAssertEqual(cams.map(\.title), ["I-70"])
        XCTAssertEqual(cams[0].latitude, 38.4)
    }

    func testFindsIframeOfAPage() {
        let html = #"<iframe class="a" src="/player/1"></iframe>"#
        XCTAssertEqual(ProbeClassifier.iframeURL(in: html, base: "https://x.example/page"), "https://x.example/player/1")
        XCTAssertNil(ProbeClassifier.iframeURL(in: "<p>none</p>", base: "https://x.example/page"))
    }

    func testFindsHiddenStreamLinks() {
        XCTAssertEqual(ProbeClassifier.hlsCandidate(in: #"{"src":"https:\/\/cdn.example\/live\/a.m3u8?t=1"}"#), "https://cdn.example/live/a.m3u8?t=1")
        XCTAssertEqual(ProbeClassifier.hlsCandidate(in: #"<source src="//cdn.example/b.m3u8">"#), "https://cdn.example/b.m3u8")
        let html = #"<iframe src="/ad"></iframe><iframe src="/player"></iframe>"#
        XCTAssertEqual(ProbeClassifier.iframeURLs(in: html, base: "https://x.example/"), ["https://x.example/ad", "https://x.example/player"])
    }

    func testDailySliceWrapsAround() {
        let all = (0..<5).map { YouTubeDiscovery.Search(query: "\($0)") }
        XCTAssertEqual(YouTubeDiscovery.slice(all, size: 3, day: 1).map(\.query), ["3", "4", "0"])
        XCTAssertGreaterThan(YouTubeDiscovery.searches.count, 300)
    }
}
