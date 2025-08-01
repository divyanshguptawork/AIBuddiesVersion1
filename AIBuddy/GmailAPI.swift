import Foundation

// Updated GmailMessage struct to include 'from' and 'body'
struct GmailMessage {
    let id: String
    let subject: String?
    let snippet: String
    let date: Date?
    let from: String? // Added 'from' field
    let body: String? // Added 'body' field for full content
}

class GmailAPI {
    static let shared = GmailAPI()

    private init() {}

    // fetchRecentMessages now returns a Result type
    func fetchRecentMessages(maxResults: Int = 10, completion: @escaping (Result<[GmailMessage], Error>) -> Void) {
        print("GmailAPI: Attempting to fetch recent messages.")
        // Corrected: Use OAuthManager.shared.getAccessToken
        OAuthManager.shared.getAccessToken { token, error in // Corrected function call and signature
            guard let token = token, error == nil else {
                // Corrected: Pass the actual error from OAuthManager if available, otherwise create a generic one.
                let authError = error ?? OAuthError.notAuthorized("Gmail not connected or not authorized.")
                print("GmailAPI: No access token or error from OAuthManager: \(authError.localizedDescription)")
                completion(.failure(authError))
                return
            }
            print("GmailAPI: Successfully received token from OAuthManager. Token starts with: \(token.prefix(10))...")

            let urlString = "https://gmail.googleapis.com/gmail/v1/users/me/messages?maxResults=\(maxResults)"
            guard let url = URL(string: urlString) else {
                let urlError = NSError(domain: "GmailAPI", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL for message list."])
                print("GmailAPI: Invalid URL for message list: \(urlString)")
                completion(.failure(urlError))
                return
            }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            print("GmailAPI: Making request to list messages: \(url.absoluteString)")

            URLSession.shared.dataTask(with: request) { data, response, error in
                if let httpResponse = response as? HTTPURLResponse {
                    print("GmailAPI: List messages API - HTTP Status Code: \(httpResponse.statusCode)")
                    if httpResponse.statusCode != 200 {
                        if let data = data, let errorString = String(data: data, encoding: .utf8) {
                            print("GmailAPI: List messages API - Error Response Body: \(errorString)")
                        }
                        let httpError = NSError(domain: "GmailAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP Error listing messages"])
                        completion(.failure(httpError))
                        return
                    }
                }

                guard let safeData = data, error == nil else {
                    let networkError = error ?? NSError(domain: "GmailAPI", code: 500, userInfo: [NSLocalizedDescriptionKey: "Network or data error fetching message list."])
                    print("GmailAPI: Gmail fetch failed (data or network error): \(networkError.localizedDescription)")
                    completion(.failure(networkError))
                    return
                }

                do {
                    let list = try JSONDecoder().decode(MessageList.self, from: safeData)
                    guard let messagesMeta = list.messages, !messagesMeta.isEmpty else {
                        print("GmailAPI: No messages found in the list response or messages array is empty.")
                        DispatchQueue.main.async { completion(.success([])) }
                        return
                    }
                    print("GmailAPI: Successfully listed \(messagesMeta.count) message IDs.")

                    let group = DispatchGroup()
                    var messages: [GmailMessage] = []
                    let lock = NSLock() // To safely append to 'messages' from concurrent tasks

                    for messageMeta in messagesMeta.prefix(maxResults) { // Ensure we don't exceed maxResults
                        group.enter()
                        // Request 'format=full' to get the full body content
                        self.fetchMessageDetail(id: messageMeta.id, token: token, format: "full") { detailedMessage in
                            lock.lock()
                            if let detailedMessage = detailedMessage {
                                messages.append(detailedMessage)
                            }
                            lock.unlock()
                            group.leave()
                        }
                    }

                    group.notify(queue: .main) {
                        // Sort messages by date, newest first, before returning
                        messages.sort { ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast) }
                        print("GmailAPI: Finished fetching details for \(messages.count) messages.")
                        completion(.success(messages))
                    }

                } catch {
                    print("❌ GmailAPI: Parsing Gmail list failed (JSON decoding error): \(error)")
                    if let data = data, let jsonError = String(data: data, encoding: .utf8) {
                        print("GmailAPI: Raw JSON data that failed decoding: \(jsonError)")
                    }
                    completion(.failure(error))
                }
            }.resume()
        }
    }

    // fetchMessageDetail now takes a 'format' parameter and returns GmailMessage?
    private func fetchMessageDetail(id: String, token: String, format: String, completion: @escaping (GmailMessage?) -> Void) {
        // Use 'format' parameter in the URL
        let urlString = "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)?format=\(format)"
        guard let url = URL(string: urlString) else {
            print("GmailAPI: Invalid URL for message detail: \(urlString)")
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        print("GmailAPI: Making request to get message details for \(id)")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let httpResponse = response as? HTTPURLResponse {
                print("GmailAPI: Message detail API - HTTP Status Code for \(id): \(httpResponse.statusCode)")
                if httpResponse.statusCode != 200 {
                    if let data = data, let errorString = String(data: data, encoding: .utf8) {
                        print("GmailAPI: Message detail API - Error Response Body for \(id): \(errorString)")
                    }
                    completion(nil)
                    return
                }
            }

            guard let safeData = data, error == nil else {
                print("❌ GmailAPI: Message detail fetch failed (data or network error) for ID \(id): \(error?.localizedDescription ?? "unknown error")")
                completion(nil)
                return
            }

            do {
                let messageDetail = try JSONDecoder().decode(GmailMessageDetail.self, from: safeData)
                print("GmailAPI: Successfully decoded message details for \(id).")

                // FIX: Use reduce(into:) to handle duplicate header names gracefully
                let headers = messageDetail.payload.headers.reduce(into: [String: String]()) { result, header in
                    result[header.name.lowercased()] = header.value
                }

                let subject = headers["subject"]
                let from = headers["from"] // Extract 'From' header
                let snippet = messageDetail.snippet
                var date: Date? = nil

                if let dateStr = headers["date"] {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "E, dd MMM yyyy HH:mm:ss Z"
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    date = formatter.date(from: dateStr)
                }

                // Extract body content
                let bodyContent = messageDetail.payload.parts?.first(where: { $0.mimeType == "text/plain" })?.body?.data
                let decodedBody = bodyContent.flatMap { dataString in
                    Data(base64Encoded: dataString.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/"))
                        .flatMap { String(data: $0, encoding: .utf8) }
                }

                let message = GmailMessage(id: messageDetail.id, subject: subject, snippet: snippet, date: date, from: from, body: decodedBody)
                completion(message)

            } catch {
                print("❌ GmailAPI: Message detail parsing failed (JSON decoding error) for ID \(id): \(error)")
                if let data = data, let jsonError = String(data: data, encoding: .utf8) {
                    print("GmailAPI: Raw JSON data that failed decoding for ID \(id): \(jsonError)")
                }
                completion(nil)
            }
        }.resume()
    }
}

// MARK: - Codable Structs for Gmail API Responses

struct MessageList: Codable {
    let messages: [MessageMeta]?
    let resultSizeEstimate: Int?
}

struct MessageMeta: Codable {
    let id: String
}

struct GmailMessageDetail: Codable {
    let id: String
    let snippet: String
    let payload: Payload
}

struct Payload: Codable {
    let headers: [Header]
    let parts: [Part]? // Added for nested parts (e.g., text/plain body)
    let body: Body? // For simple messages where body is directly under payload
}

struct Header: Codable {
    let name: String
    let value: String
}

// Added for parsing email body content
struct Part: Codable {
    let partId: String?
    let mimeType: String?
    let filename: String?
    let headers: [Header]?
    let body: Body?
}

struct Body: Codable {
    let size: Int
    let data: String? // Base64url encoded string
}
