import BLEKit
@testable import CameraKit
import Foundation
import Testing

@Suite("Panasonic LUMIX")
struct LumixTests {
    private let advertisement = Advertisement(peripheralID: UUID(), localName: "S5-30E2BA", rssi: -50,
                                              manufacturerData: Data([0x3A, 0x00, 0x01, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE]),
                                              serviceUUIDs: [Lumix.sessionService], isConnectable: true)

    @Test("Matched by the session or the location service; Panasonic data alone is not enough")
    func matching() throws {
        let match = try #require(DriverRegistry.standard.match(advertisement))
        #expect(match.driverID == LumixDriver.descriptor.id)
        #expect(match.displayName == "S5-30E2BA")
        #expect(match.details["flags"] == "01")
        let byLocation = Advertisement(peripheralID: UUID(), localName: nil, rssi: -50, manufacturerData: nil,
                                       serviceUUIDs: [Lumix.locationService], isConnectable: true)
        #expect(LumixDriver.matches(byLocation)?.displayName == "LUMIX")
        let otherPanasonic = Advertisement(peripheralID: UUID(), localName: "Panasonic TV", rssi: -50,
                                           manufacturerData: Data([0x3A, 0x00, 0x01]), serviceUUIDs: [],
                                           isConnectable: true)
        #expect(DriverRegistry.standard.match(otherPanasonic) == nil)
    }

    @Test("GPS packet matches a LUMIX app write (G9II trace): GPS-epoch time, ×10⁷ degrees, metres, 'A'")
    func gpsPacketFromTrace() {
        let fix = GeoFix(latitude: 48.3513039, longitude: 14.4044957, altitude: 409, horizontalAccuracy: 5,
                         timestamp: Date(timeIntervalSince1970: 1_734_077_603))
        #expect(Lumix.gpsPacket(fix, time: fix.timestamp).hexString
                == "23 af 86 54 cf d2 d1 1c 9d f3 95 08 99 01 41 00")
    }

    @Test("GPS packet golden vectors; below sea level is sent as 0 m")
    func gpsPacket() {
        #expect(Lumix.gpsPacket(tokyoFix, time: goldenTime).hexString
                == "f0 8a fb 57 52 11 41 15 fa 75 4b 53 2a 00 41 00")
        let sydney = GeoFix(latitude: -33.856784, longitude: 151.215297, altitude: -3.5, horizontalAccuracy: 5,
                            timestamp: goldenTime)
        #expect(Lumix.gpsPacket(sydney, time: goldenTime).hexString
                == "f0 8a fb 57 60 dd d1 eb 8a 9f 21 5a 00 00 41 00")
    }

    @Test("Clock packet matches the S5 write lux-lat-long-log replays; other zones follow the same layout")
    func clockPacket() throws {
        let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
        #expect(Lumix.clockPacket(Date(timeIntervalSince1970: 1_782_483_944), zone: berlin).hexString
                == "ea 07 06 1a 0e 19 2c 3c 00 01")
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        #expect(Lumix.clockPacket(goldenTime, zone: tokyo).hexString == "ea 07 0a 0f 0c 22 38 1c 02 00")
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        #expect(Lumix.clockPacket(goldenTime, zone: newYork).hexString == "ea 07 0a 0f 0c 22 38 d4 fe 01")
    }

    @Test("Every connect: MEI0, our name, then the clock once both ready notifications arrive")
    func handshake() async throws {
        let camera = SimulatedPeripheral.lumix()
        let driver = LumixDriver(transport: camera)
        let client = ClientIdentity.generate()
        #expect(try await driver.pair(advertisement, client: client) { _ in } == .bondOnly)
        #expect(await camera.isSubscribed(Lumix.locationReady))
        #expect(await camera.isSubscribed(Lumix.clockReady))
        var order = await camera.writes.map(\.characteristic)
        #expect(order == [Lumix.sessionInit, Lumix.deviceName, Lumix.clock])
        #expect(await camera.writes(to: Lumix.sessionInit) == [Lumix.mei0])
        #expect(await camera.writes(to: Lumix.deviceName) == [Data(client.name.utf8)])
        #expect(await camera.writes(to: Lumix.clock).first?.count == 10)

        await camera.clearWrites()
        try await driver.reconnect(identity: .bondOnly, client: client)
        order = await camera.writes.map(\.characteristic)
        #expect(order == [Lumix.sessionInit, Lumix.deviceName, Lumix.clock])
    }

    @Test("A remote-only session leaves the camera clock alone")
    func remoteOnlyKeepsClock() async throws {
        let camera = SimulatedPeripheral.lumix()
        let driver = LumixDriver(transport: camera)
        await driver.setFeatures(remote: true, geotag: false)
        try await driver.reconnect(identity: .bondOnly, client: .generate())
        #expect(await camera.writes(to: Lumix.clock).isEmpty)
    }

    @Test("Without ready notifications the connect goes on after the wait")
    func noReady() async throws {
        let camera = SimulatedPeripheral.lumix(sendsReady: false)
        let driver = LumixDriver(transport: camera, readyWindow: .milliseconds(200))
        try await driver.reconnect(identity: .bondOnly, client: .generate())
        #expect(await camera.writes(to: Lumix.clock).count == 1)
    }

    @Test("Focus 01/02 and shutter 04/05 are separate buttons; release all lets go of both")
    func buttons() async throws {
        let script = LumixDriver.script
        func bytes(_ steps: [ShotStep]) -> [String] {
            steps.compactMap { if case .write(let w) = $0 { return w.data.hexString } else { return nil } }
        }
        #expect(bytes(script.focusPress + script.shootFromFocus + script.focusRelease) == ["01", "04", "05", "02"])
        #expect(bytes(script.latch) == ["04"])
        #expect(bytes(script.unlatch) == ["05", "02"])
        #expect(bytes(script.releaseAll) == ["05", "02"])
        #expect(!script.acknowledgesFocus)

        let camera = SimulatedPeripheral.lumix()
        let driver = LumixDriver(transport: camera)
        try await driver.reconnect(identity: .bondOnly, client: .generate())
        await camera.clearWrites()
        #expect(try await driver.press(.focus) == .sent)
        #expect(try await driver.press(.shutter) == .sent)
        try await driver.release(.shutter)
        try await driver.release(.focus)
        #expect(await camera.writes(to: Lumix.control).map(\.hexString) == ["01", "04", "05", "02"])
        #expect(try await driver.press(.movie) == .unsupported)
        await driver.disconnect()
        #expect(await camera.writes(to: Lumix.control).suffix(2).map(\.hexString) == ["05", "02"])
    }

    @Test("Locations are pushed, stamped with the fix time")
    func location() async throws {
        let camera = SimulatedPeripheral.lumix()
        let driver = LumixDriver(transport: camera)
        try await driver.reconnect(identity: .bondOnly, client: .generate())
        await #expect(throws: CameraError.unsupported) {
            try await driver.updateLocation(tokyoFix, time: goldenTime, zone: .current)
        }
        #expect(try await driver.startLocationLink() == .push)
        try await driver.updateLocation(tokyoFix, time: goldenTime, zone: .current)
        #expect(await camera.writes(to: Lumix.location) == [Lumix.gpsPacket(tokyoFix, time: goldenTime)])
        #expect(driver.geotagRules.stampsSendTime == false)
    }
}
