import XCTest
@testable import SRAppleApp

/// Real server output, not the contract as written.
///
/// Every file under `Fixtures/Workflows/probe-*.json` was captured from SR-Main
/// master (#942 + #943) running against the dev database, 2026-09-25, through
/// the same device-token lane the phone uses. Scrubbed for a public repo:
/// phone numbers, coordinates, the surname, the home town and every run step's
/// output were replaced; the SHAPES are untouched, and the shapes are the point.
/// `probe-event-triggers.json` is the server's own `triggerDTO()` run on real
/// catalogue types, because the dev database had no event-triggered canvas.
///
/// If one of these fails after a site change, re-capture rather than edit.
final class FlowsProbeTests: XCTestCase {

    private func load(_ name: String) throws -> Data {
        // In the app's test bundle (xcodegen copies the JSON as resources);
        // beside this file when run from a plain SwiftPM checkout.
        if let url = Bundle(for: FlowsProbeTests.self).url(forResource: name, withExtension: "json") {
            return try Data(contentsOf: url)
        }
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        return try Data(contentsOf: here.appendingPathComponent("Fixtures/Workflows/\(name).json"))
    }

    private func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try JSONDecoder().decode(T.self, from: try load(name))
    }

    func testTheRealListDecodesEveryWorkflow() throws {
        let raw = try JSONSerialization.jsonObject(with: try load("probe-list")) as? [String: Any]
        let count = (raw?["workflows"] as? [Any])?.count ?? -1
        let list = try decode(FlowList.self, "probe-list")
        XCTAssertEqual(list.workflows.count, count, "a lossy decode must not have dropped a real row")
        XCTAssertGreaterThan(count, 0)
        XCTAssertTrue(list.workflows.contains { $0.trigger.kind == .cron })
        XCTAssertTrue(list.workflows.contains { $0.trigger.kind == .chat })
        XCTAssertFalse(list.workflows.contains { if case .other = $0.trigger.kind { return true }; return false })
        // The real server says "completed_with_errors"; it must not read as "other".
        let statuses = list.workflows.compactMap { $0.lastRun?.state }
        XCTAssertFalse(statuses.contains(.other))
    }

    func testRealDetailsDecodeAndLayOutEveryStep() throws {
        for name in ["probe-detail-morning-briefing", "probe-detail-run-forrest-alert",
                     "probe-detail-indoor-outdoor-temp", "probe-detail-test-slug"] {
            let raw = try JSONSerialization.jsonObject(with: try load(name)) as? [String: Any]
            let rawSteps = (raw?["steps"] as? [[String: Any]]) ?? []
            let detail = try decode(FlowDetail.self, name)
            XCTAssertEqual(detail.steps.count, rawSteps.count, "\(name): a step was dropped")
            XCTAssertNotNil(detail.version, name)
            // Every form field decodes, with no kind the phone does not know
            // silently degrading a real field to raw JSON.
            let rawFields = rawSteps.reduce(0) { $0 + (($1["form"] as? [Any])?.count ?? 0) }
            XCTAssertEqual(detail.steps.reduce(0) { $0 + $1.form.count }, rawFields, "\(name): a field was dropped")
            let rawKinds = Set(rawSteps.flatMap { ($0["form"] as? [[String: Any]] ?? []).compactMap { $0["kind"] as? String } })
            XCTAssertTrue(rawKinds.isSubset(of: Set(FlowFieldKind.allCases.map(\.rawValue))), "\(name): new kinds \(rawKinds)")
            // Every step is drawn exactly once.
            let drawn = FlowLayout.rows(for: detail.steps).compactMap { row -> String? in
                if case .step(let id) = row.kind { return id }
                return nil
            }
            XCTAssertEqual(drawn.count, detail.steps.count, name)
            XCTAssertEqual(Set(drawn), Set(detail.steps.map(\.id)), name)
        }
    }

    func testARealConditionalIsDrawnAsLabelledArms() throws {
        let detail = try decode(FlowDetail.self, "probe-detail-run-forrest-alert")
        let rows = FlowLayout.rows(for: detail.steps)
        let arms = rows.compactMap { row -> String? in
            if case .branch(let label) = row.kind { return label }
            return nil
        }
        // The speed check wires ONLY its "true" arm: the alert must read as
        // conditional, indented under "TRUE", not as the next line.
        XCTAssertEqual(arms, ["true"])
        let alert = rows.first { if case .step(let id) = $0.kind { return id.hasPrefix("whatsapp") }; return false }
        XCTAssertEqual(alert?.depth, 1)
    }

    func testTheRealBriefingKeepsItsScheduleAndRuns() throws {
        let detail = try decode(FlowDetail.self, "probe-detail-morning-briefing")
        XCTAssertEqual(detail.trigger.kind, .cron)
        XCTAssertNotNil(detail.trigger.cron)
        XCTAssertNotEqual(CronPreset.parse(detail.trigger.cron ?? "").kind, .custom, "07:00 daily is a preset")
        XCTAssertFalse(detail.recentRuns.isEmpty)
        XCTAssertEqual(detail.recentRuns.first?.state, .partial)
    }

    func testRealRunsRunDetailFixesAndAskDecode() throws {
        let runs = try decode(FlowRunList.self, "probe-runs")
        XCTAssertFalse(runs.runs.isEmpty)
        let run = try decode(FlowRunDetail.self, "probe-run-detail")
        XCTAssertEqual(run.run.state, .partial)
        XCTAssertEqual(flowStatusLabel(run.run.status), "Completed with errors")
        XCTAssertTrue(run.steps.contains { $0.state == .failed && $0.error != nil })
        XCTAssertTrue(run.steps.allSatisfy { $0.state != .other }, "every real step status is understood")

        struct Proposals: Decodable { let proposals: [FlowFixProposal] }
        XCTAssertNotNil(try decode(Proposals.self, "probe-fix-proposals"))

        let ask = try decode(FlowProposal.self, "probe-ask")
        XCTAssertEqual(ask.ops.count, 1)
        XCTAssertEqual(ask.ops[0]["op"], .string("update_node"))
        let detail = try decode(FlowDetail.self, "probe-detail-run-forrest-alert")
        XCTAssertTrue(FlowOps.describe(ask.ops[0], steps: detail.steps).hasPrefix("Edit “"),
                      "the proposal names a real step")
    }

    func testTheRealCatalogueDecodesWholeWithNoUnknownKinds() throws {
        let raw = try JSONSerialization.jsonObject(with: try load("probe-node-types")) as? [String: Any]
        let rawCategories = (raw?["categories"] as? [[String: Any]]) ?? []
        let rawTypes = rawCategories.reduce(0) { $0 + (($1["types"] as? [Any])?.count ?? 0) }
        let catalogue = try decode(FlowCatalogue.self, "probe-node-types")
        XCTAssertEqual(catalogue.categories.count, rawCategories.count)
        XCTAssertEqual(catalogue.categories.reduce(0) { $0 + $1.types.count }, rawTypes)
    }

    func testRealEventTypesAndEventTriggersDecodeAndReadAsWhen() throws {
        let types = try decode(FlowEventTypes.self, "probe-event-types")
        XCTAssertFalse(types.eventTypes.isEmpty)
        let completed = types.eventTypes.first { $0.type == "workflow.completed" }
        XCTAssertEqual(completed?.filterKeys.contains("status"), true)

        let triggers = try decode([FlowTrigger].self, "probe-event-triggers")
        XCTAssertEqual(triggers.map(\.kind), [.event, .event, .event])
        let first = triggers[0]
        XCTAssertEqual(first.eventType, "workflow.completed")
        XCTAssertEqual(first.filter.map(\.key), ["status", "workflowId"])
        XCTAssertFalse(first.isEditableOnPhone)
        XCTAssertEqual(first.headline(eventLabel: completed?.label), "When a workflow finished")
        // Without the catalogue, the server's own sentence still yields the label.
        XCTAssertEqual(first.headline(), "When a workflow finished")
        XCTAssertEqual(first.filter[0].sentence, "status is “failed”")
        XCTAssertEqual(first.filter[1].sentence, "workflowId contains “nightly”")
        XCTAssertFalse(triggers[1].enabled)
        XCTAssertNil(triggers[2].eventType)
        XCTAssertEqual(triggers[2].headline(), "Runs on an event")
    }

    func testARealFanOutReadsAsParallelArms() throws {
        let detail = try decode(FlowDetail.self, "probe-detail-indoor-outdoor-temp")
        let rows = FlowLayout.rows(for: detail.steps)
        let arms = rows.compactMap { row -> String? in
            if case .branch(let label) = row.kind { return label }
            return nil
        }
        XCTAssertEqual(arms.filter { $0 == "in parallel" }.count, 2, "the hourly trigger fetches outdoor and indoor at once")
        XCTAssertTrue(arms.contains("true"))
        // The merge after the two fetches is drawn once, back at the outer depth.
        let merge = rows.first { if case .step(let id) = $0.kind { return id.hasPrefix("merge") }; return false }
        XCTAssertEqual(merge?.depth, 0)
    }

    func testAProperNounLabelKeepsItsCapital() {
        XCTAssertEqual(FlowTrigger.lowerFirst("Whoop recovery synced"), "Whoop recovery synced")
        XCTAssertEqual(FlowTrigger.lowerFirst("WhatsApp message from you"), "WhatsApp message from you")
        XCTAssertEqual(FlowTrigger.lowerFirst("Email arrived on a watch"), "email arrived on a watch")
    }
}
