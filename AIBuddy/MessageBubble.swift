import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage
    @State private var revealedText: String = ""
    @State private var typingDots: String = ""
    private let typingAnimationTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack {
            if message.role == "user" {
                Spacer()
                Text(message.text) // User messages are not streamed
                    .padding(12)
                    .foregroundColor(.white)
                    .background(Color(hex: "#007AFF")) // iMessage blue
                    .cornerRadius(18)
                    .frame(maxWidth: 300, alignment: .trailing)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            } else { // Implies message.role == "model"
                VStack(alignment: .leading, spacing: 4) {
                    if message.isTyping {
                        HStack(spacing: 4) {
                            Circle().frame(width: 6, height: 6).opacity(typingDots.count >= 1 ? 1 : 0.3)
                            Circle().frame(width: 6, height: 6).opacity(typingDots.count >= 2 ? 1 : 0.3)
                            Circle().frame(width: 6, height: 6).opacity(typingDots.count >= 3 ? 1 : 0.3)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(10)
                        .onAppear(perform: startTypingAnimation)
                        .onDisappear(perform: stopTypingAnimation)
                    } else {
                        // Display the revealedText which is updated word by word
                        Text(revealedText)
                            .padding(12)
                            .foregroundColor(.white)
                            .background(Color.gray.opacity(0.25)) // AI response background
                            .cornerRadius(18)
                            .frame(maxWidth: 300, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .onAppear {
                                // When the message bubble appears, start animating the text if it's new
                                animateText(newText: message.displayedText)
                            }
                            .onChange(of: message.displayedText) { newText in
                                // If the displayedText updates (during streaming), continue animating
                                animateText(newText: newText)
                            }
                    }
                }
                Spacer()
            }
        }
    }

    // Timer for animating typing dots
    @State private var timer: Timer?

    private func startTypingAnimation() {
        var dotCount = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            dotCount = (dotCount + 1) % 4
            typingDots = String(repeating: ".", count: dotCount)
        }
    }

    private func stopTypingAnimation() {
        timer?.invalidate()
        timer = nil
        typingDots = ""
    }

    // Function to animate text word by word
    private func animateText(newText: String) {
        // If the message is still typing, or the revealed text already matches the new text, do nothing.
        guard !message.isTyping, revealedText != newText else { return }

        let words = newText.split(separator: " ").map(String.init)
        var currentWordIndex = 0
        revealedText = "" // Start with empty text for new animation

        // Invalidate any existing timer to prevent multiple animations running concurrently
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in // Adjust interval for speed
            if currentWordIndex < words.count {
                revealedText += (currentWordIndex > 0 ? " " : "") + words[currentWordIndex]
                currentWordIndex += 1
            } else {
                timer.invalidate()
            }
        }
    }
}

// MARK: - HEX Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let scanner = Scanner(string: hex)
        _ = scanner.scanString("#")

        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)

        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255

        self.init(red: r, green: g, blue: b)
    }
}
