import Foundation
import CoreLocation
import Observation

/// Minimal when-in-use location helper for "near me".
@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    @ObservationIgnored private let manager: CLLocationManager
    var authorization: CLAuthorizationStatus
    var lastLocation: CLLocation?

    override init() {
        let locationManager = CLLocationManager()
        self.manager = locationManager
        self.authorization = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
    }

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    func request() {
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if isAuthorized {
            manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if isAuthorized {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
