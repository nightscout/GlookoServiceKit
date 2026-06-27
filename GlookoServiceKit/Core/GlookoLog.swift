import Foundation
import os

enum GlookoLog {
    private static let subsystem = "GlookoServiceKit"

    static let xt = Logger(subsystem: subsystem, category: "XT")
    static let classic = Logger(subsystem: subsystem, category: "Classic")
    static let upload = Logger(subsystem: subsystem, category: "Upload")
}
