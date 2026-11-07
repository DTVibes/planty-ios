import Foundation

public enum PlantMood: String, Codable, CaseIterable, Sendable {
    case thriving, happy, neutral, thirsty
    case needsAttention = "needs_attention"
}

/// A rough estimate, never shown as a measured value.
public enum HealthEstimate: String, Codable, Sendable {
    case good, fair, check
}

public struct PlantCondition: Equatable, Sendable {
    public let mood: PlantMood
    public let health: HealthEstimate
    /// Estimated watering status in five steps, 0 (likely dry) to 4 (recently watered).
    /// The UI must label this as an estimate: a phone cannot measure soil moisture.
    public let waterLevel: Int
}

/// Turns care history and the current watering window into mood, health and water level.
public struct ConditionCalculator: Sendable {
    static let day: TimeInterval = 86_400

    public init() {}

    public func condition(water: CareRecommendation, events: [CareEvent], now: Date) -> PlantCondition {
        let live = events.filter { !$0.isDeleted }
        let level = waterLevel(water: water, now: now)

        let lastInspection = live.live(.inspect).last
        let problemOpen = lastInspection.map { $0.problemNoted && now.timeIntervalSince($0.completedAt) < 30 * Self.day } ?? false

        let windowLength = max(Self.day, water.windowEnd.timeIntervalSince(water.windowStart))
        let pastEnd = now.timeIntervalSince(water.windowEnd)
        let badlyOverdue = water.state == .overdue && pastEnd > max(2 * Self.day, 0.5 * windowLength)

        let mood: PlantMood
        if problemOpen || badlyOverdue {
            mood = .needsAttention
        } else if water.state != .scheduled && water.basedOn != nil {
            mood = .thirsty
        } else if isThriving(events: live, now: now) {
            mood = .thriving
        } else if live.contains(where: { now.timeIntervalSince($0.completedAt) <= 14 * Self.day && $0.type != .note }) {
            mood = .happy
        } else {
            mood = .neutral
        }

        let health: HealthEstimate
        switch mood {
        case .needsAttention: health = .check
        case .thirsty where water.state == .overdue: health = .fair
        default: health = .good
        }
        return PlantCondition(mood: mood, health: health, waterLevel: level)
    }

    /// At least four real care actions in the last 30 days, spread over two or more weeks.
    func isThriving(events: [CareEvent], now: Date) -> Bool {
        let recent = events.filter {
            $0.type != .note && now.timeIntervalSince($0.completedAt) <= 30 * Self.day && $0.completedAt <= now
        }
        guard recent.count >= 4,
              let first = recent.map(\.completedAt).min(),
              let last = recent.map(\.completedAt).max() else { return false }
        return last.timeIntervalSince(first) >= 14 * Self.day
    }

    func waterLevel(water: CareRecommendation, now: Date) -> Int {
        guard let base = water.basedOn else { return 2 }
        let total = water.windowEnd.timeIntervalSince(base)
        guard total > 0 else { return 0 }
        let progress = now.timeIntervalSince(base) / total
        let step = Int((progress * 4).rounded(.down))
        return max(0, min(4, 4 - step))
    }
}
