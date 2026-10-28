import Foundation

// MARK: - The desk, live
//
// While a turn runs, the site streams the desk page as ops: `{"type":"panel",
// "op":{…}}` on the chat job's SSE stream. The web reduces them with
// SR-Jkai-Core's `$lib/jkai/panel/apply.ts`; this is that file, line for line,
// so the phone's drawer fills during the turn instead of only after a reload.
//
// Two pages, on purpose:
//
// - the REDUCED page, which holds every block the server sent, including ones
//   the phone will never draw (`artifact`, a button that posts, a type this
//   build has not met). They still count towards the caps (40 blocks a page,
//   24 a section, 12 sections) and still own their ids, so the next op lands
//   where it lands on the web.
// - the SHOWN page (`PanelReducer.shown`), which is SR-Main's `nativePanel`
//   keep() filter: what a reload of the same turn would have given the drawer.
//   A live page and a reloaded page must look the same.
//
// Receiver-tolerant, like the rest of the desk: an op this build cannot read is
// a no-op, never a throw. Foundation only, so the Linux harness
// (`scripts/chat-check.sh`) compiles and tests it.

/// One desk op from the stream. The shape is Core's `panelOpSchema`.
enum PanelOp: Decodable, Equatable {
    case head(PanelHead, producer: String?)
    case upsert(section: String, sectionLabel: String?, block: PanelBlock)
    case remove(id: String)
    case quiet
    case reset
    /// Not an op this build can use: an unknown kind, or a known kind missing
    /// what the schema requires (no section, a block without an id). The web
    /// drops these at `panelOpSchema.safeParse`; so does this.
    case ignored

    private enum Keys: String, CodingKey { case kind, head, producer, section, sectionLabel, block, id }
    private enum BlockKeys: String, CodingKey { case id }

    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: Keys.self) else { self = .ignored; return }
        func string(_ key: Keys) -> String? { (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil }

        switch string(.kind) {
        case "head":
            // The head must be an object; `PanelHead` itself never throws.
            guard (try? c.nestedContainer(keyedBy: BlockKeys.self, forKey: .head)) != nil,
                  let head = try? c.decode(PanelHead.self, forKey: .head) else { self = .ignored; return }
            self = .head(head, producer: string(.producer))
        case "upsert":
            guard let section = string(.section), !section.isEmpty,
                  let blockKeys = try? c.nestedContainer(keyedBy: BlockKeys.self, forKey: .block),
                  let id = (try? blockKeys.decodeIfPresent(String.self, forKey: .id)) ?? nil, !id.isEmpty,
                  let block = try? c.decode(PanelBlock.self, forKey: .block) else { self = .ignored; return }
            self = .upsert(section: section, sectionLabel: string(.sectionLabel), block: block)
        case "remove":
            guard let id = string(.id) else { self = .ignored; return }
            self = .remove(id: id)
        case "quiet":
            self = .quiet
        case "reset":
            self = .reset
        default:
            self = .ignored
        }
    }
}

/// The `panel` frame around an op.
struct PanelFrame: Decodable {
    let op: PanelOp

    private enum Keys: String, CodingKey { case op }

    init(from decoder: Decoder) throws {
        let c = try? decoder.container(keyedBy: Keys.self)
        op = (c.flatMap { try? $0.decodeIfPresent(PanelOp.self, forKey: .op) }) ?? .ignored
    }
}

/// `apply.ts`, for a phone. PURE: never mutates its input.
enum PanelReducer {
    /// Hard cap so a runaway turn cannot grow a page without bound (`MAX_BLOCKS_PER_PAGE`).
    static let maxBlocksPerPage = 40
    /// Core's panel schema allows at most this many blocks in one section
    /// (`MAX_BLOCKS_PER_SECTION`) and this many sections on one page
    /// (`MAX_SECTIONS_PER_PAGE`). The page cap alone let a page be built that
    /// the server's strict parse then refused, so a NEW block into a full
    /// section and a NEW section on a full page are dropped here as in
    /// `apply.ts`. Replacing a block that is already there still works.
    static let maxBlocksPerSection = 24
    static let maxSectionsPerPage = 12

