import Foundation

// The rules of a capture that need no device: putting words on speakers,
// finding the owner's voice among them, and deciding whether a screenshot may
// leave the phone. Foundation only, so `scripts/captures-check.sh` compiles
// and tests them on Linux.

// MARK: - Words onto speakers

/// A word (or phrase) the transcriber heard, seconds into the recording.
struct CaptureTimedText: Equatable {
    var text: String
    var start: Double
    var end: Double
}

/// One stretch the diarizer gave to one voice. `speaker` is the diarizer's
/// own id ("1", "2", "speaker_0"…), relabelled S1, S2… by `CaptureTurns`.
struct CaptureVoiceSegment: Equatable {
    var speaker: String
    var start: Double
    var end: Double
    /// The voice embedding for this stretch, when the diarizer gives one.
    var embedding: [Float] = []
}

/// What the phone sends: turns, how many speakers, and each speaker's mean
/// voice embedding (kept on the phone, for matching the owner).
struct CaptureTurnResult: Equatable {
    var turns: [CaptureTurn]
    var speakerCount: Int
    var centroids: [String: [Float]]
}

enum CaptureTurns {
    /// A gap longer than this between two words of the same speaker starts a
    /// new turn anyway: a turn is something said, not everything one person
    /// said all afternoon.
    static let pause: Double = 4

    /// Put each word on the voice that was speaking over most of it (or the
    /// nearest one, for a word between segments), relabel the voices S1, S2…
    /// in order of first speech, and join runs into turns.
    ///
    /// No segments — diarization unavailable, or nothing it could hear —
    /// means one speaker, S1, saying all of it.
    static func build(words: [CaptureTimedText], segments: [CaptureVoiceSegment]) -> CaptureTurnResult {
        let ordered = segments.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        let spoken = words.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !ordered.isEmpty else {
            let turns = join(spoken.map { ("S1", $0) })
            return CaptureTurnResult(turns: turns, speakerCount: spoken.isEmpty ? 0 : 1, centroids: [:])
        }

        // Labels in order of first speech, counting only voices that said
        // something the transcriber caught — a cough is not a speaker.
        var assigned: [(String, CaptureTimedText)] = []
        for word in spoken {
            assigned.append((voice(for: word, in: ordered), word))
        }
        var labels: [String: String] = [:]
        for (raw, _) in assigned where labels[raw] == nil {
            labels[raw] = "S\(labels.count + 1)"
        }
        // A voice that never had a word still counts if nothing was
        // transcribed at all (the server will transcribe it).
        if spoken.isEmpty {
            for segment in ordered where labels[segment.speaker] == nil {
                labels[segment.speaker] = "S\(labels.count + 1)"
            }
        }

        let turns = join(assigned.map { (labels[$0.0] ?? "S1", $0.1) })

        var sums: [String: [Float]] = [:]
        var weights: [String: Float] = [:]
        for segment in ordered where !segment.embedding.isEmpty {
            guard let label = labels[segment.speaker] else { continue }
            let weight = Float(segment.end - segment.start)
            if var sum = sums[label], sum.count == segment.embedding.count {
                for i in sum.indices { sum[i] += segment.embedding[i] * weight }
                sums[label] = sum
            } else if sums[label] == nil {
                sums[label] = segment.embedding.map { $0 * weight }
            }
            weights[label, default: 0] += weight
        }
        var centroids: [String: [Float]] = [:]
        for (label, sum) in sums {
            let w = max(weights[label] ?? 1, 0.0001)
            centroids[label] = sum.map { $0 / w }
        }
        return CaptureTurnResult(turns: turns, speakerCount: labels.count, centroids: centroids)
    }

    /// The raw voice speaking over most of `word`, else the nearest one.
    static func voice(for word: CaptureTimedText, in segments: [CaptureVoiceSegment]) -> String {
        var best: (String, Double)?
        for segment in segments {
            let overlap = min(word.end, segment.end) - max(word.start, segment.start)
            if overlap > 0, overlap > (best?.1 ?? 0) { best = (segment.speaker, overlap) }
        }
        if let best { return best.0 }
        let middle = (word.start + word.end) / 2
        let nearest = segments.min { distance(middle, $0) < distance(middle, $1) }
        return nearest?.speaker ?? segments[0].speaker
    }

    private static func distance(_ t: Double, _ segment: CaptureVoiceSegment) -> Double {
        if t < segment.start { return segment.start - t }
        if t > segment.end { return t - segment.end }
        return 0
    }

    /// Consecutive words of one speaker, with no long pause, become a turn.
    static func join(_ words: [(String, CaptureTimedText)]) -> [CaptureTurn] {
        var turns: [CaptureTurn] = []
        for (speaker, word) in words {
            let text = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if var last = turns.last, last.speaker == speaker, word.start - last.end <= pause {
                last.text = last.text.isEmpty ? text : last.text + spacer(before: text) + text
                last.end = max(last.end, word.end)
                turns[turns.count - 1] = last
            } else {
                turns.append(CaptureTurn(speaker: speaker, start: word.start, end: max(word.end, word.start), text: text))
            }
        }
        return turns
    }

    /// No space before punctuation the transcriber split off on its own.
    private static func spacer(before text: String) -> String {
        guard let first = text.unicodeScalars.first else { return " " }
        return ",.;:!?)'’".unicodeScalars.contains(first) ? "" : " "
    }

    /// The whole transcript, from turns.
    static func transcript(_ turns: [CaptureTurn]) -> String {
        turns.map(\.text).joined(separator: " ")
    }
}

// MARK: - Which voice is the owner's

