import XCTest
import HealthKit
import LoopKit
@testable import GlookoServiceKit

final class GlookoClassicBackendTests: XCTestCase {

    private let mgdl = HKUnit(from: "mg/dL")

    private func makeBackend(_ mock: MockHTTPTransport) -> GlookoClassicBackend {
        var config = GlookoService.Configuration()
        config.variant = .classic
        let api = GlookoClassicAPI(region: .eu, sessionCookie: "c", transport: mock)
        return GlookoClassicBackend(configuration: config, sessionCookie: nil, api: api)
    }

    private func glucose(_ value: Double, userEntered: Bool, _ date: Date) -> StoredGlucoseSample {
        StoredGlucoseSample(startDate: date, quantity: HKQuantity(unit: mgdl, doubleValue: value),
                            wasUserEntered: userEntered)
    }

    func testLibreViewCSVHeaderRowsAndSorting() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let csv = GlookoLibreViewCSV.generate(from: [
            glucose(115, userEntered: false, base.addingTimeInterval(60)),
            glucose(110, userEntered: false, base),
        ])
        let lines = csv.split(separator: "\n")
        XCTAssertTrue(lines[1].contains("Historic Glucose mg/dL"))
        XCTAssertTrue(lines[2].contains(",0,110,"))
        XCTAssertTrue(lines[3].contains(",0,115,"))
        XCTAssertEqual(lines.count, 4)
    }

    func testUploadGlucoseSplitsCGMAndManual() async throws {
        let mock = MockHTTPTransport { req, _ in try MockResponder.status(req, req.url?.path.contains("file") == true ? 200 : 204) }
        let backend = makeBackend(mock)
        try await backend.uploadGlucose([glucose(120, userEntered: false, Date()),
                                         glucose(90, userEntered: true, Date())])
        XCTAssertTrue(mock.paths.contains("/api/v3/device/file/upload"))
        XCTAssertTrue(mock.paths.contains("/api/v2/readings"))
        let readings = try XCTUnwrap(mock.json(forPath: "/api/v2/readings")?["readings"] as? [[String: Any]])
        XCTAssertEqual(readings[0]["value"] as? Int, 9000)
    }

    func testUploadGlucoseManualOnlyNoDeviceFile() async throws {
        let mock = MockHTTPTransport { req, _ in try MockResponder.status(req, 204) }
        let backend = makeBackend(mock)
        try await backend.uploadGlucose([glucose(90, userEntered: true, Date())])
        XCTAssertFalse(mock.paths.contains("/api/v3/device/file/upload"))
        XCTAssertTrue(mock.paths.contains("/api/v2/readings"))
    }

    private func carb(_ grams: Double, _ date: Date) -> SyncCarbObject {
        SyncCarbObject(absorptionTime: nil, createdByCurrentApp: true, foodType: nil, grams: grams,
                       startDate: date, uuid: nil, provenanceIdentifier: "Trio", syncIdentifier: nil,
                       syncVersion: nil, userCreatedDate: nil, userUpdatedDate: nil,
                       userDeletedDate: nil, operation: .create, addedDate: nil, supercededDate: nil)
    }

    func testUploadDosesRoutesBolusToApiAndIgnoresBasal() async throws {
        let mock = MockHTTPTransport { req, _ in try MockResponder.status(req, 204) }
        let backend = makeBackend(mock)
        let now = Date()
        let doses: [DoseEntry] = [
            DoseEntry(type: .bolus, startDate: now, endDate: now, value: 2.5, unit: .units),
            DoseEntry(type: .tempBasal, startDate: now, endDate: now.addingTimeInterval(1800), value: 1.5, unit: .unitsPerHour),
            DoseEntry(type: .basal, startDate: now, endDate: now.addingTimeInterval(3600), value: 0.8, unit: .unitsPerHour),
        ]
        try await backend.uploadDoses(created: doses, deleted: [])

        let insulins = try XCTUnwrap(mock.json(forPath: "/api/v2/insulins")?["insulins"] as? [[String: Any]])
        XCTAssertEqual(insulins.count, 1)
        XCTAssertEqual(insulins[0]["value"] as? Double, 2.5)
        XCTAssertFalse(mock.paths.contains("/device/data"))
    }

    func testUploadPumpSnapshotRoutesBasalToAnalyzerAndBolusToApi() async throws {
        let mock = MockHTTPTransport { req, _ in try MockResponder.status(req, 204) }
        let backend = makeBackend(mock)
        let now = Date()
        let basal: [DoseEntry] = [
            DoseEntry(type: .tempBasal, startDate: now, endDate: now.addingTimeInterval(1800), value: 1.5, unit: .unitsPerHour),
            DoseEntry(type: .basal, startDate: now.addingTimeInterval(1800), endDate: now.addingTimeInterval(3600), value: 0.8, unit: .unitsPerHour),
        ]
        let boluses = [DoseEntry(type: .bolus, startDate: now, endDate: now, value: 2.5, unit: .units)]
        try await backend.uploadPumpSnapshot(basal: basal, boluses: boluses, carbs: [], now: now)

        let insulins = try XCTUnwrap(mock.json(forPath: "/api/v2/insulins")?["insulins"] as? [[String: Any]])
        XCTAssertEqual(insulins[0]["value"] as? Double, 2.5)

        let analyzer = try XCTUnwrap(mock.requests.first { $0.url?.path == "/device/data" })
        XCTAssertEqual(analyzer.value(forHTTPHeaderField: "X-Glooko-Extractor"), "InsuletOmnipod")
        XCTAssertEqual(analyzer.value(forHTTPHeaderField: "Content-Encoding"), "deflate")
        XCTAssertEqual(analyzer.value(forHTTPHeaderField: "Authorization"), "Bearer c")
        XCTAssertEqual(Array(analyzer.httpBody?.prefix(2) ?? []), [0x78, 0x9c])
    }

    func testUploadPumpSnapshotEmptyNoRequests() async throws {
        let mock = MockHTTPTransport { req, _ in try MockResponder.status(req, 204) }
        let backend = makeBackend(mock)
        try await backend.uploadPumpSnapshot(basal: [], boluses: [], carbs: [], now: Date())
        XCTAssertTrue(mock.requests.isEmpty)
    }

    func testUploadDosesBolusOnlyNoAnalyzer() async throws {
        let mock = MockHTTPTransport { req, _ in try MockResponder.status(req, 204) }
        let backend = makeBackend(mock)
        let now = Date()
        try await backend.uploadDoses(created: [DoseEntry(type: .bolus, startDate: now, endDate: now, value: 1, unit: .units)], deleted: [])
        XCTAssertTrue(mock.paths.contains("/api/v2/insulins"))
        XCTAssertFalse(mock.paths.contains("/device/data"))
    }

    func testUploadDosesEmptyNoRequests() async throws {
        let mock = MockHTTPTransport { req, _ in try MockResponder.status(req, 204) }
        let backend = makeBackend(mock)
        try await backend.uploadDoses(created: [], deleted: [])
        XCTAssertTrue(mock.requests.isEmpty)
    }

    func testUploadCarbsRoutesToMealsAndFoodsApi() async throws {
        let mock = MockHTTPTransport { req, _ in try MockResponder.status(req, 204) }
        let backend = makeBackend(mock)
        try await backend.uploadCarbs(created: [carb(30, Date())], updated: [], deleted: [])

        XCTAssertTrue(mock.paths.contains("/api/v2/meals"))
        XCTAssertTrue(mock.paths.contains("/api/v2/foods"))
        XCTAssertFalse(mock.paths.contains("/device/data"))

        let foods = try XCTUnwrap(mock.json(forPath: "/api/v2/foods")?["foods"] as? [[String: Any]])
        XCTAssertEqual(foods[0]["carbs"] as? Double, 30)
        let meals = try XCTUnwrap(mock.json(forPath: "/api/v2/meals")?["meals"] as? [[String: Any]])
        XCTAssertEqual(foods[0]["mealGuid"] as? String, meals[0]["guid"] as? String)
    }

    func testUploadCarbsEmptyNoRequests() async throws {
        let mock = MockHTTPTransport { req, _ in try MockResponder.status(req, 204) }
        let backend = makeBackend(mock)
        try await backend.uploadCarbs(created: [], updated: [], deleted: [])
        XCTAssertTrue(mock.requests.isEmpty)
    }

    func testUploadPumpEventsIsNoOp() async throws {
        let mock = MockHTTPTransport { req, _ in try MockResponder.status(req, 204) }
        let backend = makeBackend(mock)
        let now = Date()
        let event = PersistedPumpEvent(date: now, persistedDate: now, dose: nil, isUploaded: false,
                                       objectIDURL: URL(fileURLWithPath: "/x"), raw: nil, title: nil,
                                       type: .alarm, alarmType: .occlusion)
        try await backend.uploadPumpEvents([event])
        XCTAssertTrue(mock.requests.isEmpty)
    }

    func testLifecycle() async throws {
        let mock = MockHTTPTransport { req, _ in try MockResponder.status(req, 204) }
        let backend = makeBackend(mock)
        XCTAssertEqual(backend.variant, .classic)
        XCTAssertTrue(backend.isConfigured)
        try await backend.prepare()
        backend.tearDown()
    }
}
