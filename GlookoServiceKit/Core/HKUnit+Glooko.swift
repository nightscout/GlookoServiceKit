import HealthKit

extension HKUnit {

    static var gkMilligramsPerDeciliter: HKUnit { HKUnit(from: "mg/dL") }

    static var gkMillimolesPerLiter: HKUnit {
        HKUnit.moleUnit(with: .milli, molarMass: HKUnitMolarMassBloodGlucose).unitDivided(by: .liter())
    }

    static var gkInternationalUnitsPerHour: HKUnit { HKUnit(from: "IU/hr") }
}
