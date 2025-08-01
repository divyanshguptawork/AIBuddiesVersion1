import Foundation
import CoreLocation // Import CoreLocation for location services

// MARK: - BuddyChatManager
// Manages chat interactions, routing user input to the appropriate AI logic.
class BuddyChatManager: NSObject { // Inherit from NSObject for CLLocationManagerDelegate
    static let shared = BuddyChatManager() // Singleton instance

    // MARK: - Properties

    // Assuming BuddyModel.allBuddies is the source of truth for buddy details
    private func getBuddy(by id: String) -> BuddyModel? {
        return BuddyModel.allBuddies.first { $0.id == id }
    }

    // Location Manager to get user's current location for satellite flyovers
    private let locationManager = CLLocationManager()
    private var lastKnownLocation: CLLocation?

    // MARK: - Initialization

    private override init() {
        super.init()
        // Configure Location Manager
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        // Request authorization when the app is in use
        locationManager.requestWhenInUseAuthorization()
        // Start updating location
        locationManager.startUpdatingLocation()
        print("BuddyChatManager: Location services initialized and started.")
    }

    // MARK: - User Input Handling

    /// This method will be called whenever a user sends a message to any buddy.
    /// It routes the input to the AIReactionEngine for processing.
    /// - Parameters:
    ///   - message: The user's input message.
    ///   - buddyID: The ID of the buddy the message is sent to.
    func handleUserInput(_ message: String, buddyID: String) {
        // Retrieve buddy details from BuddyModel.allBuddies
        guard let selectedBuddy = getBuddy(by: buddyID) else {
            print("BuddyChatManager: Error: Buddy not found for ID \(buddyID)")
            BuddyMessenger.shared.post(to: buddyID, message: "I'm sorry, I don't know that buddy. Please select a valid buddy.")
            return
        }

        // Record the user message in the central history manager immediately
        let userChatMessage = ChatMessage(role: "user", text: message)
        MessageHistoryManager.shared.recordMessage(for: buddyID, message: userChatMessage)
        
        // Pass the user input to AIReactionEngine for comprehensive handling
        // AIReactionEngine will now determine intent (general chat, news, satellite, etc.)
        // and generate the appropriate response.
        AIReactionEngine.shared.handleUserChat(
            buddyID: buddyID,
            buddyName: selectedBuddy.name,
            personality: selectedBuddy.safePersonality, // Use safePersonality
            userInput: message,
            userLocation: lastKnownLocation?.coordinate // Pass the current location
        ) { response in
            // The AIReactionEngine already records its response in MessageHistoryManager.
            // BuddyMessenger is used to post the message back to the UI.
            BuddyMessenger.shared.post(to: buddyID, message: response)
        }
    }
}

// MARK: - CLLocationManagerDelegate
extension BuddyChatManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            self.lastKnownLocation = location
            // print("BuddyChatManager: Location updated to: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                print("BuddyChatManager: Location access denied by user.")
                // Optionally inform the user that location-dependent features might not work
                // BuddyMessenger.shared.post(to: "cosmicscout", message: "Cosmic Scout: To tell you about satellite flyovers, I need location access! Please enable it in Settings.")
            case .locationUnknown:
                print("BuddyChatManager: Location unknown, trying again.")
            case .network:
                print("BuddyChatManager: Location network error: \(error.localizedDescription)")
            default:
                print("BuddyChatManager: Location Manager failed with error: \(error.localizedDescription)")
            }
        } else {
            print("BuddyChatManager: Location Manager failed with error: \(error.localizedDescription)")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            print("BuddyChatManager: Location authorization granted.")
            manager.startUpdatingLocation()
        case .denied, .restricted:
            print("BuddyChatManager: Location authorization denied or restricted.")
        case .notDetermined:
            print("BuddyChatManager: Location authorization not determined.")
        @unknown default:
            print("BuddyChatManager: Unknown location authorization status.")
        }
    }
}
