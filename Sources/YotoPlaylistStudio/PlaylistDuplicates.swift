import Foundation

struct PlaylistDuplicateGroup: Identifiable {
    enum Kind: String { case audio, title }
    let kind: Kind
    let identity: String
    let tracks: [TrackRow]
    var id: String { kind.rawValue + ":" + identity }
}

enum PlaylistDuplicates {
    static func audioIdentity(_ track: JSON) -> String? {
        guard let raw = track["trackUrl"] as? String else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("yoto:") {
            let hash = String(value.dropFirst(5)).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            return hash.isEmpty ? nil : "yoto:" + hash
        }
        guard let url = URL(string: value), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else { return nil }
        return "url:" + PublicAudio.stableID(url)
    }
    static func groups(_ card: JSON) -> [PlaylistDuplicateGroup] {
        let rows = CardEditor.rows(card)
        let chapters = (card["content"] as? JSON)?["chapters"] as? [JSON] ?? []
        var identities: [String: String] = [:], audio: [String: [TrackRow]] = [:], titles: [String: [TrackRow]] = [:]
        for row in rows {
            let track = (chapters[row.chapter]["tracks"] as? [JSON] ?? [])[row.track]
            if let identity = audioIdentity(track) {
                identities[row.id] = identity; audio[identity, default: []].append(row)
            }
            // Empty/untitled generated labels are not evidence of duplicate songs.
            let title = (track["title"] as? String ?? chapters[row.chapter]["title"] as? String ?? "")
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
            if !title.isEmpty { titles[title, default: []].append(row) }
        }
        func firstPosition(_ group: PlaylistDuplicateGroup) -> Int { rows.firstIndex(where: { $0.id == group.tracks[0].id }) ?? 0 }
        let exact = audio.filter { $0.value.count > 1 }.map { PlaylistDuplicateGroup(kind: .audio, identity: $0.key, tracks: $0.value) }
        let possible = titles.filter { _, tracks in
            guard tracks.count > 1 else { return false }
            let audioIDs = tracks.compactMap { identities[$0.id] }
            return audioIDs.count != tracks.count || Set(audioIDs).count != 1
        }.map { PlaylistDuplicateGroup(kind: .title, identity: $0.key, tracks: $0.value) }
        return exact.sorted { firstPosition($0) < firstPosition($1) } + possible.sorted { firstPosition($0) < firstPosition($1) }
    }
}
