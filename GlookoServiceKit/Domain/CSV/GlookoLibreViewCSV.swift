import Foundation
import LoopKit
import HealthKit

enum GlookoLibreViewCSV {

    static func generate(from samples: [StoredGlucoseSample]) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd-yyyy HH:mm"
        formatter.timeZone = TimeZone.current
        let header = "Device,Serial Number,Device Timestamp,Record Type,Historic Glucose mg/dL,"
            + "Scan Glucose mg/dL,Non-numeric Rapid-Acting Insulin,Rapid-Acting Insulin (units),"
            + "Non-numeric Food,Carbohydrates (grams),Carbohydrates (servings),"
            + "Non-numeric Long-Acting Insulin,Long-Acting Insulin (units),Notes,"
            + "Strip Glucose mg/dL,Ketone mmol/L,Meal Insulin (units),Correction Insulin (units),"
            + "User Change Insulin (units)"
        var rows = ["Glucose,Generated on,\(formatter.string(from: Date())),Trio,Trio CGM", header]
        for sample in samples.sorted(by: { $0.startDate < $1.startDate }) {
            let mgdl = Int(sample.quantity.doubleValue(for: .gkMilligramsPerDeciliter).rounded())
            rows.append("FreeStyle LibreLink,Trio,\(formatter.string(from: sample.startDate)),0,\(mgdl),,,,,,,,,,,,,,")
        }
        return rows.joined(separator: "\n") + "\n"
    }
}
