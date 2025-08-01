//
//  LeoPalCalendarChecker.swift
//  AIBuddy
//
//  Created by Divyansh Gupta on 2025-07-16.
//

import Foundation
import EventKit // Crucial for interacting with Apple's Calendar and Reminders app

enum CalendarError: Error, LocalizedError {
    case accessDeniedOrRestricted
    case noDefaultCalendar
    case eventSaveFailed(Error)
    case reminderSaveFailed(Error)
    case invalidEventDetails(String)
    case unknownAuthorizationStatus
    
    var errorDescription: String? {
        switch self {
        case .accessDeniedOrRestricted:
            return "Access to Calendar/Reminders is denied or restricted. Please enable it in System Settings > Privacy & Security > Calendars/Reminders."
        case .noDefaultCalendar:
            return "No default calendar found for events."
        case .eventSaveFailed(let error):
            return "Failed to save event: \(error.localizedDescription)"
        case .reminderSaveFailed(let error):
            return "Failed to save reminder: \(error.localizedDescription)"
        case .invalidEventDetails(let message):
            return "Invalid event details provided: \(message)"
        case .unknownAuthorizationStatus:
            return "An unknown authorization status occurred."
        }
    }
}

class LeoPalCalendarChecker: ObservableObject {
    static let shared = LeoPalCalendarChecker() // Singleton instance
    private let eventStore = EKEventStore() // The main object to access calendar and reminder data

    private init() {
        // Request access on initialization
        requestAccessToCalendarAndReminders()
    }

    // MARK: - Access Request

    private func requestAccessToCalendarAndReminders() {
        // Request access for Events
        eventStore.requestAccess(to: .event) { granted, error in
            if granted {
                print("LeoPalCalendarChecker: Calendar access granted.")
            } else {
                print("LeoPalCalendarChecker: Calendar access denied for events: \(error?.localizedDescription ?? "Unknown error").")
            }
        }
        
        // Request access for Reminders
        eventStore.requestAccess(to: .reminder) { granted, error in
            if granted {
                print("LeoPalCalendarChecker: Reminder access granted.")
            } else {
                print("LeoPalCalendarChecker: Reminder access denied for reminders: \(error?.localizedDescription ?? "Unknown error").")
            }
        }
    }
    
    func startMonitoring() {
        print("LeoPalCalendarChecker: Monitoring started.")
    }

    // MARK: - Reminder Handling

    /// Handles a query to create a reminder.
    /// - Parameters:
    ///   - query: The natural language query for the reminder.
    ///   - completion: A closure that returns a success message or an error.
    func handleReminderCreationQuery(query: String, completion: @escaping (Result<String, Error>) -> Void) {
        print("LeoPalCalendarChecker: Handling explicit reminder creation query: \"\(query)\"")

        let authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
        switch authorizationStatus {
        case .authorized:
            addReminder(title: "AIBuddy Reminder: \(query)", completion: completion)
        case .denied, .restricted:
            completion(.failure(CalendarError.accessDeniedOrRestricted))
        case .notDetermined:
            eventStore.requestAccess(to: .reminder) { [weak self] granted, error in
                DispatchQueue.main.async { // Ensure completion is called on main thread
                    if granted {
                        self?.addReminder(title: "AIBuddy Reminder: \(query)", completion: completion) // Try again after access
                    } else {
                        completion(.failure(CalendarError.accessDeniedOrRestricted))
                    }
                }
            }
        @unknown default:
            completion(.failure(CalendarError.unknownAuthorizationStatus))
        }
    }
    
    /// Internal function to add a reminder.
    private func addReminder(title: String, completion: @escaping (Result<String, Error>) -> Void) {
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title

        guard let defaultCalendar = eventStore.defaultCalendarForNewReminders() else {
            completion(.failure(CalendarError.noDefaultCalendar))
            return
        }
        reminder.calendar = defaultCalendar

        do {
            try eventStore.save(reminder, commit: true)
            completion(.success("I've successfully created a reminder for: '\(title.replacingOccurrences(of: "AIBuddy Reminder: ", with: ""))'. Check your Reminders app!"))
        } catch {
            print("LeoPalCalendarChecker: Error saving reminder: \(error.localizedDescription)")
            completion(.failure(CalendarError.reminderSaveFailed(error)))
        }
    }

    // MARK: - Calendar Event Handling

    /// Adds an event to the user's default calendar.
    /// - Parameters:
    ///   - title: The title of the event.
    ///   - startDate: The start date and time of the event.
    ///   - endDate: The end date and time of the event. If nil, defaults to 1 hour after startDate.
    ///   - location: Optional location for the event.
    ///   - notes: Optional notes/description for the event.
    ///   - completion: A closure that returns the title of the added event or an error.
    func addEventToCalendar(title: String, startDate: Date, endDate: Date?, location: String?, notes: String?, completion: @escaping (Result<String, Error>) -> Void) {
        print("LeoPalCalendarChecker: Attempting to add event: \(title) from \(startDate) to \(endDate ?? startDate.addingTimeInterval(3600))")

        let authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        switch authorizationStatus {
        case .authorized:
            createAndSaveEvent(title: title, startDate: startDate, endDate: endDate, location: location, notes: notes, completion: completion)
        case .denied, .restricted:
            completion(.failure(CalendarError.accessDeniedOrRestricted))
        case .notDetermined:
            eventStore.requestAccess(to: .event) { [weak self] granted, error in
                DispatchQueue.main.async {
                    if granted {
                        self?.createAndSaveEvent(title: title, startDate: startDate, endDate: endDate, location: location, notes: notes, completion: completion)
                    } else {
                        completion(.failure(CalendarError.accessDeniedOrRestricted))
                    }
                }
            }
        @unknown default:
            completion(.failure(CalendarError.unknownAuthorizationStatus))
        }
    }
    
    /// Internal function to create and save an EKEvent.
    private func createAndSaveEvent(title: String, startDate: Date, endDate: Date?, location: String?, notes: String?, completion: @escaping (Result<String, Error>) -> Void) {
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        // If endDate is not provided, default to 1 hour after startDate
        event.endDate = endDate ?? startDate.addingTimeInterval(3600) // 1 hour
        event.location = location
        event.notes = notes
        event.calendar = eventStore.defaultCalendarForNewEvents // Use default calendar

        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
            completion(.success("I've added '\(title)' to your calendar!"))
        } catch {
            print("LeoPalCalendarChecker: Error saving event: \(error.localizedDescription)")
            completion(.failure(CalendarError.eventSaveFailed(error)))
        }
    }

    // MARK: - Placeholder for general calendar queries (if not leading to event creation)

    /// Handles general calendar queries that might not result in event creation.
    /// For this example, it mainly serves as a placeholder. In a more advanced scenario,
    /// Gemini would decide if an event needs to be created or if general information is requested.
    func handleCalendarQuery(query: String, completion: @escaping (Result<String, Error>) -> Void) {
        print("LeoPalCalendarChecker: Handling explicit calendar query: \"\(query)\"")
        // In a full implementation, you might use Gemini to parse the query and then
        // call addEventToCalendar, or fetch events.
        // For now, we'll indicate what could be done.
        completion(.success("I'm ready to add events to your calendar. Try saying something like 'Add an event called Meeting with John tomorrow at 3 PM at the office.'"))
    }
}

// MARK: - Date Parsing Helper (Simplified)
extension String {
    func toDate(format: String = "yyyy-MM-dd HH:mm", timeZone: TimeZone = .current) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.timeZone = timeZone
        return formatter.date(from: self)
    }
}
