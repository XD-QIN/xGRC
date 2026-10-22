import BLEKit
@testable import CameraKit
import Foundation
import Testing

/// 2026-10-15 12:34:56 UTC, shared by the packet golden vectors.
let goldenTime = Date(timeIntervalSince1970: 1_792_067_696)
let tokyoFix = GeoFix(latitude: 35.658581, longitude: 139.745433, altitude: 42, horizontalAccuracy: 5,
                      timestamp: goldenTime)

/// Polls until `condition` holds, for values that arrive through notification pumps.
func poll(_ condition: @Sendable () async -> Bool) async -> Bool {
    for _ in 0..<400 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return await condition()
}

@Suite("Fujifilm protocol")
struct FujifilmProtocolTests {
    @Test("The type byte decides the firmware: 0x02 + token is legacy, 0x01 + serial is secure")
    func firmware() {
        #expect(Fujifilm.firmware(manufacturerData: Data([0xD8, 0x04, 0x02, 0xAA, 0xBB, 0xCC, 0xDD]))
                == .legacy(token: Data([0xAA, 0xBB, 0xCC, 0xDD])))
        #expect(Fujifilm.firmware(manufacturerData: Data([0xD8, 0x04, 0x01, 1, 2, 3, 4, 5]))
                == .secure(serial: Data([1, 2, 3, 4, 5])))
        // Wrong length for the type, other company IDs.
        #expect(Fujifilm.firmware(manufacturerData: Data([0xD8, 0x04, 0x02, 1, 2, 3, 4, 5])) == nil)
        #expect(Fujifilm.firmware(manufacturerData: Data([0x2D, 0x01, 0x01, 1, 2, 3, 4, 5])) == nil)
    }

    @Test("A secure body is pairable only while it advertises the unregistered service")
    func pairable() throws {
        func advertisement(_ services: [UUID]) -> Advertisement {
            Advertisement(peripheralID: UUID(), localName: "X-T5", rssi: -50,
                          manufacturerData: Data([0xD8, 0x04, 0x01, 1, 2, 3, 4, 5]),
                          serviceUUIDs: services, isConnectable: true)
        }
        let open = try #require(FujifilmDriver.matches(advertisement([Fujifilm.unregisteredService])))
        #expect(open.isPairable)
        #expect(open.details["serial"] == "01 02 03 04 05")
        let registered = try #require(FujifilmDriver.matches(advertisement([Fujifilm.securePairingService])))
        #expect(!registered.isPairable)
    }

    @Test("Location packet golden vector (23 bytes, little-endian)")
    func locationPacket() {
        let packet = Fujifilm.locationPacket(tokyoFix, time: goldenTime)
        #expect(packet.hexString == "52 11 41 15 fa 75 4b 53 2a 00 00 00 00 00 00 00 ea 07 0a 0f 0c 22 38")
    }

    @Test("Only 01 00 on the geotag-request characteristic is a location request")
    func decoding() {
        #expect(Fujifilm.decode(Data([0x01, 0x00]), from: Fujifilm.geotagRequest) == .locationRequested)
        #expect(Fujifilm.decode(Data([0x01, 0x00]), from: Fujifilm.dateSyncState)
                == .unknown(characteristic: Fujifilm.dateSyncState, value: Data([0x01, 0x00])))
    }

    @Test("Shot script: no acks, a timed press, and release ends focus and shutter")
    func script() {
        let script = FujifilmDriver.script
        #expect(!ShotScript.confirmsShutter(script.shootFromFocus))
        #expect(!script.acknowledgesFocus)
        #expect(script.shootFromFocus.contains(.hold(.milliseconds(100))))
        #expect(!FujifilmDriver.descriptor.capabilities.contains(.ackShutter))
    }
}

@Suite("Fujifilm driver on a simulated body")
struct FujifilmDriverTests {
    private func advertisement(secure: Bool) -> Advertisement {
        let data = secure ? Data([0xD8, 0x04, 0x01, 1, 2, 3, 4, 5]) : Data([0xD8, 0x04, 0x02, 0xAA, 0xBB, 0xCC, 0xDD])
        return Advertisement(peripheralID: UUID(), localName: "X100VI", rssi: -50, manufacturerData: data,
                             serviceUUIDs: secure ? [Fujifilm.unregisteredService] : Fujifilm.legacyAdvertisedServices,
                             isConnectable: true)
    }

