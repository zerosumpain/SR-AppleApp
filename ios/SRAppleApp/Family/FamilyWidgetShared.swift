import Foundation
import Security
import UIKit
import SwiftUI

// What the family widgets and the app share, and the widgets' faces.
//
// SHARED with the widget extension (`SRAppleLive`) and the share extension
// (`SRAppleShare`), see watch.yml: nothing
// here may reach for the app's own types.
//
// ## Why the Keychain, and not an App Group
//
// An extension cannot see the app's files. The usual bridge is an App Group,
// and this team has one — but it is attached to the WATCH App IDs only. The
// iPhone app's App Store profile is minted by hand and lives in a GitHub
// secret (docs/TESTFLIGHT.md), and the Live Activity extension's is minted by
// CI through an API that cannot attach a group (scripts/asc-watch-profiles.py).
// Adding `application-groups` to either would fail the TestFlight archive
// until somebody re-minted a profile by hand — the #63/#66/#67 lesson.
//
// A Keychain ACCESS GROUP needs nothing new: every Apple profile already
// carries `keychain-access-groups = <TEAM>.*`, so any `$(AppIdentifierPrefix)…`
// group is allowed without touching the portal. The app writes a small JSON
// snapshot of each board there — and the site credential, so the widget can
// refresh on its own every twenty minutes instead of only when the app opens.

enum FamilyWidgetKind {
    static let steps = "FamilySteps"
    static let tasks = "FamilyTasks"
}

/// The widgets' refresh: iOS budgets roughly this often for a widget that
/// asks, and a step board moves every fifteen minutes on the site.
enum FamilyWidgetTiming {
    static let refresh: TimeInterval = 20 * 60
}

/// The site credential, as the widget needs it to fetch a board itself.
struct FamilyWidgetCredential: Codable, Equatable {
    let origin: String
    let token: String
}

struct FamilyStepsSnapshot: Codable, Equatable {
    let board: FamilyStepsBoard
    let savedAt: Date
}

struct FamilyTasksSnapshot: Codable, Equatable {
    let summary: FamilyTasksSummary
    let savedAt: Date
}

/// The shared Keychain group, holding the snapshots and the credential.
///
/// Every item is `AfterFirstUnlockThisDeviceOnly`: a widget refreshes while
/// the phone is locked, and nothing here should reach a backup or another
/// device.
enum FamilyShelf {
    static let service = "com.strangeramblings.com.appleapp.family-widgets"

    enum Account: String, CaseIterable {
        case credential, steps, tasks
        /// Shares the share extension could not send (FamilyBacklogShared.swift).
        case backlogQueue
        /// The reader's palette, as the widgets and Live Activities paint it
        /// (`SRWidgetPalette`). Not a secret, and not the family's: kept when
        /// everything else is cleared.
        case palette
    }

