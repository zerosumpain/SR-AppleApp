import SwiftUI
import UIKit

/// Founding (§1.5 step 1, §9.11): pick a site around Kingsport, build a name
/// from two preset halves, pick an animal mayor and a flag colour.
///
/// Children never type (§9.14): the name is "Sunny" + "vale" from the lists.
/// An adult may type one instead; the server decides whether a typed name is
/// allowed for this seat and says so. Once it is founded the frame carries the
/// town and the screen becomes the map, where Bramble takes over.
struct HometownsFoundingView: View {
    @ObservedObject var store: HometownsStore
    let wire: HometownsWire

    @State private var site: Int?
    @State private var first = HometownsCatalogue.nameFirst[0]
    @State private var second = HometownsCatalogue.nameSecond[0]
    @State private var typing = false
    @State private var typed = ""
    @State private var avatar = HometownsCatalogue.avatars[0]
    @State private var flag = 0
    @State private var working = false
    @State private var refusal: String?

    private var level: HometownsCopyLevel { wire.level }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: wire.county?.name ?? "Kingsport County", title: store.say("founding.title"),
                             strap: store.say("founding.pickSite"))
                sites
                name
                avatars
                flags
                if let refusal {
                    Label(refusal, systemImage: "exclamationmark.circle")
                        .font(SR.Text.bodyMedium(15))
                        .foregroundStyle(SR.error)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("hometowns-found-refusal")
                }
                Button { found() } label: {
                    if working {
                        ProgressView().tint(SR.paper).frame(maxWidth: .infinity)
                    } else {
                        SRButtonLabel(title: store.say("founding.confirm"), icon: "flag.fill", fill: true)
                    }
                }
                .srButton(.prominent)
                .controlSize(.large)
                .disabled(working || chosenSite == nil || (typing && typedName.count < 2))
                .accessibilityIdentifier("hometowns-found")
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .onAppear { if site == nil { site = wire.freeSites.first?.index } }
        .accessibilityIdentifier("hometowns-founding")
    }

    private var chosenSite: Int? {
        guard let site, wire.freeSites.contains(where: { $0.index == site }) else { return wire.freeSites.first?.index }
        return site
    }

    private var typedName: String {
        typed.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "  ", with: " ")
    }

    // MARK: Sites

    private var sites: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: level == .kid ? "Where" : "Site", trailing: "\(wire.freeSites.count) free")
            ForEach(wire.county?.sites ?? []) { s in
                let taken = s.owner != nil
                Button {
                    guard !taken else { return }
                    SRHaptic.select()
                    site = s.index
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: Self.siteSymbol(s.kind))
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(taken ? SR.inkGhost : SR.good)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.copy.say("site.\(s.kind)", level, or: s.kind.capitalized))
                                .font(SR.Text.title())
                                .foregroundStyle(taken ? SR.inkMuted : SR.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            if taken {
                                Text(owner(s))
                                    .font(SR.Text.secondary())
                                    .foregroundStyle(SR.inkMuted)
                            }
                        }
                        Spacer(minLength: 8)
                        if chosenSite == s.index {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(SR.accent).accessibilityLabel("Chosen")
                        }
                    }
                    .frame(minHeight: SR.tapTarget)
                    .padding(.horizontal, SR.cardPadding)
                    .padding(.vertical, 6)
                    .srGlassCard(.paper, radius: SR.Glass.innerRadius, interactive: !taken)
                }
                .buttonStyle(.plain)
                .disabled(taken)
                .accessibilityIdentifier("hometowns-site-\(s.index)")
            }
        }
    }

    private func owner(_ s: HometownsSite) -> String {
        guard let i = s.owner, wire.towns.indices.contains(i) else { return store.say("founding.siteTaken") }
        return "\(wire.towns[i].name) · \(store.say("founding.siteTaken"))"
    }

    static func siteSymbol(_ kind: String) -> String {
        switch kind {
        case "river": return "water.waves"
        case "coast": return "sailboat.fill"
        case "hills": return "mountain.2.fill"
        case "forest": return "tree.fill"
        default: return "leaf.fill"
        }
    }

    // MARK: Name

    private var name: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: store.say("founding.nameTitle"))
            Text(typing ? (typedName.isEmpty ? "…" : typedName) : first + second)
                .font(SR.Text.display(26))
                .foregroundStyle(SR.ink)
                .accessibilityIdentifier("hometowns-name-preview")
            if !typing {
                HStack(spacing: 10) {
                    halfPicker(store.say("founding.nameFirst"), selection: $first, options: HometownsCatalogue.nameFirst, id: "first")
                    halfPicker(store.say("founding.nameSecond"), selection: $second, options: HometownsCatalogue.nameSecond, id: "second")
                }
                Button {
                    SRHaptic.tap()
                    first = HometownsCatalogue.nameFirst.randomElement() ?? first
                    second = HometownsCatalogue.nameSecond.randomElement() ?? second
                } label: {
                    SRButtonLabel(title: level == .kid ? "Surprise me" : "Shuffle", icon: "shuffle")
                }
                .srButton(.regular)
                .accessibilityIdentifier("hometowns-name-shuffle")
            }
            // Adults may type a name (§9.14); a child's seat only ever uses the halves.
            if level == .adult {
                Toggle(isOn: $typing) {
                    Text(store.say("founding.nameTyped"))
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                }
                .tint(SR.accent)
                .accessibilityIdentifier("hometowns-name-type")
                if typing {
                    TextField("Town name", text: $typed)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .font(SR.Text.body())
                        .padding(12)
                        .srGlassCard(.paper, radius: SR.Glass.innerRadius)
                        .onChange(of: typed) { _, text in if text.count > 24 { typed = String(text.prefix(24)) } }
                        .accessibilityIdentifier("hometowns-name-field")
                }
            }
        }
    }

    private func halfPicker(_ title: String, selection: Binding<String>, options: [String], id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(SR.Text.label())
                .tracking(1)
                .foregroundStyle(SR.inkMuted)
            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            .tint(SR.accentInk)
            .onChange(of: selection.wrappedValue) { _, _ in SRHaptic.select() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius)
        .accessibilityIdentifier("hometowns-name-\(id)")
    }

    // MARK: Mayor and flag

    private var avatars: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: store.say("founding.pickAvatar"))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                ForEach(HometownsCatalogue.avatars, id: \.self) { a in
                    Button {
                        SRHaptic.select()
                        avatar = a
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "pawprint.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(avatar == a ? SR.accent : SR.inkMuted)
                            Text(store.say("avatar.\(a)"))
                                .font(SR.Text.secondary())
                                .foregroundStyle(SR.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .srGlassCard(avatar == a ? .accent : .paper, radius: SR.Glass.innerRadius, interactive: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(avatar == a ? .isSelected : [])
                    .accessibilityIdentifier("hometowns-avatar-\(a)")
                }
            }
        }
    }

    private var flags: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: store.say("founding.pickFlag"))
            HStack(spacing: 10) {
                ForEach(0..<HometownsCatalogue.flagColours.count, id: \.self) { n in
                    Button {
                        SRHaptic.select()
                        flag = n
                    } label: {
                        Circle()
                            .fill(HometownsColour.flag(n))
                            .overlay(Circle().stroke(flag == n ? SR.ink : SR.line, lineWidth: flag == n ? 3 : 1))
                            .frame(width: 32, height: 32)
                            .frame(minWidth: SR.tapTarget, minHeight: SR.tapTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(store.say("flag.\(n)"))
                    .accessibilityAddTraits(flag == n ? .isSelected : [])
                    .accessibilityIdentifier("hometowns-flag-\(n)")
                }
            }
        }
    }

    // MARK: Found

    private func found() {
        guard let site = chosenSite else { return }
        working = true
        refusal = nil
        let typedName = typing ? self.typedName : nil
        Task {
            let sentence = await store.found(site: site, nameParts: typedName == nil ? (first, second) : nil, name: typedName,
                                             avatar: avatar, flag: flag)
            working = false
            if let sentence {
                refusal = sentence
                SRHaptic.bad()
                UIAccessibility.post(notification: .announcement, argument: sentence)
            } else {
                SRHaptic.ok()
            }
        }
    }
}
