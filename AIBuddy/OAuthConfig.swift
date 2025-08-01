import Foundation
import AppAuth
import AppKit // Required for NSApp.windows.first

struct OAuthConfig {
    let clientID: String
    let clientSecret: String? // Google native clients typically don't use a client secret
    let redirectURI: URL
    let scopes: [String]
    let configuration: OIDServiceConfiguration
    var presentingWindow: NSWindow? // Changed from 'let' to 'var' to allow assignment

    // Helper to get the top-most visible window for presenting the OAuth flow
    static func currentPresentingWindow() -> NSWindow? {
        // macOS AppKit specific: Find the first visible window or the key window
        return NSApp.windows.first { $0.isVisible } ?? NSApp.keyWindow
    }
}

enum ServiceType: String, CaseIterable { // Added CaseIterable for potential UI listing
    case gmail = "Gmail"
    case slack = "Slack"
    case discord = "Discord"

    var config: OAuthConfig {
        guard let secretsPath = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
              let secrets = NSDictionary(contentsOfFile: secretsPath) else {
            fatalError("Secrets.plist not found or invalid. Please ensure you have a Secrets.plist file in your project bundle.")
        }

        let clientID: String
        let clientSecret: String? // Can be nil for Google iOS/macOS clients
        let redirectURI: URL
        let scopes: [String]
        let authorizationEndpoint: URL
        let tokenEndpoint: URL
        var issuer: URL? = nil

        switch self {
        case .gmail:
            guard let id = secrets["GOOGLE_CLIENT_ID"] as? String else {
                fatalError("GOOGLE_CLIENT_ID not found in Secrets.plist. Please add it.")
            }
            clientID = id
            
            // Google iOS/macOS client types usually do NOT require a client secret
            clientSecret = secrets["GOOGLE_CLIENT_SECRET"] as? String // This will likely be nil or an empty string from plist

            // Construct the redirect URI based on the Google's installed app client ID pattern
            // Example: com.googleusercontent.apps.YOUR_CLIENT_ID_WITHOUT_SUFFIX:/oauth2redirect
            let googleClientIDWithoutSuffix = clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
            guard let constructedRedirectURI = URL(string: "com.googleusercontent.apps.\(googleClientIDWithoutSuffix):/oauth2redirect") else {
                fatalError("Failed to construct Google redirect URI from client ID: \(clientID)")
            }
            redirectURI = constructedRedirectURI
            
            scopes = [
                OIDScopeOpenID,     // Standard OpenID Connect scope
                OIDScopeProfile,    // Provides access to the user's profile information
                OIDScopeEmail,      // Provides access to the user's email address
                "https://www.googleapis.com/auth/gmail.readonly",   // Read-only access to Gmail
                "https://www.googleapis.com/auth/calendar.events" // <--- CRUCIAL CHANGE: Read/Write access to Calendar Events
            ]
            authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
            tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
            issuer = URL(string: "https://accounts.google.com")! // Standard Google issuer URL

        case .slack:
            guard let id = secrets["SLACK_CLIENT_ID"] as? String,
                  let secret = secrets["SLACK_CLIENT_SECRET"] as? String else { // Slack typically uses a client secret
                fatalError("SLACK_CLIENT_ID or SLACK_CLIENT_SECRET not found in Secrets.plist. Please add them.")
            }
            clientID = id
            clientSecret = secret
            guard let slackRedirect = URL(string: "https://yourapp.com/slack/oauthredirect") else { // Use your actual Slack redirect URL
                fatalError("Invalid Slack Redirect URI")
            }
            redirectURI = slackRedirect
            scopes = ["channels:read", "chat:read", "reminders:read"] // Example Slack scopes
            authorizationEndpoint = URL(string: "https://slack.com/oauth/v2/authorize")!
            tokenEndpoint = URL(string: "https://slack.com/api/oauth.v2.access")!

        case .discord:
            guard let id = secrets["DISCORD_CLIENT_ID"] as? String,
                  let secret = secrets["DISCORD_CLIENT_SECRET"] as? String else { // Discord also typically uses a client secret
                fatalError("DISCORD_CLIENT_ID or DISCORD_CLIENT_SECRET not found in Secrets.plist. Please add them.")
            }
            clientID = id
            clientSecret = secret
            guard let discordRedirect = URL(string: "https://yourapp.com/discord/oauthredirect") else { // Use your actual Discord redirect URL
                fatalError("Invalid Discord Redirect URI")
            }
            redirectURI = discordRedirect
            scopes = ["identify", "email", "messages.read"] // Example Discord scopes
            authorizationEndpoint = URL(string: "https://discord.com/api/oauth2/authorize")!
            tokenEndpoint = URL(string: "https://discord.com/api/oauth2/token")!
        }

        // Construct OIDServiceConfiguration
        let serviceConfiguration: OIDServiceConfiguration
        if let issuer = issuer {
            serviceConfiguration = OIDServiceConfiguration(
                authorizationEndpoint: authorizationEndpoint,
                tokenEndpoint: tokenEndpoint,
                issuer: issuer
            )
        } else {
            serviceConfiguration = OIDServiceConfiguration(
                authorizationEndpoint: authorizationEndpoint,
                tokenEndpoint: tokenEndpoint
            )
        }

        return OAuthConfig(
            clientID: clientID,
            clientSecret: clientSecret,
            redirectURI: redirectURI,
            scopes: scopes,
            configuration: serviceConfiguration,
            presentingWindow: OAuthConfig.currentPresentingWindow() // Use the helper
        )
    }
}
