import SwiftUI
import MapLibre

// Trip maps that work with no signal: MapLibre on OpenFreeMap's
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

/// A trip map: whatever `TripMapScene` worked out — lines by mode, numbered
/// pins by stage, a ghost under a proposed change — painted on MapLibre so
/// it works offline. Tapping a pin hands it back (`onTap`); tapping nothing
/// hands back nil.
///
/// The pins are drawn into the map's style, so MapLibre knows nothing of them
/// as things to read out. Each pin on screen is also a VoiceOver element of
/// its own ("3. Trevi Fountain, 14:20"), where it is drawn, and activating
/// one does what tapping it does (plan §5.5). They sit beside the map in a
/// host view: `MLNMapView` answers VoiceOver's questions about its own
/// elements itself, so elements put on it would never be asked for.
struct TripSceneMap: UIViewRepresentable {
    let scene: TripMapScene.Scene
    var showsUser = false
    /// Drawn instead of the system blue dot — the demo has no GPS.
    var marker: CLLocationCoordinate2D? = nil
    /// How much of the map's foot the drawer covers: kept clear when framing.
    var bottomInset: CGFloat = 0
    /// Bumped to frame the whole scene again (Fit, a new preview).
    var frameToken = 0
    /// A place to bring into view (a pin tapped, a stop picked).
    var focus: TripLatLng? = nil
    /// Bumped to follow the phone's position.
    var followToken = 0
    var interactive = true
    var onTap: ((TripMapScene.Pin?) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> TripMapHost {
        let map = MLNMapView(frame: .zero, styleURL: SRMapStyle.url)
        map.delegate = context.coordinator
        map.logoView.isHidden = true
        map.compassView.compassVisibility = .adaptive
        map.isPitchEnabled = false
        map.isScrollEnabled = interactive
        map.isZoomEnabled = interactive
        map.isRotateEnabled = interactive
        map.showsUserLocation = showsUser && !SRDemo.isOn
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        // A double tap still zooms: the single tap waits for it to fail.
        for other in map.gestureRecognizers ?? [] {
            if let double = other as? UITapGestureRecognizer, double.numberOfTapsRequired == 2 { tap.require(toFail: double) }
        }
        map.addGestureRecognizer(tap)
        let host = TripMapHost(map: map)
        context.coordinator.host = host
        context.coordinator.apply(self, to: map)
        return host
    }

    func updateUIView(_ host: TripMapHost, context: Context) {
        let map = host.map
        let wantsUser = showsUser && !SRDemo.isOn
        if map.showsUserLocation != wantsUser { map.showsUserLocation = wantsUser }
        context.coordinator.apply(self, to: map)
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        static let pinsLayer = "sr-trip-pins"
        static let topPinsLayer = "sr-trip-pins-top"
        static let markerLayer = "sr-trip-marker"

        private var latest: TripSceneMap?
        /// Where the pins' VoiceOver elements live.
        weak var host: TripMapHost?
        private var drawn: TripMapScene.Scene?
        private var drawnMarker: CLLocationCoordinate2D?
        private var framedToken: Int?
        private var focused: TripLatLng?
        /// The drawer's height when the focus was framed: re-framed once it settles.
        private var focusedInset: CGFloat = 0
        private var followed = 0
        /// Every line layer made so far, by style key: emptied, never
        /// removed, when a scene stops using one.
        private var lineKeys: Set<String> = []

        func apply(_ spec: TripSceneMap, to map: MLNMapView) {
            latest = spec
            guard let style = map.style else { return }
            if drawn != spec.scene || !sameMarker(spec.marker) {
                draw(spec, on: style)
                drawn = spec.scene
                drawnMarker = spec.marker
            }
            place(spec, map)
            host?.speak(spec, on: map)
        }

        /// The camera settled: the pins are somewhere else on the screen.
        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            guard let spec = latest else { return }
            host?.speak(spec, on: mapView)
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            guard let spec = latest else { return }
            lineKeys = []
            draw(spec, on: style)
            drawn = spec.scene
            drawnMarker = spec.marker
            place(spec, mapView)
        }

        private func sameMarker(_ m: CLLocationCoordinate2D?) -> Bool {
            switch (m, drawnMarker) {
            case (nil, nil): return true
            case let (a?, b?): return a.latitude == b.latitude && a.longitude == b.longitude
            default: return false
            }
        }

        // MARK: Camera

        /// Frame once, then only when asked (Fit, a new preview); go to a
        /// picked place; follow the phone when asked. A reader's pan stays.
        private func place(_ spec: TripSceneMap, _ map: MLNMapView) {
            guard map.bounds.width > 0 else { return }
            if framedToken != spec.frameToken {
                let first = framedToken == nil
                if frame(spec.scene.frame, spec, map, animated: !first) { framedToken = spec.frameToken }
            }
            if let focus = spec.focus, focus != focused || abs(spec.bottomInset - focusedInset) > 20 {
                // A pin picked as the drawer drops: framed now, and again once
                // the drawer has settled at its new height.
                focused = focus
                focusedInset = spec.bottomInset
                _ = frame([focus], spec, map, animated: true, span: 0.006)
            } else if spec.focus == nil {
                focused = nil
            }
            if spec.followToken != followed {
                followed = spec.followToken
                if map.showsUserLocation { map.setUserTrackingMode(.follow, animated: true, completionHandler: nil) }
            }
        }

        @discardableResult
        private func frame(_ points: [TripLatLng], _ spec: TripSceneMap, _ map: MLNMapView, animated: Bool, span: Double = 0.004) -> Bool {
            guard let b = TripMapScene.bounds(points, minSpan: span) else { return false }
            let bounds = MLNCoordinateBounds(
                sw: CLLocationCoordinate2D(latitude: b.minLat, longitude: b.minLng),
                ne: CLLocationCoordinate2D(latitude: b.maxLat, longitude: b.maxLng)
            )
            // Never more than most of the map: a drawer pulled high still
            // leaves a strip to frame into.
            let bottom = min(spec.bottomInset, map.bounds.height * 0.6) + 28
            map.setVisibleCoordinateBounds(
                bounds, edgePadding: UIEdgeInsets(top: 36, left: 36, bottom: bottom, right: 36), animated: animated, completionHandler: nil
            )
            return true
        }

        // MARK: Taps

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let map = gesture.view as? MLNMapView, let spec = latest else { return }
            let p = gesture.location(in: map)
            let rect = CGRect(x: p.x - 22, y: p.y - 22, width: 44, height: 44)
            let hit = map.visibleFeatures(in: rect, styleLayerIdentifiers: [Self.topPinsLayer]).first
                ?? map.visibleFeatures(in: rect, styleLayerIdentifiers: [Self.pinsLayer]).first
            let id = hit?.attribute(forKey: "pid") as? String
            spec.onTap?(id.flatMap { pid in spec.scene.pins.first { $0.id == pid } })
        }

