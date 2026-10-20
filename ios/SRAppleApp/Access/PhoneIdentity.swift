import Foundation
import UIKit

/// What this phone says about itself on every request to either server, in
/// two headers SR-Main (`$lib/server/native-telemetry`) and the companion
/// pilot (`server/telemetry.mjs`) both read:
///
///     X-SR-App:     <version>/<build>/<commit>/<channel>   0.1.136/136/68136470/adhoc
///     X-SR-Device:  <model>/<os>[/<name>]          iPhone15,2/26.0.1/Rory%27s%20iPhone
///
/// Headers, not body fields: the pilot refuses any JSON field it does not
/// expect, and a header a server never reads costs nothing — so an old server
/// and a new app get on, in either order. The owner's device list prints
/// these so he can see which phone is behind, and which of a person's two
/// phones is which.
enum PhoneIdentity {
    static let appHeader = "X-SR-App"
    static let deviceHeader = "X-SR-Device"

    /// The name this phone goes by on the owner's device list. `UIDevice.name`
    /// is personal data on iOS 16+ and reads "iPhone" unless entitled, so the
    /// person types one (Settings → Connections). Empty until they do; the
    /// list then shows the model instead.
    static var phoneName: String {
        get { UserDefaults.standard.string(forKey: nameKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: nameKey) }
    }
    static let nameKey = "phoneIdentity.name"
    static let nameLimit = 60

    /// The headers for THIS phone, now. Read per request rather than once on
    /// a session, so a name typed in Settings reaches the next call.
    static var headers: [String: String] {
        let info = Bundle.main.infoDictionary ?? [:]
        return headers(
            version: info["CFBundleShortVersionString"] as? String ?? "",
            build: info["CFBundleVersion"] as? String ?? "",
            commit: AppUpdate.ownCommit,
            channel: channel,
            model: modelIdentifier,
            os: UIDevice.current.systemVersion,
            name: phoneName
        )
    }

    static func apply(to request: inout URLRequest) {
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
    }

    /// Pure, for the tests: the exact header values for these facts. The name
    /// is percent-encoded so a slash in it cannot read as a field break, and
    /// so the header stays ASCII whatever the person typed.
    static func headers(version: String, build: String, commit: String, channel: String, model: String, os: String, name: String) -> [String: String] {
        var out = [appHeader: "\(version)/\(build)/\(commit)/\(channel)", deviceHeader: "\(model)/\(os)"]
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(nameLimit))
        if !trimmed.isEmpty, let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: unreserved) {
            out[deviceHeader] = "\(model)/\(os)/\(encoded)"
        }
        return out
    }

    /// How this copy got here: a copy built for this phone's UDID carries an
    /// embedded profile and a CI commit; a TestFlight copy has the commit but
    /// no embedded profile; an Xcode run has neither.
    static var channel: String {
        if AppUpdate.isAdHoc { return "adhoc" }
        return AppUpdate.ownCommit.isEmpty ? "xcode" : "testflight"
    }

    /// `iPhone15,2` — the hardware identifier, which `UIDevice.model` ("iPhone")
    /// is not. On the simulator it is the architecture; that is fine, nothing
    /// paired from a simulator reaches a real device list.
    static var modelIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafeBytes(of: &systemInfo.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    /// RFC 3986 unreserved characters, as ASCII — `CharacterSet.alphanumerics`
    /// would pass "é" through and put a non-ASCII byte in a header.
    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}
