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

    private func glucose(_ value: Double, userEntered: Bool, _ date: Date, id: String? = nil) -> StoredGlucoseSample {
        StoredGlucoseSample(syncIdentifier: id, startDate: date, quantity: HKQuantity(unit: mgdl, doubleValue: value),
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

    func testLibreViewCSVRowsDoNotClaimALibreDevice() {
        let csv = GlookoLibreViewCSV.generate(from: [glucose(110, userEntered: false, Date())])
        XCTAssertFalse(csv.contains("Libre"))
        XCTAssertTrue(csv.split(separator: "\n")[2].hasPrefix("Trio CGM,"))
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

    func testManualReadingGuidIsStable() async throws {
        let mock = MockHTTPTransport { req, _ in try MockResponder.status(req, 204) }
        let backend = makeBackend(mock)
        try await backend.uploadGlucose([glucose(90, userEntered: true, Date(), id: "r1")])
        let readings = try XCTUnwrap(mock.json(forPath: "/api/v2/readings")?["readings"] as? [[String: Any]])
        XCTAssertEqual(readings[0]["guid"] as? String, GlookoGUID.reading("r1"))
    }

    func testUploadGlucoseManualOnlyNoDeviceFile() async throws {
        let mock = MockHTTPTransport { req, _ in try MockResponder.status(req, 204) }
        let backend = makeBackend(mock)
        try await backend.uploadGlucose([glucose(90, userEntered: true, Date())])
        XCTAssertFalse(mock.paths.contains("/api/v3/device/file/upload"))
        XCTAssertTrue(mock.paths.contains("/api/v2/readings"))
    }

    private func carb(_ grams: Double, _ date: Date, id: String? = nil) -> SyncCarbObject {
        SyncCarbObject(absorptionTime: nil, createdByCurrentApp: true, foodType: nil, grams: grams,
                       startDate: date, uuid: nil, provenanceIdentifier: "Trio", syncIdentifier: id,
                       syncVersion: nil, userCreatedDate: nil, userUpdatedDate: nil,
                       userDeletedDate: nil, operation: .create, addedDate: nil, supercededDate: nil)
    }

    private func insulins(_ mock: MockHTTPTransport) throws -> [[String: Any]] {
        try XCTUnwrap(mock.json(forPath: "/api/v2/insulins")?["insulins"] as? [[String: Any]])
    }

    private func bolus(_ units: Double, _ date: Date, id: String?, mutable: Bool = false) -> DoseEntry {
        DoseEntry(type: .bolus, startDate: date, endDate: date, value: units, unit: .units, syncIdentifier: id, isMutable: mutable)
    }

    private func utcHour(_ hour: Int) -> Date { Date(timeIntervalSince1970: 1_800_000_000 + Double(hour) * 3600) }

    func testUploadDosesRoutesBolusToApiAndIgnoresBasal() async throws {
        let mock = MockHTTPTransport { req, _ in try MockResponder.status(req, 204) }
        let backend = makeBackend(mock)
        let now = Date()
        let doses: [DoseEntry] = [
            bolus(2.5, now, id: "b1"),
            DoseEntry(type: .tempBasal, startDate: now, endDate: now.addingTimeInterval(1800), value: 1.5, unit: .unitsPerHour),
            DoseEntry(type: .basal, startDate: now, endDate: now.addingTimeInterval(3600), value: 0.8, unit: .unitsPerHour),
        ]
        try await backend.uploadDoses(created: doses, deleted: [])

        let sent = try insulins(mock)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0]["value"] as? Double, 2.5)
        XCTAssertEqual(sent[0]["insulinType"] as? String, "bolus")
        XCTAssertEqual(sent[0]["guid"] as? String, GlookoGUID.bolus("b1"))
        XCTAssertEqual(sent[0]["softDeleted"] as? Int, 0)
    }

    func testBolusGuidIsStableAcrossSends() async throws {
        let mock = MockHTTPTransport { req, _ in try MockResponder.status(req, 204) }
        let backend = makeBackend(mock)
        let now = Date()
        try await backend.uploadDoses(created: [bolus(1, now, id: "same")], deleted: [])
        try await backend.uploadDoses(created: [bolus(1, now, id: "same")], deleted: [])
        let guids = mock.requests.filter { $0.url?.path == "/api/v2/insulins" }.compactMap { request -> String? in
            let body = try? JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
            return ((body?["insulins"] as? [[String: Any]])?.first?["guid"]) as? String
        }
        XCTAssertEqual(guids.count, 2)
        XCTAssertEqual(Set(guids).count, 1)
    }

    func testDeletedBolusIsSoftDeletedOnSameGuid() async throws {
        let mock = MockHTTPTransport { req, _ in try MockResponder.status(req, 204) }
        let backend = makeBackend(mock)
        try await backend.uploadDoses(created: [], deleted: [bolus(1, Date(), id: "gone")])
        let sent = try insulins(mock)
        XCTAssertEqual(sent[0]["guid"] as? String, GlookoGUID.bolus("gone"))
        XCTAssertEqual(sent[0]["softDeleted"] as? Int, 1)
    }

    func testMutableBolusIsHeldBack() async throws {
        let mock = MockHTTPTransport { req, _ in try MockResponder.status(req, 204) }
        let backend = makeBackend(mock)
        try await backend.uploadDoses(created: [bolus(1, Date(), id: "running", mutable: true)], deleted: [])
        XCTAssertTrue(mock.requests.isEmpty)
    }

    func testInsulinWritesPingSyncComplete() async throws {
        let mock = MockHTTPTransport { req, _ in try MockResponder.status(req, 204) }
        let backend = makeBackend(mock)
        try await backend.uploadDoses(created: [bolus(1, Date(), id: "b")], deleted: [])
        XCTAssertEqual(mock.paths, ["/api/v2/insulins", "/api/v3/users/activities_and_event_data_sync/complete"])
    }

    func testSyncCompleteFailureIsIgnored() async throws {
        let mock = MockHTTPTransport { req, _ in
            try MockResponder.status(req, req.url?.path.contains("sync/complete") == true ? 500 : 204)
        }
        let backend = makeBackend(mock)
        try await backend.uploadDoses(created: [bolus(1, Date(), id: "b")], deleted: [])
        XCTAssertEqual(mock.requests.count, 2)
    }

    func testUploadPumpSnapshotSendsHourlyBasalAndBoluses() async throws {
        let mock = MockHTTPTransport { req, _ in try MockResponder.status(req, 204) }
        let backend = makeBackend(mock)
        let basal: [DoseEntry] = [
            DoseEntry(type: .tempBasal, startDate: utcHour(0), endDate: utcHour(0).addingTimeInterval(1800), value: 2, unit: .unitsPerHour),
            DoseEntry(type: .basal, startDate: utcHour(0).addingTimeInterval(1800), endDate: utcHour(2), value: 1, unit: .unitsPerHour),
        ]
        try await backend.uploadPumpSnapshot(basal: basal, boluses: [bolus(2.5, utcHour(0), id: "b1")], carbs: [],
                                             now: utcHour(3))

        let sent = try insulins(mock)
        let basals = sent.filter { $0["insulinType"] as? String == "basal" }
        XCTAssertEqual(basals.map { $0["value"] as? Double }, [1.5, 1.0])
        XCTAssertEqual(basals.map { $0["guid"] as? String }, [GlookoGUID.basalHour(utcHour(0)), GlookoGUID.basalHour(utcHour(1))])
        XCTAssertEqual(sent.filter { $0["insulinType"] as? String == "bolus" }.count, 1)
        XCTAssertFalse(mock.paths.contains("/device/data"))
        XCTAssertNil(mock.requests.first?.value(forHTTPHeaderField: "X-Glooko-API-Key"))
    }

    func testSnapshotSoftDeletesSuspendedHour() async throws {
        let mock = MockHTTPTransport { req, _ in try MockResponder.status(req, 204) }
        let backend = makeBackend(mock)
        let basal = [DoseEntry(type: .suspend, startDate: utcHour(0), endDate: utcHour(1), value: 0, unit: .units)]
        try await backend.uploadPumpSnapshot(basal: basal, boluses: [], carbs: [], now: utcHour(2))
        let sent = try insulins(mock)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0]["softDeleted"] as? Int, 1)
    }

    func testUploadPumpSnapshotEmptyNoRequests() async throws {
        let mock = MockHTTPTransport { req, _ in try MockResponder.status(req, 204) }
        let backend = makeBackend(mock)
        try await backend.uploadPumpSnapshot(basal: [], boluses: [], carbs: [], now: Date())
        XCTAssertTrue(mock.requests.isEmpty)
    }

    func testUploadDosesEmptyNoRequests() async throws {
        let mock = MockHTTPTransport { req, _ in try MockResponder.status(req, 204) }
        let backend = makeBackend(mock)
        try await backend.uploadDoses(created: [], deleted: [])
        XCTAssertTrue(mock.requests.isEmpty)
    }

    func testUploadCarbsSendsStandaloneFoodsOnly() async throws {
        let mock = MockHTTPTransport { req, _ in try MockResponder.status(req, 204) }
        let backend = makeBackend(mock)
        try await backend.uploadCarbs(created: [carb(30, Date(), id: "c1")], updated: [], deleted: [])

        XCTAssertFalse(mock.paths.contains("/api/v2/meals"))
        let foods = try XCTUnwrap(mock.json(forPath: "/api/v2/foods")?["foods"] as? [[String: Any]])
        XCTAssertEqual(foods[0]["carbs"] as? Double, 30)
        XCTAssertEqual(foods[0]["guid"] as? String, GlookoGUID.food("c1"))
        XCTAssertEqual(foods[0]["source"] as? String, "QuickAdd")
        XCTAssertTrue(foods[0]["mealGuid"] is NSNull)
        XCTAssertTrue(mock.paths.contains("/api/v3/users/activities_and_event_data_sync/complete"))
    }

    func testCarbEditAndDeleteReuseGuid() async throws {
        let mock = MockHTTPTransport { req, _ in try MockResponder.status(req, 204) }
        let backend = makeBackend(mock)
        try await backend.uploadCarbs(created: [], updated: [carb(40, Date(), id: "c1")], deleted: [carb(30, Date(), id: "c2")])
        let foods = try XCTUnwrap(mock.json(forPath: "/api/v2/foods")?["foods"] as? [[String: Any]])
        XCTAssertEqual(foods.map { $0["guid"] as? String }, [GlookoGUID.food("c1"), GlookoGUID.food("c2")])
        XCTAssertEqual(foods.map { $0["softDeleted"] as? Int }, [0, 1])
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
