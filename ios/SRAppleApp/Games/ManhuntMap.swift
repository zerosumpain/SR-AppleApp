import SwiftUI
import UIKit
import MapLibre

/// Manhunt's map: the play area's circle and the dots this phone may see.
///
/// MapLibre on OpenFreeMap, like the route maps (`SRRouteMap`, same style
/// URL), so the game reads the same streets the family's trails do. It draws
/// only what the server sent this phone (`ManhuntState.marks`) — the runner's
/// phone never holds a hunter's live position, so it cannot draw one.
///
/// The art, bottom to top: the world outside the circle dimmed (out of
/// bounds reads at a glance), the circle's dashed edge, the runner's earlier
/// pings as a fading trail (a hunter's phone), my catch reach as a ring round
/// my own dot, a soft halo under the runner, then the pins — each a disc
/// drawn once per kind and initial, with the runner's a running figure.
///
/// Framed once on the circle; after that the player pans and zooms freely,
/// and `recentre` going up frames the circle again. A redraw with nothing
/// new to show is skipped, so the map does no work on a clock tick.
struct ManhuntMap: UIViewRepresentable {
    let area: ManhuntArea?
    let marks: [ManhuntMark]
    var interactive = true
    /// The runner's earlier pings, oldest first (a hunter's phone): the trail.
    var trail: [ManhuntFix] = []
    /// A ring this many metres round my own dot: how close a catch must be.
    var reachM: Double? = nil
    /// Bumped to frame the circle again after the player has panned away.
    var recentre: Int = 0

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero, styleURL: SRMapStyle.url)
        map.delegate = context.coordinator
        map.logoView.isHidden = true
        map.compassView.compassVisibility = .adaptive
        map.isScrollEnabled = interactive
        map.isZoomEnabled = interactive
        map.isRotateEnabled = interactive
        map.isPitchEnabled = false
        // Our own dot for me, from the fix the game sent: the system's would
        // be a second, different position for the same phone.
        map.showsUserLocation = false
        context.coordinator.apply(self, to: map)
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        context.coordinator.apply(self, to: map)
    }

    /// Everything the map draws, so an unchanged frame can be skipped.
    struct Drawn: Equatable {
        let area: ManhuntArea?
        let marks: [ManhuntMark]
        let trail: [ManhuntFix]
        let reachM: Double?
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        private var latest: ManhuntMap?
        private var framedOn: ManhuntArea?
        private var framedToken = 0
        private var drawn: Drawn?

        func apply(_ spec: ManhuntMap, to map: MLNMapView) {
            latest = spec
            guard let style = map.style else { return }
            let next = Drawn(area: spec.area, marks: spec.marks, trail: spec.trail, reachM: spec.reachM)
            if next != drawn {
                drawn = next
                draw(spec, on: style)
            }
            frame(spec, map)
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            guard let spec = latest else { return }
            drawn = Drawn(area: spec.area, marks: spec.marks, trail: spec.trail, reachM: spec.reachM)
            draw(spec, on: style)
            frame(spec, mapView)
        }

        private func frame(_ spec: ManhuntMap, _ map: MLNMapView) {
            guard let area = spec.area, map.bounds.width > 0 else { return }
            let asked = spec.recentre != framedToken
            guard area != framedOn || asked else { return }
            let animated = framedOn != nil && asked
            framedOn = area
            framedToken = spec.recentre
            let ring = ManhuntRules.circle(centre: area.centre, radiusM: area.radiusM, points: 16)
            guard !ring.isEmpty else { return }
            let lats = ring.map(\.latitude), lngs = ring.map(\.longitude)
            let bounds = MLNCoordinateBounds(
                sw: CLLocationCoordinate2D(latitude: lats.min() ?? area.lat, longitude: lngs.min() ?? area.lng),
                ne: CLLocationCoordinate2D(latitude: lats.max() ?? area.lat, longitude: lngs.max() ?? area.lng)
            )
            map.setVisibleCoordinateBounds(
                bounds, edgePadding: UIEdgeInsets(top: 28, left: 18, bottom: 28, right: 18), animated: animated, completionHandler: nil
            )
        }

        private func draw(_ spec: ManhuntMap, on style: MLNStyle) {
            outside(spec.area, on: style)
            boundary(spec.area, on: style)
            trail(spec, on: style)
            reach(spec, on: style)
            halos("mh-halo-ping", spec.marks.filter { $0.kind == .runnerPing },
                  color: UIColor(hex: SR.Fixed.accent), radius: 24, opacity: 0.18, on: style)
            halos("mh-halo-live", spec.marks.filter { $0.kind == .runnerLive },
                  color: UIColor(hex: SR.Fixed.error), radius: 28, opacity: 0.24, on: style)
            pins("mh-hunter-ping", spec.marks.filter { $0.kind == .hunterPing }, on: style)
            pins("mh-hunter", spec.marks.filter { $0.kind == .hunter }, on: style)
            pins("mh-runner-ping", spec.marks.filter { $0.kind == .runnerPing }, on: style)
            pins("mh-runner-live", spec.marks.filter { $0.kind == .runnerLive }, on: style)
            pins("mh-me", spec.marks.filter { $0.kind == .me }, on: style)
        }

        /// A shape source by id: updated in place when it is there, or made
        /// (and handed back, so its layers can be added) when it is not.
        private func source(_ id: String, _ shape: MLNShape, on style: MLNStyle) -> MLNShapeSource? {
            if let existing = style.source(withIdentifier: id) as? MLNShapeSource {
                existing.shape = shape
                return nil
            }
            let made = MLNShapeSource(identifier: id, shape: shape, options: nil)
            style.addSource(made)
            return made
        }

        /// The world beyond the circle, dimmed: a box round the area with the
        /// circle cut out of it.
        private func outside(_ area: ManhuntArea?, on style: MLNStyle) {
            let id = "mh-outside"
            var shape: MLNShape = MLNShapeCollectionFeature(shapes: [])
            if let area {
                var hole = ManhuntRules.circle(centre: area.centre, radiusM: area.radiusM)
                if hole.count > 3 {
                    let span = max(0.05, area.radiusM / 111_195 * 12)
                    var box = [
                        CLLocationCoordinate2D(latitude: area.lat - span, longitude: area.lng - span * 2),
                        CLLocationCoordinate2D(latitude: area.lat - span, longitude: area.lng + span * 2),
                        CLLocationCoordinate2D(latitude: area.lat + span, longitude: area.lng + span * 2),
                        CLLocationCoordinate2D(latitude: area.lat + span, longitude: area.lng - span * 2),
                        CLLocationCoordinate2D(latitude: area.lat - span, longitude: area.lng - span * 2),
                    ]
                    let cut = MLNPolygon(coordinates: &hole, count: UInt(hole.count))
                    shape = MLNPolygonFeature(coordinates: &box, count: UInt(box.count), interiorPolygons: [cut])
                }
            }
            guard let made = source(id, shape, on: style) else { return }
            let fill = MLNFillStyleLayer(identifier: id + "-fill", source: made)
            fill.fillColor = NSExpression(forConstantValue: UIColor(hex: SR.Fixed.ink))
            fill.fillOpacity = NSExpression(forConstantValue: 0.16)
            style.addLayer(fill)
        }

        private func boundary(_ area: ManhuntArea?, on style: MLNStyle) {
            let id = "mh-area"
            var ring = area.map { ManhuntRules.circle(centre: $0.centre, radiusM: $0.radiusM) } ?? []
            let shape: MLNShape = ring.count > 3
                ? MLNPolygonFeature(coordinates: &ring, count: UInt(ring.count))
                : MLNShapeCollectionFeature(shapes: [])
            guard let made = source(id, shape, on: style) else { return }
            let fill = MLNFillStyleLayer(identifier: id + "-fill", source: made)
            fill.fillColor = NSExpression(forConstantValue: UIColor(hex: SR.Fixed.good))
            fill.fillOpacity = NSExpression(forConstantValue: 0.08)
            style.addLayer(fill)
            // A white casing under the dashes, so the edge reads on any street.
            let casing = MLNLineStyleLayer(identifier: id + "-casing", source: made)
            casing.lineColor = NSExpression(forConstantValue: UIColor.white)
            casing.lineWidth = NSExpression(forConstantValue: 6)
            casing.lineOpacity = NSExpression(forConstantValue: 0.7)
            style.addLayer(casing)
            let edge = MLNLineStyleLayer(identifier: id + "-edge", source: made)
            edge.lineColor = NSExpression(forConstantValue: UIColor(hex: SR.Fixed.good))
            edge.lineWidth = NSExpression(forConstantValue: 3.5)
            edge.lineDashPattern = NSExpression(forConstantValue: [2, 1.5])
            style.addLayer(edge)
        }

        /// Where the runner was at the pings before the last, joined up and
        /// fading: which way they are heading.
        private func trail(_ spec: ManhuntMap, on style: MLNStyle) {
            var points = spec.trail.map(\.coordinate)
            if let last = spec.marks.first(where: { $0.kind == .runnerPing }) { points.append(last.fix.coordinate) }
            let lineShape: MLNShape = points.count > 1
                ? MLNPolylineFeature(coordinates: &points, count: UInt(points.count))
                : MLNShapeCollectionFeature(shapes: [])
            if let made = source("mh-trail-line", lineShape, on: style) {
                let line = MLNLineStyleLayer(identifier: "mh-trail-line", source: made)
                line.lineColor = NSExpression(forConstantValue: UIColor(hex: SR.Fixed.accent))
                line.lineWidth = NSExpression(forConstantValue: 2.5)
                line.lineOpacity = NSExpression(forConstantValue: 0.55)
                line.lineDashPattern = NSExpression(forConstantValue: [1.5, 1.5])
                line.lineCap = NSExpression(forConstantValue: "round")
                style.addLayer(line)
            }
            let dots: [MLNPointFeature] = spec.trail.map { fix in
                let feature = MLNPointFeature()
                feature.coordinate = fix.coordinate
                return feature
            }
            if let made = source("mh-trail-dots", MLNShapeCollectionFeature(shapes: dots), on: style) {
                let layer = MLNCircleStyleLayer(identifier: "mh-trail-dots", source: made)
                layer.circleColor = NSExpression(forConstantValue: UIColor(hex: SR.Fixed.accent))
                layer.circleRadius = NSExpression(forConstantValue: 4.5)
                layer.circleOpacity = NSExpression(forConstantValue: 0.5)
                layer.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
                layer.circleStrokeWidth = NSExpression(forConstantValue: 1.5)
                layer.circleStrokeOpacity = NSExpression(forConstantValue: 0.7)
                style.addLayer(layer)
            }
        }

        /// My catch reach: a ring of `reachM` round my own dot.
        private func reach(_ spec: ManhuntMap, on style: MLNStyle) {
            let id = "mh-reach"
            var ring: [CLLocationCoordinate2D] = []
            if let m = spec.reachM, let me = spec.marks.first(where: { $0.kind == .me }) {
                ring = ManhuntRules.circle(centre: me.fix.coordinate, radiusM: m, points: 48)
            }
            let shape: MLNShape = ring.count > 3
                ? MLNPolygonFeature(coordinates: &ring, count: UInt(ring.count))
                : MLNShapeCollectionFeature(shapes: [])
            guard let made = source(id, shape, on: style) else { return }
            let fill = MLNFillStyleLayer(identifier: id + "-fill", source: made)
            fill.fillColor = NSExpression(forConstantValue: ManhuntPinArt.meColour)
            fill.fillOpacity = NSExpression(forConstantValue: 0.10)
            style.addLayer(fill)
            let edge = MLNLineStyleLayer(identifier: id + "-edge", source: made)
            edge.lineColor = NSExpression(forConstantValue: ManhuntPinArt.meColour)
            edge.lineWidth = NSExpression(forConstantValue: 1.5)
            edge.lineOpacity = NSExpression(forConstantValue: 0.6)
            style.addLayer(edge)
        }

        private func halos(_ id: String, _ marks: [ManhuntMark], color: UIColor, radius: Double, opacity: Double, on style: MLNStyle) {
            let features: [MLNPointFeature] = marks.map { mark in
                let feature = MLNPointFeature()
                feature.coordinate = mark.fix.coordinate
                return feature
            }
            guard let made = source(id, MLNShapeCollectionFeature(shapes: features), on: style) else { return }
            let layer = MLNCircleStyleLayer(identifier: id, source: made)
            layer.circleColor = NSExpression(forConstantValue: color)
            layer.circleRadius = NSExpression(forConstantValue: radius)
            layer.circleOpacity = NSExpression(forConstantValue: opacity)
            layer.circleStrokeColor = NSExpression(forConstantValue: color)
            layer.circleStrokeWidth = NSExpression(forConstantValue: 1.5)
            layer.circleStrokeOpacity = NSExpression(forConstantValue: min(1, opacity * 3))
            style.addLayer(layer)
        }

        /// Pins as one symbol layer per kind (so the runner and I always sit
        /// on top), each feature naming its drawn image.
        private func pins(_ id: String, _ marks: [ManhuntMark], on style: MLNStyle) {
            let features: [MLNPointFeature] = marks.map { mark in
                let name = ManhuntPinArt.name(mark)
                if style.image(forName: name) == nil { style.setImage(ManhuntPinArt.image(mark), forName: name) }
                let feature = MLNPointFeature()
                feature.coordinate = mark.fix.coordinate
                feature.attributes = ["icon": name]
                return feature
            }
            guard let made = source(id, MLNShapeCollectionFeature(shapes: features), on: style) else { return }
            let layer = MLNSymbolStyleLayer(identifier: id, source: made)
            layer.iconImageName = NSExpression(forKeyPath: "icon")
            layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
            layer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
            style.addLayer(layer)
        }
    }
}

