import Foundation
import AppAuth
import AppKit // For NSWindow

// Import the file where ServiceType and OAuthConfig are defined
// Assuming your OAuthConfig.swift is in the same module, no explicit import needed if public.
// If it's in a different module, you might need: import YourAppModuleName

private let kGmailAuthStateKey = "gmailAuthState"

// MARK: - OAuthError (DEFINED ONCE HERE)
enum OAuthError: Error, LocalizedError {
    case notAuthorized(String)
    case noDataReceived(String)
    case jsonDecodingError(Error)
    case invalidConfiguration(String)
    case apiError(String) // Generic API error from the server
    case requestFailed(statusCode: Int, message: String?) // Added for network request failures
    case tokenRefreshFailed(String) // Added for token refresh issues
    case jsonEncodingError(Error) // Added for JSON encoding issues (e.g., for Google Calendar)


    var errorDescription: String? {
        switch self {
        case .notAuthorized(let msg): return msg
        case .noDataReceived(let msg): return msg
        case .jsonDecodingError(let error): return "JSON Decoding Error: \(error.localizedDescription)"
        case .invalidConfiguration(let msg): return msg
        case .apiError(let msg): return "API Error: \(msg)"
        case .requestFailed(let statusCode, let message): return "Request Failed with status \(statusCode): \(message ?? "No detailed message.")"
        case .tokenRefreshFailed(let msg): return "Token Refresh Failed: \(msg)"
        case .jsonEncodingError(let error): return "JSON Encoding Error: \(error.localizedDescription)"
        }
    }
}


final class OAuthManager: ObservableObject { // Made final and conforms to ObservableObject
    static let shared = OAuthManager()

    @Published var gmailConnected = false
    @Published var slackConnected = false
    @Published var discordConnected = false

    private var currentAuthorizationFlow: OIDExternalUserAgentSession?

    internal var gmailAuthState: OIDAuthState? {
        didSet {
            // Ensure state updates are on the main thread for @Published
            DispatchQueue.main.async {
                self.gmailConnected = self.gmailAuthState != nil && self.gmailAuthState!.isAuthorized
            }
            self.saveAuthState()
        }
    }

    // Explicit private init to resolve "Ambiguous use of 'init()'"
    private init() {
        loadAuthState()
    }

    // MARK: - Connect/Disconnect Flow

    // Modified connect function to accept a presenting window
    func connect(to serviceType: ServiceType, presentingWindow: NSWindow?) {
        // Get the configuration directly from the ServiceType enum
        var config = serviceType.config // Get a mutable copy
        config.presentingWindow = presentingWindow // Set the presenting window for the flow

        startOAuthFlow(for: config)
    }

    func disconnect(from service: ServiceType) {
        switch service {
        case .gmail:
            gmailAuthState = nil
        case .slack, .discord:
            setConnectedState(service: service, isConnected: false)
        }
        print("Disconnected from \(service.rawValue)")
    }

    private func startOAuthFlow(for config: OAuthConfig) { // Changed parameter type to OAuthConfig
        let request = OIDAuthorizationRequest(
            configuration: config.configuration,
            clientId: config.clientID,
            clientSecret: config.clientSecret,
            scopes: config.scopes,
            redirectURL: config.redirectURI,
            responseType: OIDResponseTypeCode,
            additionalParameters: nil
        )

        guard let presentingWindow = config.presentingWindow else {
            print("No visible window available for presenting OAuth.")
            return
        }

        currentAuthorizationFlow = OIDAuthState.authState(
            byPresenting: request,
            presenting: presentingWindow
        ) { authState, error in
            if let authState = authState {
                print("OAuth for \(config.configuration.issuer?.absoluteString ?? "Unknown Service") successful.")
                print("  Access Token: \(authState.lastTokenResponse?.accessToken ?? "N/A")")
                print("  Granted Scopes: \(authState.lastTokenResponse?.scope ?? "None")")
                print("  Is Authorized: \(authState.isAuthorized)")

                // Assuming this flow is primarily for Gmail/Google, update authState
                if config.configuration.issuer == URL(string: "https://accounts.google.com") {
                    self.gmailAuthState = authState
                }
                // You might need to add logic here for Slack/Discord authState if they also use AppAuth
                // For now, assume they are managed differently if not using OIDAuthState.
            } else {
                print("OAuth failed for \(config.configuration.issuer?.absoluteString ?? "Unknown Service"): \(error?.localizedDescription ?? "Unknown error")")
                if config.configuration.issuer == URL(string: "https://accounts.google.com") {
                    self.gmailAuthState = nil
                }
            }
            self.currentAuthorizationFlow = nil
        }
    }

