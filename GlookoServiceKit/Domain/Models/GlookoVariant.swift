import Foundation

public enum GlookoVariant: String, Codable, CaseIterable {
    case xt
    case classic

    public var localizedTitle: String {
        switch self {
        case .xt: return "Glooko XT"
        case .classic: return "Glooko"
        }
    }
}