    /// `<TEAM>.com.strangeramblings.com.appleapp.shared`, from Info.plist
    /// (`SRSharedKeychainGroup`, filled in at build time). Nil in a build
    /// with no team — a simulator build with signing off — where every
    /// read and write here quietly does nothing.
    static var group: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SRSharedKeychainGroup") as? String,
              !value.isEmpty, !value.contains("$("), !value.hasPrefix(".") else { return nil }
        return value
    }

    private static func query(_ account: Account) -> [String: Any]? {
        guard let group else { return nil }
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecAttrAccessGroup as String: group,
        ]
    }

    static func read(_ account: Account) -> Data? {
        guard var query = query(account) else { return nil }
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    /// Replace (or, with nil, remove) one item. False when the Keychain
    /// refused — never thrown: a widget is a convenience.
    @discardableResult
    static func write(_ data: Data?, _ account: Account) -> Bool {
        guard let query = query(account) else { return false }
        let deleted = SecItemDelete(query as CFDictionary)
        guard deleted == errSecSuccess || deleted == errSecItemNotFound else { return false }
        guard let data else { return true }
        var values = query
        values[kSecValueData as String] = data
        values[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(values as CFDictionary, nil) == errSecSuccess
    }

    static func load<T: Decodable>(_ type: T.Type, _ account: Account) -> T? {
        read(account).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    /// Store a value. Returns whether what is stored CHANGED — so the app
    /// reloads a widget only when there is something new to draw.
    @discardableResult
    static func save<T: Encodable & Equatable & Decodable>(_ value: T?, _ account: Account) -> Bool {
        let current = load(T.self, account)
        guard current != value else { return false }
        let data = value.flatMap { try? JSONEncoder().encode($0) }
        return write(data, account)
    }

    static func clearAll() {
        for account in Account.allCases where account != .palette { write(nil, account) }
    }
}

/// A widget fetching its own board with the shared credential. Always as
/// this phone's own person — never "View as", which is the owner's look.
enum FamilyWidgetFetch {
    static func steps() async -> FamilyStepsBoard? {
        await get("api/native/family/steps")
    }

    static func tasks() async -> FamilyTasksBoard? {
        await get("api/native/family/tasks")
    }

    private static func get<T: Decodable>(_ path: String) async -> T? {
        guard let credential = FamilyShelf.load(FamilyWidgetCredential.self, .credential),
              let origin = URL(string: credential.origin), origin.scheme == "https" else { return nil }
        var request = URLRequest(url: origin.appending(path: path))
        request.timeoutInterval = 15
        request.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode == 401 || http.statusCode == 403 {
            FamilyShelf.clearAll()
            return nil
        }
        guard (200..<300).contains(http.statusCode) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

/// Synthetic boards for a widget's placeholder and the gallery. The repo is
/// public: made-up names only.
enum FamilyWidgetSamples {
    static var steps: FamilyStepsBoard {
        FamilyStepsBoard(
            day: FamilySteps.ymd(Date()),
            updatedAt: nil,
            people: [
                FamilyStepsPerson(id: "f_s1", name: "Sam", steps: 11_204, rank: 1),
                FamilyStepsPerson(id: "f_s2", name: "You", steps: 9_120, rank: 2, me: true),
                FamilyStepsPerson(id: "f_s3", name: "Robin", steps: 6_530, rank: 3),
                FamilyStepsPerson(id: "f_s4", name: "Kit", steps: 3_020, rank: 4),
            ],
            yesterday: FamilyStepsYesterday(leaderName: "Robin", steps: 14_210)
        )
    }

    static var tasks: FamilyTasksSummary {
        FamilyTasksSummary(
            toDo: 4, awaiting: 2, parent: true, owedPence: 1_500, owedOther: 1,
            next: [
                .init(id: "t1", title: "Empty the dishwasher", due: "Due today", overdue: false, reward: "£2"),
                .init(id: "t2", title: "Tidy the bedroom", due: "Due tomorrow", overdue: false, reward: "Game time"),
                .init(id: "t3", title: "Walk the dog", due: nil, overdue: false, reward: nil),
            ]
        )
    }
}

// MARK: - The widgets' faces
//
// Drawn here rather than in the extension so the app can show them too — the
// DEBUG gallery is how CI photographs a widget, since a UI test cannot reach
// the Home Screen. The extension wraps each in its container background and
// tap URL.
//
// Prism: each widget is its Home tile, on the Home Screen — the feature's
// hue as the whole ground, its type on top, in the reader's palette
// (`SRWidgetPalette`, left on the shelf by the app).

extension SRWidgetPalette {
    /// The palette the app last left on the shelf; Prism if none.
    static func load() -> SRWidgetPalette {
        FamilyShelf.load(SRWidgetPalette.self, .palette) ?? .prism
    }
}

/// The reader's palette for a screen an extension draws on the page rather
/// than on a hue — the share sheet. Read once per process: an extension lives
/// for one share.
enum FamilyWidgetInk {
    private static let palette = SRWidgetPalette.load()
    static var paper: Color { palette.paper.color() }
    static var ink: Color { palette.ink.color() }
    static var muted: Color { palette.ink.color(alpha: 0.65) }
    static var accent: Color { palette.accent.color() }
}

/// The faces a widget uses: SF Pro Rounded, as the app's, each scaling with
/// the reader's text size.
enum FamilyWidgetFont {
    static func rounded(_ size: CGFloat, _ weight: UIFont.Weight, _ style: UIFont.TextStyle) -> Font {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let face = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
        return Font(UIFontMetrics(forTextStyle: style).scaledFont(for: face) as CTFont)
    }

    static func display(_ size: CGFloat) -> Font { rounded(size, .heavy, .title1) }
    static func name(_ size: CGFloat) -> Font { rounded(size, .semibold, .body) }
    static func label(_ size: CGFloat) -> Font { rounded(size, .bold, .caption1) }
    static func figure(_ size: CGFloat) -> Font { rounded(size, .heavy, .body).monospacedDigit() }
}

/// Which slot a face is drawn for.
enum FamilyWidgetSize {
    case small, medium, rectangular
}

/// The step board: your place, your steps, the race.
struct FamilyStepsWidgetView: View {
    let board: FamilyStepsBoard?
    let size: FamilyWidgetSize
    var now = Date()
    var palette: SRWidgetPalette = .prism

    /// Type on the steps hue.
    private var on: Color { SRRGB.color(palette.steps.onFill) }

    var body: some View {
        if let board, let mine = board.mine {
            switch size {
            case .small: small(board, mine)
            case .medium: medium(board, mine)
            case .rectangular: rectangular(board, mine)
            }
        } else {
            empty
        }
    }

    private func kicker(_ board: FamilyStepsBoard) -> String {
        FamilySteps.isToday(board, now: now) ? "STEPS · TODAY" : "STEPS · YESTERDAY"
    }

    private func place(_ board: FamilyStepsBoard, _ mine: FamilyStepsPerson) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if mine.rank == 1 {
                Image(systemName: "crown.fill")
                    .font(FamilyWidgetFont.label(14))
            }
            Text(FamilySteps.ordinal(mine.rank))
                .font(FamilyWidgetFont.display(32))
            Text("of \(board.people.count)")
                .font(FamilyWidgetFont.label(12))
                .opacity(0.85)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func small(_ board: FamilyStepsBoard, _ mine: FamilyStepsPerson) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(kicker(board))
                .font(FamilyWidgetFont.label(10))
                .tracking(0.8)
                .opacity(0.85)
            place(board, mine)
            Text(FamilySteps.figure(mine.steps))
                .font(FamilyWidgetFont.figure(17))
            Spacer(minLength: 0)
            if let gap = FamilySteps.gap(board) {
                Text(gap)
                    .font(FamilyWidgetFont.name(12))
                    .opacity(0.9)
                    .lineLimit(2)
            }
        }
        .foregroundStyle(on)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func medium(_ board: FamilyStepsBoard, _ mine: FamilyStepsPerson) -> some View {
        let top = FamilySteps.top(board, 4)
        let lead = max(top.map(\.steps).max() ?? 1, 1)
        return HStack(alignment: .top, spacing: 14) {
            small(board, mine)
                .frame(width: 118)
            // The race: a lane per person, as long as their steps.
            VStack(alignment: .leading, spacing: 6) {
                ForEach(top) { person in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(person.me ? "You" : person.name)
                                .font(person.me ? FamilyWidgetFont.label(13) : FamilyWidgetFont.name(13))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(FamilySteps.figure(person.steps))
                                .font(FamilyWidgetFont.figure(12))
                        }
                        Capsule()
                            .fill(on.opacity(0.22))
                            .frame(height: 5)
                            .overlay(alignment: .leading) {
                                GeometryReader { geo in
                                    Capsule()
                                        .fill(on.opacity(person.me ? 1 : 0.7))
                                        .frame(width: max(5, geo.size.width * CGFloat(person.steps) / CGFloat(lead)))
                                }
                            }
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(on)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func rectangular(_ board: FamilyStepsBoard, _ mine: FamilyStepsPerson) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(FamilySteps.ordinal(mine.rank)) of \(board.people.count) · \(FamilySteps.figure(mine.steps))")
                .font(FamilyWidgetFont.label(13))
            if let gap = FamilySteps.gap(board) {
                Text(gap).font(FamilyWidgetFont.name(12)).lineLimit(1)
            }
            Text("Family steps").font(FamilyWidgetFont.label(11)).opacity(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("STEPS")
                .font(FamilyWidgetFont.label(10))
                .tracking(0.8)
                .opacity(0.85)
            Text("Open SR to see today's board.")
                .font(FamilyWidgetFont.name(13))
        }
        .foregroundStyle(size == .rectangular ? Color.primary : on)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The task list: what is left, what is waiting on you, what is owed.
struct FamilyTasksWidgetView: View {
    let summary: FamilyTasksSummary?
    let size: FamilyWidgetSize
    var palette: SRWidgetPalette = .prism

    /// Type on the tasks hue.
    private var on: Color { SRRGB.color(palette.tasks.onFill) }

    var body: some View {
        if let summary {
            switch size {
            case .small: small(summary)
            case .medium: medium(summary)
            case .rectangular: rectangular(summary)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("TASKS")
                    .font(FamilyWidgetFont.label(10))
                    .tracking(0.8)
                    .opacity(0.85)
                Text("Open SR to see the family's tasks.")
                    .font(FamilyWidgetFont.name(13))
            }
            .foregroundStyle(size == .rectangular ? Color.primary : on)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func waitingLine(_ s: FamilyTasksSummary) -> String? {
        guard s.awaiting > 0 else { return nil }
        if s.parent { return s.awaiting == 1 ? "1 to confirm" : "\(s.awaiting) to confirm" }
        return s.awaiting == 1 ? "1 with a parent" : "\(s.awaiting) with a parent"
    }

    private func small(_ s: FamilyTasksSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TASKS")
                .font(FamilyWidgetFont.label(10))
                .tracking(0.8)
                .opacity(0.85)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(s.toDo)")
                    .font(FamilyWidgetFont.display(32))
                Text("to do")
                    .font(FamilyWidgetFont.label(12))
                    .opacity(0.85)
            }
            if let waiting = waitingLine(s) {
                // Waiting on THIS reader: a chip, so it reads as theirs to do.
                Text(waiting)
                    .font(FamilyWidgetFont.label(12))
                    .padding(.horizontal, s.parent ? 7 : 0)
                    .padding(.vertical, s.parent ? 2 : 0)
                    .background(Capsule().fill(on.opacity(s.parent ? 0.16 : 0)))
            }
            Spacer(minLength: 0)
            if let owed = s.owedLine {
                Label(owed, systemImage: "sterlingsign.circle.fill")
                    .font(FamilyWidgetFont.label(11))
                    .lineLimit(2)
            }
        }
        .foregroundStyle(on)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func medium(_ s: FamilyTasksSummary) -> some View {
        HStack(alignment: .top, spacing: 14) {
            small(s).frame(width: 110)
            VStack(alignment: .leading, spacing: 7) {
                if s.next.isEmpty {
                    Label("Nothing left to do.", systemImage: "checkmark.circle.fill")
                        .font(FamilyWidgetFont.name(14))
                }
                ForEach(s.next) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: line.overdue ? "exclamationmark.circle.fill" : "circle")
                            .font(FamilyWidgetFont.label(12))
                            .opacity(line.overdue ? 1 : 0.7)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(line.title)
                                .font(FamilyWidgetFont.name(14))
                                .lineLimit(1)
                            let detail = [line.due, line.reward].compactMap { $0 }.joined(separator: " · ")
                            if !detail.isEmpty {
                                Text(detail)
                                    .font(FamilyWidgetFont.label(10))
                                    .opacity(line.overdue ? 1 : 0.8)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(on)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func rectangular(_ s: FamilyTasksSummary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(s.toDo) to do" + (waitingLine(s).map { " · \($0)" } ?? ""))
                .font(FamilyWidgetFont.label(13))
            if let first = s.next.first {
                Text(first.title).font(FamilyWidgetFont.name(12)).lineLimit(1)
            }
            Text(s.owedLine ?? "Family tasks").font(FamilyWidgetFont.label(11)).opacity(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A widget's ground: its feature's hue, with the same sheen as a Home tile.
struct FamilyWidgetGround: View {
    let hue: SRHueSpec

    var body: some View {
        ZStack {
            hue.gradient
            RadialGradient(colors: [.white.opacity(0.26), .clear], center: .topLeading, startRadius: 0, endRadius: 200)
        }
    }
}
