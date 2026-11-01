import QuickLook
import SwiftUI

/// One file's Info: what it is, where it came from, and — for the owner in
/// his own files — what jkai made of it.
///
/// Built from `GET api/native/drive/files/<id>/meta`, so a tapped push about
/// an attachment saved from mail opens straight here with nothing but the
/// id. A member sees the file's facts; the site sends them no jkai fields.
struct DriveFileScreen: View {
    let ref: DriveFileRef
    @StateObject private var model: DriveFileModel
    @ObservedObject private var access = AccessStore.shared
    @EnvironmentObject private var router: Router
    @State private var preview: URL?
    @State private var sharing: DriveLocalFile?
    @State private var ranAction = false

    init(ref: DriveFileRef) {
        self.ref = ref
        _model = StateObject(wrappedValue: DriveFileModel(ref: ref))
    }

    /// jkai on files: the owner, as himself, in his own files.
    private var jkai: Bool { access.current.owner && access.viewingAs == nil && ref.space == .mine }

    var body: some View {
        List {
            if let file = model.file {
                header(file)
                about(file)
                if let mail = model.meta?.mail { mailSection(mail) }
                if jkai {
                    analysisSection
                    intelSection(file)
                }
            } else if model.loaded {
                Section {
                    SREmpty(title: "This file didn't open", icon: "doc.questionmark",
                            message: model.message ?? "It may have been moved or deleted. Pull down to try again.")
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ProgressView().tint(SR.accent).frame(maxWidth: .infinity).padding(.vertical, 40)
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .srPaper()
        .accessibilityIdentifier("drive-file-screen")
        .navigationTitle(model.file?.name ?? "File")
        .navigationBarTitleDisplayMode(.inline)
        .srRefreshable { await model.load() }
        .task {
            await model.load()
            guard !ranAction, jkai, let action = ref.action, model.file != nil else { return }
            ranAction = true
            switch action {
            case .analyse: await model.analyse(refresh: model.analysis != nil)
            case .extract: await model.extract()
            }
        }
        .quickLookPreview($preview)
        .sheet(item: $sharing) { DriveActivitySheet(url: $0.url) }
        .overlay(alignment: .bottom) {
            if let message = model.message, model.file != nil {
                SRBanner(text: message, tone: SR.error).onTapGesture { model.message = nil }
            }
        }
    }

    // MARK: - Sections

    private func header(_ file: DriveFile) -> some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: DriveLogic.icon(mime: file.mimeType, name: file.name))
                    .foregroundStyle(SR.accentInk)
                    .frame(width: 44, height: 44)
                    .background(SR.accentInk.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(place)
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.inkMuted)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 2)
            HStack(spacing: 10) {
                Button {
                    SRHaptic.tap()
                    Task { if let url = await model.localCopy() { preview = url } }
                } label: {
                    SRButtonLabel(title: "Open", icon: "eye", fill: true)
                }
                .srButton(.prominent)
                Button {
                    Task { if let url = await model.localCopy() { sharing = DriveLocalFile(url: url) } }
                } label: {
                    SRButtonLabel(title: "Share", icon: "square.and.arrow.up", fill: true)
                }
                .srButton()
            }
            .buttonStyle(.borderless)
            .disabled(model.fetching)
        }
    }

    private var place: String {
        let folder = model.meta?.folder ?? ""
        return folder.isEmpty ? ref.space.title : "\(ref.space.title) · \(folder)"
    }

    private func about(_ file: DriveFile) -> some View {
        Section {
            row("Size", DriveLogic.size(file.sizeBytes))
            row("Kind", file.mimeType)
            if let added = DriveLogic.day(file.createdAt) { row("Added", added) }
            if file.updatedAt != file.createdAt, let changed = DriveLogic.day(file.updatedAt) { row("Changed", changed) }
            if let by = file.addedBy { row("Added by", by) }
            if let description = model.meta?.description, !description.isEmpty {
                Text(description)
                    .font(SR.Text.body(15))
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SRSectionLabel(text: "About")
        }
    }

    private func mailSection(_ mail: DriveFileMeta.Mail) -> some View {
        Section {
            row("From", mail.from)
            if let subject = mail.subject, !subject.isEmpty { row("Subject", subject) }
            if let day = DriveLogic.day(mail.receivedAt) { row("Received", day) }
        } header: {
            SRSectionLabel(text: "Saved from email")
        }
    }

    @ViewBuilder
    private var analysisSection: some View {
        Section {
            if let analysis = model.analysis {
                VStack(alignment: .leading, spacing: 6) {
                    Text(analysis.docTypeTitle.uppercased())
                        .font(SR.Text.label())
                        .tracking(1.3)
                        .foregroundStyle(SR.accentInk)
                    Text(analysis.summary)
                        .font(SR.Text.body(15))
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 2)
                if let action = analysis.actionNeeded {
                    Label(action, systemImage: "exclamationmark.circle.fill")
                        .font(SR.Text.bodyMedium(15))
                        .foregroundStyle(SR.error)
                }
                ForEach(analysis.keyFacts, id: \.self) { fact in row(fact.label, fact.value) }
                ForEach(analysis.dates, id: \.self) { fact in
                    row(fact.label, DriveLogic.day(fact.date + "T12:00:00Z") ?? fact.date)
                }
                ForEach(analysis.amounts, id: \.self) { amount in row(amount.label, FileAnalysis.money(amount)) }
            } else if !model.analysing {
                Text("jkai hasn't read this one yet.")
                    .font(SR.Text.secondary(14))
                    .foregroundStyle(SR.inkMuted)
            }
            Button {
                Task { await model.analyse(refresh: model.analysis != nil) }
            } label: {
                if model.analysing {
                    HStack(spacing: 8) {
                        ProgressView().tint(SR.accent)
                        Text("Reading…")
                    }
                } else {
                    Label(model.analysis == nil ? "Analyse" : "Analyse again", systemImage: "sparkles")
                }
            }
            .disabled(model.analysing)
            .accessibilityIdentifier("drive-file-analyse")
        } header: {
            SRSectionLabel(text: "jkai's summary")
        } footer: {
            if let analysis = model.analysis {
                Text(analysis.source == "mail-rule" ? "Read when it was saved from email." : "Read on request.")
            }
        }
    }

    private func intelSection(_ file: DriveFile) -> some View {
        Section {
            Text(model.intelSentence)
                .font(SR.Text.secondary(14))
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await model.extract() }
            } label: {
                if model.extracting {
                    HStack(spacing: 8) {
                        ProgressView().tint(SR.accent)
                        Text("Extracting…")
                    }
                } else {
                    Label("Extract entities", systemImage: "point.3.connected.trianglepath.dotted")
                }
            }
            .disabled(model.extracting)
            .accessibilityIdentifier("drive-file-extract")
            Button {
                router.ask(DriveLogic.askPrompt(for: file))
            } label: {
                Label("Ask jkai about it", systemImage: "bubble.left.and.text.bubble.right")
            }
        } header: {
            SRSectionLabel(text: "Knowledge graph")
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        LabeledContent {
            Text(value)
                .font(SR.Text.body(15))
                .foregroundStyle(SR.ink)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        } label: {
            Text(label)
                .font(SR.Text.secondary(14))
                .foregroundStyle(SR.inkMuted)
        }
    }
}

