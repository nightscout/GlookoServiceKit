import Foundation
import LoopKit
import HealthKit

public final class GlookoService: Service, ObservableObject {

    public static let pluginIdentifier = "GlookoService"
    public static let localizedTitle = LocalizedString("Glooko", comment: "Title of the Glooko service")

    public weak var serviceDelegate: ServiceDelegate?
    public weak var stateDelegate: StatefulPluggableDelegate?

    public struct Configuration: Codable {

        public var id: String = UUID().uuidString
        public var variant: GlookoVariant = .xt
        public var glucoseUnit: GlucoseUnitPreference = .mgdl
        public var email: String?

        public var classicRegion: GlookoClassicRegion = .eu

    }

    public struct UploadStats: Codable {
        public var lastUploadDate: Date?
        public var glucose = 0
        public var doses = 0
        public var carbs = 0
        public var pumpEvents = 0
    }

    @Published public var configuration: Configuration
    @Published public var stats = UploadStats()
    @Published public var lastError: String?
    public var isOnboarded: Bool

    public var credentialStore: GlookoCredentialStore = KeychainCredentialStore()

    var pendingClassicAPI: GlookoClassicAPI?
    var pendingClassicCredentials: (email: String, password: String)?

    var credentials: GlookoCredentials { GlookoCredentials(store: credentialStore, id: configuration.id) }

    public var token: String? {
        get { credentials.token }
        set { credentials.token = newValue }
    }

    private lazy var backend: GlookoBackend = makeBackend()
    private lazy var coordinator = GlookoUploadCoordinator(backend: { [unowned self] in self.backend })

    public init(hostIdentifier: String, hostVersion: String) {
        self.configuration = Configuration()
        self.isOnboarded = false
    }

    public init?(rawState: RawStateValue) {
        guard let data = rawState["configuration"] as? Data,
              let config = try? JSONDecoder().decode(Configuration.self, from: data) else {
            return nil
        }
        self.configuration = config
        self.isOnboarded = (rawState["isOnboarded"] as? Bool) ?? true
        if let statsData = rawState["stats"] as? Data,
           let saved = try? JSONDecoder().decode(UploadStats.self, from: statsData) {
            self.stats = saved
        }
    }

    public var rawState: RawStateValue {
        var raw: RawStateValue = ["isOnboarded": isOnboarded]
        if let data = try? JSONEncoder().encode(configuration) { raw["configuration"] = data }
        if let data = try? JSONEncoder().encode(stats) { raw["stats"] = data }
        return raw
    }

    public func completeCreate() { persist() }
    public func completeUpdate() { persist(); stateDelegate?.pluginDidUpdateState(self) }
    public func completeOnboard() { isOnboarded = true; persist(); stateDelegate?.pluginDidUpdateState(self) }
    public func completeDelete() { backend.tearDown(); stateDelegate?.pluginWantsDeletion(self) }

    private func persist() { stateDelegate?.pluginDidUpdateState(self) }

    public func reload() { backend.tearDown(); backend = makeBackend() }

    private func makeBackend() -> GlookoBackend {
        switch configuration.variant {
        case .xt:
            return GlookoXTBackend(configuration: configuration, token: token)
        case .classic:

            let creds = classicCredentials()
            return GlookoClassicBackend(configuration: configuration,
                                        sessionCookie: token, credentials: creds)
        }
    }

    private func classicCredentials() -> (email: String, password: String)? {
        guard let email = configuration.email, let password = credentials.classicPassword else { return nil }
        return (email, password)
    }

    public func completeDeleteRemovingToken() {
        token = nil
        completeDelete()
    }
}

extension GlookoService: RemoteDataService {

    public var glucoseDataLimit: Int? { 1000 }
    public var doseDataLimit: Int? { 1000 }
    public var carbDataLimit: Int? { 1000 }
    public var pumpEventDataLimit: Int? { 1000 }

    public var dosingDecisionDataLimit: Int? { 0 }
    public var settingsDataLimit: Int? { 0 }

    public func uploadGlucoseData(_ stored: [StoredGlucoseSample],
                                  completion: @escaping (Result<Bool, Error>) -> Void) {
        run(completion, record: { $0.glucose += stored.count }) { try await $0.uploadGlucose(stored) }
    }

    public func uploadDoseData(created: [DoseEntry], deleted: [DoseEntry],
                               completion: @escaping (Result<Bool, Error>) -> Void) {
        run(completion, record: { $0.doses += created.count }) { try await $0.uploadDoses(created: created, deleted: deleted) }
    }

    public func uploadCarbData(created: [SyncCarbObject], updated: [SyncCarbObject],
                               deleted: [SyncCarbObject],
                               completion: @escaping (Result<Bool, Error>) -> Void) {
        run(completion, record: { $0.carbs += created.count + updated.count }) {
            try await $0.uploadCarbs(created: created, updated: updated, deleted: deleted)
        }
    }

    public func uploadPumpEventData(_ stored: [PersistedPumpEvent],
                                    completion: @escaping (Result<Bool, Error>) -> Void) {
        run(completion, record: { $0.pumpEvents += stored.count }) { try await $0.uploadPumpEvents(stored) }
    }

    public var alertDataLimit: Int? { 0 }
    public func uploadAlertData(_ stored: [SyncAlertObject],
                                completion: @escaping (Result<Bool, Error>) -> Void) { completion(.success(true)) }

    public func uploadTemporaryOverrideData(updated: [TemporaryScheduleOverride], deleted: [TemporaryScheduleOverride],
                                            completion: @escaping (Result<Bool, Error>) -> Void) { completion(.success(true)) }

    public func uploadDosingDecisionData(_ stored: [StoredDosingDecision],
                                         completion: @escaping (Result<Bool, Error>) -> Void) { completion(.success(true)) }

    public func uploadSettingsData(_ stored: [StoredSettings],
                                   completion: @escaping (Result<Bool, Error>) -> Void) { completion(.success(true)) }

    public func uploadCgmEventData(_ stored: [PersistedCgmEvent],
                                   completion: @escaping (Result<Bool, Error>) -> Void) { completion(.success(true)) }

    public func remoteNotificationWasReceived(_ notification: [String: AnyObject]) async throws { }

    public func uploadPumpSnapshot(basal: [DoseEntry], boluses: [DoseEntry], carbs: [SyncCarbObject],
                                   now: Date = Date(),
                                   completion: @escaping (Result<Bool, Error>) -> Void) {
        run(completion, record: { stats in
            stats.doses = basal.count + boluses.count
            stats.carbs = carbs.count
            stats.pumpEvents = basal.count + boluses.count + carbs.count
        }) {
            try await $0.uploadPumpSnapshot(basal: basal, boluses: boluses, carbs: carbs, now: now)
        }
    }

    private func run(_ completion: @escaping (Result<Bool, Error>) -> Void,
                     record: @escaping (inout UploadStats) -> Void = { _ in },
                     _ work: @escaping (GlookoBackend) async throws -> Void) {
        Task {
            do {
                try await coordinator.perform(work)
                await MainActor.run {
                    record(&stats)
                    stats.lastUploadDate = Date()
                    lastError = nil
                    persist()
                }
                completion(.success(true))
            } catch {
                GlookoLog.upload.error("upload failed: \(error.localizedDescription)")
                await MainActor.run { self.lastError = error.localizedDescription }
                completion(.failure(error))
            }
        }
    }
}
