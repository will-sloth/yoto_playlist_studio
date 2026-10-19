import XCTest
import AppKit
@testable import YotoPlaylistStudio

final class StudioTests: XCTestCase {
    func testEditingPreservesAudioAndUnknownFields() throws {
        let card: JSON = ["cardId": "abc", "title": "Stories", "metadata": ["author": "Parent"], "content": ["unknown": ["future": true], "config": ["shuffle": true], "chapters": [["key": "c1", "display": ["icon16x16": "old", "extra": 9], "tracks": [["key": "t1", "title": "One", "trackUrl": "yoto:#audio", "display": ["icon16x16": "old", "keep": true]], ["key": "t2", "trackUrl": "yoto:#other", "display": ["icon16x16": "untouched"]]]]]]]
        let payload = try CardEditor.applying(["0:0": "yoto:#new"], to: card)
        let content = try XCTUnwrap(payload["content"] as? JSON)
        let chapter = try XCTUnwrap((content["chapters"] as? [JSON])?.first)
        let tracks = try XCTUnwrap(chapter["tracks"] as? [JSON])
        XCTAssertEqual(tracks[0]["trackUrl"] as? String, "yoto:#audio")
        XCTAssertEqual((tracks[0]["display"] as? JSON)?["icon16x16"] as? String, "yoto:#new")
        XCTAssertEqual((tracks[0]["display"] as? JSON)?["keep"] as? Bool, true)
        XCTAssertEqual((tracks[1]["display"] as? JSON)?["icon16x16"] as? String, "untouched")
        XCTAssertEqual((chapter["display"] as? JSON)?["extra"] as? Int, 9)
        XCTAssertEqual((chapter["display"] as? JSON)?["icon16x16"] as? String, "yoto:#new")
        XCTAssertEqual((content["unknown"] as? JSON)?["future"] as? Bool, true)
        XCTAssertEqual((content["config"] as? JSON)?["shuffle"] as? Bool, true)
        XCTAssertEqual((payload["metadata"] as? JSON)?["author"] as? String, "Parent")
        let originalChapters = (card["content"] as? JSON)?["chapters"] as? [JSON]
        XCTAssertEqual((originalChapters?.first?["display"] as? JSON)?["icon16x16"] as? String, "old")
    }
    func testStaleTrackSelectionIsRejected() {
        let card: JSON = ["cardId": "abc", "content": ["chapters": [["tracks": [["title": "One"]]]]]]
        XCTAssertThrowsError(try CardEditor.applying(["9:0": "yoto:#icon"], to: card))
        XCTAssertThrowsError(try CardEditor.applying([:], to: [:]))
    }
    func testSecondTrackDoesNotChangeChapterArt() throws {
        let card: JSON = ["cardId": "abc", "content": ["chapters": [["display": ["icon16x16": "original"], "tracks": [["title": "One"], ["title": "Two"]]]]]]
        let payload = try CardEditor.applying(["0:1": "yoto:#new"], to: card)
        let chapters = (payload["content"] as? JSON)?["chapters"] as? [JSON]
        XCTAssertEqual((chapters?.first?["display"] as? JSON)?["icon16x16"] as? String, "original")
    }
    func testPNGIsExactly16PixelsAndRoundTripsOrientationAndAlpha() throws {
        var pixels = [UInt32](repeating: 0, count: 256)
        pixels[0] = 0xFF0000FF
        pixels[15] = 0x00FF00FF
        pixels[240] = 0x0000FFFF
        pixels[255] = 0xFFFF0080
        let data = try PixelArt.png(pixels)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(rep.pixelsWide, 16); XCTAssertEqual(rep.pixelsHigh, 16)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        let imported = try PixelArt.importImage(url)
        XCTAssertEqual(imported[0], pixels[0]); XCTAssertEqual(imported[15], pixels[15])
        XCTAssertEqual(imported[240], pixels[240]); XCTAssertEqual(imported[255], pixels[255])
    }
}
