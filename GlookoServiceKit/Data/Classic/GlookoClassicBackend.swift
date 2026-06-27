import Foundation
import LoopKit
import HealthKit

public final class GlookoClassicBackend: GlookoBackend {
    public let variant: GlookoVariant = .classic

    private let api: GlookoClassicAPI

    public init(configuration: GlookoService.Configuration, sessionCookie: String?,
                credentials: (email: String, password: String)? = nil,
                api: GlookoClassicAPI? = nil) {
        self.api = api ?? GlookoClassicAPI(region: configuration.classicRegion,
                                           sessionCookie: sessionCookie,
                                           credentials: credentials,
                                           deviceId: configuration.id)
    }

    public var isConfigured: Bool { api.hasSession }
    public func prepare() async throws { try await api.ensureSession() }
    public func tearDown() { api.invalidate() }

    private static func now() -> String { GlookoClassicAPI.iso(Date()) }

    public func uploadGlucose(_ samples: [StoredGlucoseSample]) async throws {
        let cgm = samples.filter { !$0.wasUserEntered }
        let manual = samples.filter { $0.wasUserEntered }
        let readings = manual.map {
            GKReading(guid: UUID().uuidString, syncTimestamp: Self.now(),
                      timestamp: GlookoClassicAPI.iso($0.startDate),
                      value: Int(($0.quantity.doubleValue(for: .gkMilligramsPerDeciliter) * 100).rounded()),
                      userMealTag: 0)
        }
        try await runIndependently([
            { guard !cgm.isEmpty else { return }
              try await self.api.uploadDeviceFile(Data(GlookoLibreViewCSV.generate(from: cgm).utf8)) },
            { try await self.api.put(endpoint: "readings", jsonName: "readings", items: readings) },
        ])
    }

    public func uploadCarbs(created: [SyncCarbObject], updated: [SyncCarbObject],
                            deleted: [SyncCarbObject]) async throws {
        try await sendCarbs(created + updated)
    }

    public func uploadDoses(created: [DoseEntry], deleted: [DoseEntry]) async throws {
        try await sendBoluses(created.filter { $0.type == .bolus })
    }

    public func uploadPumpSnapshot(basal: [DoseEntry], boluses: [DoseEntry], carbs: [SyncCarbObject],
                                   now: Date) async throws {
        try await runIndependently([
            { try await self.sendBasalIBF(basal) },
            { try await self.sendBoluses(boluses) },
            { try await self.sendCarbs(carbs) },
        ])
    }

    public func uploadPumpEvents(_ events: [PersistedPumpEvent]) async throws {
        _ = events
    }

    private func runIndependently(_ operations: [() async throws -> Void]) async throws {
        var firstError: Error?
        for operation in operations {
            do {
                try await operation()
            } catch {
                GlookoLog.classic.error("Classic upload step failed: \(error.localizedDescription)")
                firstError = firstError ?? error
            }
        }
        if let firstError { throw firstError }
    }

    private func sendBoluses(_ boluses: [DoseEntry]) async throws {
        guard !boluses.isEmpty else { return }
        let items = boluses.map {
            GKInsulin(guid: UUID().uuidString, syncTimestamp: Self.now(),
                      timestamp: GlookoClassicAPI.iso($0.startDate),
                      value: $0.deliveredUnits ?? $0.programmedUnits)
        }
        try await api.put(endpoint: "insulins", jsonName: "insulins", items: items)
    }

    private func sendCarbs(_ carbs: [SyncCarbObject]) async throws {
        guard !carbs.isEmpty else { return }
        var meals: [GKMeal] = []
        var foods: [GKFood] = []
        for carb in carbs {
            let mealGuid = UUID().uuidString
            let timestamp = GlookoClassicAPI.iso(carb.startDate)
            let name = carb.foodType ?? "Trio"
            meals.append(GKMeal(guid: mealGuid, timestamp: timestamp, name: name, type: "snack"))
            foods.append(GKFood(guid: UUID().uuidString, syncTimestamp: Self.now(), timestamp: timestamp,
                                mealGuid: mealGuid, name: name,
                                carbs: carb.quantity.doubleValue(for: .gram())))
        }
        try await api.put(endpoint: "meals", jsonName: "meals", items: meals)
        try await api.put(endpoint: "foods", jsonName: "foods", items: foods)
    }

    private func sendBasalIBF(_ basal: [DoseEntry]) async throws {
        let entries = GlookoIBFGenerator.entries(basal: basal, boluses: [], carbs: [])
        guard !entries.isEmpty else { return }
        try await api.uploadToAnalyzer(GlookoIBFGenerator().generate(entries),
                                       extractor: GlookoConstants.Classic.analyzerExtractor)
    }
}
