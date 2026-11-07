import XCTest
@testable import PlantyKit

final class CareEngineTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private lazy var engine = CareEngine(calendar: calendar)
    private let day: TimeInterval = 86_400

    private let monstera = PlantSpecies(
        scientificName: "Monstera deliciosa",
        commonNames: ["en": "Swiss cheese plant", "ru": "Монстера деликатесная"],
        care: CareRequirements(wateringDays: 7...12, fertilizeIntervalDays: 30, inspectIntervalDays: 30)
    )

    private func date(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: string + "T12:00:00Z")!
    }

    private func plant(potSize: PotSize? = .medium, light: LightLevel? = .medium, location: PlantLocation? = .livingRoom) -> UserPlant {
        UserPlant(speciesID: monstera.id, customName: "Monty", location: location, light: light, potSize: potSize, createdAt: date("2026-01-01"))
    }

    private func water(_ plant: UserPlant, _ day: String) -> CareEvent {
        CareEvent(plantID: plant.id, type: .water, completedAt: date(day))
    }

    func testSpringWindowUsesSpeciesRange() {
        let plant = plant()
        let context = CareContext(plant: plant, species: monstera, events: [water(plant, "2026-04-01")], now: date("2026-04-05"))
        let rec = engine.watering(for: context)
        XCTAssertEqual(rec.windowStart, date("2026-04-08"))
        XCTAssertEqual(rec.windowEnd, date("2026-04-13"))
        XCTAssertEqual(rec.state, .scheduled)
        XCTAssertEqual(rec.reasons.map(\.code), [.speciesBaseline])
    }

    func testWinterStretchesWindowAndExplainsWhy() {
        let plant = plant()
        let context = CareContext(plant: plant, species: monstera, events: [water(plant, "2026-01-10")], now: date("2026-01-15"))
        let rec = engine.watering(for: context)
        XCTAssertEqual(rec.windowStart.timeIntervalSince(date("2026-01-10")) / day, 7 * 1.4, accuracy: 0.001)
        XCTAssertTrue(rec.reasons.contains(CareReason(.season, factor: 1.4)))
    }

    func testSouthernHemisphereFlipsSeason() {
        XCTAssertEqual(Season.of(date("2026-01-15"), hemisphere: .south, calendar: calendar), .summer)
        XCTAssertEqual(Season.of(date("2026-07-15"), hemisphere: .north, calendar: calendar), .summer)
    }

    func testSmallPotAndBrightLightShortenWindow() {
        let plant = plant(potSize: .small, light: .brightIndirect)
        let context = CareContext(plant: plant, species: monstera, events: [water(plant, "2026-04-01")], now: date("2026-04-02"))
        let rec = engine.watering(for: context)
        XCTAssertEqual(rec.windowStart.timeIntervalSince(date("2026-04-01")) / day, 7 * 0.8 * 0.9, accuracy: 0.001)
    }

    func testStatesAcrossTheWindow() {
        let plant = plant()
        let events = [water(plant, "2026-04-01")]
        XCTAssertEqual(engine.watering(for: CareContext(plant: plant, species: monstera, events: events, now: date("2026-04-07"))).state, .scheduled)
        XCTAssertEqual(engine.watering(for: CareContext(plant: plant, species: monstera, events: events, now: date("2026-04-10"))).state, .recommended)
        XCTAssertEqual(engine.watering(for: CareContext(plant: plant, species: monstera, events: events, now: date("2026-04-20"))).state, .overdue)
    }

    func testNoHistoryRecommendsACheckNow() {
        let plant = plant()
        let rec = engine.watering(for: CareContext(plant: plant, species: monstera, events: [], now: date("2026-04-01")))
        XCTAssertEqual(rec.state, .recommended)
        XCTAssertNil(rec.basedOn)
        XCTAssertTrue(rec.reasons.contains(CareReason(.noHistory)))
    }

    func testNotNeededYetPushesWindow() {
        let plant = plant()
        let events = [
            water(plant, "2026-04-01"),
            CareEvent(plantID: plant.id, type: .skipWater, completedAt: date("2026-04-09"))
        ]
        let rec = engine.watering(for: CareContext(plant: plant, species: monstera, events: events, now: date("2026-04-10")))
        XCTAssertEqual(rec.windowStart, date("2026-04-11"))
        XCTAssertEqual(rec.state, .scheduled)
        XCTAssertTrue(rec.reasons.contains(CareReason(.checkedNotNeeded)))
    }

    func testDeletedEventsAreIgnored() {
        let plant = plant()
        var wrong = water(plant, "2026-04-09")
        wrong.isDeleted = true
        let rec = engine.watering(for: CareContext(plant: plant, species: monstera, events: [water(plant, "2026-04-01"), wrong], now: date("2026-04-10")))
        XCTAssertEqual(rec.basedOn, date("2026-04-01"))
    }

    func testPersonalHistoryNeedsThreeIntervals() {
        let plant = plant()
        let three = ["2026-04-01", "2026-04-15", "2026-04-29"].map { water(plant, $0) }
        XCTAssertNil(engine.watering(for: CareContext(plant: plant, species: monstera, events: three, now: date("2026-04-30"))).reasons.first { $0.code == .personalHistory })

        let four = three + [water(plant, "2026-05-13")]
        let rec = engine.watering(for: CareContext(plant: plant, species: monstera, events: four, now: date("2026-05-14")))
        // Median 14 days vs expected 9.5: ratio 1.47, blended at 30% → 1.14.
        XCTAssertEqual(rec.reasons.first { $0.code == .personalHistory }?.factor, 1.14)
    }

    func testPersonalFactorIsClamped() {
        let plant = plant()
        let events = ["2026-01-01", "2026-03-01", "2026-05-01", "2026-07-01"].map { water(plant, $0) }
        let factor = engine.personalFactor(waterings: events, expectedMid: 9.5)
        XCTAssertEqual(factor, 1.3)
    }

    func testNoFertilizingInWinterUnlessSpeciesWantsIt() {
        let plant = plant()
        XCTAssertNil(engine.fertilizing(for: CareContext(plant: plant, species: monstera, events: [], now: date("2026-01-20"))))
        XCTAssertNotNil(engine.fertilizing(for: CareContext(plant: plant, species: monstera, events: [], now: date("2026-05-20"))))
    }

    func testEventsOfOtherPlantsAreIgnored() {
        let plant = plant()
        let other = CareEvent(plantID: UUID(), type: .water, completedAt: date("2026-04-09"))
        let rec = engine.watering(for: CareContext(plant: plant, species: monstera, events: [water(plant, "2026-04-01"), other], now: date("2026-04-10")))
        XCTAssertEqual(rec.basedOn, date("2026-04-01"))
    }
}
