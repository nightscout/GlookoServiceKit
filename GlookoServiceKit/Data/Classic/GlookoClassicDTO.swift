import Foundation

public struct GlookoDeviceInformation: Encodable {
    public var applicationType = "logbook"
    public var applicationVersion = "6.16.0"
    public var buildNumber = 160000
    public var clinicalResearch = false
    public var device = "iPhone"
    public var deviceId: String
    public var deviceManufacturer = "Apple"
    public var deviceModel = "iPhone"
    public var extractionInterface = "none"
    public var gitHash = "trio-glooko"
    public var os = "ios"
    public var osVersion = "17.0"
    public var serialNumber = ""

    public init(deviceId: String) { self.deviceId = deviceId }
}

public struct GlookoSignInRequest: Encodable {
    public struct UserLogin: Encodable { public let email: String; public let password: String }
    public let userLogin: UserLogin
    public let deviceInformation: GlookoDeviceInformation

    public init(email: String, password: String, device: GlookoDeviceInformation) {
        self.userLogin = UserLogin(email: email.lowercased(), password: password)
        self.deviceInformation = device
    }
}

public struct GlookoTwoFactorValidation: Encodable {
    public let otpAttempt: String
    public let email: String
    public let deviceInformation: GlookoDeviceInformation
}

public struct GlookoRegionResponse: Decodable {
    public struct URLs: Decodable { public let apiBase: String? }
    public let urls: URLs?
}

public struct SSv2Body<Item: Encodable>: Encodable {
    public let jsonName: String
    public let items: [Item]

    public init(jsonName: String, items: [Item]) { self.jsonName = jsonName; self.items = items }

    private struct DynamicKey: CodingKey {
        let stringValue: String
        init(_ s: String) { stringValue = s }
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        try container.encode(items, forKey: DynamicKey(jsonName))
    }
}

public struct GKReading: Encodable {
    public let guid: String
    public let syncTimestamp: String
    public let timestamp: String
    public let value: Int
    public let userMealTag: Int
}

public struct GKNote: Encodable {
    public let guid: String
    public let syncTimestamp: String
    public let timestamp: String
    public let value: String
}

public struct GKInsulin: Encodable {
    public let guid: String
    public let syncTimestamp: String
    public let timestamp: String
    public let value: Double
}

public struct GKMeal: Encodable {
    public let guid: String
    public let timestamp: String
    public let name: String
    public let type: String
}

public struct GKFood: Encodable {
    public let guid: String
    public let syncTimestamp: String
    public let timestamp: String
    public let mealGuid: String
    public let name: String
    public let carbs: Double
}