enum CaptureOwnerMatch {
    /// Cosine similarity at or above which a voice is taken to be the owner's.
    /// Speaker embeddings of one person sit well above this; two different
    /// people rarely reach it. A miss names nobody — the server then guesses
    /// from the words and the calendar, and says so.
    static let threshold: Float = 0.45
    /// And the owner's voice must beat the runner-up by this much: two voices
    /// equally like the owner's is not an answer.
    static let margin: Float = 0.05

    /// The label of the voice nearest the enrolled one, or nil.
    static func ownerLabel(enrolled: [Float], centroids: [String: [Float]],
                           threshold: Float = threshold, margin: Float = margin) -> String? {
        guard !enrolled.isEmpty else { return nil }
        let scored = centroids
            .compactMap { label, vector -> (String, Float)? in
                guard let score = cosine(enrolled, vector) else { return nil }
                return (label, score)
            }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
        guard let best = scored.first, best.1 >= threshold else { return nil }
        if scored.count > 1, best.1 - scored[1].1 < margin { return nil }
        return best.0
    }

    /// Cosine similarity, or nil for vectors that cannot be compared.
    static func cosine(_ a: [Float], _ b: [Float]) -> Float? {
        guard a.count == b.count, !a.isEmpty else { return nil }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in a.indices {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        guard na > 0, nb > 0 else { return nil }
        return dot / (na.squareRoot() * nb.squareRoot())
    }

    /// The mean of several enrolment takes, so one cough does not decide it.
    static func average(_ takes: [[Float]]) -> [Float] {
        guard let first = takes.first, !first.isEmpty else { return [] }
        let same = takes.filter { $0.count == first.count }
        var sum = [Float](repeating: 0, count: first.count)
        for take in same { for i in sum.indices { sum[i] += take[i] } }
        return sum.map { $0 / Float(same.count) }
    }
}

// MARK: - Whether a screenshot may leave the phone

/// The phone's answer about one screenshot.
struct ScreenshotVerdict: Equatable {
    /// True: no image goes up and no OCR text either — only the app's name.
    var denied: Bool
    /// Why, for Settings and the capture page: "Monzo is on your deny list".
    var reason: String?
    /// The app the phone thinks it was, from the words on screen.
    var appHint: String?
}

enum ScreenshotPolicy {
    /// Banks, payment apps and password managers: on the list from the start.
    /// The owner can add and remove names in Settings → Captures.
    static let defaultDenyList: [String] = [
        "Monzo", "Starling", "Revolut", "Barclays", "HSBC", "NatWest", "Lloyds", "Halifax", "Santander",
        "Nationwide", "First Direct", "Virgin Money", "Metro Bank", "TSB", "Chase UK", "American Express",
        "PayPal", "Wise", "Coinbase", "Vanguard", "Trading 212", "Moneybox", "Plum",
        "1Password", "Bitwarden", "LastPass", "Dashlane", "Keeper", "Passwords", "Authenticator",
    ]

    /// Apps worth naming as a hint when nothing is denied. The server's vision
    /// pass decides; this only gives it a head start.
    static let knownApps: [String] = [
        "WhatsApp", "Messages", "Gmail", "Outlook", "Mail", "Safari", "Chrome", "Slack", "Teams", "Zoom",
        "Calendar", "Google Maps", "Maps", "YouTube", "Instagram", "Facebook", "LinkedIn", "Notes", "Photos",
        "Spotify", "Netflix", "BBC News", "Guardian", "Amazon", "Uber", "Trainline", "Citymapper", "Strava",
    ]

    /// Words that mean the screen holds a secret, whatever the app.
    static let sensitivePhrases: [String] = [
        "password", "passcode", "one-time code", "one time code", "verification code", "security code",
        "sort code", "account number", "iban", "cvv", "cvc", "card number", "pin code", "recovery key",
        "seed phrase", "secret key",
    ]

    /// Decide for one screenshot's on-device OCR text.
    ///
    /// Denied when a deny-listed name appears as a whole word, or — with
    /// `sensitive` on — a secret-shaped phrase or a card number does. Matching
    /// errs towards denying: a chat that mentions "Monzo" loses its picture,
    /// which costs a little context; the other mistake costs a bank screen.
    static func evaluate(ocrText: String, denyList: [String] = defaultDenyList, sensitive: Bool = true) -> ScreenshotVerdict {
        let text = ocrText
        for name in denyList {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if contains(word: trimmed, in: text) {
                return ScreenshotVerdict(denied: true, reason: "\(trimmed) is on your deny list", appHint: trimmed)
            }
        }
        let hint = knownApps.first { contains(word: $0, in: text) }
        if sensitive {
            for phrase in sensitivePhrases where contains(word: phrase, in: text) {
                return ScreenshotVerdict(denied: true, reason: "The screen mentions a \(phrase)", appHint: hint)
            }
            if hasCardNumber(text) {
                return ScreenshotVerdict(denied: true, reason: "The screen shows a card number", appHint: hint)
            }
        }
        return ScreenshotVerdict(denied: false, reason: nil, appHint: hint)
    }

    /// Case-insensitive, on word boundaries: "Wise" matches "Wise" but not
    /// "otherwise".
    static func contains(word: String, in text: String) -> Bool {
        let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: word) + "(?![\\p{L}\\p{N}])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text.range(of: word, options: .caseInsensitive) != nil
        }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// 13–19 digits, in groups or not, that pass the Luhn check.
    static func hasCardNumber(_ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: "(?<!\\d)(?:\\d[ -]?){12,18}\\d(?!\\d)") else { return false }
        let range = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: range) {
            guard let r = Range(match.range, in: text) else { continue }
            let digits = text[r].compactMap { $0.wholeNumberValue }
            if (13...19).contains(digits.count), luhn(digits) { return true }
        }
        return false
    }

    static func luhn(_ digits: [Int]) -> Bool {
        var sum = 0
        for (offset, digit) in digits.reversed().enumerated() {
            if offset % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
    }
}
