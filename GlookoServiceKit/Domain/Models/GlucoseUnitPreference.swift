import Foundation
import HealthKit

public enum GlucoseUnitPreference: String, Codable {
    case mgdl
    case mmol

    public func encode(mgdl: Double) -> Double {
        switch self {
        case .mgdl: return mgdl.rounded()
        case .mmol:
            let mmol = HKQuantity(unit: .gkMilligramsPerDeciliter, doubleValue: mgdl).doubleValue(for: .gkMillimolesPerLiter)
            return (mmol * 10).rounded() / 10
        }
    }
}
