import MapKit
import SwiftUI

/// One-tap lines to the whole family, and the bat phone, on Home's msg family
/// tile and in msg family's "Family now" (John, 2026-10-27: "more quick
/// actions, including a button … that says something innocuous like bat
/// phone"). The Chat page lists the same lines down the page instead
/// (`FamilyQuickList`): "the quick messages should be a vertical list".
///
/// A quick line SENDS — unlike the composer's chips, which only fill the box —
/// so for five seconds after, the strip offers to take it back: a thumb on a
/// tile is not the same as pressing Send.
struct FamilyQuickStrip: View {
    /// On a tile's own colour (Home), rather than the page's paper (Threads).
    var onFill = false
    var identifier = "family-quick"
    @ObservedObject private var store = FamilyMessagesStore.shared
    /// The line just sent, while it can still be taken back.
    @State private var sent: String?

    var body: some View {
        Group {
            if let sent {
                sentRow(sent)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        BatPhoneButton(onFill: onFill)
                        if let here = FamilyComposerAccessories.whereIAm() {
                            chip("📍 Where I am", id: "\(identifier)-where") { send(here) }
                        }
                        ForEach(FamilyMessageTools.quickSend, id: \.self) { line in
                            chip(line, id: "\(identifier)-\(line)") { send(line) }
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private func send(_ line: String) {
        Task {
            guard await store.send(line) else { return }
            withAnimation(.snappy) { sent = line }
            try? await Task.sleep(for: FamilyQuickSend.undoWindow)
            if sent == line { withAnimation(.snappy) { sent = nil } }
        }
    }

    private func undo(_ line: String) {
        withAnimation(.snappy) { sent = nil }
        FamilyQuickSend.takeBack(line)
    }

    private func sentRow(_ line: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").accessibilityHidden(true)
            Text("Sent “\(line)”")
                .font(SR.Text.bodyMedium(13))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Button("Undo") { undo(line) }
                .font(SR.Text.title(13))
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .background(Capsule().fill(onFill ? Color.white.opacity(0.28) : SR.surface))
                .buttonStyle(.plain)
                .accessibilityIdentifier("\(identifier)-undo")
        }
        .foregroundStyle(onFill ? Color.white : SR.ink)
        .frame(minHeight: 34)
        .transition(.opacity)
    }

    private func chip(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button {
            SRHaptic.select()
            action()
        } label: {
            Text(title)
                .lineLimit(1)
                .font(SR.Text.bodyMedium(13))
                .foregroundStyle(onFill ? Color.white : SR.ink)
                .padding(.horizontal, 11)
                .frame(minHeight: 34)
                .background(Capsule().fill(onFill ? Color.white.opacity(0.22) : SR.surface))
                .overlay(Capsule().strokeBorder(onFill ? Color.clear : SR.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(store.isBusy("new"))
        .accessibilityHint("Sends this to everyone in the family")
        .accessibilityIdentifier(id)
    }
}

/// What a quick line and the bat phone share: taking back what was just sent.
enum FamilyQuickSend {
    /// How long a quick line can be taken back with one tap.
    static let undoWindow: Duration = .seconds(5)

    /// The newest of mine with those words: the one just sent.
    @MainActor
    static func takeBack(_ line: String) {
        let store = FamilyMessagesStore.shared
        guard let mine = store.thread.last(where: { $0.mine && $0.body == line }) else { return }
        Task { _ = await store.delete(mine.id) }
    }
}

/// The quick lines down the page, for the Chat page's family side (John,
/// 2026-10-27: "quick messages should be a vertical list"). One tap sends,
/// like the strip; the row then says so and offers Undo for five seconds.
struct FamilyQuickList: View {
    var identifier = "family-quick-list"
    @ObservedObject private var store = FamilyMessagesStore.shared
    @State private var sent: String?
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 48

    var body: some View {
        let here = FamilyComposerAccessories.whereIAm()
        let lines = (here.map { [$0] } ?? []) + FamilyMessageTools.quickSend
        VStack(spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.element) { index, line in
                if index > 0 { Divider().overlay(SR.divider).padding(.leading, 48) }
                row(line, icon: line == here ? "location.fill" : "paperplane",
                    id: line == here ? "\(identifier)-where" : "\(identifier)-\(line)")
            }
        }
        .srGlassCard(.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private func row(_ line: String, icon: String, id: String) -> some View {
        HStack(spacing: 0) {
            Button {
                SRHaptic.select()
                send(line)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: sent == line ? "checkmark.circle.fill" : icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(sent == line ? SR.good : SR.accentDeep)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    Text(sent == line ? "Sent “\(line)”" : line)
                        .font(SR.Text.body(16))
                        .foregroundStyle(SR.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                }
                .padding(.leading, 12)
                .frame(minHeight: rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.isBusy("new") || sent == line)
            .accessibilityLabel(sent == line ? "Sent \(line)" : line)
            .accessibilityHint(sent == line ? "" : "Sends this to everyone in the family")
            .accessibilityIdentifier(id)

            if sent == line {
                Button("Undo") {
                    withAnimation(.snappy) { sent = nil }
                    FamilyQuickSend.takeBack(line)
                }
                .font(SR.Text.title(14))
                .foregroundStyle(SR.accentDeep)
                .padding(.horizontal, 14)
                .frame(minHeight: rowHeight)
                .buttonStyle(.plain)
                .accessibilityIdentifier("\(identifier)-undo")
                .transition(.opacity)
            }
        }
    }

    private func send(_ line: String) {
        Task {
            guard await store.send(line) else { return }
            withAnimation(.snappy) { sent = line }
            try? await Task.sleep(for: FamilyQuickSend.undoWindow)
            if sent == line { withAnimation(.snappy) { sent = nil } }
        }
    }
}

// MARK: - Bat phone

/// The bat phone's send, shared by every button that shows it — Home's top
/// row, msg family's quick strip, the Chat page's big one, and the app icon's
/// quick action — so each of them shows "sent" and can take it back.
///
/// Since 2026-10-27 (John: "it shouldn't raise the alarm it should just
/// message the group") it is a msg family MESSAGE — "🦇 Bat phone — I need
/// you.", where, the battery and a map link (`BatPhoneWords.message`) — sent
/// quietly: no buzz, sound or banner on this phone. It used to raise the
/// family alarm's quiet kind, which took over everyone else's screen with a
/// siren for what is usually "come and get me".
@MainActor
final class BatPhone: ObservableObject {
    static let shared = BatPhone()

    struct Sent: Equatable {
        let body: String
        let at: Date
    }

    @Published private(set) var sending = false
    /// What went, while it can still be taken back.
    @Published private(set) var sent: Sent?
    @Published private(set) var failed = false

    /// How long "Take back" is offered: long enough to notice a pocket
    /// press, short enough that nobody has already set off.
    static let undoWindow: TimeInterval = 60

    /// Where, the battery and the place's name, each only if it comes fast,
    /// then the message. True when it went.
    @discardableResult
    func send() async -> Bool {
        guard !sending else { return false }
        sending = true
        failed = false
        defer { sending = false }
        let battery = FamilyAlarmStore.batteryLevel()
        let here = await OneFix.current(timeout: .seconds(4))
        var place: String?
        if SRDemo.isOn {
            // The demo's made-up fix has a made-up name: no geocoder call.
            place = "Central Park, New York"
        } else if let here {
            place = await FamilyAlarmStore.placeName(here)
        }
        let body = BatPhoneWords.message(place: place, battery: battery, lat: here?.latitude, lon: here?.longitude)
        guard await FamilyMessagesStore.shared.send(body, quiet: true) else {
            failed = true
            return false
        }
        let at = Date()
        sent = Sent(body: body, at: at)
        Task {
            try? await Task.sleep(for: .seconds(Self.undoWindow))
            if sent?.at == at { sent = nil }
        }
        return true
    }

    /// Delete the message just sent. True when it went.
    @discardableResult
    func takeBack() async -> Bool {
        guard let sent else { return false }
        let store = FamilyMessagesStore.shared
        if !store.thread.contains(where: { $0.mine && $0.body == sent.body }) { await store.load() }
        guard let mine = store.thread.last(where: { $0.mine && $0.body == sent.body }),
              await store.delete(mine.id) else { return false }
        self.sent = nil
        return true
    }
}

/// "Bat phone": one press messages the whole family that you need them, with
/// where you are, your battery and a map link (`BatPhone`). Nothing sounds or
/// shows on this phone; for a minute after, it offers to take it back.
///
/// Two sizes. `.compact` looks like any other quick action, for Home's top
/// row and the quick strip: two taps, not a hold, because a hold inside a
/// Home tile is the tile's long-press menu, and a pop-up asking "Are you
/// sure?" is exactly what a person who needs this to be discreet cannot have
/// on the screen. The first tap arms it for three seconds ("Tap to send");
/// the second sends.
///
/// `.large` is the Chat page's (John: "bat phone button should be bigger but
/// with a guard protecting accidental pressing"): a press and hold, with a
/// ring that fills over a second and a half — let go early and nothing is
/// sent. VoiceOver gets a plain action instead, since a double-tap is already
/// deliberate.
struct BatPhoneButton: View {
    enum Size { case compact, large }

    var onFill = false
    var size: Size = .compact
    @ObservedObject private var bat = BatPhone.shared
    @State private var armed = false
    @State private var confirmingUndo = false
    /// The large button's ring: 0 at rest, 1 when the hold has been long enough.
    @State private var progress: CGFloat = 0
    @ScaledMetric(relativeTo: .title) private var ring: CGFloat = 58

    /// How long the large button must be held.
    static let hold: Double = 1.5

    var body: some View {
        switch size {
        case .compact: compact
        case .large: large
        }
    }

    // MARK: Compact

    private var compact: some View {
        Button {
            tapped()
        } label: {
            HStack(spacing: 5) {
                if bat.sending {
                    ProgressView().controlSize(.mini).tint(onFill ? .white : SR.ink)
                } else {
                    Image(systemName: bat.sent != nil ? "checkmark" : FamilyAlarmKind.quiet.symbol)
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
                Text(compactTitle).lineLimit(1)
            }
            .font(SR.Text.bodyMedium(13))
            .foregroundStyle(onFill ? Color.white : SR.ink)
            .padding(.horizontal, 11)
            .frame(minHeight: 34)
            .background(Capsule().fill(compactFill))
            .overlay(Capsule().strokeBorder(onFill || armed ? Color.clear : SR.line, lineWidth: 1))
            .animation(.snappy, value: armed)
        }
        .buttonStyle(.plain)
        .disabled(bat.sending)
        .accessibilityLabel(bat.sent != nil ? "Bat phone sent" : armed ? "Bat phone, tap again to send" : "Bat phone")
        .accessibilityHint(bat.sent != nil ? "Offers to take it back"
                           : "Tap twice to quietly message your family that you need them, with where you are and your battery")
        .accessibilityIdentifier("bat-phone")
        .confirmationDialog("Bat phone sent to the family", isPresented: $confirmingUndo, titleVisibility: .visible) {
            Button("Take it back", role: .destructive) { Task { await bat.takeBack() } }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Taking it back deletes the message. Anyone who already saw the notification has seen it.")
        }
    }

    private var compactTitle: String {
        if bat.sent != nil { return "Bat phone · sent" }
        if bat.failed { return "Bat phone · retry" }
        return armed ? "Tap to send" : "Bat phone"
    }

    private var compactFill: Color {
        if armed { return onFill ? Color.white.opacity(0.42) : SR.accentDeep.opacity(0.22) }
        return onFill ? Color.white.opacity(0.22) : SR.surface
    }

    private func tapped() {
        if bat.sent != nil {
            confirmingUndo = true
            return
        }
        guard armed else {
            SRHaptic.select()
            armed = true
            Task {
                try? await Task.sleep(for: .seconds(3))
                armed = false
            }
            return
        }
        armed = false
        fire()
    }

    /// A buzz the holder feels and nobody hears; no sound, no banner.
    private func fire() {
        SRHaptic.tap()
        Task { await bat.send() }
    }

    // MARK: Large

    private var large: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(SR.error.opacity(0.18), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: bat.sent != nil ? 1 : progress)
                        .stroke(bat.sent != nil ? SR.good : SR.error, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    if bat.sending {
                        ProgressView().tint(SR.error)
                    } else {
                        Image(systemName: bat.sent != nil ? "checkmark" : FamilyAlarmKind.quiet.symbol)
                            .font(.system(size: ring * 0.36, weight: .semibold))
                            .foregroundStyle(bat.sent != nil ? SR.good : SR.error)
                    }
                }
                .frame(width: min(ring, 84), height: min(ring, 84))
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Bat phone")
                        .font(SR.Text.title(20))
                        .foregroundStyle(SR.ink)
                    Text(largeDetail)
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(bat.failed ? SR.error : SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                    .fill(SR.error.opacity(0.08 + 0.14 * progress))
            )
            .overlay(
                RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                    .strokeBorder(SR.error.opacity(0.45), lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous))
            .onLongPressGesture(minimumDuration: Self.hold, maximumDistance: 40) {
                progress = 0
                fire()
            } onPressingChanged: { pressing in
                guard bat.sent == nil, !bat.sending else { return }
                if pressing {
                    SRHaptic.select()
                    withAnimation(.linear(duration: Self.hold)) { progress = 1 }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
                }
            }
            .allowsHitTesting(bat.sent == nil && !bat.sending)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(bat.sent != nil ? "Bat phone sent" : "Bat phone")
            .accessibilityValue(bat.failed ? "Not sent. Try again." : "")
            .accessibilityHint(bat.sent != nil ? ""
                               : "Messages your family that you need them, with where you are and your battery. Nothing sounds on your phone.")
            .accessibilityAction { if bat.sent == nil && !bat.sending { fire() } }
            .accessibilityIdentifier("bat-phone-large")

            if bat.sent != nil {
                Button {
                    SRHaptic.select()
                    Task { await bat.takeBack() }
                } label: {
                    Label("Take it back", systemImage: "arrow.uturn.backward")
                        .font(SR.Text.bodyMedium(14))
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .srButton(.regular)
                .accessibilityHint("Deletes the bat phone message")
                .accessibilityIdentifier("bat-phone-undo")
                .transition(.opacity)
            }
        }
        .animation(.snappy, value: bat.sent)
    }

    private var largeDetail: String {
        if bat.sending { return "Sending…" }
        if bat.sent != nil { return "Sent to the family, with where you are. Nothing showed or sounded here." }
        if bat.failed { return FamilyMessagesStore.shared.message.map { "Not sent: \($0) Hold to try again." } ?? "Not sent. Hold to try again." }
        if progress > 0 { return "Keep holding…" }
        return "Hold for a second and a half to message the family that you need them, with where you are."
    }
}

/// The drive from this phone to a bat phone, from Apple Maps: "14 min drive
/// from you", or nil when there is no answer (no location, no route).
enum BatPhoneDrive {
    @MainActor
    static func from(here destination: CLLocationCoordinate2D) async -> String? {
        if SRDemo.isOn { return BatPhoneWords.drive(seconds: 14 * 60) }
        let request = MKDirections.Request()
        request.source = MKMapItem.forCurrentLocation()
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .automobile
        let eta = try? await MKDirections(request: request).calculateETA()
        return BatPhoneWords.drive(seconds: eta?.expectedTravelTime)
    }
}
