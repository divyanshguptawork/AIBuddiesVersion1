import Foundation
import Combine

struct Reminder: Codable, Identifiable, Equatable {
    let id: String
    let subject: String
    let body: String
    let time: Date
    var notified: Bool
    let createdAt: Date
    
    init(id: String, subject: String, body: String, time: Date, notified: Bool = false) {
        self.id = id
        self.subject = subject
        self.body = body
        self.time = time
        self.notified = notified
        self.createdAt = Date()
    }
    
    static func == (lhs: Reminder, rhs: Reminder) -> Bool {
        return lhs.id == rhs.id
    }
}

class ReminderDatabase: ObservableObject {
    static let shared = ReminderDatabase()
    
    @Published private(set) var reminders: [Reminder] = []
    private let userDefaults = UserDefaults.standard
    private let remindersKey = "saved_reminders"
    private var reminderTimer: Timer?
    
    private init() {
        loadReminders()
        startReminderMonitoring()
    }
    
    // MARK: - Core Database Operations
    
    func saveReminder(_ reminder: Reminder) {
        DispatchQueue.main.async {
            // Remove existing reminder with same ID if it exists
            self.reminders.removeAll { $0.id == reminder.id }
            // Add new reminder
            self.reminders.append(reminder)
            // Sort by time
            self.reminders.sort { $0.time < $1.time }
            self.persistReminders()
            print("ReminderDatabase: Saved reminder - \(reminder.subject) for \(reminder.time)")
        }
    }
    
    func deleteReminder(id: String) {
        DispatchQueue.main.async {
            self.reminders.removeAll { $0.id == id }
            self.persistReminders()
            print("ReminderDatabase: Deleted reminder with ID: \(id)")
        }
    }
    
    func markReminderAsNotified(_ id: String) {
        DispatchQueue.main.async {
            if let index = self.reminders.firstIndex(where: { $0.id == id }) {
                self.reminders[index].notified = true
                self.persistReminders()
                print("ReminderDatabase: Marked reminder as notified: \(id)")
            }
        }
    }
    
    func updateReminder(_ reminder: Reminder) {
        saveReminder(reminder) // saveReminder handles updates by ID
    }
    
    // MARK: - Query Operations
    
    func fetchUpcomingReminders(within minutes: Int) -> [Reminder] {
        let now = Date()
        let futureLimit = Calendar.current.date(byAdding: .minute, value: minutes, to: now) ?? now
        
        return reminders.filter { reminder in
            !reminder.notified &&
            reminder.time >= now &&
            reminder.time <= futureLimit
        }.sorted { $0.time < $1.time }
    }
    
    func fetchOverdueReminders() -> [Reminder] {
        let now = Date()
        return reminders.filter { reminder in
            !reminder.notified && reminder.time < now
        }.sorted { $0.time < $1.time }
    }
    
    func fetchTodayReminders() -> [Reminder] {
        let calendar = Calendar.current
        let today = Date()
        
        return reminders.filter { reminder in
            calendar.isDate(reminder.time, inSameDayAs: today)
        }.sorted { $0.time < $1.time }
    }
    
    func fetchAllActiveReminders() -> [Reminder] {
        return reminders.filter { !$0.notified }.sorted { $0.time < $1.time }
    }
    
    func fetchRemindersByTimeRange(from startDate: Date, to endDate: Date) -> [Reminder] {
        return reminders.filter { reminder in
            reminder.time >= startDate && reminder.time <= endDate
        }.sorted { $0.time < $1.time }
    }
    
    func searchReminders(query: String) -> [Reminder] {
        let lowercaseQuery = query.lowercased()
        return reminders.filter { reminder in
            reminder.subject.lowercased().contains(lowercaseQuery) ||
            reminder.body.lowercased().contains(lowercaseQuery)
        }.sorted { $0.time < $1.time }
    }
    
    // MARK: - Monitoring and Notifications
    
