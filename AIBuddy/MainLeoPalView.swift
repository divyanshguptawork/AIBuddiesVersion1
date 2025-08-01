import SwiftUI

struct MainLeoPalView: View {
    var body: some View {
        VStack(spacing: 24) {
            Text("LeoPal is running!")
                .font(.title)
                .fontWeight(.bold)

            Text("LeoPal will remind you about emails, calendar invites, and more.")

            if OAuthManager.shared.gmailConnected {
                Text("✅ Gmail Connected")
            }
            if OAuthManager.shared.slackConnected {
                Text("✅ Slack Connected")
            }
            if OAuthManager.shared.discordConnected {
                Text("✅ Discord Connected")
            }

            Spacer()
        }
        .padding()
        .frame(width: 500)
    }
}