// MARK: - AIReactionEngine.swift
import Foundation
import SwiftUI
import Combine
import CoreLocation

enum AIReactionEngineError: Error, LocalizedError {
    case invalidActionFormat(String)
    case generalError(String)
    case apiError(String)
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .invalidActionFormat(let action):
            return "Invalid action format received from AI: \(action)"
        case .generalError(let message):
            return "An internal error occurred: \(message)"
        case .apiError(let message):
            return "API Error: \(message)"
        case .invalidURL:
            return "Invalid URL constructed."
        }
    }
}

enum CosmicScoutAction: Equatable {
    case fetchSpaceNews(query: String?)
    case fetchSatelliteFlyovers
    case generalChat
    case generalSpaceInquiry
    case notSpaceRelated
    case none
    case error(String)
}

class AIReactionEngine: ObservableObject {
    static let shared = AIReactionEngine()

    private let apiKey: String = {
        guard let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path),
              let key = dict["GEMINI_API_KEY"] as? String else {
            fatalError("GEMINI_API_KEY not found in Secrets.plist")
        }
        return key
    }()

    private let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-lite:streamGenerateContent"
    private let messageHistoryManager = MessageHistoryManager.shared
    private let cosmicScoutDataFetcher = CosmicScoutDataFetcher.shared
    private let messenger = BuddyMessenger.shared
    private let leoPalCalendarChecker = LeoPalCalendarChecker.shared
    private let googleCalendarAPI = GoogleCalendarAPI.shared

    private var proactiveUpdateTimer: Timer?
    private let proactiveUpdateInterval: TimeInterval = 3 * 60 * 60

    @Published var isTyping: Bool = false

    private init() {
        setupProactiveCosmicScoutMonitoring()
    }

    // MARK: - sendPromptToGemini
    internal func sendPromptToGemini(prompt: String, buddyID: String, systemInstruction: String? = nil, conversationHistory: [ChatMessage]? = nil) async throws -> String {
        var contents: [[String: Any]] = []
        var finalPrompt = prompt

        if let systemInstruction = systemInstruction {
            finalPrompt = "\(systemInstruction)\n\n\(prompt)"
        }

        if let history = conversationHistory, !history.isEmpty {
            for message in history {
                contents.append(["role": message.role, "parts": [["text": message.text]]])
            }
        }
        contents.append(["role": "user", "parts": [["text": finalPrompt]]])

        let requestBody: [String: Any] = [
            "contents": contents
        ]

        guard let url = URL(string: "\(endpoint)?key=\(apiKey)&alt=json"),
              let httpBody = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw AIReactionEngineError.generalError("Invalid API Request Setup")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type") // Corrected argument label
        request.httpBody = httpBody

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorData = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIReactionEngineError.apiError("Gemini API error: \(errorData)")
        }

        var fullResponseText = ""
        if let responseString = String(data: data, encoding: .utf8) {
            print("AIReactionEngine (DEBUG): Raw responseString from Gemini:\n\(responseString)")

            guard let responseData = responseString.data(using: .utf8),
                  let jsonArray = try? JSONSerialization.jsonObject(with: responseData) as? [[String: Any]] else {
                print("AIReactionEngine (DEBUG): Failed to parse raw responseString as a JSON array.")
                throw AIReactionEngineError.generalError("Failed to parse Gemini API response as JSON array.")
            }

            for result in jsonArray {
                print("AIReactionEngine (DEBUG): Processing individual JSON object from array: \(result)")

                guard let candidates = result["candidates"] as? [[String: Any]],
                      let content = candidates.first?["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]],
                      let text = parts.first?["text"] as? String else {
                    print("AIReactionEngine (DEBUG): Failed to extract text from a JSON object within the array.")
                    continue
                }
                let cleanedText = text.removingMarkdown()
                print("AIReactionEngine (DEBUG): Extracted and Cleaned Text Part: \(cleanedText)")
                fullResponseText += cleanedText
            }
        }
        print("AIReactionEngine (DEBUG): Final fullResponseText before return: \(fullResponseText)")
        return fullResponseText
    }

    // MARK: - analyze (Screen Reaction)
    func analyze(screenText: String, interval: Int, buddyID: String, completion: @escaping (String, String) -> Void) {
        if buddyID == "cosmicscout" { return }

        let now = Date()
        if let last = messageHistoryManager.getLastScreenReactionTriggerTime(for: buddyID), now.timeIntervalSince(last) < Double(interval) { // Changed to use messageHistoryManager method
            return
        }
        if !messageHistoryManager.shouldSendMessage(for: buddyID, message: "", screenText: screenText) {
            return
        }
        messageHistoryManager.updateLastScreenReactionTriggerTime(for: buddyID, to: now) // Changed to use messageHistoryManager method
        let personality = BuddyModel.allBuddies.first(where: { $0.id == buddyID })?.personality ?? "neutral"

        let prompt = """
        You're an intelligent assistant that reacts to what the user is currently doing on their screen.
        The user is currently interacting with the **\(buddyID)** buddy. Its tone is **\(personality)**.

        Step 1: Analyze the screen text to understand what the user is doing (e.g., focused work, YouTube, Instagram, ChatGPT, code, gaming).

        Step 2: If the user is switching from focus work to distraction (like Instagram, social media, YouTube), gently remind them of their original task—but only if it feels meaningful.

        Step 3: If the buddy is Spacecat, only provide a response if there's something genuinely humorous, witty, or sarcastic to say based on the screen text. If there isn't, respond with "ACTION:NONE". For other buddies, provide a smart, short one-liner (supportive, witty, sarcastic, or calm) that fits the **\(buddyID)** buddy's tone.

        Output format:
        \(buddyID): message OR ACTION:NONE
        Ensure the message does not contain any Markdown formatting.
        """
        Task {
            do {
                let response = try await sendPromptToGemini(prompt: prompt + "\n\nScreen text:\n\"\"\"\n\(screenText)\n\"\"\"", buddyID: buddyID)
                let components = response.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                if components.count == 2 {
                    let responseBuddyID = components[0].lowercased()
                    let message = components[1]

                    if responseBuddyID == buddyID.lowercased() && message.uppercased() == "NONE" && buddyID == "spacecat" {
                        print("AIReactionEngine: Spacecat decided not to react as there was nothing funny to say.")
                        return
                    }

                    let validIDs = BuddyModel.allBuddies.map { $0.id }
                    if validIDs.contains(responseBuddyID) && responseBuddyID == buddyID.lowercased() {
                        DispatchQueue.main.async {
                            let finalPrefixedMessage = "\(buddyID): \(message)"
                            self.messenger.post(to: buddyID, message: finalPrefixedMessage)
                            let aiMessage = ChatMessage(role: "model", text: finalPrefixedMessage)
                            self.messageHistoryManager.recordMessage(for: buddyID, message: aiMessage)
                            completion(buddyID, finalPrefixedMessage)
                        }
                    } else {
                        DispatchQueue.main.async {
                            let errorMessage = "AIReactionEngine: Received an invalid response. Please try again."
                            self.messenger.post(to: buddyID, message: errorMessage)
                            self.messageHistoryManager.recordMessage(for: buddyID, message: ChatMessage(role: "model", text: errorMessage))
                            completion(buddyID, errorMessage)
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        let errorMessage = "AIReactionEngine: Unexpected response format. Please try again."
                        self.messenger.post(to: buddyID, message: errorMessage)
                        self.messageHistoryManager.recordMessage(for: buddyID, message: ChatMessage(role: "model", text: errorMessage))
                        completion(buddyID, errorMessage)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    let errorMessage = "\(buddyID.capitalized): My circuits are a bit jammed right now. Try again later!"
                    self.messenger.post(to: buddyID, message: errorMessage)
                    self.messageHistoryManager.recordMessage(for: buddyID, message: ChatMessage(role: "model", text: errorMessage))
                    completion(buddyID, errorMessage)
                }
            }
        }
    }

    // MARK: - handleUserChat (Intent Recognition & Response Routing)
    func handleUserChat(buddyID: String, buddyName: String, personality: String, userInput: String, userLocation: CLLocationCoordinate2D?, completion: @escaping (String) -> Void) {
        let history = (buddyID == "spacecat") ? [] : messageHistoryManager.getChatHistory(for: buddyID)
        let intentPrompt: String

        // Add typing indicator for Leopal immediately
        if buddyID == "leopal" {
            DispatchQueue.main.async {
                self.messenger.postTypingIndicator(to: buddyID)
            }
        }

        if buddyID == "cosmicscout" {
            intentPrompt = """
            You are an AI assistant specifically for Cosmic Scout. Your primary purpose is to provide space news and satellite flyover information.
            The user's input is: "\(userInput)".

            Based on the user's input, determine the appropriate action to take.
            **Prioritize space-related actions if the user's query is at all relevant to space, even if indirect.**

            Available Actions for Cosmic Scout:
            1. **General Space Inquiry**: If the user is asking a general question about space, astronomy, celestial bodies, space missions, or the universe that isn't explicitly news or satellite flyover related, but is still *about space*.
                Output: `ACTION:GENERAL_SPACE_INQUIRY`

            2. **Fetch Space News**: If the user is asking for general space news, recent space news, or updates in space (e.g., "latest space news", "what's happening in space").
                Output: `ACTION:FETCH_SPACE_NEWS`

            3. **Fetch Specific Space News**: If the user is asking for news about a specific topic related to space (e.g., "news about Mars", "tell me about the latest rocket launch", "James Webb discoveries").
                Output: `ACTION:FETCH_SPECIFIC_NEWS:[query]` (replace [query] with the extracted specific topic, ensure no spaces around colon for easy splitting)

            4. **Fetch Satellite Flyovers**: If the user is asking about visible satellites, the ISS, or when they can see something orbiting overhead (e.g., "when can I see the ISS", "any satellites tonight"). This action requires the user's location.
                Output: `ACTION:FETCH_SATELLITE_FLYOVERS`

            5. **Not Space Related**: If the user is asking about a topic that has absolutely no relation to space (e.g., "recipe for cake", "how's the weather", "what's your favorite color").
                Output: `ACTION:NOT_SPACE_RELATED`

            Your output should ONLY be one of the `ACTION:` formats above. Do not add any other text.
            Current date and time for context: \(Date().formatted(date: .numeric, time: .shortened))
            """
        } else {
            intentPrompt = """
            You are an AI assistant designed to help manage interactions for various "buddy" personas.
            The user is currently talking to the buddy named "\(buddyName)" who has the personality: "\(personality)".
            The user's input is: "\(userInput)".

            Based on the user's input, determine the appropriate action to take.

            Available Actions:
            1. **General Chat**: If the user is just having a normal conversation, asking general questions, or if their request doesn't fit specific tools.
                Output: `ACTION:GENERAL_CHAT`

            2. **Fetch Space News**: If the user is asking for general space news, recent space news, or updates in space. This is for Cosmic Scout only.
                Output: `ACTION:FETCH_SPACE_NEWS`

            3. **Fetch Specific Space News**: If the user is asking for news about a specific topic related to space (e.g., "news about Mars", "tell me about the latest rocket launch", "James Webb discoveries"). This is for Cosmic Scout only.
                Output: `ACTION:FETCH_SPECIFIC_NEWS:[query]` (replace [query] with the extracted specific topic, ensure no spaces around colon for easy splitting)

            4. **Fetch Satellite Flyovers**: If the user is asking about visible satellites, the ISS, or when they can see something orbiting overhead. This action requires the user's location. This is for Cosmic Scout only.
                Output: `ACTION:FETCH_SATELLITE_FLYOVERS`

            5. **Not My Area**: If the user is talking to Cosmic Scout about something that is NOT space news or satellite related. This is for Cosmic Scout only.
                Output: `ACTION:NOT_MY_AREA`

            6. **Create Reminder**: If the user is asking to create a reminder (e.g., "remind me to call John at 2pm"). This is for LeoPal only.
                Output: `ACTION:CREATE_REMINDER:[Reminder Text]`

            7. **Add Calendar Event**: If the user is asking to add an event to their calendar (e.g., "add a meeting with Mary tomorrow at 10 AM", "schedule a dentist appointment on July 25th at 4:30 PM"). This is for LeoPal only.
                Output: `ACTION:ADD_CALENDAR_EVENT:TITLE|START_TIME|END_TIME|LOCATION|DESCRIPTION`
                - `TITLE`: The event title (required).
                - `START_TIME`: Date and time in 'YYYY-MM-DD HH:MM' format (required).
                - `END_TIME`: Date and time in 'YYYY-MM-DD HH:MM' format (optional, if omitted, assume 1 hour after start).
                - `LOCATION`: Event location (optional).
                - `DESCRIPTION`: Event description/notes (optional).
                Example: `ACTION:ADD_CALENDAR_EVENT:Team Sync|2025-07-20 10:00|2025-07-20 11:00|Conference Room A|Discuss project progress`
                (Adjust date '2025-07-20' to current or relative date as appropriate based on context like 'tomorrow', 'next Monday', etc.)

            Your output should ONLY be one of the `ACTION:` formats above. Do not add any other text.
            Current date and time for context: \(Date().formatted(date: .numeric, time: .shortened))
            """
        }

        Task {
            do {
                let intentResponse = try await sendPromptToGemini(prompt: intentPrompt, buddyID: buddyID, conversationHistory: history)
                print("AIReactionEngine: Intent identified: \(intentResponse)")

                let actionComponents = intentResponse.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

                var recognizedAction: CosmicScoutAction = .none
                var calendarActionPayload: String? = nil
                var reminderActionPayload: String? = nil

                if actionComponents.first == "ACTION" {
                    let actionAndPayload = actionComponents.count > 1 ? actionComponents[1] : ""
                    let actionTypeParts = actionAndPayload.split(separator: ":", maxSplits: 1).map(String.init)
                    let actionType = actionTypeParts[0].replacingOccurrences(of: "_", with: "").uppercased()
                    let payload = actionTypeParts.count > 1 ? actionTypeParts[1] : ""

                    switch actionType {
                    case "GENERALCHAT":
                        recognizedAction = (buddyID == "cosmicscout") ? .generalSpaceInquiry : .generalChat
                    case "GENERALSPACEINQUIRY":
                        recognizedAction = .generalSpaceInquiry
                    case "FETCHSPACENEWS":
                        recognizedAction = .fetchSpaceNews(query: nil)
                    case "FETCHSATELLITEFLYOVERS":
                        recognizedAction = .fetchSatelliteFlyovers
                    case "FETCHSPECIFICNEWS":
                        let query = String(payload).trimmingCharacters(in: .whitespacesAndNewlines)
                        recognizedAction = .fetchSpaceNews(query: query.isEmpty ? nil : query)
                    case "NOTMYAREA", "NOTSPACERELATED":
                        recognizedAction = .notSpaceRelated
                    case "CREATEREMINDER":
                        reminderActionPayload = String(payload).trimmingCharacters(in: .whitespacesAndNewlines)
                    case "ADDCALENDAREVENT":
                        calendarActionPayload = String(payload).trimmingCharacters(in: .whitespacesAndNewlines)
                    case "NONE":
                        recognizedAction = .none
                    default:
                        print("AIReactionEngine: Unrecognized specific action from Gemini: \(actionType) (payload: \(payload))")
                        recognizedAction = .error("Unrecognized action: \(actionType)")
                    }
                } else {
                    print("AIReactionEngine: Gemini did not return a valid ACTION format. Falling back to default behavior.")
                    recognizedAction = (buddyID == "cosmicscout") ? .generalSpaceInquiry : .generalChat
                }

                if let payload = reminderActionPayload {
                    handleReminderAction(payload: payload, buddyID: buddyID, completion: completion)
                } else if let payload = calendarActionPayload {
                    await handleAddCalendarEventAction(payload: payload, buddyID: buddyID, completion: completion)
                } else {
                    if buddyID == "cosmicscout" {
                        switch recognizedAction {
                        case .fetchSpaceNews(let query):
                            await handleFetchSpaceNews(buddyID: buddyID, query: query, completion: completion)
                        case .fetchSatelliteFlyovers:
                            await handleFetchSatelliteFlyovers(buddyID: buddyID, completion: completion)
                        case .generalSpaceInquiry:
                            await handleGeneralChat(buddyID: buddyID, buddyName: buddyName, personality: personality, userInput: userInput, completion: completion)
                        case .notSpaceRelated:
                            let cannedResponse = "Cosmic Scout: My sensors are tuned to the cosmos! That's a bit outside my orbit. Ask me something stellar related to space news, satellite sightings, or general space facts!"
                            DispatchQueue.main.async {
                                self.messenger.post(to: buddyID, message: cannedResponse)
                                self.messageHistoryManager.recordMessage(for: buddyID, message: ChatMessage(role: "model", text: cannedResponse))
                                completion(cannedResponse)
                            }
                        case .generalChat, .none, .error:
                            let cannedResponse = "Cosmic Scout: My cosmic communication lines are a bit fuzzy, spacefarer! Could you try asking that again, focusing on space news, satellites, or general cosmic wonders?"
                            DispatchQueue.main.async {
                                self.messenger.post(to: buddyID, message: cannedResponse)
                                self.messageHistoryManager.recordMessage(for: buddyID, message: ChatMessage(role: "model", text: cannedResponse))
                                completion(cannedResponse)
                            }
                        }
                    } else {
                        await handleGeneralChat(buddyID: buddyID, buddyName: buddyName, personality: personality, userInput: userInput, completion: completion)
                    }
                }
            } catch {
                print("AIReactionEngine: Error during intent recognition: \(error.localizedDescription). Falling back to general chat or appropriate Cosmic Scout response.")
                
                if buddyID == "cosmicscout" {
                    let cannedResponse = "Cosmic Scout: My cosmic communication lines are a bit fuzzy! I couldn't quite grasp your last message, spacefarer. Try asking about space news or satellites!"
                    DispatchQueue.main.async {
                        self.messenger.post(to: buddyID, message: cannedResponse)
                        self.messageHistoryManager.recordMessage(for: buddyID, message: ChatMessage(role: "model", text: cannedResponse))
                        completion(cannedResponse)
                    }
                } else {
                    await handleGeneralChat(buddyID: buddyID, buddyName: buddyName, personality: personality, userInput: userInput, completion: completion)
                }
            }
        }
    }
    // MARK: - handleFetchSpaceNews
    private func handleFetchSpaceNews(buddyID: String, query: String?, completion: @escaping (String) -> Void) async {
        cosmicScoutDataFetcher.fetchSpaceNews(query: query) { [weak self] events, error in
            guard let self = self else { return }

            DispatchQueue.main.async {
                if let error = error {
                    let errorMessage = "Cosmic Scout: Apologies, spacefarer! I encountered an issue fetching the news: \(error.localizedDescription)"
                    print("Error fetching news: \(error)")
                    self.messenger.post(to: buddyID, message: errorMessage)
                    self.messageHistoryManager.recordMessage(for: buddyID, message: ChatMessage(role: "model", text: errorMessage))
                    completion(errorMessage)
                    return
                }

                guard let events = events, !events.isEmpty else {
                    let noNewsMessage = "Cosmic Scout: Hmm, I couldn't find any recent space news related to that. Perhaps try a different query?"
                    self.messenger.post(to: buddyID, message: noNewsMessage)
                    self.messageHistoryManager.recordMessage(for: buddyID, message: ChatMessage(role: "model", text: noNewsMessage))
                    completion(noNewsMessage)
                    return
                }

                Task {
                    await self.summarizeAndPresentNews(buddyID: buddyID, events: events, originalQuery: query, completion: completion)
                }
            }
        }
    }

    // MARK: - summarizeAndPresentNews
    private func summarizeAndPresentNews(buddyID: String, events: [SpaceEvent], originalQuery: String?, completion: @escaping (String) -> Void) async {
        let eventsDescription = events.prefix(5).map { event in
            "Title: \(event.title)\nDescription: \(event.description ?? "No description available.")\nSource: \(event.sourceName) (URL: \(event.sourceURL.absoluteString))\nPublished: \(self.messageHistoryManager.dateFormatter.string(from: event.date))\n"
        }.joined(separator: "\n---\n")

        let prompt = """
        You are Cosmic Scout, an enthusiastic, awe-struck, and knowledgeable AI buddy about space.
        Here are some recent space news articles. Please summarize the most interesting points
        from these articles in a captivating and concise way for the user.
        Mention 2-3 key highlights. If possible, encourage the user to ask for more details on a specific topic or visit a source.
        Make sure to maintain your adventurous space persona.

        Here are the articles:
        \"\"\"
        \(eventsDescription)
        \"\"\"

        Ensure your response does not contain any Markdown formatting.
        """

        do {
            let geminiResponse = try await sendPromptToGemini(prompt: prompt, buddyID: buddyID)
            DispatchQueue.main.async {
                let finalMessage = "Cosmic Scout: " + geminiResponse
                self.messenger.post(to: buddyID, message: finalMessage)
                self.messageHistoryManager.recordMessage(for: buddyID, message: ChatMessage(role: "model", text: finalMessage))
                completion(finalMessage)
            }
        } catch {
            print("Error summarizing news with Gemini: \(error.localizedDescription)")
            DispatchQueue.main.async {
                let fallbackMessage = "Cosmic Scout: I found some news, but my cosmic translator is a bit fuzzy! Here are some headlines:\n\n" + events.prefix(3).map { $0.title }.joined(separator: "\n")
                self.messenger.post(to: buddyID, message: fallbackMessage)
                self.messageHistoryManager.recordMessage(for: buddyID, message: ChatMessage(role: "model", text: fallbackMessage))
                completion(fallbackMessage)
            }
        }
    }

    // MARK: - handleFetchSatelliteFlyovers
    private func handleFetchSatelliteFlyovers(buddyID: String, completion: @escaping (String) -> Void) async {
        cosmicScoutDataFetcher.fetchSatelliteFlyovers { [weak self] passes, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let error = error {
                    let errorMessage = "Cosmic Scout: My cosmic sensors are a bit hazy right now. Couldn't fetch satellite data: \(error.localizedDescription)"
                    print("Error fetching satellite passes: \(error)")
                    self.messenger.post(to: buddyID, message: errorMessage)
                    self.messageHistoryManager.recordMessage(for: buddyID, message: ChatMessage(role: "model", text: errorMessage))
                    completion(errorMessage)
                    return
                }

                guard let passes = passes, !passes.isEmpty else {
                    let noPassesMessage = "Cosmic Scout: No major satellite flyovers detected for your location in the near future. Keep your eyes on the stars, though!"
                    self.messenger.post(to: buddyID, message: noPassesMessage)
                    self.messageHistoryManager.recordMessage(for: buddyID, message: ChatMessage(role: "model", text: noPassesMessage))
                    completion(noPassesMessage)
                    return
                }

                // Call the updateLastSpaceUpdate method on MessageHistoryManager
                self.messageHistoryManager.updateLastSpaceUpdate(for: buddyID, checkedDate: Date(), satellitePasses: passes)

                Task {
                    await self.formatSatellitePassesWithGemini(buddyID: buddyID, passes: passes, completion: completion)
                }
            }
        }
    }

    // MARK: - formatSatellitePassesWithGemini
    private func formatSatellitePassesWithGemini(buddyID: String, passes: [SatellitePass], completion: @escaping (String) -> Void) async {
        let passesDescription = passes.prefix(3).map { pass in
            let startTime = pass.startTime.formatted(date: .omitted, time: .shortened)
            let endTime = pass.endTime.formatted(date: .omitted, time: .shortened)
            // Assuming `satelliteName` and `direction` are available on `SatellitePass`
            return "Satellite: \(pass.satelliteName), Visible from \(startTime) to \(endTime) (Max Elevation: \(Int(pass.maxEl))°), Direction: \(pass.direction)"
        }.joined(separator: "\n")

        let prompt = """
        You are Cosmic Scout, an enthusiastic, awe-struck, and knowledgeable AI buddy about space.
        Here are some upcoming satellite flyovers for the user's location.
        Please present this information in an exciting and easy-to-understand way,
        maintaining your adventurous space persona. Suggest to the user to look up at the specified times.

        Here are the satellite passes:
        \"\"\"
        \(passesDescription)
        \"\"\"

        Ensure your response does not contain any Markdown formatting.
        """

        do {
            let geminiResponse = try await sendPromptToGemini(prompt: prompt, buddyID: buddyID)
            DispatchQueue.main.async {
                let finalMessage = "Cosmic Scout: " + geminiResponse
                self.messenger.post(to: buddyID, message: finalMessage)
                self.messageHistoryManager.recordMessage(for: buddyID, message: ChatMessage(role: "model", text: finalMessage))
                completion(finalMessage)
            }
        } catch {
            print("Error formatting satellite passes with Gemini: \(error.localizedDescription)")
            DispatchQueue.main.async {
                let fallbackMessage = "Cosmic Scout: Fantastic news! I've spotted some celestial visitors for you:\n" + passesDescription + "\nLook up at these times, spacefarer!"
                self.messenger.post(to: buddyID, message: fallbackMessage)
                self.messageHistoryManager.recordMessage(for: buddyID, message: ChatMessage(role: "model", text: fallbackMessage))
                completion(fallbackMessage)
            }
        }
    }

    // MARK: - handleGeneralChat
    private func handleGeneralChat(buddyID: String, buddyName: String, personality: String, userInput: String, completion: @escaping (String) -> Void) async {
        let history = messageHistoryManager.getChatHistory(for: buddyID)
        let prompt = """
        You are \(buddyName), a \(personality) AI buddy. Respond helpfully and concisely to the user’s message in your unique tone.
        Ensure your response does not contain any Markdown formatting.

        User: \(userInput)
        """

        do {
            let geminiResponse = try await sendPromptToGemini(prompt: prompt, buddyID: buddyID, conversationHistory: history)
            DispatchQueue.main.async {
                let finalMessage = "\(buddyName): " + geminiResponse
                self.messenger.post(to: buddyID, message: finalMessage)
                self.messageHistoryManager.recordMessage(for: buddyID, message: ChatMessage(role: "model", text: finalMessage))
                completion(finalMessage)
            }
        } catch {
            print("Error in general chat with Gemini: \(error.localizedDescription)")
            DispatchQueue.main.async {
                let errorMessage = "\(buddyName): My cosmic communication lines are a bit jammed! Can you repeat that, spacefarer?"
                self.messenger.post(to: buddyID, message: errorMessage)
                self.messageHistoryManager.recordMessage(for: buddyID, message: ChatMessage(role: "model", text: errorMessage))
                completion(errorMessage)
            }
        }
    }

    // MARK: - Reminder Handling (using LeoPalCalendarChecker for EventKit Reminders)
    private func handleReminderAction(payload: String, buddyID: String, completion: @escaping (String) -> Void) {
        let reminderText = payload.trimmingCharacters(in: .whitespacesAndNewlines)

        leoPalCalendarChecker.handleReminderCreationQuery(query: reminderText) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                var messageToUser: String
                switch result {
                case .success(let message):
                    messageToUser = message
                case .failure(let error):
                    messageToUser = "Failed to create reminder: \(error.localizedDescription)"
                }
                self.messenger.post(to: buddyID, message: messageToUser)
                self.messageHistoryManager.recordMessage(for: buddyID, message: ChatMessage(role: "model", text: messageToUser))
                completion(messageToUser)
            }
        }
    }


    // MARK: - Calendar Event Handling (using GoogleCalendarAPI for Google Calendar Events)
    private func handleAddCalendarEventAction(payload: String, buddyID: String, completion: @escaping (String) -> Void) async {
        let parts = payload.split(separator: "|", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)

        guard parts.count >= 2 else {
            let errorMessage = "I need at least a title and a start time to create a calendar event. Format: TITLE|YYYY-MM-DD HH:MM|..."
            self.messenger.post(to: buddyID, message: errorMessage)
            self.messageHistoryManager.recordMessage(for: buddyID, message: ChatMessage(role: "model", text: errorMessage))
            completion(errorMessage)
            return
        }

        let title = parts[0]
        let startTimeString = parts[1]
        let endTimeString = parts.count > 2 && !parts[2].isEmpty ? parts[2] : nil
        let location = parts.count > 3 && !parts[3].isEmpty ? parts[3] : nil
        let description = parts.count > 4 && !parts[4].isEmpty ? parts[4] : nil

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        dateFormatter.timeZone = TimeZone.current

        guard let startDate = dateFormatter.date(from: startTimeString) else {
            let errorMessage = "I couldn't understand the start time for the event: \(startTimeString). Please use 'YYYY-MM-DD HH:MM' format."
            self.messenger.post(to: buddyID, message: errorMessage)
            self.messageHistoryManager.recordMessage(for: buddyID, message: ChatMessage(role: "model", text: errorMessage))
            completion(errorMessage)
            return
        }

        var endDate: Date? = nil
        if let ets = endTimeString {
            endDate = dateFormatter.date(from: ets)
        }

        let finalEndDate = endDate ?? startDate.addingTimeInterval(3600)

        googleCalendarAPI.addEvent(title: title, startDate: startDate, endDate: finalEndDate, location: location, description: description) { [weak self] event, error in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                var messageToUser: String
                if let error = error {
                    messageToUser = "Failed to add event to Google Calendar: \(error.localizedDescription)"
                } else if let event = event {
                    messageToUser = "I've successfully added '\(event.summary)' to your Google Calendar!"
                } else {
                    messageToUser = "Failed to add event to Google Calendar: Unknown error."
                }
                self.messenger.post(to: buddyID, message: messageToUser)
                self.messageHistoryManager.recordMessage(for: buddyID, message: ChatMessage(role: "model", text: messageToUser))
                completion(messageToUser)
            }
        }
    }


    // MARK: - Proactive Cosmic Scout Monitoring

    func startMonitoringScreenContent() {
            setupProactiveCosmicScoutMonitoring()
        }

        private func setupProactiveCosmicScoutMonitoring() {
            proactiveUpdateTimer?.invalidate()
            proactiveUpdateTimer = Timer.scheduledTimer(withTimeInterval: proactiveUpdateInterval, repeats: true) { [weak self] _ in
                self?.checkForNewCosmicScoutUpdates()
            }
            checkForNewCosmicScoutUpdates()
        }

        private func checkForNewCosmicScoutUpdates() {
            let cosmicScoutID = "cosmicscout"
            let lastInfo = messageHistoryManager.getLastSpaceUpdateInfo(for: cosmicScoutID)
            let twentyFourHoursAgo = Date().addingTimeInterval(-24 * 60 * 60)
            let fromDateForNews = (lastInfo?.lastCheckDate ?? Date()) > Date() ? twentyFourHoursAgo : (lastInfo?.lastCheckDate ?? twentyFourHoursAgo)
            cosmicScoutDataFetcher.fetchSpaceNews(fromDate: fromDateForNews) { [weak self] newEvents, error in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    if let error = error { return }
                    guard let newEvents = newEvents, !newEvents.isEmpty else {
                        self.messageHistoryManager.updateLastSpaceUpdate(for: cosmicScoutID, checkedDate: Date())
                        return
                    }
                    let relevantProactiveNews = newEvents.filter { event in
                        event.date > fromDateForNews && !self.messageHistoryManager.hasRecentSimilarSpaceUpdate(for: cosmicScoutID, newsTitles: [event.title])
                    }.sorted { $0.date > $1.date }
                    if let latestEvent = relevantProactiveNews.first {
                        self.proactivelyNotifyUserOfNews(buddyID: cosmicScoutID, event: latestEvent)
                        self.messageHistoryManager.updateLastSpaceUpdate(for: cosmicScoutID, checkedDate: Date(), newsTitles: [latestEvent.title])
                    }
                }
            }

            let lastSatelliteUpdateInfo = messageHistoryManager.getLastSpaceUpdateInfo(for: cosmicScoutID)
            let fromDateForSatellites = (lastSatelliteUpdateInfo?.lastCheckDate ?? Date()) > Date() ? twentyFourHoursAgo : (lastSatelliteUpdateInfo?.lastCheckDate ?? twentyFourHoursAgo)
            cosmicScoutDataFetcher.fetchSatelliteFlyovers { [weak self] newPasses, error in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    if let error = error { return }
                    guard let newPasses = newPasses, !newPasses.isEmpty else {
                        self.messageHistoryManager.updateLastSpaceUpdate(for: cosmicScoutID, checkedDate: Date())
                        return
                    }
                    // Simplified the expression to aid compiler type-checking
                    let relevantProactivePasses = newPasses.filter { pass in
                        let isRecent = pass.startTime > Date().addingTimeInterval(-5 * 60)
                        let isUpcomingWithin24Hours = pass.startTime < Date().addingTimeInterval(24 * 60 * 60)
                        let hasNoRecentSimilarUpdate = !self.messageHistoryManager.hasRecentSimilarSpaceUpdate(for: cosmicScoutID, satellitePasses: [pass])
                        return isRecent && isUpcomingWithin24Hours && hasNoRecentSimilarUpdate
                    }.sorted { $0.startTime < $1.startTime }


                    if let nextPass = relevantProactivePasses.first {
                        self.proactivelyNotifyUserOfSatellitePasses(buddyID: cosmicScoutID, pass: nextPass)
                        self.messageHistoryManager.updateLastSpaceUpdate(for: cosmicScoutID, checkedDate: Date(), satellitePasses: [nextPass])
                    }
                }
            }
        }

        private func proactivelyNotifyUserOfNews(buddyID: String, event: SpaceEvent) {
            let message = "Cosmic Scout: New cosmic discovery! \(event.title). Explore more!"
            self.messenger.post(to: buddyID, message: message)
        }

        private func proactivelyNotifyUserOfSatellitePasses(buddyID: String, pass: SatellitePass) {
            let startTime = pass.startTime.formatted(date: .omitted, time: .shortened)
            let message = "Cosmic Scout: Look up! The \(pass.satelliteName) will be visible starting around \(startTime)!"
            self.messenger.post(to: buddyID, message: message)
        }
}
