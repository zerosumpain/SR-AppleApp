import Foundation
import Security
import SwiftUI

// What the family widgets and the app share, and the widgets' faces.
//
// SHARED with the widget extension (`SRAppleLive`, see watch.yml): nothing
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
        for account in Account.allCases { write(nil, account) }
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

/// The site palette's day values, from the shared tokens: the extension cannot
/// see `SR`.
enum FamilyWidgetInk {
    private typealias T = SRTokens.Colour
    static let paper = Color(token: T.bg.light)
    static let ink = Color(token: T.textPrimary.light)
    static let muted = Color(token: T.textMuted.light)
    static let ghost = Color(token: T.textGhost.light)
    static let accent = Color(token: T.accent.light)
    static let accentInk = Color(token: T.accentInk.light)
    static let good = Color(token: T.good.light)
    static let error = Color(token: T.error.light)
    static let line = Color(token: T.line.light)
}

/// The three faces a widget uses, each scaling with the reader's text size.
enum FamilyWidgetFont {
    static func display(_ size: CGFloat) -> Font { .custom("InterDisplay-ExtraBold", size: size, relativeTo: .title) }
    static func name(_ size: CGFloat) -> Font { .custom("DMSans-Medium", size: size, relativeTo: .body) }
    static func label(_ size: CGFloat) -> Font { .custom("JetBrainsMono-Medium", size: size, relativeTo: .caption) }
    static func figure(_ size: CGFloat) -> Font { .custom("JetBrainsMono-Medium", size: size, relativeTo: .body) }
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
            Text(FamilySteps.ordinal(mine.rank))
                .font(FamilyWidgetFont.display(30))
                .foregroundStyle(mine.rank == 1 ? FamilyWidgetInk.accent : FamilyWidgetInk.ink)
            Text("of \(board.people.count)")
                .font(FamilyWidgetFont.label(12))
                .foregroundStyle(FamilyWidgetInk.muted)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func small(_ board: FamilyStepsBoard, _ mine: FamilyStepsPerson) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(kicker(board))
                .font(FamilyWidgetFont.label(10))
                .tracking(1)
                .foregroundStyle(FamilyWidgetInk.muted)
            place(board, mine)
            Text(FamilySteps.figure(mine.steps))
                .font(FamilyWidgetFont.figure(17))
                .foregroundStyle(FamilyWidgetInk.ink)
            Spacer(minLength: 0)
            if let gap = FamilySteps.gap(board) {
                Text(gap)
                    .font(FamilyWidgetFont.name(12))
                    .foregroundStyle(FamilyWidgetInk.muted)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func medium(_ board: FamilyStepsBoard, _ mine: FamilyStepsPerson) -> some View {
        HStack(alignment: .top, spacing: 14) {
            small(board, mine)
                .frame(width: 124)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(FamilySteps.top(board, 4)) { person in
                    HStack(spacing: 6) {
                        Text("\(person.rank)")
                            .font(FamilyWidgetFont.label(11))
                            .foregroundStyle(FamilyWidgetInk.ghost)
                            .frame(width: 14, alignment: .leading)
                        Text(person.me ? "You" : person.name)
                            .font(FamilyWidgetFont.name(14))
                            .foregroundStyle(person.me ? FamilyWidgetInk.accent : FamilyWidgetInk.ink)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(FamilySteps.figure(person.steps))
                            .font(FamilyWidgetFont.figure(13))
                            .foregroundStyle(FamilyWidgetInk.ink)
                    }
                }
                Spacer(minLength: 0)
            }
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
                .tracking(1)
                .foregroundStyle(FamilyWidgetInk.muted)
            Text("Open SR to see today's board.")
                .font(FamilyWidgetFont.name(13))
                .foregroundStyle(size == .rectangular ? Color.primary : FamilyWidgetInk.ink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The task list: what is left, what is waiting on you, what is owed.
struct FamilyTasksWidgetView: View {
    let summary: FamilyTasksSummary?
    let size: FamilyWidgetSize

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
                    .tracking(1)
                    .foregroundStyle(FamilyWidgetInk.muted)
                Text("Open SR to see the family's tasks.")
                    .font(FamilyWidgetFont.name(13))
                    .foregroundStyle(size == .rectangular ? Color.primary : FamilyWidgetInk.ink)
            }
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
                .tracking(1)
                .foregroundStyle(FamilyWidgetInk.muted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(s.toDo)")
                    .font(FamilyWidgetFont.display(30))
                    .foregroundStyle(FamilyWidgetInk.ink)
                Text("to do")
                    .font(FamilyWidgetFont.label(12))
                    .foregroundStyle(FamilyWidgetInk.muted)
            }
            if let waiting = waitingLine(s) {
                Text(waiting)
                    .font(FamilyWidgetFont.name(13))
                    .foregroundStyle(s.parent ? FamilyWidgetInk.accent : FamilyWidgetInk.ink)
            }
            Spacer(minLength: 0)
            if let owed = s.owedLine {
                Text(owed)
                    .font(FamilyWidgetFont.label(11))
                    .foregroundStyle(FamilyWidgetInk.good)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func medium(_ s: FamilyTasksSummary) -> some View {
        HStack(alignment: .top, spacing: 14) {
            small(s).frame(width: 110)
            VStack(alignment: .leading, spacing: 7) {
                if s.next.isEmpty {
                    Text("Nothing left to do.")
                        .font(FamilyWidgetFont.name(14))
                        .foregroundStyle(FamilyWidgetInk.muted)
                }
                ForEach(s.next) { line in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(line.title)
                            .font(FamilyWidgetFont.name(14))
                            .foregroundStyle(FamilyWidgetInk.ink)
                            .lineLimit(1)
                        let detail = [line.due, line.reward].compactMap { $0 }.joined(separator: " · ")
                        if !detail.isEmpty {
                            Text(detail)
                                .font(FamilyWidgetFont.label(10))
                                .foregroundStyle(line.overdue ? FamilyWidgetInk.error : FamilyWidgetInk.muted)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
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
