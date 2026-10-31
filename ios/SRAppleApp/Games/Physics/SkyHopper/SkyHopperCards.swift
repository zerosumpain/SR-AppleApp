import SwiftUI

/// Before a run: how to play, tilt or buttons, Hop's colour, then Play.
struct SkyHopperIntroCard: View {
    @ObservedObject var session: SkyHopperSession

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SkyHopperCardHolder {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    howTo
                    controls
                    colours
                }
            }
            playButton
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sky-hopper-intro")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SKY HOPPER")
                .font(SR.Text.label())
                .tracking(SR.inkKickerTracking)
                .foregroundStyle(SR.accent)
            Text("Bounce from cloud to cloud. Don't look down.")
                .font(SR.Text.display(22))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var howTo: some View {
        VStack(alignment: .leading, spacing: 10) {
            SkyHopperHowRow(icon: "arrow.left.and.right",
                            text: "Hop bounces by itself. Steer left and right to land on the next cloud. The sides wrap round.")
            SkyHopperHowRow(icon: "arrow.up.to.line", text: "Springs launch you high. Stars are worth \(SkyHopperRules.starPoints) points each.",
                            tint: SkyHopperInk.starDeep)
            SkyHopperHowRow(icon: "fanblades.fill", text: "Grab a propeller cap to fly, a bubble to save a fall, a magnet for stars.",
                            tint: SkyHopperInk.cap)
            SkyHopperHowRow(icon: "cloud.fill", text: "Crumbly clouds take one bounce. See-through ones come and go.",
                            tint: SkyHopperInk.crack)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STEER WITH")
                .font(SR.Text.label())
                .tracking(SR.inkLabelTracking)
                .foregroundStyle(SR.inkMuted)
            HStack(spacing: 8) {
                ForEach(SkyHopperControl.allCases) { control in
                    SkyHopperControlTile(control: control, selected: session.control == control,
                                         enabled: control == .buttons || session.tilt.available,
                                         best: session.records.best(control).score) {
                        session.choose(control)
                    }
                }
            }
            Text(controlLine)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var controlLine: String {
        if session.scripted { return "In the demo, Hop flies itself." }
        if !session.tilt.available { return "This phone can't tilt to steer, so the big arrows are on." }
        let best = session.best
        let line = session.control.line
        return best > 0 ? "\(line) Best: \(best)." : line
    }

    private var colours: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("COLOUR")
                .font(SR.Text.label())
                .tracking(SR.inkLabelTracking)
                .foregroundStyle(SR.inkMuted)
            HStack(spacing: 4) {
                ForEach(SkyHopperColour.allCases) { colour in
                    SkyHopperColourSwatch(colour: colour, open: session.records.isUnlocked(colour),
                                          selected: session.colour == colour) {
                        session.choose(colour: colour)
                    }
                }
            }
            Text(colourLine)
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var colourLine: String {
        let stars = session.records.totalStars
        let got = stars == 1 ? "1 star collected" : "\(stars) stars collected"
        guard let next = session.records.nextColour else { return "\(got). Every colour is yours." }
        return "\(got). \(next.title) opens at \(next.unlockStars)."
    }

    private var playButton: some View {
        Button {
            SRHaptic.tap()
            session.play()
        } label: {
            SRButtonLabel(title: "Play", icon: "play.fill", fill: true)
                .frame(minHeight: 48)
        }
        .srButton(.prominent)
        .controlSize(.large)
        .accessibilityIdentifier("sky-hopper-start")
    }
}

/// Mid-run, the clock stopped.
struct SkyHopperPauseCard: View {
    @ObservedObject var session: SkyHopperSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PAUSED")
                .font(SR.Text.label())
                .tracking(SR.inkKickerTracking)
                .foregroundStyle(SR.accent)
            Text("\(session.metres) m up, \(session.stars == 1 ? "1 star" : "\(session.stars) stars")")
                .font(SR.Text.display(22))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("\(session.zone.name). Hop waits in mid-air: tap the sky to carry on.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                session.resume()
            } label: {
                SRButtonLabel(title: "Resume", icon: "play.fill", fill: true)
                    .frame(minHeight: 48)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .accessibilityIdentifier("sky-hopper-resume")
            HStack(spacing: 10) {
                Button {
                    SRHaptic.tap()
                    session.play()
                } label: {
                    SRButtonLabel(title: "Restart", icon: "arrow.counterclockwise", fill: true)
                        .frame(minHeight: 48)
                }
                .srButton(.regular)
                .controlSize(.large)
                .accessibilityIdentifier("sky-hopper-restart")
                Button {
                    SRHaptic.tap()
                    session.menu()
                } label: {
                    SRButtonLabel(title: "Menu", icon: "slider.horizontal.3", fill: true)
                        .frame(minHeight: 48)
                }
                .srButton(.regular)
                .controlSize(.large)
                .accessibilityIdentifier("sky-hopper-menu")
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sky-hopper-paused")
    }
}

/// The end of a run: how it ended, how high, the stars, the best, and any
/// colour it opened.
struct SkyHopperOverCard: View {
    let result: SkyHopperRunResult
    let onAgain: () -> Void
    let onMenu: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SkyHopperCardHolder {
                VStack(alignment: .leading, spacing: 12) {
                    kicker
                    Text(result.fall.sentence)
                        .font(SR.Text.display(22))
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(tip)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    chips
                    Text(tally)
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    openings
                }
            }
            buttons
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sky-hopper-over")
    }

    private var kicker: some View {
        HStack(spacing: 8) {
            Image(systemName: result.newBest ? "trophy.fill" : "cloud.fill")
                .font(.system(size: 18, weight: .bold))
                .accessibilityHidden(true)
            Text(result.newBest ? "NEW BEST" : "GAME OVER")
                .font(SR.Text.label())
                .tracking(SR.inkKickerTracking)
        }
        .foregroundStyle(result.newBest ? SR.good : SR.error)
    }

    private var chips: some View {
        HStack(spacing: 8) {
            SkyHopperStatChip(label: "HEIGHT", value: "\(result.metres) m")
            SkyHopperStatChip(label: "STARS", value: "\(result.stars)")
            SkyHopperStatChip(label: "SCORE", value: "\(result.score)")
        }
    }

    private var tip: String {
        if result.newBest { return "Your best yet with \(result.control.title.lowercased()). Can you go higher?" }
        return "Best with \(result.control.title.lowercased()): \(result.best). \(result.fall.tip)"
    }

    private var tally: String {
        var parts = ["Reached \(result.zone.name)"]
        if result.springs > 0 { parts.append(result.springs == 1 ? "1 spring" : "\(result.springs) springs") }
        if result.powerUps > 0 { parts.append(result.powerUps == 1 ? "1 power-up" : "\(result.powerUps) power-ups") }
        if result.saves > 0 { parts.append(result.saves == 1 ? "saved once" : "saved \(result.saves) times") }
        return parts.joined(separator: ", ") + "."
    }

    @ViewBuilder
    private var openings: some View {
        if !result.unlockedColours.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(result.unlockedColours, id: \.self) { name in
                    SkyHopperHowRow(icon: "paintpalette.fill", text: "New colour: \(name). Pick it on the menu.", tint: SR.good)
                }
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Button {
                SRHaptic.tap()
                onAgain()
            } label: {
                SRButtonLabel(title: "Play again", icon: "arrow.counterclockwise", fill: true)
                    .frame(minHeight: 48)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .accessibilityIdentifier("sky-hopper-again")
            Button {
                SRHaptic.tap()
                onMenu()
            } label: {
                SRButtonLabel(title: "Menu", icon: "slider.horizontal.3", fill: true)
                    .frame(minHeight: 48)
            }
            .srButton(.regular)
            .controlSize(.large)
            .accessibilityIdentifier("sky-hopper-over-menu")
        }
    }
}

/// Tilt or Buttons, with that way's best.
struct SkyHopperControlTile: View {
    let control: SkyHopperControl
    let selected: Bool
    let enabled: Bool
    let best: Int
    let action: () -> Void

    var body: some View {
        Button {
            SRHaptic.select()
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: control.icon)
                    .font(.system(size: 18, weight: .bold))
                    .accessibilityHidden(true)
                Text(control.title)
                    .font(SR.Text.title(15))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(best > 0 ? "Best \(best)" : "No best yet")
                    .font(SR.Text.mono(11))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .opacity(0.8)
            }
            .foregroundStyle(selected ? Color.white : SR.ink)
            .frame(maxWidth: .infinity, minHeight: 72)
            .padding(.vertical, 4)
            .background(tileFace)
            .contentShape(Rectangle())
        }
        .buttonStyle(SRPressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel(control.title)
        .accessibilityHint(control.line)
        .accessibilityAddTraits(selected ? AccessibilityTraits.isSelected : AccessibilityTraits())
        .accessibilityIdentifier("sky-hopper-control-\(control.rawValue)")
    }

    private var tileFace: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(selected ? SR.accent : SR.ink.opacity(0.07))
    }
}

