import SwiftUI

/// Italian to say or show, with no signal and no model: every phrase is
/// written here, so the book works on an iOS 17 phone and with the language
/// not downloaded. Tap a phrase to hear it, hold it up with "Show".
///
/// "Your own" turns any English line into Italian with the on-phone
/// translator and keeps it — the allergy, the hotel's name, the child's age
/// for a ticket desk.
struct TravelPhrasebookScreen: View {
    @StateObject private var bridge = TravelTranslationBridge()
    @ObservedObject private var voice = TravelVoice.shared
    @State private var section = TravelPhrases.sections[0].id
    @State private var draft = ""
    @State private var drafting = false
    @State private var own: [TravelPhrase] = TravelPhrases.loadOwn()
    @State private var showing: TravelShowCard?
    @FocusState private var typing: Bool

    private let speech = TravelLanguage.italian.speech

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.cardGap) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(TravelPhrases.sections) { s in
                            Button {
                                SRHaptic.select()
                                section = s.id
                            } label: {
                                Label(s.title, systemImage: s.icon)
                                    .font(SR.Text.label(13))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .foregroundStyle(section == s.id ? SR.paper : SR.ink)
                                    .background(Capsule().fill(section == s.id ? SR.accent : SR.surface))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(section == s.id ? .isSelected : [])
                        }
                    }
                }
                if section == TravelPhrases.ownSection {
                    ownComposer
                    if own.isEmpty {
                        Text("Nothing saved yet. Type a line in English above.")
                            .font(SR.Text.secondary(14))
                            .foregroundStyle(SR.inkMuted)
                    }
                    ForEach(own) { phrase in
                        row(phrase)
                            .contextMenu {
                                Button(role: .destructive) { remove(phrase) } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                } else if let current = TravelPhrases.sections.first(where: { $0.id == section }) {
                    if let note = current.note {
                        Text(note)
                            .font(SR.Text.secondary(13))
                            .foregroundStyle(SR.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(current.phrases) { row($0) }
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(TravelTranslationHost(bridge: bridge))
        .srGround(.warm)
        .navigationTitle("Phrasebook")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $showing) { TravelShowSheet(card: $0) }
        .onAppear { bridge.language = .italian }
        .onDisappear { voice.stop() }
        .accessibilityIdentifier("travel-phrasebook")
    }

    private func row(_ phrase: TravelPhrase) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                SRHaptic.tap()
                voice.say(phrase.italian, in: speech, slow: true)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(phrase.english)
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.inkSecondary)
                    Text(phrase.italian)
                        .font(SR.Text.title(17))
                        .foregroundStyle(SR.ink)
                    if let say = phrase.say {
                        Text(say)
                            .font(SR.Text.mono(12))
                            .foregroundStyle(SR.inkMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Says it in Italian")
            Button {
                showing = TravelShowCard(big: phrase.italian, small: phrase.english, speech: speech)
            } label: {
                Image(systemName: "rectangle.expand.vertical")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SR.accent)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show it big")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(SR.surface))
    }

    private var ownComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            TravelTranslatorNote(bridge: bridge)
            HStack(spacing: 8) {
                TextField("Say it in English…", text: $draft, axis: .vertical)
                    .lineLimit(1...3)
                    .focused($typing)
                    .submitLabel(.done)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(SR.surface))
                    .accessibilityIdentifier("travel-own-field")
                Button {
                    Task { await add() }
                } label: {
                    if drafting { ProgressView() } else { Image(systemName: "plus.circle.fill").font(.system(size: 28)) }
                }
                .foregroundStyle(SR.accent)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || drafting || !TravelTranslationBridge.supported)
                .accessibilityLabel("Translate and keep")
            }
        }
    }

    private func add() async {
        let english = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !english.isEmpty else { return }
        drafting = true
        defer { drafting = false }
        guard let italian = await bridge.translate(english, .out) else { return }
        typing = false
        draft = ""
        own.insert(TravelPhrase(english: english, italian: italian), at: 0)
        TravelPhrases.saveOwn(own)
        voice.say(italian, in: speech, slow: true)
    }

    private func remove(_ phrase: TravelPhrase) {
        own.removeAll { $0.id == phrase.id }
        TravelPhrases.saveOwn(own)
    }
}

struct TravelPhrase: Identifiable, Hashable, Codable {
    var id: String { english + "|" + italian }
    let english: String
    let italian: String
    /// A rough sound-it-out, stress in capitals.
    var say: String? = nil
}

struct TravelPhraseSection: Identifiable {
    let id: String
    let title: String
    let icon: String
    var note: String? = nil
    let phrases: [TravelPhrase]
}

enum TravelPhrases {
    static let ownSection = "own"
    static let ownKey = "travel.phrases.own"

    static func loadOwn() -> [TravelPhrase] {
        guard let data = UserDefaults.standard.data(forKey: ownKey) else { return [] }
        return (try? JSONDecoder().decode([TravelPhrase].self, from: data)) ?? []
    }

