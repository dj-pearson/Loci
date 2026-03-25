import CoreLocation
import Foundation

@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    // MARK: - Properties

    private(set) var currentLocation: CLLocation?
    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var locationError: LocationError?

    var isAuthorizedAlways: Bool {
        authorizationStatus == .authorizedAlways
    }

    var isAuthorizedWhenInUse: Bool {
        authorizationStatus == .authorizedWhenInUse
    }

    var isAuthorized: Bool {
        isAuthorizedAlways || isAuthorizedWhenInUse
    }

    var isDenied: Bool {
        authorizationStatus == .denied
    }

    var isRestricted: Bool {
        authorizationStatus == .restricted
    }

    private let locationManager: CLLocationManager

    // MARK: - Initialization

    override init() {
        locationManager = CLLocationManager()
        authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }

    // MARK: - Permission Requests

    func requestWhenInUsePermission() {
        guard authorizationStatus == .notDetermined else { return }
        locationManager.requestWhenInUseAuthorization()
    }

    func requestAlwaysPermission() {
        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            locationManager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        locationError = nil

        switch manager.authorizationStatus {
        case .denied:
            locationError = .denied
            locationManager.stopUpdatingLocation()
        case .restricted:
            locationError = .restricted
            locationManager.stopUpdatingLocation()
        case .authorizedWhenInUse, .authorizedAlways:
            locationError = nil
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                locationError = .denied
            case .locationUnknown:
                locationError = .locationUnavailable
            default:
                locationError = .unknown(clError.localizedDescription)
            }
        }
    }

    // MARK: - Error Types

    enum LocationError: Equatable {
        case denied
        case restricted
        case locationUnavailable
        case unknown(String)

        var localizedDescription: String {
            switch self {
            case .denied:
                String(localized: "Location access has been denied. Please enable it in Settings to use Loci.")
            case .restricted:
                String(localized: "Location access is restricted on this device.")
            case .locationUnavailable:
                String(localized: "Unable to determine your location. Please try again.")
            case .unknown(let message):
                message
            }
        }
    }
}
