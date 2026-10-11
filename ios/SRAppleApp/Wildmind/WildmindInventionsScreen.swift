import SwiftUI

/// Inventions: everything made in this valley, newest first, each opening to
/// what it is, how it is made, why it works and what the referee said; then
/// the ideas the referee turned down.
///
/// `GET api/native/wildmind/inventions` through `WildmindFeeds.inventions`,
/// polled every minute while the page is up.
struct WildmindInventionsScreen: View {
    @ObservedObject private var feed = WildmindFeeds.inventions
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "wildmind", title: "Inventions",
                             strap: "Everything made in this valley, newest first, and the ideas the referee turned down.")
                if feed.phase == .ready, let reply = feed.value {
                    if feed.stale { WildmindStaleNote() }
                    made(reply)
                    refused(reply)
                } else {
                    WildmindLaneStateView(phase: feed.phase, what: "Inventions") {
                        Task { await feed.load() }
                    }
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .accessibilityIdentifier("wildmind-inventions-screen")
        .srGround(.wire)
        .navigationTitle("Inventions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { SRBarMark() } }
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            await feed.poll(every: .seconds(60))
        }
        .srRefreshable { await feed.load() }
    }

    private func made(_ reply: WildmindInventions) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Made here", trailing: "\(reply.inventions.count)")
            if reply.inventions.isEmpty {
                Text("Nothing invented yet. The first idea is usually a tool.")
                    .font(SR.Text.secondary(15))
                    .foregroundStyle(SR.inkMuted)
            } else {
                VStack(spacing: SR.cardGap) {
                    ForEach(reply.inventions) { invention in
                        NavigationLink(value: WildmindPage.invention(invention)) {
                            row(invention)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("wildmind-invention-\(invention.id)")
                    }
                }
            }
        }
    }

    private func row(_ invention: WildmindInventionEntry) -> some View {
        SRCard(interactive: true) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(invention.name)
                        .font(SR.Text.title(17))
                        .foregroundStyle(SR.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(WildmindInventionWords.byline(invention))
                        .font(SR.Text.secondary(14))
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if invention.placed {
                    SRGlassChip(text: "placed", icon: "mappin", tone: SR.good)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SR.inkGhost)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func refused(_ reply: WildmindInventions) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Refused ideas", trailing: reply.refused.isEmpty ? nil : "\(reply.refused.count)")
            if reply.refused.isEmpty {
                Text("The referee hasn\u{2019}t turned anything down lately.")
                    .font(SR.Text.secondary(15))
                    .foregroundStyle(SR.inkMuted)
            } else {
                SRCard {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(reply.refused.enumerated()), id: \.offset) { _, refusal in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "xmark.circle")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(SR.error)
                                    .padding(.top, 2)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(refusal.text)
                                        .font(SR.Text.body(15))
                                        .foregroundStyle(SR.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if let when = refusal.when {
                                        Text(when.uppercased())
                                            .font(SR.Text.mono())
                                            .foregroundStyle(SR.inkMuted)
                                    }
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("wildmind-inventions-refused")
    }
}

/// One invention, whole.
struct WildmindInventionScreen: View {
    let invention: WildmindInventionEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                VStack(alignment: .leading, spacing: 12) {
                    SRPageHeader(kicker: invention.kind ?? "invention", title: invention.name)
                    HStack(spacing: 8) {
                        if let inventor = invention.inventor {
                            SRGlassChip(text: inventor, icon: "person", tone: SR.inkSecondary)
                        }
                        if let day = invention.day {
                            SRGlassChip(text: "day \(day)", icon: "sun.max", tone: SR.inkSecondary)
                        }
                        if invention.placed {
                            SRGlassChip(text: "placed", icon: "mappin", tone: SR.good)
                        }
                    }
                }
                section("What it is", invention.description, mono: false)
                section("How it\u{2019}s made", invention.summary, mono: true)
                section("Why it works", invention.rationale, mono: false)
                if !invention.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SRSectionLabel(text: "The referee\u{2019}s notes")
                        SRCard {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(Array(invention.notes.enumerated()), id: \.offset) { _, note in
                                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                                        Circle()
                                            .fill(SR.accent)
                                            .frame(width: 5, height: 5)
                                            .accessibilityHidden(true)
                                        Text(note)
                                            .font(SR.Text.body(15))
                                            .foregroundStyle(SR.ink)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }
                }
                if invention.description == nil && invention.summary == nil && invention.rationale == nil && invention.notes.isEmpty {
                    Text("Nobody wrote anything down about this one.")
                        .font(SR.Text.secondary(15))
                        .foregroundStyle(SR.inkMuted)
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .accessibilityIdentifier("wildmind-invention-screen")
        .srGround(.wire)
        .navigationTitle(invention.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func section(_ title: String, _ text: String?, mono: Bool) -> some View {
        if let text {
            VStack(alignment: .leading, spacing: 10) {
                SRSectionLabel(text: title)
                SRCard {
                    Text(text)
                        .font(mono ? SR.Text.mono(13) : SR.Text.body(16))
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// The few words under an invention's name.
enum WildmindInventionWords {
    /// "Wren · day 4 · container".
    static func byline(_ invention: WildmindInventionEntry) -> String {
        var parts: [String] = []
        if let inventor = invention.inventor { parts.append(inventor) }
        if let day = invention.day { parts.append("day \(day)") }
        if let kind = invention.kind { parts.append(kind) }
        return parts.isEmpty ? "invented here" : parts.joined(separator: " \u{00B7} ")
    }
}
