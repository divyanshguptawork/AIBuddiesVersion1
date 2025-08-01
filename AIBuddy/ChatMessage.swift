// MARK: - ChatMessage.swift
import Foundation

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID // Unique ID for the message
    let role: String // "user" or "model"
    var text: String // Changed from 'let' to 'var' to allow modification after init (for streaming final text)
    var displayedText: String // The text currently displayed (for streaming effect)
    let timestamp: Date // When the message was created
    var isTyping: Bool // Indicates if the message is currently being typed out

    init(id: UUID = UUID(), role: String, text: String, timestamp: Date = Date(), isTyping: Bool = false, displayedText: String? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.isTyping = isTyping
        // If displayedText is explicitly provided, use it. Otherwise, if typing, start empty, else use full text.
        self.displayedText = displayedText ?? (isTyping ? "" : text)
    }

    // Custom initializer for a typing indicator message
    static func typingIndicator(for buddyID: String, messageID: String) -> ChatMessage {
        // Use a deterministic UUID from the messageID string for typing indicator only
        return ChatMessage(id: UUID(uuidString: messageID) ?? UUID(), role: "model", text: "", isTyping: true, displayedText: "")
    }
    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        // Compare by ID for Identifiable, and also by role and text for content comparison
        return lhs.id == rhs.id && lhs.role == rhs.role && lhs.text == rhs.text && lhs.isTyping == rhs.isTyping && lhs.displayedText == rhs.displayedText
    }
}
