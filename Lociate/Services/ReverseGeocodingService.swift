import CoreLocation
import Foundation

@Observable
final class ReverseGeocodingService {
    // MARK: - Properties

    private let geocoder = CLGeocoder()
    private var cache: [String: String] = [:]
    private var pendingRequests: [String: Task<String?, Error>] = [:]

    // MARK: - Public API

    func reverseGeocode(_ coordinate: CLLocationCoordinate2D) async throws -> String? {
        let cacheKey = Self.cacheKey(for: coordinate)

        if let cached = cache[cacheKey] {
            return cached
        }

        if let pending = pendingRequests[cacheKey] {
            return try await pending.value
        }

        let task = Task<String?, Error> {
            defer { pendingRequests.removeValue(forKey: cacheKey) }

            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let placemarks = try await geocodeWithRetry(location: location)

            guard let placemark = placemarks.first else { return nil }

            let placeName = Self.formatPlaceName(from: placemark)

            if let placeName {
                cache[cacheKey] = placeName
            }

            return placeName
        }

        pendingRequests[cacheKey] = task
        return try await task.value
    }

    func clearCache() {
        cache.removeAll()
    }

    // MARK: - Private Helpers

    private func geocodeWithRetry(location: CLLocation, attempts: Int = 3) async throws -> [CLPlacemark] {
        for attempt in 1...attempts {
            do {
                return try await geocoder.reverseGeocodeLocation(location)
            } catch let error as CLError where error.code == .network && attempt < attempts {
                try await Task.sleep(for: .seconds(Double(attempt)))
            }
        }
        return try await geocoder.reverseGeocodeLocation(location)
    }

    static func formatPlaceName(from placemark: CLPlacemark) -> String? {
        if let name = placemark.name,
           name != placemark.thoroughfare,
           name != placemark.subThoroughfare {
            if let thoroughfare = placemark.thoroughfare {
                return "\(name), \(thoroughfare)"
            }
            return name
        }

        if let thoroughfare = placemark.thoroughfare {
            if let subThoroughfare = placemark.subThoroughfare {
                return "\(subThoroughfare) \(thoroughfare)"
            }
            return thoroughfare
        }

        if let locality = placemark.locality {
            if let subLocality = placemark.subLocality {
                return "\(subLocality), \(locality)"
            }
            return locality
        }

        return placemark.administrativeArea
    }

    static func cacheKey(for coordinate: CLLocationCoordinate2D) -> String {
        let lat = (coordinate.latitude * 1000).rounded() / 1000
        let lon = (coordinate.longitude * 1000).rounded() / 1000
        return "\(lat),\(lon)"
    }
}
