import os.log
import LoopKitUI
import GlookoServiceKit
import GlookoServiceKitUI

class GlookoServiceKitPlugin: NSObject, ServiceUIPlugin {
    private let log = OSLog(subsystem: "GlookoServiceKitPlugin", category: "GlookoServiceKitPlugin")

    public var serviceType: ServiceUI.Type? { GlookoService.self }

    override init() {
        super.init()
        os_log("Instantiated", log: log, type: .default)
    }
}
