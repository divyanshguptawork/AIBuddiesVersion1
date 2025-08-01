import Foundation
import Combine
import NaturalLanguage

class LeoPalEmailChecker: ObservableObject {
    static let shared = LeoPalEmailChecker()
    private var timer: Timer?
    private let gmailAPI = GmailAPI.shared
    private let aiEngine = AIReactionEngine.shared
    private let googleCalendar = GoogleCalendarAPI.shared
    private let notificationManager = NotificationManager.shared

    private let lastProcessedEmailIdKey = "leopal_lastProcessedEmailId"
    private var lastProcessedEmailId: String? {
        get { UserDefaults.standard.string(forKey: lastProcessedEmailIdKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastProcessedEmailIdKey) }
    }

    private func getLeoPalBuddy() -> BuddyModel? {
        BuddyModel.allBuddies.first { $0.id == "leopal" }
    }

    private init() {
        _ = lastProcessedEmailId
        setupReminderMonitoring()
    }

    func startMonitoring() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.checkForNewEmails()
            self?.checkUpcomingCalendarEvents()
        }
        print("LeoPalEmailChecker started monitoring.")
        checkForNewEmails()
        checkUpcomingCalendarEvents()
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        print("LeoPalEmailChecker stopped monitoring.")
    }

    private func setupReminderMonitoring() {
        // Monitor reminders every 30 seconds
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.checkAndNotifyReminders()
        }
    }

    private func checkForNewEmails() {
        print("LeoPalEmailChecker: Initiating background check for new emails...")
        gmailAPI.fetchRecentMessages(maxResults: 5) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(let messages):
                    if messages.isEmpty {
                        print("LeoPalEmailChecker: No recent emails found from API.")
                        return
                    }
                    
                    var trulyNewEmails: [GmailMessage] = []
                    var latestEmailIdFromFetch: String? = nil
                    if let firstFetchedMessage = messages.first {
                        latestEmailIdFromFetch = firstFetchedMessage.id
                    }
                    
                    for message in messages {
                        if message.id == self.lastProcessedEmailId { break }
                        // Corrected: Assumed MessageHistoryManager.shared.hasProcessedEmail
                        if !MessageHistoryManager.shared.hasProcessedEmail(message.id) {
                            trulyNewEmails.append(message)
                        }
                    }
                    
                    if !trulyNewEmails.isEmpty {
                        print("LeoPalEmailChecker: Found \(trulyNewEmails.count) truly new emails.")
                        self.processAndAnalyzeNewEmails(trulyNewEmails)
                    } else {
                        print("LeoPalEmailChecker: No genuinely new emails since last check.")
                    }
                    
                    if let newLatestId = latestEmailIdFromFetch {
                        self.lastProcessedEmailId = newLatestId
                        print("LeoPalEmailChecker: Updated lastProcessedEmailId to \(newLatestId)")
                    }
                    
                case .failure(let error):
                    print("LeoPalEmailChecker: Error fetching recent messages for background check: \(error.localizedDescription)")
                }
            }
        }
    }

    private func processAndAnalyzeNewEmails(_ newEmails: [GmailMessage]) {
        let group = DispatchGroup()

        for message in newEmails {
            group.enter()
            
            // Mark as processed immediately to avoid duplicates
            // Corrected: Assumed MessageHistoryManager.shared.markEmailAsProcessed
            MessageHistoryManager.shared.markEmailAsProcessed(message.id)
            
            guard let subject = message.subject,
                  let body = message.body,
                  !body.isEmpty else {
                print("LeoPalEmailChecker: Skipping analysis for email \(message.id) due to missing subject or body.")
                group.leave()
                continue
            }

            // Check if it's a meeting/event email and extract details
            if let meetingInfo = extractMeetingInfo(subject: subject, body: body) {
                createCalendarEventFromEmail(meetingInfo: meetingInfo, emailDate: message.date)
            }

            // Enhanced reminder detection
            if let reminderInfo = extractReminderInfo(subject: subject, body: body) {
                createReminderFromEmail(reminderInfo: reminderInfo, emailId: message.id)
            }

            let emailContentForAI = """
            Subject: \(subject)
            From: \(message.from ?? "Unknown")
            Body: \(String(body.prefix(1500)))
            """
            
            let leopalSystemInstruction = """
            You are LeoPal, a helpful, upbeat AI assistant. Analyze this email and provide a concise, actionable summary.
            Highlight key information, deadlines, action items, or important updates. Be brief but informative.
            If the email contains meeting information, emphasize the time, date, and location.
            """

            Task {
                do {
                    let aiSummary = try await aiEngine.sendPromptToGemini(
                        prompt: emailContentForAI,
                        buddyID: "leopal",
                        systemInstruction: leopalSystemInstruction
                    )
                    
                    DispatchQueue.main.async {
                        print("LeoPalEmailChecker: AI analyzed email (Subject: \(subject)): \(aiSummary)")
                        
                        if !aiSummary.isEmpty && !aiSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            let notificationMessage = "📨 New Email from \(message.from ?? "Unknown Sender"): \(aiSummary)"
                            BuddyMessenger.shared.post(to: "leopal", message: notificationMessage)
                            
                            // Schedule a local notification
                            self.notificationManager.scheduleNotification(
                                id: "email_\(message.id)",
                                title: "New Email from \(message.from ?? "Unknown")",
                                body: String(aiSummary.prefix(100)),
                                timeInterval: 1,
                                userData: ["buddyID": "leopal", "type": "email"]
                            )
                        }
                        group.leave()
                    }
                } catch {
                    print("LeoPalEmailChecker: Error during AI analysis for email (Subject: \(subject)): \(error.localizedDescription)")
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main) {
            print("LeoPalEmailChecker: Finished processing all new emails.")
        }
    }

    private func checkUpcomingCalendarEvents() {
        let now = Date()
        let nextHour = Calendar.current.date(byAdding: .hour, value: 1, to: now) ?? now
        
        googleCalendar.fetchEvents(startDate: now, endDate: nextHour) { [weak self] events, error in
            guard let self = self, let events = events, error == nil else {
                if let error = error {
                    print("LeoPalEmailChecker: Error fetching calendar events: \(error.localizedDescription)")
                }
                return
            }
            
            for event in events {
                if let startTime = self.parseEventDateTime(event.start),
                    startTime.timeIntervalSince(now) > 0 && startTime.timeIntervalSince(now) <= 900 { // 15 minutes
                    let message = "📅 Upcoming Event: \(event.summary) in \(Int(startTime.timeIntervalSince(now)/60)) minutes"
                    BuddyMessenger.shared.post(to: "leopal", message: message)
                    
                    // Schedule notification 5 minutes before
                    if startTime.timeIntervalSince(now) > 300 {
                        self.notificationManager.scheduleNotification(
                            id: "event_\(event.id ?? UUID().uuidString)",
                            title: "Upcoming Event",
                            body: "\(event.summary) starts in 5 minutes",
                            timeInterval: startTime.timeIntervalSince(now) - 300,
                            userData: ["buddyID": "leopal", "type": "calendar"]
                        )
                    }
                }
            }
        }
    }

    private func checkAndNotifyReminders() {
        let reminders = ReminderDatabase.shared.fetchUpcomingReminders(within: 30)
        for reminder in reminders {
            if !reminder.notified && reminder.time <= Date() {
                let message = "⏰ Reminder: \(reminder.subject)"
                BuddyMessenger.shared.post(to: "leopal", message: message)
                ReminderDatabase.shared.markReminderAsNotified(reminder.id)
                
                notificationManager.scheduleNotification(
                    id: "reminder_\(reminder.id)",
                    title: "Reminder",
                    body: reminder.subject,
                    timeInterval: 1,
                    userData: ["buddyID": "leopal", "type": "reminder"]
                )
            }
        }
    }

    // MARK: - Natural Language Processing for Reminders and Meetings

    private func extractReminderInfo(subject: String, body: String) -> ReminderInfo? {
        let content = "\(subject) \(body)".lowercased()
        
        // Enhanced reminder detection patterns
        let reminderPatterns = [
            "remind me", "reminder", "don't forget", "remember to", "follow up",
            "deadline", "due date", "schedule", "appointment", "task"
        ]
        
        guard reminderPatterns.contains(where: { content.contains($0) }) else {
            return nil
        }
        
        let reminderTime = extractTimeFromText(content)
        return ReminderInfo(
            subject: subject,
            body: body,
            extractedTime: reminderTime ?? Date().addingTimeInterval(3600) // Default to 1 hour
        )
    }

    private func extractMeetingInfo(subject: String, body: String) -> MeetingInfo? {
        let content = "\(subject) \(body)".lowercased()
        
        let meetingKeywords = [
            "meeting", "zoom", "teams", "webex", "conference call", "interview",
            "appointment", "call", "session", "presentation", "demo"
        ]
        
        guard meetingKeywords.contains(where: { content.contains($0) }) else {
            return nil
        }
        
        let meetingTime = extractTimeFromText(content)
        let location = extractLocationFromText(content)
        
        return MeetingInfo(
            title: subject,
            description: body,
            startTime: meetingTime ?? Date().addingTimeInterval(3600),
            location: location
        )
    }

    private func extractTimeFromText(_ text: String) -> Date? {
        let now = Date()
        let calendar = Calendar.current
        
        // Time patterns with more sophisticated matching
        let timePatterns = [
            // Specific times
            (pattern: #"(\d{1,2}):(\d{2})\s*(am|pm)"#, handler: { (matches: [String]) -> Date? in
                guard matches.count >= 4,
                      let hour = Int(matches[1]),
                      let minute = Int(matches[2]) else { return nil }
                
                var adjustedHour = hour
                if matches[3].lowercased() == "pm" && hour != 12 {
                    adjustedHour += 12
                } else if matches[3].lowercased() == "am" && hour == 12 {
                    adjustedHour = 0
                }
                
                return calendar.date(bySettingHour: adjustedHour, minute: minute, second: 0, of: now)
            }),
            
            // Relative times
            (pattern: #"in (\d+) (minute|hour|day)s?"#, handler: { (matches: [String]) -> Date? in
                guard matches.count >= 3,
                      let amount = Int(matches[1]) else { return nil }
                
                let unit = matches[2]
                if unit.hasPrefix("minute") {
                    return now.addingTimeInterval(TimeInterval(amount * 60))
                } else if unit.hasPrefix("hour") {
                    return now.addingTimeInterval(TimeInterval(amount * 3600))
                } else if unit.hasPrefix("day") {
                    return calendar.date(byAdding: .day, value: amount, to: now)
                }
                return nil
            }),
            
            // Day references
            (pattern: #"(tomorrow|next week|monday|tuesday|wednesday|thursday|friday|saturday|sunday)"#, handler: { (matches: [String]) -> Date? in
                guard !matches.isEmpty else { return nil }
                
                let dayReference = matches[0].lowercased()
                if dayReference == "tomorrow" {
                    return calendar.date(byAdding: .day, value: 1, to: now)
                } else if dayReference == "next week" {
                    return calendar.date(byAdding: .weekOfYear, value: 1, to: now)
                } else {
                    // Handle specific weekdays
                    let weekdays = ["sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4,
                                    "thursday": 5, "friday": 6, "saturday": 7]
                    if let targetWeekday = weekdays[dayReference] {
                        return self.nextDate(for: targetWeekday, from: now) // Corrected: Added self.
                    }
                }
                return nil
            })
        ]
        
        for (pattern, handler) in timePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(text.startIndex..., in: text)
                if let match = regex.firstMatch(in: text, options: [], range: range) {
                    var matches: [String] = []
                    for i in 0..<match.numberOfRanges {
                        let range = match.range(at: i)
                        if range.location != NSNotFound,
                            let swiftRange = Range(range, in: text) {
                            matches.append(String(text[swiftRange]))
                        }
                    }
                    if let extractedDate = handler(matches) {
                        return extractedDate
                    }
                }
            }
        }
        
        return nil
    }

    private func nextDate(for weekday: Int, from date: Date) -> Date? {
        let calendar = Calendar.current
        let currentWeekday = calendar.component(.weekday, from: date)
        let daysToAdd = (weekday - currentWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: daysToAdd == 0 ? 7 : daysToAdd, to: date)
    }

    private func extractLocationFromText(_ text: String) -> String? {
        let locationPatterns = [
            #"(?:at|in|@)\s+([^,\n]+)"#,
            #"location[:\s]+([^,\n]+)"#,
            #"room\s+(\w+)"#
        ]
        
        for pattern in locationPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(text.startIndex..., in: text)
                if let match = regex.firstMatch(in: text, options: [], range: range),
                    match.numberOfRanges > 1 {
                    let locationRange = match.range(at: 1)
                    if let swiftRange = Range(locationRange, in: text) {
                        return String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
        }
        return nil
    }

    private func createCalendarEventFromEmail(meetingInfo: MeetingInfo, emailDate: Date?) {
        let endTime = Calendar.current.date(byAdding: .hour, value: 1, to: meetingInfo.startTime) ?? meetingInfo.startTime
        
        googleCalendar.addEvent(
            title: meetingInfo.title,
            startDate: meetingInfo.startTime,
            endDate: endTime,
            location: meetingInfo.location,
            description: meetingInfo.description
        ) { event, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("LeoPalEmailChecker: Error creating calendar event: \(error.localizedDescription)")
                    BuddyMessenger.shared.post(to: "leopal", message: "❌ Couldn't add meeting '\(meetingInfo.title)' to calendar: \(error.localizedDescription)")
                } else {
                    print("LeoPalEmailChecker: Successfully created calendar event")
                    BuddyMessenger.shared.post(to: "leopal", message: "📅 Added meeting '\(meetingInfo.title)' to your calendar for \(meetingInfo.startTime.formatted(date: .abbreviated, time: .shortened))")
                }
            }
        }
    }

    private func createReminderFromEmail(reminderInfo: ReminderInfo, emailId: String) {
        let reminder = Reminder(
            id: emailId,
            subject: reminderInfo.subject,
            body: reminderInfo.body,
            time: reminderInfo.extractedTime,
            notified: false
        )
        ReminderDatabase.shared.saveReminder(reminder)
        
        BuddyMessenger.shared.post(to: "leopal", message: "⏰ Set reminder: '\(reminderInfo.subject)' for \(reminderInfo.extractedTime.formatted(date: .abbreviated, time: .shortened))")
    }

    private func parseEventDateTime(_ eventDateTime: GoogleCalendarEvent.EventDateTime) -> Date? {
        if let dateTimeString = eventDateTime.dateTime {
            let formatter = ISO8601DateFormatter()
            return formatter.date(from: dateTimeString)
        } else if let dateString = eventDateTime.date {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: dateString)
        }
        return nil
    }

    func handleEmailQuery(query: String, completion: @escaping (Result<String, Error>) -> Void) {
        print("LeoPalEmailChecker: Handling explicit email query: \"\(query)\"")
        gmailAPI.fetchRecentMessages(maxResults: 1) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(let messages):
                    guard let latestMessage = messages.first else {
                        completion(.success("📭 No recent emails found."))
                        return
                    }
                    
                    guard let subject = latestMessage.subject,
                          let body = latestMessage.body,
                          !body.isEmpty else {
                        completion(.success("I found a recent email, but couldn't get its full content. Subject: \(latestMessage.subject ?? "No Subject")"))
                        return
                    }

                    let truncatedBody = String(body.prefix(1500))
                    let emailContentForAI = """
                    Subject: \(subject)
                    From: \(latestMessage.from ?? "Unknown")
                    Body: \(truncatedBody)
                    """
                    
                    let leopalSystemInstruction = """
                    You are LeoPal, an upbeat, helpful AI assistant. Summarize the email below clearly and concisely,
                    and highlight any important information or actions. Avoid fluff. Focus on actionable insights.
                    """

                    Task {
                        do {
                            let aiSummary = try await self.aiEngine.sendPromptToGemini(
                                prompt: emailContentForAI,
                                buddyID: "leopal",
                                systemInstruction: leopalSystemInstruction
                            )
                            
                            DispatchQueue.main.async {
                                if aiSummary.isEmpty || aiSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    completion(.success("I fetched your recent email (Subject: \(subject)), but I couldn't generate a summary from it right now. It might be empty or contain unsupported content."))
                                } else {
                                    completion(.success("📬 \(aiSummary)"))
                                }
                            }
                        } catch {
                            DispatchQueue.main.async {
                                print("LeoPalEmailChecker: Error during AI summary generation for explicit query: \(error.localizedDescription)")
                                completion(.failure(error))
                            }
                        }
                    }
                    
                case .failure(let error):
                    DispatchQueue.main.async {
                        print("LeoPalEmailChecker: Error fetching recent messages for explicit query: \(error.localizedDescription)")
                        completion(.failure(error))
                    }
                }
            }
        }
    }

    private func isMeeting(subject: String, body: String) -> Bool {
        let keywords = ["meeting", "calendar", "zoom", "interview", "event", "schedule", "appointment", "call"]
        return keywords.contains { subject.lowercased().contains($0) || body.lowercased().contains($0) }
    }
}

// MARK: - Supporting Structures

struct ReminderInfo {
    let subject: String
    let body: String
    let extractedTime: Date
}

struct MeetingInfo {
    let title: String
    let description: String
    let startTime: Date
    let location: String?
}

enum EmailCheckerError: Error, LocalizedError {
    case buddyNotFound
    case summaryGenerationFailed(String)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .buddyNotFound:
            return "LeoPal buddy could not be found."
        case .summaryGenerationFailed(let message):
            return "Failed to generate email summary: \(message)"
        case .apiError(let message):
            return "API error during email processing: \(message)"
        }
    }
}
