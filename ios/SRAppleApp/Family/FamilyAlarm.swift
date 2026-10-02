import AVFoundation
import AudioToolbox
import CoreLocation
import SwiftUI
import UserNotifications

/// The family alarm: "I am in danger", raised from the Family tab, ringing
/// every other family phone as loudly as iOS allows.
///
/// ## How loud is "as loudly as iOS allows"
///
/// - **App open (or opened from the alert):** the siren plays on a `.playback`
///   audio session, which iOS does NOT silence with the ring/silent switch,
///   on a loop until somebody taps Silence, with the phone vibrating under it.
///   It plays at the phone's media volume — no app may raise the system
///   volume itself.
/// - **App in the background or the phone locked:** the push carries the same
///   siren or morse file as its sound (28 s), time-sensitive so it breaks
///   through a Focus that allows it. A switched-to-silent phone vibrates but
///   stays quiet; only a CRITICAL alert overrides the switch, and that needs
///   Apple's Critical Alerts entitlement. The site sends critical alerts the
///   moment `APNS_CRITICAL_ALERTS=1` is set — after Apple grants it and the
///   entitlement is in the provisioning profile (an entitlement the profile
///   lacks fails the archive, so it is NOT in `SRAppleApp.entitlements` yet).
/// - **The push is usually redacted:** a phone with notification details off
///   (the default) gets "Family alarm" with no name or place, so the app
///   fills both in from `GET /api/native/family/alarm` as soon as it rings.
/// - **A phone that cannot be pushed** (no site pairing, or a push lost):
///   the Family tab polls `GET /api/native/family/alarm` while it is open, and
///   the app checks once on every return to the foreground.
struct FamilyAlarm: Decodable, Equatable, Identifiable {
    let alarmId: String
    let from: String
    let name: String
    /// `siren` or `morse`.
    let kind: String
    let message: String?
    let lat: Double?
    let lon: Double?
    let at: String
    let cancelledAt: String?

    var id: String { alarmId }
    var cancelled: Bool { cancelledAt != nil }

    /// From a push's custom keys — the same fields at the payload's top level.
    init?(userInfo: [AnyHashable: Any]) {
        guard let id = userInfo["alarmId"] as? String else { return nil }
        alarmId = id
        from = userInfo["from"] as? String ?? ""
        name = userInfo["name"] as? String ?? "Someone in the family"
        kind = userInfo["kind"] as? String ?? "siren"
        message = userInfo["message"] as? String
        lat = (userInfo["lat"] as? NSNumber)?.doubleValue
        lon = (userInfo["lon"] as? NSNumber)?.doubleValue
        at = userInfo["at"] as? String ?? timestamp(Date())
        cancelledAt = nil
    }

    init(alarmId: String, from: String, name: String, kind: String, message: String?,
         lat: Double?, lon: Double?, at: String, cancelledAt: String?) {
        self.alarmId = alarmId
        self.from = from
        self.name = name
        self.kind = kind
        self.message = message
        self.lat = lat
        self.lon = lon
        self.at = at
        self.cancelledAt = cancelledAt
    }
}

enum FamilyAlarmKind: String, CaseIterable, Identifiable {
    case siren
    case morse

    var id: String { rawValue }
    var title: String { self == .siren ? "Siren" : "Morse SOS" }
    var detail: String { self == .siren ? "A rising and falling wail" : "··· ––– ··· beeping, over and over" }
    var symbol: String { self == .siren ? "light.beacon.max.fill" : "dot.radiowaves.left.and.right" }
    /// The bundled file, and the push's `sound` — the names must match the
    /// site's (`sr-siren.caf`, `sr-morse.caf`).
    var sound: String { self == .siren ? "sr-siren" : "sr-morse" }
}

// MARK: - The store

@MainActor
final class FamilyAlarmStore: ObservableObject {
    static let shared = FamilyAlarmStore()
    static let category = "family-alarm"
    static let cancelCategory = "family-alarm-cancel"
    private static let seenKey = "family-alarm-seen"

    /// Somebody else's alarm, on screen until it is dismissed.
    @Published var incoming: FamilyAlarm?
    /// The alarm this phone raised, until it is stood down.
    @Published private(set) var raised: FamilyAlarm?
    @Published private(set) var raisedTo: Int?
    @Published private(set) var sending = false
    @Published var failure: String?

