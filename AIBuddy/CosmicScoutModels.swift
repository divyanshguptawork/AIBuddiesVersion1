// MARK: - CosmicScoutModels.swift
import Foundation

// MARK: - NewsAPI Response Structures
struct NewsAPIResponse: Codable {
    let status: String
    let totalResults: Int?
    let articles: [Article]?
    let code: String?
    let message: String?

    struct Article: Codable {
        let source: Source
        let author: String?
        let title: String
        let description: String?
        let url: String
        let urlToImage: String?
        let publishedAt: String
        let content: String?
    }

    struct Source: Codable {
        let id: String?
        let name: String
    }
}

// MARK: - N2YO API Response Structures
struct N2YOPassResponse: Codable {
    let info: N2YOInfo
    let passes: [N2YOSatellitePass]?
}

struct N2YOInfo: Codable {
    let satid: Int
    let satname: String
    let transactionscount: Int
    let passescount: Int
}

struct N2YOSatellitePass: Codable, Hashable, Identifiable {
    let id: UUID // This ID is for Identifiable conformance within the app, not part of the N2YO JSON.

    let startAz: Double
    let startAzCompass: String
    let startEl: Double
    let startUTC: TimeInterval
    let maxAz: Double
    let maxAzCompass: String
    let maxEl: Double
    let maxUTC: TimeInterval
    let endAz: Double
    let endAzCompass: String
    let endEl: Double
    let endUTC: TimeInterval
    let mag: Double
    let duration: Int
    let startVisibility: TimeInterval?
    
    // Custom properties not directly from N2YO API, but useful for app logic
    let satelliteName: String
    let direction: String


    // Custom initializer for creating N2YOSatellitePass instances from raw data
    init(startAz: Double, startAzCompass: String, startEl: Double, startUTC: TimeInterval,
         maxAz: Double, maxAzCompass: String, maxEl: Double, maxUTC: TimeInterval,
         endAz: Double, endAzCompass: String, endEl: Double, endUTC: TimeInterval,
         mag: Double, duration: Int, startVisibility: TimeInterval?,
         satelliteName: String, direction: String) {
        self.id = UUID() // Generate a new UUID for each instance created this way
        self.startAz = startAz
        self.startAzCompass = startAzCompass
        self.startEl = startEl
        self.startUTC = startUTC
        self.maxAz = maxAz
        self.maxAzCompass = maxAzCompass
        self.maxEl = maxEl
        self.maxUTC = maxUTC
        self.endAz = endAz
        self.endAzCompass = endAzCompass
        self.endEl = endEl
        self.endUTC = endUTC
        self.mag = mag
        self.duration = duration
        self.startVisibility = startVisibility
        self.satelliteName = satelliteName
        self.direction = direction
    }

    // Manual Codable implementation to ignore 'id', 'satelliteName', 'direction' during encoding/decoding,
    // assuming they are derived or added post-decoding.
    // If you intend to persist these, you need to add them to CodingKeys and handle their encoding/decoding.
    enum CodingKeys: String, CodingKey {
        case startAz, startAzCompass, startEl, startUTC
        case maxAz, maxAzCompass, maxEl, maxUTC
        case endAz, endAzCompass, endEl, endUTC
        case mag, duration, startVisibility
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.startAz = try container.decode(Double.self, forKey: .startAz)
        self.startAzCompass = try container.decode(String.self, forKey: .startAzCompass)
        self.startEl = try container.decode(Double.self, forKey: .startEl)
        self.startUTC = try container.decode(TimeInterval.self, forKey: .startUTC)
        self.maxAz = try container.decode(Double.self, forKey: .maxAz)
        self.maxAzCompass = try container.decode(String.self, forKey: .maxAzCompass)
        self.maxEl = try container.decode(Double.self, forKey: .maxEl)
        self.maxUTC = try container.decode(TimeInterval.self, forKey: .maxUTC)
        self.endAz = try container.decode(Double.self, forKey: .endAz)
        try self.endAzCompass = container.decode(String.self, forKey: .endAzCompass)
        try self.endEl = container.decode(Double.self, forKey: .endEl)
        try self.endUTC = container.decode(TimeInterval.self, forKey: .endUTC)
        self.mag = try container.decode(Double.self, forKey: .mag)
        self.duration = try container.decode(Int.self, forKey: .duration)
        self.startVisibility = try container.decodeIfPresent(TimeInterval.self, forKey: .startVisibility)
        self.id = UUID() // Generate UUID upon decoding from JSON