    @Test("Secure pairing: status back with byte 3 = 0x20, name, notifications, 10 s sync cycle")
    func securePairing() async throws {
        let camera = SimulatedPeripheral.fujifilm(secure: true)
        let driver = FujifilmDriver(transport: camera)
        let client = ClientIdentity.generate()
        let steps = StepRecorder()
        let identity = try await driver.pair(advertisement(secure: true), client: client) { steps.append($0) }

        #expect(identity.values["serial"] == Data([1, 2, 3, 4, 5]))
        #expect(steps.values == [.bonding, .registering, .done])
        #expect(await camera.writes(to: Fujifilm.secureStatus) == [Data([0x07, 0x96, 0x00, 0x20])])
        #expect(await camera.writes(to: Fujifilm.secureName) == [Data(client.name.utf8)])
        #expect(await camera.writes(to: Fujifilm.locationSyncCycle) == [Data([0x0A, 0x00])])
        #expect(await camera.isSubscribed(Fujifilm.dateSyncState))
        #expect(await camera.isSubscribed(Fujifilm.geotagRequest))
    }

    @Test("Legacy pairing writes the advertised token and is repeated on reconnect")
    func legacyPairing() async throws {
        let camera = SimulatedPeripheral.fujifilm(secure: false)
        let driver = FujifilmDriver(transport: camera)
        let identity = try await driver.pair(advertisement(secure: false), client: .generate()) { _ in }
        #expect(identity.values["token"] == Data([0xAA, 0xBB, 0xCC, 0xDD]))
        try await driver.reconnect(identity: identity, client: .generate())
        #expect(await camera.writes(to: Fujifilm.legacyToken) == [Data([0xAA, 0xBB, 0xCC, 0xDD]),
                                                                  Data([0xAA, 0xBB, 0xCC, 0xDD])])
        #expect(await camera.isSubscribed(Fujifilm.legacyIndication))
    }

    @Test("A reconnect without a stored token or serial asks to pair again")
    func missingIdentity() async throws {
        let driver = FujifilmDriver(transport: SimulatedPeripheral.fujifilm())
        await #expect(throws: CameraError.pairAgain) {
            try await driver.reconnect(identity: .bondOnly, client: .generate())
        }
    }

    @Test("Each shutter value goes out as the two writes 01 00 then the parameter")
    func twoWrites() async throws {
        let camera = SimulatedPeripheral.fujifilm()
        let driver = FujifilmDriver(transport: camera)
        try await driver.reconnect(identity: CameraIdentity(values: ["serial": Data([1, 2, 3, 4, 5])]),
                                   client: .generate())
        _ = try await driver.press(.focus)
        _ = try await driver.press(.shutter)
        try await driver.release(.shutter)
        #expect(await camera.writes(to: Fujifilm.shutter).map(\.hexString)
                == ["01 00", "03 00", "01 00", "02 00", "01 00", "00 00"])
        #expect(try await driver.press(.movie) == .unsupported)
    }

    @Test("Geotag is pull: a request becomes an event, and an answer that is not newer is skipped")
    func pull() async throws {
        let camera = SimulatedPeripheral.fujifilm()
        let driver = FujifilmDriver(transport: camera)
        try await driver.reconnect(identity: CameraIdentity(values: ["serial": Data([1, 2, 3, 4, 5])]),
                                   client: .generate())
        #expect(try await driver.startLocationLink() == .pull)

        let events = driver.events()
        await camera.notify(Fujifilm.locationRequest, on: Fujifilm.geotagRequest)
        var iterator = events.makeAsyncIterator()
        #expect(await iterator.next() == .locationRequested)

        try await driver.updateLocation(tokyoFix, time: goldenTime, zone: .current)
        try await driver.updateLocation(tokyoFix, time: goldenTime.addingTimeInterval(0.5), zone: .current)
        try await driver.updateLocation(tokyoFix, time: goldenTime.addingTimeInterval(10), zone: .current)
        let packets = await camera.writes(to: Fujifilm.geotagPacket)
        #expect(packets.count == 2)
        #expect(packets.allSatisfy { $0.count == 23 })
    }

    @Test("A geotag-only session needs no shutter service")
    func geotagOnly() async throws {
        let camera = SimulatedPeripheral(services: [
            .simulated(Fujifilm.securePairingService, [Fujifilm.secureStatus: [.read, .write],
                                                       Fujifilm.secureName: [.write]]),
            .simulated(Fujifilm.stateService, [Fujifilm.dateSyncState: [.notify], Fujifilm.geotagRequest: [.notify]]),
            .simulated(Fujifilm.geotagService, [Fujifilm.geotagPacket: [.write]]),
        ], values: [Fujifilm.secureStatus: SimulatedPeripheral.fujifilmStatus])
        let driver = FujifilmDriver(transport: camera)
        await driver.setFeatures(remote: false, geotag: true)
        try await driver.reconnect(identity: CameraIdentity(values: ["serial": Data([1, 2, 3, 4, 5])]),
                                   client: .generate())
        await driver.setFeatures(remote: true, geotag: true)
        await #expect(throws: CameraError.missingCharacteristic(Fujifilm.shutter)) {
            try await driver.reconnect(identity: CameraIdentity(values: ["serial": Data([1, 2, 3, 4, 5])]),
                                       client: .generate())
        }
    }
}
