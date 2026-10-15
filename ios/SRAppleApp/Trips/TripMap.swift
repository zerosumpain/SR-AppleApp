import SwiftUI
import MapLibre

// The day on a map that works with no signal: MapLibre on OpenFreeMap's
// tiles, as the route screens draw (`Health/SRRouteMap.swift`), with the
// day's pack downloaded through the same `OfflineMaps` store.

enum TripDayGeometry {
    /// The pack id for one trip day, kept apart from route ids.
    static func packId(trip: String, date: String) -> String { "trip:\(trip):\(date)" }

    /// The legs drawn: the routed line where there is one, else a straight
    /// segment between the two stops — still the right way to point.
    static func legLines(_ day: PlannedDay) -> [[CLLocationCoordinate2D]] {
        day.legs.enumerated().compactMap { i, leg in
            if let line = leg.line, line.count > 1 {
                return line.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
            }
            guard i + 1 < day.stops.count,
                  let a = day.stops[i].location, let b = day.stops[i + 1].location else { return nil }
            return [CLLocationCoordinate2D(latitude: a.lat, longitude: a.lng),
                    CLLocationCoordinate2D(latitude: b.lat, longitude: b.lng)]
        }
    }

    /// One line through the whole day, for the pack's corridor.
    static func corridorLine(_ day: PlannedDay) -> [CLLocationCoordinate2D] {
        let legs = legLines(day).flatMap { $0 }
        if !legs.isEmpty { return legs }
        return day.stops.compactMap(\.location).map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
    }
}

/// Stops, legs and you. Done stops go quiet, the next one is the accent.
struct TripDayMap: UIViewRepresentable {
    let day: PlannedDay
    let doneIds: Set<String>
    let nextId: String?
    var showsUser = true
    /// Drawn instead of the system blue dot — the demo has no GPS.
    var marker: CLLocationCoordinate2D?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero, styleURL: SRMapStyle.url)
        map.delegate = context.coordinator
        map.logoView.isHidden = true
        map.compassView.compassVisibility = .adaptive
        map.isPitchEnabled = false
        map.showsUserLocation = showsUser && !SRDemo.isOn
        context.coordinator.apply(self, to: map)
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        let wantsUser = showsUser && !SRDemo.isOn
        if map.showsUserLocation != wantsUser { map.showsUserLocation = wantsUser }
        context.coordinator.apply(self, to: map)
    }

    /// What is drawn, so an unchanged day is not redrawn. The day screen
    /// refreshes every thirty seconds, and rebuilding every line and stop
    /// layer on each tick kept the GPU busy for a picture that had not moved.
    nonisolated fileprivate var drawn: String {
        let marker = self.marker.map { "\($0.latitude),\($0.longitude)" } ?? "-"
        return "\(day.hashValue)|\(doneIds.sorted().joined(separator: ","))|\(nextId ?? "-")|\(marker)"
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        private var latest: TripDayMap?
        private var framedFor: String?
        private var drawnKey: String?

        func apply(_ spec: TripDayMap, to map: MLNMapView) {
            latest = spec
            guard let style = map.style else { return }
            let key = spec.drawn
            if key != drawnKey {
                draw(spec, on: style)
                drawnKey = key
            }
            frame(spec, map)
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            guard let spec = latest else { return }
            draw(spec, on: style)
            drawnKey = spec.drawn
            frame(spec, mapView)
        }

        /// Framed once per day shown; after that the reader's pan stays.
        private func frame(_ spec: TripDayMap, _ map: MLNMapView) {
            guard framedFor != spec.day.date, map.bounds.width > 0 else { return }
            let all = spec.day.stops.compactMap(\.location) + spec.day.legs.flatMap { $0.line ?? [] }
            guard let first = all.first else { return }
            framedFor = spec.day.date
            var minLat = first.lat, maxLat = first.lat, minLng = first.lng, maxLng = first.lng
            for p in all {
                minLat = min(minLat, p.lat); maxLat = max(maxLat, p.lat)
                minLng = min(minLng, p.lng); maxLng = max(maxLng, p.lng)
            }
            let bounds = MLNCoordinateBounds(
                sw: CLLocationCoordinate2D(latitude: minLat, longitude: minLng),
                ne: CLLocationCoordinate2D(latitude: maxLat, longitude: maxLng)
            )
            map.setVisibleCoordinateBounds(
                bounds, edgePadding: UIEdgeInsets(top: 40, left: 30, bottom: 40, right: 30), animated: false, completionHandler: nil
            )
        }

        private func draw(_ spec: TripDayMap, on style: MLNStyle) {
            let legs: [MLNShape] = TripDayGeometry.legLines(spec.day).map { coords in
                var points = coords
                return MLNPolylineFeature(coordinates: &points, count: UInt(points.count))
            }
            shape("sr-trip-legs", MLNShapeCollection(shapes: legs), on: style) { source in
                let layer = MLNLineStyleLayer(identifier: "sr-trip-legs", source: source)
                layer.lineColor = NSExpression(forConstantValue: UIColor(hex: SR.Fixed.accent))
                layer.lineWidth = NSExpression(forConstantValue: 4)
                layer.lineCap = NSExpression(forConstantValue: "round")
                layer.lineJoin = NSExpression(forConstantValue: "round")
                return layer
            }
            stops("sr-trip-done", spec.day.stops.filter { spec.doneIds.contains($0.id) }, color: UIColor(hex: SR.Fixed.ink).withAlphaComponent(0.4), radius: 6, on: style)
            stops("sr-trip-stops", spec.day.stops.filter { !spec.doneIds.contains($0.id) && $0.id != spec.nextId }, color: UIColor(hex: SR.Fixed.ink), radius: 7, on: style)
            stops("sr-trip-next", spec.day.stops.filter { $0.id == spec.nextId }, color: UIColor(hex: SR.Fixed.accent), radius: 10, on: style)
            let here: [MLNShape] = spec.marker.map { at in
                let f = MLNPointFeature()
                f.coordinate = at
                return [f]
            } ?? []
            circles("sr-trip-marker", here, color: .systemBlue, radius: 8, on: style)
        }

        private func stops(_ id: String, _ list: [PlannedStop], color: UIColor, radius: Double, on style: MLNStyle) {
            let points: [MLNShape] = list.compactMap { stop in
                guard let at = stop.location else { return nil }
                let f = MLNPointFeature()
                f.coordinate = CLLocationCoordinate2D(latitude: at.lat, longitude: at.lng)
                f.title = stop.title
                return f
            }
            circles(id, points, color: color, radius: radius, on: style)
        }

        private func circles(_ id: String, _ points: [MLNShape], color: UIColor, radius: Double, on style: MLNStyle) {
            shape(id, MLNShapeCollection(shapes: points), on: style) { source in
                let layer = MLNCircleStyleLayer(identifier: id, source: source)
                layer.circleColor = NSExpression(forConstantValue: color)
                layer.circleRadius = NSExpression(forConstantValue: radius)
                layer.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
                layer.circleStrokeWidth = NSExpression(forConstantValue: 2.5)
                return layer
            }
        }

        /// Replace a source's shape, or add the source and its layer once.
        private func shape(_ id: String, _ shape: MLNShape, on style: MLNStyle, layer: (MLNShapeSource) -> MLNStyleLayer) {
            if let source = style.source(withIdentifier: id) as? MLNShapeSource {
                source.shape = shape
                return
            }
            let source = MLNShapeSource(identifier: id, shape: shape, options: nil)
            style.addSource(source)
            style.addLayer(layer(source))
        }
    }
}

