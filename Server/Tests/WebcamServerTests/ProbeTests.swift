@testable import WebcamServer
import WebcamKit
import XCTest

final class ProbeTests: XCTestCase {
    private func classify(_ contentType: String?, _ body: String = "", url: String = "https://x.example/c") -> Classification {
        ProbeClassifier.classify(url: url, contentType: contentType, body: Data(body.utf8))
    }

    func testDirectTypes() {
        XCTAssertEqual(classify("image/jpeg").streamType, .image)
        XCTAssertEqual(classify("multipart/x-mixed-replace; boundary=x").streamType, .mjpeg)
        XCTAssertEqual(classify("application/vnd.apple.mpegurl").streamType, .hls)
        XCTAssertEqual(classify("text/plain", "#EXTM3U\n").streamType, .hls)
        XCTAssertEqual(classify("application/pdf").streamType, .unknown)
    }

    func testPageWithEmbeddedYouTube() {
        let result = classify("text/html", #"<iframe src="https://www.youtube.com/embed/abcdefghijk?x=1">"#)
        XCTAssertEqual(result.streamType, .youtube)
        XCTAssertEqual(result.streamURL, "https://www.youtube-nocookie.com/embed/abcdefghijk")
    }

    func testPageWithHLSAndPreview() {
        let html = #"<meta property="og:image" content="/p.jpg"><script>u="https://s.example/a.m3u8?t=1&amp;b=2"</script>"#
        let result = classify("text/html; charset=utf-8", html)
        XCTAssertEqual(result.streamType, .webpage)
        XCTAssertEqual(result.candidateHLS, "https://s.example/a.m3u8?t=1&b=2")
        XCTAssertEqual(result.thumbnailURL, "https://x.example/p.jpg")
    }

    func testYouTubeLiveDetection() {
        XCTAssertEqual(ProbeClassifier.youtubeStatusPage(forEmbed: "https://www.youtube-nocookie.com/embed/abcdefghijk"), "https://www.youtube.com/watch?v=abcdefghijk")
        XCTAssertEqual(ProbeClassifier.youtubeStatusPage(forEmbed: "https://www.youtube-nocookie.com/embed/live_stream?channel=UC1"), "https://www.youtube.com/channel/UC1/live")
        XCTAssertTrue(ProbeClassifier.isLiveYouTubePage(Data(#"x"isLive":true,y"#.utf8)))
        XCTAssertFalse(ProbeClassifier.isLiveYouTubePage(Data(#""isLiveContent":true"#.utf8)))
        XCTAssertFalse(ProbeClassifier.isLiveYouTubePage(Data(#""playableInEmbed":false,"isLive":true"#.utf8)))
        XCTAssertTrue(ProbeClassifier.isLiveYouTubePage(Data(#""playableInEmbed":true,"isLive":true,"playableInEmbed":false"#.utf8)))
    }

    func testSearchPageIsNotAVideo() {
        XCTAssertNil(ProbeClassifier.youtubeEmbed(in: "https://www.youtube.com/results?search_query=live"))
    }

    func testPrivateHostsAreRefused() {
        for url in ["http://localhost/a", "http://127.0.0.1/", "http://192.168.1.10/", "http://10.0.0.1/", "http://172.20.0.1/", "http://[::1]/", "ftp://x.example/"] {
            XCTAssertFalse(ProbeClassifier.isPublicWebURL(url), url)
        }
        XCTAssertTrue(ProbeClassifier.isPublicWebURL("https://8.8.8.8/"))
        XCTAssertTrue(ProbeClassifier.isPublicWebURL("https://x.example/"))
    }

    func testReimportKeepsProbeResult() {
        let model = WebcamModel()
        model.lastChecked = Date()
        model.streamType = StreamType.hls.rawValue
        model.streamURL = "https://s/a.m3u8"
        model.isOnline = false
        model.apply(ImportedWebcam(title: "New", latitude: 1, longitude: 2, originalURL: "https://p"))
        XCTAssertEqual(model.title, "New")
        XCTAssertEqual(model.streamType, StreamType.hls.rawValue)
        XCTAssertEqual(model.streamURL, "https://s/a.m3u8")
        XCTAssertFalse(model.isOnline)
    }
}
