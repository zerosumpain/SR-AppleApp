import Foundation

/// The money icon a price wears, following where the trip is: a euro in Rome,
/// a pound in Edinburgh — never a euro on every price (red team 2026-10-15,
/// plan §5.5).
///
/// A symbol in the price itself wins ("£18", "CHF 20"); otherwise the trip's
/// own time zone says the country. Anywhere this does not know gets the
/// neutral banknote rather than a guess.
///
/// Foundation only: the Linux harness tests it.
enum TripCurrency {
    /// An SF Symbol name for a price on this trip.
    static func symbol(price: String?, timeZone: String?) -> String {
        if let price, let found = fromText(price) { return found }
        if let zone = timeZone, let found = fromZone(zone) { return found }
        return "banknote"
    }

    /// The symbol a price's own text names.
    static func fromText(_ text: String) -> String? {
        if text.contains("£") || code("GBP", in: text) { return "sterlingsign.circle" }
        if text.contains("€") || code("EUR", in: text) { return "eurosign.circle" }
        if text.contains("¥") || code("JPY", in: text) { return "yensign.circle" }
        if code("CHF", in: text) { return "francsign.circle" }
        if text.contains("$") { return "dollarsign.circle" }
        return nil
    }

    /// "EUR 12" names the euro; "Europe" does not.
    private static func code(_ code: String, in text: String) -> Bool {
        text.range(of: "\\b\(code)\\b", options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Sterling, the euro, the Swiss franc, the yen and the dollar, by IANA
    /// zone. The euro list is the euro area's zones (and the microstates that
    /// use it); a zone in a country with a currency of its own is not in it.
    static func fromZone(_ identifier: String) -> String? {
        if sterling.contains(identifier) { return "sterlingsign.circle" }
        if euro.contains(identifier) { return "eurosign.circle" }
        if identifier == "Europe/Zurich" || identifier == "Europe/Vaduz" { return "francsign.circle" }
        if identifier == "Asia/Tokyo" { return "yensign.circle" }
        if dollar.contains(identifier) || identifier.hasPrefix("Australia/") { return "dollarsign.circle" }
        return nil
    }

    private static let sterling: Set<String> = [
        "Europe/London", "Europe/Belfast", "Europe/Guernsey", "Europe/Jersey", "Europe/Isle_of_Man", "Atlantic/Stanley",
    ]

    private static let euro: Set<String> = [
        "Europe/Rome", "Europe/Vatican", "Europe/San_Marino", "Europe/Paris", "Europe/Monaco", "Europe/Berlin",
        "Europe/Busingen", "Europe/Madrid", "Africa/Ceuta", "Atlantic/Canary", "Europe/Lisbon", "Atlantic/Madeira",
        "Atlantic/Azores", "Europe/Amsterdam", "Europe/Brussels", "Europe/Luxembourg", "Europe/Vienna", "Europe/Dublin",
        "Europe/Helsinki", "Europe/Mariehamn", "Europe/Athens", "Europe/Malta", "Asia/Nicosia", "Asia/Famagusta",
        "Europe/Nicosia", "Europe/Tallinn", "Europe/Riga", "Europe/Vilnius", "Europe/Bratislava", "Europe/Ljubljana",
        "Europe/Zagreb", "Europe/Andorra", "Europe/Podgorica", "Europe/Kosovo",
    ]

    private static let dollar: Set<String> = [
        "America/New_York", "America/Chicago", "America/Denver", "America/Phoenix", "America/Los_Angeles",
        "America/Anchorage", "Pacific/Honolulu", "America/Detroit", "America/Boise",
        "America/Toronto", "America/Vancouver", "America/Edmonton", "America/Winnipeg", "America/Halifax",
        "Pacific/Auckland", "Asia/Singapore", "Asia/Hong_Kong",
    ]
}
