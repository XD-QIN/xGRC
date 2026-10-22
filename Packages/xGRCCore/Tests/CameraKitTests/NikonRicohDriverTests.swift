import BLEKit
@testable import CameraKit
import Foundation
import Testing

@Suite("Nikon Remote")
struct NikonRemoteTests {
    private let advertisement = Advertisement(peripheralID: UUID(), localName: "Z6_3", rssi: -50, manufacturerData: nil,
                                              serviceUUIDs: [Nikon.service], isConnectable: true)

    @Test("Stage 1 is 01, timestamp 1 big-endian, then our ID with device byte 0x01")
    func stage1() {
        let id = Nikon.makeID()
        #expect(id.count == 8 && id.first == 0x01)
        let message = Nikon.stage1(id: id)
        #expect(message.count == 17)
        #expect(message.prefix(9).hexString == "01 00 00 00 00 00 00 00 01")
        #expect(message.suffix(8) == id)
    }

    @Test("Pairing menu: service, no manufacturer data; paired: 99 03 + device ID + 00")
    func matching() throws {
        let pairing = try #require(NikonRemoteDriver.matches(advertisement))
        #expect(pairing.isPairable)
        let paired = Advertisement(peripheralID: UUID(), localName: "Z6_3", rssi: -50,
                                   manufacturerData: Data([0x99, 0x03, 0x01, 0xAA, 0xBB, 0xCC, 0x00]),
                                   serviceUUIDs: [Nikon.service], isConnectable: true)
        let match = try #require(NikonRemoteDriver.matches(paired))
        #expect(!match.isPairable)
        #expect(match.details["deviceID"] == "01 aa bb cc")
    }

    @Test("Four-stage handshake returns the ID and the camera serial, and runs again on reconnect")
    func handshake() async throws {
        let camera = SimulatedPeripheral.nikonRemote()
        let driver = NikonRemoteDriver(transport: camera)
        let identity = try await driver.pair(advertisement, client: .generate()) { _ in }
        let id = try #require(identity.values["id"])
        #expect(identity.values["serial"] == Data(SimulatedPeripheral.nikonSerial.utf8))
        try await driver.reconnect(identity: identity, client: .generate())
        let messages = await camera.writes(to: Nikon.remotePairing)
        #expect(messages == [Nikon.stage1(id: id), Nikon.stage3, Nikon.stage1(id: id), Nikon.stage3])
    }

    @Test("A wrong stage 2 is a refused pairing; on reconnect it means pair again")
    func refused() async throws {
        let driver = NikonRemoteDriver(transport: SimulatedPeripheral.nikonRemote(acceptsStage1: false))
        await #expect(throws: CameraError.pairingRejected) {
            _ = try await driver.pair(advertisement, client: .generate()) { _ in }
        }
        await #expect(throws: CameraError.pairAgain) {
            try await driver.reconnect(identity: CameraIdentity(values: ["id": Nikon.makeID()]), client: .generate())
        }
    }

    @Test("A camera set to pair a smart device is unsupported")
    func snapBridge() async throws {
        let driver = NikonRemoteDriver(transport: SimulatedPeripheral.nikonRemote(smartDevice: true))
        await #expect(throws: CameraError.unsupported) {
            _ = try await driver.pair(advertisement, client: .generate()) { _ in }
        }
    }

    @Test("Bulb runs as Time: latch and unlatch are both a press and a release")
    func time() {
        let script = NikonRemoteDriver.script
        func bytes(_ steps: [ShotStep]) -> [String] {
            steps.compactMap { if case .write(let w) = $0 { return w.data.hexString } else { return nil } }
        }
        #expect(bytes(script.latch) == ["02 02", "02 00"])
        #expect(bytes(script.unlatch) == ["02 02", "02 00"])
        #expect(NikonRemoteDriver.descriptor.capabilities.contains(.bulbAsTime))
    }
}

@Suite("Ricoh GR")
struct RicohTests {
    private let advertisement = Advertisement(peripheralID: UUID(), localName: "RICOH GR IIIx", rssi: -50,
                                              manufacturerData: nil, serviceUUIDs: [], isConnectable: true)

    @Test("GPS packet golden vector (32 bytes: big-endian doubles, little-endian year, datum 0)")
    func gpsPacket() {
        #expect(Ricoh.gpsPacket(tokyoFix, time: goldenTime).hexString
                == "40 41 d4 4c 61 d8 62 2c 40 61 77 da 96 4e 8b 7e 40 45 00 00 00 00 00 00 ea 07 0a 0f 0c 22 38 00")
    }

    @Test("Matched by service or by name")
    func matching() {
        #expect(RicohDriver.matches(advertisement) != nil)
        #expect(Ricoh.nameMatches("GR"))
        #expect(!Ricoh.nameMatches("GREAT SPEAKER"))
        let byService = Advertisement(peripheralID: UUID(), localName: nil, rssi: -50, manufacturerData: nil,
                                      serviceUUIDs: [Ricoh.shootingService], isConnectable: true)
        #expect(RicohDriver.matches(byService)?.displayName == "Ricoh GR")
    }

    @Test("A shot is flavour 0 then start with AF; release all is stop")
    func shot() async throws {
        let camera = SimulatedPeripheral.ricoh()
        let driver = RicohDriver(transport: camera)
        _ = try await driver.pair(advertisement, client: .generate()) { _ in }
        await camera.clearWrites()
        _ = try await driver.press(.shutter)
        #expect(await camera.writes.map(\.data.hexString) == ["00", "01 01"])
        #expect(try await driver.press(.focus) == .unsupported)
        // Stop ends an operation a lost link or a failed write left running.
        #expect(RicohDriver.script.releaseAllWrites.map(\.data.hexString) == ["02 00"])
    }

    @Test("Store Location Info. off stops geotagging before any packet; on, packets go out")
    func storeLocation() async throws {
        let off = RicohDriver(transport: SimulatedPeripheral.ricoh(storeLocation: false))
        try await off.reconnect(identity: .bondOnly, client: .generate())
        await #expect(throws: CameraError.locationLinkOff) { _ = try await off.startLocationLink() }

        let camera = SimulatedPeripheral.ricoh(storeLocation: true)
        let on = RicohDriver(transport: camera)
        try await on.reconnect(identity: .bondOnly, client: .generate())
        #expect(try await on.startLocationLink() == .push)
        // A second start on the same connection uses the notified value.
        #expect(try await on.startLocationLink() == .push)
        try await on.updateLocation(tokyoFix, time: goldenTime, zone: .current)
        #expect(await camera.writes(to: Ricoh.gpsInformation).count == 1)

        // The user turns it off on the camera.
        await camera.notify(Data([0x00]), on: Ricoh.geoTag)
        #expect(await poll {
            (try? await on.updateLocation(tokyoFix, time: goldenTime, zone: .current)) == nil
        })
        #expect(on.geotagRules.minimumInterval == .seconds(10))
        #expect(on.geotagRules.stampsSendTime == false)
    }
}
