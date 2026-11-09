import CoreLocation
import AeroSpatialCore

@MainActor
final class PilotLocationService: NSObject, CLLocationManagerDelegate {
    var onUpdate: ((GeoPoint?, Double?) -> Void)?
    var onStatus: ((String) -> Void)?
    private let manager = CLLocationManager()
    private var position: GeoPoint?
    private var heading: Double?
    private(set) var lastPositionUptime: TimeInterval?
    private(set) var lastHeadingUptime: TimeInterval?
    private(set) var headingAccuracyDegrees: Double?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.headingFilter = 5
    }

    func start() {
        guard CLLocationManager.locationServicesEnabled() else {
            onStatus?("Location services are disabled.")
            return
        }
        manager.requestWhenInUseAuthorization()
        refreshPermission()
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    private func refreshPermission() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
        case .restricted, .denied:
            onStatus?("Location permission denied. Relative position cues are unavailable.")
        default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refreshPermission()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy > 0,
              location.horizontalAccuracy <= 100 else { return }
        lastPositionUptime = ProcessInfo.processInfo.systemUptime
        position = GeoPoint(latitude: location.coordinate.latitude,
                            longitude: location.coordinate.longitude)
        onUpdate?(position, heading)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        guard newHeading.trueHeading >= 0 else {
            heading = nil
            headingAccuracyDegrees = nil
            lastHeadingUptime = nil
            onStatus?("True-north heading unavailable. Geographic audio alignment is disabled.")
            onUpdate?(position, nil)
            return
        }
        heading = newHeading.trueHeading
        lastHeadingUptime = ProcessInfo.processInfo.systemUptime
        headingAccuracyDegrees = newHeading.headingAccuracy
        onUpdate?(position, heading)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        onStatus?("Location: \(error.localizedDescription)")
    }
}