    private func setConnectedState(service: ServiceType, isConnected: Bool) {
        switch service {
        case .gmail:
            break // Handled by gmailAuthState didSet
        case .slack:
            slackConnected = isConnected
        case .discord:
            discordConnected = isConnected
        }
        print("Set \(service.rawValue) connected state to \(isConnected)") // Added a print for clarity
    }

    // MARK: - AuthState Persistence

    private func saveAuthState() {
        if let authState = gmailAuthState {
            do {
                let archivedAuthState = try NSKeyedArchiver.archivedData(withRootObject: authState, requiringSecureCoding: true)
                UserDefaults.standard.set(archivedAuthState, forKey: kGmailAuthStateKey)
                print("Gmail auth state saved.")
            } catch {
                print("Failed to archive Gmail auth state: \(error.localizedDescription)")
            }
        } else {
            UserDefaults.standard.removeObject(forKey: kGmailAuthStateKey)
            print("Gmail auth state cleared.")
        }
    }

    private func loadAuthState() {
        if let archivedAuthState = UserDefaults.standard.data(forKey: kGmailAuthStateKey) {
            do {
                if let authState = try NSKeyedUnarchiver.unarchivedObject(ofClass: OIDAuthState.self, from: archivedAuthState) {
                    self.gmailAuthState = authState
                    print("Gmail auth state loaded. Is authorized: \(authState.isAuthorized)")
                    print("  Loaded Scopes: \(authState.lastTokenResponse?.scope?.replacingOccurrences(of: " ", with: ", ") ?? "None")") // Added .replacingOccurrences for cleaner log
                }
            } catch {
                print("Failed to unarchive Gmail auth state: \(error.localizedDescription)")
                self.gmailAuthState = nil
            }
        }
    }

    /// Retrieves the current access token, refreshing it if necessary.
    /// This method is now public and can be used by API clients (like GoogleCalendarAPI).
    func getAccessToken(completion: @escaping (String?, Error?) -> Void) {
        print("Attempting to get Gmail/Google access token...")
        guard let authState = gmailAuthState, authState.isAuthorized else {
            let error = OAuthError.notAuthorized("Google not connected or not authorized. Please connect Google via settings.")
            print("  Error: Google not connected or not authorized before token action.")
            completion(nil, error)
            return
        }

        authState.performAction { (accessToken, idToken, error) in
            DispatchQueue.main.async { // Ensure completion is called on the main thread
                if let error = error {
                    print("  Error refreshing or getting access token: \(error.localizedDescription)")
                    // If there's a token refresh error, the authState might be invalid, so clear it.
                    self.gmailAuthState = nil
                    completion(nil, OAuthError.tokenRefreshFailed(error.localizedDescription))
                } else if let accessToken = accessToken {
                    print("  Successfully obtained Google access token (first 10 chars): \(accessToken.prefix(10))...")
                    print("  Current Granted Scopes: \(authState.scope?.replacingOccurrences(of: " ", with: ", ") ?? "None")")
                    completion(accessToken, nil)
                } else {
                    let error = OAuthError.tokenRefreshFailed("No access token received from OIDAuthState.performAction.")
                    print("  Error: No access token received from performAction.")
                    completion(nil, error)
                }
            }
        }
    }

    var hasConnectedApps: Bool {
        return gmailConnected || slackConnected || discordConnected
    }
}
