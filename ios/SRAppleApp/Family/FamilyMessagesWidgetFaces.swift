import SwiftUI

// msg family's widget and the bat phone's, drawn.
//
// SHARED with the widget extension (`SRAppleLive`, see watch.yml), beside
// `FamilyWidgetShared.swift`'s faces and for the same reason: drawn here
// rather than in the extension so the app's gallery (Settings → Widget
// previews) can show them, which is how CI photographs a widget. Not in that
// file because the share extension compiles it too, and has no messages.
//
// Prism, as the other family widgets: msg family's widget is its Home tile on
// the Home Screen — the family hue as the ground, its type on top. The bat
// phone takes the palette's error tone, so it reads as the one that matters.

/// Which slot a face is drawn for.
enum FamilyMessagesWidgetSize {
    case small, medium, large, circular, rectangular, inline

    var lockScreen: Bool { self == .circular || self == .rectangular || self == .inline }
}

/// msg family: what is unread and who wrote last (small), the latest threads
/// (medium), and the latest five with their answers (large).
struct FamilyMessagesWidgetView: View {
    let snapshot: FamilyMessagesSnapshot?
    let size: FamilyMessagesWidgetSize
    var now = Date()
    var palette: SRWidgetPalette = .prism

    @Environment(\.dynamicTypeSize) private var typeSize

    /// Type on the family hue.
    private var on: Color { SRRGB.color(palette.family.onFill) }

    var body: some View {
        if let snapshot {
            switch size {
            case .small: small(snapshot)
            case .medium: list(snapshot, rows: typeSize >= .xxLarge ? 2 : 3, detail: false)
            case .large: list(snapshot, rows: typeSize >= .xxLarge ? 3 : typeSize >= .large ? 4 : 5, detail: true)
            case .circular: circular(snapshot)
            case .rectangular: rectangular(snapshot)
            case .inline: inline(snapshot)
            }
        } else {
            empty
        }
    }

    // MARK: - Home Screen

    private var kicker: some View {
        Text("MSG FAMILY")
            .font(FamilyWidgetFont.label(10))
            .tracking(0.8)
            .opacity(0.85)
    }

