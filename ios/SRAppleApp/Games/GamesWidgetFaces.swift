import SwiftUI

// The Games widget, drawn.
//
// SHARED with the widget extension (`SRAppleLive`, see watch.yml), beside the
// family widgets' faces and for the same reason: the app's gallery
// (Settings → Widget previews) draws them too.
//
// Prism: the Games tile on the Home Screen — the games hue as the ground, its
// type on top. Nothing here plays: a row opens its room in the app, and the
// rest of the widget opens the Games tab.

/// What wants you: invites (first), games where it is your move, and how
/// the last one ended.
struct GamesWidgetView: View {
    let snapshot: GamesWidgetSnapshot?
    let size: FamilyMessagesWidgetSize
    var now = Date()
    var palette: SRWidgetPalette = .prism

    @Environment(\.dynamicTypeSize) private var typeSize

    /// Type on the games hue.
    private var on: Color { SRRGB.color(palette.gamesHue.onFill) }

    var body: some View {
        if let snapshot {
            let s = GamesWidget.live(snapshot, now: now)
            switch size {
            case .small: small(s)
            case .medium, .large: medium(s)
            case .circular: circular(s)
            case .rectangular: rectangular(s)
            case .inline: Label("Games · \(GamesWidget.headline(s))", systemImage: "gamecontroller.fill")
            }
        } else {
            empty
        }
    }

    private var kicker: some View {
        Text("GAMES")
            .font(FamilyWidgetFont.label(10))
            .tracking(0.8)
            .opacity(0.85)
    }

    // MARK: - Home Screen

    private func small(_ s: GamesWidgetSnapshot) -> some View {
        let first = (s.invites + s.moves).first
        return VStack(alignment: .leading, spacing: 3) {
            kicker
            if s.invites.isEmpty && s.moves.isEmpty {
                Label("All quiet", systemImage: "checkmark.circle.fill")
                    .font(FamilyWidgetFont.label(14))
                    .padding(.top, 6)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(GamesWidget.waiting(s))")
                        .font(FamilyWidgetFont.display(32))
                    Text(s.invites.isEmpty ? "your move" : (GamesWidget.waiting(s) == 1 ? "invite" : "waiting"))
                        .font(FamilyWidgetFont.label(12))
                        .opacity(0.85)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            if let row = first ?? s.last {
                Label(row.title, systemImage: GamesWidget.symbol(row.kind))
                    .font(FamilyWidgetFont.label(12))
                    .lineLimit(1)
                Text(GamesWidget.detail(row, now: now))
                    .font(FamilyWidgetFont.name(12))
                    .lineLimit(typeSize > .large ? 1 : 2)
                    .opacity(0.92)
            } else {
                Text("Start a game in SR.")
                    .font(FamilyWidgetFont.name(12))
            }
        }
        .foregroundStyle(on)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(s))
    }

    private func medium(_ s: GamesWidgetSnapshot) -> some View {
        let rows = GamesWidget.rows(s, limit: typeSize >= .xxLarge ? 2 : 3)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                kicker
                Spacer(minLength: 4)
                Text(GamesWidget.headline(s))
                    .font(FamilyWidgetFont.label(11))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(on.opacity(0.18)))
                    .lineLimit(1)
            }
            if rows.isEmpty {
                Text("Nothing waiting. Start a game in SR and it shows here.")
                    .font(FamilyWidgetFont.name(13))
            }
            ForEach(rows) { row in
                // Each row opens its own room; the rest of the widget, Games.
                Link(destination: GlanceLink.gameURL(room: row.roomId, game: row.game)) {
                    line(row)
                }
            }
            if s.playing > 0 {
                Text(s.playing == 1 ? "1 more on the go" : "\(s.playing) more on the go")
                    .font(FamilyWidgetFont.label(10))
                    .opacity(0.8)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(on)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func line(_ row: GamesWidgetRow) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: GamesWidget.symbol(row.kind))
                .font(FamilyWidgetFont.label(12))
                .frame(width: 26, height: 26)
                .background(Circle().fill(on.opacity(row.kind == .result ? 0.12 : 0.22)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(row.title)
                    .font(FamilyWidgetFont.label(13))
                    .lineLimit(1)
                Text(GamesWidget.detail(row, now: now))
                    .font(FamilyWidgetFont.name(11))
                    .lineLimit(1)
                    .opacity(0.9)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.title), \(GamesWidget.detail(row, now: now))")
    }

    // MARK: - Lock Screen

    private func circular(_ s: GamesWidgetSnapshot) -> some View {
        VStack(spacing: 0) {
            Image(systemName: GamesWidget.waiting(s) > 0 ? "gamecontroller.fill" : "gamecontroller")
                .font(FamilyWidgetFont.label(14))
            Text("\(GamesWidget.waiting(s))")
                .font(FamilyWidgetFont.figure(15))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(s))
    }

    private func rectangular(_ s: GamesWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(GamesWidget.headline(s))
                .font(FamilyWidgetFont.label(13))
                .lineLimit(1)
            if let row = GamesWidget.rows(s, limit: 1).first {
                Text("\(row.title) · \(GamesWidget.detail(row, now: now))")
                    .font(FamilyWidgetFont.name(12))
                    .lineLimit(1)
            }
            Text("Games").font(FamilyWidgetFont.label(11)).opacity(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(s))
    }

    // MARK: - Words for VoiceOver

    private func spoken(_ s: GamesWidgetSnapshot) -> String {
        var parts = ["Games", GamesWidget.headline(s)]
        for row in GamesWidget.rows(s, limit: 3) { parts.append("\(row.title), \(GamesWidget.detail(row, now: now))") }
        return parts.joined(separator: ". ")
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !size.lockScreen { kicker }
            Text(size == .inline ? "Games" : "Open SR to see your games.")
                .font(FamilyWidgetFont.name(13))
        }
        .foregroundStyle(size.lockScreen ? Color.primary : on)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