        // MARK: Drawing

        private func draw(_ spec: TripSceneMap, on style: MLNStyle) {
            // Pins first, so every line can go in beneath them.
            let below = pins(spec.scene.pins.filter { !$0.top }, id: Self.pinsLayer, on: style, below: nil)
            _ = pins(spec.scene.pins.filter(\.top), id: Self.topPinsLayer, on: style, below: nil)
            lines(spec.scene.lines, on: style, below: below)
            marker(spec.marker, on: style)
        }

        private func lines(_ lines: [TripMapScene.Line], on style: MLNStyle, below: MLNStyleLayer?) {
            var byKey: [String: (TripMapScene.LineStyle, [MLNShape])] = [:]
            var order: [String] = []
            for line in lines where line.points.count > 1 {
                var coords = line.points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
                let shape = MLNPolylineFeature(coordinates: &coords, count: UInt(coords.count))
                let key = line.style.key
                if byKey[key] == nil { order.append(key); byKey[key] = (line.style, []) }
                byKey[key]?.1.append(shape)
            }
            for key in lineKeys where byKey[key] == nil {
                (style.source(withIdentifier: "sr-trip-line-\(key)") as? MLNShapeSource)?.shape = MLNShapeCollection(shapes: [])
            }
            // Ghosts and guesses under the real routes, the heaviest on top.
            let sorted = order.sorted { (byKey[$0]?.0.width ?? 0) < (byKey[$1]?.0.width ?? 0) }
            for key in sorted {
                guard let entry = byKey[key] else { continue }
                let (lineStyle, shapes) = entry
                let id = "sr-trip-line-\(key)"
                let collection = MLNShapeCollection(shapes: shapes)
                if let source = style.source(withIdentifier: id) as? MLNShapeSource {
                    source.shape = collection
                    continue
                }
                let source = MLNShapeSource(identifier: id, shape: collection, options: nil)
                style.addSource(source)
                let layer = MLNLineStyleLayer(identifier: id, source: source)
                layer.lineColor = NSExpression(forConstantValue: UIColor(hex: lineStyle.color))
                layer.lineOpacity = NSExpression(forConstantValue: lineStyle.alpha)
                layer.lineWidth = NSExpression(forConstantValue: lineStyle.width)
                layer.lineJoin = NSExpression(forConstantValue: "round")
                switch lineStyle.pattern {
                case .solid:
                    layer.lineCap = NSExpression(forConstantValue: "round")
                case .dotted:
                    // Round caps on near-zero dashes: a row of dots.
                    layer.lineCap = NSExpression(forConstantValue: "round")
                    layer.lineDashPattern = NSExpression(forConstantValue: [0.1, 1.9])
                case .dashed:
                    layer.lineCap = NSExpression(forConstantValue: "butt")
                    layer.lineDashPattern = NSExpression(forConstantValue: [2.2, 1.8])
                }
                if let below { style.insertLayer(layer, below: below) } else { style.addLayer(layer) }
                lineKeys.insert(key)
            }
        }

