import SwiftUI
import PhotosUI
import Vision

/// Point the camera at a menu, a sign, a ticket machine or a label: the words
/// are read off the photo (Vision, on the phone) and each line is translated
/// into English beside the original, top to bottom as printed.
///
/// A photo rather than a live viewfinder: the menu stays put while you read
/// it, the waiter can be shown a line, and it works on an old photo too.
struct TravelSignReaderScreen: View {
    @StateObject private var bridge = TravelTranslationBridge()
    @State private var image: UIImage?
    @State private var lines: [Line] = []
    @State private var reading = false
    @State private var camera = false
    @State private var picked: PhotosPickerItem?
    @State private var problem: String?
    @State private var showing: TravelShowCard?

    struct Line: Identifiable, Hashable {
        let id = UUID()
        let text: String
        var english: String?
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.cardGap) {
                TravelTranslatorNote(bridge: bridge)
                HStack(spacing: 12) {
                    if CameraPicker.isAvailable {
                        SRButton(title: "Take a photo", filled: true) { camera = true }
                            .accessibilityIdentifier("travel-reader-camera")
                    }
                    PhotosPicker(selection: $picked, matching: .images) {
                        SRButtonLabel(title: "From photos", fill: true)
                    }
                    .srButton()
                    .controlSize(.large)
                }
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("The photo being read")
                }
                if reading {
                    HStack { ProgressView(); Text("Reading…").foregroundStyle(SR.inkSecondary) }
                }
                if let problem {
                    Text(problem).font(SR.Text.secondary(14)).foregroundStyle(SR.error)
                }
                if image == nil && !reading { hint }
                if !lines.isEmpty {
                    SRSectionLabel(text: "What it says", trailing: "\(lines.count) lines")
                    ForEach(lines) { line in row(line) }
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(TravelTranslationHost(bridge: bridge))
        .srGround(.warm)
        .navigationTitle("Read a sign")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $camera) {
            CameraPicker { read($0) }.ignoresSafeArea()
        }
        .sheet(item: $showing) { TravelShowSheet(card: $0) }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let photo = UIImage(data: data) {
                    read(photo)
                }
                picked = nil
            }
        }
        .accessibilityIdentifier("travel-reader")
    }

    private var hint: some View {
        SRCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Menus, signs and labels")
                    .font(SR.Text.title(17))
                    .foregroundStyle(SR.ink)
                Text("Take a photo square-on and close enough to fill the frame. Each printed line comes back in English, in the order it is printed. Tap a line to show it big or hear it said.")
                    .font(SR.Text.secondary(14))
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(_ line: Line) -> some View {
        Button {
            showing = TravelShowCard(big: line.text, small: line.english, speech: bridge.language.speech)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(line.english ?? (TravelTranslationBridge.supported ? "…" : line.text))
                    .font(SR.Text.bodyMedium(16))
                    .foregroundStyle(SR.ink)
                Text(line.text)
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(SR.surface))
        }
        .buttonStyle(.plain)
    }

    private func read(_ photo: UIImage) {
        image = photo
        lines = []
        problem = nil
        reading = true
        let languages = [bridge.language.speech, TravelLanguage.english.speech]
        Task {
            let found = await TravelTextReader.lines(in: photo, languages: languages)
            reading = false
            if found.isEmpty {
                problem = "No words found. Try again closer, square-on and with more light."
                return
            }
            lines = found.map { Line(text: $0) }
            // One at a time, in printed order, so the top of the menu is
            // readable first.
            for line in lines {
                let english = await bridge.translate(line.text, .back)
                if let index = lines.firstIndex(where: { $0.id == line.id }) {
                    lines[index].english = english
                }
            }
        }
    }
}

/// Printed text off a photo, as lines, top to bottom.
enum TravelTextReader {
    static func lines(in image: UIImage, languages: [String]) async -> [String] {
        guard let cg = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await withCheckedContinuation { continuation in
            // Vision can both call back with an error and throw from
            // `perform`: the continuation is resumed by whichever is first.
            let once = Once()
            let request = VNRecognizeTextRequest { request, _ in
                let found = (request.results as? [VNRecognizedTextObservation]) ?? []
                // Vision's origin is bottom left: higher `maxY` is nearer the top.
                let ordered = found
                    .sorted { a, b in
                        abs(a.boundingBox.midY - b.boundingBox.midY) < 0.01
                            ? a.boundingBox.minX < b.boundingBox.minX
                            : a.boundingBox.midY > b.boundingBox.midY
                    }
                    .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespaces) }
                    .filter { $0.count > 1 }
                once.run { continuation.resume(returning: ordered) }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = languages
            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cgImage: cg, orientation: orientation)
                do { try handler.perform([request]) } catch { once.run { continuation.resume(returning: []) } }
            }
        }
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false

        func run(_ body: () -> Void) {
            lock.lock()
            defer { lock.unlock() }
            guard !done else { return }
            done = true
            body()
        }
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
