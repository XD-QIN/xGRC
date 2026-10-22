import BLEKit
@testable import CameraKit
import Foundation
import Testing

@Suite("Sony location link")
struct SonyLocationTests {
    /// 2026-10-15 13:05:09 UTC.
    let time = Date(timeIntervalSince1970: 1_792_069_509)
    let tokyo = GeoFix(latitude: 35.658581, longitude: 139.745433, altitude: 42, horizontalAccuracy: 5,
                       timestamp: Date(timeIntervalSince1970: 1_792_069_505))

    private func bytes(_ data: Data, _ range: Range<Int>) -> String {
        Data(data[range]).hexString
    }

    @Test("DD21 picks the packet: the α7C II's value takes the 95-byte form")
    func profile() {
        #expect(Sony.LocationProfile(features: Data([0x06, 0x10, 0x00, 0x9C, 0x02, 0x00, 0x00])) == .withTimeZone)
        #expect(Sony.LocationProfile(features: Data([0x06, 0x10, 0x00, 0x9C, 0x00, 0x00])) == .basic)
        // Any other length is an unknown profile.
        #expect(Sony.LocationProfile(features: Data([0x05, 0x10, 0x00, 0x9C, 0x02])) == .basic)
        #expect(Sony.LocationProfile(features: Data()) == .basic)
    }

    @Test("95-byte packet layout, with standard offset and DST in effect (Berlin, summer time)")
    func packet95() throws {
        let zone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let p = Sony.locationPacket(tokyo, time: time, zone: zone, profile: .withTimeZone)
        #expect(p.count == 95)
        #expect(bytes(p, 0..<2) == "00 5d")
        #expect(bytes(p, 2..<11) == "08 02 fc 03 00 00 10 10 10")
        #expect(bytes(p, 11..<15) == "15 41 11 52")
        #expect(bytes(p, 15..<19) == "53 4b 75 fa")
        #expect(bytes(p, 19..<26) == "07 ea 0a 0f 0d 05 09")
        #expect(p[26..<91].allSatisfy { $0 == 0 })
        // Standard offset excludes DST: +60 min, DST +60 min.
        #expect(bytes(p, 91..<93) == "00 3c")
        #expect(bytes(p, 93..<95) == "00 3c")
    }

    @Test("Negative coordinates and offsets are two's complement")
    func negative() throws {
        let fix = GeoFix(latitude: -33.8688, longitude: -70.5, horizontalAccuracy: 5, timestamp: time)
        let zone = try #require(TimeZone(identifier: "America/New_York"))
        let p = Sony.locationPacket(fix, time: time, zone: zone, profile: .withTimeZone)
        #expect(bytes(p, 11..<15) == "eb d0 08 00")
        #expect(bytes(p, 15..<19) == "d5 fa 8d c0")
        // New York in October: standard −300 min, DST +60.
        #expect(bytes(p, 91..<93) == "fe d4")
        #expect(bytes(p, 93..<95) == "00 3c")
    }

    @Test("91-byte packet has no time-zone fields")
    func packet91() {
        let p = Sony.locationPacket(tokyo, time: time, zone: .current, profile: .basic)
        #expect(p.count == 91)
        #expect(bytes(p, 0..<2) == "00 59")
        #expect(p[5] == 0x00)
        #expect(bytes(p, 19..<26) == "07 ea 0a 0f 0d 05 09")
    }

    @Test("Start takes the lock, enables, and pushes the 95-byte packet")
    func startAndPush() async throws {
        let camera = FakeCamera(behavior: .instant)
        let driver = SonyDriver(transport: camera)
        try await driver.reconnect(identity: .bondOnly, client: .generate())
        #expect(try await driver.startLocationLink() == .push)
        #expect(await camera.locationLock == 1)
        #expect(await camera.locationEnable == 1)
        let writes = await camera.received.map(\.characteristic)
        #expect(writes.firstIndex(of: Sony.dd30)! < writes.firstIndex(of: Sony.dd31)!)

        try await driver.updateLocation(tokyo, time: time, zone: .current)
        #expect(await camera.locationPackets().map(\.count) == [95])

        await driver.stopLocationLink()
        #expect(await camera.locationLock == 0)
        #expect(await camera.locationEnable == 0)
        let order = await camera.received.suffix(2).map(\.characteristic)
        #expect(order == [Sony.dd31, Sony.dd30])
    }

    @Test("Older firmware without DD30/DD31 takes DD11 directly")
    func olderFirmware() async throws {
        let camera = FakeCamera(behavior: FakeCamera.Behavior(focusAckDelay: .zero, shutterAckDelay: .zero,
                                                              locationFeatures: Data([0x05, 0x10, 0x00, 0x9C, 0x00]),
                                                              hasLocationLock: false))
        let driver = SonyDriver(transport: camera)
        try await driver.reconnect(identity: .bondOnly, client: .generate())
        _ = try await driver.startLocationLink()
        try await driver.updateLocation(tokyo, time: time, zone: .current)
        #expect(await camera.locationPackets().map(\.count) == [91])
        #expect(await camera.received.contains { $0.characteristic == Sony.dd30 } == false)
    }

    @Test("0x9D means the camera's Location Info. Link is off; 0x9F means another device holds it")
    func errors() async throws {
        let off = FakeCamera(behavior: FakeCamera.Behavior(locationLinkOff: true))
        let offDriver = SonyDriver(transport: off)
        try await offDriver.reconnect(identity: .bondOnly, client: .generate())
        await #expect(throws: CameraError.locationLinkOff) { try await offDriver.startLocationLink() }

        let held = FakeCamera(behavior: FakeCamera.Behavior(locationLockedElsewhere: true))
        let heldDriver = SonyDriver(transport: held)
        try await heldDriver.reconnect(identity: .bondOnly, client: .generate())
        await #expect(throws: CameraError.busy) { try await heldDriver.startLocationLink() }
    }

    @Test("A reconnect re-enables an active location link")
    func reconnectReenables() async throws {
        let camera = FakeCamera(behavior: .instant)
        let driver = SonyDriver(transport: camera)
        try await driver.reconnect(identity: .bondOnly, client: .generate())
        _ = try await driver.startLocationLink()
        await camera.dropLink()
        await camera.restoreLink()
        await camera.clearReceived()
        try await driver.reconnect(identity: .bondOnly, client: .generate())
        // The camera still had the values set, so nothing needed rewriting;
        // after a camera power cycle it would.
        try await driver.updateLocation(tokyo, time: time, zone: .current)
        #expect(await camera.locationPackets().count == 1)
    }

    @Test("Disconnect releases the location lock")
    func disconnectReleases() async throws {
        let camera = FakeCamera(behavior: .instant)
        let driver = SonyDriver(transport: camera)
        try await driver.reconnect(identity: .bondOnly, client: .generate())
        _ = try await driver.startLocationLink()
        await driver.disconnect()
        #expect(await camera.locationLock == 0)
        #expect(await camera.locationEnable == 0)
    }

    @Test("DD01 advisories decode to location on/off")
    func advisory() {
        #expect(Sony.decode(locationAdvisory: Data([0x03, 0x01, 0x02, 0x01])) == .locationEnabled(true))
        #expect(Sony.decode(locationAdvisory: Data([0x03, 0x01, 0x02, 0x00])) == .locationEnabled(false))
    }
}
