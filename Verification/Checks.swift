import AppKit
import Foundation

func XCTUnwrap<T>(_ value: T?) throws -> T { guard let value else { throw StudioError("Unexpected nil") }; return value }
func XCTAssertEqual<T: Equatable>(_ lhs: T, _ rhs: T) { precondition(lhs == rhs, "Mismatch: \(lhs) vs \(rhs)") }
func XCTAssertThrowsError<T>(_ value: @autoclosure () throws -> T) { do { _ = try value(); fatalError("Expected rejection") } catch {} }
final class StudioTests {
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

@main
enum Verification {
static func main() throws {
let checks = StudioTests()
try checks.testEditingPreservesAudioAndUnknownFields()
checks.testStaleTrackSelectionIsRejected()
try checks.testSecondTrackDoesNotChangeChapterArt()
try checks.testPNGIsExactly16PixelsAndRoundTripsOrientationAndAlpha()
let icons = [LibraryIcon(id: "moon", title: "Moon", tags: ["night"], url: nil), LibraryIcon(id: "star", title: "Golden Star", tags: ["twinkle"], url: nil)]
let suggested = try XCTUnwrap(IconSuggestions.suggest(title: "Twinkle, Twinkle Little Star", icons: icons))
XCTAssertEqual(IconSuggestions.identity(suggested), "star")
let rejected = try XCTUnwrap(IconSuggestions.suggest(title: "Twinkle Star", icons: icons, excluding: ["star"]))
XCTAssertEqual(IconSuggestions.identity(rejected), "template:Star")
let generic = try XCTUnwrap(IconSuggestions.suggest(title: "Unknown Tune", icons: []))
XCTAssertEqual(IconSuggestions.identity(generic), "template:Music")
precondition(IconSuggestions.suggest(title: "Unknown Tune", icons: [], excluding: ["template:Music"]) == nil)
XCTAssertEqual(IconSuggestions.words("THE Móon Song"), Set(["moon"]))
let polarIcons = [LibraryIcon(id: "brown", title: "Brown Bear", tags: ["bear", "kids"], url: nil), LibraryIcon(id: "polar", title: "Polar Bear", tags: ["arctic"], url: nil), LibraryIcon(id: "book", title: "Read Aloud Book", tags: ["kids", "classic"], url: nil)]
let polar = try XCTUnwrap(IconSuggestions.suggest(title: "Polar Bear, Polar Bear, What do you hear _ Animated Book _ Read aloud.mp3", icons: polarIcons))
XCTAssertEqual(IconSuggestions.identity(polar), "polar")
let second = try XCTUnwrap(IconSuggestions.suggest(title: "polar bear", icons: polarIcons, excluding: ["polar"]))
XCTAssertEqual(IconSuggestions.identity(second), "brown")
let request = try ArtGenerator.request(prompt: "A white polar bear", apiKey: "test-key")
XCTAssertEqual(request.url?.host, "api.openai.com")
let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? JSON)
XCTAssertEqual(body["model"] as? String, "gpt-image-2")
XCTAssertEqual(body["n"] as? Int, 1)
XCTAssertThrowsError(try ArtGenerator.request(prompt: "bear", apiKey: ""))
XCTAssertThrowsError(try ArtGenerator.request(prompt: "", apiKey: "test"))
XCTAssertThrowsError(try ArtGenerator.pixels(data: Data(), status: 401))
XCTAssertThrowsError(try ArtGenerator.pixels(data: Data(), status: 429))
XCTAssertThrowsError(try ArtGenerator.pixels(data: Data("{}".utf8), status: 200))
let expected = PixelArt.template("Star", color: 0xFFC857FF)
let imageResponse = try JSONSerialization.data(withJSONObject: ["data": [["b64_json": try PixelArt.png(expected).base64EncodedString()]]])
XCTAssertEqual(try ArtGenerator.pixels(data: imageResponse, status: 200), expected)
let communityURL = CommunitySource.yotoIcons.url(query: "polar bear & moon")
XCTAssertEqual(communityURL.host, "www.yotoicons.com")
let queryItems = try XCTUnwrap(URLComponents(url: communityURL, resolvingAgainstBaseURL: false)?.queryItems)
XCTAssertEqual(queryItems.first(where: { $0.name == "tag" })?.value, "polar bear & moon")
XCTAssertEqual(CommunitySource.everything.url(query: "bear").path, "/icons")
XCTAssertEqual(CommunitySource.suggestedQuery("Polar Bear, Polar Bear, Read Aloud.mp3"), "polar bear")
XCTAssertEqual(CommunitySource.allowedPage(URL(string: "https://www.yotoicons.com/icons")!), true)
XCTAssertEqual(CommunitySource.allowedPage(URL(string: "https://www.yotoeverything.com/icons")!), true)
XCTAssertEqual(CommunitySource.allowedPage(URL(string: "https://www.yotoicons.com.evil.test/file")!), false)
XCTAssertEqual(CommunitySource.allowedPage(URL(string: "file:///private/tmp/icon.png")!), false)
XCTAssertEqual(CommunitySource.isImage(URL(string: "https://www.yotoeverything.com/icons/polar-bear-standing.png")!), true)
let withArt = TrackRow(chapter: 0, track: 0, title: "Song", icon: "yoto:#existing")
let noArt = TrackRow(chapter: 0, track: 1, title: "Song", icon: nil)
XCTAssertEqual(IconSuggestions.shouldSuggest(withArt, automatically: true, hasStagedArt: false), false)
XCTAssertEqual(IconSuggestions.shouldSuggest(withArt, automatically: false, hasStagedArt: false), true)
XCTAssertEqual(IconSuggestions.shouldSuggest(noArt, automatically: true, hasStagedArt: false), true)
XCTAssertEqual(IconSuggestions.shouldSuggest(noArt, automatically: false, hasStagedArt: true), false)
let inheritedArt: JSON = ["content": ["chapters": [["display": ["icon16x16": "yoto:#inherited"], "tracks": [["display": [:]]]]]]]
XCTAssertEqual(CardEditor.rows(inheritedArt).first?.icon, "yoto:#inherited")
print("PASS: existing artwork suppresses automatic suggestions, explicit requests allowed, staged art protected, chapter artwork inheritance")
let artCard: JSON = ["content": ["chapters": [["display": ["icon16x16": "yoto:#chapter", "iconUrl16x16": "https://example.com/chapter.png"], "tracks": [
    ["title": "Inherited"],
    ["title": "Custom", "display": ["icon16x16": "yoto:#custom", "iconUrl16x16": "https://example.com/custom.png"]],
    ["title": "URL only", "display": ["icon16x16": "https://example.com/direct.png"]],
    ["title": "Override without URL", "display": ["icon16x16": "yoto:#private"]],
    ["title": "Unsafe URL", "display": ["icon16x16": "yoto:#safe", "iconUrl16x16": "file:///tmp/private.png"]]
]]]]]
let artRows = CardEditor.rows(artCard)
XCTAssertEqual(artRows[0].iconURL?.absoluteString, "https://example.com/chapter.png")
XCTAssertEqual(artRows[1].iconURL?.absoluteString, "https://example.com/custom.png")
XCTAssertEqual(artRows[2].iconURL?.absoluteString, "https://example.com/direct.png")
precondition(artRows[3].iconURL == nil && artRows[4].iconURL == nil)
XCTAssertEqual(artRows[3].icon, "yoto:#private")
precondition(artRows.allSatisfy { !IconSuggestions.shouldSuggest($0, automatically: true, hasStagedArt: false) })
print("PASS: existing custom and direct icon URLs, inherited chapter images, track override isolation, unsafe URL rejection, no automatic replacement")
let customLibrary = [LibraryIcon(id: "custom-123", title: "My icon", tags: [], url: URL(string: "https://example.com/custom.png")), LibraryIcon(id: "missing", title: "Missing", tags: [], url: nil)]
let customPreviews = IconPreview.urls(customLibrary)
XCTAssertEqual(customPreviews["yoto:#custom-123"]?.absoluteString, "https://example.com/custom.png")
XCTAssertEqual(customPreviews["yoto:custom-123"]?.absoluteString, "https://example.com/custom.png")
precondition(customPreviews["yoto:#missing"] == nil)
print("PASS: private icon library lookup maps both Yoto reference forms and skips missing image URLs")
let directPublic = try PublicAudio.directTracks("https://example.com/audio/One%20Song.mp3\nhttps://example.com/audio/One%20Song.mp3\nhttps://example.com/two.flac")
XCTAssertEqual(directPublic.count, 2)
XCTAssertEqual(directPublic[0].title, "One Song")
XCTAssertThrowsError(try PublicAudio.remoteURL("https://127.0.0.1/private.mp3"))
XCTAssertThrowsError(try PublicAudio.remoteURL("https://server.local/private.mp3"))
XCTAssertThrowsError(try PublicAudio.remoteURL("file:///tmp/private.mp3"))
XCTAssertThrowsError(try PublicAudio.remoteURL("https://user:pass@example.com/song.mp3"))
XCTAssertThrowsError(try PublicAudio.directTracks("https://example.com/article"))
XCTAssertThrowsError(try PublicAudio.shareURL("https://share.yoto.co.evil.test/s/abc"))
XCTAssertEqual(try PublicAudio.shareURL("https://share.yoto.co/s/abc123").host, "share.yoto.co")
let sharedFixture: JSON = ["props": ["pageProps": ["card": ["title": "Public book", "creatorEmail": "private@example.test", "content": ["chapters": [["title": "Chapter", "display": ["icon16x16": "https://example.com/original.png"], "tracks": [["title": "First", "trackUrl": "https://example.com/first.aac"], ["title": "Second", "trackUrl": "https://example.com/second.mp3"]]]]]]]]]
let sharedData = try JSONSerialization.data(withJSONObject: sharedFixture)
let sharedHTML = "<html><script type='application/json' id='__NEXT_DATA__'>" + String(decoding: sharedData, as: UTF8.self) + "</script></html>"
let publicBook = try PublicAudio.collection(html: sharedHTML)
XCTAssertEqual(publicBook.title, "Public book")
XCTAssertEqual(publicBook.tracks.map(\.title), ["First", "Second"])
XCTAssertEqual(publicBook.tracks[0].artworkURL?.absoluteString, "https://example.com/original.png")
XCTAssertThrowsError(try PublicAudio.collection(html: "<html>expired</html>"))
let signedA = URL(string: "https://secure-media.yotoplay.com/audio/id?Expires=1&Signature=old&Key-Pair-Id=key")!
let signedB = URL(string: "https://secure-media.yotoplay.com/audio/id?Expires=2&Signature=new&Key-Pair-Id=key")!
XCTAssertEqual(PublicAudio.stableID(signedA), PublicAudio.stableID(signedB))
precondition(PublicAudio.stableID(URL(string: "https://example.com/download.mp3?id=1")!) != PublicAudio.stableID(URL(string: "https://example.com/download.mp3?id=2")!))
print("PASS: public audio URL validation, batch deduplication, share-page parsing and order, chapter artwork, malformed pages, signed-link cache stability")
let newPlaylist = try CardEditor.newPlaylist(title: "  Public stories  ")
XCTAssertEqual(newPlaylist["title"] as? String, "Public stories")
precondition(newPlaylist["cardId"] == nil)
XCTAssertEqual(((newPlaylist["content"] as? JSON)?["chapters"] as? [JSON])?.count, 0)
XCTAssertThrowsError(try CardEditor.newPlaylist(title: " "))
XCTAssertThrowsError(try CardEditor.newPlaylist(title: String(repeating: "a", count: 101)))
print("PASS: new playlist title validation, empty local draft and creation payload without an existing playlist ID")
let video = try AudioImport.youtubeURL("https://youtu.be/pZw9veQ76fo?list=ignored")
XCTAssertEqual(video.absoluteString, "https://www.youtube.com/watch?v=pZw9veQ76fo")
XCTAssertEqual(try AudioImport.youtubeURL("https://www.youtube.com/shorts/pZw9veQ76fo").absoluteString, video.absoluteString)
XCTAssertThrowsError(try AudioImport.youtubeURL("https://youtube.com.evil.test/watch?v=pZw9veQ76fo"))
XCTAssertThrowsError(try AudioImport.youtubeURL("https://www.youtube.com/playlist?list=abc"))
XCTAssertThrowsError(try AudioImport.youtubeURL("file:///tmp/audio"))
XCTAssertThrowsError(try AudioImport.youtubeURL("https://www.youtube.com/watch?v=--exec"))
let oldCard: JSON = ["cardId": "card1", "title": "Test playlist", "metadata": ["author": "Family", "media": ["duration": 12, "fileSize": 200]], "content": ["config": ["shuffle": true], "chapters": [["key": "01", "title": "Original", "tracks": [["trackUrl": "yoto:#existing", "display": ["icon16x16": "yoto:#original-art"]]]]]]]
let transcode: JSON = ["transcodedSha256": "new-audio", "transcodedInfo": ["duration": 3, "fileSize": 100, "channels": 2, "format": "mp3"]]
let appended = try AudioImport.append(transcode: transcode, title: "New song", to: oldCard)
let newContent = try XCTUnwrap(appended["content"] as? JSON)
let newChapters = try XCTUnwrap(newContent["chapters"] as? [JSON])
XCTAssertEqual(newChapters.count, 2)
XCTAssertEqual((newChapters[1]["tracks"] as? [JSON])?.first?["channels"] as? String, "stereo")
XCTAssertEqual(((newChapters[0]["tracks"] as? [JSON])?.first?["display"] as? JSON)?["icon16x16"] as? String, "yoto:#original-art")
XCTAssertEqual((newChapters[1]["tracks"] as? [JSON])?.first?["trackUrl"] as? String, "yoto:#new-audio")
XCTAssertEqual((newContent["config"] as? JSON)?["shuffle"] as? Bool, true)
XCTAssertEqual((appended["metadata"] as? JSON)?["author"] as? String, "Family")
XCTAssertEqual(((appended["metadata"] as? JSON)?["media"] as? JSON)?["duration"] as? Double, 15)
XCTAssertThrowsError(try AudioImport.append(transcode: [:], title: "New", to: oldCard))
XCTAssertThrowsError(try AudioImport.append(transcode: transcode, title: " ", to: oldCard))
let archiveTest = FileManager.default.temporaryDirectory.appendingPathComponent("yoto-archive-test-" + UUID().uuidString)
try FileManager.default.createDirectory(at: archiveTest, withIntermediateDirectories: true)
let sourceMP3 = archiveTest.appendingPathComponent("source.mp3")
try Data("audio-fixture".utf8).write(to: sourceMP3)
let kept = try AudioImport.keepLocalCopy(sourceMP3, title: "A/B:Song", videoID: "video", directory: archiveTest.appendingPathComponent("archive"))
let keptAgain = try AudioImport.keepLocalCopy(sourceMP3, title: "A/B:Song", videoID: "video", directory: archiveTest.appendingPathComponent("archive"))
precondition(kept != keptAgain)
try FileManager.default.removeItem(at: sourceMP3)
XCTAssertEqual(try Data(contentsOf: kept), Data("audio-fixture".utf8))
XCTAssertEqual(try Data(contentsOf: keptAgain), Data("audio-fixture".utf8))
XCTAssertEqual(AudioImport.savedCopies(videoID: "video", directory: archiveTest.appendingPathComponent("archive")).count, 2)
XCTAssertEqual(AudioImport.savedCopies(videoID: "other", directory: archiveTest.appendingPathComponent("archive")).count, 0)
try FileManager.default.removeItem(at: archiveTest)
print("PASS: permanent audio copies survive source cleanup, safe filenames and non-overwriting repeat downloads")
let batchURLs = try AudioImport.youtubeURLs("https://youtu.be/pZw9veQ76fo\nhttps://www.youtube.com/watch?v=pZw9veQ76fo&list=ignored\nhttps://www.youtube.com/watch?v=abcdefghijk")
XCTAssertEqual(batchURLs.count, 2)
XCTAssertEqual(batchURLs[0].absoluteString, "https://www.youtube.com/watch?v=pZw9veQ76fo")
XCTAssertThrowsError(try AudioImport.youtubeURLs("https://youtu.be/pZw9veQ76fo\nnot-a-url"))
XCTAssertThrowsError(try AudioImport.youtubeURLs("  "))
let batchPayload = try AudioImport.appendBatch([(transcode, "First added"), (transcode, "Second added")], to: oldCard)
let batchChapters = try XCTUnwrap((batchPayload["content"] as? JSON)?["chapters"] as? [JSON])
XCTAssertEqual(batchChapters.count, 3)
let addedKeys = try batchChapters.dropFirst().map { try XCTUnwrap($0["key"] as? String) }
precondition(addedKeys.allSatisfy { !$0.isEmpty && $0.count <= 20 })
XCTAssertEqual(Set(addedKeys).count, addedKeys.count)
XCTAssertEqual(batchChapters[0]["key"] as? String, "01")
print("PASS: appended chapter keys fit Yoto's 20-character limit, are distinct, and preserve existing keys")
XCTAssertEqual(batchChapters[1]["title"] as? String, "First added")
XCTAssertEqual(batchChapters[2]["title"] as? String, "Second added")
XCTAssertEqual(((batchPayload["metadata"] as? JSON)?["media"] as? JSON)?["duration"] as? Double, 18)
XCTAssertThrowsError(try AudioImport.appendBatch([], to: oldCard))
print("PASS: multiline queue, canonical duplicate removal, invalid batch rejection, ordered batch append and aggregate totals")
print("PASS: YouTube URL validation, playlist URL rejection, appended track, original artwork/audio/settings/metadata preservation and totals")
print("PASS: community search encoding, source URLs, subject defaults, navigation restrictions and image-link detection")
print("PASS: polar-bear specificity, second match, generation request, missing key, API errors and generated PNG decoding (mock response; no API calls)")
print("PASS: icon ranking, rejected alternatives, generic fallback, exhausted suggestions and normalized titles")
print("PASS: playlist preservation, stale selections, chapter artwork, PNG dimensions, orientation and transparency")

}
}
