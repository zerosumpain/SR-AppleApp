import SwiftUI
import UIKit

// The big moments over the town — founded, a new tier, a round number of
// people — and the how-to-play sheet. A moment comes from
// `HometownsMilestones` (remembered on this phone, so each is shown once) or
// from the town arriving on the frame after Found.

/// A moment worth stopping the map for.
struct HometownsMoment: Identifiable, Equatable {
    enum Kind: Equatable {
        case founded
        case tierUp(Int)
        case population(Int)
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let line: String
    let animal: String
    let flag: Int
    let tier: Int
}

/// The card for a moment: the mayor in a burst of light, a line, confetti
/// (not under Reduce Motion), a success buzz, and one big button. Tapping
/// outside the card closes it too.
struct HometownsMomentCard: View {
    let moment: HometownsMoment
    let level: HometownsCopyLevel
    /// "See what's new": the Build sheet, after a new tier.
    var openBuild: (() -> Void)? = nil
    let done: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @ScaledMetric(relativeTo: .title) private var badge: CGFloat = 92

    var body: some View {
        ZStack {
            Color.black.opacity(0.38)
                .ignoresSafeArea()
                .onTapGesture { done() }
                .accessibilityHidden(true)
            if !reduceMotion {
                HometownsConfetti()
                    .ignoresSafeArea()
            }
            card
                .scaleEffect(shown || reduceMotion ? 1 : 0.86)
                .opacity(shown ? 1 : 0)
        }
        .onAppear {
            // One success buzz per moment: the store already buzzes when a
            // frame brings a new tier, and the founding screen when Found
            // succeeds, so only a head-count milestone buzzes here.
            if case .population = moment.kind { SRHaptic.ok() }
            UIAccessibility.post(notification: .announcement, argument: moment.title)
            if reduceMotion {
                shown = true
            } else {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) { shown = true }
            }
        }
        .accessibilityIdentifier("hometowns-moment")
    }

    private var kicker: String {
        switch moment.kind {
        case .founded: return level == .kid ? "YOUR NEW TOWN" : "FOUNDED"
        case .tierUp: return level == .kid ? "YOUR TOWN GREW UP" : "NEW TIER"
        case .population: return level == .kid ? "MORE PEOPLE" : "MILESTONE"
        }
    }

