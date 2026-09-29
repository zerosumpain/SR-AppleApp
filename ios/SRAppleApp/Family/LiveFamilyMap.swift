import SwiftUI
import MapKit

/// MapKit animates actual annotation coordinates between received fixes. No
/// extrapolation: when updates stop, the marker stops at its last observation.
struct LiveFamilyMap: UIViewRepresentable {
    let people: [FamilyPerson]
    let showTrails: Bool
    @Binding var following: String?
    let recenter: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = true
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "person")
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        let positioned = people.filter { $0.position != nil }
        let ids = Set(positioned.map(\.subject))
        for (id, annotation) in coordinator.annotations where !ids.contains(id) {
            map.removeAnnotation(annotation)
            coordinator.annotations.removeValue(forKey: id)
        }
        for person in positioned {
            guard let position = person.position else { continue }
            let point: PersonAnnotation
            if let existing = coordinator.annotations[person.subject] {
                point = existing
                guard point.observedAt <= position.at else { continue }
                let distance = CLLocation(latitude: point.coordinate.latitude, longitude: point.coordinate.longitude)
                    .distance(from: CLLocation(latitude: position.lat, longitude: position.lon))
                // A large discontinuity is a new observation, not a journey.
                let duration = reduceMotion || distance > 250 ? 0 : 1.0
                UIView.animate(withDuration: duration, delay: 0, options: [.beginFromCurrentState, .curveLinear]) {
                    point.coordinate = position.coordinate
                }
            } else {
                point = PersonAnnotation(subject: person.subject, coordinate: position.coordinate)
                coordinator.annotations[person.subject] = point
                map.addAnnotation(point)
            }
            point.title = person.name
            point.subtitle = person.line
            point.observedAt = position.at
            point.initial = person.initial
            if let marker = map.view(for: point) as? MKMarkerAnnotationView { coordinator.style(marker, point) }
        }
        if let subject = following, let target = coordinator.annotations[subject] {
            let changed = coordinator.followed != subject
            if changed {
                map.setRegion(MKCoordinateRegion(center: target.coordinate, latitudinalMeters: 800, longitudinalMeters: 800), animated: !reduceMotion)
            } else { map.setCenter(target.coordinate, animated: !reduceMotion) }
        } else if !coordinator.fitted || coordinator.recenter != recenter {
            if !coordinator.annotations.isEmpty {
                map.showAnnotations(Array(coordinator.annotations.values), animated: coordinator.fitted && !reduceMotion)
                coordinator.fitted = true
            }
        }
        coordinator.followed = following
        coordinator.recenter = recenter
        // History only changes on the slower household refresh. Live positions
        // never recreate the route overlays or imply unseen route segments.
        let trails = showTrails ? people.flatMap { $0.today?.segments() ?? [] } : []
        let trailKey = trails.map { $0.map { "\($0.latitude),\($0.longitude)" }.joined(separator: ";") }.joined(separator: "|")
        if coordinator.trailKey != trailKey {
            map.removeOverlays(map.overlays)
            for coordinates in trails { map.addOverlay(MKPolyline(coordinates: coordinates, count: coordinates.count)) }
            coordinator.trailKey = trailKey
        }
    }

    final class PersonAnnotation: MKPointAnnotation {
        let subject: String
        var observedAt = ""
        var initial = ""
        init(subject: String, coordinate: CLLocationCoordinate2D) {
            self.subject = subject
            super.init()
            self.coordinate = coordinate
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: LiveFamilyMap
        var annotations: [String: PersonAnnotation] = [:]
        var fitted = false
        var recenter = 0
        var followed: String?
        var trailKey = ""
        init(_ parent: LiveFamilyMap) { self.parent = parent }
        func style(_ marker: MKMarkerAnnotationView, _ point: PersonAnnotation) {
            marker.glyphText = point.initial
            marker.markerTintColor = UIColor(point.subject == parent.following ? SR.accent : SR.ink)
            marker.accessibilityLabel = "\(point.title ?? "Family member"), last GPS fix \(point.observedAt)"
        }
        func mapView(_ map: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let point = annotation as? PersonAnnotation else { return nil }
            let marker = map.dequeueReusableAnnotationView(withIdentifier: "person", for: point) as! MKMarkerAnnotationView
            marker.canShowCallout = true
            marker.displayPriority = .required
            style(marker, point)
            return marker
        }
        func mapView(_ map: MKMapView, didSelect view: MKAnnotationView) {
            guard let point = view.annotation as? PersonAnnotation else { return }
            parent.following = point.subject
        }
        func mapView(_ map: MKMapView, regionWillChangeAnimated animated: Bool) {
            let gestures = map.subviews.flatMap { $0.gestureRecognizers ?? [] }
            if gestures.contains(where: { $0.state == .began || $0.state == .changed }) {
                // A pan hands control back to the reader. Follow can be restored
                // by selecting a person or using the menu.
                DispatchQueue.main.async { self.parent.following = nil }
            }
        }
        func mapView(_ map: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.strokeColor = UIColor(SR.accent)
            renderer.lineWidth = 3
            return renderer
        }
    }
}
