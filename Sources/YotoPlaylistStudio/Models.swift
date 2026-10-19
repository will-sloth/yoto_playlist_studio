import Foundation
import AppKit

typealias JSON = [String: Any]
struct StudioError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}
struct Playlist: Identifiable {
    var id: String
    var title: String
}
struct TrackRow: Identifiable {
    var chapter: Int
    var track: Int
    var title: String
    var icon: String?
    var iconURL: URL? = nil
    var id: String { "\(chapter):\(track)" }
}
struct LibraryIcon: Identifiable {
    var id: String
    var title: String
    var tags: [String]
    var url: URL?
}
enum IconPreview {
    static func urls(_ icons: [LibraryIcon]) -> [String: URL] {
        var result: [String: URL] = [:]
        for icon in icons {
            guard let url = icon.url, url.scheme == "https", url.host != nil else { continue }
            result["yoto:#" + icon.id] = url
            result["yoto:" + icon.id] = url
        }
        return result
    }
}
enum ArtChoice {
    case library(LibraryIcon)
    case pixels([UInt32])
}

enum CardEditor {
    static func newPlaylist(title: String) throws -> JSON {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 100 else { throw StudioError("Enter a playlist name of 1–100 characters.") }
        return ["title": title, "content": ["chapters": [JSON](), "playbackType": "linear"]]
    }

    static func rows(_ card: JSON) -> [TrackRow] {
        let content = card["content"] as? JSON ?? [:]
        return (content["chapters"] as? [JSON] ?? []).enumerated().flatMap { ci, chapter in
            (chapter["tracks"] as? [JSON] ?? []).enumerated().map { ti, track in
                let trackDisplay = track["display"] as? JSON ?? [:]
                let chapterDisplay = chapter["display"] as? JSON ?? [:]
                // A track override wins as a unit: never pair it with a chapter's image URL.
                func reference(_ display: JSON) -> String? {
                    [display["icon16x16"], display["iconUrl16x16"]].compactMap { $0 as? String }.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                }
                let display = reference(trackDisplay) == nil ? chapterDisplay : trackDisplay
                let icon = reference(display)
                let directURL = [display["iconUrl16x16"] as? String, icon].compactMap { $0 }.compactMap { URL(string: $0) }.first { $0.scheme == "https" && $0.host != nil }
                return TrackRow(chapter: ci, track: ti, title: track["title"] as? String ?? chapter["title"] as? String ?? "Track \(ti + 1)", icon: icon, iconURL: directURL)
            }
        }
    }

    // Preserve the complete content tree, including unknown audio and configuration fields.
    static func applying(_ references: [String: String], to card: JSON) throws -> JSON {
        guard let cardID = card["cardId"] as? String, !cardID.isEmpty,
              var content = card["content"] as? JSON,
              var chapters = content["chapters"] as? [JSON] else {
            throw StudioError("Yoto returned an incomplete playlist. No changes were sent.")
        }
        let validIDs = Set(rows(card).map(\.id))
        guard Set(references.keys).isSubset(of: validIDs) else {
            throw StudioError("The playlist structure changed. Reload it before applying artwork.")
        }
        for ci in chapters.indices {
            var tracks = chapters[ci]["tracks"] as? [JSON] ?? []
            for ti in tracks.indices {
                if let icon = references["\(ci):\(ti)"] {
                    var display = tracks[ti]["display"] as? JSON ?? [:]
                    display["icon16x16"] = icon
                    tracks[ti]["display"] = display
                }
            }
            chapters[ci]["tracks"] = tracks
            // Chapter selection uses the first track's art, where that track was edited.
            if let first = references["\(ci):0"] {
                var display = chapters[ci]["display"] as? JSON ?? [:]
                display["icon16x16"] = first
                chapters[ci]["display"] = display
            }
        }
        content["chapters"] = chapters
        var result: JSON = ["cardId": cardID, "content": content]
        for key in ["title", "metadata"] { if let value = card[key] { result[key] = value } }
        return result
    }
}

