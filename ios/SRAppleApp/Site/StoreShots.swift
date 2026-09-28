import Foundation

// MARK: - App Store screenshots
//
// `-SRStoreShots` (DEBUG, with `-SRDemo`; see `SRDemo.isStoreShots`) runs the
// same demo fixtures for the App Store listing, which must not show another
// company's name or product. The fixtures name real news desks, real model
// families and real services because the showcase screenshots are for
// reviewing the look against what the site really sends; the store pictures
// swap each for a neutral, made-up name, on the way out of `SRDemoFixtures`.
//
// A text swap on the JSON, not a second set of fixtures: every screen stays
// exactly as the showcase draws it, and a new brand in a fixture is one line
// here. Ids and keys are left alone (`hn:41200001` still routes).

enum SRStoreShots {
    /// Longest first where one contains another.
    static let swaps: [(String, String)] = [
        // News desks, their hosts, and their post prefixes.
        ("Show HN: ", ""),
        ("Ask HN: ", ""),
        ("Hacker News", "Tech Wire"),
        ("Financial Times", "Market Ledger"),
        ("\"BBC\"", "\"World Desk\""),
        ("Lobsters", "Dev Digest"),
        ("news.ycombinator.com", "techwire.example"),
        ("lobste.rs", "devdigest.example"),
        ("www.bbc.co.uk", "worlddesk.example"),
        ("bbc.co.uk", "worlddesk.example"),
        ("www.ft.com", "marketledger.example"),
        ("ft.com", "marketledger.example"),
        ("github.com", "code.example"),
        // The model picker.
        ("GPT-6 Astra", "Astra"),
        ("GPT-5.6 Sol", "Sol"),
        ("Claude Sonnet 5", "Lyric"),
        ("GLM 5.2", "Compact"),
        ("codex/gpt-6-astra", "astra"),
        ("codex/gpt-5.6-sol", "sol"),
        ("anthropic/claude-sonnet-5", "lyric"),
        ("claude-sonnet-4-5", "lyric"),
        ("z-ai/glm-5.2", "compact"),
        // Other companies' products.
        ("WHOOP's", "the strap's"),
        ("WHOOP", "strap"),
        ("iPhone", "Phone"),
        ("Gmail", "Mail"),
        ("Google", "the mail provider"),
    ]

    static func scrub(_ json: String) -> String {
        swaps.reduce(json) { text, swap in text.replacingOccurrences(of: swap.0, with: swap.1) }
    }
}
