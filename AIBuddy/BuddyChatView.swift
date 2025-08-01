// BuddyChatView.swift
import SwiftUI
import CoreLocation // For location permissions (Cosmic Scout)
// import AppKit // Uncomment if you need specific AppKit functionalities not covered by SwiftUI

struct BuddyChatView: View {
    let buddy: BuddyModel
    @ObservedObject var messenger: BuddyMessenger = BuddyMessenger.shared // Observe BuddyMessenger
    @State private var userInput: String = ""
    @State private var scrollProxy: ScrollViewProxy? = nil
    @State private var locationManager = CLLocationManager()
    @State private var userLocation: CLLocationCoordinate2D? = nil // State for user's location

    var body: some View {
        VStack {
            // Chat history display
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        // Accessing messenger.chats[buddy.id] is now correct
                        ForEach(messenger.chats[buddy.id] ?? []) { message in
                            ChatMessageView(message: message, buddyAccentColor: buddy.accentColor)
                                .id(message.id) // Assign ID for scrolling
                        }
                    }
                    .padding()
                }
                .onChange(of: messenger.chats[buddy.id]?.last?.id) { _ in
                    // Auto-scroll to the bottom when a new message arrives
                    scrollToBottom(proxy: proxy)
                }
                .onAppear {
                    // Initial scroll to bottom if history exists
                    scrollProxy = proxy // Capture proxy
                    scrollToBottom(proxy: proxy)
                }
            }

            // Input field
            HStack {
                TextField("Message \(buddy.name)...", text: $userInput)
                    .textFieldStyle(RoundedBorderTextFieldStyle()) // On macOS, this might render differently, consider .plain or no style for a native look.
                    .padding(.horizontal)
                    .frame(minHeight: 40) // Ensure enough height for the text field
                 
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .font(.title2)
                        .foregroundColor(buddy.accentColor)
                }
                .padding(.trailing)
                .disabled(userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            // Removed .padding(.bottom, UIDevice.current.hasNotch ? 0 : 10) as it's iOS specific.
        }
        .navigationTitle(buddy.name)
        // .navigationBarTitleDisplayMode(.inline) is iOS specific. For macOS, .navigationTitle is usually enough.
        .onAppear {
            // Request location permission when Cosmic Scout is active
            if buddy.id == "cosmicscout" {
                requestLocationPermission()
            }
            
            // Load chat history for the current buddy into BuddyMessenger's @Published property
            messenger.loadHistory(for: buddy.id)
            
            // Clear SpaceCat history if desired upon view appearance
            // This is where you'd put the conditional clear:
            // if buddy.id == "spacecat" {
            //     MessageHistoryManager.shared.clearChatHistory(for: "spacecat")
            //     messenger.clearHistory(for: "spacecat") // Also clear in-memory chats
            // }
        }
        .onDisappear {
            // Your onDisappear logic here
            // Example:
            // if buddy.id == "spacecat" {
            //    MessageHistoryManager.shared.updateLastScreenReactionTriggerTime(for: "spacecat", to: Date())
            // }
        }
    }
    
    private func sendMessage() {
        let trimmedInput = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return }

        // Create the user message
        let userMessage = ChatMessage(role: "user", text: trimmedInput)
        
        // Directly append user message to the messenger's @Published chats array
        // This will trigger the UI update and auto-scroll
        DispatchQueue.main.async {
            var currentBuddyChats = self.messenger.chats[self.buddy.id] ?? []
            // Remove any typing indicator before adding the user's message
            if let index = currentBuddyChats.lastIndex(where: { $0.isTyping }) {
                currentBuddyChats.remove(at: index)
            }
            currentBuddyChats.append(userMessage)
            self.messenger.chats[self.buddy.id] = currentBuddyChats
        }
        
        // Record user message in MessageHistoryManager for persistence
        MessageHistoryManager.shared.recordMessage(for: buddy.id, message: userMessage)
            
        // Trigger AI reaction/response
        AIReactionEngine.shared.handleUserChat(
            buddyID: buddy.id,
            buddyName: buddy.name,
            personality: buddy.personality,
            userInput: trimmedInput,
            userLocation: userLocation // Pass user location if available
        ) { _ in
            // Response handled by AIReactionEngine posting to BuddyMessenger's `post` method,
            // which will then update `messenger.chats`
        }
            
        userInput = "" // Clear input field
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        // Scroll only if there are messages to scroll to
        if let lastMessageID = messenger.chats[buddy.id]?.last?.id {
            proxy.scrollTo(lastMessageID, anchor: .bottom)
        }
    }
    
    private func requestLocationPermission() {
        locationManager.delegate = LocationDelegate.shared
        // For macOS, `requestWhenInUseAuthorization()` still prompts the user,
        // but the system dialog looks different and behavior can vary slightly.
        locationManager.requestWhenInUseAuthorization()
            
        // Start updating location to get the current coordinate
        locationManager.startUpdatingLocation()
        LocationDelegate.shared.onLocationUpdate = { newLocation in
            self.userLocation = newLocation.coordinate
            print("BuddyChatView: User location updated: \(newLocation.coordinate)")
            self.locationManager.stopUpdatingLocation() // Stop once location is received
        }
    }
}

// Helper struct for displaying individual chat messages
struct ChatMessageView: View {
    let message: ChatMessage
    let buddyAccentColor: Color
    
    var body: some View {
        HStack {
            if message.role == "user" {
                Spacer()
                Text(message.text)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            } else { // model
                if message.isTyping {
                    Text(message.text) // This will be "..."
                        .padding()
                        .background(buddyAccentColor.opacity(0.1))
                        .foregroundColor(.secondary)
                        .cornerRadius(10)
                        .opacity(0.7) // Make typing indicator a bit transparent
                } else {
                    Text(message.text)
                        .padding()
                        .background(buddyAccentColor.opacity(0.2))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                }
                Spacer()
            }
        }
    }
}

// A simple delegate to handle CLLocationManager updates
class LocationDelegate: NSObject, CLLocationManagerDelegate, ObservableObject {
    static let shared = LocationDelegate() // Singleton
    
    var onLocationUpdate: ((CLLocation) -> Void)?
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        onLocationUpdate?(location)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("LocationManager failed with error: \(error.localizedDescription)")
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            print("Location authorization granted.")
            manager.startUpdatingLocation() // Start updating after permission is granted
        case .denied, .restricted:
            print("Location authorization denied or restricted.")
            // Handle denied permission, e.g., inform user or disable location-dependent features
        case .notDetermined:
            print("Location authorization not determined.")
        @unknown default:
            fatalError("Unknown authorization status")
        }
    }
}