        /// Pins as one symbol layer, each feature naming its badge image.
        @discardableResult
        private func pins(_ pins: [TripMapScene.Pin], id: String, on style: MLNStyle, below: MLNStyleLayer?) -> MLNStyleLayer? {
            // Features, not bare shapes: a plain shape collection goes to the
            // map as geometry alone, and the badge and id ride as properties.
            let features: [MLNPointFeature] = pins.map { pin in
                let name = pin.badge.name
                if style.image(forName: name) == nil { style.setImage(TripPinArt.image(pin.badge), forName: name) }
                let f = MLNPointFeature()
                f.coordinate = CLLocationCoordinate2D(latitude: pin.at.lat, longitude: pin.at.lng)
                f.attributes = ["icon": name, "pid": pin.id]
                return f
            }
            let collection = MLNShapeCollectionFeature(shapes: features)
            if let source = style.source(withIdentifier: id) as? MLNShapeSource {
                source.shape = collection
                return style.layer(withIdentifier: id)
            }
            let source = MLNShapeSource(identifier: id, shape: collection, options: nil)
            style.addSource(source)
            let layer = MLNSymbolStyleLayer(identifier: id, source: source)
            layer.iconImageName = NSExpression(forKeyPath: "icon")
            layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
            layer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
            if let below { style.insertLayer(layer, below: below) } else { style.addLayer(layer) }
            return layer
        }

        private func marker(_ at: CLLocationCoordinate2D?, on style: MLNStyle) {
            let shapes: [MLNShape] = at.map { c in
                let f = MLNPointFeature()
                f.coordinate = c
                return [f]
            } ?? []
            let collection = MLNShapeCollection(shapes: shapes)
            if let source = style.source(withIdentifier: Self.markerLayer) as? MLNShapeSource {
                source.shape = collection
                return
            }
            let source = MLNShapeSource(identifier: Self.markerLayer, shape: collection, options: nil)
            style.addSource(source)
            let layer = MLNCircleStyleLayer(identifier: Self.markerLayer, source: source)
            layer.circleColor = NSExpression(forConstantValue: UIColor.systemBlue)
            layer.circleRadius = NSExpression(forConstantValue: 8)
            layer.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
            layer.circleStrokeWidth = NSExpression(forConstantValue: 2.5)
            style.addLayer(layer)
        }
    }
}

/// The map and, beside it, its pins as VoiceOver elements. Touches go to the
/// map as before: the host draws nothing and the elements are not views.
final class TripMapHost: UIView {
    let map: MLNMapView
    private var pins: [TripPinElement] = []

    init(map: MLNMapView) {
        self.map = map
        super.init(frame: .zero)
        map.frame = bounds
        map.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(map)
        accessibilityElements = [map]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var latest: TripSceneMap?

    override func layoutSubviews() {
        super.layoutSubviews()
        map.frame = bounds
        if let latest { speak(latest, on: map) }
    }

    /// One element per labelled pin on screen, in the plan's order, framed
    /// where the pin is drawn: a 44-point square, the tap's own reach. A pin
    /// off the edge, or under the drawer, is left out — VoiceOver would
    /// otherwise point at something nobody can see.
    func speak(_ spec: TripSceneMap, on map: MLNMapView) {
        latest = spec
        guard map.bounds.width > 0 else { return }
        let visible = CGRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - spec.bottomInset))
        pins = spec.scene.pins.compactMap { pin in
            guard let label = pin.label else { return nil }
            let point = map.convert(CLLocationCoordinate2D(latitude: pin.at.lat, longitude: pin.at.lng), toPointTo: self)
            guard visible.contains(point) else { return nil }
            let element = TripPinElement(accessibilityContainer: self)
            element.accessibilityLabel = label
            element.accessibilityFrameInContainerSpace = CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44)
            if let onTap = spec.onTap {
                element.accessibilityTraits = .button
                element.activate = { onTap(pin) }
            }
            return element
        }
        accessibilityElements = (pins as [Any]) + [map]
    }
}

