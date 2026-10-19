import Foundation

struct IconSuggestion {
    var art: ArtChoice
    var title: String
    var reason: String
}

enum IconSuggestions {
    static func shouldSuggest(_ row: TrackRow, automatically: Bool, hasStagedArt: Bool) -> Bool {
        !hasStagedArt && (!automatically || row.icon == nil)
    }
    static func words(_ text: String) -> Set<String> {
        let stop: Set<String> = ["the", "a", "an", "and", "of", "to", "for", "in", "on", "song", "songs", "track", "feat", "with", "version", "official", "audio", "lyrics", "little", "mp3", "mp4", "read", "aloud", "animated", "book", "kids", "stories", "story", "classic", "by", "what", "do", "you", "see", "hear", "scholastic", "corner", "share"]
        return Set(text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty && !stop.contains($0) })
    }
    static let themes: [(Set<String>, String, UInt32)] = [
        (["star", "stars", "twinkle", "sparkle", "sun", "sunshine"], "Star", 0xFFC857FF),
        (["moon", "night", "sleep", "sleepy", "bedtime", "dream", "dreams", "lullaby"], "Moon", 0x6674D9FF),
        (["love", "heart", "family", "hug", "hugs", "friend", "friends"], "Heart", 0xF596B4FF),
        (["tree", "trees", "forest", "woods", "wood", "garden", "nature", "christmas"], "Tree", 0x56CC9DFF)
    ]
    static func suggest(title: String, icons: [LibraryIcon], excluding: Set<String> = []) -> IconSuggestion? {
        let tokens = words(title)
        var expanded = tokens
        for token in tokens where token.count > 3 && token.hasSuffix("s") { expanded.insert(String(token.dropLast())) }
        for (keywords, name, _) in themes where !expanded.isDisjoint(with: keywords) { expanded.formUnion(words(name)) }
        let candidates = icons.compactMap { icon -> (LibraryIcon, Int, [String])? in
            guard !excluding.contains(icon.id) else { return nil }
            let titleMatches = expanded.intersection(words(icon.title))
            let tagMatches = expanded.intersection(words(icon.tags.joined(separator: " ")))
            let matches = titleMatches.union(tagMatches).sorted()
            let polarTitle = words(title).contains("polar") && words(title).contains("bear")
            let polarIcon = words(icon.title + " " + icon.tags.joined(separator: " ")).contains("polar")
            let bearIcon = words(icon.title + " " + icon.tags.joined(separator: " ")).contains("bear")
            let specificity = polarTitle && polarIcon && bearIcon ? 30 : 0
            let score = titleMatches.count * 4 + tagMatches.count * 2 + specificity
            return score > 0 ? (icon, score, matches) : nil
        }.sorted { lhs, rhs in lhs.1 == rhs.1 ? lhs.0.id < rhs.0.id : lhs.1 > rhs.1 }
        if let best = candidates.first {
            return IconSuggestion(art: .library(best.0), title: best.0.title, reason: "Yoto icon matching: " + best.2.joined(separator: ", "))
        }
        for (keywords, name, color) in themes where !expanded.isDisjoint(with: keywords) && !excluding.contains("template:" + name) {
            return IconSuggestion(art: .pixels(PixelArt.template(name, color: color)), title: name, reason: "Starter design inspired by the song title")
        }
        guard !excluding.contains("template:Music") else { return nil }
        return IconSuggestion(art: .pixels(PixelArt.template("Music", color: 0x5BBBEFFF)), title: "Music", reason: "General music design — no specific title match")
    }
    static func identity(_ suggestion: IconSuggestion) -> String {
        if case .library(let icon) = suggestion.art { return icon.id }
        return "template:" + suggestion.title
    }
}