        // Provide default values or decode from context if available
        self.satelliteName = "Unknown Satellite" // Placeholder
        self.direction = "Unknown Direction" // Placeholder
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(startAz, forKey: .startAz)
        try container.encode(startAzCompass, forKey: .startAzCompass)
        try container.encode(startEl, forKey: .startEl)
        try container.encode(startUTC, forKey: .startUTC)
        try container.encode(maxAz, forKey: .maxAz)
        try container.encode(maxAzCompass, forKey: .maxAzCompass)
        try container.encode(maxEl, forKey: .maxEl)
        try container.encode(maxUTC, forKey: .maxUTC)
        try container.encode(endAz, forKey: .endAz)
        try container.encode(endAzCompass, forKey: .endAzCompass)
        try container.encode(endEl, forKey: .endEl)
        try container.encode(endUTC, forKey: .endUTC)
        try container.encode(mag, forKey: .mag)
        try container.encode(duration, forKey: .duration)
        try container.encodeIfPresent(startVisibility, forKey: .startVisibility)
    }

    // Computed properties for easier use in SwiftUI Views
    var startTime: Date {
        Date(timeIntervalSince1970: startUTC)
    }

    var endTime: Date {
        Date(timeIntervalSince1970: endUTC)
    }
    
    // Conformance to Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(startUTC)
        hasher.combine(maxUTC)
        hasher.combine(endUTC)
        hasher.combine(startAz)
        hasher.combine(endAz)
        hasher.combine(maxEl)
        hasher.combine(mag)
        hasher.combine(duration)
        hasher.combine(satelliteName) // Include satelliteName in hash
        hasher.combine(direction) // Include direction in hash
    }

    static func == (lhs: N2YOSatellitePass, rhs: N2YOSatellitePass) -> Bool {
        return lhs.startUTC == rhs.startUTC &&
               lhs.endUTC == rhs.endUTC &&
               lhs.maxUTC == rhs.maxUTC &&
               lhs.startAz == rhs.startAz &&
               lhs.endAz == rhs.endAz &&
               lhs.maxEl == rhs.maxEl &&
               lhs.mag == rhs.mag &&
               lhs.duration == rhs.duration &&
               lhs.satelliteName == rhs.satelliteName &&
               lhs.direction == rhs.direction
    }
}

// Dummy N2YOErrorResponse for decoding N2YO API error messages
struct N2YOErrorResponse: Codable {
    let error: String?
}

// MARK: - Internal App Data Models (SpaceEvent)
struct SpaceEvent: Identifiable, Codable, Equatable, Hashable {
    let id = UUID() // Unique ID for Identifiable conformance
    let title: String
    let description: String?
    let date: Date
    let sourceURL: URL
    let type: String
    let sourceName: String

    // Conformance to Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(title)
        hasher.combine(description)
        hasher.combine(date)
        hasher.combine(sourceURL)
        hasher.combine(type)
        hasher.combine(sourceName)
    }

    // Conformance to Equatable
    static func == (lhs: SpaceEvent, rhs: SpaceEvent) -> Bool {
        return lhs.title == rhs.title &&
               lhs.description == rhs.description &&
               lhs.date == rhs.date &&
               lhs.sourceURL == rhs.sourceURL &&
               lhs.type == rhs.type &&
               lhs.sourceName == rhs.sourceName
    }
}

// MARK: - Use typealias for SatellitePass to refer to N2YOSatellitePass
typealias SatellitePass = N2YOSatellitePass

// MARK: - SpaceUpdateInfo
struct SpaceUpdateInfo: Codable, Equatable, Hashable {
    var lastCheckDate: Date
    var lastNotifiedNewsTitles: [String] // To prevent re-notifying same news
    var lastNotifiedSatellitePasses: [SatellitePass] // To prevent re-notifying same passes

    init(lastCheckDate: Date = .distantPast, lastNotifiedNewsTitles: [String] = [], lastNotifiedSatellitePasses: [SatellitePass] = []) {
        self.lastCheckDate = lastCheckDate
        self.lastNotifiedNewsTitles = lastNotifiedNewsTitles
        self.lastNotifiedSatellitePasses = lastNotifiedSatellitePasses
    }

    // Conformance to Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(lastCheckDate)
        lastNotifiedNewsTitles.forEach { hasher.combine($0) }
        lastNotifiedSatellitePasses.forEach { hasher.combine($0) }
    }

    // Conformance to Equatable
    static func == (lhs: SpaceUpdateInfo, rhs: SpaceUpdateInfo) -> Bool {
        return lhs.lastCheckDate == rhs.lastCheckDate &&
               lhs.lastNotifiedNewsTitles == rhs.lastNotifiedNewsTitles &&
               lhs.lastNotifiedSatellitePasses == rhs.lastNotifiedSatellitePasses
    }
}
