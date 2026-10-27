import Foundation

public struct GlookoSignInRequest: Encodable {
    public struct Login: Encodable { public let email: String; public let password: String }

    public enum Version { case v3, v2 }

    public let version: Version
    public let login: Login

    public init(email: String, password: String, version: Version) {
        self.version = version
        self.login = Login(email: email.lowercased().trimmingCharacters(in: .whitespaces), password: password)
    }

    private enum CodingKeys: String, CodingKey { case user, userLogin }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(login, forKey: version == .v3 ? .user : .userLogin)
    }
}

public struct GlookoTwoFactorValidation: Encodable {
    public let otpAttempt: String
    public let email: String
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
    public var softDeleted = 0
    public var updatedAt: String?

    public init(guid: String, syncTimestamp: String, timestamp: String, value: Int, userMealTag: Int,
                softDeleted: Bool = false) {
        self.guid = guid
        self.syncTimestamp = syncTimestamp
        self.timestamp = timestamp
        self.value = value
        self.userMealTag = userMealTag
        self.softDeleted = softDeleted ? 1 : 0
        self.updatedAt = syncTimestamp
    }
}

public struct GKNote: Encodable {
    public let guid: String
    public let syncTimestamp: String
    public let timestamp: String
    public let value: String
}

public struct GKInsulin: Encodable {
    public enum Kind: String, Encodable { case bolus, basal }

    public let guid: String
    public let timestamp: String
    public let value: Double
    public let insulinType: Kind
    public let softDeleted: Bool
    public let externalId: String
    public let name: String
    public let syncTimestamp: String

    public init(guid: String, timestamp: String, value: Double, insulinType: Kind, softDeleted: Bool = false,
                source: String, syncTimestamp: String) {
        self.guid = guid
        self.timestamp = timestamp
        self.value = (value * 1000).rounded() / 1000
        self.insulinType = insulinType
        self.softDeleted = softDeleted
        self.externalId = "\(source.lowercased()):\(insulinType.rawValue):\(guid.prefix(8))"
        self.name = "\(source) \(insulinType.rawValue)"
        self.syncTimestamp = syncTimestamp
    }

    private enum CodingKeys: String, CodingKey {
        case guid, timestamp, value, insulinType, medicationGuid, softDeleted, deviceDelivered, manuallyEnteredText
        case pumpGuid, insulinPenGuid, cgmDeviceGuid, externalId, name, updatedAt, syncTimestamp
    }

    // medicationGuid stays null: linking a catalogue medication reclassifies basal as bolus.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(guid, forKey: .guid)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(value, forKey: .value)
        try c.encode(insulinType, forKey: .insulinType)
        try c.encodeNil(forKey: .medicationGuid)
        try c.encode(softDeleted ? 1 : 0, forKey: .softDeleted)
        try c.encode(1, forKey: .deviceDelivered)
        try c.encode(false, forKey: .manuallyEnteredText)
        try c.encodeNil(forKey: .pumpGuid)
        try c.encodeNil(forKey: .insulinPenGuid)
        try c.encodeNil(forKey: .cgmDeviceGuid)
        try c.encode(externalId, forKey: .externalId)
        try c.encode(name, forKey: .name)
        try c.encode(syncTimestamp, forKey: .updatedAt)
        try c.encode(syncTimestamp, forKey: .syncTimestamp)
    }
}

public struct GKFood: Encodable {
    public let guid: String
    public let timestamp: String
    public let carbs: Double
    public let softDeleted: Bool
    public let syncTimestamp: String

    public init(guid: String, timestamp: String, carbs: Double, softDeleted: Bool = false, syncTimestamp: String) {
        self.guid = guid
        self.timestamp = timestamp
        self.carbs = carbs
        self.softDeleted = softDeleted
        self.syncTimestamp = syncTimestamp
    }

    private enum CodingKeys: String, CodingKey {
        case guid, timestamp, carbs, mealGuid, source, name, servingQuantity, softDeleted, updatedAt, syncTimestamp
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(guid, forKey: .guid)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(carbs, forKey: .carbs)
        try c.encodeNil(forKey: .mealGuid)
        try c.encode("QuickAdd", forKey: .source)
        try c.encode("", forKey: .name)
        try c.encode(0, forKey: .servingQuantity)
        try c.encode(softDeleted ? 1 : 0, forKey: .softDeleted)
        try c.encode(syncTimestamp, forKey: .updatedAt)
        try c.encode(syncTimestamp, forKey: .syncTimestamp)
    }
}
