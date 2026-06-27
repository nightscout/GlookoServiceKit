import SwiftUI
import LoopKit
import LoopKitUI
import GlookoServiceKit

extension GlookoService: @retroactive ServiceUI {

    public static var image: UIImage? { nil }

    public static func setupViewController(colorPalette: LoopUIColorPalette,
                                           pluginHost: PluginHost) -> SetupUIResult<ServiceViewController, ServiceUI> {
        let nav = ServiceNavigationController()
        nav.isNavigationBarHidden = true
        let service = GlookoService(hostIdentifier: pluginHost.hostIdentifier, hostVersion: pluginHost.hostVersion)

        let view = GlookoSettingsView(service: service, onCreated: {
            service.completeCreate()
            nav.notifyServiceCreatedAndOnboarded(service)
        }, dismiss: {
            nav.notifyComplete()
        })
        nav.pushViewController(UIHostingController(rootView: view), animated: false)
        return .userInteractionRequired(nav)
    }

    public func settingsViewController(colorPalette: LoopUIColorPalette) -> ServiceViewController {
        let nav = ServiceNavigationController()
        nav.isNavigationBarHidden = true
        let view = GlookoSettingsView(service: self, onCreated: {}, dismiss: {
            nav.notifyComplete()
        })
        nav.pushViewController(UIHostingController(rootView: view), animated: false)
        return nav
    }
}
