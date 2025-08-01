import Foundation
import UserNotifications
import Combine

class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private var cancellables = Set<AnyCancellable>()
    
    override private init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        checkAuthorizationStatus()
    }
    
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                self.authorizationStatus = granted ? .authorized : .denied
                completion(granted)
            }
        }
    }
    
    private func checkAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.authorizationStatus = settings.authorizationStatus
            }
        }
    }
    
    // Schedule a local notification
    func scheduleNotification(
        id: String,
        title: String,
        body: String,
        timeInterval: TimeInterval,
        userData: [String: Any] = [:]
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userData
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("NotificationManager: Error scheduling notification: \(error.localizedDescription)")
            } else {
                print("NotificationManager: Successfully scheduled notification with ID: \(id)")
            }
        }
    }
    
    // Schedule notification for a specific date
    func scheduleNotification(
        id: String,
        title: String,
        body: String,
        date: Date,
        userData: [String: Any] = [:]
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userData
        
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date),
            repeats: false
        )
        
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("NotificationManager: Error scheduling notification: \(error.localizedDescription)")
            } else {
                print("NotificationManager: Successfully scheduled notification for \(date)")
            }
        }
    }
    
    // Cancel a specific notification
    func cancelNotification(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        print("NotificationManager: Cancelled notification with ID: \(id)")
    }
    
    // Cancel all notifications
    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        print("NotificationManager: Cancelled all notifications")
    }
    
    // Get pending notifications
    func getPendingNotifications(completion: @escaping ([UNNotificationRequest]) -> Void) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            DispatchQueue.main.async {
                completion(requests)
            }
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        print("NotificationManager: User interacted with notification: \(userInfo)")
        
        // Handle different notification types
        if let buddyID = userInfo["buddyID"] as? String {
            handleBuddyNotification(buddyID: buddyID, userInfo: userInfo)
        }
        
        completionHandler()
    }
    
    private func handleBuddyNotification(buddyID: String, userInfo: [AnyHashable: Any]) {
        // This can be extended to handle specific buddy notification actions
        print("NotificationManager: Handling notification for buddy: \(buddyID)")
    }
}
