import Foundation
@main struct DuplicateChecks {
    static func main() throws {
        func card(_ tracks: [JSON]) -> JSON { ["content": ["chapters": tracks.enumerated().map { index, track -> JSON in ["key": String(index), "tracks": [track]] }]] }
        let input = card([
            ["title": "First recording", "trackUrl": "yoto:#hash-one"],
            ["title": "A different name", "trackUrl": "yoto:hash-one"],
            ["title": "Third copy", "trackUrl": "yoto:#hash-one"],
            ["title": " Same   Title ", "trackUrl": "yoto:#hash-two"],
            ["title": "same title", "trackUrl": "yoto:#hash-three"],
            ["title": "Unique", "trackUrl": "yoto:#hash-four"]
        ])
        let before = try JSONSerialization.data(withJSONObject: input, options: [.sortedKeys])
        let groups = PlaylistDuplicates.groups(input)
        precondition(groups.count == 2 && groups[0].kind == .audio && groups[0].tracks.map(\.id) == ["0:0", "1:0", "2:0"])
        precondition(groups[1].kind == .title && groups[1].tracks.map(\.id) == ["3:0", "4:0"])
        let both = PlaylistDuplicates.groups(card([["title": "Same", "trackUrl": "yoto:#one"], ["title": "SAME", "trackUrl": "yoto:#one"]]))
        precondition(both.count == 1 && both[0].kind == .audio)
        let signed = PlaylistDuplicates.groups(card([["title": "A", "trackUrl": "https://secure-media.yotoplay.com/audio/test.mp3?Expires=1&Signature=a&Key-Pair-Id=x"], ["title": "B", "trackUrl": "https://secure-media.yotoplay.com/audio/test.mp3?Expires=2&Signature=b&Key-Pair-Id=x"]]))
        precondition(signed.count == 1 && signed[0].kind == .audio)
        precondition(PlaylistDuplicates.groups(card([["trackUrl": ""], ["trackUrl": ""]])).isEmpty)
        precondition(PlaylistDuplicates.groups(card([["title": "One", "trackUrl": "yoto:#one"], ["title": "Two", "trackUrl": "yoto:#two"]])).isEmpty)
        precondition(PlaylistDuplicates.groups([:]).isEmpty)
        let after = try JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]); precondition(before == after)
        print("PASS: duplicate checks group repeated audio even with different titles, separate uncertain title matches, normalize Yoto references/signed links, avoid blank-title and double-reporting false positives, keep stable playlist positions and never alter data")
    }
}
