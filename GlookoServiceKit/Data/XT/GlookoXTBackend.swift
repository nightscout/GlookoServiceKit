import Foundation
import LoopKit
import HealthKit

public final class GlookoXTBackend: GlookoBackend {
    public let variant: GlookoVariant = .xt

    private let config: GlookoService.Configuration
    private let token: String?
    private let api: GlookoXTClient

    public init(configuration: GlookoService.Configuration, token: String?) {
        self.config = configuration
        self.token = token
        self.api = GlookoXTClient(token: token)
    }

    public var isConfigured: Bool { token != nil }

    public func prepare() async throws {
        guard !api.isConnected else { return }
        try await api.connect()
    }

    public func tearDown() { api.disconnect() }

    public func uploadGlucose(_ samples: [StoredGlucoseSample]) async throws {
        try await send(samples.map { sample in
            let mgdl = sample.quantity.doubleValue(for: .gkMilligramsPerDeciliter)
            if sample.wasUserEntered {
                return GlookoRecordBuilder.manualGlucose(sample.startDate, mgdl: mgdl, unit: config.glucoseUnit)
            }
            return GlookoRecordBuilder.cgm(sample.startDate, mgdl: mgdl, unit: config.glucoseUnit)
        })
    }

    public func uploadDoses(created: [DoseEntry], deleted: [DoseEntry]) async throws {
        let records = created.compactMap { Self.map($0) }
        try await send(records)
    }

    public func uploadCarbs(created: [SyncCarbObject], updated: [SyncCarbObject],
                            deleted: [SyncCarbObject]) async throws {
        let records = (created + updated).map {
            GlookoRecordBuilder.carbs($0.startDate,
                                      grams: $0.quantity.doubleValue(for: .gram()),
                                      mealTag: nil)
        }
        try await send(records)
    }

    public func uploadPumpSnapshot(basal: [DoseEntry], boluses: [DoseEntry], carbs: [SyncCarbObject],
                                   now: Date) async throws {
        let entries = GlookoIBFGenerator.entries(basal: basal, boluses: boluses, carbs: carbs)
        guard !entries.isEmpty else { return }
        GlookoLog.upload.info("snapshot: \(entries.count) entries (\(basal.count) basal, \(boluses.count) bolus)")
        try await api.uploadIBF(GlookoIBFGenerator().generate(entries), reference: now)
    }

    public func uploadPumpEvents(_ events: [PersistedPumpEvent]) async throws {
        let records: [GlookoRecord] = events.compactMap { event in
            switch event.type {
            case .suspend: return GlookoRecordBuilder.suspend(event.date, note: "Suspend")
            case .prime:   return GlookoRecordBuilder.prime(event.date)
            default:       return nil
            }
        }
        try await send(records)
    }

    static func map(_ dose: DoseEntry) -> GlookoRecord? {
        let units = dose.deliveredUnits ?? dose.programmedUnits
        let durationMin = max(0, Int(dose.endDate.timeIntervalSince(dose.startDate) / 60))
        switch dose.type {
        case .bolus:

            return dose.automatic == true
                ? GlookoRecordBuilder.smb(dose.startDate, units: units)
                : GlookoRecordBuilder.bolus(dose.startDate, units: units, correction: false)
        case .tempBasal:
            return GlookoRecordBuilder.scheduledBasal(dose.startDate, rateUPerHour: dose.unitsPerHour,
                                                      durationMin: durationMin)
        case .basal:
            return GlookoRecordBuilder.scheduledBasal(dose.startDate, rateUPerHour: dose.unitsPerHour,
                                                      durationMin: durationMin)
        case .suspend:
            return GlookoRecordBuilder.suspend(dose.startDate, note: "Suspend")
        case .resume:
            return nil
        @unknown default:
            return nil
        }
    }

    private func send(_ records: [GlookoRecord]) async throws {
        guard !records.isEmpty else { return }
        for start in stride(from: 0, to: records.count, by: 100) {
            let chunk = Array(records[start ..< min(start + 100, records.count)])
            _ = try await api.addRecords(chunk)
        }
    }
}
