// MARK: - MessageHistoryManager.swift
import Foundation

class MessageHistoryManager {
    static let shared = MessageHistoryManager()
   
    private let userDefaults = UserDefaults.standard
    private let historyKeyPrefix = "chat_history_"
    private let processedEmailIdKeyPrefix = "processed_email_id_" // New prefix for processed emails
    private let lastScreenReactionKeyPrefix = "last_screen_reaction_"
    private let lastSpaceUpdateKey = "last_cosmic_scout_update" // For proactive news/satellite
    private let lastEmailUpdateKey = "last_leopal_email_update" // For proactive email
    private let lastCalendarEventUpdateKey = "last_leopal_calendar_event_update" // For proactive calendar events

    // Thresholds for message and content similarity for SpaceCat and other buddies
    var messageDuplicateThreshold: TimeInterval = 30 // seconds: Messages within this time are considered duplicates
    var contentSimilarityThreshold: Double = 0.8 // 0.0 to 1.0: How similar text needs to be to be considered a duplicate

    // In-memory cache for last screen reaction times to minimize UserDefaults access
    var lastScreenReactionTriggerTime: [String: Date] = [:]
   
    // Using SpaceUpdateInfo from CosmicScoutModels
    // No need to redefine SpaceUpdateInfo here, as it's imported from CosmicScoutModels.swift

    // Structure to hold information about the last proactive email update
    struct EmailUpdateInfo: Codable {
        var lastCheckDate: Date
        var lastNotifiedEmailSubjects: [String]
        var lastNotifiedEmailSenders: [String]
    }

    // Structure to hold information about the last proactive calendar event update
    struct CalendarEventUpdateInfo: Codable {
        var lastCheckDate: Date
        var lastNotifiedEventSummaries: [String]
    }

    // No need to redefine SatellitePass struct here, as it's imported from CosmicScoutModels.swift

