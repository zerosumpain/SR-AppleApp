import MapKit
import SwiftUI

/// One-tap lines to the whole family, and the bat phone, on Home's msg family
/// tile and over the Threads list (John, 2026-10-27: "more quick actions,
/// including a button … that says something innocuous like bat phone").
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
            try? await Task.sleep(for: .seconds(5))
            if sent == line { withAnimation(.snappy) { sent = nil } }
        }
    }

    /// The newest of mine with those words: the one just sent.
    private func undo(_ line: String) {
        withAnimation(.snappy) { sent = nil }
        guard let mine = store.thread.last(where: { $0.mine && $0.body == line }) else { return }
        Task { _ = await store.delete(mine.id) }
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

/// "Bat phone": looks like any other quick action, and quietly raises the
/// family alarm's `quiet` kind — nothing sounds, lights up or pops up on
/// this phone, while everyone else is told urgently who, where, their
/// battery and how far a drive it is.
///
/// Two taps, not a hold: a hold inside a Home tile is the tile's long-press
/// menu, and a pop-up asking "Are you sure?" is exactly what a person who
/// needs this to be discreet cannot have on the screen. The first tap arms
/// it for three seconds ("Tap to send"); the second sends.
struct BatPhoneButton: View {
    var onFill = false
    @ObservedObject private var alarm = FamilyAlarmStore.shared
    @State private var armed = false
    @State private var failed = false
    @State private var standingDown = false

    private var sent: Bool { alarm.raised?.quiet == true }

    var body: some View {
        Button {
            tapped()
        } label: {
            HStack(spacing: 5) {
                if alarm.sending {
                    ProgressView().controlSize(.mini).tint(onFill ? .white : SR.ink)
                } else {
                    Image(systemName: sent ? "checkmark" : FamilyAlarmKind.quiet.symbol)
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
                Text(title).lineLimit(1)
            }
            .font(SR.Text.bodyMedium(13))
            .foregroundStyle(onFill ? Color.white : SR.ink)
            .padding(.horizontal, 11)
            .frame(minHeight: 34)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(onFill || armed ? Color.clear : SR.line, lineWidth: 1))
            .animation(.snappy, value: armed)
        }
        .buttonStyle(.plain)
        .disabled(alarm.sending)
        .accessibilityLabel(sent ? "Bat phone sent" : armed ? "Bat phone, tap again to send" : "Bat phone")
        .accessibilityHint(sent ? "Opens stand down" : "Tap twice to quietly send your family an urgent alert with where you are and your battery")
        .accessibilityIdentifier("bat-phone")
        .confirmationDialog(standDownTitle, isPresented: $standingDown, titleVisibility: .visible) {
            Button("I'm OK — stand down") { Task { await alarm.standDown() } }
            Button("Keep it going", role: .cancel) {}
        }
    }

    private var title: String {
        if sent { return "Bat phone · sent" }
        if failed { return "Bat phone · retry" }
        return armed ? "Tap to send" : "Bat phone"
    }

    private var fill: Color {
        if armed { return onFill ? Color.white.opacity(0.42) : SR.accentDeep.opacity(0.22) }
        return onFill ? Color.white.opacity(0.22) : SR.surface
    }

    private var standDownTitle: String {
        alarm.raisedTo.map { "Sent to \($0) \($0 == 1 ? "person" : "people")" } ?? "Bat phone sent"
    }

    private func tapped() {
        if sent {
            standingDown = true
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
        // A buzz the holder feels and nobody hears; no sound, no banner.
        SRHaptic.tap()
        Task { failed = !(await alarm.raiseQuietly()) }
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
