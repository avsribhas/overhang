import Foundation

public struct Emoji: Hashable, Identifiable, Sendable {
    public let character: String
    /// Lowercased Unicode name, e.g. "grinning face with smiling eyes".
    public let name: String
    public var id: String { character }
}

/// Builds the emoji list from the Unicode tables shipped with Swift, so no bundled dataset is needed.
/// Covers single-scalar emoji with default emoji presentation (the large majority of the picker-worthy set).
public enum EmojiCatalog {
    static let ranges: [ClosedRange<UInt32>] = [
        0x1F600...0x1F64F, // emoticons
        0x1F910...0x1F9FF, // supplemental symbols & pictographs
        0x1FA70...0x1FAFF, // symbols & pictographs extended-A
        0x1F300...0x1F5FF, // misc symbols & pictographs
        0x1F680...0x1F6FF, // transport & map
        0x2600...0x27BF, // misc symbols, dingbats
        0x1F1E6...0x1F1FF, // regional indicators (excluded below)
    ]

    public static let all: [Emoji] = {
        var result: [Emoji] = []
        var seen = Set<String>()
        for range in ranges {
            for value in range {
                guard let scalar = Unicode.Scalar(value) else { continue }
                let props = scalar.properties
                guard props.isEmojiPresentation, !(0x1F1E6...0x1F1FF).contains(value),
                      let name = props.name
                else { continue }
                let character = String(Character(scalar))
                guard seen.insert(character).inserted else { continue }
                result.append(Emoji(character: character, name: name.lowercased()))
            }
        }
        return result
    }()

    /// Every whitespace-separated term must appear in the emoji's name.
    public static func search(_ query: String, in emoji: [Emoji] = all) -> [Emoji] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return emoji }
        return emoji.filter { item in terms.allSatisfy { item.name.contains($0) } }
    }
}
