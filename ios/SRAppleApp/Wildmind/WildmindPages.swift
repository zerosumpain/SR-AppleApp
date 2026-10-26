import SwiftUI

/// The pages the Wildmind page opens: Talk (with the whisper composer),
/// Chronicle, Inventions and one invention. Pushed on More's stack, which
/// registers `WildmindPageView` for them (`ContentView`).
enum WildmindPage: Hashable {
    /// The valley in 3D, full-screen (`WildmindWorldScreen`).
    case world
    /// `compose`: open with the whisper composer focused.
    case talk(compose: Bool)
    case chronicle
    case inventions
    case invention(WildmindInventionEntry)
}

struct WildmindPageView: View {
    let page: WildmindPage

    var body: some View {
        switch page {
        case .world: WildmindWorldScreen()
        case .talk(let compose): WildmindTalkScreen(compose: compose)
        case .chronicle: WildmindChronicleScreen()
        case .inventions: WildmindInventionsScreen()
        case .invention(let invention): WildmindInventionScreen(invention: invention)
        }
    }
}

/// What an owner page says while it has nothing to show, plainly: asking,
/// the valley quiet, the site too old for the route, this phone refused, or
/// a failure with a way to try again. Never a spinner that does not end —
/// the ask behind it times out.
struct WildmindLaneStateView: View {
    let phase: WildmindLoadPhase
    /// "Talk", "The chronicle", "Inventions": what needs a newer site.
    let what: String
    let retry: () -> Void

    var body: some View {
        switch phase {
        case .loading, .ready:
            VStack(spacing: 12) {
                ProgressView()
                Text("Asking the valley\u{2026}")
                    .font(SR.Text.secondary(14))
                    .foregroundStyle(SR.inkMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
            .accessibilityIdentifier("wildmind-lane-loading")
        case .offline:
            SREmpty(
                title: "The valley\u{2019}s quiet",
                icon: "moon.zzz",
                message: "Wildmind isn\u{2019}t answering the site just now, so there\u{2019}s nothing new to read. It\u{2019}ll be here when it wakes.",
                actionLabel: "Try again",
                action: retry
            )
            .accessibilityIdentifier("wildmind-lane-offline")
        case .notOnSite:
            SREmpty(
                title: "Not on the site yet",
                icon: "map",
                message: "\(what) needs a newer site than this one. It\u{2019}ll be here once the site catches up."
            )
            .accessibilityIdentifier("wildmind-lane-not-on-site")
        case .missing:
            SREmpty(
                title: "Nobody by that name",
                icon: "person.crop.circle.badge.questionmark",
                message: "This valley has nobody by that name just now."
            )
        case .refused:
            SREmpty(
                title: "Not on this phone",
                icon: "lock",
                message: "The valley\u{2019}s words are read on the owner\u{2019}s phone."
            )
        case .failed(let message):
            SREmpty(
                title: "The valley didn\u{2019}t answer",
                icon: "wifi.slash",
                message: message,
                actionLabel: "Try again",
                action: retry
            )
        }
    }
}

/// A filter chip, as News sets its views: mono, glass, accent when chosen.
struct WildmindChip: View {
    let label: String
    let selected: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button {
            SRHaptic.select()
            action()
        } label: {
            Text(label.uppercased())
                .font(SR.Text.label())
                .tracking(1.2)
                .foregroundStyle(selected ? SR.paper : SR.inkSecondary)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(minHeight: 38)
                .srGlass(selected ? .accent : .paper, in: Capsule(), interactive: true)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// A "the last ask failed" line over what was shown before.
struct WildmindStaleNote: View {
    var text = "The valley stopped answering, so this is what it last said."

    var body: some View {
        Label(text, systemImage: "clock.arrow.circlepath")
            .font(SR.Text.secondary(14))
            .foregroundStyle(SR.inkMuted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension WildmindTone {
    /// By id: JKai in the accent, Wren in the petrol ink, anyone else ochre.
    static func of(who: String?) -> Color {
        switch who {
        case "main"?: return SR.accent
        case "companion"?: return SR.accentInk
        default: return other
        }
    }
}