enum PixelArt {
    static let palette: [UInt32] = [0, 0xFFFFFFFF, 0xFF6B4AFF, 0xFFC857FF, 0xFFE6A7FF, 0x56CC9DFF, 0x248C76FF, 0x5BBBEFFF, 0x6674D9FF, 0xB58AE8FF, 0xF596B4FF, 0x884F3DFF, 0x292939FF]
    static let templates = ["Star", "Moon", "Heart", "Tree", "Music"]
    static func template(_ name: String, color: UInt32) -> [UInt32] {
        var pixels = [UInt32](repeating: 0, count: 256)
        func put(_ x: Int, _ y: Int, _ c: UInt32) { if (0..<16).contains(x) && (0..<16).contains(y) { pixels[y * 16 + x] = c } }
        for y in 1..<15 { for x in 1..<15 {
            let dx = Double(x) - 7.5, dy = Double(y) - 7.5
            var on = false
            switch name {
            case "Moon": on = dx * dx + dy * dy < 40 && pow(dx - 3, 2) + pow(dy + 2, 2) > 32
            case "Heart": on = ((x >= 3 && x <= 6 || x >= 9 && x <= 12) && y >= 3 && y <= 5) || (y >= 5 && y <= 12 && abs(dx) < Double(14 - y))
            case "Tree": on = (y >= 2 && y <= 11 && abs(dx) < Double(y) * 0.55) || (y >= 11 && y <= 14 && x >= 7 && x <= 8)
            case "Music": on = ((x == 6 || x == 7 || x == 12 || x == 13) && y >= 3 && y <= 11) || (y >= 2 && y <= 4 && x >= 6 && x <= 13) || (y >= 10 && y <= 12 && ((x >= 3 && x <= 6) || (x >= 9 && x <= 12)))
            default:
                let angle = atan2(dy, dx) + .pi / 2
                let radius = 4.4 + 2.1 * cos(5 * angle)
                on = sqrt(dx * dx + dy * dy) < radius
            }
            if on { put(x, y, color) }
        } }
        return pixels
    }
    static func bitmap(_ pixels: [UInt32]) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bitmapFormat: .alphaNonpremultiplied, bytesPerRow: 64, bitsPerPixel: 32)!
        for y in 0..<16 { for x in 0..<16 {
            let c = pixels[y * 16 + x]
            let offset = y * rep.bytesPerRow + x * 4
            rep.bitmapData![offset] = UInt8((c >> 24) & 255)
            rep.bitmapData![offset + 1] = UInt8((c >> 16) & 255)
            rep.bitmapData![offset + 2] = UInt8((c >> 8) & 255)
            rep.bitmapData![offset + 3] = UInt8(c & 255)
        } }
        return rep
    }
    static func png(_ pixels: [UInt32]) throws -> Data {
        guard pixels.count == 256, let data = bitmap(pixels).representation(using: .png, properties: [:]) else { throw StudioError("Could not encode the icon.") }
        return data
    }
    static func image(_ pixels: [UInt32]) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.addRepresentation(bitmap(pixels))
        return image
    }
    static func importImage(_ url: URL) throws -> [UInt32] {
        return try importImageData(Data(contentsOf: url))
    }
    static func importImageData(_ data: Data) throws -> [UInt32] {
        guard let image = NSImage(data: data) else { throw StudioError("Choose a PNG, JPEG or another supported image.") }
        var rect = NSRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { throw StudioError("Could not read that image.") }
        var bytes = [UInt8](repeating: 0, count: 1024)
        let success = bytes.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(data: storage.baseAddress, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .none
            let scale = min(16 / Double(cg.width), 16 / Double(cg.height))
            let w = Double(cg.width) * scale, h = Double(cg.height) * scale
            context.draw(cg, in: CGRect(x: (16-w)/2, y: (16-h)/2, width: w, height: h))
            return true
        }
        guard success else { throw StudioError("Could not resize that image.") }
        return (0..<256).map { i in
            let p = i * 4, a = UInt32(bytes[p+3])
            guard a > 0 else { return 0 }
            func straight(_ v: UInt8) -> UInt32 { min(255, UInt32(v) * 255 / a) }
            return straight(bytes[p]) << 24 | straight(bytes[p+1]) << 16 | straight(bytes[p+2]) << 8 | a
        }
    }
}
