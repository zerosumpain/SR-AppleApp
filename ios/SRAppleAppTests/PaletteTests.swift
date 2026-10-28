import XCTest
import SwiftUI
@testable import SRAppleApp

/// The reader's palettes: every preset holds the floors Prism was measured
/// to, whatever the reader re-picks stays readable, and the choice survives
/// the round trip through storage.
///
/// Pure arithmetic on hex values, so it measures the palette as designed —
/// not whichever one this simulator's last run happened to leave chosen.
final class PaletteTests: XCTestCase {

    private func ratio(_ a: UInt32, _ b: UInt32) -> Double { SRRGB.contrast(a, b) }

    private func label(_ palette: SRPalette, _ what: String, _ value: Double) -> String {
        "\(palette.name): \(what) measures \(String(format: "%.2f", value)):1"
    }

    // MARK: - Every preset

    func testEveryReadingTokenClearsAAOnBothGroundsInBothModes() {
        for p in SRPalette.presets {
            let tokens: [(String, SRTone)] = [
                ("ink", p.ink), ("inkSecondary", p.inkSecondary), ("accent", p.accent), ("accentInk", p.accentInk),
                ("good", p.good), ("warn", p.warn), ("error", p.error),
            ]
            for (name, tone) in tokens {
                for (ground, groundName) in [(p.paper, "paper"), (p.surface, "surface")] {
                    let light = ratio(tone.light, ground.light), dark = ratio(tone.dark, ground.dark)
                    XCTAssertGreaterThanOrEqual(light, 4.5, label(p, "\(name) on \(groundName) (light)", light))
                    XCTAssertGreaterThanOrEqual(dark, 4.5, label(p, "\(name) on \(groundName) (dark)", dark))
                }
            }
        }
    }

    func testMutedInkClearsAAAndGhostInkStaysDecoration() {
        for p in SRPalette.presets {
            for (ink, paper, mode) in [(p.ink.light, p.paper.light, "light"), (p.ink.dark, p.paper.dark, "dark")] {
                let muted = ratio(SRRGB.mix(ink, paper, 0.65), paper)
                XCTAssertGreaterThanOrEqual(muted, 4.5, label(p, "inkMuted (\(mode))", muted))
            }
            let ghost = ratio(SRRGB.mix(p.ink.light, p.paper.light, 0.45), p.paper.light)
            XCTAssertTrue((2.6...3.2).contains(ghost), label(p, "inkGhost", ghost))
        }
    }

    func testPaperTypeReadsOnTheInvertingFills() {
        for p in SRPalette.presets {
            for (fill, name) in [(p.ink, "ink"), (p.accentDeep, "accentDeep")] {
                let light = ratio(p.paper.light, fill.light), dark = ratio(p.paper.dark, fill.dark)
                XCTAssertGreaterThanOrEqual(light, 4.5, label(p, "paper on \(name) (light)", light))
                XCTAssertGreaterThanOrEqual(dark, 4.5, label(p, "paper on \(name) (dark)", dark))
            }
            let white = ratio(SRRGB.white, p.accentDeep.light)
            XCTAssertGreaterThanOrEqual(white, 4.5, label(p, "white on accentDeep", white))
        }
    }

    func testTheBandsPartnersReadOnTheBand() {
        // The band is the light ink in both modes; its partners are the dark
        // mode's tokens.
        for p in SRPalette.presets {
            for (name, tone) in [("accent", p.accent), ("accentInk", p.accentInk), ("good", p.good), ("error", p.error)] {
                let value = ratio(tone.dark, p.ink.light)
                XCTAssertGreaterThanOrEqual(value, 4.5, label(p, "\(name)OnDark on the band", value))
            }
        }
    }

    func testTileTypeHoldsThreeToOneMidFill() {
        for p in SRPalette.presets {
            for key in SR.HueKey.allCases {
                let hue = p.hue(key)
                let value = ratio(hue.onFill, SRRGB.mix(hue.base, hue.glow, 0.5))
                XCTAssertGreaterThanOrEqual(value, 3, label(p, "type on the \(key.rawValue) tile", value))
            }
        }
    }

    func testEveryPresetIsComplete() {
        XCTAssertEqual(Set(SRPalette.presets.map(\.id)).count, SRPalette.presets.count)
        XCTAssertEqual(SRPalette.presets.first?.id, "prism", "Prism is the default and comes first")
        for p in SRPalette.presets {
            XCTAssertEqual(Set(p.hues.keys), Set(SR.HueKey.allCases), "\(p.name) is missing a hue")
            XCTAssertEqual(p.people.count, 8, "\(p.name) needs a colour for each of eight people")
            XCTAssertEqual(Set(p.people).count, 8, "\(p.name) gives two people one colour")
            XCTAssertEqual(p.iconGround.count, 4)
        }
        // The primary icon is Prism's; every other palette has its own.
        XCTAssertNil(SRPalette.prism.icon)
        let alternates = SRPalette.presets.compactMap(\.icon)
        XCTAssertEqual(alternates.count, SRPalette.presets.count - 1)
        XCTAssertEqual(Set(alternates).count, alternates.count)
    }

