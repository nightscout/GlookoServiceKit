import Foundation
import LoopKit
import HealthKit

public final class GlookoClassicBackend: GlookoBackend {
    public let variant: GlookoVariant = .classic

    private let api: GlookoClassicAPI
    private let identity: GlookoClientIdentity
    private let clock: () -> Date

    public init(configuration: GlookoService.Configuration, sessionCookie: String?,
                credentials: (email: String, password: String)? = nil,
                identity: GlookoClientIdentity = GlookoClientIdentity(),
                api: GlookoClassicAPI? = nil,
                clock: @escaping () -> Date = Date.init) {
        self.identity = identity
        self.clock = clock
        self.api = api ?? GlookoClassicAPI(region: configuration.classicRegion,
                                           sessionCookie: sessionCookie,
                                           credentials: credentials,
                                           identity: identity)
    }

    public var isConfigured: Bool { api.hasSession }
    public var sessionCookie: String? { api.sessionCookie }
    public func prepare() async throws { try await api.ensureSession() }
    public func tearDown() { api.invalidate() }

    private func syncTimestamp() -> String { GlookoClassicAPI.utc(clock()) }

    public func uploadGlucose(_ samples: [StoredGlucoseSample]) async throws {
        let cgm = samples.filter { !$0.wasUserEntered }
        let stamp = syncTimestamp()
        let readings = samples.filter(\.wasUserEntered).map {
            GKReading(guid: GlookoGUID.reading(Self.seed($0.syncIdentifier, $0.startDate)), syncTimestamp: stamp,
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
        let stamp = syncTimestamp()
        let foods = (created + updated).map { food($0, deleted: false, stamp) } + deleted.map { food($0, deleted: true, stamp) }
        guard !foods.isEmpty else { return }
        try await api.put(endpoint: "foods", jsonName: "foods", items: foods)
        await completeSync()
    }

    public func uploadDoses(created: [DoseEntry], deleted: [DoseEntry]) async throws {
        let stamp = syncTimestamp()
        let items = Self.boluses(created).map { bolus($0, deleted: false, stamp) }
            + deleted.filter { $0.type == .bolus }.map { bolus($0, deleted: true, stamp) }
        guard !items.isEmpty else { return }
        try await api.put(endpoint: "insulins", jsonName: "insulins", items: items)
        await completeSync()
    }

    public func uploadPumpSnapshot(basal: [DoseEntry], boluses: [DoseEntry], carbs: [SyncCarbObject],
                                   now: Date) async throws {
        let stamp = syncTimestamp()
        let hours = GlookoHourlyBasal.hours(from: basal, now: now)
        // A settled hour that delivered nothing is soft-deleted, so a recomputed hour never keeps a stale total.
        let insulins = hours.map {
            GKInsulin(guid: GlookoGUID.basalHour($0.start), timestamp: GlookoClassicAPI.iso($0.start), value: $0.units,
                      insulinType: .basal, softDeleted: $0.units <= 0, source: identity.sourceName, syncTimestamp: stamp)
        } + Self.boluses(boluses).map { bolus($0, deleted: false, stamp) }
        let foods = carbs.map { food($0, deleted: false, stamp) }
        guard !insulins.isEmpty || !foods.isEmpty else { return }
        try await runIndependently([
            { try await self.api.put(endpoint: "insulins", jsonName: "insulins", items: insulins) },
            { try await self.api.put(endpoint: "foods", jsonName: "foods", items: foods) },
        ])
        await completeSync()
    }

    public func uploadPumpEvents(_ events: [PersistedPumpEvent]) async throws {
        _ = events
    }

    static func boluses(_ doses: [DoseEntry]) -> [DoseEntry] {
        doses.filter { $0.type == .bolus && !$0.isMutable }
    }

    static func seed(_ syncIdentifier: String?, _ date: Date) -> String {
        syncIdentifier ?? "\(Int(date.timeIntervalSince1970))"
    }

    private func bolus(_ dose: DoseEntry, deleted: Bool, _ stamp: String) -> GKInsulin {
        GKInsulin(guid: GlookoGUID.bolus(Self.seed(dose.syncIdentifier, dose.startDate)),
                  timestamp: GlookoClassicAPI.iso(dose.startDate),
                  value: dose.deliveredUnits ?? dose.programmedUnits, insulinType: .bolus,
                  softDeleted: deleted, source: identity.sourceName, syncTimestamp: stamp)
    }

    private func food(_ carb: SyncCarbObject, deleted: Bool, _ stamp: String) -> GKFood {
        let id = carb.syncIdentifier ?? carb.uuid?.uuidString ?? Self.seed(nil, carb.startDate)
        return GKFood(guid: GlookoGUID.food(id), timestamp: GlookoClassicAPI.iso(carb.startDate),
                      carbs: carb.quantity.doubleValue(for: .gram()), softDeleted: deleted, syncTimestamp: stamp)
    }

    private func completeSync() async {
        do {
            try await api.syncComplete()
        } catch {
            GlookoLog.classic.info("Sync-complete notice failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func runIndependently(_ operations: [() async throws -> Void]) async throws {
        var firstError: Error?
        for operation in operations {
            do {
                try await operation()
            } catch {
                GlookoLog.classic.error("Classic upload step failed: \(error.localizedDescription, privacy: .public)")
                firstError = firstError ?? error
            }
        }
        if let firstError { throw firstError }
    }
}
