#if DEBUG
import SwiftUI

// MARK: - Demo family boards
//
// `-SRDemo` answers for `/api/native/family/steps` and `/api/native/family/tasks`.
// Synthetic throughout — the repository is public. John is the caller and a
// parent; Sam leads the step board with John second (the demo's own Apple
// Health figure, 9,120, is laid over John's 8,412, so the "live" row shows);
// Pat is on the board with no steps yet. The task list has something in every
// state: to do (one overdue, one sent back), two done and waiting for John,
// three confirmed — one paid — and £12 plus a day out owed.

extension SRDemoFixtures {
    static func familyRoute(method: String, parts: [String], body: Data?, clock: DemoClock) -> String? {
        // parts: ["api", "native", "family", ...]
        let rest = Array(parts.dropFirst(3))
        switch (method, rest.count, rest.first ?? "") {
        case ("GET", 1, "steps"):
            return familySteps(clock)
        case ("GET", 1, "tasks"):
            return familyTasks(clock)
        case ("POST", 1, "tasks"):
            let fields = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let title = (fields?["title"] as? String) ?? "New task"
            return "{\"task\": \(taskJSON(id: "t_new", title: title, createdBy: "f_john", created: clock.iso(minutesAgo: 0)))}"
        case ("PATCH", 2, "tasks"):
            return "{\"task\": \(taskJSON(id: rest[1], title: "Updated", createdBy: "f_john", created: clock.iso(minutesAgo: 0)))}"
        default:
            return nil
        }
    }

    static func familySteps(_ clock: DemoClock) -> String {
        let day = FamilySteps.ymd(clock.now)
        let updated = clock.iso(minutesAgo: 7)
        return """
        {"day":"\(day)","updatedAt":"\(updated)","people":[
          {"id":"f_sam","name":"Sam","steps":11204,"rank":1,"me":false,"updatedAt":"\(updated)"},
          {"id":"f_john","name":"John","steps":8412,"rank":2,"me":true,"updatedAt":"\(updated)"},
          {"id":"f_robin","name":"Robin","steps":6530,"rank":3,"me":false,"updatedAt":"\(updated)"},
          {"id":"f_kit","name":"Kit","steps":3020,"rank":4,"me":false,"updatedAt":"\(clock.iso(minutesAgo: 40))"},
          {"id":"f_pat","name":"Pat","steps":0,"rank":5,"me":false,"updatedAt":null}
        ],"yesterday":{"leaderName":"Robin","steps":14210}}
        """
    }

    static func taskJSON(
        id: String, title: String, notes: String? = nil, deadline: String? = nil, assignee: String? = nil,
        createdBy: String, status: String = "open", doneBy: String? = nil, doneAt: String? = nil,
        sentBackNote: String? = nil, confirmedBy: String? = nil, confirmedAt: String? = nil,
        reward: (kind: String, pence: Int?, note: String?, paidAt: String?)? = nil, created: String
    ) -> String {
        var rewardJSON = "null"
        if let reward {
            let pence: Double? = reward.pence.map { Double($0) }
            rewardJSON = "{\"kind\":\(s(reward.kind)),\"pence\":\(n(pence)),\"note\":\(s(reward.note)),\"paidAt\":\(s(reward.paidAt))}"
        }
        return """
        {"id":\(s(id)),"title":\(s(title)),"notes":\(s(notes)),"deadline":\(s(deadline)),"assignee":\(s(assignee)),\
        "createdBy":\(s(createdBy)),"status":\(s(status)),"doneBy":\(s(doneBy)),"doneAt":\(s(doneAt)),\
        "sentBackNote":\(s(sentBackNote)),"confirmedBy":\(s(confirmedBy)),"confirmedAt":\(s(confirmedAt)),\
        "reward":\(rewardJSON),"createdAt":\(s(created))}
        """
    }