/// A pin, to VoiceOver: activating it is tapping it.
final class TripPinElement: UIAccessibilityElement {
    var activate: (() -> Void)?

    override func accessibilityActivate() -> Bool {
        guard let activate else { return false }
        activate()
        return true
    }
}

/// A pin, drawn once per distinct badge: a white-edged disc in its colour,
/// its number or symbol in white, a ring when it is next or picked.
enum TripPinArt {
    static func image(_ badge: TripMapScene.Badge) -> UIImage {
        let d = CGFloat(badge.size)
        let ring: CGFloat = badge.ring == nil ? 0 : 3
        let pad: CGFloat = 3
        let full = d + ring * 2 + pad * 2
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: full, height: full), format: format).image { ctx in
            let c = ctx.cgContext
            let outer = CGRect(x: pad, y: pad, width: d + ring * 2, height: d + ring * 2)
            let disc = outer.insetBy(dx: ring, dy: ring)
            c.saveGState()
            c.setShadow(offset: CGSize(width: 0, height: 1), blur: 2.5, color: UIColor.black.withAlphaComponent(badge.faded ? 0.12 : 0.3).cgColor)
            if let colour = badge.ring {
                UIColor(hex: colour).setFill()
                c.fillEllipse(in: outer)
            }
            UIColor.white.setFill()
            c.fillEllipse(in: disc)
            c.restoreGState()
            let edge: CGFloat = badge.glyph == .dot ? 1.5 : 2.5
            UIColor(hex: badge.fill, alpha: badge.faded ? 0.42 : 1).setFill()
            c.fillEllipse(in: disc.insetBy(dx: edge, dy: edge))
            switch badge.glyph {
            case .number(let n):
                let font = UIFont.monospacedDigitSystemFont(ofSize: d * 0.46, weight: .bold)
                let text = "\(n)" as NSString
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
                let size = text.size(withAttributes: attributes)
                text.draw(at: CGPoint(x: disc.midX - size.width / 2, y: disc.midY - size.height / 2), withAttributes: attributes)
            case .symbol(let name):
                let config = UIImage.SymbolConfiguration(pointSize: d * 0.4, weight: .semibold)
                if let symbol = UIImage(systemName: name, withConfiguration: config)?.withTintColor(.white, renderingMode: .alwaysOriginal) {
                    let s = symbol.size
                    symbol.draw(in: CGRect(x: disc.midX - s.width / 2, y: disc.midY - s.height / 2, width: s.width, height: s.height))
                }
            case .dot:
                break
            }
        }
    }
}

/// The key the map draws a day with: the plan's stages, as the list groups
/// them, so a pin's colour is its band's.
extension TripMapScene {
    static func day(_ day: PlannedDay, bundle: TripBundle, done: Set<String>, nextId: String?, selectedId: String?, preview: PlannedDay?) -> Scene {
        Self.day(
            day, stages: TripStages.stages(day, wishes: bundle.wishes), done: done, nextId: nextId, selectedId: selectedId,
            preview: preview, previewStages: preview.map { TripStages.stages($0, wishes: bundle.wishes) } ?? []
        )
    }
}

/// The day's ••• menu: what used to sit at the foot of the plan — this
/// day's offline map, the way back to all the days, and how fresh the saved
/// plan is — out of the way of the plan itself. With no signal, its icon
/// says so.
struct TripDayMoreMenu: View {
    let tripId: String
    let day: PlannedDay
    let tripTitle: String
    let allDays: () -> Void
    @ObservedObject private var maps = OfflineMaps.shared
    @ObservedObject private var network = TripNetwork.shared
    @ObservedObject private var store = TripStore.shared
    @ObservedObject private var queue = TripEventQueue.shared
    @State private var askCellular = false

    private var id: String { TripDayGeometry.packId(trip: tripId, date: day.date) }
    private var mapped: Bool { !TripDayGeometry.corridorLine(day).isEmpty }

