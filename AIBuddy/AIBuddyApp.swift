//
//  AIBuddyApp.swift
//  AIBuddy
//
//  Created by Divyansh Gupta on 6/15/25.
//

import SwiftUI

@main
struct AIBuddyApp: App {
    init() {
        // Start LeoPal's email and calendar monitoring
        LeoPalEmailChecker.shared.startMonitoring()
        LeoPalCalendarChecker.shared.startMonitoring() // Ensure this is also called if it's part of LeoPal's proactive checks
        print("LeoPalEmailChecker and LeoPalCalendarChecker started monitoring on app launch.")

        // Start AIReactionEngine for proactive screen content monitoring and reactions
        // This now calls the dedicated public method in AIReactionEngine
        AIReactionEngine.shared.startMonitoringScreenContent()
        print("AIReactionEngine started all proactive monitoring on app launch.")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
