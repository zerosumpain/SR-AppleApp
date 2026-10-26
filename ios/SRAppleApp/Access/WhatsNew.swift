import SwiftUI
import UIKit

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
        WhatsNewRelease(id: "2026-10-26-captures", when: "October 2026", title: "Say it once", items: [
            WhatsNewItem(icon: "waveform.badge.mic", title: "Captures",
                         detail: "In More. Record a thought or a conversation: it is written out on the phone, voices are told apart, and the site suggests follow-ups that run only when you approve them.",
                         ownerOnly: true),
            WhatsNewItem(icon: "button.horizontal.top.press", title: "From anywhere",
                         detail: "Start and stop a capture with the Action Button, Back Tap or a Control Center control, with the timer on the Lock Screen. A Shortcut can add a screenshot. Set it up in Settings → Captures.",
                         ownerOnly: true),
            WhatsNewItem(icon: "magnifyingglass", title: "Find what was said",
                         detail: "Search your captures by words, person, app or date, and open anyone mentioned to see every capture they are in.",
                         ownerOnly: true),
        ]),
        WhatsNewRelease(id: "2026-10-26-chess-valley", when: "October 2026", title: "Blue against red", items: [
            WhatsNewItem(icon: "checkerboard.rectangle", title: "Chess in colour",
                         detail: "Pieces are blue and red now, the board edge shows whose turn it is, and a Captured card counts what each side has taken."),
            WhatsNewItem(icon: "mountain.2", title: "Walk the valley",
                         detail: "Wildmind opens the 3D valley on the phone, with the desktop's panels and controls.",
                         ownerOnly: true),
        ]),
        WhatsNewRelease(id: "2026-10-26-forecast", when: "October 2026", title: "Better guesses", items: [
            WhatsNewItem(icon: "figure.walk.motion", title: "Walking, cycling or driving",
                         detail: "The phone now says how you were moving, so journey times and arrival guesses stop mixing up a bike ride with a car."),
            WhatsNewItem(icon: "heart.text.square", title: "Who sees your health",
                         detail: "If you upload from Apple Health, John can now see your week as a summary - steps, sleep and workouts. You see your own on the website, nobody else does, and you can turn uploads off in Settings → Apple Health."),
            WhatsNewItem(icon: "calendar.day.timeline.left", title: "The rest of today",
                         detail: "The website lays out where everyone's routines usually take them for the rest of the day, and skips the school run in the holidays."),
        ]),
        WhatsNewRelease(id: "2026-10-25-hometowns", when: "October 2026", title: "Build a town", items: [
            WhatsNewItem(icon: "building.2", title: "Hometowns",
                         detail: "In Games. Each of you builds a town around Kingsport, and a year passes every day. Playing alone, you can pause it."),
            WhatsNewItem(icon: "location.north.circle", title: "Family Orbit turns with you",
                         detail: "On the Family tab the Orbit centres on you and turns as the phone does, so everyone is shown the way they really are. The compass button puts north back at the top."),
            WhatsNewItem(icon: "map", title: "Trip planning on the phone",
                         detail: "The planner suggests changes with what each one costs, asks its questions as cards you can answer from a notification, and Share → SR adds a place to a trip.",
                         ownerOnly: true),
            WhatsNewItem(icon: "sparkles.rectangle.stack", title: "Daydream cards stay put",
                         detail: "A card you rate stays where it is until you leave the screen.",
                         ownerOnly: true),
        ]),
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
    /// this screen, and is shown what it has missed. Undecided while the phone
    /// has not been unlocked since it started: the pairing cannot be read then,
    /// and "not paired" would be a guess that loses every note.
    static func prepareLaunch(paired: Bool, protectedDataAvailable: Bool = true) {
        guard UserDefaults.standard.object(forKey: seenKey) == nil, protectedDataAvailable, !paired else { return }
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
    @Environment(\.scenePhase) private var scenePhase

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
        // Seen once it is on screen in front of somebody: an active scene, not
        // merely presented. iOS relaunches the app in the background after an
        // update (a location wake, a push, a refresh) and SwiftUI builds the
        // window then too; marking on appear there lost the notes unseen
        // (build 154, 10-25). Not on close, so a phone killed with the sheet
        // up is not shown it twice.
        .onAppear { markIfSeen(scenePhase) }
        .onChange(of: scenePhase) { _, phase in markIfSeen(phase) }
    }

    private func markIfSeen(_ phase: ScenePhase) {
        guard !history, phase == .active, UIApplication.shared.applicationState == .active else { return }
        WhatsNew.markSeen(releases.map(\.id))
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
