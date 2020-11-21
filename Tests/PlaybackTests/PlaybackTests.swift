import XCTest
@testable import Playback

final class PlaybackTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(Playback().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
