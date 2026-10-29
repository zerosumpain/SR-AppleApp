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
    @State private var howToPlay = false
    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 52

    private var level: HometownsCopyLevel { wire.level }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                header
                sites
                name
                avatars
                flags
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 20)
        }
        .srGround(.warm)
        .safeAreaInset(edge: .bottom) { foundBar }
        .onAppear { if site == nil { site = wire.freeSites.first?.index } }
        .sheet(isPresented: $howToPlay) { HometownsHowToPlaySheet(level: level) }
        .accessibilityIdentifier("hometowns-founding")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            SRPageHeader(kicker: wire.county?.name ?? "Kingsport County", title: store.say("founding.title"),
                         strap: store.say("founding.pickSite"))
            Button {
                SRHaptic.tap()
                howToPlay = true
            } label: {
                HometownsBigLabel(title: "How to play", icon: "questionmark.circle")
            }
            .srButton(.regular)
            .accessibilityIdentifier("hometowns-found-how")
        }
    }

    /// Found, always in reach under the scroll, with the server's refusal above it.
    private var foundBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let refusal {
                Label(refusal, systemImage: "exclamationmark.circle.fill")
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("hometowns-found-refusal")
            }
            HStack(spacing: 12) {
                HometownsCritterBadge(animal: avatar, ground: HometownsColour.flag(flag), size: 44)
                Button { found() } label: {
                    if working {
                        ProgressView().tint(Color.white).frame(maxWidth: .infinity, minHeight: 44)
                    } else {
                        HometownsBigLabel(title: store.say("founding.confirm"), icon: "flag.fill", fill: true)
                    }
                }
                .srButton(.prominent)
                .disabled(working || chosenSite == nil || (typing && typedName.count < 2))
                .accessibilityIdentifier("hometowns-found")
            }
        }
        .padding(.horizontal, SR.gutter)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private var chosenSite: Int? {
        guard let site, wire.freeSites.contains(where: { $0.index == site }) else { return wire.freeSites.first?.index }
        return site
    }

    private var typedName: String {
        typed.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "  ", with: " ")
    }

    private var shownName: String {
        typing ? (typedName.isEmpty ? "…" : typedName) : first + second
    }

    // MARK: Sites

    private var sites: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: level == .kid ? "Where" : "Site", trailing: "\(wire.freeSites.count) free")
            if wire.county != nil {
                map
            }
            ForEach(wire.county?.sites ?? []) { s in
                siteRow(s)
            }
        }
    }

    /// The county drawn from above; a free site is tapped to pick it. The rows
    /// under it are the same choice for VoiceOver, so the map is hidden from it.
    private var map: some View {
        GeometryReader { geo in
            let size = geo.size
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = HometownsRing.ringRadius(size)
            let r = HometownsRing.siteRadius(size)
            ZStack {
                HometownsRing(wire: wire, selected: chosenSite)
                ForEach(wire.freeSites) { s in
                    Circle()
                        .fill(Color.white.opacity(0.001))
                        .frame(width: max(56, r * 2 + 16), height: max(56, r * 2 + 16))
                        .contentShape(Circle())
                        .position(HometownsRing.point(s.index, centre: centre, radius: radius))
                        .onTapGesture { pick(s.index) }
                }
            }
        }
        .frame(height: 280)
        .srGlassCard(.paper)
        .srAnimation(.snappy, value: chosenSite)
        .accessibilityHidden(true)
    }

    private func pick(_ index: Int) {
        guard site != index else { return }
        SRHaptic.select()
        site = index
    }

    private func siteRow(_ s: HometownsSite) -> some View {
        let taken = s.owner != nil
        let chosen = chosenSite == s.index
        return Button {
            guard !taken else { return }
            pick(s.index)
        } label: {
            HStack(spacing: 12) {
                HometownsSiteTile(kind: s.kind, taken: taken)
                    .frame(width: 52, height: 52)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: Self.siteSymbol(s.kind))
                            .font(SR.Text.label(12))
                            .foregroundStyle(Color.white)
                            .padding(4)
                            .background(Circle().fill(Color.black.opacity(0.35)))
                            .padding(2)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.copy.say("site.\(s.kind)", level, or: s.kind.capitalized))
                        .font(SR.Text.title())
                        .foregroundStyle(taken ? SR.inkMuted : SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if taken {
                        Text(owner(s))
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if chosen {
                    Image(systemName: "checkmark.circle.fill")
                        .font(SR.Text.title(22))
                        .foregroundStyle(SR.accent)
                        .accessibilityLabel("Chosen")
                }
            }
            .frame(minHeight: 56)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .srGlassCard(.paper, radius: SR.Glass.innerRadius, interactive: !taken)
            .overlay(
                RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                    .stroke(chosen ? SR.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(SRPressStyle())
        .disabled(taken)
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier("hometowns-site-\(s.index)")
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
            signpost
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
                    HometownsBigLabel(title: level == .kid ? "Surprise me" : "Shuffle", icon: "shuffle")
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
                        .padding(14)
                        .frame(minHeight: 52)
                        .srGlassCard(.paper, radius: SR.Glass.innerRadius)
                        .onChange(of: typed) { _, text in if text.count > 24 { typed = String(text.prefix(24)) } }
                        .accessibilityIdentifier("hometowns-name-field")
                }
            }
        }
    }

    /// The name on the town's signpost, with its flag flying beside it.
    private var signpost: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(spacing: 0) {
                Text(shownName)
                    .font(SR.Text.display(26))
                    .foregroundStyle(Color(hex: 0x2A211C))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.opacity)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(LinearGradient(colors: [Color(hex: 0xF2D58A), Color(hex: 0xE0B65A)], startPoint: .top, endPoint: .bottom))
                    )
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color(hex: 0x8A6A3A), lineWidth: 2))
                    .srAnimation(.snappy, value: shownName)
                    .accessibilityLabel("Town name: \(shownName)")
                    .accessibilityIdentifier("hometowns-name-preview")
                HStack(spacing: 60) {
                    Rectangle().fill(Color(hex: 0x6B4E33)).frame(width: 6, height: 26)
                    Rectangle().fill(Color(hex: 0x6B4E33)).frame(width: 6, height: 26)
                }
                .accessibilityHidden(true)
            }
            HometownsFlagPole(colour: HometownsColour.flag(flag), height: 64)
                .srAnimation(.snappy, value: flag)
        }
        .padding(.top, 4)
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
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .padding(10)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius)
        .accessibilityIdentifier("hometowns-name-\(id)")
    }

    // MARK: Mayor and flag

    private var avatars: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: store.say("founding.pickAvatar"))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                ForEach(HometownsCatalogue.avatars, id: \.self) { a in
                    avatarButton(a)
                }
            }
        }
    }

    private func avatarButton(_ a: String) -> some View {
        let on = avatar == a
        return Button {
            SRHaptic.select()
            avatar = a
        } label: {
            VStack(spacing: 6) {
                HometownsCritterBadge(animal: a, ground: on ? HometownsColour.flag(flag) : SR.line, size: avatarSize)
                    .scaleEffect(on ? 1.06 : 1)
                Text(store.say("avatar.\(a)"))
                    .font(SR.Text.secondary())
                    .foregroundStyle(on ? SR.ink : SR.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .padding(.vertical, 6)
            .srGlassCard(.paper, radius: SR.Glass.innerRadius, interactive: true)
            .overlay(
                RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                    .stroke(on ? SR.accent : Color.clear, lineWidth: 2.5)
            )
            .srAnimation(.snappy, value: on)
        }
        .buttonStyle(SRPressStyle())
        .accessibilityLabel(store.say("avatar.\(a)"))
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("hometowns-avatar-\(a)")
    }

    private var flags: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: store.say("founding.pickFlag"))
            // A grid, not a row: eight thumb-sized targets and their gaps are
            // wider than a phone's column, and wrap at large text sizes too.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(0..<HometownsCatalogue.flagColours.count, id: \.self) { n in
                    flagButton(n)
                }
            }
        }
    }

    private func flagButton(_ n: Int) -> some View {
        let on = flag == n
        return Button {
            SRHaptic.select()
            flag = n
        } label: {
            HometownsPennant()
                .fill(HometownsColour.flag(n))
                .overlay(HometownsPennant().stroke(on ? SR.ink : SR.line, lineWidth: on ? 3 : 1))
                .frame(width: 40, height: 28)
                .offset(y: on ? -3 : 0)
                .frame(minWidth: 64, minHeight: 56)
                .background(
                    RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                        .fill(on ? SR.accent.opacity(0.16) : SR.ink.opacity(0.04))
                )
                .contentShape(Rectangle())
                .srAnimation(.snappy, value: on)
        }
        .buttonStyle(SRPressStyle())
        .accessibilityLabel(store.say("flag.\(n)"))
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("hometowns-flag-\(n)")
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