/// One of Hop's colours: a little round Hop, locked until enough stars.
struct SkyHopperColourSwatch: View {
    let colour: SkyHopperColour
    let open: Bool
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            SRHaptic.select()
            action()
        } label: {
            ZStack {
                Circle()
                    .fill(fill)
                    .frame(width: 38, height: 38)
                    .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1))
                    .opacity(open ? 1 : 0.35)
                if open {
                    eyes
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(SR.ink)
                }
                Circle()
                    .stroke(selected ? SR.accent : Color.clear, lineWidth: 3)
                    .frame(width: 48, height: 48)
            }
            .frame(width: 52, height: 52)
            .contentShape(Circle())
        }
        .buttonStyle(SRPressStyle())
        .accessibilityLabel(open ? colour.title : "\(colour.title), locked. Collect \(colour.unlockStars) stars in all to open it.")
        .accessibilityAddTraits(selected ? AccessibilityTraits.isSelected : AccessibilityTraits())
        .accessibilityIdentifier("sky-hopper-colour-\(colour.rawValue)")
    }

    private var eyes: some View {
        HStack(spacing: 5) {
            Circle().fill(SkyHopperInk.eye).frame(width: 6, height: 7)
            Circle().fill(SkyHopperInk.eye).frame(width: 6, height: 7)
        }
        .offset(y: -3)
        .accessibilityHidden(true)
    }

    private var fill: AnyShapeStyle {
        let paint = SkyHopperHopPaint.of(colour)
        if paint.rainbow {
            let colours: [Color] = [0.0, 0.16, 0.33, 0.5, 0.66, 0.83].map { Color(hue: $0, saturation: 0.62, brightness: 0.98) }
            return AnyShapeStyle(AngularGradient(colors: colours, center: .center, startAngle: .degrees(0), endAngle: .degrees(360)))
        }
        return AnyShapeStyle(LinearGradient(colors: [paint.light, paint.main, paint.dark], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

/// One line of how to play: an icon in a tinted circle and the words.
struct SkyHopperHowRow: View {
    let icon: String
    let text: String
    var tint: Color = SR.accent

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(Circle().fill(tint.opacity(0.14)))
                .accessibilityHidden(true)
            Text(text)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A small figure with its label, on the results card.
struct SkyHopperStatChip: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(SR.Text.label())
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
            Text(value)
                .font(SR.Text.title())
                .foregroundStyle(SR.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous).fill(SR.ink.opacity(0.06)))
        .accessibilityElement(children: .combine)
    }
}

/// Keeps a card on screen whatever the text size: as it is when it fits,
/// scrolling when the reader's setting makes it taller than the room left.
struct SkyHopperCardHolder<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
    }
}
