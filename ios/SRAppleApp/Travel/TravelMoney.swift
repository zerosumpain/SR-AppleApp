import SwiftUI

/// Euros and pounds: a converter, a cheat sheet of everyday prices, and a
/// bill splitter that knows the Italian bill.
///
/// The rate is the European Central Bank's reference rate (via Frankfurter, no
/// key, nothing about you sent), fetched when the page opens and KEPT, so it
/// works with roaming off; it says how old it is. A card's own rate differs a
/// little — the "my rate" override is for whoever wants their bank's figure.
struct TravelMoneyScreen: View {
    @ObservedObject private var rates = TravelRates.shared
    @State private var amount = ""
    @State private var euros = true
    @State private var bill = ""
    @State private var people = 5
    @State private var tip = 0
    @State private var editingRate = false
    @State private var rateDraft = ""
    @FocusState private var focus: Field?

    enum Field { case amount, bill, rate }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                converter
                cheatSheet
                splitter
                tips
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .srGround(.warm)
        .navigationTitle("Money")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus = nil }
            }
        }
        .task { await rates.refresh() }
        .srRefreshable { await rates.refresh(force: true) }
        .accessibilityIdentifier("travel-money")
    }

    // MARK: - Converter

    private var converter: some View {
        SRCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(euros ? "€" : "£").font(SR.Text.hero(34)).foregroundStyle(SR.inkMuted)
                    TextField("0", text: $amount)
                        .keyboardType(.decimalPad)
                        .font(SR.Text.hero(34))
                        .focused($focus, equals: .amount)
                        .accessibilityIdentifier("travel-money-amount")
                    Button {
                        SRHaptic.select()
                        euros.toggle()
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle.fill").font(.system(size: 30))
                    }
                    .foregroundStyle(SR.accent)
                    .accessibilityLabel(euros ? "Switch to pounds into euros" : "Switch to euros into pounds")
                }
                Text(converted)
                    .font(SR.Text.figure(30))
                    .foregroundStyle(SR.ink)
                    .accessibilityIdentifier("travel-money-result")
                rateLine
            }
        }
    }

    private var converted: String {
        guard let value = Self.number(amount), let rate = rates.rate else { return euros ? "£ —" : "€ —" }
        return euros ? Self.pounds(value / rate) : Self.euros(value * rate)
    }

    @ViewBuilder
    private var rateLine: some View {
        if editingRate {
            HStack {
                Text("£1 = €").font(SR.Text.secondary(14))
                TextField("1.19", text: $rateDraft)
                    .keyboardType(.decimalPad)
                    .focused($focus, equals: .rate)
                    .frame(width: 80)
                Button("Use") {
                    rates.override(Self.number(rateDraft))
                    editingRate = false
                    focus = nil
                }
                Button("Reset") {
                    rates.override(nil)
                    editingRate = false
                }
                .foregroundStyle(SR.inkMuted)
            }
            .font(SR.Text.label(13))
        } else {
            Button {
                rateDraft = rates.rate.map { String(format: "%.4f", $0) } ?? ""
                editingRate = true
                focus = .rate
            } label: {
                Text(rates.describe)
                    .font(SR.Text.mono(12))
                    .foregroundStyle(rates.stale ? SR.warn : SR.inkMuted)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Set your own rate")
        }
    }

    // MARK: - Cheat sheet

    private var cheatSheet: some View {
        VStack(alignment: .leading, spacing: 8) {
            SRSectionLabel(text: "Everyday prices", trailing: "in pounds")
            let prices: [(Double, String)] = [
                (1.5, "an espresso at the bar"), (3, "a gelato"), (1.5, "a bus or metro ride"),
                (10, "a pizza"), (25, "a family museum ticket"), (55, "an airport taxi to the centre")
            ]
            if let rate = rates.rate {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach([1.0, 5, 10, 20, 50, 100], id: \.self) { euro in
                        HStack {
                            Text(Self.euros(euro)).font(SR.Text.bodyMedium(16)).foregroundStyle(SR.ink)
                            Spacer()
                            Text(Self.pounds(euro / rate)).font(SR.Text.body(16)).foregroundStyle(SR.inkSecondary)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(SR.surface))
                    }
                }
                Text("Roughly: " + prices.map { "\(Self.euros($0.0)) \($0.1)" }.joined(separator: " · ") + ". Prices vary; these are a feel, not a quote.")
                    .font(SR.Text.secondary(12))
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No rate yet — open this once with signal, or tap the rate line to type your own.")
                    .font(SR.Text.secondary(14))
                    .foregroundStyle(SR.inkSecondary)
            }
        }
    }

    // MARK: - Split the bill

    private var splitter: some View {
        VStack(alignment: .leading, spacing: 8) {
            SRSectionLabel(text: "Split the bill")
            SRCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Total €").font(SR.Text.bodyMedium(16))
                        TextField("0.00", text: $bill)
                            .keyboardType(.decimalPad)
                            .font(SR.Text.title(19))
                            .multilineTextAlignment(.trailing)
                            .focused($focus, equals: .bill)
                            .accessibilityIdentifier("travel-bill-total")
                    }
                    Stepper("Between \(people)", value: $people, in: 1...20)
                        .font(SR.Text.bodyMedium(16))
                    Picker("Extra", selection: $tip) {
                        Text("No tip").tag(0)
                        Text("Round up").tag(-1)
                        Text("5%").tag(5)
                        Text("10%").tag(10)
                    }
                    .pickerStyle(.segmented)
                    if let total = Self.number(bill), total > 0 {
                        let paid = Self.withTip(total, tip)
                        let each = paid / Double(people)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Each pays \(Self.euros(each))")
                                .font(SR.Text.figure(24))
                                .foregroundStyle(SR.ink)
                            Text("Leave \(Self.euros(paid)) in all" + (rates.rate.map { " · about \(Self.pounds(paid / $0))" } ?? ""))
                                .font(SR.Text.secondary(14))
                                .foregroundStyle(SR.inkSecondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 6) {
            SRSectionLabel(text: "Worth knowing")
            ForEach([
                "When a card machine offers pounds or euros, choose EUROS — picking pounds lets the shop's bank set a worse rate.",
                "Coperto (cover, a few euros a head) and sometimes servizio are printed on the bill. Neither is a tip.",
                "Standing at the bar is cheaper than sitting at a table for the same coffee.",
                "Keep some coins: small cafés, toilets and some buses prefer cash.",
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

    // MARK: - Arithmetic

    /// "12,50" and "12.50" both, as typed on a phone set to either region.
    static func number(_ text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: ",", with: ".").filter { "0123456789.".contains($0) }
        guard let value = Double(cleaned), value.isFinite, value >= 0 else { return nil }
        return value
    }

    /// `tip` is a percentage, or -1 to round up to the next whole €5 (a
    /// bill already on one is left as it is).
    static func withTip(_ total: Double, _ tip: Int) -> Double {
        if tip < 0 { return (total / 5).rounded(.up) * 5 }
        return total * (1 + Double(tip) / 100)
    }

    static func euros(_ value: Double) -> String { money(value, "EUR") }
    static func pounds(_ value: Double) -> String { money(value, "GBP") }

    private static func money(_ value: Double, _ code: String) -> String {
        value.formatted(.currency(code: code).precision(.fractionLength(value >= 100 ? 0 : 2)).locale(Locale(identifier: "en_GB")))
    }
}

/// The pound → euro rate, kept on the phone.
@MainActor
final class TravelRates: ObservableObject {
    static let shared = TravelRates()

    /// Euros to one pound.
    @Published private(set) var rate: Double?
    /// The ECB date the rate is for, "2026-10-23".
    @Published private(set) var date: String?
    @Published private(set) var fetched: Date?
    @Published private(set) var custom = false

    private let defaults = UserDefaults.standard
    private static let key = "travel.rates.v1"

    private struct Stored: Codable {
        var rate: Double
        var date: String?
        var fetched: Date?
        var custom: Bool
    }

    init() {
        if let data = defaults.data(forKey: Self.key), let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            rate = stored.rate
            date = stored.date
            fetched = stored.fetched
            custom = stored.custom
        }
    }

    var stale: Bool {
        guard !custom, let fetched else { return rate == nil }
        return Date().timeIntervalSince(fetched) > 4 * 86_400
    }

    var describe: String {
        guard let rate else { return "No rate yet · tap to set one" }
        let base = "£1 = €" + String(format: "%.4f", rate)
        if custom { return base + " · your rate · tap to change" }
        let when = fetched.map { "updated " + $0.formatted(.relative(presentation: .named)) } ?? ""
        return base + " · ECB \(date ?? "")" + (when.isEmpty ? "" : " · \(when)") + " · tap to set your own"
    }

    func override(_ value: Double?) {
        if let value, value > 0 {
            rate = value
            custom = true
            save()
        } else {
            custom = false
            Task { await refresh(force: true) }
        }
    }

    func refresh(force: Bool = false) async {
        if custom { return }
        if !force, let fetched, Date().timeIntervalSince(fetched) < 6 * 3600 { return }
        guard let url = URL(string: "https://api.frankfurter.dev/v1/latest?base=GBP&symbols=EUR") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        struct Answer: Decodable { let date: String; let rates: [String: Double] }
        guard let reply = try? await URLSession.shared.data(for: request),
              (reply.1 as? HTTPURLResponse)?.statusCode == 200,
              let answer = try? JSONDecoder().decode(Answer.self, from: reply.0),
              let euro = answer.rates["EUR"], euro > 0 else { return }
        rate = euro
        date = answer.date
        fetched = Date()
        save()
    }

    private func save() {
        guard let rate else { return }
        let stored = Stored(rate: rate, date: date, fetched: fetched, custom: custom)
        defaults.set(try? JSONEncoder().encode(stored), forKey: Self.key)
    }
}
