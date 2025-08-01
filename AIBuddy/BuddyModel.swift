// MARK: - BuddyModel.swift
import Foundation
import SwiftUI // For Color
import AppKit // Added for NSColor (macOS equivalent of UIKit's UIColor)

struct BuddyModel: Identifiable, Codable {
    let id: String // Unique identifier (e.g., "leopal", "cosmicscout", "spacecat")
    let name: String
    let iconName: String // SFSymbol name or asset name
    let avatar: String // Assumed 'avatar' is a String (e.g., "buddy_avatar_leopal")
    let personality: String // e.g., "helpful", "adventurous", "witty"
    let safePersonality: String // Required by BuddyCard.swift
    let accentColor: Color // For UI theming
    let isDefault: Bool // Is this a default buddy?
    let safeInterval: TimeInterval // Required by ContentView.swift (e.g., 2.0 seconds)

    // A custom initializer to handle Color which is not Codable by default
    init(id: String, name: String, iconName: String, avatar: String, personality: String, safePersonality: String, accentColor: Color, isDefault: Bool, safeInterval: TimeInterval) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.avatar = avatar
        self.personality = personality
        self.safePersonality = safePersonality
        self.accentColor = accentColor
        self.isDefault = isDefault
        self.safeInterval = safeInterval
    }

    // Custom Decoding
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        iconName = try container.decode(String.self, forKey: .iconName)
        avatar = try container.decode(String.self, forKey: .avatar)
        personality = try container.decode(String.self, forKey: .personality)
        safePersonality = try container.decode(String.self, forKey: .safePersonality)
        isDefault = try container.decode(Bool.self, forKey: .isDefault)
        safeInterval = try container.decode(TimeInterval.self, forKey: .safeInterval)

        // Decode Color from RGBA components
        let red = try container.decode(Double.self, forKey: .red)
        let green = try container.decode(Double.self, forKey: .green)
        let blue = try container.decode(Double.self, forKey: .blue)
        let alpha = try container.decode(Double.self, forKey: .alpha)
        accentColor = Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    // Custom Encoding
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(iconName, forKey: .iconName)
        try container.encode(avatar, forKey: .avatar)
        try container.encode(personality, forKey: .personality)
        try container.encode(safePersonality, forKey: .safePersonality)
        try container.encode(isDefault, forKey: .isDefault)
        try container.encode(safeInterval, forKey: .safeInterval)

        // Encode Color as RGBA components using NSColor
        let nsColor = NSColor(accentColor) // Convert SwiftUI.Color to AppKit.NSColor
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        nsColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) // Get components

        try container.encode(Double(red), forKey: .red)
        try container.encode(Double(green), forKey: .green)
        try container.encode(Double(blue), forKey: .blue)
        try container.encode(Double(alpha), forKey: .alpha)
    }

    // Define CodingKeys for custom Codable conformance
    private enum CodingKeys: String, CodingKey {
        case id, name, iconName, avatar, personality, safePersonality, isDefault, safeInterval
        case red, green, blue, alpha // Keys for Color components
    }
}

// Extension to get RGBA components from SwiftUI.Color (via NSColor)
// This extension is no longer strictly necessary if components are directly accessed in encode(to:)
// but can be kept for consistency or if other parts of the codebase use it.
extension NSColor {
    // Helper to get RGBA components as Doubles
    var rgba: (red: Double, green: Double, blue: Double, alpha: Double) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        self.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (Double(red), Double(green), Double(blue), Double(alpha))
    }
}


extension BuddyModel {
    static let allBuddies: [BuddyModel] = [
        BuddyModel(id: "leopal", name: "LeoPal", iconName: "lightbulb.fill", avatar: "leopal_avatar", personality: "helpful and organized", safePersonality: "helpful", accentColor: .blue, isDefault: true, safeInterval: 2.0),
        BuddyModel(id: "cosmicscout", name: "Cosmic Scout", iconName: "satellite.dish.fill", avatar: "cosmicscout_avatar", personality: "enthusiastic, awe-struck, and knowledgeable about space", safePersonality: "enthusiastic", accentColor: .purple, isDefault: true, safeInterval: 3.0),
        BuddyModel(id: "spacecat", name: "SpaceCat", iconName: "cat.fill", avatar: "spacecat_avatar", personality: "witty, sarcastic, and humorous", safePersonality: "witty", accentColor: .orange, isDefault: true, safeInterval: 2.5),
        // Add more buddies as needed
    ]
    
    static func getBuddy(byID id: String) -> BuddyModel? {
        return allBuddies.first(where: { $0.id == id })
    }
}
