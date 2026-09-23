import SwiftUI

/// One turn in the transcript.
///
/// Not a chat bubble in the iMessage sense. The system has no shadows and only
/// three radii, so a turn is distinguished by a mono role label and a rule down
/// its left edge — a user turn takes the accent, an assistant turn the hairline.
/// That reads as the site rather than as every other chat app.
struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        if message.isUser { userTurn } else { assistantTurn }
    }

    /// Your turn: smoked ink, trailing, the one dark shape in the transcript.
    ///
    /// Not an accent bubble. Cream on burnt orange measures under 4:1 at body
    /// size, and a whole paragraph in the accent would spend the colour that is
    /// supposed to mean "this matters" on "you said this".
    private var userTurn: some View {
        VStack(alignment: .trailing, spacing: 6) {
            VStack(alignment: .leading, spacing: 8) {
                MarkdownText(raw: message.content, register: .ink)
                attachments(register: .ink)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .srGlass(.ink, in: UnevenRoundedRectangle(
                topLeadingRadius: 22, bottomLeadingRadius: 22,
                bottomTrailingRadius: 8, topTrailingRadius: 22,
                style: .continuous
            ))
            .environment(\.colorScheme, .dark)
            meta
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 44)
    }

    /// jkai's turn: prose on the page, the way an answer reads on the desk.
    /// Glass around a long answer would be a box around an essay.
    private var assistantTurn: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // The monogram as jkai's avatar — the one place the brand mark
                // speaks.
                (Text("sr").foregroundStyle(SR.paper) + Text(".").foregroundStyle(SR.accentOnDark))
                    .font(SR.Text.brand(13))
                    .frame(width: 26, height: 26)
                    .background(SR.ink, in: Circle())
                    .accessibilityHidden(true)
                meta
            }

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

            if !message.toolSteps.isEmpty {
                ToolStepList(steps: message.toolSteps)
                    .padding(12)
                    .srGlassCard(.paper, radius: SR.Glass.innerRadius)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var meta: some View {
        HStack(spacing: 8) {
            Text(message.isUser ? "YOU" : "JKAI")
                .font(SR.monoMedium(12))
                .tracking(1.2)
                .foregroundStyle(message.isUser ? SR.accent : SR.inkSecondary)
            if message.source == "whatsapp" {
                SRPill(text: "WhatsApp", tone: SR.good)
            }
            if let stamp = message.createdAt {
                Text(shortAgo(stamp))
                    .font(SR.mono(12))
                    .foregroundStyle(SR.inkMuted)
            }
        }
    }

    @ViewBuilder
    private func attachments(register: SRRegister) -> some View {
        if !message.attachments.isEmpty {
            ForEach(message.attachments) { attachment in
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
struct TurnActivityPanel: View {
    let activity: TurnActivity
    @State private var thinkingOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.6).tint(SR.accent)
                Text((activity.status ?? "Thinking").uppercased())
                    .font(SR.monoMedium(12))
                    .tracking(1.1)
                    .foregroundStyle(SR.inkSecondary)
            }

            if !activity.steps.isEmpty {
                ToolStepList(steps: activity.steps)
            }

            if !activity.thinking.isEmpty {
                Button {
                    thinkingOpen.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: thinkingOpen ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                        Text("Reasoning").font(SR.mono(12)).tracking(1)
                    }
                    .foregroundStyle(SR.inkMuted)
                }
                .buttonStyle(.plain)

                if thinkingOpen {
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
            Text("Plans, confirmations and credential prompts are answered at the desk. The turn is waiting there, and a WhatsApp message with the link is on its way.")
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
        // `.full` keeps the newlines a transcript depends on; the default
        // collapses them and turns a list into one paragraph.
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        if var parsed = try? AttributedString(markdown: text, options: options) {
            for run in parsed.runs where run.inlinePresentationIntent == .code {
                parsed[run.range].font = SR.mono(14)
            }
            return parsed
        }
        return AttributedString(text)
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
