import SwiftUI
import MapLibre

// The route map that works with no signal.
//
// Apple's `Map` cannot draw tiles it did not fetch itself, so a route taken
// offline is drawn by MapLibre instead, on OpenFreeMap's vector tiles — free,
// keyless, and downloadable as a pack (`OfflineMaps`). A pack lives in the
// same store MapLibre reads every tile through, so nothing here knows whether
// it is online: with a pack it draws, without one and without signal it is a
// blank ground under the route line, which still tells you which way to go.
//
// Only the route screens use it; every other map stays on MapKit.

enum SRMapStyle {
    /// OpenFreeMap's Liberty style. Attribution ("OpenFreeMap © OpenMapTiles
    /// Data from OpenStreetMap") is MapLibre's own ornament and stays on —
    /// a licence term, like Mapbox's on the web.
    static let url = URL(string: "https://tiles.openfreemap.org/styles/liberty")!
}

struct SRRouteMap: UIViewRepresentable {
    let route: [CLLocationCoordinate2D]
    var walked: [CLLocationCoordinate2D] = []
    /// Follow the phone's position (walking) or frame the whole route (reading).
    var followsUser = false
    var interactive = true
    /// Drawn instead of the system blue dot — the demo has no GPS.
    var marker: CLLocationCoordinate2D?

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
        map.showsUserLocation = followsUser && !SRDemo.isOn
        if followsUser && !SRDemo.isOn { map.userTrackingMode = .follow }
        context.coordinator.apply(self, to: map, framing: true)
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        context.coordinator.apply(self, to: map, framing: false)
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        private var latest: SRRouteMap?
        private var framed = false

        func apply(_ spec: SRRouteMap, to map: MLNMapView, framing: Bool) {
            latest = spec
            guard let style = map.style else { return }
            draw(spec, on: style)
            if !framed || framing { frame(spec, map) }
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            guard let spec = latest else { return }
            draw(spec, on: style)
            frame(spec, mapView)
        }

        private func frame(_ spec: SRRouteMap, _ map: MLNMapView) {
            guard !spec.route.isEmpty, map.bounds.width > 0 else { return }
            framed = true
            if spec.followsUser && !SRDemo.isOn { return }
            let lats = spec.route.map(\.latitude), lngs = spec.route.map(\.longitude)
            let bounds = MLNCoordinateBounds(
                sw: CLLocationCoordinate2D(latitude: lats.min()!, longitude: lngs.min()!),
                ne: CLLocationCoordinate2D(latitude: lats.max()!, longitude: lngs.max()!)
            )
            map.setVisibleCoordinateBounds(
                bounds, edgePadding: UIEdgeInsets(top: 40, left: 30, bottom: 40, right: 30), animated: false, completionHandler: nil
            )
        }

        private func draw(_ spec: SRRouteMap, on style: MLNStyle) {
            line("sr-route", spec.route, color: UIColor(SR.accent), width: 5, on: style)
            line("sr-walked", spec.walked, color: UIColor(SR.ink), width: 3, on: style)
            point("sr-start", spec.route.first, color: UIColor(SR.good), radius: 6, on: style)
            point("sr-marker", spec.marker, color: .systemBlue, radius: 8, on: style)
        }

        private func line(_ id: String, _ coords: [CLLocationCoordinate2D], color: UIColor, width: Double, on style: MLNStyle) {
            var points = coords
            let shape: MLNShape = points.count > 1
                ? MLNPolylineFeature(coordinates: &points, count: UInt(points.count))
                : MLNShapeCollectionFeature(shapes: [])
            if let source = style.source(withIdentifier: id) as? MLNShapeSource {
                source.shape = shape
                return
            }
            let source = MLNShapeSource(identifier: id, shape: shape, options: nil)
            style.addSource(source)
            let layer = MLNLineStyleLayer(identifier: id, source: source)
            layer.lineColor = NSExpression(forConstantValue: color)
            layer.lineWidth = NSExpression(forConstantValue: width)
            layer.lineCap = NSExpression(forConstantValue: "round")
            layer.lineJoin = NSExpression(forConstantValue: "round")
            style.addLayer(layer)
        }

        private func point(_ id: String, _ at: CLLocationCoordinate2D?, color: UIColor, radius: Double, on style: MLNStyle) {
            let shape: MLNShape
            if let at {
                let feature = MLNPointFeature()
                feature.coordinate = at
                shape = feature
            } else {
                shape = MLNShapeCollectionFeature(shapes: [])
            }
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
