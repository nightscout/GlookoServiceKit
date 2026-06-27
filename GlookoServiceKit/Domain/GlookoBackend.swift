import Foundation
import LoopKit

public protocol GlookoBackend: AnyObject {
    var variant: GlookoVariant { get }
    var isConfigured: Bool { get }

    func prepare() async throws

    func uploadGlucose(_ samples: [StoredGlucoseSample]) async throws
    func uploadDoses(created: [DoseEntry], deleted: [DoseEntry]) async throws
    func uploadCarbs(created: [SyncCarbObject], updated: [SyncCarbObject], deleted: [SyncCarbObject]) async throws
    func uploadPumpEvents(_ events: [PersistedPumpEvent]) async throws

    func uploadPumpSnapshot(basal: [DoseEntry], boluses: [DoseEntry], carbs: [SyncCarbObject], now: Date) async throws

    func tearDown()
}

public extension GlookoBackend {
    func tearDown() {}
    func uploadPumpSnapshot(basal: [DoseEntry], boluses: [DoseEntry], carbs: [SyncCarbObject], now: Date) async throws {}
}