/// The file behind one Info screen, and jkai's two actions on it.
@MainActor
final class DriveFileModel: ObservableObject {
    let ref: DriveFileRef
    @Published private(set) var meta: DriveFileMeta?
    @Published private(set) var analysis: FileAnalysis?
    @Published private(set) var intel: DriveIntelState?
    @Published private(set) var loaded = false
    @Published private(set) var analysing = false
    @Published private(set) var extracting = false
    @Published private(set) var fetching = false
    @Published var message: String?

    init(ref: DriveFileRef) {
        self.ref = ref
    }

    /// The meta's file, or the row it was opened from while that loads.
    var file: DriveFile? { meta?.file ?? ref.known }

    func load() async {
        defer { loaded = true }
        do {
            let answer = try await DriveAPI.meta(ref)
            meta = answer
            if let found = answer.analysis { analysis = found }
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    var intelSentence: String {
        if let intel {
            return DriveLogic.intelSentence(status: intel.status, outcome: intel.outcome, entityCount: intel.entityCount)
        }
        guard let known = meta?.intel else { return DriveLogic.intelSentence(status: "unknown", outcome: nil, entityCount: nil) }
        return DriveLogic.intelSentence(status: known.status, outcome: known.outcome, entityCount: known.entityCount)
    }

    func analyse(refresh: Bool) async {
        guard !analysing else { return }
        analysing = true
        defer { analysing = false }
        do {
            analysis = try await DriveAPI.analyse(ref.id, refresh: refresh)
            SRHaptic.ok()
        } catch {
            message = Self.words(error)
        }
    }

    func extract() async {
        guard !extracting else { return }
        extracting = true
        defer { extracting = false }
        do {
            let final = try await DriveAPI.extractAndWait(ref.id) { [weak self] state in self?.intel = state }
            intel = final
            if final.status == "done" { SRHaptic.ok() }
        } catch {
            message = Self.words(error)
        }
    }

    /// The file on this phone, fetched once per version.
    func localCopy() async -> URL? {
        guard let file else { return nil }
        if let hit = DriveCache.url(for: file) { return hit }
        fetching = true
        defer { fetching = false }
        do {
            let data = try await SiteClient.shared.bytes(DriveLogic.filePath(file.id))
            return try DriveCache.store(data, for: file)
        } catch {
            message = error.localizedDescription
            return nil
        }
    }

    /// The site's 409/422 refusals in plain words.
    private static func words(_ error: Error) -> String {
        if case .status(let code, let text)? = error as? SiteError {
            if code == 422 || (code == 409 && text.lowercased().contains("text")) {
                return "There's no readable text in this file yet. Try again in a minute."
            }
            return text
        }
        return error.localizedDescription
    }
}