    static func familyTasks(_ clock: DemoClock) -> String {
        let day = { (offset: Int) in FamilyTaskRules.ymd(clock.now.addingTimeInterval(Double(offset) * 86_400)) }
        let ago = { (minutes: Double) in clock.iso(minutesAgo: minutes) }

        let bins = taskJSON(id: "t_bins", title: "Bins out for collection", deadline: day(-1),
                            createdBy: "f_john", created: ago(3_000))
        let dishes = taskJSON(id: "t_dishes", title: "Empty the dishwasher", deadline: day(0), assignee: "f_sam",
                              createdBy: "f_john", reward: ("cash", 200, nil, nil), created: ago(600))
        let bedroom = taskJSON(id: "t_bedroom", title: "Tidy the bedroom", notes: "Clothes away, bed made, floor clear.",
                               deadline: day(1), assignee: "f_robin", createdBy: "f_john",
                               reward: ("game_time", nil, "An hour on Saturday", nil), created: ago(900))
        let car = taskJSON(id: "t_car", title: "Wash the car", assignee: "f_kit", createdBy: "f_john",
                           sentBackNote: "The wheels still need doing.", reward: ("cash", 500, nil, nil), created: ago(2_000))
        let reading = taskJSON(id: "t_reading", title: "Reading log signed", deadline: day(2), assignee: "f_sam",
                               createdBy: "f_sam", status: "done", doneBy: "f_sam", doneAt: ago(35),
                               reward: ("lunch_out", nil, "Pizza on Friday", nil), created: ago(1_500))
        let lawn = taskJSON(id: "t_lawn", title: "Mow the lawn", assignee: "f_robin", createdBy: "f_john",
                            status: "done", doneBy: "f_robin", doneAt: ago(80), reward: ("cash", 300, nil, nil), created: ago(4_000))

        let hoover = taskJSON(id: "t_hoover", title: "Hoover the stairs", assignee: "f_sam", createdBy: "f_john",
                              status: "confirmed", doneBy: "f_sam", doneAt: ago(1_600), confirmedBy: "f_john",
                              confirmedAt: ago(1_500), reward: ("cash", 200, nil, nil), created: ago(5_000))
        let shop = taskJSON(id: "t_shop", title: "Help with the big shop", createdBy: "f_john",
                            status: "confirmed", doneBy: "f_robin", doneAt: ago(2_900), confirmedBy: "f_john",
                            confirmedAt: ago(2_880), reward: ("day_out", nil, "The zoo", nil), created: ago(6_000))
        let garage = taskJSON(id: "t_garage", title: "Clear the garage", assignee: "f_kit", createdBy: "f_john",
                              status: "confirmed", doneBy: "f_kit", doneAt: ago(4_400), confirmedBy: "f_john",
                              confirmedAt: ago(4_300), reward: ("cash", 1_000, nil, nil), created: ago(9_000))
        let plants = taskJSON(id: "t_plants", title: "Water the plants", assignee: "f_kit", createdBy: "f_john",
                              status: "confirmed", doneBy: "f_kit", doneAt: ago(8_000), confirmedBy: "f_john",
                              confirmedAt: ago(7_900), reward: ("cash", 200, nil, ago(7_000)), created: ago(10_000))

        return """
        {"me":{"id":"f_john","parent":true},
         "people":[{"id":"f_john","name":"John"},{"id":"f_sam","name":"Sam"},{"id":"f_robin","name":"Robin"},{"id":"f_kit","name":"Kit"}],
         "open":[\([bins, dishes, bedroom, reading, car, lawn].joined(separator: ","))],
         "completed":[\([hoover, shop, garage, plants].joined(separator: ","))],
         "owed":{"totalPence":1200,"items":[\([garage, hoover, shop].joined(separator: ","))]}}
        """
    }
}

/// The family widgets as a Home Screen would draw them, at their real sizes.
/// Demo only — reached from Settings → Today → Widget previews.
struct FamilyWidgetGallery: View {
    @ObservedObject private var steps = FamilyStepsStore.shared
    @ObservedObject private var tasks = FamilyTasksStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SRSectionLabel(text: "Steps")
                HStack(alignment: .top, spacing: 16) {
                    tile(FamilyStepsWidgetView(board: steps.board ?? FamilyWidgetSamples.steps, size: .small), width: 158)
                    tile(FamilyStepsWidgetView(board: steps.board ?? FamilyWidgetSamples.steps, size: .rectangular), width: 158, height: 72, lock: true)
                }
                tile(FamilyStepsWidgetView(board: steps.board ?? FamilyWidgetSamples.steps, size: .medium), width: 338)

                SRSectionLabel(text: "Tasks")
                HStack(alignment: .top, spacing: 16) {
                    tile(FamilyTasksWidgetView(summary: tasks.summary ?? FamilyWidgetSamples.tasks, size: .small), width: 158)
                    tile(FamilyTasksWidgetView(summary: tasks.summary ?? FamilyWidgetSamples.tasks, size: .rectangular), width: 158, height: 72, lock: true)
                }
                tile(FamilyTasksWidgetView(summary: tasks.summary ?? FamilyWidgetSamples.tasks, size: .medium), width: 338)
            }
            .padding(SR.gutter)
        }
        .background(Color(red: 0.36, green: 0.42, blue: 0.5).ignoresSafeArea())
        .accessibilityIdentifier("widget-gallery")
        .navigationTitle("Widget previews")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await steps.load()
            await tasks.load()
        }
    }

    /// A widget-sized, widget-shaped frame. `lock` draws a Lock Screen slot:
    /// no paper, light text on the wallpaper.
    private func tile<V: View>(_ view: V, width: CGFloat, height: CGFloat = 158, lock: Bool = false) -> some View {
        view
            .padding(lock ? 6 : 16)
            .frame(width: width, height: height, alignment: .topLeading)
            .foregroundStyle(lock ? Color.white : FamilyWidgetInk.ink)
            .environment(\.colorScheme, lock ? .dark : .light)
            .background(
                RoundedRectangle(cornerRadius: lock ? 12 : 22, style: .continuous)
                    .fill(lock ? Color.white.opacity(0.12) : FamilyWidgetInk.paper)
            )
    }
}
#endif
