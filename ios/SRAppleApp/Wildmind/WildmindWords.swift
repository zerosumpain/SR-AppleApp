import Foundation

// MARK: - The chapter's words
//
// The site writes the Wildmind chapter by rule (`showcase-notes-wildmind.ts`,
// `wildmind-words.ts`), and the phone writes it by the same rules so the two
// read as one book:
//
// - No digits in fixed copy. A count is a word ("fifteen places"), a place in
//   the line is an ordinal ("the sixteenth"), and only large figures that come
//   straight from the data are written as figures.
// - Marginal notes start in lower case.
// - Game time only — never a clock time, never "ago".
// - Past tense when the valley is stale or paused.
// - A figure the site did not send is a dash, never 0.
//
// Foundation only, so the sentences can be run and read on Linux.

enum WildmindWords {
    // MARK: Numbers

    private static let small = [
        "no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
        "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen",
    ]
    private static let tens = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]

    /// A count as a word: "no", "one", "twenty-three", "a hundred"; past a
    /// hundred, the figure itself ("1,204").
    static func count(_ n: Int) -> String {
        if n < 0 { return figure(n) }
        if n < 20 { return small[n] }
        if n < 100 {
            let unit = n % 10
            return tens[n / 10] + (unit == 0 ? "" : "-" + small[unit])
        }
        if n == 100 { return "a hundred" }
        return figure(n)
    }

    /// The same, capitalised for the start of a sentence.
    static func countCapitalised(_ n: Int) -> String {
        let word = count(n)
        return word.prefix(1).uppercased() + word.dropFirst()
    }

    /// A figure with the thousands marked, as the site prints large data.
    static func figure(_ n: Int) -> String {
        let format = NumberFormatter()
        format.numberStyle = .decimal
        format.locale = Locale(identifier: "en_GB")
        return format.string(from: NSNumber(value: n)) ?? String(n)
    }

    private static let ordinals = [
        "zeroth", "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth",
        "eleventh", "twelfth", "thirteenth", "fourteenth", "fifteenth", "sixteenth", "seventeenth", "eighteenth",
        "nineteenth",
    ]
    private static let tenths = [
        "", "", "twentieth", "thirtieth", "fortieth", "fiftieth", "sixtieth", "seventieth", "eightieth", "ninetieth",
    ]

    /// "first", "sixteenth", "twenty-third"; from a hundred, "104th".
    static func ordinal(_ n: Int) -> String {
        if n >= 0 && n < 20 { return ordinals[n] }
        if n >= 20 && n < 100 {
            let unit = n % 10
            return unit == 0 ? tenths[n / 10] : tens[n / 10] + "-" + ordinals[unit]
        }
        let teen = (n % 100) >= 11 && (n % 100) <= 13
        let suffix = teen ? "th" : [1: "st", 2: "nd", 3: "rd"][n % 10] ?? "th"
        return "\(n)\(suffix)"
    }

    /// A list joined the English way: "a", "a and b", "a, b and c".
    static func and(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }

    // MARK: Time

    /// How long a life lasted: "less than a day", "a day", "thirty-two days".
    static func days(_ value: Double) -> String {
        let whole = Int(value.rounded())
        if value < 1 { return "less than a day" }
        if whole == 1 { return "a day" }
        return "\(count(whole)) days"
    }

    /// The weather as an adjective for the day: "a wet spring night".
    static func weatherWord(_ weather: String?) -> String? {
        switch weather {
        case "clear": return "clear"
        case "cloudy": return "cloudy"
        case "rain": return "wet"
        case "storm": return "stormy"
        case "snow": return "snowy"
        case "fog": return "foggy"
        default: return nil
        }
    }

    /// "Day five of this life, a wet spring night."
    static func daySentence(_ time: WildmindTime) -> String? {
        guard let day = time.day, day > 0 else { return nil }
        let parts = [weatherWord(time.weather), time.season, time.isNight ? "night" : "day"].compactMap { $0 }
        let article = parts.first.map { $0.hasPrefix("a") || $0.hasPrefix("o") ? "an" : "a" } ?? "a"
        return "Day \(count(day)) of this life, \(article) \(parts.joined(separator: " "))."
    }

    // MARK: People

    /// How a cause of death is said: "died of the cold".
    static func cause(_ raw: String?) -> String? {
        switch raw {
        case "starvation": return "hunger"
        case "thirst": return "thirst"
        case "cold": return "the cold"
        case "exhaustion": return "exhaustion"
        case "injuries": return "their injuries"
        default: return nil
        }
    }

    /// The tag on the map: "JKai is asleep", "Wren was at work", "JKai died here".
    static func tag(_ person: WildmindPerson, pastTense: Bool) -> String {
        guard person.alive else { return "\(person.name) died here" }
        return "\(person.name) \(pastTense ? "was" : "is") \(person.doing)"
    }

    /// What a person is doing and where: "asleep near Heron Lake".
    static func doingNear(_ person: WildmindPerson) -> String {
        guard person.alive else { return person.near.map { "died near \($0)" } ?? "died" }
        return person.near.map { "\(person.doing) near \($0)" } ?? person.doing
    }

    /// The morale band in words.
    static func morale(_ raw: String?) -> String? {
        switch raw {
        case "good": return "in good heart"
        case "getting-by": return "getting by"
        case "low": return "low"
        default: return nil
        }
    }

    /// Whether the person is deciding for themselves just now.
    static func mind(_ person: WildmindPerson) -> String {
        guard person.alive else { return "at rest" }
        return person.thinking ? "thinking it through" : "running on habit"
    }

    // MARK: The map

    /// The label over the map.
    static func figureLabel(_ state: WildmindState, main: String) -> String {
        switch state {
        case .betweenLives: return "The valley as \(main) left it"
        case .offline: return "The valley"
        default: return "The valley as they\u{2019}ve seen it"
        }
    }

    /// The state line under the label, when the valley is not live.
    static func stateNote(_ state: WildmindState, snapshot: WildmindSnapshot) -> String? {
        let day = snapshot.time.day.map(count) ?? "one"
        switch state {
        case .resting:
            return "their minds are resting till tomorrow, so they\u{2019}re getting by on habit."
        case .paused:
            return "the valley\u{2019}s paused just now, so everyone\u{2019}s stopped where they stood."
        case .betweenLives:
            let name = snapshot.main?.name ?? "JKai"
            // The cause only when the site has already written this life into
            // the tree; otherwise it is not known yet, and not guessed.
            let generation = snapshot.stats.generation
            let ended = snapshot.stats.earlierLives.first { generation != nil && $0.n == generation }
            let died = ended.flatMap { cause($0.cause) }.map { "died of \($0)" } ?? "died"
            let next = snapshot.stats.generation.map { " The \(ordinal($0 + 1)) of the line is next." } ?? ""
            return "\(name) \(died) on day \(day).\(next)"
        case .stale, .offline:
            return "this is how the valley stood on day \(day). It isn\u{2019}t answering just now."
        case .live, .unknown:
            return nil
        }
    }

    /// The stamp's second line: "SPRING", "SPRING · NIGHT", "PAUSED", "AS IT
    /// STOOD".
    static func stampSub(_ state: WildmindState, time: WildmindTime) -> String {
        switch state {
        case .paused: return "paused"
        case .stale, .offline: return "as it stood"
        default:
            let season = time.season ?? "today"
            return time.isNight ? "\(season) \u{00B7} night" : season
        }
    }

    /// The caption under the map, the site's three parts.
    static func caption(_ snapshot: WildmindSnapshot, state: WildmindState) -> String {
        var parts: [String] = []
        if let day = daySentence(snapshot.time) { parts.append(day) }
        let names = snapshot.people.map(\.name)
        let who = names.isEmpty ? "they" : and(names)
        let places = snapshot.stats.placesFound
        let named = places.map { $0 == 0 ? ", with no places named yet" : ", with \(count($0)) \($0 == 1 ? "place" : "places") named so far" } ?? ""
        parts.append("A map of the land \(who) \(names.count == 1 ? "has" : "have") seen\(named).")
        let doings = snapshot.people.map { person -> String in
            guard person.alive else { return "\(person.name) died \(person.near.map { "near \($0)" } ?? "here")" }
            let verb = state.pastTense ? "was" : "is"
            return "\(person.name) \(verb) \(person.doing)\(person.near.map { " near \($0)" } ?? "")"
        }
        if !doings.isEmpty { parts.append(and(doings) + ".") }
        if state == .live { parts.append("It\u{2019}s redrawn while you\u{2019}re looking.") }
        return parts.joined(separator: " ")
    }

    /// The scale bar: the longest round distance that fits `room` points.
    static func scale(pointsPerMetre: Double, room: Double) -> (metres: Int, words: String)? {
        let steps: [(Int, String)] = [
            (1000, "a kilometre"), (500, "five hundred metres"), (200, "two hundred metres"),
            (100, "a hundred metres"), (50, "fifty metres"), (20, "twenty metres"), (10, "ten metres"),
            (5, "five metres"), (2, "two metres"),
        ]
        guard pointsPerMetre > 0, pointsPerMetre.isFinite,
              let fit = steps.first(where: { Double($0.0) * pointsPerMetre <= room }) else { return nil }
        return (metres: fit.0, words: fit.1)
    }

    // MARK: The readings

    /// "the newest is Reed basket, and before that Fire drill and Flint
    /// knife." Split so the names can be set upright inside the italic.
    static func latestParts(_ latest: [WildmindInvention]) -> [(text: String, isName: Bool)] {
        guard let first = latest.first else { return [] }
        var parts: [(text: String, isName: Bool)] = [(text: "the newest is ", isName: false), (text: first.name, isName: true)]
        let rest = latest.dropFirst().map(\.name)
        if !rest.isEmpty {
            parts.append((text: ", and before that ", isName: false))
            for (index, name) in rest.enumerated() {
                if index > 0 { parts.append((text: index == rest.count - 1 ? " and " : ", ", isName: false)) }
                parts.append((text: name, isName: true))
            }
        }
        parts.append((text: ".", isName: false))
        return parts
    }

    /// "some of what they do is habit, so they only stop to think when
    /// something's new. They think with Haiku and invent with Sonnet."
    static func habitAndModels(_ stats: WildmindStats) -> String? {
        var sentences: [String] = []
        if let habit = stats.habit {
            let share: String
            switch habit {
            case .most: share = "most"
            case .aboutHalf: share = "about half"
            case .some: share = "some"
            }
            sentences.append("\(share) of what they do is habit, so they only stop to think when something\u{2019}s new.")
        }
        if let models = modelsLine(stats.models) {
            sentences.append(sentences.isEmpty ? models.prefix(1).lowercased() + models.dropFirst() : models)
        }
        return sentences.isEmpty ? nil : sentences.joined(separator: " ")
    }

    /// "They think with Haiku and invent with Sonnet."
    static func modelsLine(_ models: WildmindModels) -> String? {
        switch (models.mind, models.designer) {
        case let (mind?, designer?) where mind == designer:
            return "They think and invent with \(mind)."
        case let (mind?, designer?):
            return "They think with \(mind) and invent with \(designer)."
        case let (mind?, nil):
            return "They think with \(mind)."
        case let (nil, designer?):
            return "They invent with \(designer)."
        case (nil, nil):
            return nil
        }
    }

    /// One line of the family tree, as the site writes it: "the fifteenth
    /// lasted thirty-two days and died of the cold".
    static func lifeLine(_ life: WildmindLife) -> String {
        let who = life.n.map { "the \(ordinal($0))" } ?? "one"
        let died = cause(life.cause).map { " and died of \($0)" } ?? ""
        return "\(who) lasted \(days(life.days))\(died)"
    }

    /// The living one, closing the tree: "this one, five days in so far".
    static func thisLife(_ state: WildmindState, time: WildmindTime) -> String {
        if state == .betweenLives { return "this one, gone, and the next not yet begun" }
        guard let day = time.day, day > 0 else { return "this one, just begun" }
        return day == 1 ? "this one, a day in so far" : "this one, \(count(day)) days in so far"
    }

    /// Lower-case roman numerals for the tree's list: i, ii, iii, iv.
    static func roman(_ n: Int) -> String {
        guard n > 0 && n < 4000 else { return String(n) }
        let table: [(Int, String)] = [
            (1000, "m"), (900, "cm"), (500, "d"), (400, "cd"), (100, "c"), (90, "xc"),
            (50, "l"), (40, "xl"), (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i"),
        ]
        var left = n
        var out = ""
        for (value, numeral) in table {
            while left >= value {
                out += numeral
                left -= value
            }
        }
        return out
    }

    /// The generation in words: "the sixteenth of the line".
    static func generation(_ n: Int?) -> String? {
        guard let n, n > 0 else { return nil }
        return n == 1 ? "the first of the line" : "the \(ordinal(n)) of the line"
    }

    /// The opening: who the two are.
    static func lede(main: String, companion: String) -> String {
        "Wildmind is a small world I\u{2019}m building where \(main) and \(companion) have Claude for minds. "
            + "They start in a valley with nothing and have to invent whatever they need, and a referee in the "
            + "code throws out any idea the valley couldn\u{2019}t actually supply."
    }

    /// The aside under the lede.
    static func shirt(main: String) -> String {
        "the orange one\u{2019}s \(main), you might recognise the shirt."
    }

    /// What VoiceOver hears for the map: what the drawing shows, in a breath.
    static func mapSummary(_ snapshot: WildmindSnapshot, state: WildmindState, places: [String]) -> String {
        var parts = ["A hand-drawn map of the valley."]
        if let day = daySentence(snapshot.time) { parts.append(day) }
        let shown = places.prefix(4)
        if !shown.isEmpty { parts.append("Places marked include \(and(Array(shown))).") }
        let people = snapshot.people.map { person in
            person.alive ? "\(tag(person, pastTense: state.pastTense))\(person.near.map { " near \($0)" } ?? "")"
                : tag(person, pastTense: true)
        }
        if !people.isEmpty { parts.append(and(people) + ".") }
        return parts.joined(separator: " ")
    }
}
