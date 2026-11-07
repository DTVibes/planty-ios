import Foundation

public enum Season: String, Codable, Sendable {
    case spring, summer, autumn, winter

    public static func of(_ date: Date, hemisphere: Hemisphere, calendar: Calendar) -> Season {
        let month = calendar.component(.month, from: date)
        let north: Season
        switch month {
        case 3...5: north = .spring
        case 6...8: north = .summer
        case 9...11: north = .autumn
        default: north = .winter
        }
        guard hemisphere == .south else { return north }
        switch north {
        case .spring: return .autumn
        case .summer: return .winter
        case .autumn: return .spring
        case .winter: return .summer
        }
    }

    var wateringFactor: Double {
        switch self {
        case .summer: return 0.85
        case .spring, .autumn: return 1.0
        case .winter: return 1.4
        }
    }
}

public enum CareTaskKind: String, Codable, Sendable {
    case water, fertilize, inspect
}

public enum CareTaskState: String, Codable, Sendable {
    /// The care window has not opened yet.
    case scheduled
    /// Inside the window: the plant may need this now. Wording must stay "may need".
    case recommended
    /// Past the end of the window.
    case overdue
}

/// One reason behind a recommendation. The app turns `code` into localized text,
/// so the UI can always explain why a task is suggested.
public struct CareReason: Codable, Hashable, Sendable {
    public enum Code: String, Codable, Sendable {
        case speciesBaseline = "species_baseline"
        case season
        case potSize = "pot_size"
        case light
        case exposedLocation = "exposed_location"
        case personalHistory = "personal_history"
        case checkedNotNeeded = "checked_not_needed"
        case noHistory = "no_history"
        case restingSeason = "resting_season"
    }

    public let code: Code
    /// The multiplier this reason applied to the interval, when it applied one.
    public let factor: Double?

    public init(_ code: Code, factor: Double? = nil) {
        self.code = code
        self.factor = factor
    }
}

public struct CareRecommendation: Codable, Hashable, Sendable {
    public let kind: CareTaskKind
    public let windowStart: Date
    public let windowEnd: Date
    public let state: CareTaskState
    /// The event the window counts from (last watering), or nil without history.
    public let basedOn: Date?
    public let reasons: [CareReason]
}

public struct CareContext: Sendable {
    public var plant: UserPlant
    public var species: PlantSpecies
    public var events: [CareEvent]
    public var hemisphere: Hemisphere
    public var now: Date

    public init(plant: UserPlant, species: PlantSpecies, events: [CareEvent], hemisphere: Hemisphere = .north, now: Date) {
        self.plant = plant
        self.species = species
        self.events = events.filter { $0.plantID == plant.id }
        self.hemisphere = hemisphere
        self.now = now
    }
}

/// Deterministic, explainable care rules. Same inputs always give the same output.
/// The rules are documented in docs/care-engine.md; keep both in sync.
public struct CareEngine: Sendable {
    static let day: TimeInterval = 86_400
    /// How much of the user's own watering rhythm is blended in once there is enough history.
    static let personalWeight = 0.3
    static let personalMinIntervals = 3

    public var calendar: Calendar

    public init(calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.calendar = calendar
    }

    public func recommendations(for context: CareContext) -> [CareRecommendation] {
        [watering(for: context), fertilizing(for: context), inspection(for: context)].compactMap { $0 }
    }

