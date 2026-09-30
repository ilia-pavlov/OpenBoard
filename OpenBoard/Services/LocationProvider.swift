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

    /// Give up on GPS after this long: with no fix (indoors, simulator without a
    /// location) `liveUpdates()` never delivers one, and the row would say
    /// "Finding your location…" forever.
    private static let timeout: Duration = .seconds(12)

    private enum Saved {
        static let origin = "location.origin"
        static let latitude = "location.latitude"
        static let longitude = "location.longitude"
    }

    init(mock: Bool) {
        self.mock = mock
        // The last location the user searched from is the default next launch,
        // so Near me is ready without waiting for GPS or a prompt.
        let defaults = UserDefaults.standard
        if !mock, let saved = defaults.string(forKey: Saved.origin) {
            origin = saved
            if defaults.object(forKey: Saved.latitude) != nil {
                coordinate = CLLocationCoordinate2D(latitude: defaults.double(forKey: Saved.latitude),
                                                    longitude: defaults.double(forKey: Saved.longitude))
            }
            status = .located
        }
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
        let outcome = await withTaskGroup(of: Outcome.self) { group in
            group.addTask { await Self.firstFix() }
            group.addTask {
                try? await Task.sleep(for: Self.timeout)
                return .timedOut
            }
            let first = await group.next() ?? .timedOut
            group.cancelAll()
            return first
        }
        switch outcome {
        case .located(let location):
            let city = try? await cityName(for: location)
            save(origin: city ?? String(format: "%.4f, %.4f", location.coordinate.latitude, location.coordinate.longitude),
                 coordinate: location.coordinate)
        case .denied:
            status = .denied
        case .failed(let message):
            status = .failed(message)
        case .timedOut:
            // Keep a location found earlier; otherwise ask for a city or ZIP.
            status = origin == nil ? .failed(String(localized: "Couldn't find your location.")) : .located
        }
    }

    private enum Outcome: Sendable {
        case located(CLLocation)
        case denied
        case failed(String)
        case timedOut
    }

    /// The first usable location, or why there won't be one.
    private nonisolated static func firstFix() async -> Outcome {
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if update.authorizationDenied || update.authorizationDeniedGlobally { return .denied }
                if let location = update.location { return .located(location) }
            }
            return .failed(String(localized: "Couldn't find your location."))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// A city or ZIP the user typed.
    func useManual(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        save(origin: trimmed, coordinate: nil)
    }

    private func save(origin: String, coordinate: CLLocationCoordinate2D?) {
        self.origin = origin
        self.coordinate = coordinate
        status = .located
        guard !mock else { return }
        let defaults = UserDefaults.standard
        defaults.set(origin, forKey: Saved.origin)
        if let coordinate {
            defaults.set(coordinate.latitude, forKey: Saved.latitude)
            defaults.set(coordinate.longitude, forKey: Saved.longitude)
        } else {
            defaults.removeObject(forKey: Saved.latitude)
            defaults.removeObject(forKey: Saved.longitude)
        }
    }

    private func cityName(for location: CLLocation) async throws -> String? {
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        let items = try await request.mapItems
        return items.first?.addressRepresentations?.cityWithContext
    }
}
