import Foundation

struct GlookoUploadCoordinator {
    let backend: () -> GlookoBackend

    func perform(_ work: @escaping (GlookoBackend) async throws -> Void) async throws {
        let backend = backend()
        guard backend.isConfigured else { throw GlookoAPIError.noToken }
        try await backend.prepare()
        try await work(backend)
    }
}