    /// Alarms already dismissed here, so a poll does not ring them twice.
    private var seen: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.seenKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue.suffix(100)), forKey: Self.seenKey) }
    }

    /// Only where the site will answer: family, with the site credential.
    var available: Bool { AccessStore.shared.familyBoards }

    // MARK: Raising

    func raise(_ kind: FamilyAlarmKind, message: String) async {
        guard !sending else { return }
        sending = true
        failure = nil
        defer { sending = false }
        struct Reply: Decodable { let alarmId: String; let pushed: Int; let recipients: Int }
        var body: [String: Any] = ["kind": kind.rawValue]
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { body["message"] = String(trimmed.prefix(140)) }
        // Where they are, if a fix comes quickly — the alarm must not wait
        // ten seconds on a GPS that may never answer indoors.
        let here = await OneFix.current(timeout: .seconds(4))
        if let here { body["position"] = ["lat": here.latitude, "lon": here.longitude] }
        do {
            let data = try JSONSerialization.data(withJSONObject: body)
            // asSelf: an alarm is from THIS phone's person, whoever is being viewed.
            let reply: Reply = try await SiteClient.shared.send("api/native/family/alarm", method: "POST", body: data, asSelf: true)
            raised = FamilyAlarm(alarmId: reply.alarmId, from: "", name: "You", kind: kind.rawValue,
                                 message: body["message"] as? String, lat: here?.latitude, lon: here?.longitude,
                                 at: timestamp(Date()), cancelledAt: nil)
            raisedTo = reply.recipients
            SRHaptic.ok()
        } catch {
            failure = "The alarm did not send: \(error.localizedDescription) If you are in danger, call 999."
            SRHaptic.bad()
        }
    }

    func standDown() async {
        guard let raised else { return }
        do {
            let data = try JSONSerialization.data(withJSONObject: ["alarmId": raised.alarmId])
            struct Reply: Decodable { let ok: Bool? }
            let _: Reply = try await SiteClient.shared.send("api/native/family/alarm/cancel", method: "POST", body: data, asSelf: true)
            self.raised = nil
            raisedTo = nil
        } catch {
            failure = "Could not stand the alarm down: \(error.localizedDescription)"
        }
    }

    // MARK: Receiving

    /// A push arrived (or was tapped). Ring, unless it was already dismissed.
    func receive(_ alarm: FamilyAlarm) {
        guard !seen.contains(alarm.alarmId), !alarm.cancelled else { return }
        // The same alarm again (a poll after the push): keep ringing, and
        // keep whichever copy says more.
        if incoming?.alarmId == alarm.alarmId {
            if alarm.lat != nil || alarm.message != nil { incoming = alarm }
            return
        }
        incoming = alarm
        AlarmPlayer.shared.start(FamilyAlarmKind(rawValue: alarm.kind) ?? .siren)
        // Most phones get the push REDACTED — "Family alarm", no name, no
        // place — because notification details are off by default. The
        // site's list has who and where.
        if alarm.lat == nil { Task { await poll() } }
    }

    /// The sender stood it down: stop ringing, and say so.
    func cancelled(_ alarmId: String) {
        guard incoming?.alarmId == alarmId else { return }
        AlarmPlayer.shared.stop()
        if let alarm = incoming {
            incoming = FamilyAlarm(alarmId: alarm.alarmId, from: alarm.from, name: alarm.name, kind: alarm.kind,
                                   message: alarm.message, lat: alarm.lat, lon: alarm.lon, at: alarm.at,
                                   cancelledAt: timestamp(Date()))
        }
    }

    /// The pull floor: anything active this phone has not dismissed rings.
    func poll() async {
        guard available, !SRDemo.isOn else { return }
        struct Reply: Decodable { let alarms: [FamilyAlarm] }
        guard let reply: Reply = try? await SiteClient.shared.send("api/native/family/alarm", asSelf: true) else { return }
        // The list holds only ACTIVE alarms: one that has dropped out of it
        // was stood down (or is over half an hour old).
        if let current = incoming, !current.cancelled {
            if let fresh = reply.alarms.first(where: { $0.alarmId == current.alarmId }) {
                receive(fresh)
            } else {
                cancelled(current.alarmId)
            }
        }
        if incoming == nil, let next = reply.alarms.first(where: { !$0.cancelled && !seen.contains($0.alarmId) }) {
            receive(next)
        }
    }

    func silence() { AlarmPlayer.shared.stop() }

    func dismiss() {
        AlarmPlayer.shared.stop()
        if let id = incoming?.alarmId { seen.insert(id) }
        incoming = nil
    }
}

// MARK: - The sound

