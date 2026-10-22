import BLEKit
@testable import CameraKit
import Foundation
import Testing

@Suite("Canon protocol")
struct CanonProtocolTests {
    @Test("UUIDs share the base xxxxxxxx-0000-1000-0000-D8492FFFA821")
    func base() {
        #expect(Canon.remoteService.uuidString == "00050000-0000-1000-0000-D8492FFFA821")
        #expect(Canon.smartIdentity.characteristic.uuidString == "0001000A-0000-1000-0000-D8492FFFA821")
    }

    @Test("The advertised service picks Remote or Smartphone")
    func matching() throws {
        func advertisement(_ service: UUID) -> Advertisement {
            Advertisement(peripheralID: UUID(), localName: "EOS R6m2", rssi: -50, manufacturerData: nil,
                          serviceUUIDs: [service], isConnectable: true)
        }
        let registry = DriverRegistry.standard
        #expect(registry.match(advertisement(Canon.remoteService))?.driverID == CanonRemoteDriver.descriptor.id)
        #expect(registry.match(advertisement(Canon.smartService))?.driverID == CanonSmartDriver.descriptor.id)
    }

    @Test("Smartphone location packet golden vector (20 bytes, little-endian floats)")
    func locationPacket() {
        let sydney = GeoFix(latitude: -33.856784, longitude: 151.215297, altitude: -3.5, horizontalAccuracy: 5,
                            timestamp: goldenTime)
        #expect(Canon.locationPacket(sydney, time: goldenTime).hexString
                == "04 53 59 6d 07 42 45 1e 37 17 43 2d 00 00 60 40 70 c8 d0 6a")
    }

    @Test("Remote control bytes are mode 0x0C | buttons")
    func controlBytes() {
        let script = CanonRemoteDriver.script
        let bytes = (script.focusPress + script.shootFromFocus + script.focusRelease).compactMap { step -> String? in
            if case .write(let write) = step { return write.data.hexString }
            return nil
        }
        #expect(bytes == ["4c", "8c", "0c", "0c"])
    }
}

@Suite("Canon drivers on simulated bodies")
struct CanonDriverTests {
    private let advertisement = Advertisement(peripheralID: UUID(), localName: "EOS R6m2", rssi: -50,
                                              manufacturerData: nil, serviceUUIDs: [], isConnectable: true)

    @Test("Remote: identifies with 0x03 + name; control writes go without response where that is all it takes")
    func remote() async throws {
        let camera = SimulatedPeripheral.canonRemote()
        let driver = CanonRemoteDriver(transport: camera)
        let client = ClientIdentity.generate()
        _ = try await driver.pair(advertisement, client: client) { _ in }
        #expect(await camera.writes(to: Canon.remoteIdentify) == [Data([0x03]) + Data(client.name.utf8)])

        _ = try await driver.press(.focus)
        _ = try await driver.press(.shutter)
        try await driver.release(.shutter)
        let control = await camera.writes.filter { $0.characteristic == Canon.remoteControl }
        #expect(control.map(\.data.hexString) == ["4c", "8c", "0c"])
        #expect(control.allSatisfy { !$0.withResponse })
    }

    @Test("Smartphone: identifies, waits for Accept, then enables and switches to shoot mode")
    func smartAccepted() async throws {
        let camera = SimulatedPeripheral.canonSmart(answer: .accept)
        let driver = CanonSmartDriver(transport: camera)
        let client = ClientIdentity.generate()
        _ = try await driver.pair(advertisement, client: client) { _ in }

        let name = Data(client.name.utf8)
        #expect(await camera.writes(to: Canon.smartName) == [Data([0x01]) + name])
        let identity = await camera.writes(to: Canon.smartIdentity)
        #expect(identity.count == 4)
        #expect(identity[0].first == 0x03 && identity[0].count == 17)
        #expect(identity[1] == Data([0x04]) + name)
        #expect(identity[2] == Data([0x05, Canon.platformIOS]))
        #expect(identity[3] == Data([0x01]))
        #expect(await camera.writes(to: Canon.mode) == [Data([Canon.shootMode])])
    }

    @Test("Smartphone: Cancel on the camera is a rejected pairing")
    func smartRejected() async throws {
        let driver = CanonSmartDriver(transport: SimulatedPeripheral.canonSmart(answer: .reject))
        await #expect(throws: CameraError.pairingRejected) {
            _ = try await driver.pair(advertisement, client: .generate()) { _ in }
        }
    }

    @Test("Smartphone: the camera's request is answered with enable, then packets go out")
    func smartLocation() async throws {
        let camera = SimulatedPeripheral.canonSmart()
        let driver = CanonSmartDriver(transport: camera)
        try await driver.reconnect(identity: .bondOnly, client: .generate())
        #expect(try await driver.startLocationLink() == .push)
        #expect(await camera.writes(to: Canon.location) == [Data([0x01])])
        try await driver.updateLocation(tokyoFix, time: goldenTime, zone: .current)
        #expect(await camera.writes(to: Canon.location).last?.count == 20)
    }

    @Test("Smartphone: without Select GPS device › Smartphone, pushes report the camera's setting off")
    func smartLocationOff() async throws {
        let driver = CanonSmartDriver(transport: SimulatedPeripheral.canonSmart(gpsFromSmartphone: false),
                                      enableWindow: .milliseconds(50))
        try await driver.reconnect(identity: .bondOnly, client: .generate())
        _ = try await driver.startLocationLink()
        await #expect(throws: CameraError.locationLinkOff) {
            try await driver.updateLocation(tokyoFix, time: goldenTime, zone: .current)
        }
    }

    @Test("Smartphone shutter: 00 01 press, 00 02 release; no half-press")
    func smartShutter() async throws {
        let camera = SimulatedPeripheral.canonSmart()
        let driver = CanonSmartDriver(transport: camera)
        try await driver.reconnect(identity: .bondOnly, client: .generate())
        #expect(try await driver.press(.focus) == .unsupported)
        _ = try await driver.press(.shutter)
        try await driver.release(.shutter)
        #expect(await camera.writes(to: Canon.shutter).map(\.hexString) == ["00 01", "00 02"])
        #expect(!CanonSmartDriver.script.focusSupported)
    }
}
