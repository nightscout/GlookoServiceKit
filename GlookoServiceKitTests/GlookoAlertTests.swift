import XCTest
import LoopKit
@testable import GlookoServiceKit

private final class AlertRecorder: ServiceDelegate {
    var issued: [Alert] = []
    var retracted: [Alert.Identifier] = []
    var hostIdentifier: String { "test" }
    var hostVersion: String { "1" }
    func issueAlert(_ alert: Alert) { issued.append(alert) }
    func retractAlert(identifier: Alert.Identifier) { retracted.append(identifier) }
    func enactRemoteOverride(name: String, durationTime: TimeInterval?, remoteAddress: String) async throws {}
    func cancelRemoteOverride() async throws {}
    func deliverRemoteCarbs(amountInGrams: Double, absorptionTime: TimeInterval?, foodType: String?, startDate: Date?) async throws {}
    func deliverRemoteBolus(amountInUnits: Double) async throws {}
}

private final class FailingBackend: GlookoBackend {
    let variant: GlookoVariant = .classic
    var isConfigured = true
    var error: Error?
    func prepare() async throws {}
    func uploadGlucose(_ samples: [StoredGlucoseSample]) async throws { if let error { throw error } }
    func uploadDoses(created: [DoseEntry], deleted: [DoseEntry]) async throws {}
    func uploadCarbs(created: [SyncCarbObject], updated: [SyncCarbObject], deleted: [SyncCarbObject]) async throws {}
    func uploadPumpEvents(_ events: [PersistedPumpEvent]) async throws {}
}

final class GlookoAlertTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeService() -> (GlookoService, AlertRecorder, FailingBackend) {
        let service = GlookoService(hostIdentifier: "test", hostVersion: "1")
        service.credentialStore = InMemoryCredentialStore()
        let recorder = AlertRecorder()
        service.serviceDelegate = recorder
        let backend = FailingBackend()
        service.backendOverride = backend
        service.reload()
        return (service, recorder, backend)
    }

    private func upload(_ service: GlookoService) async -> Result<Bool, Error> {
        await withCheckedContinuation { continuation in
            service.uploadGlucoseData([]) { continuation.resume(returning: $0) }
        }
    }

    // MARK: - Which alerts

    func testSignInErrorsRaiseAuthenticationAlert() {
        let stats = GlookoService.UploadStats()
        for error: GlookoAPIError in [.authenticationRequired, .noToken, .twoFactorRequired,
                                      .upload(endpoint: "x", status: 401, message: nil),
                                      .upload(endpoint: "x", status: 403, message: nil)] {
            XCTAssertEqual(GlookoService.alertsToIssue(for: error, stats: stats, now: now), [.authenticationNeeded], "\(error)")
        }
    }

    func testTransientErrorsRaiseNothingAtFirst() {
        var stats = GlookoService.UploadStats()
        stats.lastUploadDate = now.addingTimeInterval(-60)
        for error: Error in [GlookoAPIError.upload(endpoint: "x", status: 500, message: nil), GlookoAPIError.notConnected,
                             URLError(.notConnectedToInternet)] {
            XCTAssertEqual(GlookoService.alertsToIssue(for: error, stats: stats, now: now), [], "\(error)")
        }
    }

    func testStalledAfterAnHourWithoutSuccess() {
        var stats = GlookoService.UploadStats()
        stats.lastUploadDate = now.addingTimeInterval(-GlookoService.stalledAlertDelay)
        XCTAssertEqual(GlookoService.alertsToIssue(for: URLError(.timedOut), stats: stats, now: now), [.uploadsStalled])
    }

    func testStalledCountsFromFirstFailureWhenNeverUploaded() {
        var stats = GlookoService.UploadStats()
        stats.failingSince = now.addingTimeInterval(-GlookoService.stalledAlertDelay + 60)
        XCTAssertEqual(GlookoService.alertsToIssue(for: URLError(.timedOut), stats: stats, now: now), [])
        stats.failingSince = now.addingTimeInterval(-GlookoService.stalledAlertDelay - 60)
        XCTAssertEqual(GlookoService.alertsToIssue(for: URLError(.timedOut), stats: stats, now: now), [.uploadsStalled])
    }

    // MARK: - Issue and retract

    func testFailedUploadIssuesAuthenticationAlertOnce() async {
        let (service, recorder, backend) = makeService()
        backend.error = GlookoAPIError.authenticationRequired

        _ = await upload(service)
        _ = await upload(service)

        XCTAssertEqual(recorder.issued.map(\.identifier.alertIdentifier), ["authentication-needed"])
        XCTAssertEqual(recorder.issued.first?.identifier.managerIdentifier, GlookoService.pluginIdentifier)
        XCTAssertEqual(recorder.issued.first?.trigger, .immediate)
    }

    func testSuccessRetractsActiveAlerts() async {
        let (service, recorder, backend) = makeService()
        backend.error = GlookoAPIError.authenticationRequired
        _ = await upload(service)

        backend.error = nil
        _ = await upload(service)
        _ = await upload(service)

        XCTAssertEqual(recorder.retracted.map(\.alertIdentifier), ["authentication-needed"])
        XCTAssertNil(service.stats.failingSince)
    }

    func testActiveAlertsSurviveRestore() async throws {
        let (service, _, backend) = makeService()
        backend.error = GlookoAPIError.authenticationRequired
        _ = await upload(service)

        let restored = try XCTUnwrap(GlookoService(rawState: service.rawState))
        XCTAssertEqual(restored.activeAlerts, [.authenticationNeeded])
        XCTAssertNotNil(restored.stats.failingSince)
    }

    func testSignOutRetractsAlerts() async {
        let (service, recorder, backend) = makeService()
        backend.error = GlookoAPIError.authenticationRequired
        _ = await upload(service)

        service.signOut()
        await MainActor.run {}
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(recorder.retracted.map(\.alertIdentifier), ["authentication-needed"])
    }
}
