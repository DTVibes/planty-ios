import Foundation

public enum PotSize: String, Codable, CaseIterable, Sendable {
    case small, medium, large
}

public enum LightLevel: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case brightIndirect = "bright_indirect"
    case direct
}

public enum PlantLocation: String, Codable, CaseIterable, Sendable {
    case livingRoom = "living_room"
    case bedroom, kitchen, bathroom, office, balcony, outdoor, other

    /// Spots where a plant is exposed to sun and wind and dries out faster in summer.
    public var isExposed: Bool { self == .balcony || self == .outdoor }
}

public enum Hemisphere: String, Codable, Sendable {
    case north, south
}

/// Care needs of a species, taken from the curated botanical database.
/// Every value must be backed by a cited source in `plant_species.source_refs`.
public struct CareRequirements: Codable, Hashable, Sendable {
    /// Typical days between waterings in spring and autumn, from the low to the high end.
    public var wateringDays: ClosedRange<Int>
    /// Days between feedings in the growing season, or nil when the species is rarely fed.
    public var fertilizeIntervalDays: Int?
    public var fertilizeInWinter: Bool
    public var inspectIntervalDays: Int
    public var preferredLight: LightLevel

    public init(
        wateringDays: ClosedRange<Int>,
        fertilizeIntervalDays: Int? = nil,
        fertilizeInWinter: Bool = false,
        inspectIntervalDays: Int = 30,
        preferredLight: LightLevel = .brightIndirect
    ) {
        self.wateringDays = wateringDays
        self.fertilizeIntervalDays = fertilizeIntervalDays
        self.fertilizeInWinter = fertilizeInWinter
        self.inspectIntervalDays = inspectIntervalDays
        self.preferredLight = preferredLight
    }
}

public struct PlantSpecies: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var scientificName: String
    /// Common names keyed by locale code ("en", "de", "ru").
    public var commonNames: [String: String]
    public var care: CareRequirements

    public init(id: UUID = UUID(), scientificName: String, commonNames: [String: String], care: CareRequirements) {
        self.id = id
        self.scientificName = scientificName
        self.commonNames = commonNames
        self.care = care
    }

    public func commonName(for locale: String) -> String {
        commonNames[locale] ?? commonNames["en"] ?? scientificName
    }
}

public struct UserPlant: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var speciesID: UUID
    public var customName: String
    public var acquiredAt: Date?
    public var location: PlantLocation?
    public var light: LightLevel?
    public var potSize: PotSize?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        speciesID: UUID,
        customName: String,
        acquiredAt: Date? = nil,
        location: PlantLocation? = nil,
        light: LightLevel? = nil,
        potSize: PotSize? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.speciesID = speciesID
        self.customName = customName
        self.acquiredAt = acquiredAt
        self.location = location
        self.light = light
        self.potSize = potSize
        self.createdAt = createdAt
    }
}
