import AVFoundation
import AudioToolbox
import CoreLocation
import MediaPlayer
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
///   The phone's volume is driven to 100% and held there while it rings
///   (`FullVolume`), then put back where it was.
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
    /// `siren`, `morse`, or `quiet` — the bat phone.
    let kind: String
    let message: String?
    let lat: Double?
    let lon: Double?
    let at: String
    let cancelledAt: String?
    /// The bat phone's: the sender's battery (0…1) and the place their phone
    /// named, when it could. Nil from a site before them.
    var battery: Double? = nil
    var place: String? = nil

    var id: String { alarmId }
    var cancelled: Bool { cancelledAt != nil }
    var quiet: Bool { kind == FamilyAlarmKind.quiet.rawValue }

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
        battery = (userInfo["battery"] as? NSNumber)?.doubleValue
        place = userInfo["place"] as? String
    }

    init(alarmId: String, from: String, name: String, kind: String, message: String?,
         lat: Double?, lon: Double?, at: String, cancelledAt: String?, battery: Double? = nil, place: String? = nil) {
        self.alarmId = alarmId
        self.from = from
        self.name = name
        self.kind = kind
        self.message = message
        self.lat = lat
        self.lon = lon
        self.at = at
        self.cancelledAt = cancelledAt
        self.battery = battery
        self.place = place
    }
}

enum FamilyAlarmKind: String, CaseIterable, Identifiable {
    case siren
    case morse
    /// The bat phone (`BatPhoneButton`): nothing sounds or shows on the
    /// sender's phone; everyone else is told urgently who, where, their
    /// battery and how far a drive it is.
    case quiet

    var id: String { rawValue }
    /// The two the alarm sheet offers; the bat phone has its own button.
    static let sounding: [FamilyAlarmKind] = [.siren, .morse]

    var title: String {
        switch self {
        case .siren: return "Siren"
        case .morse: return "Morse SOS"
        case .quiet: return "Bat phone"
        }
    }

    var detail: String {
        switch self {
        case .siren: return "A rising and falling wail"
        case .morse: return "··· ––– ··· beeping, over and over"
        case .quiet: return "Nothing sounds on your phone"
        }
    }

    var symbol: String {
        switch self {
        case .siren: return "light.beacon.max.fill"
        case .morse: return "dot.radiowaves.left.and.right"
        case .quiet: return "phone.connection.fill"
        }
    }

    /// The bundled file, and the push's `sound` — the names must match the
    /// site's (`sr-siren.caf`, `sr-morse.caf`). A bat phone's push makes the
    /// default sound; open, the app rings it as morse.
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

    /// The ringing alarm Silence was pressed on. A poll that then learns its
    /// kind must not start it ringing again under the thumb that silenced it.
    private var silenced: String?

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

