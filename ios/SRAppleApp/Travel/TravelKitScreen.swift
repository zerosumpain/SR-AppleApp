import SwiftUI

/// Navigation values for the Travel kit, pushed from the hub.
struct TravelKitRef: Hashable {}

enum TravelToolRef: String, Hashable, CaseIterable {
    case translate, reader, phrases, money, wayBack
}

/// The Travel kit: five tools for being abroad, all on the phone.
///
/// Built for Newcastle → Rome (2026-10-26) and kept general: none of it needs
/// the site, a pairing or a trip, so it is in everyone's hub. Each tool works
/// with roaming off once it has been opened on Wi-Fi — the translator needs
/// its language downloaded, Money needs one rate fetch — and the page says
/// which are ready.
struct TravelKitScreen: View {
    @EnvironmentObject private var router: Router
    @ObservedObject private var rates = TravelRates.shared
    @StateObject private var bridge = TravelTranslationBridge()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                VStack(spacing: SR.cardGap) {
                    ForEach(TravelToolRef.allCases, id: \.self) { tool in
                        Button {
                            SRHaptic.tap()
                            router.pushFromHub(tool)
                        } label: {
                            MoreCard(icon: tool.icon, fill: tool.fill, title: tool.title, blurb: tool.blurb, status: status(tool))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("travel-tool-\(tool.rawValue)")
                    }
                }
                TravelEssentials()
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .background(TravelTranslationHost(bridge: bridge))
        .srGround(.warm)
        .navigationTitle("Travel kit")
        .navigationBarTitleDisplayMode(.inline)
        .task { await rates.refresh() }
        .accessibilityIdentifier("travel-kit")
    }

    private func status(_ tool: TravelToolRef) -> String? {
        switch tool {
        case .translate, .reader:
            if !TravelTranslationBridge.supported { return "Needs iOS 18" }
            return bridge.installed ? "\(bridge.language.name) offline" : "Download \(bridge.language.name)"
        case .phrases: return "Works offline"
        case .money: return rates.rate.map { String(format: "£1 = €%.2f", $0) }
        case .wayBack:
            let pins = TravelPin.load()
            return pins.isEmpty ? nil : (pins.count == 1 ? pins[0].name : "\(pins.count) pins")
        }
    }
}

extension TravelToolRef {
    var title: String {
        switch self {
        case .translate: return "Live translate"
        case .reader: return "Read a sign"
        case .phrases: return "Phrasebook"
        case .money: return "Money"
        case .wayBack: return "Way back"
        }
    }

    var blurb: String {
        switch self {
        case .translate: return "Talk both ways, or live captions of a guide or announcement, translated as it's said."
        case .reader: return "Photograph a menu, sign or label and read every line in English."
        case .phrases: return "Italian to say or show: eating, allergies, getting around, help."
        case .money: return "Euros to pounds, everyday prices and splitting the bill."
        case .wayBack: return "Pin the hotel; an arrow points back to it, signal or not."
        }
    }

    var icon: String {
        switch self {
        case .translate: return "waveform.and.mic"
        case .reader: return "text.viewfinder"
        case .phrases: return "character.book.closed.fill"
        case .money: return "eurosign.circle.fill"
        case .wayBack: return "location.north.line.fill"
        }
    }

    var fill: Color {
        switch self {
        case .translate: return SR.accent
        case .reader: return SR.accentInk
        case .phrases: return SR.accentDeep
        case .money: return SR.good
        case .wayBack: return SR.warn
        }
    }

    @ViewBuilder
    var screen: some View {
        switch self {
        case .translate: TravelTranslateScreen()
        case .reader: TravelSignReaderScreen()
        case .phrases: TravelPhrasebookScreen()
        case .money: TravelMoneyScreen()
        case .wayBack: TravelWayBackScreen()
        }
    }
}

/// Italy at a glance: both clocks, the numbers to call and the things a
/// first morning in Rome trips over.
struct TravelEssentials: View {
    private static let rome = TimeZone(identifier: "Europe/Rome") ?? .current
    private static let home = TimeZone(identifier: "Europe/London") ?? .current

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Italy essentials")
            TimelineView(.everyMinute) { context in
                HStack(spacing: SR.cardGap) {
                    clock("Rome", context.date, Self.rome)
                    clock("Home", context.date, Self.home)
                }
            }
            SRCard {
                VStack(alignment: .leading, spacing: 10) {
                    call("Emergency — police, ambulance, fire", "112", "112")
                    Divider()
                    call("British Embassy, Rome", "+39 06 4220 0001", "+390642200001")
                    Divider()
                    call("UK Foreign Office, 24 hours", "+44 20 7008 5000", "+442070085000")
                }
            }
            ForEach([
                "Sockets are types C, F and L — a UK plug needs an adapter.",
                "The nasoni (street fountains) run with cold drinking water: bring a bottle to fill.",
                "St Peter's, the Vatican and most churches turn away bare shoulders and knees.",
                "Validate a paper bus or tram ticket in the machine as you board; a contactless card at the gate does it for you.",
            ], id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Text("•").foregroundStyle(SR.accent)
                    Text(line)
                        .font(SR.Text.secondary(14))
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func clock(_ label: String, _ now: Date, _ zone: TimeZone) -> some View {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = zone
        return VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(SR.Text.label(11)).foregroundStyle(SR.inkMuted)
            Text(now.formatted(style)).font(SR.Text.figure(26)).foregroundStyle(SR.ink)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(SR.surface))
        .accessibilityElement(children: .combine)
    }

    private func call(_ label: String, _ shown: String, _ dial: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(SR.Text.secondary(13)).foregroundStyle(SR.inkSecondary)
                Text(shown).font(SR.Text.title(17)).foregroundStyle(SR.ink)
            }
            Spacer()
            if let url = URL(string: "tel:\(dial)") {
                Link(destination: url) {
                    Image(systemName: "phone.fill")
                        .foregroundStyle(SR.paper)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(dial == "112" ? SR.error : SR.good))
                }
                .accessibilityLabel("Call \(label)")
            }
        }
    }
}
