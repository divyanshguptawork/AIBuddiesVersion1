import Foundation

class BuddyIntervalManager {
    static let shared = BuddyIntervalManager()

    private var lastTriggered: [String: Date] = [:]

    func shouldTrigger(for buddyID: String, interval: Int) -> Bool {
        let now = Date()
        let last = lastTriggered[buddyID] ?? .distantPast
        if now.timeIntervalSince(last) >= Double(interval) {
            lastTriggered[buddyID] = now
            return true
        }
        return false
    }
}
