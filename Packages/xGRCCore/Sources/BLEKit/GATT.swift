import Foundation

// Value types that cross BLEKit's boundary. `CBPeripheral` and
// `CBCharacteristic` never leave BLEKit; only these snapshots do
// (architecture doc § Architecture, executor rule).

extension UUID {
    /// The Bluetooth Base UUID with a 16-bit or 32-bit short UUID filled in:
    /// `0000xxxx-0000-1000-8000-00805F9B34FB`.
    public static func bluetooth(_ short: UInt32) -> UUID {
        let b = withUnsafeBytes(of: short.bigEndian, Array.init)
        return UUID(uuid: (b[0], b[1], b[2], b[3],
                           0x00, 0x00, 0x10, 0x00,
                           0x80, 0x00, 0x00, 0x80, 0x5F, 0x9B, 0x34, 0xFB))
    }

    /// Short form for logs: `FF01` for a base UUID, the full string otherwise.
    public var bluetoothDescription: String {
        let s = uuidString
        if s.hasSuffix("-0000-1000-8000-00805F9B34FB"), s.hasPrefix("0000") {
            return String(s.dropFirst(4).prefix(4))
        }
        return s
    }
}

/// A characteristic is identified by service and characteristic UUID together:
/// Fujifilm reuses one characteristic UUID in two services.
public struct GATTCharacteristicID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let service: UUID
    public let characteristic: UUID

    public init(service: UUID, characteristic: UUID) {
        self.service = service
        self.characteristic = characteristic
    }

    public var description: String {
        "\(service.bluetoothDescription)/\(characteristic.bluetoothDescription)"
    }
}

public struct CharacteristicProperties: OptionSet, Hashable, Sendable, Codable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public static let read = CharacteristicProperties(rawValue: 1 << 0)
    public static let write = CharacteristicProperties(rawValue: 1 << 1)
    public static let writeWithoutResponse = CharacteristicProperties(rawValue: 1 << 2)
    public static let notify = CharacteristicProperties(rawValue: 1 << 3)
    public static let indicate = CharacteristicProperties(rawValue: 1 << 4)

    /// Compact form for the transcript, e.g. `"rwn"`.
    public var transcriptCode: String {
        var s = ""
        if contains(.read) { s += "r" }
        if contains(.write) { s += "w" }
        if contains(.writeWithoutResponse) { s += "W" }
        if contains(.notify) { s += "n" }
        if contains(.indicate) { s += "i" }
        return s
    }
}

public struct GATTCharacteristic: Hashable, Sendable {
    public let id: GATTCharacteristicID
    public let properties: CharacteristicProperties

    public init(id: GATTCharacteristicID, properties: CharacteristicProperties) {
        self.id = id
        self.properties = properties
    }
}

public struct GATTService: Hashable, Sendable {
    public let uuid: UUID
    public let characteristics: [GATTCharacteristic]

    public init(uuid: UUID, characteristics: [GATTCharacteristic]) {
        self.uuid = uuid
        self.characteristics = characteristics
    }
}

extension Array where Element == GATTService {
    public func characteristic(_ id: GATTCharacteristicID) -> GATTCharacteristic? {
        first { $0.uuid == id.service }?.characteristics.first { $0.id == id }
    }

    public func contains(_ id: GATTCharacteristicID) -> Bool {
        characteristic(id) != nil
    }
}

/// Why a link went down.
public enum LinkReason: Hashable, Sendable, Codable {
    case connectionTimeout
    case peerTerminated
    case localTerminated
    case connectionFailed
    case encryptionFailed
    case other(code: Int)
}

public enum GATTError: Error, Hashable, Sendable {
    /// ATT error from the peripheral (e.g. Sony `0x90` = Bluetooth Rmt Ctrl off).
    case att(UInt8)
    /// The camera requires a bonded, encrypted link.
    case insufficientAuthentication
    /// The camera deleted our bond.
    case peerRemovedPairing
    case disconnected(LinkReason)
    case timeout
    /// The driver asked for a characteristic the camera does not have.
    case characteristicNotFound(GATTCharacteristicID)
    /// Bluetooth is off, unauthorised or unsupported.
    case bluetoothUnavailable(CentralState)
    /// A read on a characteristic the driver subscribed to: Core Bluetooth
    /// delivers both on one callback, so reads and notifications cannot be
    /// told apart there.
    case readOnSubscribedCharacteristic(GATTCharacteristicID)
    case other(domain: String, code: Int)
}

/// Link events a driver or session can react to.
public enum LinkEvent: Hashable, Sendable {
    /// The OS re-established the link (pending connect with auto-reconnect).
    case reconnected
    case disconnected(LinkReason, isReconnecting: Bool)
    /// `peripheral(_:didModifyServices:)`: rediscover before giving up.
    case servicesModified
    case bondRemoved
    /// watchOS: the background wake-up budget is nearly spent / spent.
    case backgroundBudget(exceeded: Bool)
}

public enum CentralState: String, Hashable, Sendable, Codable {
    case unknown
    case resetting
    case unsupported
    case unauthorized
    case poweredOff
    case poweredOn
}

/// One advertisement seen by a foreground scan.
public struct Advertisement: Hashable, Sendable {
    /// `CBPeripheral.identifier`: stable per device and per peer, never the MAC.
    public let peripheralID: UUID
    public let localName: String?
    public let rssi: Int
    /// Includes the 2-byte company ID first, as Core Bluetooth reports it.
    public let manufacturerData: Data?
    public let serviceUUIDs: [UUID]
    public let isConnectable: Bool

    public init(peripheralID: UUID, localName: String?, rssi: Int, manufacturerData: Data?,
                serviceUUIDs: [UUID], isConnectable: Bool) {
        self.peripheralID = peripheralID
        self.localName = localName
        self.rssi = rssi
        self.manufacturerData = manufacturerData
        self.serviceUUIDs = serviceUUIDs
        self.isConnectable = isConnectable
    }
}

extension Data {
    /// Lower-case hex with spaces, e.g. `"01 07"`.
    public var hexString: String {
        map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    /// Parses `"01 07"`, `"0107"` or `"01-07"`.
    public init?(hex: String) {
        let digits = hex.filter(\.isHexDigit)
        guard digits.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        var index = digits.startIndex
        while index < digits.endIndex {
            let next = digits.index(index, offsetBy: 2)
            guard let byte = UInt8(digits[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
