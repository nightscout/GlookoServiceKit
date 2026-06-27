import Foundation

public enum GlookoClassicRegion: String, CaseIterable, Codable {
    case auto
    case eu
    case us

    public var displayName: String {
        switch self {
        case .auto: return LocalizedString("Auto-detect", comment: "Glooko region auto")
        case .eu:   return LocalizedString("Europe (eu)", comment: "Glooko region EU")
        case .us:   return LocalizedString("United States (us)", comment: "Glooko region US")
        }
    }

    public var hostPrefix: String? { self == .auto ? nil : rawValue }
}
