import Foundation

public enum CareEventType: String, Codable, CaseIterable, Sendable {
    case water, fertilize, repot, prune, inspect, note
    /// The user checked the soil and decided the plant does not need water yet.
    case skipWater = "skip_water"
}

/// One care action the user logged. Events are append-only; a correction
/// marks the old event deleted instead of removing it, so sync never conflicts.
public struct CareEvent: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var plantID: UUID
    public var type: CareEventType
    public var completedAt: Date
    public var notes: String?
    /// Set on an inspection when the user saw a possible problem (pests, yellow leaves).
    public var problemNoted: Bool
    public var isDeleted: Bool

    public init(
        id: UUID = UUID(),
        plantID: UUID,
        type: CareEventType,
        completedAt: Date,
        notes: String? = nil,
        problemNoted: Bool = false,
        isDeleted: Bool = false
    ) {
        self.id = id
        self.plantID = plantID
        self.type = type
        self.completedAt = completedAt
        self.notes = notes
        self.problemNoted = problemNoted
        self.isDeleted = isDeleted
    }
}

extension Array where Element == CareEvent {
    /// Live events of one type, oldest first.
    func live(_ type: CareEventType) -> [CareEvent] {
        filter { !$0.isDeleted && $0.type == type }.sorted { $0.completedAt < $1.completedAt }
    }
}
