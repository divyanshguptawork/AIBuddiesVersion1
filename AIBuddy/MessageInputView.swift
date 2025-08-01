import SwiftUI

struct MessageInputView: View {
    @Binding var inputText: String
    var onSend: (String) -> Void

    @State private var textHeight: CGFloat = 30

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(alignment: .bottom) {
                GrowingTextView(text: $inputText, height: $textHeight, onReturn: sendMessage)
                    .frame(minHeight: 30, maxHeight: 100)
                    .padding(6)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.4)))

                Button(action: {
                    sendMessage()
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .resizable()
                        .frame(width: 26, height: 26)
                        .foregroundColor(.blue)
                        .padding(.bottom, 4)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(10)
        }
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSend(trimmed)
        inputText = ""
        textHeight = 30
    }
}