    private func startReminderMonitoring() {
        reminderTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.checkAndTriggerReminders()
        }
        print("ReminderDatabase: Started reminder monitoring")
    }
    
    private func checkAndTriggerReminders() {
        let now = Date()
        let overdueReminders = reminders.filter { reminder in
            !reminder.notified && reminder.time <= now
        }
        
        for reminder in overdueReminders {
            triggerReminder(reminder)
        }
        
        // Clean up old notified reminders (older than 30 days)
        cleanupOldReminders()
    }
    
    private func triggerReminder(_ reminder: Reminder) {
        print("ReminderDatabase: Triggering reminder: \(reminder.subject)")
        
        // Send message to LeoPal
        let message = "⏰ **Reminder:** \(reminder.subject)"
        BuddyMessenger.shared.post(to: "leopal", message: message)
        
        // Schedule local notification
        NotificationManager.shared.scheduleNotification(
            id: "reminder_\(reminder.id)",
            title: "⏰ Reminder",
            body: reminder.subject,
            timeInterval: 1,
            userData: [
                "buddyID": "leopal",
                "type": "reminder",
                "reminderID": reminder.id
            ]
        )
        
        // Mark as notified
        markReminderAsNotified(reminder.id)
    }
    
    private func cleanupOldReminders() {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let initialCount = reminders.count
        
        reminders.removeAll { reminder in
            reminder.notified && reminder.time < thirtyDaysAgo
        }
        
        if reminders.count != initialCount {
            persistReminders()
            print("ReminderDatabase: Cleaned up \(initialCount - reminders.count) old reminders")
        }
    }
    
    // MARK: - Batch Operations
    
    func deleteAllReminders() {
        DispatchQueue.main.async {
            self.reminders.removeAll()
            self.persistReminders()
            print("ReminderDatabase: Deleted all reminders")
        }
    }
    
    func deleteCompletedReminders() {
        DispatchQueue.main.async {
            let initialCount = self.reminders.count
            self.reminders.removeAll { $0.notified }
            self.persistReminders()
            print("ReminderDatabase: Deleted \(initialCount - self.reminders.count) completed reminders")
        }
    }
    
    func snoozeReminder(id: String, for minutes: Int) {
        DispatchQueue.main.async {
            if let index = self.reminders.firstIndex(where: { $0.id == id }) {
                let newTime = Calendar.current.date(byAdding: .minute, value: minutes, to: Date()) ?? Date()
                var updatedReminder = self.reminders[index]
                
                // Create new reminder with snoozed time
                let snoozedReminder = Reminder(
                    id: "\(id)_snoozed_\(Date().timeIntervalSince1970)",
                    subject: "⏰ \(updatedReminder.subject)",
                    body: updatedReminder.body,
                    time: newTime,
                    notified: false
                )
                
                // Mark original as notified and add snoozed version
                self.reminders[index].notified = true
                self.reminders.append(snoozedReminder)
                self.reminders.sort { $0.time < $1.time }
                self.persistReminders()
                
                print("ReminderDatabase: Snoozed reminder \(id) for \(minutes) minutes")
            }
        }
    }
    
    // MARK: - Statistics and Analytics
    
    func getReminderStats() -> (total: Int, active: Int, completed: Int, overdue: Int) {
        let active = reminders.filter { !$0.notified }.count
        let completed = reminders.filter { $0.notified }.count
        let overdue = fetchOverdueReminders().count
        
        return (
            total: reminders.count,
            active: active,
            completed: completed,
            overdue: overdue
        )
    }
    
    // MARK: - Persistence
    
    private func persistReminders() {
        do {
            let data = try JSONEncoder().encode(reminders)
            userDefaults.set(data, forKey: remindersKey)
        } catch {
            print("ReminderDatabase: Error persisting reminders: \(error.localizedDescription)")
        }
    }
    
    private func loadReminders() {
        guard let data = userDefaults.data(forKey: remindersKey) else {
            print("ReminderDatabase: No saved reminders found")
            return
        }
        
        do {
            reminders = try JSONDecoder().decode([Reminder].self, from: data)
            reminders.sort { $0.time < $1.time }
            print("ReminderDatabase: Loaded \(reminders.count) reminders")
        } catch {
            print("ReminderDatabase: Error loading reminders: \(error.localizedDescription)")
            reminders = []
        }
    }
    
    // MARK: - Import/Export
    
    func exportReminders() -> Data? {
        do {
            return try JSONEncoder().encode(reminders)
        } catch {
            print("ReminderDatabase: Error exporting reminders: \(error.localizedDescription)")
            return nil
        }
    }
    
    func importReminders(from data: Data, replace: Bool = false) -> Bool {
        do {
            let importedReminders = try JSONDecoder().decode([Reminder].self, from: data)
            
            DispatchQueue.main.async {
                if replace {
                    self.reminders = importedReminders
                } else {
                    // Merge, avoiding duplicates by ID
                    for reminder in importedReminders {
                        if !self.reminders.contains(where: { $0.id == reminder.id }) {
                            self.reminders.append(reminder)
                        }
                    }
                }
                self.reminders.sort { $0.time < $1.time }
                self.persistReminders()
            }
            
            print("ReminderDatabase: Successfully imported \(importedReminders.count) reminders")
            return true
        } catch {
            print("ReminderDatabase: Error importing reminders: \(error.localizedDescription)")
            return false
        }
    }
    
    deinit {
        reminderTimer?.invalidate()
    }
}