/// "Download today's map" — the day's corridor as an offline pack, on Wi-Fi
/// unless the person says mobile data is fine.
struct TripMapPackRow: View {
    let tripId: String
    let day: PlannedDay
    let title: String
    @ObservedObject private var maps = OfflineMaps.shared
    @ObservedObject private var network = TripNetwork.shared
    @State private var askCellular = false

    private var id: String { TripDayGeometry.packId(trip: tripId, date: day.date) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(SR.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(SR.Text.title(15)).foregroundStyle(SR.ink)
                Text(detail).font(SR.Text.secondary(13)).foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            action
        }
        .padding(.vertical, 6)
        .confirmationDialog("Download on mobile data?", isPresented: $askCellular, titleVisibility: .visible) {
            Button("Download now") { start() }
            Button("Wait for Wi-Fi", role: .cancel) {}
        } message: {
            Text("A day's map is usually a few megabytes.")
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var action: some View {
        switch maps.state(for: id) {
        case .none, .failed:
            Button {
                SRHaptic.tap()
                if network.unmetered { start() } else { askCellular = true }
            } label: { SRButtonLabel(title: "Download", icon: "arrow.down.circle") }
                .srButton(.regular)
                .disabled(!network.online || SRDemo.isOn)
                .accessibilityIdentifier("trip-map-download")
        case .downloading(let p):
            ProgressView(value: p).frame(width: 60).tint(SR.accent)
        case .ready:
            Button("Remove") { maps.delete(id) }
                .font(SR.Text.label())
                .foregroundStyle(SR.inkMuted)
        }
    }

    private func start() {
        maps.download(id: id, name: title, line: TripDayGeometry.corridorLine(day))
    }

    private var icon: String {
        if case .ready = maps.state(for: id) { return "checkmark.circle.fill" }
        return "map"
    }

    private var headline: String {
        switch maps.state(for: id) {
        case .ready: return "Today's map is on the phone"
        case .downloading: return "Downloading the map…"
        default: return "Download today's map"
        }
    }

    private var detail: String {
        switch maps.state(for: id) {
        case .ready(let bytes): return "\(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)) · works with no signal"
        case .failed(let why): return why
        case .downloading: return "Keep the app open until it finishes."
        case .none:
            if !network.online { return "Needs a connection — the plan itself is already saved." }
            return network.unmetered ? "On Wi-Fi now — a few megabytes." : "Best on Wi-Fi — a few megabytes."
        }
    }
}