/// A pin, drawn once per kind, colour and initial: a white-edged disc with a
/// soft shadow, the person's initial in it — or, for the runner, a running
/// figure, and for me a person on blue.
enum ManhuntPinArt {
    /// My own dot: the system's location blue, so "you" reads as it does in Maps.
    static let meHex: UInt32 = 0x2F80ED
    static var meColour: UIColor { UIColor(hex: meHex) }

    static func fill(_ kind: ManhuntMark.Kind) -> UInt32 {
        switch kind {
        case .me: return meHex
        case .hunter: return SR.Fixed.accentInk
        case .runnerPing: return SR.Fixed.accent
        case .runnerLive: return SR.Fixed.error
        case .hunterPing: return SR.Fixed.warn
        }
    }

    static func side(_ kind: ManhuntMark.Kind) -> CGFloat {
        switch kind {
        case .runnerLive, .runnerPing: return 34
        case .me: return 28
        case .hunter, .hunterPing: return 28
        }
    }

    static func initial(_ mark: ManhuntMark) -> String {
        String(mark.name.prefix(1)).uppercased()
    }

    static func name(_ mark: ManhuntMark) -> String {
        let glyph: String
        switch mark.kind {
        case .runnerLive, .runnerPing, .me: glyph = "sym"
        case .hunter, .hunterPing: glyph = initial(mark)
        }
        return "mh-pin-\(mark.kind.rawValue)-\(glyph)-\(String(fill(mark.kind), radix: 16))"
    }

