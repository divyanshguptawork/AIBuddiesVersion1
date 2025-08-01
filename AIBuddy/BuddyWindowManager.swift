import SwiftUI
import AppKit

class BuddyWindowManager {
    static let shared = BuddyWindowManager()
    private var windows: [String: NSWindow] = [:]
    private var saveTimer: Timer?

    init() {
        startPositionAutoSave()
    }

    func open(buddy: BuddyModel) {
        if let existing = windows[buddy.id] {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let view = BuddyCard(buddy: buddy, onClose: {
            self.close(buddyID: buddy.id)
        })

        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)

        // Load position and size
        let allPositions = loadAllPositions()
        let saved = allPositions[buddy.id]
        let position = CGPoint(x: saved?.x ?? 200, y: saved?.y ?? 200)
        let size = NSSize(width: saved?.width ?? 340, height: saved?.height ?? 300)

        window.setFrame(NSRect(origin: position, size: size), display: true)
        window.title = buddy.name
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        window.standardWindowButton(.zoomButton)?.isHidden = true

        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            self.updateBuddyPosition(buddy.id, window: window)
            self.windows[buddy.id] = nil
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { _ in
            self.updateBuddyPosition(buddy.id, window: window)
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: window, queue: .main) { _ in
            self.updateBuddyPosition(buddy.id, window: window)
        }

        windows[buddy.id] = window
    }

    func close(buddyID: String) {
        windows[buddyID]?.close()
        windows[buddyID] = nil
    }

    func restoreOpenBuddies(_ buddies: [BuddyModel]) {
        let fileURL = getDocumentsDirectory().appendingPathComponent("openBuddies.json")
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else { return }

        for id in decoded {
            if let buddy = buddies.first(where: { $0.id == id }) {
                open(buddy: buddy)
            }
        }
    }

    private func startPositionAutoSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            var allPositions: [String: [String: CGFloat]] = [:]
            for (buddyID, window) in self.windows {
                let frame = window.frame
                allPositions[buddyID] = [
                    "x": frame.origin.x,
                    "y": frame.origin.y,
                    "width": frame.size.width,
                    "height": frame.size.height
                ]
            }

            let fileURL = self.getBuddyPositionsURL()
            do {
                let data = try JSONSerialization.data(withJSONObject: allPositions, options: .prettyPrinted)
                try data.write(to: fileURL)
            } catch {
                print("Failed to write positions: \(error)")
            }

            self.saveOpenBuddyIDs()
        }
    }

    private func updateBuddyPosition(_ buddyID: String, window: NSWindow) {
        let frame = window.frame
        let fileURL = getBuddyPositionsURL()

        var allPositions: [String: [String: CGFloat]] = [:]
        if let data = try? Data(contentsOf: fileURL),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: [String: CGFloat]] {
            allPositions = parsed
        }

        allPositions[buddyID] = [
            "x": frame.origin.x,
            "y": frame.origin.y,
            "width": frame.size.width,
            "height": frame.size.height
        ]

        if let updated = try? JSONSerialization.data(withJSONObject: allPositions, options: .prettyPrinted) {
            try? updated.write(to: fileURL)
            print("Updated position+size saved for \(buddyID)")
        }
    }

    private func loadAllPositions() -> [String: (x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat)] {
        let url = getBuddyPositionsURL()
        guard let data = try? Data(contentsOf: url),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: [String: CGFloat]] else {
            return [:]
        }

        var result: [String: (x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat)] = [:]
        for (id, dict) in raw {
            if let x = dict["x"], let y = dict["y"],
               let width = dict["width"], let height = dict["height"] {
                result[id] = (x, y, width, height)
            }
        }
        return result
    }

    private func saveOpenBuddyIDs() {
        let idsArray = Array(windows.keys)
        let fileURL = getDocumentsDirectory().appendingPathComponent("openBuddies.json")
        do {
            let json = try JSONEncoder().encode(idsArray)
            try json.write(to: fileURL)
        } catch {
            print("Failed to save open buddy list: \(error)")
        }
    }

    private func getBuddyPositionsURL() -> URL {
        getDocumentsDirectory().appendingPathComponent("buddyPositions.json")
    }

    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
}
