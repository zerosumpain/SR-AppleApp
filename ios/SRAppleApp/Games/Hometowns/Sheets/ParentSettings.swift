import SwiftUI

/// Parent settings (§9.13), the M1 basics: the county's rivalry, mishaps and
/// Regional Day hour, the pause (solo counties only), and each mayor's seat — a child's or an
/// adult's, pushes, pranks, answering only, gentler advisors.
///
/// Only seats the server knows as parents may change these, and it checks
/// every one (F6). County rules changed mid-day land after the next Regional
/// Day, so nothing a phone has already predicted changes under it. The frame
/// does not carry other seats' settings, so a seat's choices are buttons that
/// SET a value rather than switches that claim to show one.
struct ParentSettingsSheet: View {
    @ObservedObject var store: HometownsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var rivalry = "friendly"
    @State private var mishaps = "mild"
    @State private var hour = 18
    @State private var loaded = false
    @State private var confirmPause = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SR.sectionGap) {
                    if store.isParent {
                        county
                        if store.canPause || store.countyPaused {
                            pause
                        }
                        seats
                    } else {
                        SREmpty(title: "For parents", icon: "lock.fill", message: "Ask a parent to change the county's settings.")
                    }
                }
                .padding(.horizontal, SR.gutter)
                .padding(.vertical, 12)
            }
            .srGround(.warm)
            .navigationTitle("Parent settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: load)
        }
        .presentationDetents([.large])
        .accessibilityIdentifier("hometowns-parent")
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let predict = store.wire?.me?.predict {
            rivalry = predict.rivalry
            mishaps = predict.mishaps
        }
        if let at = store.wire?.clock?.nextRegionalDayAt, at > 0 {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Europe/London") ?? .current
            let h = calendar.component(.hour, from: Date(timeIntervalSince1970: at / 1000))
            if HometownsCountySetup.hours.contains(h) { hour = h }
        }
    }

    // MARK: The county

    private var county: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: store.wire?.county?.name ?? "The county")
            VStack(alignment: .leading, spacing: 14) {
                segmented("Rivalry", selection: $rivalry, options: [("friendly", "Friendly"), ("spirited", "Spirited")], id: "rivalry")
                segmented("Mishaps", selection: $mishaps, options: [("mild", "Mild"), ("off", "Off")], id: "mishaps")
                VStack(alignment: .leading, spacing: 6) {
                    Text("REGIONAL DAY")
                        .font(SR.Text.label())
                        .tracking(SR.kickerTracking)
                        .foregroundStyle(SR.inkSecondary)
                    Picker("Regional Day", selection: $hour) {
                        ForEach(HometownsCountySetup.hours, id: \.self) { Text(HometownsCountySetup.hourLabel($0)).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .tint(SR.accentInk)
                    .accessibilityIdentifier("hometowns-parent-hour")
                }
                Text("Changes start after the next Regional Day. It always falls between 08:00 and 19:00, outside quiet hours.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    store.settings(county: ["rivalry": rivalry, "mishaps": mishaps, "regionalHour": hour])
                } label: {
                    SRButtonLabel(title: "Save the county's settings", icon: "checkmark", fill: true)
                }
                .srButton(.prominent)
                .accessibilityIdentifier("hometowns-parent-save")
            }
            .padding(SR.cardPadding)
            .srGlassCard(.paper)
        }
    }

    private func segmented(_ title: String, selection: Binding<String>, options: [(String, String)], id: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(SR.Text.label())
                .tracking(SR.kickerTracking)
                .foregroundStyle(SR.inkSecondary)
            Picker(title, selection: selection) {
                ForEach(options.indices, id: \.self) { i in Text(options[i].1).tag(options[i].0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("hometowns-parent-\(id)")
        }
    }

    // MARK: Pause

    private var pause: some View {
        let paused: Bool = store.countyPaused
        return VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Pause")
            VStack(alignment: .leading, spacing: 10) {
                Text(paused
                     ? "The county is paused. Nothing grows and nothing is lost until it starts again."
                     : "You play this county on your own, so you can pause it for as long as you like. A second mayor joining starts it again.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    if paused { store.pause(false) } else { confirmPause = true }
                } label: {
                    SRButtonLabel(title: paused ? "Start the county again" : "Pause the county", icon: paused ? "play.fill" : "pause.fill", fill: true)
                }
                .srButton(paused ? .prominent : .regular)
                .accessibilityIdentifier("hometowns-parent-pause")
            }
            .padding(SR.cardPadding)
            .srGlassCard(.paper)
        }
        .confirmationDialog("Pause the county?", isPresented: $confirmPause, titleVisibility: .visible) {
            Button("Pause") { store.pause(true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your town stops until you start it again.")
        }
    }

    // MARK: Seats

    private var seats: some View {
        let players = (store.wire?.players ?? []).filter { $0.seat != nil && $0.status == "joined" }
        return VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Mayors", trailing: "\(players.count)")
            ForEach(players) { player in
                seat(player)
            }
        }
    }

    private func seat(_ player: HometownsPlayer) -> some View {
        let seat = player.seat ?? ""
        let mine = seat == store.wire?.me?.seat
        let town = store.wire?.towns.first { $0.seat == seat }
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(player.name + (mine ? " (you)" : ""))
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                if let town {
                    Text("\(town.name) · \(HometownsCatalogue.tierName(town.tier))")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                }
            }
            if !mine {
                choice("Seat", [("A child's", ["profile": "kid"]), ("An adult's", ["profile": "adult"])], seat: seat)
            }
            choice("Pushes", [("Off", ["pushes": false]), ("On", ["pushes": true])], seat: seat)
            if !mine {
                choice("Pranks", [("Off", ["pranks": false]), ("On", ["pranks": true])], seat: seat)
                choice("Deals", [("Answer only", ["answerOnly": true]), ("Propose too", ["answerOnly": false])], seat: seat)
                choice("Advisors", [("Usual", ["assist": "none"]), ("Gentler", ["assist": "gentle"])], seat: seat)
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityIdentifier("hometowns-parent-seat-\(seat)")
    }

    /// A row of buttons that each set one value on a seat (stacked at the
    /// largest text sizes, where a row would cut the words short). Each
    /// button says what it sets: "Pushes: On", not "On".
    private func choice(_ title: String, _ options: [(String, [String: Any])], seat: String) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            Text(title)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .frame(minWidth: 70, alignment: .leading)
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button {
                    var patch = option.1
                    patch["seat"] = seat
                    store.settings(seat: patch)
                } label: {
                    Text(option.0)
                        .font(SR.Text.label(13))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(minHeight: 36)
                }
                .srButton(.regular)
                .accessibilityLabel("\(title): \(option.0)")
                .accessibilityIdentifier("hometowns-parent-\(seat)-\(title.lowercased())-\(option.0.lowercased())")
            }
            Spacer(minLength: 0)
        }
    }
}
