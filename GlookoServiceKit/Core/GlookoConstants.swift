import Foundation

enum GlookoConstants {

    enum Product {
        static let cgmLibre = 85
        static let pumpOmnipod = 96
    }

    enum XT {
        static let restBase = URL(string: "https://srv.glookoxt.com")!
        static let socketBase = URL(string: "https://srv.glookoxt.com")!

        static let apiVersion = "3.17.0"
    }

    enum Classic {
        static let globalBase = "https://global.api.glooko.com"
        static func patientApiBase(prefix: String) -> String {
            "https://\(prefix).patient-api.glooko.com"
        }
    }

    static let repositoryURL = "https://github.com/nightscout/GlookoServiceKit"
}

/// Who is talking to Glooko. Sent as-is; never impersonates a Glooko client.
public struct GlookoClientIdentity: Equatable {
    public var hostIdentifier: String
    public var hostVersion: String

    public init(hostIdentifier: String = "unknown", hostVersion: String = "0") {
        self.hostIdentifier = hostIdentifier
        self.hostVersion = hostVersion
    }

    public var sourceName: String {
        hostIdentifier.split(separator: ".").last.map(String.init) ?? hostIdentifier
    }

    public var userAgent: String {
        "GlookoServiceKit (\(hostIdentifier)/\(hostVersion); +\(GlookoConstants.repositoryURL))"
    }
}