/// The siren on a loop, through the silent switch, with the phone vibrating.
@MainActor
final class AlarmPlayer {
    static let shared = AlarmPlayer()
    private var player: AVAudioPlayer?
    private var buzz: Task<Void, Never>?

    func start(_ kind: FamilyAlarmKind) {
        stop()
        let session = AVAudioSession.sharedInstance()
        // `.playback` is the category the ring/silent switch does not mute.
        // Not mixable: this is the only thing that should be heard.
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)
        if let url = Bundle.main.url(forResource: kind.sound, withExtension: "caf"),
           let player = try? AVAudioPlayer(contentsOf: url) {
            player.numberOfLoops = -1
            player.volume = 1
            player.play()
            self.player = player
        }
        buzz = Task {
            while !Task.isCancelled {
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                try? await Task.sleep(for: .seconds(1.2))
            }
        }
    }

    func stop() {
        player?.stop()
        player = nil
        buzz?.cancel()
        buzz = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// MARK: - Raising it

/// The red button on the Family tab's bar.
struct FamilyAlarmButton: View {
    @ObservedObject private var store = FamilyAlarmStore.shared
    @State private var open = false

    var body: some View {
        Button {
            SRHaptic.tap()
            open = true
        } label: {
            Image(systemName: store.raised == nil ? "sos.circle.fill" : "light.beacon.max.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, SR.error)
                .font(.system(size: 20, weight: .bold))
                .symbolEffect(.pulse, options: .repeating, isActive: store.raised != nil)
        }
        .accessibilityLabel(store.raised == nil ? "Raise the alarm" : "Alarm raised")
        .accessibilityIdentifier("family-alarm")
        .sheet(isPresented: $open) { RaiseAlarmSheet() }
    }
}

/// Choose the sound, say something if there is time, then HOLD to raise —
/// a tap in a pocket must not wake the family at three in the morning.
struct RaiseAlarmSheet: View {
    @ObservedObject private var store = FamilyAlarmStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var kind: FamilyAlarmKind = .siren
    @State private var message = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let raised = store.raised {
                        raisedCard(raised)
                    } else {
                        Text("Every other phone in the family rings loudly, with where you are. Use it when you need help now.")
                            .font(SR.Text.body())
                            .foregroundStyle(SR.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        VStack(spacing: 10) {
                            ForEach(FamilyAlarmKind.allCases) { option in
                                kindRow(option)
                            }
                        }
                        TextField("Optional: what is happening", text: $message, axis: .vertical)
                            .font(SR.Text.body())
                            .lineLimit(1...3)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(SR.surface))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(SR.line, lineWidth: 1))
                        HoldToRaise(sending: store.sending) {
                            Task { await store.raise(kind, message: message) }
                        }
                    }
                    if let failure = store.failure {
                        Text(failure)
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.error)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("If you are in immediate danger, call 999 as well. This tells your family; it does not call the emergency services.")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(SR.gutter)
            }
            .srGround(.warm)
            .navigationTitle("Raise the alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }

    private func kindRow(_ option: FamilyAlarmKind) -> some View {
        Button {
            SRHaptic.select()
            kind = option
        } label: {
            HStack(spacing: 12) {
                Image(systemName: option.symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(kind == option ? SR.error : SR.inkMuted)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title).font(SR.Text.title()).foregroundStyle(SR.ink)
                    Text(option.detail).font(SR.Text.secondary(13)).foregroundStyle(SR.inkSecondary)
                }
                Spacer()
                Image(systemName: kind == option ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(kind == option ? SR.error : SR.inkGhost)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(kind == option ? SR.error.opacity(0.08) : SR.surface))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(kind == option ? SR.error.opacity(0.5) : SR.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(kind == option ? .isSelected : [])
        .accessibilityIdentifier("family-alarm-kind-\(option.rawValue)")
    }

    private func raisedCard(_ raised: FamilyAlarm) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "light.beacon.max.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(SR.error)
                    .symbolEffect(.pulse, options: .repeating)
                Text("ALARM RAISED")
                    .font(SR.Text.display(24))
                    .foregroundStyle(SR.error)
            }
            Text(store.raisedTo.map { "\($0) \($0 == 1 ? "person has" : "people have") been alerted\(raised.lat == nil ? "" : ", with where you are")." } ?? "Your family has been alerted.")
                .font(SR.Text.body())
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                SRHaptic.tap()
                Task { await store.standDown() }
            } label: {
                Text("I'm OK — stand down")
                    .font(SR.Text.title())
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(SR.good)
            .accessibilityIdentifier("family-alarm-stand-down")
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(SR.error.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(SR.error.opacity(0.5), lineWidth: 1.5))
    }
}

/// A big red button that fires after being held for two seconds, filling as
/// it goes. VoiceOver gets a plain double-tap action instead: a long press is
/// not a gesture a screen-reader user can see the progress of.
struct HoldToRaise: View {
    let sending: Bool
    let fire: () -> Void
    static let hold: Double = 2
    @State private var pressing = false
    @State private var progress: Double = 0

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(SR.error.opacity(0.85))
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(hex: 0x8E1B1B))
                    .frame(width: proxy.size.width * progress)
            }
            HStack(spacing: 10) {
                if sending {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "sos").font(.system(size: 22, weight: .heavy))
                }
                Text(sending ? "SENDING…" : pressing ? "KEEP HOLDING" : "HOLD TO RAISE THE ALARM")
                    .font(SR.Text.display(17))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onLongPressGesture(minimumDuration: Self.hold, maximumDistance: 40) {
            SRHaptic.ok()
            progress = 0
            pressing = false
            fire()
        } onPressingChanged: { down in
            pressing = down
            if down {
                SRHaptic.tap()
                withAnimation(.linear(duration: Self.hold)) { progress = 1 }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
            }
        }
        .disabled(sending)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Raise the alarm")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { fire() }
        .accessibilityIdentifier("family-alarm-hold")
    }
}