    private var card: some View {
        VStack(spacing: 14) {
            burst
            Text(kicker)
                .font(SR.Text.label())
                .tracking(SR.kickerTracking)
                .foregroundStyle(SR.accent)
            Text(moment.title)
                .font(SR.Text.display(24))
                .foregroundStyle(SR.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(moment.line)
                .font(SR.Text.body())
                .foregroundStyle(SR.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HometownsTierLadder(tier: moment.tier, level: level)
                .padding(.vertical, 4)
            buttons
        }
        .padding(22)
        .frame(maxWidth: 380)
        .srGlassCard(.paper)
        .padding(.horizontal, SR.gutter)
        .accessibilityElement(children: .contain)
        // VoiceOver stays on the card while it is up, not on the map under it.
        .accessibilityAddTraits(.isModal)
    }

    private var burst: some View {
        ZStack {
            HometownsSunburst()
                .fill(SR.accent.opacity(0.18))
                .frame(width: badge * 1.7, height: badge * 1.7)
                .rotationEffect(.degrees(shown && !reduceMotion ? 24 : 0))
                .animation(reduceMotion ? nil : .easeOut(duration: 3), value: shown)
            HometownsCritterBadge(animal: moment.animal, ground: HometownsColour.flag(moment.flag), size: badge)
                .shadow(color: Color.black.opacity(0.18), radius: 10, y: 4)
        }
        .frame(height: badge * 1.4)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var buttons: some View {
        VStack(spacing: 10) {
            Button {
                done()
            } label: {
                HometownsBigLabel(title: level == .kid ? "Hooray!" : "Lovely", icon: "sparkles", fill: true)
            }
            .srButton(.prominent)
            .accessibilityIdentifier("hometowns-moment-done")
            if let openBuild {
                Button {
                    openBuild()
                } label: {
                    HometownsBigLabel(title: "See what's new", icon: "hammer.fill", fill: true)
                }
                .srButton(.regular)
                .accessibilityIdentifier("hometowns-moment-build")
            }
        }
    }
}

/// Rays from the middle, for a moment's burst of light.
struct HometownsSunburst: Shape {
    var rays = 14

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let step = Double.pi * 2 / Double(max(1, rays))
        for i in 0..<rays {
            let a = Double(i) * step
            let b = a + step * 0.45
            path.move(to: centre)
            path.addLine(to: CGPoint(x: centre.x + radius * CGFloat(cos(a)), y: centre.y + radius * CGFloat(sin(a))))
            path.addLine(to: CGPoint(x: centre.x + radius * CGFloat(cos(b)), y: centre.y + radius * CGFloat(sin(b))))
            path.closeSubpath()
        }
        return path
    }
}

/// Hamlet → Village → Town → City → Metropolis, with the town's own tier lit.
struct HometownsTierLadder: View {
    let tier: Int
    let level: HometownsCopyLevel
    @ScaledMetric(relativeTo: .caption) private var dot: CGFloat = 30

    static let icons = ["house.fill", "house.and.flag.fill", "building.fill", "building.2.fill", "building.columns.fill"]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { t in
                VStack(spacing: 4) {
                    Image(systemName: Self.icons[t])
                        .font(.system(size: dot * 0.42, weight: .semibold))
                        .foregroundStyle(t <= tier ? SR.paper : SR.inkMuted)
                        .frame(width: dot, height: dot)
                        .background(Circle().fill(t <= tier ? SR.accent : SR.line))
                        .overlay(Circle().stroke(t == tier ? SR.ink.opacity(0.6) : Color.clear, lineWidth: 2))
                    Text(HometownsCopy.shared.say("tier.\(t)", level, or: HometownsCatalogue.tierName(t)))
                        .font(SR.Text.label(12))
                        .foregroundStyle(t == tier ? SR.ink : SR.inkMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(HometownsCopy.shared.say("tier.\(min(max(tier, 0), 4))", level, or: HometownsCatalogue.tierName(tier))), step \(min(max(tier, 0), 4) + 1) of 5")
    }
}

// MARK: - How to play

/// Hometowns in five steps, from Bramble, for the menu and the founding screen.
struct HometownsHowToPlaySheet: View {
    let level: HometownsCopyLevel
    @Environment(\.dismiss) private var dismiss

    struct Step: Identifiable {
        let id: Int
        let icon: String
        let colour: Color
        let title: String
        let line: String
    }

    private var kid: Bool { level == .kid }

    private var steps: [Step] {
        [
            Step(id: 1, icon: "flag.fill", colour: Color(hex: 0xD6463A), title: kid ? "Start your town" : "Found your town",
                 line: kid ? "Pick a place near Kingsport, make a name and choose your animal mayor."
                     : "Choose a site around Kingsport, name the town and pick an animal mayor."),
            Step(id: 2, icon: "hammer.fill", colour: HometownsZoneStyle.colour("shops"), title: "Plan, then build",
                 line: kid ? "Tap Build, then draw roads and paint homes, shops and farms on the map. See-through plans are free until you tap Build it!"
                     : "Pick a tool in Build and drag on the map. Ghosts are free and undoable; the forecast shows the cost, the money and the people before you tap Build it!"),
            Step(id: 3, icon: "clock.fill", colour: HometownsZoneStyle.colour("farms"), title: "Watch it grow",
                 line: kid ? "Your first weeks go as fast as you like: tap Next week. After that, people move in while you're away."
                     : "The Founding Fortnight runs as fast as you tap Next week. After that the town grows on the county clock, even with the app shut."),
            Step(id: 4, icon: "face.smiling", colour: HometownsZoneStyle.colour("homes"), title: "Keep people happy",
                 line: kid ? "The bars at the top show what your town wants. The animal helpers give you tips."
                     : "The Wants bar shows demand. Advisors suggest one thing at a time; People shows every face's needs and what they say."),
            Step(id: 5, icon: "sun.max.fill", colour: Color(hex: 0xE0A030), title: "Regional Day",
                 line: kid ? "Once a day the whole county settles up and the morning news comes out."
                     : "Once a day the county settles up: the Morning Bulletin, the money and the season's standings."),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SR.sectionGap) {
                    hello
                    VStack(spacing: SR.cardGap) {
                        ForEach(steps) { step in row(step) }
                    }
                    ladder
                }
                .padding(.horizontal, SR.gutter)
                .padding(.vertical, 12)
            }
            .srGround(.warm)
            .navigationTitle("How to play")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .accessibilityIdentifier("hometowns-how-to-play")
    }

    private var hello: some View {
        HStack(alignment: .center, spacing: 14) {
            HometownsMascot(advisor: "bramble", size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text("BRAMBLE THE BADGER")
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                Text(kid ? "Build a town, keep its people happy, and watch it grow into a city!"
                     : "Build a town around Kingsport, keep its people happy, and grow it from a hamlet to a metropolis.")
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func row(_ step: Step) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(step.colour)
                Image(systemName: step.icon)
                    .font(SR.Text.title(18))
                    .foregroundStyle(Color.white)
            }
            .frame(width: 46, height: 46)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(step.id). \(step.title)")
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                Text(step.line)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
    }

    private var ladder: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: kid ? "Grow your town" : "The tiers")
            VStack(alignment: .leading, spacing: 10) {
                HometownsTierLadder(tier: 0, level: level)
                Text(kid ? "More people means bigger buildings, more to build and more to see."
                     : "Each tier opens new buildings, zones, taxes and lenses.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(SR.cardPadding)
            .srGlassCard(.paper)
        }
    }
}
