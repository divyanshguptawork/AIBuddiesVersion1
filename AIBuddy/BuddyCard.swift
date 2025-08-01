import SwiftUI
import Foundation
import EventKit
import CoreLocation // Import CoreLocation for CLLocationCoordinate2D

struct BuddyCard: View {
    let buddy: BuddyModel
    let onClose: () -> Void

    @State private var expanded: Bool = false
    @State private var showCameraOverlay = false
    @State private var userInput: String = ""
    @State private var messages: [ChatMessage] = []

    @State private var isLoadingResponse: Bool = false

    @ObservedObject private var locationManager = LocationManager.shared
    @ObservedObject private var aiReactionEngine = AIReactionEngine.shared
    @ObservedObject private var buddyMessenger = BuddyMessenger.shared

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack {
                    Image(buddy.avatar)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())

                    Text(buddy.name)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Spacer()

                    HStack(spacing: 12) {
                        Image(systemName: "mic.fill").foregroundColor(.white)

                        Button(action: {
                            withAnimation {
                                showCameraOverlay.toggle()
                            }
                        }) {
                            Image(systemName: showCameraOverlay ? "video.slash.fill" : "video.fill")
                                .foregroundColor(.white)
                        }

                        Button(action: {
                            BuddyMessenger.shared.unregister(buddyID: buddy.id)
                            MessageHistoryManager.shared.clearChatHistory(for: buddy.id)
                            onClose()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                        }
                    }
                }
                .padding()
                .background(Color.purple)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack {
                            ForEach(messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }

                        }
                    }
                    .onChange(of: messages.count) { _ in
                        if let last = messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                    .onChange(of: aiReactionEngine.isTyping) { isTyping in
                        if isTyping {
                            proxy.scrollTo("typingIndicator", anchor: .bottom)
                        } else if let last = messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .frame(maxHeight: .infinity)

                if showCameraOverlay {
                    Rectangle()
                        .fill(Color.gray.opacity(0.4))
                        .overlay(Text("📷 Dummy Webcam").foregroundColor(.white))
                        .cornerRadius(8)
                        .frame(height: 120)
                        .padding(.horizontal)
                        .transition(.opacity)
                }

                VStack {
                    TextEditor(text: $userInput)
                        .font(.body)
                        .padding(6)
                        .frame(minHeight: 40, maxHeight: 100)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.4)))
                    HStack {
                        Spacer()
                        Button("Send") {
                            sendMessage()
                        }
                        .keyboardShortcut(.return, modifiers: [.command])
                        .disabled(userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || aiReactionEngine.isTyping)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)

                Button(action: {
                    withAnimation {
                        expanded.toggle()
                    }
                }) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.up")
                        .padding(8)
                        .background(Color.green)
                        .clipShape(Circle())
                        .shadow(radius: 2)
                }
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .cornerRadius(15)
            .shadow(radius: 6)
        }
        .onAppear {
            registerWithMessenger()
            self.messages = MessageHistoryManager.shared.getChatHistory(for: buddy.id)
            if buddy.id == "cosmicscout" {
                locationManager.requestLocation()
            }
        }
    }

    private func sendMessage() {
        let trimmed = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let userMsg = ChatMessage(role: "user", text: trimmed)
        messages.append(userMsg)
        MessageHistoryManager.shared.recordMessage(for: buddy.id, message: userMsg)
        userInput = ""
        aiReactionEngine.isTyping = true

        let lowercasedInput = trimmed.lowercased()

        if buddy.id == "leopal" {
            if lowercasedInput.contains("email") || lowercasedInput.contains("mail") {
                LeoPalEmailChecker.shared.handleEmailQuery(query: trimmed) { result in
                    DispatchQueue.main.async {
                        self.aiReactionEngine.isTyping = false
                        // Do NOT manually append to messages here!
                        // The BuddyMessenger.register handler will deliver the response to the view.
                    }
                }
                return
            } else if lowercasedInput.contains("set reminder") || lowercasedInput.contains("create reminder") {
                LeoPalCalendarChecker.shared.handleReminderCreationQuery(query: trimmed) { result in
                    DispatchQueue.main.async {
                        self.aiReactionEngine.isTyping = false
                        // Do NOT manually append to messages here!
                        // The BuddyMessenger.register handler will deliver the response to the view.
                    }
                }
                return
            }
        }

        aiReactionEngine.handleUserChat(
            buddyID: buddy.id,
            buddyName: buddy.name,
            personality: buddy.safePersonality,
            userInput: trimmed,
            userLocation: locationManager.lastKnownLocation
        ) { aiResponse in
            DispatchQueue.main.async {
                self.aiReactionEngine.isTyping = false
                // Do NOT manually append to messages here!
                // The BuddyMessenger.register handler will deliver the response to the view.
            }
        }
    }

    private func registerWithMessenger() {
        BuddyMessenger.shared.register(buddyID: buddy.id) { chatMessage in
            DispatchQueue.main.async {
                self.messages.append(chatMessage)
                MessageHistoryManager.shared.recordMessage(for: self.buddy.id, message: chatMessage)
            }
        }
    }
}