    private func small(_ s: FamilyMessagesSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            kicker
            if s.unread > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(s.unread)")
                        .font(FamilyWidgetFont.display(32))
                    Text("unread")
                        .font(FamilyWidgetFont.label(12))
                        .opacity(0.85)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            } else {
                Label("All read", systemImage: "checkmark.circle.fill")
                    .font(FamilyWidgetFont.label(14))
                    .padding(.top, 6)
            }
            Spacer(minLength: 0)
            if let line = s.threads.first {
                // Whoever wrote last that was not me, else the newest thread's.
                HStack(spacing: 6) {
                    initials(s.newestInitials ?? line.initials, size: 26)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(s.newestFrom ?? line.who)
                            .font(FamilyWidgetFont.label(12))
                            .lineLimit(1)
                        Text(FamilyMessagesWidget.when(line.at, now: now))
                            .font(FamilyWidgetFont.label(10))
                            .opacity(0.8)
                    }
                }
                // Two lines while they fit; one once the reader's text is
                // bigger than the default, or the count is pushed off the top.
                Text(line.latest ?? line.text)
                    .font(FamilyWidgetFont.name(12))
                    .lineLimit(typeSize > .large ? 1 : 2)
                    .opacity(0.92)
            } else {
                Text("No messages yet.")
                    .font(FamilyWidgetFont.name(12))
            }
        }
        .foregroundStyle(on)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summaryLabel(s))
    }

    private func list(_ s: FamilyMessagesSnapshot, rows: Int, detail: Bool) -> some View {
        VStack(alignment: .leading, spacing: detail ? 9 : 7) {
            HStack(alignment: .firstTextBaseline) {
                kicker
                Spacer(minLength: 4)
                if let unread = FamilyMessagesWidget.unreadPhrase(s.unread) {
                    Text(unread)
                        .font(FamilyWidgetFont.label(11))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(on.opacity(0.18)))
                }
            }
            if s.threads.isEmpty {
                Text("No messages yet. Anything sent to the family shows here.")
                    .font(FamilyWidgetFont.name(13))
            }
            ForEach(s.threads.prefix(rows)) { line in
                row(line, detail: detail)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(on)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// One thread: the sender's circle, their name and words, when it last
    /// moved — and, on the large widget, its newest answer and how many.
    private func row(_ line: FamilyMessagesWidgetLine, detail: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            initials(line.initials, size: detail ? 28 : 24)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(line.who)
                        .font(FamilyWidgetFont.label(12))
                        .lineLimit(1)
                    if line.unread {
                        Circle().fill(on).frame(width: 6, height: 6).accessibilityHidden(true)
                    }
                    Spacer(minLength: 4)
                    Text(FamilyMessagesWidget.when(line.at, now: now))
                        .font(FamilyWidgetFont.label(10))
                        .opacity(0.8)
                }
                Text(line.text)
                    .font(FamilyWidgetFont.name(13))
                    .lineLimit(1)
                if detail, let answers = answers(line) {
                    Text(answers)
                        .font(FamilyWidgetFont.label(10))
                        .lineLimit(1)
                        .opacity(0.82)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowLabel(line))
    }

    /// "↳ Robin: On my way · 3 replies".
    private func answers(_ line: FamilyMessagesWidgetLine) -> String? {
        let parts = [line.latest.map { "↳ \($0)" }, FamilyMessagesWidget.repliesPhrase(line.replies)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func initials(_ letters: String, size: CGFloat) -> some View {
        Text(letters)
            .font(FamilyWidgetFont.label(size * 0.42))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: size, height: size)
            .background(Circle().fill(on.opacity(0.2)))
            .accessibilityHidden(true)
    }

    // MARK: - Lock Screen

    private func circular(_ s: FamilyMessagesSnapshot) -> some View {
        VStack(spacing: 0) {
            Image(systemName: s.unread > 0 ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                .font(FamilyWidgetFont.label(14))
            Text("\(s.unread)")
                .font(FamilyWidgetFont.figure(15))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summaryLabel(s))
    }

    private func rectangular(_ s: FamilyMessagesSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(headline(s))
                .font(FamilyWidgetFont.label(13))
                .lineLimit(1)
            if let line = s.threads.first {
                Text("\(line.who): \(line.text)")
                    .font(FamilyWidgetFont.name(12))
                    .lineLimit(1)
            }
            Text("msg family").font(FamilyWidgetFont.label(11)).opacity(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inline(_ s: FamilyMessagesSnapshot) -> some View {
        Label(headline(s), systemImage: "bubble.left.and.bubble.right.fill")
    }

    /// "3 unread · Robin", or "All read".
    private func headline(_ s: FamilyMessagesSnapshot) -> String {
        guard let unread = FamilyMessagesWidget.unreadPhrase(s.unread) else { return "All read" }
        return s.newestFrom.map { "\(unread) · \($0)" } ?? unread
    }

    // MARK: - Words for VoiceOver

    private func summaryLabel(_ s: FamilyMessagesSnapshot) -> String {
        var parts = ["msg family", FamilyMessagesWidget.unreadPhrase(s.unread) ?? "all read"]
        if let line = s.threads.first { parts.append("latest from \(line.who): \(line.latest ?? line.text)") }
        return parts.joined(separator: ", ")
    }

    private func rowLabel(_ line: FamilyMessagesWidgetLine) -> String {
        var parts = ["\(line.who): \(line.text)", FamilyMessagesWidget.when(line.at, now: now)]
        if line.unread { parts.append("unread") }
        if let replies = FamilyMessagesWidget.repliesPhrase(line.replies) { parts.append(replies) }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !size.lockScreen { kicker }
            Text(size == .inline ? "msg family" : "Open SR to see msg family.")
                .font(FamilyWidgetFont.name(13))
        }
        .foregroundStyle(size.lockScreen ? Color.primary : on)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Bat phone

/// The bat phone's symbol and colour, wherever it is drawn outside the app's
/// own button. Not on the view: a `View`'s statics are the main actor's, and
/// the control reads these too.
enum BatPhoneLook {
    /// The same symbol as the bat phone in msg family (`FamilyAlarmKind.quiet`).
    static let symbol = "phone.connection.fill"

    /// The palette's error tone, made into a hue the way a picked colour is.
    static func hue(_ palette: SRWidgetPalette) -> SRHueSpec {
        SRHueSpec.from(palette.error.light, ink: palette.ink.light)
    }
}

/// The bat phone's own button for the Home Screen and the Lock Screen. It
/// sends nothing: a tap opens the app on the bat phone's check
/// (`BatPhoneURL`), where the button that sends is.
struct BatPhoneWidgetView: View {
    let size: FamilyMessagesWidgetSize
    /// Whether this phone can use it: it has been set up with the family.
    var ready = true
    var palette: SRWidgetPalette = .prism

    private var on: Color { SRRGB.color(BatPhoneLook.hue(palette).onFill) }

    var body: some View {
        switch size {
        case .circular:
            Image(systemName: BatPhoneLook.symbol)
                .font(FamilyWidgetFont.display(20))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Bat phone")
        case .rectangular, .inline:
            HStack(spacing: 8) {
                Image(systemName: BatPhoneLook.symbol)
                    .font(FamilyWidgetFont.display(18))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Bat phone").font(FamilyWidgetFont.label(14))
                    Text(ready ? "Asks before it sends" : "Open SR to set up")
                        .font(FamilyWidgetFont.name(12))
                        .opacity(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        default:
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: BatPhoneLook.symbol)
                    .font(FamilyWidgetFont.display(24))
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(on.opacity(0.2)))
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                Text("Bat phone")
                    .font(FamilyWidgetFont.display(22))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(ready ? "Tap, then send from SR" : "Open SR to set up")
                    .font(FamilyWidgetFont.name(12))
                    .lineLimit(2)
                    .opacity(0.9)
            }
            .foregroundStyle(on)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens SR on the bat phone. Nothing is sent from here.")
        }
    }
}
