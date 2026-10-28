import SwiftUI

/// The glance widgets in Settings → Widget previews (`FamilyWidgetGallery`):
/// Family now, Trips, Games and Health today at each size, as the widget
/// draws them.
///
/// Family now and Trips draw this phone's own family and trips when it has
/// them — the demo's in the screenshot harness — through the same bridges
/// that fill the shelf; Games and Health draw made-up samples (the lobby and
/// the rings are not this screen's to read).
struct GlanceWidgetGallerySections: View {
    let palette: SRWidgetPalette
    @ObservedObject private var trips = TripStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SRSectionLabel(text: "Family now")
            HStack(alignment: .top, spacing: 16) {
                tile(FamilyNowWidgetView(snapshot: family, size: .small, palette: palette), width: 158, hue: palette.family)
                VStack(alignment: .leading, spacing: 14) {
                    tile(FamilyNowWidgetView(snapshot: family, size: .rectangular, palette: palette), width: 158, height: 72, lock: true)
                    tile(FamilyNowWidgetView(snapshot: family, size: .circular, palette: palette), width: 72, height: 72, lock: true)
                }
            }
            tile(FamilyNowWidgetView(snapshot: family, size: .medium, palette: palette), width: 338, hue: palette.family)

            SRSectionLabel(text: "Trips")
            HStack(alignment: .top, spacing: 16) {
                tile(TripsWidgetView(snapshot: tripDay, size: .small, palette: palette), width: 158, hue: palette.trips)
                tile(TripsWidgetView(snapshot: TripsWidgetSamples.upcoming(), size: .small, palette: palette), width: 158, hue: palette.trips)
            }
            HStack(alignment: .top, spacing: 16) {
                tile(TripsWidgetView(snapshot: tripDay, size: .rectangular, palette: palette), width: 158, height: 72, lock: true)
                tile(TripsWidgetView(snapshot: TripsWidgetSamples.upcoming(), size: .circular, palette: palette), width: 72, height: 72, lock: true)
            }
            tile(TripsWidgetView(snapshot: tripDay, size: .medium, palette: palette), width: 338, hue: palette.trips)

            SRSectionLabel(text: "Games")
            HStack(alignment: .top, spacing: 16) {
                tile(GamesWidgetView(snapshot: GamesWidgetSamples.snapshot(), size: .small, palette: palette), width: 158, hue: palette.gamesHue)
                VStack(alignment: .leading, spacing: 14) {
                    tile(GamesWidgetView(snapshot: GamesWidgetSamples.snapshot(), size: .rectangular, palette: palette), width: 158, height: 72, lock: true)
                    tile(GamesWidgetView(snapshot: GamesWidgetSamples.snapshot(), size: .circular, palette: palette), width: 72, height: 72, lock: true)
                }
            }
            tile(GamesWidgetView(snapshot: GamesWidgetSamples.snapshot(), size: .medium, palette: palette), width: 338, hue: palette.gamesHue)

            SRSectionLabel(text: "Health today")
            HStack(alignment: .top, spacing: 16) {
                tile(HealthWidgetView(snapshot: HealthWidgetSamples.snapshot(), size: .small, palette: palette), width: 158, hue: palette.healthHue)
                VStack(alignment: .leading, spacing: 14) {
                    tile(HealthWidgetView(snapshot: HealthWidgetSamples.snapshot(), size: .rectangular, palette: palette), width: 158, height: 72, lock: true)
                    tile(HealthWidgetView(snapshot: HealthWidgetSamples.snapshot(), size: .circular, palette: palette), width: 72, height: 72, lock: true)
                }
            }
            tile(HealthWidgetView(snapshot: HealthWidgetSamples.snapshot(), size: .medium, palette: palette), width: 338, hue: palette.healthHue)
        }
    }

    /// This phone's family as the widget would get it, else the samples.
    private var family: FamilyNowSnapshot {
        guard let view = FamilyStore.current?.view, view.showsHousehold, !view.people.isEmpty else {
            return FamilyNowWidgetSamples.snapshot()
        }
        return FamilyNowWidgetBridge.snapshot(view)
    }

    /// The trip day running on this phone, else the samples.
    private var tripDay: TripsWidgetSnapshot {
        if let made = TripsWidgetBridge.snapshot(trips), made.kind == .running, !made.stops.isEmpty { return made }
        return TripsWidgetSamples.running()
    }

    /// A widget-sized, widget-shaped frame, as `FamilyWidgetGallery` draws
    /// one. `lock` draws a Lock Screen slot: no ground, light text on the
    /// wallpaper.
    @ViewBuilder
    private func tile<V: View>(_ view: V, width: CGFloat, height: CGFloat = 158, lock: Bool = false, hue: SRHueSpec? = nil) -> some View {
        let shape = RoundedRectangle(cornerRadius: lock ? 12 : 22, style: .continuous)
        let framed = view
            .padding(lock ? 6 : 16)
            .frame(width: width, height: height, alignment: .topLeading)
            .foregroundStyle(lock ? Color.white : SR.ink)
            .environment(\.colorScheme, lock ? .dark : .light)
        if let hue, !lock {
            framed.background(FamilyWidgetGround(hue: hue).clipShape(shape))
        } else {
            framed.background(shape.fill(Color.white.opacity(0.12)))
        }
    }
}
