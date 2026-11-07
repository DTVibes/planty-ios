import XCTest
@testable import PlantyKit

final class ConditionTests: XCTestCase {
    private let calculator = ConditionCalculator()
    private let day: TimeInterval = 86_400
    private let base = Date(timeIntervalSince1970: 1_780_000_000)
    private let plantID = UUID()

    private func window(_ state: CareTaskState, startOffset: Double, endOffset: Double, basedOn: Date?) -> CareRecommendation {
        CareRecommendation(
            kind: .water,
            windowStart: base.addingTimeInterval(startOffset * day),
            windowEnd: base.addingTimeInterval(endOffset * day),
            state: state,
            basedOn: basedOn,
            reasons: []
        )
    }

    private func event(_ type: CareEventType, daysAgo: Double, problem: Bool = false) -> CareEvent {
        CareEvent(plantID: plantID, type: type, completedAt: base.addingTimeInterval(-daysAgo * day), problemNoted: problem)
    }

    func testThirstyInsideWindow() {
        let water = window(.recommended, startOffset: -1, endOffset: 4, basedOn: base.addingTimeInterval(-8 * day))
        XCTAssertEqual(calculator.condition(water: water, events: [event(.water, daysAgo: 8)], now: base).mood, .thirsty)
    }

    func testNeedsAttentionWhenBadlyOverdue() {
        let water = window(.overdue, startOffset: -10, endOffset: -5, basedOn: base.addingTimeInterval(-17 * day))
        let condition = calculator.condition(water: water, events: [event(.water, daysAgo: 17)], now: base)
        XCTAssertEqual(condition.mood, .needsAttention)
        XCTAssertEqual(condition.health, .check)
    }

    func testProblemNotedNeedsAttentionEvenWhenWatered() {
        let water = window(.scheduled, startOffset: 3, endOffset: 8, basedOn: base.addingTimeInterval(-4 * day))
        let events = [event(.water, daysAgo: 4), event(.inspect, daysAgo: 1, problem: true)]
        XCTAssertEqual(calculator.condition(water: water, events: events, now: base).mood, .needsAttention)
    }

    func testHappyAfterRecentCare() {
        let water = window(.scheduled, startOffset: 3, endOffset: 8, basedOn: base.addingTimeInterval(-4 * day))
        XCTAssertEqual(calculator.condition(water: water, events: [event(.water, daysAgo: 4)], now: base).mood, .happy)
    }

    func testThrivingNeedsSteadyRoutine() {
        let water = window(.scheduled, startOffset: 3, endOffset: 8, basedOn: base.addingTimeInterval(-2 * day))
        let events = [event(.water, daysAgo: 25), event(.water, daysAgo: 16), event(.inspect, daysAgo: 10), event(.water, daysAgo: 2)]
        XCTAssertEqual(calculator.condition(water: water, events: events, now: base).mood, .thriving)
    }

    func testNotesAloneDoNotMakeAPlantHappy() {
        let water = window(.scheduled, startOffset: 3, endOffset: 8, basedOn: nil)
        XCTAssertEqual(calculator.condition(water: water, events: [event(.note, daysAgo: 1)], now: base).mood, .neutral)
    }

    func testWaterLevelFallsAcrossTheWindow() {
        let lastWater = base
        let rec = CareRecommendation(kind: .water, windowStart: base.addingTimeInterval(6 * day), windowEnd: base.addingTimeInterval(8 * day), state: .scheduled, basedOn: lastWater, reasons: [])
        XCTAssertEqual(calculator.waterLevel(water: rec, now: base), 4)
        XCTAssertEqual(calculator.waterLevel(water: rec, now: base.addingTimeInterval(4 * day)), 2)
        XCTAssertEqual(calculator.waterLevel(water: rec, now: base.addingTimeInterval(20 * day)), 0)
    }
}

final class ProgressionTests: XCTestCase {
    func testWateringTooEarlyEarnsNothing() {
        // Same cases as supabase/tests/rls_test.sql (species minimum 7 days).
        XCTAssertEqual(XPRules.xp(for: .water, daysSincePreviousWatering: 2, speciesMinWateringDays: 7), 0)
        XCTAssertEqual(XPRules.xp(for: .water, daysSincePreviousWatering: 8, speciesMinWateringDays: 7), 10)
        XCTAssertEqual(XPRules.xp(for: .water, daysSincePreviousWatering: nil, speciesMinWateringDays: 7), 10)
        XCTAssertEqual(XPRules.xp(for: .fertilize, daysSincePreviousWatering: nil, speciesMinWateringDays: 7), 15)
    }

    func testPlantLevels() {
        XCTAssertEqual(PlantLevel.level(forXP: 0), 1)
        XCTAssertEqual(PlantLevel.level(forXP: 49), 1)
        XCTAssertEqual(PlantLevel.level(forXP: 50), 2)
        XCTAssertEqual(PlantLevel.level(forXP: 700), 5)
        XCTAssertEqual(PlantLevel.level(forXP: 5_000), 5)
        XCTAssertEqual(PlantLevel.nextThreshold(forXP: 60), 150)
        XCTAssertNil(PlantLevel.nextThreshold(forXP: 700))
    }

    func testGrowthStages() {
        XCTAssertEqual(PlantLevel.growthStage(level: 1, mood: .happy), .small)
        XCTAssertEqual(PlantLevel.growthStage(level: 3, mood: .happy), .growing)
        XCTAssertEqual(PlantLevel.growthStage(level: 5, mood: .happy), .mature)
        XCTAssertEqual(PlantLevel.growthStage(level: 5, mood: .thriving), .thriving)
    }

    func testGardenLevelBoundaries() {
        XCTAssertEqual(GardenLevel.level(forTotalXP: 0), 1)
        XCTAssertEqual(GardenLevel.level(forTotalXP: 99), 1)
        XCTAssertEqual(GardenLevel.level(forTotalXP: 100), 2)
        XCTAssertEqual(GardenLevel.threshold(for: 3), 283)
        XCTAssertEqual(GardenLevel.level(forTotalXP: 282), 2)
        XCTAssertEqual(GardenLevel.level(forTotalXP: 283), 3)
        XCTAssertEqual(GardenLevel.threshold(for: 5), 800)
        XCTAssertEqual(GardenLevel.level(forTotalXP: 800), 5)
    }
}
