import SwiftUI
import MapLibre

/// Manhunt's map: the play area's circle and the dots this phone may see.
///
/// MapLibre on OpenFreeMap, like the route maps (`SRRouteMap`, same style
/// URL), so the game reads the same streets the family's trails do. It draws
/// only what the server sent this phone (`ManhuntState.marks`) — the runner's
/// phone never holds a hunter's live position, so it cannot draw one.
///
/// Framed once on the circle; after that the player pans and zooms freely.
struct ManhuntMap: UIViewRepresentable {
    let area: ManhuntArea?
    let marks: [ManhuntMark]
    var interactive = true

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

    final class Coordinator: NSObject, MLNMapViewDelegate {
        private var latest: ManhuntMap?
        private var framedOn: ManhuntArea?

        func apply(_ spec: ManhuntMap, to map: MLNMapView) {
            latest = spec
            guard let style = map.style else { return }
            draw(spec, on: style)
            frame(spec, map)
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            guard let spec = latest else { return }
            draw(spec, on: style)
            frame(spec, mapView)
        }

        private func frame(_ spec: ManhuntMap, _ map: MLNMapView) {
            guard let area = spec.area, area != framedOn, map.bounds.width > 0 else { return }
            framedOn = area
            let ring = ManhuntRules.circle(centre: area.centre, radiusM: area.radiusM, points: 16)
            guard !ring.isEmpty else { return }
            let lats = ring.map(\.latitude), lngs = ring.map(\.longitude)
            let bounds = MLNCoordinateBounds(
                sw: CLLocationCoordinate2D(latitude: lats.min()!, longitude: lngs.min()!),
                ne: CLLocationCoordinate2D(latitude: lats.max()!, longitude: lngs.max()!)
            )
            map.setVisibleCoordinateBounds(
                bounds, edgePadding: UIEdgeInsets(top: 24, left: 16, bottom: 24, right: 16), animated: false, completionHandler: nil
            )
        }

        private func draw(_ spec: ManhuntMap, on style: MLNStyle) {
            boundary(spec.area, on: style)
            dots("mh-hunter-ping", spec.marks.filter { $0.kind == .hunterPing }, color: UIColor(hex: SR.Fixed.warn), radius: 7, on: style)
            dots("mh-runner-ping", spec.marks.filter { $0.kind == .runnerPing }, color: UIColor(hex: SR.Fixed.accent), radius: 9, on: style)
            dots("mh-hunter", spec.marks.filter { $0.kind == .hunter }, color: UIColor(hex: SR.Fixed.accentInk), radius: 7, on: style)
            dots("mh-runner-live", spec.marks.filter { $0.kind == .runnerLive }, color: UIColor(hex: SR.Fixed.error), radius: 9, on: style)
            dots("mh-me", spec.marks.filter { $0.kind == .me }, color: .systemBlue, radius: 8, on: style)
        }

        private func boundary(_ area: ManhuntArea?, on style: MLNStyle) {
            let id = "mh-area"
            var ring = area.map { ManhuntRules.circle(centre: $0.centre, radiusM: $0.radiusM) } ?? []
            let shape: MLNShape = ring.count > 3
                ? MLNPolygonFeature(coordinates: &ring, count: UInt(ring.count))
                : MLNShapeCollectionFeature(shapes: [])
            if let source = style.source(withIdentifier: id) as? MLNShapeSource {
                source.shape = shape
                return
            }
            let source = MLNShapeSource(identifier: id, shape: shape, options: nil)
            style.addSource(source)
            let fill = MLNFillStyleLayer(identifier: id + "-fill", source: source)
            fill.fillColor = NSExpression(forConstantValue: UIColor(hex: SR.Fixed.good))
            fill.fillOpacity = NSExpression(forConstantValue: 0.10)
            style.addLayer(fill)
            let edge = MLNLineStyleLayer(identifier: id + "-edge", source: source)
            edge.lineColor = NSExpression(forConstantValue: UIColor(hex: SR.Fixed.good))
            edge.lineWidth = NSExpression(forConstantValue: 3)
            edge.lineDashPattern = NSExpression(forConstantValue: [2, 1.5])
            style.addLayer(edge)
        }

        private func dots(_ id: String, _ marks: [ManhuntMark], color: UIColor, radius: Double, on style: MLNStyle) {
            let features: [MLNPointFeature] = marks.map { mark in
                let feature = MLNPointFeature()
                feature.coordinate = mark.fix.coordinate
                return feature
            }
            let shape = MLNShapeCollectionFeature(shapes: features)
            if let source = style.source(withIdentifier: id) as? MLNShapeSource {
                source.shape = shape
                return
            }
            let source = MLNShapeSource(identifier: id, shape: shape, options: nil)
            style.addSource(source)
            let layer = MLNCircleStyleLayer(identifier: id, source: source)
            layer.circleColor = NSExpression(forConstantValue: color)
            layer.circleRadius = NSExpression(forConstantValue: radius)
            layer.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
            layer.circleStrokeWidth = NSExpression(forConstantValue: 2.5)
            style.addLayer(layer)
        }
    }
}
