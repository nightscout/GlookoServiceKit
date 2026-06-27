import XCTest
import LoopKit
@testable import GlookoServiceKit

private final class MockStateDelegate: StatefulPluggableDelegate {
    var updated = 0
    var deletions = 0
    func pluginDidUpdateState(_ plugin: StatefulPluggable) { updated += 1 }
    func pluginWantsDeletion(_ plugin: StatefulPluggable) { deletions += 1 }
}

final class GlookoServiceTests: XCTestCase {

    private func makeService() -> (GlookoService, MockStateDelegate) {
        let service = GlookoService(hostIdentifier: "test", hostVersion: "1")
        service.credentialStore = InMemoryCredentialStore()
        let delegate = MockStateDelegate()
        service.stateDelegate = delegate
        return (service, delegate)
    }

    func testTokenPersistsViaStore() {
        let (service, _) = makeService()
        XCTAssertNil(service.token)
        service.token = "jwt"
        XCTAssertEqual(service.token, "jwt")
    }

    func testRawStateRoundTrip() throws {
        let (service, _) = makeService()
        service.configuration.variant = .classic
        service.configuration.email = "a@b.com"
        service.configuration.classicRegion = .us
        let restored = try XCTUnwrap(GlookoService(rawState: service.rawState))
        XCTAssertEqual(restored.configuration.variant, .classic)
        XCTAssertEqual(restored.configuration.email, "a@b.com")
        XCTAssertEqual(restored.configuration.classicRegion, .us)
    }

    func testInitRejectsBadRawState() {
        XCTAssertNil(GlookoService(rawState: ["configuration": Data("nonsense".utf8)]))
    }

    func testIsAuthenticatedXT() {
        let (service, _) = makeService()
        service.configuration.variant = .xt
        XCTAssertFalse(service.isAuthenticated)
        service.token = "jwt"
        XCTAssertTrue(service.isAuthenticated)
    }

    func testIsAuthenticatedClassicNeedsEmailAndPassword() throws {
        let (service, _) = makeService()
        service.configuration.variant = .classic
        XCTAssertFalse(service.isAuthenticated)
        service.configuration.email = "a@b.com"
        XCTAssertFalse(service.isAuthenticated)
        try service.credentialStore.set("pw", for: service.classicPasswordKey)
        XCTAssertTrue(service.isAuthenticated)
    }

    func testSignOutClears() throws {
        let (service, _) = makeService()
        service.configuration.variant = .classic
        service.configuration.email = "a@b.com"
        try service.credentialStore.set("pw", for: service.classicPasswordKey)
        service.token = "cookie"
        service.signOut()
        XCTAssertNil(service.token)
        XCTAssertNil(service.configuration.email)
        XCTAssertFalse(service.isAuthenticated)
    }

    func testLifecycleCallbacks() {
        let (service, delegate) = makeService()
        service.completeCreate()
        service.completeUpdate()
        service.completeOnboard()
        XCTAssertTrue(service.isOnboarded)
        XCTAssertGreaterThanOrEqual(delegate.updated, 3)
        service.completeDelete()
        XCTAssertEqual(delegate.deletions, 1)
    }

    func testCompleteDeleteRemovingTokenPurges() {
        let (service, _) = makeService()
        service.token = "jwt"
        service.completeDeleteRemovingToken()
        XCTAssertNil(service.token)
    }

    func testDataLimits() {
        let (service, _) = makeService()
        XCTAssertEqual(service.glucoseDataLimit, 1000)
        XCTAssertEqual(service.doseDataLimit, 1000)
        XCTAssertEqual(service.carbDataLimit, 1000)
        XCTAssertEqual(service.pumpEventDataLimit, 1000)
        XCTAssertEqual(service.dosingDecisionDataLimit, 0)
        XCTAssertEqual(service.settingsDataLimit, 0)
        XCTAssertEqual(service.alertDataLimit, 0)
    }

    func testUnmappedUploadsSucceedImmediately() async {
        let (service, _) = makeService()
        await assertSuccess { service.uploadAlertData([], completion: $0) }
        await assertSuccess { service.uploadTemporaryOverrideData(updated: [], deleted: [], completion: $0) }
        await assertSuccess { service.uploadDosingDecisionData([], completion: $0) }
        await assertSuccess { service.uploadSettingsData([], completion: $0) }
        await assertSuccess { service.uploadCgmEventData([], completion: $0) }
        try? await service.remoteNotificationWasReceived([:])
    }

    func testMappedUploadsFailWhenNotConfigured() async {
        let (service, _) = makeService()
        await assertFailure { service.uploadGlucoseData([], completion: $0) }
        await assertFailure { service.uploadDoseData(created: [], deleted: [], completion: $0) }
        await assertFailure { service.uploadCarbData(created: [], updated: [], deleted: [], completion: $0) }
        await assertFailure { service.uploadPumpEventData([], completion: $0) }
    }

    private func assertSuccess(_ call: (@escaping (Result<Bool, Error>) -> Void) -> Void) async {
        let result = await withCheckedContinuation { (c: CheckedContinuation<Result<Bool, Error>, Never>) in
            call { c.resume(returning: $0) }
        }
        if case .failure = result { XCTFail("expected success") }
    }

    private func assertFailure(_ call: (@escaping (Result<Bool, Error>) -> Void) -> Void) async {
        let result = await withCheckedContinuation { (c: CheckedContinuation<Result<Bool, Error>, Never>) in
            call { c.resume(returning: $0) }
        }
        if case .success = result { XCTFail("expected failure") }
    }
}
