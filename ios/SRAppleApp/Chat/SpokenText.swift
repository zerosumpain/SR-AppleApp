import Foundation

/// An answer as it should sound, not as it is typed.
///
/// A reply is markdown, and a synthesiser reads markdown literally: "asterisk
/// asterisk", every character of a URL, a whole code block one symbol at a
/// time. This keeps the words and drops the marks. A code block becomes one
/// short sentence, because reading code aloud helps nobody, and a link reads
/// as its text.
///
/// Foundation only: the Linux harness tests it.
enum SpokenText {
    static func plain(_ markdown: String) -> String {
        var lines: [String] = []
        var inFence = false
        var saidCode = false
        for raw in markdown.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                inFence.toggle()
                if inFence && !saidCode {
                    lines.append("There is a code block here.")
                    saidCode = true
                }
                if !inFence { saidCode = false }
                continue
            }
            if inFence { continue }
            lines.append(inline(block(line)))
        }
        return lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// Headings, quotes, bullets, numbered items and rules lose their marker.
    private static func block(_ line: String) -> String {
        var line = line
        if line.range(of: #"^([-*_]\s*){3,}$"#, options: .regularExpression) != nil { return "" }
        line = line.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
        line = line.replacingOccurrences(of: #"^(>\s?)+"#, with: "", options: .regularExpression)
        line = line.replacingOccurrences(of: #"^[-*+]\s+(\[[ xX]\]\s+)?"#, with: "", options: .regularExpression)
        // A table row reads as its cells; its divider is not read at all.
        if line.hasPrefix("|") {
            if line.range(of: #"^\|?[\s:|-]+\|?$"#, options: .regularExpression) != nil { return "" }
            line = line
                .split(separator: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        }
        return line
    }

    private static func inline(_ text: String) -> String {
        var text = text
        // Images say nothing; links say their text.
        text = text.replacingOccurrences(of: #"!\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        // A bare address is "a link", not forty characters of it.
        text = text.replacingOccurrences(of: #"https?://\S+"#, with: "a link", options: .regularExpression)
        text = text.replacingOccurrences(of: "`", with: "")
        // Emphasis marks, but not an asterisk standing alone ("2 * 3").
        text = text.replacingOccurrences(of: #"(\*\*|__)(\S(?:.*?\S)?)\1"#, with: "$2", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?<![\w*])([*_])(\S(?:.*?\S)?)\1(?![\w*])"#, with: "$2", options: .regularExpression)
        text = text.replacingOccurrences(of: #"~~(.+?)~~"#, with: "$1", options: .regularExpression)
        return text
    }
}
