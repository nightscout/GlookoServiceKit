import Foundation

public enum GlucoseUnitPreference: String, Codable {
    case mgdl
    case mmol

    public func encode(mgdl: Double) -> Double {
        switch self {
        case .mgdl: return mgdl.rounded()
        case .mmol: return (mgdl * 0.0555 * 10).rounded() / 10
        }
    }
}
