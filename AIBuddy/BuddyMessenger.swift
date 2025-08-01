// BuddyMessenger.swift
import Foundation
import Combine

class BuddyMessenger: ObservableObject {
    static let shared = BuddyMessenger()

    // This property needs to be @Published for BuddyChatView to observe changes
    // It will hold the current state of chats for all buddies.
    @Published var chats: [String: [ChatMessage]] = [:]

    private var listeners: [String: (ChatMessage) -> Void] = [:]
    private let messageHistoryManager = MessageHistoryManager.shared

    private init() {
        // Load initial chat history for all known buddies when messenger is initialized
        // This assumes you have a way to get all BuddyModel IDs.
        // For example, if BuddyModel.allBuddies is accessible:
        BuddyModel.allBuddies.forEach { buddy in
            self.chats[buddy.id] = messageHistoryManager.getChatHistory(for: buddy.id)
        }
    }

    func register(buddyID: String, handler: @escaping (ChatMessage) -> Void) {
        listeners[buddyID] = handler
    }

    func unregister(buddyID: String) {
        listeners.removeValue(forKey: buddyID)
    }

    /// Posts a new, complete message to the chat with enhanced duplicate prevention
    func post(to buddyID: String, message: String, shouldCheckDuplicates: Bool = true) {
        // Enhanced duplicate prevention
        // Note: For actual UI display, we'll use the @Published `chats` property directly.
        // The `shouldSendMessage` check is typically for preventing redundant AI responses
        // or persistent history entries if the message is too similar.
        if shouldCheckDuplicates && !messageHistoryManager.shouldSendMessage(
            for: buddyID,
            message: message,
            screenText: "" // You might need to pass actual screen text here if `shouldSendMessage` uses it
        ) {
            print("BuddyMessenger: Skipping duplicate message for \(buddyID)")
            return
        }
       
        // Before adding the new message, remove any existing typing indicator for this buddy
        // This ensures the typing indicator is replaced by the actual message.
        if let index = chats[buddyID]?.lastIndex(where: { $0.isTyping }) {
            chats[buddyID]?.remove(at: index)
        }

        let chatMessage = ChatMessage(role: "model", text: message)
        DispatchQueue.main.async {
            // Update the @Published property so SwiftUI views observe the change
            var currentBuddyChats = self.chats[buddyID] ?? []
            currentBuddyChats.append(chatMessage)
            self.chats[buddyID] = currentBuddyChats

            self.listeners[buddyID]?(chatMessage) // Notify direct listeners if any
            // Record the message in history
            self.messageHistoryManager.recordMessage(for: buddyID, message: chatMessage)
        }
    }

    /// Posts a typing indicator message
    func postTypingIndicator(to buddyID: String) {
        let typingMessage = ChatMessage(role: "model", text: "...", isTyping: true)
        DispatchQueue.main.async {
            // Add typing indicator to the @Published property
            var currentBuddyChats = self.chats[buddyID] ?? []
            // Ensure only one typing indicator is present
            if !currentBuddyChats.contains(where: { $0.isTyping }) {
                currentBuddyChats.append(typingMessage)
                self.chats[buddyID] = currentBuddyChats
            }
            self.listeners[buddyID]?(typingMessage)
            // Typing indicators are typically not recorded in persistent history
            // self.messageHistoryManager.recordMessage(for: buddyID, message: typingMessage)
        }
    }

    /// Posts a message and then removes typing indicator
    func postWithTyping(to buddyID: String, message: String, typingDuration: TimeInterval = 1.0) {
        postTypingIndicator(to: buddyID)
       
        DispatchQueue.main.asyncAfter(deadline: .now() + typingDuration) {
            // The `post` function now inherently removes the typing indicator before adding the new message.
            self.post(to: buddyID, message: message)
        }
    }

    /// Posts a proactive message (bypasses some duplicate checks)
    func postProactive(to buddyID: String, message: String) {
        post(to: buddyID, message: message, shouldCheckDuplicates: false)
    }

    /// Posts a priority message (for urgent notifications)
    func postPriority(to buddyID: String, message: String) {
        let priorityMessage = "⚡ " + message
        post(to: buddyID, message: priorityMessage, shouldCheckDuplicates: false)
    }

    /// Gets recent chat history for context
    func getRecentHistory(for buddyID: String, limit: Int = 5) -> [ChatMessage] {
        let history = messageHistoryManager.getChatHistory(for: buddyID)
        return Array(history.suffix(limit))
    }

    /// Clears chat history for a specific buddy
    func clearHistory(for buddyID: String) {
        messageHistoryManager.clearChatHistory(for: buddyID)
        // Also clear from in-memory @Published chats
        DispatchQueue.main.async {
            self.chats[buddyID] = []
        }
    }
   
    // Method to load history from MessageHistoryManager into BuddyMessenger's @Published property
    // This is called by BuddyChatView's onAppear
    func loadHistory(for buddyID: String) {
        DispatchQueue.main.async {
            self.chats[buddyID] = self.messageHistoryManager.getChatHistory(for: buddyID)
        }
    }
}
