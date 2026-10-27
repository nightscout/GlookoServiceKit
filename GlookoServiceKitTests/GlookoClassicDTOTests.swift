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
        XCTAssertEqual(try encodeJSON(GKInsulin(guid: "g", timestamp: "t", value: 12, insulinType: .bolus,
                                                source: "Trio", syncTimestamp: "s"))["value"] as? Double, 12)
        XCTAssertEqual(try encodeJSON(GKNote(guid: "g", syncTimestamp: "s", timestamp: "t", value: "hi"))["value"] as? String, "hi")
    }

    func testSignInRequestV3AndV2Shapes() throws {
        let v3 = try encodeJSON(GlookoSignInRequest(email: " USER@X.COM ", password: "pw", version: .v3))
        let user = try XCTUnwrap(v3["user"] as? [String: Any])
        XCTAssertEqual(user["email"] as? String, "user@x.com")
        XCTAssertEqual(user["password"] as? String, "pw")
        XCTAssertNil(v3["userLogin"])
        XCTAssertNil(v3["deviceInformation"])
        let v2 = try encodeJSON(GlookoSignInRequest(email: "a@b.c", password: "pw", version: .v2))
        XCTAssertNotNil(v2["userLogin"])
        XCTAssertNil(v2["user"])
        XCTAssertNil(v2["deviceInformation"])
    }

    func testTwoFactorBodyHasNoDeviceInformation() throws {
        let json = try encodeJSON(GlookoTwoFactorValidation(otpAttempt: "123456", email: "a@b.c"))
        XCTAssertEqual(Set(json.keys), ["otpAttempt", "email"])
    }

    func testInsulinEncodesVerifiedShape() throws {
        let json = try encodeJSON(GKInsulin(guid: "abcdef12-0000", timestamp: "t", value: 1.23456, insulinType: .basal,
                                            softDeleted: true, source: "Trio", syncTimestamp: "s"))
        XCTAssertEqual(json["value"] as? Double, 1.235)
        XCTAssertEqual(json["insulinType"] as? String, "basal")
        XCTAssertEqual(json["softDeleted"] as? Int, 1)
        XCTAssertEqual(json["deviceDelivered"] as? Int, 1)
        XCTAssertEqual(json["manuallyEnteredText"] as? Bool, false)
        XCTAssertEqual(json["externalId"] as? String, "trio:basal:abcdef12")
        XCTAssertEqual(json["updatedAt"] as? String, "s")
        XCTAssertEqual(json["syncTimestamp"] as? String, "s")
        for key in ["medicationGuid", "pumpGuid", "insulinPenGuid", "cgmDeviceGuid"] {
            XCTAssertTrue(json[key] is NSNull, key)
        }
    }

    func testFoodIsStandaloneQuickAdd() throws {
        let json = try encodeJSON(GKFood(guid: "g", timestamp: "t", carbs: 30, syncTimestamp: "s"))
        XCTAssertEqual(json["source"] as? String, "QuickAdd")
        XCTAssertTrue(json["mealGuid"] is NSNull)
        XCTAssertEqual(json["carbs"] as? Double, 30)
        XCTAssertEqual(json["softDeleted"] as? Int, 0)
        XCTAssertEqual(json["servingQuantity"] as? Int, 0)
    }

    func testRegionResponseDecodes() throws {
        let data = Data(#"{"urls":{"apiBase":"https://us.patient-api.glooko.com"}}"#.utf8)
        let region = try JSONDecoder().decode(GlookoRegionResponse.self, from: data)
        XCTAssertEqual(region.urls?.apiBase, "https://us.patient-api.glooko.com")
    }
}
