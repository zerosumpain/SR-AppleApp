import SwiftUI
import VisionKit
import AVFoundation

struct PairingPayload: Decodable, Equatable {
    let type: String
    let version: Int
    let server: String
    let code: String

    @MainActor static func parse(_ text: String) throws -> PairingPayload {
        guard text.utf8.count <= 2048,
              let data = text.data(using: .utf8),
              let value = try? JSONDecoder().decode(Self.self, from: data),
              value.type == "sr-companion-pair", value.version == 1,
              value.code.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else {
            throw CompanionError.message("This is not the health & location code. If you scanned the Chat & news code, that one goes under Settings → Connections → Chat & news. Create the right one at strangeramblings.com/welcome.")
        }
        _ = try API.validateURL(value.server)
        return value
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
                    Text("You can also paste a pairing code on the previous screen.").font(.callout).padding()
                }
            }
            .navigationTitle("Pair by QR code").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task {
                guard DataScannerViewController.isSupported else {
                    message = "Camera scanning is unavailable on this device. Use manual pairing instead."; return
                }
                let allowed = await AVCaptureDevice.requestAccess(for: .video)
                guard !Task.isCancelled else { return }
                guard allowed else { cameraDenied = true; message = "Allow camera access in Settings to scan your pairing QR code."; return }
                guard DataScannerViewController.isAvailable else {
                    message = "The camera is currently unavailable. Try again or use manual pairing."; return
                }
                ready = true
            }
        }.preferredColorScheme(.light)
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
            catch { context.coordinator.fail("The camera could not start. Try again or use manual pairing.") }
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
            fail("The camera became unavailable. Try again or use manual pairing.")
        }
    }
}