    /// The bat phone: no sound, no screen, no success buzz — a phone held
    /// by someone in trouble must not give them away. Where they are, their
    /// battery and the place's name go with it, each only if it comes fast.
    /// True when it went.
    @discardableResult
    func raiseQuietly() async -> Bool {
        guard !sending else { return false }
        sending = true
        failure = nil
        defer { sending = false }
        struct Reply: Decodable { let alarmId: String; let pushed: Int; let recipients: Int }
        var body: [String: Any] = ["kind": FamilyAlarmKind.quiet.rawValue]
        let battery = Self.batteryLevel()
        if let battery { body["battery"] = battery }
        let here = await OneFix.current(timeout: .seconds(4))
        var place: String?
        if let here {
            body["position"] = ["lat": here.latitude, "lon": here.longitude]
            place = await Self.placeName(here)
            if let place { body["place"] = place }
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: body)
            let reply: Reply = try await SiteClient.shared.send("api/native/family/alarm", method: "POST", body: data, asSelf: true)
            raised = FamilyAlarm(alarmId: reply.alarmId, from: "", name: "You", kind: FamilyAlarmKind.quiet.rawValue,
                                 message: nil, lat: here?.latitude, lon: here?.longitude,
                                 at: timestamp(Date()), cancelledAt: nil, battery: battery, place: place)
            raisedTo = reply.recipients
            return true
        } catch {
            failure = "Not sent: \(error.localizedDescription)"
            return false
        }
    }

    /// 0…1, or nil where iOS will not say (a simulator).
    static func batteryLevel() -> Double? {
        let device = UIDevice.current
        let was = device.isBatteryMonitoringEnabled
        device.isBatteryMonitoringEnabled = true
        let level = device.batteryLevel
        if !was { device.isBatteryMonitoringEnabled = false }
        return level >= 0 ? Double(level) : nil
    }

    /// "Elton Parade, Darlington", if the geocoder answers in two seconds.
    static func placeName(_ at: CLLocationCoordinate2D) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask {
                let marks = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: at.latitude, longitude: at.longitude))
                guard let mark = marks?.first else { return nil }
                let first = mark.areasOfInterest?.first ?? mark.thoroughfare ?? mark.name
                let parts = [first, mark.locality].compactMap { $0 }.reduce(into: [String]()) { out, part in
                    if !out.contains(part) { out.append(part) }
                }
                return parts.isEmpty ? nil : String(parts.joined(separator: ", ").prefix(80))
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(2))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
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
            // A kind the push did not carry: ring the right sound from now on.
            if let current = incoming, current.kind != alarm.kind, !current.cancelled, silenced != alarm.alarmId {
                AlarmPlayer.shared.start(FamilyAlarmKind(rawValue: alarm.kind) ?? .siren)
            }
            if alarm.lat != nil || alarm.message != nil || alarm.place != nil || incoming?.kind != alarm.kind, incoming != alarm {
                incoming = alarm
            }
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
                                   cancelledAt: timestamp(Date()), battery: alarm.battery, place: alarm.place)
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

    func silence() {
        silenced = incoming?.alarmId
        AlarmPlayer.shared.stop()
    }

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
        FullVolume.shared.hold()
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
        FullVolume.shared.release()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// The phone's volume at 100% while the alarm rings, whatever it was set to.
///
/// iOS has no API for an app to set the system volume. The only way is the
/// slider inside an `MPVolumeView`, kept in the window but invisible (which
/// also keeps the system volume HUD from popping up). Apple does not support
/// this, and it only works while the app is in the foreground: a locked phone
/// needs a critical alert, which carries its own volume.
///
/// Pressing volume down while it rings is pushed straight back up — Silence is
/// the way to quiet it. On release the volume goes back to what it was.
@MainActor
final class FullVolume {
    static let shared = FullVolume()
    private var view: MPVolumeView?
    private var watch: NSKeyValueObservation?
    private var before: Float?

    func hold() {
        guard watch == nil else { return }
        let session = AVAudioSession.sharedInstance()
        before = session.outputVolume
        let view = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 1, height: 1))
        view.alpha = 0.01
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        keyWindow?.addSubview(view)
        self.view = view
        watch = session.observe(\.outputVolume) { [weak self] _, _ in
            Task { @MainActor in
                guard let self, self.watch != nil else { return }
                if AVAudioSession.sharedInstance().outputVolume < 0.99 { self.set(1) }
            }
        }
        // The slider is not wired up until the view has been laid out once.
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            guard watch != nil else { return }
            set(1)
        }
    }

    func release() {
        guard watch != nil else { return }
        watch?.invalidate()
        watch = nil
        if let before { set(before) }
        before = nil
        // Leave the view a moment so the restore lands before it goes.
        let view = self.view
        self.view = nil
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            view?.removeFromSuperview()
        }
    }

    private func set(_ level: Float) {
        guard let slider = view?.subviews.compactMap({ $0 as? UISlider }).first else { return }
        slider.setValue(level, animated: false)
        slider.sendActions(for: .valueChanged)
    }

    private var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }
}

// MARK: - Raising it

/// The red button on the Family tab's bar.
struct FamilyAlarmButton: View {
    @ObservedObject private var store = FamilyAlarmStore.shared
    @State private var open = false

    /// A bat phone is not shown here: it must not light anything up on the
    /// sender's screen.
    private var sounding: Bool { store.raised.map { !$0.quiet } ?? false }

