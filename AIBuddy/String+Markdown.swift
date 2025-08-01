import Foundation

extension String {
    func removingMarkdown() -> String {
        var cleanedString = self
        // Remove bold (**text** or __text__)
        cleanedString = cleanedString.replacingOccurrences(of: "\\*\\*|__", with: "", options: .regularExpression)
        // Remove italics (*text* or _text_)
        cleanedString = cleanedString.replacingOccurrences(of: "\\*|_", with: "", options: .regularExpression)
        // Remove headings (# Heading)
        cleanedString = cleanedString.replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)
        // Remove bullet points (- item, * item, + item)
        cleanedString = cleanedString.replacingOccurrences(of: "^[-*+]\\s*", with: "", options: .regularExpression)
        // Remove code blocks (```code```) and inline code (`code`)
        cleanedString = cleanedString.replacingOccurrences(of: "```.*?```", with: "", options: .regularExpression, range: nil)
        cleanedString = cleanedString.replacingOccurrences(of: "`[^`]*`", with: "", options: .regularExpression)
        // Remove links ([text](url)) - keep text
        cleanedString = cleanedString.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)
        // Remove extra newlines or leading/trailing whitespace
        cleanedString = cleanedString.trimmingCharacters(in: .whitespacesAndNewlines)
        cleanedString = cleanedString.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression) // Replace multiple spaces with one

        return cleanedString
    }
}
