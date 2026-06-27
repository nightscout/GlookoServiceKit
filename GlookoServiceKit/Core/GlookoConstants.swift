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

        static let analyzerApiKey = "LkUiWKNcHvtKs8CckMzFPfLE"
        static let analyzerSwid = "A18507"
        static let analyzerExtractor = "InsuletOmnipod"
        static func analyzerBase(from patientApiBase: String) -> String {
            patientApiBase.replacingOccurrences(of: "patient-api", with: "upload")
        }
    }

    static let userAgent = "GlookoServiceKit GlookoAndroid/6.16.0"
}