    var body: some View {
        Menu {
            Section {
                if mapped { mapItem }
                Button { allDays() } label: { Label("All days of \(tripTitle)", systemImage: "calendar") }
                    .accessibilityIdentifier("trip-all-days")
            }
            Section {
                Text(TripSavedLine.words(refreshedAt: store.refreshedAt, online: network.online, queued: queue.count(for: tripId)))
            }
        } label: {
            Image(systemName: network.online ? "ellipsis.circle" : "wifi.slash")
                .accessibilityLabel(network.online ? "More" : "More — offline, using the saved plan")
        }
        .accessibilityIdentifier("trip-more")
        .confirmationDialog("Download on mobile data?", isPresented: $askCellular, titleVisibility: .visible) {
            Button("Download now") { start() }
            Button("Wait for Wi-Fi", role: .cancel) {}
        } message: {
            Text("A day's map is usually a few megabytes.")
        }
    }

    @ViewBuilder
    private var mapItem: some View {
        switch maps.state(for: id) {
        case .none, .failed:
            Button {
                if network.unmetered { start() } else { askCellular = true }
            } label: { Label("Save this day's map offline", systemImage: "arrow.down.circle") }
                .disabled(!network.online || SRDemo.isOn)
                .accessibilityIdentifier("trip-map-download")
        case .downloading(let p):
            Button {} label: { Label("Saving the map… \(Int((p * 100).rounded())) %", systemImage: "arrow.down.circle.dotted") }
                .disabled(true)
        case .ready(let bytes):
            Button(role: .destructive) { maps.delete(id) } label: {
                Label("Remove the offline map (\(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)))", systemImage: "checkmark.circle")
            }
        }
    }

    private func start() {
        maps.download(id: id, name: "\(tripTitle) · \(day.date)", line: TripDayGeometry.corridorLine(day))
    }
}

/// "Make the whole trip work offline": every day's map in one go, before
/// leaving — rather than a download on each day, found one day at a time.
/// The same packs as the day's menu (`TripDayMoreMenu`), so either shows the other's work.
struct TripOfflineRow: View {
    let tripId: String
    let title: String
    let days: [PlannedDay]
    @ObservedObject private var maps = OfflineMaps.shared
    @ObservedObject private var network = TripNetwork.shared
    @State private var askCellular = false

    /// Days with somewhere on them to download.
    private var mapped: [PlannedDay] { days.filter { !TripDayGeometry.corridorLine($0).isEmpty } }
    private func id(_ day: PlannedDay) -> String { TripDayGeometry.packId(trip: tripId, date: day.date) }
    private var states: [OfflineMaps.State] { mapped.map { maps.state(for: id($0)) } }

    private var readyCount: Int {
        states.filter { state in
            if case .ready = state { return true } else { return false }
        }.count
    }

    private var downloadingCount: Int {
        states.filter { state in
            if case .downloading = state { return true } else { return false }
        }.count
    }

    private var bytes: UInt64 {
        states.reduce(UInt64(0)) { total, state in
            if case .ready(let b) = state { return total + b } else { return total }
        }
    }

    private var allReady: Bool { !mapped.isEmpty && readyCount == mapped.count }

    var body: some View {
        if !mapped.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: allReady ? "checkmark.circle.fill" : "map")
                    .foregroundStyle(allReady ? SR.good : SR.accent)
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
                Text("A day's map is usually a few megabytes; this trip has \(mapped.count).")
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("trip-offline-all")
        }
    }

    @ViewBuilder
    private var action: some View {
        if downloadingCount > 0 {
            ProgressView().tint(SR.accent)
        } else if allReady {
            Button("Remove") { mapped.forEach { maps.delete(id($0)) } }
                .font(SR.Text.label())
                .foregroundStyle(SR.inkMuted)
        } else {
            Button {
                SRHaptic.tap()
                if network.unmetered { start() } else { askCellular = true }
            } label: { TripButtonLabel(readyCount > 0 ? "The rest" : "Download", icon: "arrow.down.circle") }
                .srButton(.regular)
                .disabled(!network.online || SRDemo.isOn)
        }
    }

    private var headline: String {
        if allReady { return "The whole trip works offline" }
        if downloadingCount > 0 { return "Downloading the trip's maps…" }
        return "Make the whole trip work offline"
    }

    private var detail: String {
        if allReady { return "\(mapped.count) days · \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))" }
        if downloadingCount > 0 { return "\(readyCount) of \(mapped.count) days done. Keep the app open until it finishes." }
        if !network.online { return "Needs a connection — the plan itself is already saved." }
        let done = readyCount > 0 ? "\(readyCount) of \(mapped.count) days saved. " : ""
        return done + "Every day's map, before you go — best on Wi-Fi."
    }

    private func start() {
        for day in mapped {
            switch maps.state(for: id(day)) {
            case .ready, .downloading: continue
            default: maps.download(id: id(day), name: "\(title) · \(day.date)", line: TripDayGeometry.corridorLine(day))
            }
        }
    }
}
