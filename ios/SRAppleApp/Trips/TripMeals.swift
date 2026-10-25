import SwiftUI

// Real meals (v7): a lunch or dinner the plan gave a time but no place now
// carries up to three real places near where you will be, open then, found
// on OpenStreetMap by the site (SR-Main `meals.ts`). Choosing one makes it a
// wish that IS that meal (`replacesMeal`), so the plan routes you there; for
// someone who can't change the plan it becomes a suggestion for a parent.

extension PlannedStop {
    /// "lunch" or "dinner", from the meal stop's id (`meal:<date>:lunch`).
    var mealName: String? {
        guard kind == .meal else { return nil }
        if id.hasSuffix(":lunch") { return "lunch" }
        if id.hasSuffix(":dinner") { return "dinner" }
        return nil
    }

    /// A meal still waiting for a place, with places to choose from. A
    /// meal stop is always a placeholder — the solver pins it where you
    /// were before, or at the stay — since a chosen place is a wish stop.
    var awaitsMealChoice: Bool { mealName != nil && !(mealOptions ?? []).isEmpty }
}

extension MealOption {
    /// "Italian · 4 min walk from the Pantheon".
    var line: String {
        [cuisine ?? (kind == "cafe" ? "Café" : "Restaurant"), "\(Int(walkMin)) min walk from \(walkFrom)"].joined(separator: " · ")
    }
}

/// The three places for one meal, under its row in the day: each with what
/// it is, the walk, its hours that day, and Choose (or Suggest).
struct TripMealChoices: View {
    let tripId: String
    let day: PlannedDay
    let stop: PlannedStop
    let bundle: TripBundle
    /// Bigger, with photographs: the stop screen's version.
    var large = false
    /// "Map": the option's pin on the day map.
    var onShow: ((MealOption) -> Void)? = nil
    @ObservedObject private var store = TripStore.shared
    @ObservedObject private var network = TripNetwork.shared
    @Environment(\.tripOnDark) private var onDark
    @State private var busy: String?
    @State private var message: String?

    private var options: [MealOption] { stop.mealOptions ?? [] }
    private var can: TripAccess { bundle.can }

    var body: some View {
        if stop.awaitsMealChoice {
            VStack(alignment: .leading, spacing: 8) {
                if !large {
                    Text("Where to eat · \(options.count) nearby, open then")
                        .font(SR.Text.label(11))
                        .foregroundStyle(onDark ? SR.creamOnDark : SR.inkMuted)
                }
                ForEach(options) { option in
                    TripMealOptionCard(
                        option: option,
                        photo: bundle.images?[option.id],
                        large: large,
                        actionLabel: can.canEdit || can.canApprove ? "Choose" : "Suggest",
                        busy: busy == option.id,
                        // One choice at a time, and only with a connection.
                        enabled: busy == nil && (network.online || SRDemo.isOn),
                        choose: { choose(option) },
                        show: onShow.map { show in { show(option) } }
                    )
                }
                Text("From OpenStreetMap. Walks are straight-line estimates; check a place's hours before you go.")
                    .font(SR.Text.secondary(11))
                    .foregroundStyle(onDark ? SR.creamOnDark : SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if let message {
                    Text(message)
                        .font(SR.Text.secondary(12))
                        .foregroundStyle(onDark ? SR.creamOnDark : SR.inkSecondary)
                }
            }
            .padding(.leading, large ? 0 : 60)
            .padding(.bottom, 6)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("trip-meal-choices-\(stop.mealName ?? "meal")")
        }
    }

    private func choose(_ option: MealOption) {
        guard let meal = stop.mealName else { return }
        busy = option.id
        message = nil
        let stage: DayStage = meal == "lunch" ? .lunch : .evening
        let idea = TripMealChoices.idea(option, meal: meal, stop: stop, date: day.date)
        Task {
            let failure: String?
            if can.canEdit || can.canApprove {
                failure = await store.add(idea, tripId: tripId, date: day.date, stage: stage)
            } else {
                failure = await store.suggest(idea.wish, tripId: tripId, date: day.date, stage: stage, note: idea.why, fitText: idea.fit)
            }
            busy = nil
            if let failure {
                SRHaptic.bad()
                message = failure
            } else {
                SRHaptic.ok()
                message = can.canEdit || can.canApprove ? nil : "Suggested — a parent will see it."
            }
        }
    }

    /// The option as an idea for the existing add/suggest paths: a wish that
    /// replaces that meal, already placed, for the meal's own length.
    nonisolated static func idea(_ option: MealOption, meal: String, stop: PlannedStop, date: String) -> TripIdea {
        TripIdea(
            title: option.name,
            why: option.why,
            fit: "\(meal.capitalized) \(TripWords.span(stop)) · \(Int(option.walkMin)) min walk from \(option.walkFrom)",
            wish: WishDraft(
                title: option.name, placeQuery: nil, priority: "must",
                durationMin: max(30, stop.departMin - stop.arriveMin), partOfDay: "any",
                fixedDate: date, fixedStartMin: nil, note: option.why,
                replacesMeal: meal, place: option.place
            ),
            verdict: nil,
            source: "nearby"
        )
    }
}

/// One place to eat: its photo when Commons has one, name, what and how
/// far, its hours that day (or that they are not on record), and buttons.
struct TripMealOptionCard: View {
    let option: MealOption
    let photo: PlaceImage?
    var large = false
    let actionLabel: String
    let busy: Bool
    var enabled = true
    let choose: () -> Void
    var show: (() -> Void)? = nil
    @Environment(\.tripOnDark) private var onDark

    private var ink: Color { onDark ? SR.cream : SR.ink }
    private var muted: Color { onDark ? SR.creamOnDark : SR.inkSecondary }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if large, let photo {
                TripPhotoView(photo: photo, height: 140)
            }
            HStack(alignment: .top, spacing: 10) {
                if !large, let photo {
                    TripPhotoThumb(photo: photo, size: 48)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(option.name)
                        .font(SR.Text.title(15))
                        .foregroundStyle(ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(option.line)
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let open = option.openText {
                        Label(open, systemImage: "clock")
                            .font(SR.Text.mono(12))
                            .foregroundStyle(onDark ? SR.cream : SR.good)
                    } else {
                        Label("Hours not on record — check before going", systemImage: "questionmark.circle")
                            .font(SR.Text.mono(12))
                            .foregroundStyle(onDark ? SR.cream : SR.warn)
                    }
                    let extras = (option.diet.map { $0.capitalized + " options" }
                                  + (option.outdoorSeating ? ["Outdoor seating"] : [])
                                  + (option.wheelchair == true ? ["Step-free"] : []))
                    if !extras.isEmpty {
                        Text(extras.joined(separator: " · "))
                            .font(SR.Text.secondary(12))
                            .foregroundStyle(muted)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Button(action: choose) {
                    if busy { ProgressView() } else { TripButtonLabel(actionLabel, icon: "checkmark", fill: true) }
                }
                .srButton(.prominent)
                .disabled(busy || !enabled)
                .accessibilityIdentifier("trip-meal-choose")
                if let show {
                    Button(action: show) { TripButtonLabel("Map", icon: "map") }
                        .srButton(.regular)
                }
                if let site = option.website.flatMap(TripLinkButtons.safeURL) {
                    Link(destination: site) { TripButtonLabel("Website", icon: "arrow.up.right.square") }
                        .srButton(.regular)
                }
            }
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((onDark ? Color.white : SR.ink).opacity(0.06), in: RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trip-meal-option")
    }
}
