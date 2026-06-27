import XCTest
@testable import GlookoServiceKit

final class GlookoClassicDTOTests: XCTestCase {

    private func encodeJSON<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testSSv2BodyWrapsUnderJsonName() throws {
        let body = SSv2Body(jsonName: "readings", items: [
            GKReading(guid: "g", syncTimestamp: "t", timestamp: "ts", value: 120, userMealTag: 0)
        ])
        let json = try encodeJSON(body)
        let array = try XCTUnwrap(json["readings"] as? [[String: Any]])
        XCTAssertEqual(array.count, 1)
        XCTAssertEqual(array[0]["value"] as? Int, 120)
    }

    func testReadingEncodesAllFields() throws {
        let json = try encodeJSON(GKReading(guid: "g", syncTimestamp: "s", timestamp: "t",
                                            value: 99, userMealTag: 1))
        XCTAssertEqual(json["guid"] as? String, "g")
        XCTAssertEqual(json["value"] as? Int, 99)
        XCTAssertEqual(json["userMealTag"] as? Int, 1)
    }

    func testInsulinAndNoteEncodeValue() throws {
        XCTAssertEqual(try encodeJSON(GKInsulin(guid: "g", syncTimestamp: "s", timestamp: "t", value: 12))["value"] as? Double, 12)
        XCTAssertEqual(try encodeJSON(GKNote(guid: "g", syncTimestamp: "s", timestamp: "t", value: "hi"))["value"] as? String, "hi")
    }

    func testDeviceInformationHasAllFields() throws {
        let json = try encodeJSON(GlookoDeviceInformation(deviceId: "dev-1"))
        ["applicationType", "applicationVersion", "buildNumber", "clinicalResearch", "device",
         "deviceId", "deviceManufacturer", "deviceModel", "extractionInterface", "gitHash",
         "os", "osVersion", "serialNumber"].forEach { XCTAssertNotNil(json[$0], $0) }
        XCTAssertEqual(json["deviceId"] as? String, "dev-1")
    }

    func testSignInRequestLowercasesEmail() throws {
        let json = try encodeJSON(GlookoSignInRequest(email: "USER@X.COM", password: "pw",
                                                      device: GlookoDeviceInformation(deviceId: "d")))
        let login = try XCTUnwrap(json["userLogin"] as? [String: Any])
        XCTAssertEqual(login["email"] as? String, "user@x.com")
        XCTAssertEqual(login["password"] as? String, "pw")
        XCTAssertNotNil(json["deviceInformation"])
    }

    func testRegionResponseDecodes() throws {
        let data = Data(#"{"urls":{"apiBase":"https://us.patient-api.glooko.com"}}"#.utf8)
        let region = try JSONDecoder().decode(GlookoRegionResponse.self, from: data)
        XCTAssertEqual(region.urls?.apiBase, "https://us.patient-api.glooko.com")
    }
}
