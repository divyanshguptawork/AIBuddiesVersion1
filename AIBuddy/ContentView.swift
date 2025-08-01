import SwiftUI
import Foundation // Needed for FileManager, URL, etc.
import CoreLocation // Potentially needed if CLLocation is used directly in ContentView, though it's mainly in BuddyCard/LocationManager.

struct ContentView: View {
    @State private var dragAmount = CGSize.zero
    @State private var windowPosition: CGPoint = CGPoint(x: 100, y: 100)
    @State private var currentWidth: CGFloat = 400
    @State private var currentHeight: CGFloat = 300

    @State private var buddies: [BuddyModel] = []
    @State private var openBuddies: Set<String> = []
    @State private var currentBuddyID: String? = nil
    @State private var expanded = false
    @State private var showCameraOverlay = false
    @State private var buddyPositions: [String: CGPoint] = [:]

    @State private var showLeoPalSetup = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            GeometryReader { geometry in
                VStack {
                    Spacer()
                    if showCameraOverlay {
                        Rectangle()
                            .fill(Color.gray.opacity(0.4))
                            .overlay(Text("📷 Dummy Webcam").foregroundColor(.white))
                            .cornerRadius(8)
                            .frame(height: 120)
                            .padding(.horizontal)
                            .transition(.opacity)
                    }
                }
                .frame(width: currentWidth, height: currentHeight)
                .background(Color.clear)
                .cornerRadius(15)
                .shadow(radius: 10)
                .position(x: windowPosition.x, y: windowPosition.y)
                .gesture(
                    DragGesture()
                        .onChanged { value in dragAmount = value.translation }
                        .onEnded { _ in
                            windowPosition = CGPoint(
                                x: windowPosition.x + dragAmount.width,
                                y: windowPosition.y + dragAmount.height
                            )
                            saveWindowPositionToFile()
                        }
                )
                .overlay( // This overlay appears to be your main "Home" window content
                    VStack {
                        HStack {
                            // Removed hardcoded Image("avatar1") here.
                            // If you need a static icon for the "Home" window,
                            // you'd add it back with a fixed name, not related to buddies.
                            Text("Home")
                                .foregroundColor(.white)
                                .fontWeight(.bold)
                            Spacer()
                            HStack {
                                Button(action: toggleCard) {
                                    Image(systemName: "mic.fill").foregroundColor(.white)
                                }
                                Button(action: toggleCard) {
                                    Image(systemName: "video.fill").foregroundColor(.white)
                                }
                                Button(action: toggleCard) {
                                    Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                                }
                            }
                        }
                        .padding()
                        .background(Color.purple)
                        .cornerRadius(10)

                        ScrollView {
                            VStack(alignment: .leading) {
                                Text("What's up? How are you doing today?")
                            }
                            .foregroundColor(.white)
                        }
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                    }
                )
                .onAppear {
                    loadWindowPositionFromFile()
                    loadInitialBuddies() // This now loads from BuddyModel.allBuddies
                    BuddyWindowManager.shared.restoreOpenBuddies(buddies)

                    // LeoPal special case setup
                    if !OAuthManager.shared.hasConnectedApps {
                        showLeoPalSetup = true
                    }
                    if OAuthManager.shared.gmailConnected {
                        LeoPalEmailChecker.shared.startMonitoring()
                        print("LeoPal email monitoring started.")
                    }

                    // Timer for screen OCR and AI reaction
                    Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                        ScreenOCR.shared.captureScreenAndExtractText { text in
                            for buddy in buddies {
                                if buddy.id.lowercased() == "leopal" {
                                    // LeoPal uses OAuth instead of OCR
                                    continue
                                }
                                AIReactionEngine.shared.analyze(
                                    screenText: text,
                                    // FIXED: Cast buddy.safeInterval to Int
                                    interval: Int(buddy.safeInterval),
                                    buddyID: buddy.id
                                ) { buddyID, message in
                                    BuddyMessenger.shared.post(to: buddyID, message: message)
                                }
                            }
                        }
                    }
                }
                .onChange(of: geometry.size) { _ in
                    currentWidth = geometry.size.width
                    currentHeight = geometry.size.height
                }
            }

            BuddyDock(
                buddies: buddies,
                openBuddies: $openBuddies,
                currentBuddyID: $currentBuddyID,
                expanded: $expanded
            )
        }
        .sheet(isPresented: $showLeoPalSetup) {
            FirstLaunchPromptView {
                withAnimation {
                    showLeoPalSetup = false
                }
            }
        }
        .onChange(of: openBuddies) { _ in
            saveOpenBuddyIDs()
        }
    }

    private func toggleCard() {
        withAnimation {
            // placeholder
        }
    }

    // MARK: - MODIFIED: Now loads buddies directly from BuddyModel.allBuddies
    private func loadInitialBuddies() {
        self.buddies = BuddyModel.allBuddies
        print("Buddies loaded from BuddyModel.allBuddies: \(self.buddies.map { $0.name })")
    }

    // MARK: - REMOVED: loadBuddies() is no longer needed as we're not reading from JSON on a timer
    /*
    private func loadBuddies() {
        guard let url = Bundle.main.url(forResource: "buddies", withExtension: "json") else {
            print("buddies.json not found")
            return
        }

        DispatchQueue.global().async {
            var previousIDs = Set(self.buddies.map { $0.id })
            while true {
                if let data = try? Data(contentsOf: url),
                    let decoded = try? JSONDecoder().decode([BuddyModel].self, from: data) {
                    DispatchQueue.main.async {
                        let newIDs = Set(decoded.map { $0.id })
                        let difference = newIDs.subtracting(previousIDs)
                        if !difference.isEmpty {
                            self.buddies = decoded
                            previousIDs = newIDs
                            print("New buddies loaded: \(difference)")
                        }
                    }
                }
                sleep(2)
            }
        }
    }
    */

    private func saveWindowPositionToFile() {
        let position = ["x": windowPosition.x, "y": windowPosition.y]
        if let fileURL = getDocumentsDirectory()?.appendingPathComponent("windowPosition.json") {
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: position, options: [])
                try jsonData.write(to: fileURL)
            } catch {
                print("Error saving position: \(error)")
            }
        }
    }

    private func loadWindowPositionFromFile() {
        if let fileURL = getDocumentsDirectory()?.appendingPathComponent("windowPosition.json"),
            let data = try? Data(contentsOf: fileURL),
            let dict = try? JSONSerialization.jsonObject(with: data) as? [String: CGFloat],
            let x = dict["x"], let y = dict["y"] {
            windowPosition = CGPoint(x: x, y: y)
        }
    }

    private func saveBuddyPositions() {
        let data = buddyPositions.mapValues { ["x": $0.x, "y": $0.y] }
        if let url = getDocumentsDirectory()?.appendingPathComponent("buddyPositions.json"),
            let json = try? JSONSerialization.data(withJSONObject: data) {
            try? json.write(to: url)
        }
    }

    private func loadBuddyPositions() {
        if let url = getDocumentsDirectory()?.appendingPathComponent("buddyPositions.json"),
            let data = try? Data(contentsOf: url),
            let dict = try? JSONSerialization.jsonObject(with: data) as? [String: [String: CGFloat]] {
            for (id, pos) in dict {
                if let x = pos["x"], let y = pos["y"] {
                    buddyPositions[id] = CGPoint(x: x, y: y)
                }
            }
        }
    }

    private func saveOpenBuddyIDs() {
        let idsArray = Array(openBuddies)
        if let fileURL = getDocumentsDirectory()?.appendingPathComponent("openBuddies.json") {
            do {
                let json = try JSONEncoder().encode(idsArray)
                try json.write(to: fileURL)
                print("Open buddies saved")
            } catch {
                print("Error saving open buddy list: \(error.localizedDescription)")
            }
        }
    }

    private func loadOpenBuddyIDs() {
        if let fileURL = getDocumentsDirectory()?.appendingPathComponent("openBuddies.json"),
            let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode([String].self, from: data) {
            openBuddies = Set(decoded)
            currentBuddyID = decoded.last
            for id in decoded {
                if let buddy = buddies.first(where: { $0.id == id }) {
                    BuddyWindowManager.shared.open(buddy: buddy)
                }
            }
        }
    }

    private func getDocumentsDirectory() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }
}
