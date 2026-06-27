import Foundation

public struct GlookoRecord: Encodable {
    public var recorded_at: String
    public var glycemia: Double?
    public var product_glycemia_id: Int?
    public var fast_insulin: Double?
    public var product_fast_insulin_id: Int?
    public var correction_insulin: Double?
    public var slow_insulin: Double?
    public var product_slow_insulin_id: Int?
    public var basal_rate: Double?
    public var rate_percentage: Double?
    public var duration: Int?
    public var product_pump_id: Int?
    public var pump_stop: Bool?
    public var carbs: Int?
    public var meal_tag: String?
    public var activity_step: Int?
    public var activity_minute: Int?
    public var bolus_rate: Double?
    public var is_prime: Bool?
    public var serial_number: String?
    public var note: String?

    public init(recordedAt: Date) {
        self.recorded_at = GlookoRecord.iso(recordedAt)
    }

    public static func iso(_ date: Date) -> String { GlookoDate.iso(date) }

}

public enum GlookoRecordBuilder {

    public static func cgm(_ date: Date, mgdl: Double, unit: GlucoseUnitPreference) -> GlookoRecord {
        var r = GlookoRecord(recordedAt: date)
        r.glycemia = unit.encode(mgdl: mgdl)
        r.product_glycemia_id = GlookoConstants.Product.cgmLibre
        return r
    }

    public static func manualGlucose(_ date: Date, mgdl: Double, unit: GlucoseUnitPreference) -> GlookoRecord {
        var r = GlookoRecord(recordedAt: date)
        r.glycemia = unit.encode(mgdl: mgdl)
        return r
    }

    public static func bolus(_ date: Date, units: Double, correction: Bool = false) -> GlookoRecord {
        var r = GlookoRecord(recordedAt: date)
        let u = (units * 1000).rounded() / 1000
        r.correction_insulin = correction ? u : nil
        r.fast_insulin = correction ? nil : u
        return r
    }

    public static func smb(_ date: Date, units: Double) -> GlookoRecord {
        var r = bolus(date, units: units, correction: false)
        r.note = "SMB"
        return r
    }

    public static func slowInsulin(_ date: Date, units: Double) -> GlookoRecord {
        var r = GlookoRecord(recordedAt: date)
        r.slow_insulin = (units * 1000).rounded() / 1000
        return r
    }

    public static func scheduledBasal(_ date: Date, rateUPerHour: Double, durationMin: Int?) -> GlookoRecord {
        var r = GlookoRecord(recordedAt: date)
        r.basal_rate = (rateUPerHour * 1000).rounded() / 1000
        r.duration = durationMin
        r.product_pump_id = GlookoConstants.Product.pumpOmnipod
        return r
    }

    public static func loopBasal(_ date: Date, percent: Double, durationMin: Int?) -> GlookoRecord {
        var r = GlookoRecord(recordedAt: date)
        r.rate_percentage = (percent).rounded()
        r.duration = durationMin
        r.product_pump_id = GlookoConstants.Product.pumpOmnipod
        return r
    }

    public static func suspend(_ date: Date, note: String? = nil) -> GlookoRecord {
        var r = GlookoRecord(recordedAt: date)
        r.pump_stop = true
        r.note = note
        return r
    }

    public static func carbs(_ date: Date, grams: Double, mealTag: String? = nil) -> GlookoRecord {
        var r = GlookoRecord(recordedAt: date)
        r.carbs = Int(grams.rounded())
        r.meal_tag = mealTag
        return r
    }

    public static func prime(_ date: Date) -> GlookoRecord {
        var r = GlookoRecord(recordedAt: date)
        r.is_prime = true
        return r
    }
}
