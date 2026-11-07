import Foundation

/// XP amounts. The server (supabase/migrations, function `xp_for_event`) is the source of truth;
/// the app uses these only to show provisional XP before sync confirms it. Keep both in sync.
public enum XPRules {
    public static let addPlant = 20

    /// XP for one care event. Watering again sooner than 60% of the species' shortest
    /// interval earns nothing, so the game never rewards overwatering.
    public static func xp(for type: CareEventType, daysSincePreviousWatering: Double?, speciesMinWateringDays: Int) -> Int {
        switch type {
        case .water:
            if let days = daysSincePreviousWatering, days < Double(speciesMinWateringDays) * 0.6 { return 0 }
            return 10
        case .fertilize, .repot: return 15
        case .prune: return 10
        case .inspect, .note, .skipWater: return 5
        }
    }
}

public enum GrowthStage: Int, Codable, CaseIterable, Sendable {
    case small = 1, growing, mature, thriving
}

/// Per-plant levels. Cosmetic and educational only: they do not describe real growth.
public enum PlantLevel {
    public static let thresholds = [0, 50, 150, 350, 700]

    public static func level(forXP xp: Int) -> Int {
        thresholds.lastIndex(where: { xp >= $0 }).map { $0 + 1 } ?? 1
    }

    /// XP needed for the next level, or nil at the top level.
    public static func nextThreshold(forXP xp: Int) -> Int? {
        thresholds.first(where: { $0 > xp })
    }

    public static func growthStage(level: Int, mood: PlantMood) -> GrowthStage {
        switch level {
        case ...1: return .small
        case 2...3: return .growing
        case 4: return .mature
        default: return mood == .thriving ? .thriving : .mature
        }
    }
}

/// Garden level from total XP: level L starts at 100 × (L − 1)^1.5 XP.
public enum GardenLevel {
    public static func level(forTotalXP xp: Int) -> Int {
        guard xp > 0 else { return 1 }
        var level = Int(pow(Double(xp) / 100, 1 / 1.5)) + 1
        // Correct floating point drift at exact boundaries.
        while threshold(for: level + 1) <= xp { level += 1 }
        while level > 1 && threshold(for: level) > xp { level -= 1 }
        return level
    }

    public static func threshold(for level: Int) -> Int {
        guard level > 1 else { return 0 }
        return Int((100 * pow(Double(level - 1), 1.5)).rounded())
    }
}
