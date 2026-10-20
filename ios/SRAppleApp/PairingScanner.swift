import SwiftUI
import VisionKit
import AVFoundation

/// The one pairing code: `{type: "sr-pair", version: 1, server, code}`, from
/// strangeramblings.com/welcome (SR-Main `$lib/server/pair-payload`). It
/// replaced the two codes a phone used to need — health & location, and chat &
/// news — and it connects only a phone signed in as the person it was made
/// for (`CodePairing`).
///
/// Without a `code` it is the page's OPEN code, shown to a visitor who is not
/// signed in: nobody's, no secret. Scanned, the phone signs in with its own
/// Apple ID, and someone the owner pre-registered in the household is let
/// straight in.
struct PairingPayload: Decodable, Equatable {
    static let type = "sr-pair"

    let type: String
    let version: Int
    let server: String
    let code: String?
    /// An install link's code (`/app/<name>-<tag>`): the same link that put
    /// the app on a phone pairs it, once scanned or opened from here. Never
    /// in the JSON the site's QR carries; set by `parse` from a link.
    var join: String? = nil

    /// `rory-Ab12Cd34Ef` — a first name and a ten-character tag.
    static let joinCodePattern = "^[a-z]{1,20}-[A-Za-z0-9_-]{10}$"

    @MainActor static func parse(_ text: String) throws -> PairingPayload {
        if let link = fromLink(text) { return link }
        guard text.utf8.count <= 2048,
              let data = text.data(using: .utf8),
              let value = try? JSONDecoder().decode(Self.self, from: data) else {
            throw CompanionError.message("That is not a Strange Ramblings pairing code. Make yours at strangeramblings.com/welcome.")
        }
        // The two codes this one replaced. Name the fix, not just the refusal.
        guard value.type != "sr-companion-pair", value.type != "sr-native-pair" else {
            throw CompanionError.message("That is one of the old pair of codes. strangeramblings.com/welcome now shows one code for everything — make a new one there.")
        }
        guard value.type == Self.type else {
            throw CompanionError.message("That is not a Strange Ramblings pairing code. Make yours at strangeramblings.com/welcome.")
        }
        guard value.version == 1 else {
            throw CompanionError.message("That pairing code is from a newer version of the site than this app understands. Update the app.")
        }
        if let code = value.code, code.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) == nil {
            throw CompanionError.message("That pairing code is damaged. Make a new one at strangeramblings.com/welcome.")
        }
        _ = try API.validateURL(value.server)
        return value
    }

    /// An install link as the site's QR or "Open SR" button carries it:
    /// `https://<site>/app/<code>`, or `sr://pair?join=<code>&server=<site>`.
    /// Nil for anything else, so the JSON parse gets its turn.
    @MainActor static func fromLink(_ text: String) -> PairingPayload? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count <= 512, let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return nil }
        var server: String?
        var code: String?
        if scheme == "https", url.pathComponents.count == 3, url.pathComponents[1] == "app" {
            code = url.pathComponents[2]
            server = "https://" + (url.host ?? "") + (url.port.map { ":\($0)" } ?? "")
        } else if scheme == "sr", url.host == "pair" {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            code = items.first { $0.name == "join" }?.value
            server = items.first { $0.name == "server" }?.value
        } else {
            return nil
        }
        guard let code, code.range(of: joinCodePattern, options: .regularExpression) != nil,
              let server, (try? API.validateURL(server)) != nil else { return nil }
        return PairingPayload(type: Self.type, version: 1, server: server, code: nil, join: code)
    }
}

struct PairingScanner: View {
    @Environment(\.dismiss) private var dismiss
    @State private var ready = false
    @State private var message = "Requesting camera access…"
    @State private var cameraDenied = false
    let onScan: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("Scan the pairing QR code at strangeramblings.com/welcome. Open it on your iPad or computer.")
                    .padding(.horizontal)
                if ready {
                    CameraScanner(onScan: { value in onScan(value); dismiss() }, onError: { error in
                        ready = false; message = error
                    })
                } else {
                    ContentUnavailableView("QR scanner", systemImage: "qrcode.viewfinder", description: Text(message))
                    if cameraDenied {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                    Text("You can also type the code instead, on the previous screen.").font(.callout).padding()
                }
            }
            .navigationTitle("Pair with a code").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task {
                guard DataScannerViewController.isSupported else {
                    message = "Camera scanning is unavailable on this device. Type the code instead."; return
                }
                let allowed = await AVCaptureDevice.requestAccess(for: .video)
                guard !Task.isCancelled else { return }
                guard allowed else { cameraDenied = true; message = "Allow camera access in Settings to scan your pairing QR code."; return }
                guard DataScannerViewController.isAvailable else {
                    message = "The camera is currently unavailable. Try again or type the code instead."; return
                }
                ready = true
            }
        }
    }
}

private struct CameraScanner: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onError: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan, onError: onError) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced,
            recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true, isGuidanceEnabled: true, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        // Start after SwiftUI has mounted the scanner view.
        DispatchQueue.main.async { [weak scanner] in
            guard let scanner, !context.coordinator.finished else { return }
            do { try scanner.startScanning() }
            catch { context.coordinator.fail("The camera could not start. Try again or type the code instead.") }
        }
        return scanner
    }
    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}
    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        coordinator.finished = true
        uiViewController.stopScanning()
    }
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var finished = false
        let onScan: (String) -> Void
        let onError: (String) -> Void
        init(onScan: @escaping (String) -> Void, onError: @escaping (String) -> Void) { self.onScan = onScan; self.onError = onError }
        func fail(_ message: String) { guard !finished else { return }; finished = true; onError(message) }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let barcode) = item, let value = barcode.payloadStringValue, !finished {
                    finished = true; dataScanner.stopScanning(); onScan(value); return
                }
            }
        }
        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            fail("The camera became unavailable. Try again or type the code instead.")
        }
    }
}
