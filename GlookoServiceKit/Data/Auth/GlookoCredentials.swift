import Foundation

struct GlookoCredentials {
    private let store: GlookoCredentialStore
    private let id: String

    init(store: GlookoCredentialStore, id: String) {
        self.store = store
        self.id = id
    }

    var token: String? {
        get { (try? store.value(for: id)) ?? nil }
        nonmutating set { try? store.set(newValue, for: id) }
    }

    var classicPassword: String? {
        get { (try? store.value(for: passwordKey)) ?? nil }
        nonmutating set { try? store.set(newValue, for: passwordKey) }
    }

    func clear() {
        token = nil
        classicPassword = nil
    }

    private var passwordKey: String { "\(id).password" }
}