    var body: some View {
        Button {
            SRHaptic.tap()
            open = true
        } label: {
            Image(systemName: sounding ? "light.beacon.max.fill" : "sos.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, SR.error)
                .font(.system(size: 20, weight: .bold))
                .symbolEffect(.pulse, options: .repeating, isActive: sounding)
        }
        .accessibilityLabel(sounding ? "Alarm raised" : "Raise the alarm")
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
    /// The sound playing here as a test, for what remains of its ten seconds.
    @State private var testing: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let raised = store.raised, !raised.quiet {
                        raisedCard(raised)
                    } else {
                        Text("Every other phone in the family rings loudly, with where you are. Use it when you need help now.")
                            .font(SR.Text.body())
                            .foregroundStyle(SR.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        VStack(spacing: 10) {
                            ForEach(FamilyAlarmKind.sounding) { option in
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
                            stopTest()
                            Task { await store.raise(kind, message: message) }
                        }
                        testButton
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
        .onDisappear { stopTest() }
    }

    /// Play the chosen sound on THIS phone for ten seconds — exactly as a
    /// family member's phone plays it with the app open, through the silent
    /// switch — without telling anyone. Raising an alarm never rings the
    /// sender's own phone, so this is the only way to hear it.
    private var testButton: some View {
        Button {
            SRHaptic.tap()
            if testing != nil {
                stopTest()
            } else {
                AlarmPlayer.shared.start(kind)
                testing = Task {
                    try? await Task.sleep(for: .seconds(10))
                    guard !Task.isCancelled else { return }
                    AlarmPlayer.shared.stop()
                    testing = nil
                }
            }
        } label: {
            Label(testing == nil ? "Test the \(kind.title.lowercased()) on this phone" : "Stop the test",
                  systemImage: testing == nil ? "speaker.wave.3.fill" : "stop.fill")
                .font(SR.Text.title(15))
                .foregroundStyle(SR.error)
                .frame(maxWidth: .infinity, minHeight: SR.tapTarget)
                .overlay(Capsule().strokeBorder(SR.error.opacity(0.5), lineWidth: 1.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Plays for ten seconds here only. Nobody else is told.")
        .accessibilityIdentifier("family-alarm-test")
    }

    private func stopTest() {
        guard let task = testing else { return }
        task.cancel()
        testing = nil
        AlarmPlayer.shared.stop()
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
    /// A bat phone's drive from here, from Apple Maps; nil until it answers.
    @State private var drive: String?

    var body: some View {
        ZStack {
            (alarm.cancelled ? SR.good : SR.error)
                .opacity(flash && !alarm.cancelled ? 0.8 : 1)
                .ignoresSafeArea()
            VStack(spacing: 22) {
                Spacer()
                Image(systemName: alarm.cancelled ? "checkmark.shield.fill" : alarm.quiet ? FamilyAlarmKind.quiet.symbol : "light.beacon.max.fill")
                    .font(.system(size: 76, weight: .bold))
                    .symbolEffect(.pulse, options: .repeating, isActive: !alarm.cancelled && !reduceMotion)
                Text(headline)
                    .font(SR.Text.hero(34))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if alarm.quiet && !alarm.cancelled {
                    VStack(spacing: 6) {
                        ForEach(BatPhoneWords.facts(place: alarm.place, battery: alarm.battery, drive: drive), id: \.self) { line in
                            Text(line)
                        }
                    }
                    .font(SR.Text.bodyMedium(19))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("family-alarm-facts")
                }
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
                if alarm.quiet, !alarm.cancelled, let lat = alarm.lat, let lon = alarm.lon,
                   let url = URL(string: "https://maps.apple.com/?daddr=\(lat),\(lon)&dirflg=d") {
                    Button {
                        store.silence()
                        openURL(url)
                    } label: {
                        Label("Drive there", systemImage: "car.fill")
                            .font(SR.Text.title(18))
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .foregroundStyle(SR.error)
                            .background(Capsule().fill(.white))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("family-alarm-drive")
                }
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
        .task(id: alarm.lat) {
            guard alarm.quiet, let lat = alarm.lat, let lon = alarm.lon else { return }
            drive = await BatPhoneDrive.from(here: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("family-alarm-incoming")
    }

    private var headline: String {
        let name = alarm.name.uppercased()
        if alarm.cancelled { return "\(name) IS OK" }
        return alarm.quiet ? "BAT PHONE — \(name) NEEDS YOU" : "\(name) RAISED THE ALARM"
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