    func testEveryAlternateIconShipsInTheBundle() {
        // actool writes the alternates into Info.plist from the asset catalogue
        // (`ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS`). A palette whose
        // icon is not here would ask iOS for an icon that does not exist.
        let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
        let shipped = (icons?["CFBundleAlternateIcons"] as? [String: Any]).map { Set($0.keys) } ?? []
        for icon in SRPalette.presets.compactMap(\.icon) {
            XCTAssertTrue(shipped.contains(icon), "\(icon) is not in the bundle's alternate icons: \(shipped.sorted())")
        }
    }

    func testEveryPaletteIsOffered() {
        // The first six and the eight added on 2026-10-27. A stored choice
        // names its preset by id, so an id that went missing would quietly
        // send that reader back to Prism.
        let ids = SRPalette.presets.map(\.id)
        let expected = ["prism", "sherbet", "ocean", "sunset", "meadow", "classic",
                        "candy", "citrus", "berry", "lavender", "arctic", "forest", "terracotta", "graphite"]
        XCTAssertGreaterThanOrEqual(ids.count, expected.count)
        for id in expected {
            XCTAssertTrue(ids.contains(id), "\(id) is not offered")
            XCTAssertEqual(SRPalette.preset(id).id, id)
        }
    }

    // MARK: - The reader's own colours

    func testAPickedAccentIsMadeLegibleEitherWay() {
        // Too pale for the light page, too deep for the dark one.
        for picked: UInt32 in [0xFFFF66, 0x000033, 0x7FFFD4, 0xFF00FF] {
            for p in SRPalette.presets {
                let (accent, deep) = SRPalette.derivedAccent(picked, in: p)
                XCTAssertGreaterThanOrEqual(ratio(accent.light, p.paper.light), 4.5, "\(p.name) \(String(picked, radix: 16)) light")
                XCTAssertGreaterThanOrEqual(ratio(accent.light, p.surface.light), 4.5)
                XCTAssertGreaterThanOrEqual(ratio(accent.dark, p.paper.dark), 4.5, "\(p.name) \(String(picked, radix: 16)) dark")
                XCTAssertGreaterThanOrEqual(ratio(accent.dark, p.surface.dark), 4.5)
                XCTAssertGreaterThanOrEqual(ratio(accent.dark, p.ink.light), 4.5, "on the band")
                XCTAssertGreaterThanOrEqual(ratio(SRRGB.white, deep.light), 4.5)
                XCTAssertGreaterThanOrEqual(ratio(p.paper.light, deep.light), 4.5)
            }
        }
    }

    func testAnAccentThatAlreadyReadsIsLeftAlone() {
        let (accent, _) = SRPalette.derivedAccent(0x5233F0, in: .prism)
        XCTAssertEqual(accent.light, 0x5233F0)
    }

    func testAPickedHueChoosesItsOwnType() {
        let yellow = SRHueSpec.from(0xFFE600, ink: 0x15123A)
        XCTAssertEqual(yellow.onFill, 0x15123A, "white on yellow fails")
        let navy = SRHueSpec.from(0x1E2A78, ink: 0x15123A)
        XCTAssertEqual(navy.onFill, SRRGB.white)
        XCTAssertEqual(navy.base, 0x1E2A78)
    }

    func testPicksBelongToTheirPreset() {
        var choice = SRPaletteChoice()
        choice.preset = "ocean"
        choice.pick(.family, 0x123456)
        XCTAssertEqual(SRPalette.resolve(choice).hue(.family).base, 0x123456)
        choice.preset = "prism"
        XCTAssertEqual(SRPalette.resolve(choice).hue(.family).base, SRPalette.prism.hue(.family).base,
                       "a colour picked on Ocean leaked into Prism")
        choice.preset = "ocean"
        XCTAssertTrue(choice.customised)
        choice.resetCurrent()
        XCTAssertFalse(choice.customised)
        XCTAssertEqual(SRPalette.resolve(choice), SRPalette.ocean)
    }

    func testUnpickingAHueRemovesIt() {
        var choice = SRPaletteChoice()
        choice.pick(.steps, 0xABCDEF)
        choice.pick(.steps, nil)
        XCTAssertFalse(choice.customised)
        XCTAssertNil(choice.hues["prism"])
    }

    // MARK: - Storage