    public func watering(for context: CareContext) -> CareRecommendation {
        let care = context.species.care
        var reasons: [CareReason] = [CareReason(.speciesBaseline)]
        var factor = 1.0

        let season = Season.of(context.now, hemisphere: context.hemisphere, calendar: calendar)
        if season.wateringFactor != 1 {
            factor *= season.wateringFactor
            reasons.append(CareReason(.season, factor: season.wateringFactor))
        }
        if let pot = context.plant.potSize, pot != .medium {
            let f = pot == .small ? 0.8 : 1.2
            factor *= f
            reasons.append(CareReason(.potSize, factor: f))
        }
        if let light = context.plant.light {
            let f: Double
            switch light {
            case .low: f = 1.2
            case .medium: f = 1.0
            case .brightIndirect: f = 0.9
            case .direct: f = 0.85
            }
            if f != 1 {
                factor *= f
                reasons.append(CareReason(.light, factor: f))
            }
        }
        if let location = context.plant.location, location.isExposed, season == .summer {
            factor *= 0.8
            reasons.append(CareReason(.exposedLocation, factor: 0.8))
        }

        let waterings = context.events.live(.water)
        guard let lastWater = waterings.last?.completedAt else {
            reasons.append(CareReason(.noHistory))
            return CareRecommendation(
                kind: .water,
                windowStart: context.now,
                windowEnd: context.now.addingTimeInterval(Double(care.wateringDays.lowerBound) * Self.day),
                state: .recommended,
                basedOn: nil,
                reasons: reasons
            )
        }

        let baselineMid = Double(care.wateringDays.lowerBound + care.wateringDays.upperBound) / 2 * factor
        if let personal = personalFactor(waterings: waterings, expectedMid: baselineMid) {
            factor *= personal
            reasons.append(CareReason(.personalHistory, factor: personal))
        }

        var start = lastWater.addingTimeInterval(Double(care.wateringDays.lowerBound) * factor * Self.day)
        var end = lastWater.addingTimeInterval(Double(care.wateringDays.upperBound) * factor * Self.day)

        // "Not needed yet" after the last watering pushes the window out from the day of the check.
        if let skip = context.events.live(.skipWater).last?.completedAt, skip > lastWater {
            let pushDays = max(2.0, (Double(care.wateringDays.lowerBound) * factor * 0.25).rounded())
            let span = end.timeIntervalSince(start)
            start = max(start, skip.addingTimeInterval(pushDays * Self.day))
            end = max(end, start.addingTimeInterval(span))
            reasons.append(CareReason(.checkedNotNeeded))
        }

        return CareRecommendation(
            kind: .water,
            windowStart: start,
            windowEnd: end,
            state: state(now: context.now, start: start, end: end),
            basedOn: lastWater,
            reasons: reasons
        )
    }

    public func fertilizing(for context: CareContext) -> CareRecommendation? {
        guard let interval = context.species.care.fertilizeIntervalDays else { return nil }
        let season = Season.of(context.now, hemisphere: context.hemisphere, calendar: calendar)
        if season == .winter && !context.species.care.fertilizeInWinter { return nil }
        let last = context.events.live(.fertilize).last?.completedAt ?? context.plant.createdAt
        let start = last.addingTimeInterval(Double(interval) * Self.day)
        let end = start.addingTimeInterval(14 * Self.day)
        return CareRecommendation(
            kind: .fertilize,
            windowStart: start,
            windowEnd: end,
            state: state(now: context.now, start: start, end: end),
            basedOn: last,
            reasons: [CareReason(.speciesBaseline)]
        )
    }

    public func inspection(for context: CareContext) -> CareRecommendation {
        let last = context.events.live(.inspect).last?.completedAt ?? context.plant.createdAt
        let start = last.addingTimeInterval(Double(context.species.care.inspectIntervalDays) * Self.day)
        let end = start.addingTimeInterval(7 * Self.day)
        return CareRecommendation(
            kind: .inspect,
            windowStart: start,
            windowEnd: end,
            state: state(now: context.now, start: start, end: end),
            basedOn: last,
            reasons: [CareReason(.speciesBaseline)]
        )
    }

    // MARK: - Helpers

    private func state(now: Date, start: Date, end: Date) -> CareTaskState {
        if now < start { return .scheduled }
        if now <= end { return .recommended }
        return .overdue
    }

    /// Ratio of the user's median watering interval to the expected one, blended at 30%
    /// and clamped, or nil while there are fewer than three intervals.
    func personalFactor(waterings: [CareEvent], expectedMid: Double) -> Double? {
        guard waterings.count > Self.personalMinIntervals, expectedMid > 0 else { return nil }
        let recent = Array(waterings.suffix(6))
        var intervals: [Double] = []
        for index in 1..<recent.count {
            intervals.append(recent[index].completedAt.timeIntervalSince(recent[index - 1].completedAt) / Self.day)
        }
        let sorted = intervals.sorted()
        let median = sorted.count % 2 == 1
            ? sorted[sorted.count / 2]
            : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        let ratio = min(2.0, max(0.5, median / expectedMid))
        let blended = 1 + (ratio - 1) * Self.personalWeight
        return (blended * 100).rounded() / 100
    }
}
