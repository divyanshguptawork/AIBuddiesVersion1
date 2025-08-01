import SwiftUI
import AppKit // Import AppKit to access NSApplication

struct FirstLaunchPromptView: View {
    var onDismiss: () -> Void

    @AppStorage("leopal_firstLaunchCompleted") private var firstLaunchCompleted = false
    @ObservedObject private var oauthManager = OAuthManager.shared

    @State private var gmailToggle = false
    @State private var slackToggle = false
    @State private var discordToggle = false
    @State private var animateIn = false

    var body: some View {
        VStack(spacing: 24) {
            Text("Welcome to LeoPal 🦁")
                .font(.title)
                .fontWeight(.bold)

            Text("Which apps should LeoPal monitor for reminders and events?")
                .multilineTextAlignment(.center)

            Toggle("Gmail", isOn: $gmailToggle)
                .onChange(of: gmailToggle) { newValue in
                    // Provide the presentingWindow here
                    newValue ? oauthManager.connect(to: .gmail, presentingWindow: NSApplication.shared.windows.first) : oauthManager.disconnect(from: .gmail)
                }

            Toggle("Slack", isOn: $slackToggle)
                .onChange(of: slackToggle) { newValue in
                    // Provide the presentingWindow here (if Slack also uses AppAuth with a presenting window)
                    // Based on your OAuthManager, it seems only Gmail uses `startOAuthFlow` with a presenting window.
                    // If Slack/Discord use a different authentication method not requiring a presenting window,
                    // you can keep it as `nil` or remove the parameter from `connect` for those service types.
                    // For now, assuming you might extend them to use it, I'll add `nil` or the window.
                    newValue ? oauthManager.connect(to: .slack, presentingWindow: nil) : oauthManager.disconnect(from: .slack)
                }

            Toggle("Discord", isOn: $discordToggle)
                .onChange(of: discordToggle) { newValue in
                    // Provide the presentingWindow here (if Discord also uses AppAuth with a presenting window)
                    newValue ? oauthManager.connect(to: .discord, presentingWindow: nil) : oauthManager.disconnect(from: .discord)
                }

            Button("Continue") {
                withAnimation {
                    firstLaunchCompleted = true
                    animateIn = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onDismiss()
                }
            }
            .padding()
            .background(Color.green)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .padding()
        .frame(width: 400)
        .scaleEffect(animateIn ? 1 : 0.8)
        .opacity(animateIn ? 1 : 0)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: animateIn)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(16)
        .shadow(radius: 20)
        .onAppear {
            gmailToggle = oauthManager.gmailConnected
            slackToggle = oauthManager.slackConnected
            discordToggle = oauthManager.discordConnected
            animateIn = true
        }
    }
}