    // Date formatter for consistent date handling in proactive updates
    let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = .current
        return formatter
    }()

    private init() {
        loadLastScreenReactionTriggerTimes()
        // Initialize proactive update info if not present
        if userDefaults.data(forKey: lastSpaceUpdateKey) == nil {
            saveLastSpaceUpdateInfo(SpaceUpdateInfo(lastCheckDate: Date().addingTimeInterval(-24 * 60 * 60), lastNotifiedNewsTitles: [], lastNotifiedSatellitePasses: []))
        }
        if userDefaults.data(forKey: lastEmailUpdateKey) == nil {
            saveLastEmailUpdateInfo(EmailUpdateInfo(lastCheckDate: Date().addingTimeInterval(-24 * 60 * 60), lastNotifiedEmailSubjects: [], lastNotifiedEmailSenders: []))
        }
        if userDefaults.data(forKey: lastCalendarEventUpdateKey) == nil {
            saveLastCalendarEventUpdateInfo(CalendarEventUpdateInfo(lastCheckDate: Date().addingTimeInterval(-24 * 60 * 60), lastNotifiedEventSummaries: []))
        }
    }

    // MARK: - Email Processing Status

    func hasProcessedEmail(_ emailId: String) -> Bool {
        return userDefaults.bool(forKey: processedEmailIdKeyPrefix + emailId)
    }

    func markEmailAsProcessed(_ emailId: String) {
        userDefaults.set(true, forKey: processedEmailIdKeyPrefix + emailId)
    }

    // MARK: - Chat History Management

    func recordMessage(for buddyID: String, message: ChatMessage) {
        var history = getChatHistory(for: buddyID)
        history.append(message)
        saveChatHistory(for: buddyID, history: history)
    }

    func getChatHistory(for buddyID: String) -> [ChatMessage] {
        if let data = userDefaults.data(forKey: historyKeyPrefix + buddyID),
         let history = try? JSONDecoder().decode([ChatMessage].self, from: data) {
            return history
        }
        return []
    }

    func clearChatHistory(for buddyID: String) {
        userDefaults.removeObject(forKey: historyKeyPrefix + buddyID)
        print("MessageHistoryManager: Chat history cleared for \(buddyID)")
    }

    private func saveChatHistory(for buddyID: String, history: [ChatMessage]) {
        do {
            let data = try JSONEncoder().encode(history)
            userDefaults.set(data, forKey: historyKeyPrefix + buddyID)
        } catch {
            print("MessageHistoryManager: Error saving chat history for \(buddyID): \(error.localizedDescription)")
        }
    }

    // MARK: - Screen Reaction Time Management

    func updateLastScreenReactionTriggerTime(for buddyID: String, to date: Date) {
        lastScreenReactionTriggerTime[buddyID] = date
        saveLastScreenReactionTriggerTimes()
        print("MessageHistoryManager: Last screen reaction time updated for \(buddyID) to \(date)")
    }
   
    func getLastScreenReactionTriggerTime(for buddyID: String) -> Date? {
        return lastScreenReactionTriggerTime[buddyID]
    }

    func saveLastScreenReactionTriggerTimes() {
        do {
            let data = try JSONEncoder().encode(lastScreenReactionTriggerTime)
            userDefaults.set(data, forKey: lastScreenReactionKeyPrefix + "all")
        } catch {
            print("MessageHistoryManager: Error saving last screen reaction times: \(error.localizedDescription)")
        }
    }

    private func loadLastScreenReactionTriggerTimes() {
        if let data = userDefaults.data(forKey: lastScreenReactionKeyPrefix + "all"),
         let loadedTimes = try? JSONDecoder().decode([String: Date].self, from: data) {
            lastScreenReactionTriggerTime = loadedTimes
        }
    }

    // MARK: - Duplicate Prevention Logic (Proactive updates and general messages)

    /// Determines if a message should be sent based on recent history and screen text.
    /// This combines the logic for general messages and screen reactions.
    func shouldSendMessage(for buddyID: String, message: String, screenText: String) -> Bool {
        let now = Date()
        let history = getChatHistory(for: buddyID)
              
        // Prevent duplicate messages (chat-based)
        if let lastMessage = history.last(where: { $0.role == "model" && !$0.isTyping }) {
            // Check if the exact message or a very similar message was sent recently
            let timeSinceLastMessage = now.timeIntervalSince(lastMessage.timestamp)
            if timeSinceLastMessage < messageDuplicateThreshold {
                let similarity = calculateCosineSimilarity(text1: message, text2: lastMessage.text)
                if similarity > contentSimilarityThreshold {
                    print("MessageHistoryManager: Duplicate message suppressed for \(buddyID) based on content similarity (\(similarity)) and recency.")
                    return false
                }
            }
        }
              
        // Prevent duplicate screen reactions (screen-based) - specifically for SpaceCat
        if buddyID == "spacecat" { // Only SpaceCat uses screen reaction
            if let lastScreenReactionTime = getLastScreenReactionTriggerTime(for: buddyID) {
                let timeSinceLastReaction = now.timeIntervalSince(lastScreenReactionTime)
                if timeSinceLastReaction < messageDuplicateThreshold { // Use the same threshold for now
                    // You might want to compare screenText content here for more robust prevention
                    // This would involve storing previous screen texts, which can be memory intensive.
                    // For simplicity, we just use time-based for now.
                    print("MessageHistoryManager: Screen reaction suppressed for SpaceCat due to recency.")
                    return false
                }
            }
        }

        return true
    }
             
    // Simple cosine similarity placeholder (can be improved with actual NLP embedding)
    private func calculateCosineSimilarity(text1: String, text2: String) -> Double {
        // For a true cosine similarity, you'd convert texts to vector embeddings.
        // This is a very basic word overlap check for demonstration.
        let words1 = Set(text1.lowercased().split { $0.isWhitespace }.map(String.init))
        let words2 = Set(text2.lowercased().split { $0.isWhitespace }.map(String.init))
              
        let intersection = words1.intersection(words2).count
        let union = words1.union(words2).count
              
        if union == 0 { return 0.0 }
        return Double(intersection) / Double(union)
    }

    // MARK: - Proactive Update History Management (Cosmic Scout, LeoPal Emails/Calendar)

    func getLastSpaceUpdateInfo(for buddyID: String) -> SpaceUpdateInfo? { // Using imported type
        guard buddyID == "cosmicscout" else { return nil }
        if let data = userDefaults.data(forKey: lastSpaceUpdateKey),
         let info = try? JSONDecoder().decode(SpaceUpdateInfo.self, from: data) { // Using imported type
            return info
        }
        return nil // Should be initialized in init, but for safety
    }

    func updateLastSpaceUpdate(for buddyID: String, checkedDate: Date, newsTitles: [String] = [], satellitePasses: [SatellitePass] = []) { // Using imported type
        guard buddyID == "cosmicscout" else { return }
        var currentInfo = getLastSpaceUpdateInfo(for: buddyID) ?? SpaceUpdateInfo(lastCheckDate: Date().addingTimeInterval(-24 * 60 * 60), lastNotifiedNewsTitles: [], lastNotifiedSatellitePasses: []) // Using imported type
              
        currentInfo.lastCheckDate = checkedDate
              
        // Add new news titles and filter out old ones
        currentInfo.lastNotifiedNewsTitles.append(contentsOf: newsTitles)
        currentInfo.lastNotifiedNewsTitles = Array(Set(currentInfo.lastNotifiedNewsTitles)).suffix(50) // Keep a reasonable number
              
        // Add new satellite passes and filter out old ones
        currentInfo.lastNotifiedSatellitePasses.append(contentsOf: satellitePasses)
        // Keep only future passes or very recent ones, and limit count
        currentInfo.lastNotifiedSatellitePasses = Array(currentInfo.lastNotifiedSatellitePasses
            .filter { $0.startTime > Date().addingTimeInterval(-24 * 60 * 60) }
            .sorted { $0.startTime > $1.startTime }
            .suffix(50)) // Keep a reasonable number
              
        saveLastSpaceUpdateInfo(currentInfo)
    }
   
    // This method is called by AIReactionEngine
    func recordSatellitePasses(for buddyID: String, passes: [SatellitePass]) { // Using imported type
        updateLastSpaceUpdate(for: buddyID, checkedDate: Date(), satellitePasses: passes)
    }

    func hasRecentSimilarSpaceUpdate(for buddyID: String, newsTitles: [String]? = nil, satellitePasses: [SatellitePass]? = nil) -> Bool { // Using imported type
        guard buddyID == "cosmicscout", let info = getLastSpaceUpdateInfo(for: buddyID) else { return false }
              
        if let titles = newsTitles {
            for title in titles {
                if info.lastNotifiedNewsTitles.contains(where: { $0.localizedCaseInsensitiveContains(title) || title.localizedCaseInsensitiveContains($0) }) {
                    return true
                }
            }
        }
              
        if let passes = satellitePasses {
            for newPass in passes {
                if info.lastNotifiedSatellitePasses.contains(where: {
                    $0.satelliteName == newPass.satelliteName && // Accessing satelliteName property
                    abs($0.startTime.timeIntervalSince(newPass.startTime)) < (60 * 60) // within 1 hour
                }) {
                    return true
                }
            }
        }
        return false
    }

    private func saveLastSpaceUpdateInfo(_ info: SpaceUpdateInfo) { // Using imported type
        do {
            let data = try JSONEncoder().encode(info)
            userDefaults.set(data, forKey: lastSpaceUpdateKey)
        } catch {
            print("MessageHistoryManager: Error saving last space update info: \(error.localizedDescription)")
        }
    }

    // LeoPal Email Update Tracking
    func getLastEmailUpdateInfo(for buddyID: String) -> EmailUpdateInfo? {
        guard buddyID == "leopal" else { return nil }
        if let data = userDefaults.data(forKey: lastEmailUpdateKey),
         let info = try? JSONDecoder().decode(EmailUpdateInfo.self, from: data) {
            return info
        }
        return nil
    }

    func updateLastEmailUpdate(for buddyID: String, subject: String, sender: String) {
        guard buddyID == "leopal" else { return }
        var currentInfo = getLastEmailUpdateInfo(for: buddyID) ?? EmailUpdateInfo(lastCheckDate: Date().addingTimeInterval(-24 * 60 * 60), lastNotifiedEmailSubjects: [], lastNotifiedEmailSenders: [])
              
        currentInfo.lastCheckDate = Date()
        currentInfo.lastNotifiedEmailSubjects.append(subject)
        currentInfo.lastNotifiedEmailSenders.append(sender)
        // Keep a reasonable number, e.g., last 100 entries to prevent memory bloat
        currentInfo.lastNotifiedEmailSubjects = Array(currentInfo.lastNotifiedEmailSubjects.suffix(100))
        currentInfo.lastNotifiedEmailSenders = Array(currentInfo.lastNotifiedEmailSenders.suffix(100))
              
        saveLastEmailUpdateInfo(currentInfo)
    }

    func hasRecentSimilarEmailUpdate(for buddyID: String, emailSubject: String, emailSender: String) -> Bool {
        guard buddyID == "leopal", let info = getLastEmailUpdateInfo(for: buddyID) else { return false }
              
        return info.lastNotifiedEmailSubjects.contains(where: { $0.localizedCaseInsensitiveContains(emailSubject) }) ||
                   info.lastNotifiedEmailSenders.contains(where: { $0.localizedCaseInsensitiveContains(emailSender) })
    }

    private func saveLastEmailUpdateInfo(_ info: EmailUpdateInfo) {
        do {
            let data = try JSONEncoder().encode(info)
            userDefaults.set(data, forKey: lastEmailUpdateKey)
        } catch {
            print("MessageHistoryManager: Error saving last email update info: \(error.localizedDescription)")
        }
    }

    // LeoPal Calendar Event Update Tracking
    func getLastCalendarEventUpdateInfo(for buddyID: String) -> CalendarEventUpdateInfo? {
        guard buddyID == "leopal" else { return nil }
        if let data = userDefaults.data(forKey: lastCalendarEventUpdateKey),
         let info = try? JSONDecoder().decode(CalendarEventUpdateInfo.self, from: data) {
            return info
        }
        return nil
    }

    func updateLastCalendarEventUpdate(for buddyID: String, eventSummary: String) {
        guard buddyID == "leopal" else { return }
        var currentInfo = getLastCalendarEventUpdateInfo(for: buddyID) ?? CalendarEventUpdateInfo(lastCheckDate: Date().addingTimeInterval(-24 * 60 * 60), lastNotifiedEventSummaries: [])
              
        currentInfo.lastCheckDate = Date()
        currentInfo.lastNotifiedEventSummaries.append(eventSummary)
        // Keep a reasonable number, e.g., last 100 entries
        currentInfo.lastNotifiedEventSummaries = Array(currentInfo.lastNotifiedEventSummaries.suffix(100))
              
        saveLastCalendarEventUpdateInfo(currentInfo)
    }

    func hasRecentSimilarCalendarEventUpdate(for buddyID: String, eventSummary: String) -> Bool {
        guard buddyID == "leopal", let info = getLastCalendarEventUpdateInfo(for: buddyID) else { return false }
              
        return info.lastNotifiedEventSummaries.contains(where: { $0.localizedCaseInsensitiveContains(eventSummary) })
    }

    private func saveLastCalendarEventUpdateInfo(_ info: CalendarEventUpdateInfo) {
        do {
            let data = try JSONEncoder().encode(info)
            userDefaults.set(data, forKey: lastCalendarEventUpdateKey)
        } catch {
            print("MessageHistoryManager: Error saving last calendar event update info: \(error.localizedDescription)")
        }
    }
}
