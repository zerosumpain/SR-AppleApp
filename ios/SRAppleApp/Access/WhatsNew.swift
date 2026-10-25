import SwiftUI

/// "What's new", on the first open after an update.
///
/// The notes are written here, by hand, in the words the family would use —
/// not commit subjects, which say "one policy call per household". Each
/// release has an id of its own rather than a build number: the number is
/// the CI run, unknown when the notes are written, and a rebuild of the same
/// code (a phone added to the ad-hoc profile) must not show them again.
///
/// The phone remembers the ids it has shown. Anything in the app it has not
/// shown yet is new to this person, so the one rule covers an update, a
/// skipped update (both sets of notes), and a TestFlight build alike.
///
/// To add notes: put a release at the TOP of `releases` with a fresh id.
struct WhatsNewRelease: Identifiable, Equatable {
    let id: String
    /// Shown under the title: "October 2026".
    let when: String
    let title: String
    let items: [WhatsNewItem]
}

struct WhatsNewItem: Identifiable, Equatable {
    let icon: String
    let title: String
    let detail: String
    /// Something only the owner can open is not news to anyone else.
    var ownerOnly = false
    var id: String { title }
}

enum WhatsNew {
    /// Newest first.
    static let releases: [WhatsNewRelease] = [
        WhatsNewRelease(id: "2026-10-25-travel", when: "October 2026", title: "Ready for Rome", items: [
            WhatsNewItem(icon: "airplane", title: "Travel kit",
                         detail: "In More. Five tools for abroad that work on the phone, with roaming off."),
            WhatsNewItem(icon: "captions.bubble", title: "Live translate",
                         detail: "Talk with someone in Italian, Spanish, French, German or Portuguese, or caption what is being said. Open it once on Wi-Fi to download the language."),
            WhatsNewItem(icon: "text.viewfinder", title: "Read a sign",
                         detail: "Photograph a menu, a sign or a ticket and read it in English."),
            WhatsNewItem(icon: "book", title: "Phrasebook",
                         detail: "Italian for food, allergies, shops and getting help, said out loud for you."),
            WhatsNewItem(icon: "eurosign.circle", title: "Money",
                         detail: "Pounds and euros both ways, splitting a bill, and what to tip."),
            WhatsNewItem(icon: "location.north.line", title: "Way back",
                         detail: "Pin the hotel, then follow the arrow home or show a taxi driver where to go."),
            WhatsNewItem(icon: "checkerboard.rectangle", title: "Chess fits its box",
                         detail: "The whole board shows now, not just one corner."),
            WhatsNewItem(icon: "sparkles", title: "This screen",
                         detail: "After each update, SR says what changed. It is in Settings → About too."),
        ]),
        WhatsNewRelease(id: "2026-10-24-play-nearby", when: "October 2026", title: "Play nearby", items: [
            WhatsNewItem(icon: "dot.radiowaves.left.and.right", title: "Games without signal",
                         detail: "Twenty games to play with phones in the same room, over Bluetooth or a hotspot. No internet needed."),
        ]),
        WhatsNewRelease(id: "2026-10-23-family-games", when: "October 2026", title: "Family games", items: [
            WhatsNewItem(icon: "gamecontroller", title: "Seven new games",
                         detail: "And a game you leave halfway is still there when you come back."),
        ]),
    ]

    /// How many releases one splash shows. A phone a long way behind sees the
    /// latest few, not a history lesson; About has the rest.
    static let shownAtOnce = 3

    static let seenKey = "whatsNew.seen"

    /// The releases this person has not been shown, trimmed to what they can
    /// use. A release left with no items for them counts as seen.
    static func unseen(in releases: [WhatsNewRelease] = releases, seen: Set<String>, owner: Bool) -> [WhatsNewRelease] {
        releases
            .filter { !seen.contains($0.id) }
            .map { visible($0, owner: owner) }
            .filter { !$0.items.isEmpty }
            .prefix(shownAtOnce)
            .map { $0 }
    }

    /// Every release, for About.
    static func all(owner: Bool) -> [WhatsNewRelease] {
        releases.map { visible($0, owner: owner) }.filter { !$0.items.isEmpty }
    }

    static func visible(_ release: WhatsNewRelease, owner: Bool) -> WhatsNewRelease {
        WhatsNewRelease(id: release.id, when: release.when, title: release.title,
                        items: release.items.filter { owner || !$0.ownerOnly })
    }

    static var seen: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: seenKey) ?? [])
    }

    static func markSeen(_ ids: [String]) {
        UserDefaults.standard.set(Array(seen.union(ids)).sorted(), forKey: seenKey)
    }

    /// At launch, before anything pairs. A fresh install has nothing to be
    /// told: everything in it is new, and Welcome is the introduction. So a
    /// phone with no record and no site pairing starts with every note seen.
    ///
    /// One with no record but a pairing is an update from a build older than
    /// this screen, and is shown what it has missed.
    static func prepareLaunch(paired: Bool) {
        guard UserDefaults.standard.object(forKey: seenKey) == nil, !paired else { return }
        markSeen(releases.map(\.id))
    }

    /// What to show now, if anything. Never in a demo: the review demo is for
    /// someone who has never seen the app, and every screenshot test would
    /// open on this sheet. `-SRWhatsNew` shows it in the showcase anyway.
    @MainActor static func pending(owner: Bool) -> [WhatsNewRelease] {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-SRWhatsNew") {
            return unseen(seen: [], owner: owner)
        }
        #endif
        if SRDemo.isOn { return [] }
        return unseen(seen: seen, owner: owner)
    }
}

/// The splash: the newest release in full, anything else missed below it.
struct WhatsNewSheet: View {
    let releases: [WhatsNewRelease]
    /// From About: the whole history, opened on purpose, nothing to mark.
    var history = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SR.sectionGap) {
                    ForEach(Array(releases.enumerated()), id: \.element.id) { index, release in
                        section(release, first: index == 0)
                    }
                }
                .padding(.horizontal, SR.gutter)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .accessibilityIdentifier("whats-new")
            .safeAreaInset(edge: .bottom) {
                if !history {
                    SRButton(title: "Got it", filled: true) { dismiss() }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, SR.gutter)
                        .padding(.vertical, 12)
                        .accessibilityIdentifier("whats-new-done")
                }
            }
            .srPaper()
            .navigationTitle(history ? String(localized: "What's new") : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if history {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
            }
        }
        .onAppear {
            // Shown, so seen: marked as it appears, not when it closes, so a
            // phone killed with the sheet up is not shown it twice. A sheet
            // that never presented (another modal got there first) never
            // gets here, and is still waiting next time.
            if !history { WhatsNew.markSeen(releases.map(\.id)) }
        }
    }

    @ViewBuilder
    private func section(_ release: WhatsNewRelease, first: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                SRLabel(text: first && !history ? "New in SR · \(release.when)" : release.when)
                Text(release.title)
                    .font(first ? SR.Text.hero(30) : SR.Text.display())
                    .foregroundStyle(SR.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 16) {
                ForEach(release.items) { item in row(item) }
            }
        }
    }

    private func row(_ item: WhatsNewItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: item.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Circle().fill(SR.accent))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                Text(item.detail)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