    static func saveOwn(_ phrases: [TravelPhrase]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(phrases), forKey: ownKey)
    }

    private static func p(_ english: String, _ italian: String, _ say: String? = nil) -> TravelPhrase {
        TravelPhrase(english: english, italian: italian, say: say)
    }

    static let sections: [TravelPhraseSection] = [
        TravelPhraseSection(id: "basics", title: "Basics", icon: "hand.wave", phrases: [
            p("Hello / good morning", "Buongiorno", "bwon-JOR-no"),
            p("Good evening", "Buonasera", "bwon-a-SAIR-a"),
            p("Hi / bye (friendly)", "Ciao", "chow"),
            p("Please", "Per favore", "pair fa-VOR-ay"),
            p("Thank you (very much)", "Grazie (mille)", "GRAT-see-ay MEE-lay"),
            p("You're welcome", "Prego", "PRAY-go"),
            p("Excuse me (to get attention)", "Scusi", "SKOO-zee"),
            p("Sorry", "Mi dispiace", "mee dee-SPYAH-chay"),
            p("Yes / no", "Sì / no"),
            p("Do you speak English?", "Parla inglese?", "PAR-la een-GLAY-zay"),
            p("I don't understand", "Non capisco", "non ka-PEE-sko"),
            p("Could you say that more slowly?", "Può parlare più lentamente?", "pwoh par-LAR-ay pyoo len-ta-MEN-tay"),
            p("Goodbye", "Arrivederci", "ar-ree-veh-DAIR-chee"),
        ]),
        TravelPhraseSection(id: "food", title: "Eating", icon: "fork.knife",
            note: "A cover charge (coperto) per person is normal on the bill and is not a tip. Tipping isn't expected; rounding up for good service is plenty.",
            phrases: [
                p("A table for five, please", "Un tavolo per cinque, per favore", "oon TA-vo-lo pair CHEEN-kway"),
                p("Can we see the menu?", "Possiamo vedere il menù?"),
                p("What do you recommend?", "Cosa ci consiglia?", "KO-za chee kon-SEEL-ya"),
                p("Is there a children's menu?", "C'è un menù per bambini?"),
                p("Still / sparkling water", "Acqua naturale / frizzante", "AK-wa na-too-RA-lay / freet-SAN-tay"),
                p("Tap water is fine", "Va bene l'acqua del rubinetto"),
                p("I'll have this, please", "Prendo questo, per favore", "PREN-do KWES-to"),
                p("Without…", "Senza…", "SEN-tsa"),
                p("Is it spicy?", "È piccante?"),
                p("The bill, please", "Il conto, per favore", "eel KON-to"),
                p("Can I pay by card?", "Posso pagare con la carta?"),
                p("A coffee (espresso)", "Un caffè", "oon kaf-FEH"),
                p("Two ice creams: a cone and a cup", "Due gelati: un cono e una coppetta"),
                p("It was delicious!", "Era buonissimo!"),
            ]),
        TravelPhraseSection(id: "allergy", title: "Allergies", icon: "allergens",
            note: "Show these rather than say them — the Show button fills the screen. Add your own exact wording under Your own.",
            phrases: [
                p("I'm allergic to… (a woman says allergica)", "Sono allergico a…"),
                p("…nuts", "…frutta a guscio"),
                p("…peanuts", "…arachidi"),
                p("…milk / dairy", "…latte e latticini"),
                p("…eggs", "…uova"),
                p("…gluten. I'm coeliac", "…glutine. Sono celiaco"),
                p("…shellfish", "…crostacei e frutti di mare"),
                p("Does this contain…?", "Questo contiene…?"),
                p("It's very serious", "È molto grave"),
            ]),
        TravelPhraseSection(id: "around", title: "Getting around", icon: "tram.fill", phrases: [
            p("Where is…?", "Dov'è…?", "doh-VEH"),
            p("How do I get to…?", "Come arrivo a…?"),
            p("Is it far? / Is it near?", "È lontano? / È vicino?"),
            p("Left / right / straight on", "Sinistra / destra / sempre dritto"),
            p("A ticket, please", "Un biglietto, per favore", "oon beel-YET-to"),
            p("Two adults and three children", "Due adulti e tre bambini"),
            p("Which stop for…?", "Qual è la fermata per…?"),
            p("Does this bus go to…?", "Questo autobus va a…?"),
            p("Take me to this address, please", "Mi porti a questo indirizzo, per favore"),
            p("How much to…?", "Quanto costa fino a…?"),
            p("Where are the toilets?", "Dove sono i bagni?", "DOH-vay SO-no ee BAN-yee"),
            p("What time does it open / close?", "A che ora apre / chiude?"),
        ]),
        TravelPhraseSection(id: "shop", title: "Shopping", icon: "bag.fill", phrases: [
            p("How much is it?", "Quanto costa?", "KWAN-to KOS-ta"),
            p("I'm just looking, thanks", "Sto solo guardando, grazie"),
            p("Do you have a smaller / bigger size?", "Avete una taglia più piccola / più grande?"),
            p("I'll take it", "Lo prendo"),
            p("A bag, please", "Una busta, per favore"),
            p("Pharmacy", "Farmacia", "far-ma-CHEE-a"),
            p("Sun cream", "Crema solare"),
            p("Something for a headache", "Qualcosa per il mal di testa"),
        ]),
        TravelPhraseSection(id: "help", title: "Help", icon: "cross.case.fill",
            note: "Emergency in Italy (and across Europe): 112.",
            phrases: [
                p("Help!", "Aiuto!", "ah-YOO-to"),
                p("Call an ambulance", "Chiami un'ambulanza", "KYA-mee"),
                p("I need a doctor", "Ho bisogno di un medico"),
                p("Where is the nearest hospital?", "Dov'è l'ospedale più vicino?"),
                p("I've lost my son (daughter: mia figlia)", "Ho perso mio figlio"),
                p("I've lost my passport", "Ho perso il passaporto"),
                p("My bag has been stolen", "Mi hanno rubato la borsa"),
                p("Where are the police?", "Dov'è la polizia?"),
                p("I'm staying at…", "Alloggio a…"),
            ]),
        TravelPhraseSection(id: ownSection, title: "Your own", icon: "plus.bubble", phrases: []),
    ]
}
