import Testing
@testable import WebcamKit

@Test func parsesValidBox() throws {
    let box = try #require(BoundingBox(queryValue: "47.0,5.5,55.1,15.5"))
    #expect(box.contains(latitude: 52.5, longitude: 13.4))
    #expect(!box.contains(latitude: 40.7, longitude: -74.0))
}

@Test func rejectsMalformedBox() {
    #expect(BoundingBox(queryValue: "1,2,3") == nil)
    #expect(BoundingBox(queryValue: "100,0,10,10") == nil)
    #expect(BoundingBox(queryValue: "10,0,5,10") == nil)
}

@Test func handlesAntimeridian() throws {
    let box = try #require(BoundingBox(queryValue: "-50,170,-30,-170"))
    #expect(box.crossesAntimeridian)
    #expect(box.contains(latitude: -40, longitude: 175))
    #expect(box.contains(latitude: -40, longitude: -175))
    #expect(!box.contains(latitude: -40, longitude: 0))
}