    /// `DEFAULT_TURN_HEAD`: the page an op lands on when there is none yet.
    static let defaultHead = PanelHead(kicker: "This turn", context: [], title: "Working")

    static func apply(_ page: PanelPage?, _ op: PanelOp) -> PanelPage? {
        if case .ignored = op { return page }
        var base = page ?? PanelPage(version: 1, producer: "turn", head: defaultHead, sections: [], quiet: false)
        switch op {
        case .ignored:
            return page
        case .head(let head, let producer):
            base.head = head
            base.producer = producer ?? base.producer
            return base
        case .quiet:
            base.quiet = true
            return base
        case .reset:
            base.quiet = false
            base.sections = []
            return base
        case .remove(let id):
            return without(id, in: base)
        case .upsert(let sectionId, let sectionLabel, let block):
            let existing = base.sections.contains { $0.blocks.contains { $0.id == block.id } }
            if !existing && count(base) >= maxBlocksPerPage { return base }
            // Replace in place when the block already lives in the target
            // section, so a live update does not make it jump to the bottom.
            if let s = base.sections.firstIndex(where: { $0.id == sectionId }),
               let at = base.sections[s].blocks.firstIndex(where: { $0.id == block.id }) {
                base.sections[s].blocks[at] = block
                base.quiet = false
                return base
            }
            // New to this section: refused when the section, or the page's
            // run of sections, is already full. A block moving here from
            // another section is new to this one.
            if let s = base.sections.firstIndex(where: { $0.id == sectionId }) {
                if base.sections[s].blocks.count >= maxBlocksPerSection { return base }
            } else if base.sections.count >= maxSectionsPerPage {
                return base
            }
            var cleaned = existing ? without(block.id, in: base) : base
            if let s = cleaned.sections.firstIndex(where: { $0.id == sectionId }) {
                if let sectionLabel { cleaned.sections[s].label = sectionLabel }
                cleaned.sections[s].blocks.append(block)
            } else {
                cleaned.sections.append(PanelSection(id: sectionId, label: sectionLabel ?? "", blocks: [block]))
            }
            cleaned.quiet = false
            return cleaned
        }
    }

    static func apply(_ page: PanelPage?, _ ops: [PanelOp]) -> PanelPage? {
        ops.reduce(page) { apply($0, $1) }
    }

    /// What the drawer draws: SR-Main's `nativePanel` keep() filter over the
    /// reduced page. Blocks the phone cannot draw are already `.unknown` (an
    /// artifact, a type this build has not met, a buttons block left with no
    /// ask or link, a group left with nothing), so they go; a section left
    /// empty goes; a page left empty is nil — exactly what a reload returns.
    static func shown(_ page: PanelPage?) -> PanelPage? {
        guard var page else { return nil }
        page.sections = page.sections
            .map { section in
                var section = section
                section.blocks = section.blocks.filter { $0.kind != .unknown }
                return section
            }
            .filter { !$0.blocks.isEmpty }
        return page.sections.isEmpty ? nil : page
    }

    /// `done.result.panel`: the finished page, authoritative over the live one
    /// (`finalDeskPage` on the web). An object is the page; `null` means the
    /// turn ended with none; absent means keep what was streamed.
    enum Final: Equatable {
        case keep
        case none
        case page(PanelPage)
    }

    static func final(fromResult result: [String: Any]) -> Final {
        guard result.keys.contains("panel") else { return .keep }
        let raw = result["panel"]
        if raw == nil || raw is NSNull { return .none }
        guard let object = raw as? [String: Any], JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let page = try? JSONDecoder().decode(PanelPage.self, from: data) else { return .keep }
        return .page(page)
    }

    private static func count(_ page: PanelPage) -> Int {
        page.sections.reduce(0) { $0 + $1.blocks.count }
    }

    /// `withoutBlock`: the block goes; its section stays, even if empty.
    private static func without(_ id: String, in page: PanelPage) -> PanelPage {
        var page = page
        for s in page.sections.indices { page.sections[s].blocks.removeAll { $0.id == id } }
        return page
    }
}