    func testTheChoiceSurvivesTheRoundTrip() {
        var choice = SRPaletteChoice()
        choice.preset = "sunset"
        choice.pick(.trips, 0x00FF00)
        choice.accent["sunset"] = 0x112233
        choice.glow = .soft
        choice.iconFollows = false
        XCTAssertEqual(SRPaletteChoice.decode(choice.raw), choice)
    }

    func testAnythingUnreadableIsPrism() {
        XCTAssertEqual(SRPaletteChoice.decode(nil), SRPaletteChoice())
        XCTAssertEqual(SRPaletteChoice.decode("not json"), SRPaletteChoice())
        // A field from a later build is ignored, not fatal.
        let later = SRPaletteChoice.decode(#"{"preset":"ocean","glow":"neon","future":1}"#)
        XCTAssertEqual(later.preset, "ocean")
        XCTAssertEqual(later.glow, .vivid)
        // A preset this build does not have resolves to Prism.
        var gone = SRPaletteChoice()
        gone.preset = "retired"
        XCTAssertEqual(SRPalette.resolve(gone).id, "prism")
    }

    func testAPickedColourComesBackAsTheSameHex() {
        for hex: UInt32 in [0x000000, 0xFFFFFF, 0x5233F0, 0xE85D00] {
            XCTAssertEqual(SRRGB.hex(of: SRRGB.color(hex)), hex)
        }
    }

    // MARK: - Paint and the widgets

    func testPaintIsThePalette() {
        let paint = SRPaint(SRPalette.ocean)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(paint.accent).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(Int(round(r * 255)) << 16 | Int(round(g * 255)) << 8 | Int(round(b * 255)), 0x0B5FD6)
        UIColor(paint.accent).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)).getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(Int(round(r * 255)) << 16 | Int(round(g * 255)) << 8 | Int(round(b * 255)), 0x6CB2FF)
        XCTAssertEqual(paint.people.count, 8)
    }

    func testTheWidgetsGetThePalettesHues() {
        let widget = SRPalette.sunset.widget
        XCTAssertEqual(widget.steps, SRPalette.sunset.hue(.steps))
        XCTAssertEqual(widget.tasks, SRPalette.sunset.hue(.tasks))
        XCTAssertEqual(widget.family, SRPalette.sunset.hue(.family))
        XCTAssertEqual(widget.trips, SRPalette.sunset.hue(.trips))
        XCTAssertEqual(widget.gamesHue, SRPalette.sunset.hue(.games))
        XCTAssertEqual(widget.healthHue, SRPalette.sunset.hue(.health))
        XCTAssertEqual(widget.people, SRPalette.sunset.people)
        XCTAssertEqual(widget.person(1), SRPalette.sunset.people[1])
        XCTAssertEqual(widget.person(SRPalette.sunset.people.count), SRPalette.sunset.people[0], "slots wrap round")
        // The extension's fallback is Prism's own, exactly.
        XCTAssertEqual(SRWidgetPalette.prism, SRPalette.prism.widget)
    }

    /// A palette left on the shelf before the glance widgets reads, and
    /// paints their hues and circles in Prism's.
    func testAWidgetPaletteFromBeforeTheGlanceWidgetsStillReads() throws {
        var old = SRPalette.meadow.widget
        old.games = nil
        old.health = nil
        old.people = nil
        let decoded = try JSONDecoder().decode(SRWidgetPalette.self, from: JSONEncoder().encode(old))
        XCTAssertEqual(decoded.steps, SRPalette.meadow.widget.steps)
        XCTAssertEqual(decoded.gamesHue, SRWidgetPalette.prism.gamesHue)
        XCTAssertEqual(decoded.healthHue, SRWidgetPalette.prism.healthHue)
        XCTAssertEqual(decoded.person(0), SRWidgetPalette.prismPeople[0])
    }

    func testTheWidgetPaletteRoundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(SRPalette.meadow.widget)
        XCTAssertEqual(try JSONDecoder().decode(SRWidgetPalette.self, from: data), SRPalette.meadow.widget)
    }

    // MARK: - The sheet

    func testTheSheetOffersOnlyTheColoursThisPersonSees() {
        let member = SRPaletteSheet.keys(access: AppAccess(family: true), sitePaired: false)
        // The Travel kit tile is on every phone and wears the trips hue, so a
        // member with no trips board still gets a Trips colour to change.
        XCTAssertEqual(member, [.family, .health, .move, .trips])
        let owner = SRPaletteSheet.keys(access: .everything, sitePaired: true)
        XCTAssertEqual(owner.first, .family)
        XCTAssertTrue(owner.contains(.alerts))
        XCTAssertTrue(owner.contains(.daydream))
        XCTAssertEqual(Set(owner).count, owner.count, "a hue listed twice")
    }
}
