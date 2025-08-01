// LocationManager.swift
import Foundation
import CoreLocation
import Combine // Import Combine for @Published

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager() // Singleton

    private let locationManager = CLLocationManager()

    @Published var lastKnownLocation: CLLocationCoordinate2D?
    @Published var authorizationStatus: CLAuthorizationStatus // Corrected: This remains CLAuthorizationStatus

    // Cancellables to hold Combine subscriptions
    private var cancellables = Set<AnyCancellable>()

    override private init() {
        // Initialize authorizationStatus first, before calling super.init()
        self.authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyReduced // Good balance for general use
        // locationManager.distanceFilter = 100 // Update only after significant movement (e.g., 100 meters)

        // Subscribe to authorization status changes
        $authorizationStatus
            .sink { status in
                print("Location authorization status changed: \(status.rawValue)")
                // For macOS, `authorizedAlways` is the primary "allowed" status.
                // We'll also consider `.authorized` if it's explicitly available and means always.
                #if os(macOS)
                if status == .authorizedAlways {
                    self.locationManager.requestLocation()
                }
                #else // For iOS, watchOS, tvOS
                if status == .authorizedWhenInUse || status == .authorizedAlways {
                    self.locationManager.requestLocation()
                }
                #endif
            }
            .store(in: &cancellables)
    }

    func requestLocation() {
        // For macOS, requestAlwaysAuthorization() is typically used for "allow while app is in use"
        // as there isn't a direct "when in use" option like on iOS.
        // The user will be prompted with "Allow [Your App] to access your location?"
        locationManager.requestAlwaysAuthorization()

        // This is a one-time request for the current location.
        // It will call locationManager(_:didUpdateLocations:) once with the best available location.
        locationManager.requestLocation()
    }

    // Call this if you need continuous updates (e.g., for navigation, though less likely for this app)
    func startUpdatingLocation() {
        locationManager.startUpdatingLocation()
    }

    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Update the published authorization status when it changes
        authorizationStatus = manager.authorizationStatus

        // Handle macOS specific authorization checks
        #if os(macOS)
        switch manager.authorizationStatus {
        case .authorizedAlways: // This means location access is granted on macOS
            print("Location authorization granted on macOS.")
            // No need to call manager.requestLocation() here if you're using `requestLocation()`
            // which handles the initial request after authorization.
        case .denied, .restricted:
            print("Location authorization denied or restricted on macOS.")
            // Handle denied/restricted state, e.g., show an alert
        case .notDetermined:
            print("Location authorization not determined on macOS. Requesting...")
            // Requesting authorization happens in `requestLocation()`.
        @unknown default:
            fatalError("Unknown authorization status on macOS")
        }
        #else // For iOS, watchOS, tvOS
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            print("Location authorization granted on non-macOS.")
        case .denied, .restricted:
            print("Location authorization denied or restricted on non-macOS.")
        case .notDetermined:
            print("Location authorization not determined on non-macOS.")
        @unknown default:
            fatalError("Unknown authorization status on non-macOS")
        }
        #endif
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            print("Location updated: \(location.coordinate.latitude), \(location.coordinate.longitude)")
            // Publish the new location
            lastKnownLocation = location.coordinate
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clError = error as? CLError {
            if clError.code == .denied {
                print("Location access denied by user.")
            } else if clError.code == .locationUnknown {
                print("Location currently unavailable.")
            } else {
                print("Location manager failed with error: \(error.localizedDescription)")
            }
        } else {
            print("Location manager failed with error: \(error.localizedDescription)")
        }
    }
}