    static func image(_ mark: ManhuntMark) -> UIImage {
        let d = side(mark.kind)
        let pad: CGFloat = 4
        let full = d + pad * 2
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let colour = UIColor(hex: fill(mark.kind))
        // A ping is where they WERE: its disc is ringed in a dashed edge.
        let isPing = mark.kind == .runnerPing || mark.kind == .hunterPing
        return UIGraphicsImageRenderer(size: CGSize(width: full, height: full), format: format).image { ctx in
            let c = ctx.cgContext
            let outer = CGRect(x: pad, y: pad, width: d, height: d)
            c.saveGState()
            c.setShadow(offset: CGSize(width: 0, height: 1.5), blur: 3, color: UIColor.black.withAlphaComponent(0.35).cgColor)
            UIColor.white.setFill()
            c.fillEllipse(in: outer)
            c.restoreGState()
            let disc = outer.insetBy(dx: 2.5, dy: 2.5)
            colour.setFill()
            c.fillEllipse(in: disc)
            if isPing {
                c.setStrokeColor(UIColor.white.withAlphaComponent(0.85).cgColor)
                c.setLineWidth(1.5)
                c.setLineDash(phase: 0, lengths: [3, 2.5])
                c.strokeEllipse(in: disc.insetBy(dx: 2.5, dy: 2.5))
                c.setLineDash(phase: 0, lengths: [])
            }
            switch mark.kind {
            case .runnerLive, .runnerPing:
                symbol("figure.run", in: disc, size: d * 0.5)
            case .me:
                symbol("person.fill", in: disc, size: d * 0.44)
            case .hunter, .hunterPing:
                let font = UIFont.systemFont(ofSize: d * 0.46, weight: .heavy)
                let text = initial(mark) as NSString
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
                let size = text.size(withAttributes: attributes)
                text.draw(at: CGPoint(x: disc.midX - size.width / 2, y: disc.midY - size.height / 2), withAttributes: attributes)
            }
        }
    }

    private static func symbol(_ name: String, in disc: CGRect, size: CGFloat) {
        let config = UIImage.SymbolConfiguration(pointSize: size, weight: .bold)
        guard let symbol = UIImage(systemName: name, withConfiguration: config)?
            .withTintColor(.white, renderingMode: .alwaysOriginal) else { return }
        let s = symbol.size
        symbol.draw(in: CGRect(x: disc.midX - s.width / 2, y: disc.midY - s.height / 2, width: s.width, height: s.height))
    }
}
