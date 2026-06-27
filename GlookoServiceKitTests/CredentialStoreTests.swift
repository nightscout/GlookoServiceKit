import XCTest
import LoopKit
@testable import GlookoServiceKit

final class CredentialStoreTests: XCTestCase {

    func testInMemoryRoundTrip() throws {
        let store = InMemoryCredentialStore()
        XCTAssertNil(try store.value(for: "k"))
        try store.set("secret", for: "k")
        XCTAssertEqual(try store.value(for: "k"), "secret")
    }

    func testInMemoryRemoveOnNil() throws {
        let store = InMemoryCredentialStore()
        try store.set("secret", for: "k")
        try store.set(nil, for: "k")
        XCTAssertNil(try store.value(for: "k"))
    }

    func testKeychainRoundTripAndAbsent() throws {
        let store = KeychainCredentialStore(prefix: "test.glooko.\(UUID().uuidString)")
        let key = "session"
        do {
            let absent = try store.value(for: key)
            XCTAssertNil(absent)
            try store.set("tok-123", for: key)
            let stored = try store.value(for: key)
            XCTAssertEqual(stored, "tok-123")
            try store.set(nil, for: key)
            let removed = try store.value(for: key)
            XCTAssertNil(removed)
        } catch let error as KeychainManagerError {

            throw XCTSkip("Keychain unavailable in this test environment: \(error)")
        }
    }
}
