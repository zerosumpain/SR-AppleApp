import XCTest
@testable import SRAppleApp

/// The Flows tab: the wire contract decoded defensively, schedules mapped to
/// presets and back, and a graph laid out as a column with its branches.
final class FlowsTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    // MARK: - Contract decoding

    func testTheListDecodesAndKeepsOrder() throws {
        let list = try decode(FlowList.self, """
        {"workflows": [
          {"slug": "a", "title": "A", "description": null,
           "trigger": {"kind": "cron", "cron": "0 7 * * 1-5", "timezone": "Europe/London", "enabled": true,
                       "description": "Weekdays at 07:00", "nextRuns": ["2026-09-26T06:00:00.000Z"]},
           "nodeCount": 4,
           "lastRun": {"id": "r1", "status": "failed", "trigger": "schedule", "startedAt": "2026-09-25T06:00:00.000Z",
                       "completedAt": null, "durationMs": null, "error": "boom"},
           "needsAttention": true, "attentionReason": "Failed three times", "updatedAt": "2026-09-25T06:00:00.000Z"},
          {"slug": "b", "title": "B", "trigger": {"kind": "manual", "enabled": true, "description": "When you start it"},
           "nodeCount": 2, "lastRun": null, "needsAttention": false, "attentionReason": null, "updatedAt": "2026-09-24T06:00:00.000Z"}
        ]}
        """)
        XCTAssertEqual(list.workflows.map(\.slug), ["a", "b"])
        XCTAssertEqual(list.workflows[0].trigger.kind, .cron)
        XCTAssertEqual(list.workflows[0].trigger.nextRuns.count, 1)
        XCTAssertEqual(list.workflows[0].lastRun?.state, .failed)
        XCTAssertTrue(list.workflows[0].needsAttention)
        XCTAssertEqual(list.workflows[1].trigger.nextRuns, [])
    }

    func testAnUnknownTriggerKindIsOtherNotAFailure() throws {
        let trigger = try decode(FlowTrigger.self, #"{"kind": "telepathy", "enabled": false, "description": "When I think of it"}"#)
        XCTAssertEqual(trigger.kind, .other("telepathy"))
        XCTAssertFalse(trigger.enabled)
        XCTAssertNil(trigger.cron)
    }

    func testAnUnknownFieldKindFallsBackToJSON() throws {
        let field = try decode(FlowField.self, #"{"key": "x", "label": "X", "kind": "hologram", "advanced": true}"#)
        XCTAssertEqual(field.kind, .json)
        XCTAssertTrue(field.advanced)
        let bare = try decode(FlowField.self, #"{"key": "y"}"#)
        XCTAssertEqual(bare.kind, .json)
        XCTAssertEqual(bare.label, "y")
        XCTAssertFalse(bare.advanced)
    }

    func testOptionsAcceptObjectsAndBareStrings() throws {
        let field = try decode(FlowField.self, """
        {"key": "m", "label": "Model", "kind": "dropdown",
         "options": [{"value": "auto", "label": "Default"}, "fast", {"value": 3, "label": "Three"}]}
        """)
        XCTAssertEqual(field.options.map(\.label), ["Default", "fast", "Three"])
        XCTAssertEqual(field.options[2].value, .number(3))
    }

    func testOneBrokenWorkflowDoesNotEmptyTheList() throws {
        let list = try decode(FlowList.self, """
        {"workflows": [{"title": "no slug"}, {"slug": "ok", "title": "OK"}]}
        """)
        XCTAssertEqual(list.workflows.map(\.slug), ["ok"])
        XCTAssertEqual(list.workflows[0].trigger.kind, .manual)
    }

    func testTheDetailDecodesWithNumericIdsAndMissingArrays() throws {
        let detail = try decode(FlowDetail.self, """
        {"slug": "a", "title": "A", "version": 3,
         "trigger": {"kind": "webhook", "enabled": true, "description": "On call"},
         "building": false,
         "steps": [{"id": 1, "type": "t", "label": "Start", "category": "trigger", "config": {"n": 1, "s": "x", "o": {"k": [true, null]}},
                    "form": [{"key": "n", "label": "N", "kind": "number"}], "next": [{"handle": "", "targetId": 2}]},
                   {"id": 2, "type": "u", "label": "Next"}],
         "edges": [{"id": 9, "source": 1, "target": 2, "sourceHandle": null}]}
        """)
        XCTAssertEqual(detail.version, 3)
        XCTAssertEqual(detail.steps.map(\.id), ["1", "2"])
        XCTAssertNil(detail.steps[0].next[0].handle, "an empty handle is no handle")
        XCTAssertEqual(detail.steps[0].next[0].targetId, "2")
        XCTAssertEqual(detail.steps[0].config["o"]?["k"]?.array, [.bool(true), .null])
        XCTAssertEqual(detail.edges[0].id, "9")
        XCTAssertEqual(detail.recentRuns.count, 0)
        XCTAssertEqual(detail.fixProposals.count, 0)
        XCTAssertEqual(detail.steps[1].form.count, 0)
    }

    func testRunDetailProposalAndCatalogueDecode() throws {
        let run = try decode(FlowRunDetail.self, """
        {"run": {"id": 42, "status": "running", "trigger": "manual", "startedAt": "2026-09-25T06:00:00Z"},
         "steps": [{"nodeId": "a", "label": "A", "type": "llm", "status": "completed", "startedAt": null,
                    "durationMs": 1200, "error": null, "output": "{}", "rows": 3}]}
        """)
        XCTAssertEqual(run.run.id, "42")
        XCTAssertEqual(run.run.state, .running)
        XCTAssertEqual(run.steps[0].rows, 3)

        let proposal = try decode(FlowProposal.self, """
        {"summary": "Do it", "ops": [{"op": "remove_node", "nodeId": "a", "future": {"x": 1}}], "warnings": ["careful"]}
        """)
        XCTAssertEqual(proposal.ops.count, 1)
        // Sent back verbatim: a field the phone does not know survives.
        XCTAssertEqual(proposal.ops[0]["future"]?["x"], .number(1))

        let catalogue = try decode(FlowCatalogue.self, """
        {"categories": [{"id": "ai", "label": "AI", "types": [{"type": "llm", "label": "Ask", "description": "d",
          "icon": null, "defaultConfig": {"prompt": ""}, "form": [{"key": "prompt", "kind": "template"}]}]}]}
        """)
        XCTAssertEqual(catalogue.categories[0].types[0].form[0].kind, .template)
    }

    func testTheDemoFixturesDecodeAgainstTheRealModels() throws {
        let base = "https://strangeramblings.com/"
        func get(_ path: String) -> Data {
            SRDemoFixtures.reply(method: "GET", url: URL(string: base + path)!, body: nil).body
        }
        let list = try JSONDecoder().decode(FlowList.self, from: get("api/native/workflows"))
        XCTAssertEqual(list.workflows.count, 5)
        XCTAssertTrue(list.workflows.contains(where: \.needsAttention))
        let detail = try JSONDecoder().decode(FlowDetail.self, from: get("api/native/workflows/morning-brief"))
        XCTAssertEqual(detail.steps.count, 7)
        XCTAssertTrue(FlowLayout.rows(for: detail.steps).contains { if case .branch = $0.kind { return true }; return false })
        let triage = try JSONDecoder().decode(FlowDetail.self, from: get("api/native/workflows/inbox-triage"))
        XCTAssertEqual(triage.fixProposals.count, 1)
        let run = try JSONDecoder().decode(FlowRunDetail.self, from: get("api/native/workflows/runs/demo-run-brief-1"))
        XCTAssertFalse(run.steps.isEmpty)
        let catalogue = try JSONDecoder().decode(FlowCatalogue.self, from: get("api/native/workflows/node-types"))
        XCTAssertFalse(catalogue.categories.isEmpty)
    }

    // MARK: - Schedules

    func testPresetsRoundTripThroughCron() {
        let cases: [(String, CronPreset)] = [
            ("15 * * * *", .hourly(minute: 15)),
            ("30 7 * * *", .daily(hour: 7, minute: 30)),
            ("0 9 * * 1-5", .weekdays(hour: 9, minute: 0)),
            ("0 18 * * 0", .weekly(weekday: 0, hour: 18, minute: 0)),
            ("45 6 * * 3", .weekly(weekday: 3, hour: 6, minute: 45)),
        ]
        for (expression, preset) in cases {
            XCTAssertEqual(CronPreset.parse(expression), preset, expression)
            XCTAssertEqual(preset.expression, expression)
        }
    }

    func testAnythingElseIsCustomAndKeptVerbatim() {
        for raw in ["*/5 * * * *", "0 9 1 * *", "0 9 * * 1,3", "0 9-17 * * *", "0 9 * 6 *", "nonsense"] {
            XCTAssertEqual(CronPreset.parse(raw).kind, .custom, raw)
        }
        XCTAssertEqual(CronPreset.parse("*/5 * * * *").expression, "*/5 * * * *")
    }

    func testSundayIsZeroEvenWhenWrittenAsSeven() {
        XCTAssertEqual(CronPreset.parse("0 8 * * 7"), .weekly(weekday: 0, hour: 8, minute: 0))
    }

    func testSwitchingPresetKeepsTheTime() {
        let daily = CronPreset.daily(hour: 6, minute: 40)
        XCTAssertEqual(daily.converted(to: .weekdays), .weekdays(hour: 6, minute: 40))
        XCTAssertEqual(daily.converted(to: .weekly).expression, "40 6 * * 1")
        XCTAssertEqual(daily.converted(to: .hourly), .hourly(minute: 40))
        XCTAssertEqual(daily.converted(to: .custom), .custom("40 6 * * *"))
    }

    func testCronSanityCheck() {
        XCTAssertTrue(CronPreset.looksValid("*/5 9-17 * * MON-FRI"))
        XCTAssertFalse(CronPreset.looksValid("0 9 * *"))
        XCTAssertFalse(CronPreset.looksValid("0 9 * * 1; rm"))
    }

    // MARK: - Layout

    private func step(_ id: String, _ next: [(String?, String)] = []) -> FlowStep {
        FlowStep(id: id, type: "t", label: id.uppercased(), next: next.map { FlowNext(handle: $0.0, targetId: $0.1) })
    }

    private func describe(_ rows: [FlowLayoutRow]) -> [String] {
        rows.map { row in
            let pad = String(repeating: ".", count: row.depth)
            switch row.kind {
            case .step(let id): return pad + id
            case .branch(let label): return pad + "[" + label + "]"
            case .passthrough: return pad + "~"
            }
        }
    }

    func testALineIsAColumn() {
        let steps = [step("t", [(nil, "a")]), step("a", [(nil, "b")]), step("b")]
        XCTAssertEqual(describe(FlowLayout.rows(for: steps)), ["t", "a", "b"])
    }

    func testABranchThatMeetsAgainIndentsItsArmsAndDrawsTheMergeOnce() {
        let steps = [
            step("t", [(nil, "check")]),
            step("check", [("true", "yes"), ("false", "no")]),
            step("yes", [(nil, "send")]),
            step("no", [(nil, "send")]),
            step("send"),
        ]
        XCTAssertEqual(
            describe(FlowLayout.rows(for: steps)),
            ["t", "check", ".[true]", ".yes", ".[false]", ".no", "send"]
        )
    }

    func testAnArmStraightToTheMergeSaysSo() {
        let steps = [
            step("check", [("true", "extra"), ("false", "end")]),
            step("extra", [(nil, "end")]),
            step("end"),
        ]
        XCTAssertEqual(
            describe(FlowLayout.rows(for: steps)),
            ["check", ".[true]", ".extra", ".[false]", ".~", "end"]
        )
    }

    func testArmsThatNeverMeetStayIndented() {
        let steps = [
            step("approve", [("approved", "ship"), ("rejected", "tell")]),
            step("ship", [(nil, "log")]),
            step("log"),
            step("tell"),
        ]
        XCTAssertEqual(
            describe(FlowLayout.rows(for: steps)),
            ["approve", ".[approved]", ".ship", ".log", ".[rejected]", ".tell"]
        )
    }

    func testNestedBranchesAndStrayStepsAreAllListed() {
        let steps = [
            step("t", [(nil, "a")]),
            step("a", [("x", "b"), ("y", "c")]),
            step("b", [("p", "d"), ("q", "e")]),
            step("c"),
            step("d"),
            step("e"),
            step("orphan"),
        ]
        let rows = describe(FlowLayout.rows(for: steps))
        XCTAssertEqual(rows, ["t", "a", ".[x]", ".b", "..[p]", "..d", "..[q]", "..e", ".[y]", ".c", "orphan"])
        XCTAssertEqual(Set(FlowLayout.rows(for: steps).compactMap { if case .step(let id) = $0.kind { return id }; return nil }).count, 7)
    }

    func testACycleTerminates() {
        let steps = [step("a", [(nil, "b")]), step("b", [(nil, "a")])]
        XCTAssertEqual(describe(FlowLayout.rows(for: steps)), ["a", "b"])
    }

    func testUpstreamIsEveryAncestor() {
        let steps = [
            step("t", [(nil, "a")]),
            step("a", [("x", "b"), ("y", "c")]),
            step("b", [(nil, "d")]),
            step("c", [(nil, "d")]),
            step("d"),
        ]
        XCTAssertEqual(Set(FlowLayout.upstream(of: "d", in: steps).map(\.id)), ["t", "a", "b", "c"])
        XCTAssertEqual(FlowLayout.upstream(of: "t", in: steps).map(\.id), [])
    }

    // MARK: - Ops

    func testAddAfterSplicesWhenThereIsASuccessorAndWiresWhenThereIsNot() {
        let middle = step("a", [("false", "z"), (nil, "b")])
        let spliced = FlowOps.insertStep(after: middle, type: "llm", label: "Ask", config: [:])
        XCTAssertEqual(spliced.count, 1)
        XCTAssertEqual(spliced[0]["op"], .string("insert_between"))
        XCTAssertEqual(spliced[0]["targetNodeId"], .string("b"), "the unlabelled successor, not a branch arm")

        let end = step("b")
        let wired = FlowOps.insertStep(after: end, type: "llm", label: "Ask", config: ["prompt": .string("")])
        XCTAssertEqual(wired.map { $0["op"]?.string }, ["add_node", "add_edge"])
        XCTAssertEqual(wired[1]["targetNodeId"], .string("#" + (wired[0]["ref"]?.string ?? "")))
        XCTAssertEqual(wired[1]["sourceNodeId"], .string("b"))
    }

    func testAnEditIsSentAsAPatch() {
        let original: [String: JSONValue] = ["a": .number(1), "b": .string("x"), "c": .bool(true)]
        let edited: [String: JSONValue] = ["a": .number(2), "b": .string("x"), "d": .null]
        let (patch, removed) = FlowOps.diff(from: original, to: edited)
        XCTAssertEqual(patch, ["a": .number(2), "d": .null])
        XCTAssertEqual(removed, ["c"])
        let op = FlowOps.updateNode("n", config: patch, removeKeys: removed, label: nil)
        XCTAssertEqual(op["removeConfigKeys"], .array([.string("c")]))
        XCTAssertNil(op["label"])
    }

    func testOpsReadAsPlainWords() {
        let steps = [step("a"), step("b")]
        XCTAssertEqual(FlowOps.describe(FlowOps.removeNode("a"), steps: steps), "Delete “A”")
        let splice = FlowOps.insertStep(after: step("a", [(nil, "b")]), type: "delay", label: "Wait", config: [:])[0]
        XCTAssertEqual(FlowOps.describe(splice, steps: steps), "Insert a delay step “Wait” between “A” and “B”")
        XCTAssertTrue(FlowOps.describe(.object(["op": .string("teleport")]), steps: steps).contains("teleport"))
    }

    func testJSONValueRoundTripsThroughPrettyText() {
        let value: JSONValue = .object(["n": .number(1.5), "a": .array([.string("x"), .null, .bool(false)])])
        XCTAssertEqual(JSONValue.parse(value.pretty), value)
        XCTAssertNil(JSONValue.parse("{not json"))
        XCTAssertEqual(JSONValue.number(3).display, "3")
    }

    func testDurations() {
        XCTAssertEqual(flowDuration(420), "420ms")
        XCTAssertEqual(flowDuration(14_820), "14.8s")
        XCTAssertEqual(flowDuration(184_000), "3m 04s")
        XCTAssertNil(flowDuration(nil))
    }
}
