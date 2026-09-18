import CoreLocation
import MapKit
import Observation

/// One-shot "where am I" for the tournament search: the device location
/// (When-In-Use) reverse-geocoded to a city the US Chess search understands
/// ("Somerville, NJ"). Users can also type a city or ZIP instead.
@MainActor
@Observable
final class LocationProvider {
    enum Status: Equatable {
        case idle
        case locating
        case located
        case denied
        case failed(String)
    }

    private(set) var status: Status = .idle
    /// City name or ZIP used as the search origin.
    private(set) var origin: String?
    /// Device coordinate, when the origin came from GPS (for distances).
    private(set) var coordinate: CLLocationCoordinate2D?

    /// Mock mode uses a fixed synthetic location and never prompts.
    private let mock: Bool

    init(mock: Bool) {
        self.mock = mock
    }

    func useCurrentLocation() async {
        if mock {
            origin = "Somerville, NJ"
            coordinate = CLLocationCoordinate2D(latitude: 40.5743, longitude: -74.6099)
            status = .located
            return
        }
        status = .locating
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if update.authorizationDenied || update.authorizationDeniedGlobally {
                    status = .denied
                    return
                }
                guard let location = update.location else { continue }
                coordinate = location.coordinate
                origin = try await cityName(for: location) ?? String(format: "%.4f, %.4f",
                                                                    location.coordinate.latitude,
                                                                    location.coordinate.longitude)
                status = .located
                return
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// A city or ZIP the user typed.
    func useManual(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        origin = trimmed
        coordinate = nil
        status = .located
    }

    private func cityName(for location: CLLocation) async throws -> String? {
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        let items = try await request.mapItems
        return items.first?.addressRepresentations?.cityWithContext
    }
}
