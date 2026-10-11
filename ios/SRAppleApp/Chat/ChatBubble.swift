import SwiftUI

/// One turn in the transcript.
///
/// The web chat's register, brought to the phone (2026-10-01): a small mono
/// byline per turn (`YOU · 14:02`, `JKAI · 14:02`), jkai's prose full-width on
/// the page with no bubble round it, your own turns marked by a 2pt accent rule
/// down their leading edge, and everything a turn RAN folded to one line —
/// `● 4 tools · on the desk` — that opens the desk drawer at this answer.
///
/// The earlier smoked-ink bubble for your turns went: the desk reads a thread
/// as a document, and a document marks who is speaking with a rule and a
/// byline, not a balloon.
struct ChatBubble: View {
    let message: ChatMessage
    /// Opens the desk at this turn. Nil where there is no desk.
    var openDesk: (() -> Void)? = nil

    var body: some View {
        if message.isUser { userTurn } else { assistantTurn }
    }

    /// Your turn: the accent rule, then what you said, in ink on the page.
    private var userTurn: some View {
        VStack(alignment: .leading, spacing: 6) {
            byline
            VStack(alignment: .leading, spacing: 8) {
                MarkdownText(raw: message.content)
                attachments(register: .paper)
            }
            .padding(.leading, 14)
            .padding(.vertical, 2)
            .overlay(alignment: .leading) {
                Rectangle().fill(SR.accent).frame(width: 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    /// jkai's turn: prose on the page, the way an answer reads on the desk.
    /// Glass around a long answer would be a box around an essay.
    private var assistantTurn: some View {
        VStack(alignment: .leading, spacing: 8) {
            byline

            if message.content.isEmpty {
                // An assistant bubble with nothing in it yet is a turn that has
                // been accepted and not started. Saying nothing at all looks
                // like a dropped message.
                Text("…")
                    .font(SR.body(16))
                    .foregroundStyle(SR.inkMuted)
            } else {
                MarkdownText(raw: message.content)
            }

            attachments(register: .paper)

            ForEach(Array((message.artifacts ?? []).enumerated()), id: \.offset) { _, artifact in
                ArtifactCard(artifact: artifact)
            }

            // The quiet lines under an answer: what it cited, then what it ran
            // and whether that is on the desk.
            if let sources = message.sources, !sources.isEmpty {
                SourcesLine(sources: sources)
            }
            if !message.toolSteps.isEmpty || onDesk {
                DeskToolLine(steps: message.toolSteps, onDesk: onDesk, openDesk: openDesk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Whether this answer has a desk page to open.
    private var onDesk: Bool {
        openDesk != nil && (message.panel?.hasContent ?? false)
    }

    /// `YOU · 14:02` — who, then when, in the mono label face.
    private var byline: some View {
        HStack(spacing: 8) {
            (Text(message.isUser ? "YOU" : "JKAI")
                .foregroundStyle(message.isUser ? SR.accent : SR.inkSecondary)
             + Text(message.createdAt.map { " · " + Self.clock($0) } ?? "")
                .foregroundStyle(SR.inkMuted))
                .font(SR.Text.label(12))
                .tracking(1.2)
            if message.source == "whatsapp" {
                SRPill(text: "WhatsApp", tone: SR.good)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// `14:02` today, `30 Sep 14:02` before it. A clock, not "2h ago": the
    /// byline is a timestamp on a document, and it should not change while
    /// you read.
    static func clock(_ iso: String, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let date = parseTimestamp(iso) else { return "" }
        let format = DateFormatter()
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        format.locale = Locale(identifier: "en_GB")
        format.dateFormat = calendar.isDate(date, inSameDayAs: now) ? "HH:mm" : "d MMM HH:mm"
        return format.string(from: date)
    }

    @ViewBuilder
    private func attachments(register: SRRegister) -> some View {
        if !message.attachments.isEmpty {
            // A photo is drawn; anything else is named. A paperclip and
            // "Photo 2026-09-23.jpg" tells you nothing about which picture.
            ForEach(message.attachments.filter(\.isImage)) { attachment in
                AttachmentImage(attachment: attachment)
            }
            ForEach(message.attachments.filter(\.isAudio)) { attachment in
                VoiceNoteRow(attachment: attachment, register: register)
            }
            ForEach(message.attachments.filter { !$0.isImage && !$0.isAudio }) { attachment in
                HStack(spacing: 7) {
                    Image(systemName: "paperclip").font(.system(size: 11))
                    Text(attachment.filename ?? attachment.kind ?? "Attachment")
                        .font(SR.mono(12))
                        .lineLimit(1)
                }
                .foregroundStyle(register.muted)
            }
        }
    }
}

struct ToolStepList: View {
    let steps: [ToolStep]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: step.failed ? "xmark" : "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(step.failed ? SR.error : SR.good)
                        .padding(.top, 3)
                    Text(step.summary ?? step.tool ?? "tool")
                        .font(SR.mono(12))
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.top, 2)
    }
}

/// The live panel between the send and the answer.
///
/// One line while it works — what it is doing and how many steps so far — with
/// the steps and the reasoning a tap away. It used to print every step as it
/// ran, which on a phone pushed the answer that was about to arrive off the
/// bottom of the screen.
struct TurnActivityPanel: View {
    let activity: TurnActivity
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { open.toggle() }
            } label: {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.6).tint(SR.accent)
                    Text(headline)
                        .font(SR.monoMedium(12))
                        .tracking(1.1)
                        .foregroundStyle(SR.inkSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if hasDetail {
                        Image(systemName: open ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(SR.inkMuted)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!hasDetail)

            if open {
                if !activity.steps.isEmpty { ToolStepList(steps: activity.steps) }
                if !activity.thinking.isEmpty {
                    Text(activity.thinking)
                        .font(SR.mono(12))
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                        .background(SR.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
    }

    private var hasDetail: Bool { !activity.steps.isEmpty || !activity.thinking.isEmpty }

    private var headline: String {
        let status = (activity.status ?? "Thinking").uppercased()
        switch activity.steps.count {
        case 0: return status
        case 1: return "\(status) · 1 STEP"
        default: return "\(status) · \(activity.steps.count) STEPS"
        }
    }
}

/// A turn that opened a gate the phone cannot answer.
struct BlockedTurnCard: View {
    let blocked: BlockedTurn

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SRLabel(text: "Needs the website")
            Text(blocked.sentence)
                .font(SR.bodyMedium(15))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !blocked.detail.isEmpty {
                Text(blocked.detail)
                    .font(SR.body(14))
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Confirmations and credential prompts are answered at the desk. The turn is waiting there, and a WhatsApp message with the link is on its way.")
                .font(SR.body(14))
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            Link(destination: SiteClient.defaultOrigin.appendingPathComponent("jkai")) {
                SRButtonLabel(title: "Open jkai on the web", icon: "safari")
            }
            .srButton(.prominent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .srGlassCard(.paper)
        .overlay(
            RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                .strokeBorder(SR.accent.opacity(0.55), lineWidth: 1)
        )
    }
}

/// Markdown, rendered the way the system would set it.
///
/// `AttributedString(markdown:)` handles the inline run — bold, italic, code
/// spans, links — but it flattens block structure, so fenced code and list items
/// are split out here first. A code block set in body font is unreadable, and
/// the site inverts contrast for code (`--code-bg` is ink, `--code-text` cream)
/// rather than tinting it.
struct MarkdownText: View {
    let raw: String
    /// Which ground the prose is on. A user turn is smoked ink now, and ink
    /// type on it would be invisible.
    var register: SRRegister = .paper

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .code(let text, let language):
                    CodeBlock(text: text, language: language)
                case .prose(let text):
                    Text(inline(text))
                        .font(SR.body(16))
                        .lineSpacing(5)
                        .foregroundStyle(register.primary)
                        .tint(register.accent)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Internal rather than private so the splitter can be tested directly.
    /// It is the one piece of real logic in this view, and the half-streamed
    /// fence case is not something a screenshot would ever catch.
    enum Block {
        case prose(String)
        case code(String, String?)
    }

    /// The parsed blocks, for tests.
    var testBlocks: [Block] { blocks }

    /// Split on fences. A fence that never closes takes the rest of the message
    /// — which is what a half-streamed code block IS, and rendering it as code
    /// while it arrives is better than rendering it as prose and reflowing.
    private var blocks: [Block] {
        var result: [Block] = []
        var prose: [String] = []
        var code: [String] = []
        var language: String?
        var inFence = false

        for line in raw.components(separatedBy: "\n") {
            if line.hasPrefix("```") {
                if inFence {
                    result.append(.code(code.joined(separator: "\n"), language))
                    code = []
                    language = nil
                    inFence = false
                } else {
                    if !prose.isEmpty {
                        result.append(.prose(prose.joined(separator: "\n")))
                        prose = []
                    }
                    let tag = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                    language = tag.isEmpty ? nil : tag
                    inFence = true
                }
                continue
            }
            if inFence { code.append(line) } else { prose.append(line) }
        }
        if !code.isEmpty { result.append(.code(code.joined(separator: "\n"), language)) }
        if !prose.isEmpty { result.append(.prose(prose.joined(separator: "\n"))) }
        return result
    }

    private func inline(_ text: String) -> AttributedString {
        // Inline-only, WHITESPACE PRESERVED. `.full` was here, under a comment
        // saying it kept the newlines — it does not. It turns them into block
        // structure (`presentationIntent`) that a single `Text` never renders,
        // so a list came out as one run-on line: "off:Mon easy 6 kmWed 5 x 1 km".
        // Found by the demo screenshots. The block syntax a transcript actually
        // uses — bullets, numbered items, headings — is done by hand per line
        // below, and the inline syntax (bold, code, links) by the parser.
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        var result = AttributedString()
        let lines = text.components(separatedBy: "\n")
        for (index, raw) in lines.enumerated() {
            var line = raw
            var heading = false
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let indent = String(line.prefix(while: { $0 == " " }))
                line = indent + "•  " + trimmed.dropFirst(2)
            } else if trimmed.hasPrefix("#") {
                let body = trimmed.drop(while: { $0 == "#" })
                if body.hasPrefix(" ") {
                    line = String(body.dropFirst())
                    heading = true
                }
            }
            var parsed = (try? AttributedString(markdown: line, options: options)) ?? AttributedString(line)
            for run in parsed.runs where run.inlinePresentationIntent == .code {
                parsed[run.range].font = SR.mono(14)
            }
            if heading { parsed.font = SR.bodyBold(17) }
            result += parsed
            if index < lines.count - 1 { result += AttributedString("\n") }
        }
        return result
    }
}

/// A fenced block. Inverted contrast, per `--code-bg` / `--code-text`.
struct CodeBlock: View {
    let text: String
    let language: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language {
                Text(language.uppercased())
                    .font(SR.mono(12))
                    .tracking(1)
                    .foregroundStyle(Color(hex: 0xEDE4D4, alpha: 0.5))
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
            }
            // Code scrolls in its own container rather than wrapping. A wrapped
            // line of code is a different line of code, and `overflow-x: auto`
            // is what the site does with one.
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(SR.mono(13))
                    .foregroundStyle(SR.paper)
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SR.ink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
