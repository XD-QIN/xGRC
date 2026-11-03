import BLEKit
@testable import CameraKit
import Foundation
import Testing

@Suite("GoPro")
struct GoProTests {
    private let advertisement = Advertisement(peripheralID: UUID(), localName: "GoPro 1234", rssi: -50,
                                              manufacturerData: nil, serviceUUIDs: [UUID.bluetooth(0xFEA6)],
                                              isConnectable: true)

    @Test("Matched by the FEA6 service; the name alone is not enough")
    func matching() throws {
        let match = try #require(DriverRegistry.standard.match(advertisement))
        #expect(match.driverID == GoProDriver.descriptor.id)
        #expect(match.displayName == "GoPro 1234")
        let nameOnly = Advertisement(peripheralID: UUID(), localName: "GoPro 1234", rssi: -50, manufacturerData: nil,
                                     serviceUUIDs: [], isConnectable: true)
        #expect(DriverRegistry.standard.match(nameOnly) == nil)
    }

    @Test("Messages use the general header: length, command ID, parameter length, parameter")
    func messages() {
        #expect(GoPro.controlService.uuidString == "0000FEA6-0000-1000-8000-00805F9B34FB")
        #expect(GoPro.command.characteristic.uuidString == "B5F90072-AA8D-11E3-9046-0002A5D5C51B")
        #expect(GoPro.shutterOn.hexString == "03 01 01 01")
        #expect(GoPro.shutterOff.hexString == "03 01 01 00")
        #expect(GoPro.thirdPartyClientInfo.hexString == "01 50")
        #expect(GoPro.loadPresetGroup(GoPro.PresetGroup.photo).hexString == "04 3e 02 03 e9")
        #expect(GoPro.keepAlive.hexString == "03 5b 01 42")
    }

    @Test("Responses are reassembled across continuation packets and every header size")
    func accumulator() {
        var acc = GoPro.Accumulator()
        #expect(acc.add(Data([0x02, 0x01, 0x00])) == [0x01, 0x00])
        // Extended 13-bit header: 0x20 | high bits, then low byte; 21 bytes over two packets.
        let payload = [UInt8](0..<21)
        #expect(acc.add(Data([0x20, 0x15] + payload.prefix(18))) == nil)
        #expect(acc.add(Data([0x80] + payload.suffix(3))) == payload)
        // Extended 16-bit header.
        #expect(acc.add(Data([0x40, 0x00, 0x02, 0xAA, 0xBB])) == [0xAA, 0xBB])
        // A stray continuation with nothing pending is ignored.
        #expect(acc.add(Data([0x80, 0x01])) == nil)
    }

    @Test("Every connect: subscribe, third-party client info, then the Photo preset group (remote only)")
    func connect() async throws {
        let camera = SimulatedPeripheral.gopro()
        let driver = GoProDriver(transport: camera, keepAliveEvery: nil)
        #expect(try await driver.pair(advertisement, client: .generate()) { _ in } == .bondOnly)
        #expect(await camera.isSubscribed(GoPro.commandResponse))
        #expect(await camera.writes(to: GoPro.command) == [GoPro.thirdPartyClientInfo,
                                                           GoPro.loadPresetGroup(GoPro.PresetGroup.photo)])

        let geotagOnly = SimulatedPeripheral.gopro()
        let other = GoProDriver(transport: geotagOnly, keepAliveEvery: nil)
        await other.setFeatures(remote: false, geotag: true)
        try await other.reconnect(identity: .bondOnly, client: .generate())
        #expect(await geotagOnly.writes(to: GoPro.command) == [GoPro.thirdPartyClientInfo])
    }

    @Test("A shot is Set Shutter on; a success response confirms it, an error does not")
    func shutterAck() async throws {
        let script = GoProDriver.script
        #expect(!script.focusSupported)
        #expect(ShotScript.confirmsShutter(script.shootWithoutFocus))
        #expect(script.releaseAll.isEmpty)

        let camera = SimulatedPeripheral.gopro()
        let driver = GoProDriver(transport: camera, keepAliveEvery: nil)
        try await driver.reconnect(identity: .bondOnly, client: .generate())
        var events = driver.events().makeAsyncIterator()
        #expect(try await driver.press(.shutter) == .sent)
        #expect(await camera.writes(to: GoPro.command).last == GoPro.shutterOn)
        var event = await events.next()
        while case .unknown? = event { event = await events.next() }
        #expect(event == .shutterActive)
        #expect(try await driver.press(.focus) == .unsupported)

        let busy = SimulatedPeripheral.gopro(shutterStatus: 0x01)
        let refused = GoProDriver(transport: busy, keepAliveEvery: nil)
        try await refused.reconnect(identity: .bondOnly, client: .generate())
        var refusedEvents = refused.events().makeAsyncIterator()
        _ = try await refused.press(.shutter)
        // Skip the late answers to the connect's own commands (3E, 50).
        let shutterError = CameraEvent.unknown(characteristic: GoPro.commandResponse, value: Data([0x01, 0x01]))
        var seen: [CameraEvent] = []
        while let next = await refusedEvents.next() {
            seen.append(next)
            if next == shutterError || next == .shutterActive { break }
        }
        #expect(seen.last == shutterError)
        #expect(!seen.contains(.shutterActive))
    }

    @Test("The keep-alive goes to the settings characteristic while connected, and stops on disconnect")
    func keepAlive() async throws {
        let camera = SimulatedPeripheral.gopro()
        let driver = GoProDriver(transport: camera, keepAliveEvery: .milliseconds(20))
        try await driver.reconnect(identity: .bondOnly, client: .generate())
        try await Task.sleep(for: .milliseconds(150))
        #expect(await camera.writes(to: GoPro.settings).contains(GoPro.keepAlive))
        await driver.disconnect()
        let count = await camera.writes(to: GoPro.settings).count
        try await Task.sleep(for: .milliseconds(100))
        #expect(await camera.writes(to: GoPro.settings).count == count)
    }

    @Test("No location link")
    func noLocation() async throws {
        let driver = GoProDriver(transport: SimulatedPeripheral.gopro(), keepAliveEvery: nil)
        await #expect(throws: CameraError.unsupported) { try await driver.startLocationLink() }
    }
}
