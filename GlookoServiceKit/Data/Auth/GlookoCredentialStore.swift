import Foundation
import LoopKit

public protocol GlookoCredentialStore: AnyObject {
    func set(_ value: String?, for key: String) throws
    func value(for key: String) throws -> String?
}

public final class KeychainCredentialStore: GlookoCredentialStore {
    private let keychain = KeychainManager()
    private let prefix: String

    public init(prefix: String = "org.nightscout.GlookoService") {
        self.prefix = prefix
    }

    private func service(_ key: String) -> String { "\(prefix).\(key)" }

    public func set(_ value: String?, for key: String) throws {
        try keychain.replaceGenericPassword(value, forService: service(key))
    }

    public func value(for key: String) throws -> String? {
        do {
            return try keychain.getGenericPasswordForService(service(key))
        } catch let KeychainManagerError.copy(status) where status == errSecItemNotFound {
            return nil
        }
    }
}

public final class InMemoryCredentialStore: GlookoCredentialStore {
    private var storage: [String: String] = [:]
    public init() {}

    public func set(_ value: String?, for key: String) throws {
        guard let value else { storage[key] = nil; return }
        storage[key] = value
    }

    public func value(for key: String) throws -> String? { storage[key] }
}