// MARK: - Receiving it

/// Somebody else's alarm, over everything: who, what they said, where they
/// are, and the two things to do — silence it and go.
struct IncomingAlarmView: View {
    let alarm: FamilyAlarm
    @ObservedObject private var store = FamilyAlarmStore.shared
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flash = false

    var body: some View {
        ZStack {
            (alarm.cancelled ? SR.good : SR.error)
                .opacity(flash && !alarm.cancelled ? 0.8 : 1)
                .ignoresSafeArea()
            VStack(spacing: 22) {
                Spacer()
                Image(systemName: alarm.cancelled ? "checkmark.shield.fill" : "light.beacon.max.fill")
                    .font(.system(size: 76, weight: .bold))
                    .symbolEffect(.pulse, options: .repeating, isActive: !alarm.cancelled && !reduceMotion)
                Text(alarm.cancelled ? "\(alarm.name.uppercased()) IS OK" : "\(alarm.name.uppercased()) RAISED THE ALARM")
                    .font(SR.Text.hero(34))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let message = alarm.message, !message.isEmpty {
                    Text("“\(message)”")
                        .font(SR.Text.bodyMedium(19))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(alarm.cancelled ? "They stood the alarm down." : when)
                    .font(SR.Text.mono(14))
                    .opacity(0.85)
                Spacer()
                if !alarm.cancelled, let lat = alarm.lat, let lon = alarm.lon,
                   let url = URL(string: "https://maps.apple.com/?ll=\(lat),\(lon)&q=\(alarm.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Here")") {
                    Button {
                        store.silence()
                        openURL(url)
                    } label: {
                        Label("Show where they are", systemImage: "map.fill")
                            .font(SR.Text.title(18))
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .foregroundStyle(SR.error)
                            .background(Capsule().fill(.white))
                    }
                    .buttonStyle(.plain)
                }
                if !alarm.cancelled {
                    Button {
                        store.silence()
                    } label: {
                        Label("Silence", systemImage: "speaker.slash.fill")
                            .font(SR.Text.title(18))
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .overlay(Capsule().strokeBorder(.white, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("family-alarm-silence")
                }
                Button {
                    store.dismiss()
                } label: {
                    Text(alarm.cancelled ? "Close" : "I've seen it — close")
                        .font(SR.Text.secondary(16))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("family-alarm-dismiss")
            }
            .foregroundStyle(.white)
            .padding(SR.gutter)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { flash = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("family-alarm-incoming")
    }

    private var when: String {
        guard let date = parseTimestamp(alarm.at) else { return "Just now" }
        return "Raised at \(date.formatted(date: .omitted, time: .shortened))"
    }
}

/// Puts an incoming alarm over every tab, and checks for one whenever the app
/// comes back to the foreground.
struct FamilyAlarmHost: ViewModifier {
    @ObservedObject private var store = FamilyAlarmStore.shared
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $store.incoming) { alarm in
                IncomingAlarmView(alarm: alarm)
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await store.poll() }
            }
            .task { await store.poll() }
    }
}
