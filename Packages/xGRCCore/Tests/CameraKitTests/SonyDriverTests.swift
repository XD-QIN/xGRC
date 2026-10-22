import BLEKit
@testable import CameraKit
import Foundation
import Testing

@Suite("Sony protocol")
struct SonyProtocolTests {
    /// A Sony advertisement with the given mode-flags byte (offset 9).
    private func advertisement(flags: UInt8) -> Data {
        Data([0x2D, 0x01, 0x03, 0x00, 0x65, 0x00, 0x05, 0x48, 0x22, flags, 0x00, 0x21, 0x00])
    }

    @Test("Base UUIDs expand 16-bit characteristics")
    func baseUUID() {
        #expect(UUID.bluetooth(0xFF01).uuidString == "0000FF01-0000-1000-8000-00805F9B34FB")
        #expect(Sony.ff01.characteristic.bluetoothDescription == "FF01")
        #expect(Sony.remoteService.uuidString == "8000FF00-FF00-FFFF-FFFF-FFFFFFFFFFFF")
    }

    @Test("freemote: 22 EF 00 is open for pairing, 22 AF 00 is not")
    func pairingFlags() throws {
        let open = try #require(Sony.AdvertisementInfo(manufacturerData: advertisement(flags: 0xEF)))
        #expect(open.isPairable)
        let closed = try #require(Sony.AdvertisementInfo(manufacturerData: advertisement(flags: 0xAF)))
        #expect(!closed.isPairable)
        #expect(closed.pairingSupported)
    }

    @Test("The low flag bits never decide pairability")
    func lowBitsIgnored() throws {
        let a = try #require(Sony.AdvertisementInfo(manufacturerData: advertisement(flags: 0xC0)))
        let b = try #require(Sony.AdvertisementInfo(manufacturerData: advertisement(flags: 0xC6)))
        #expect(a.isPairable && b.isPairable)
    }

    @Test("Location bits and model code are decoded")
    func locationBits() throws {
        let info = try #require(Sony.AdvertisementInfo(manufacturerData: advertisement(flags: 0xB0)))
        #expect(info.locationSupported)
        #expect(info.locationEnabled)
        #expect(info.modelCode == "0548")
        #expect(info.protocolVersion == 0x65)
    }

    @Test("Other manufacturers and other Sony devices are not matched")
    func rejectsOthers() {
        #expect(Sony.AdvertisementInfo(manufacturerData: Data([0x4C, 0x00, 0x03, 0x00, 0x65, 0, 0, 0, 0x22, 0xF0])) == nil)
        // Device type other than camera (0x0003).
        #expect(Sony.AdvertisementInfo(manufacturerData: Data([0x2D, 0x01, 0x01, 0x00, 0x65, 0, 0, 0, 0x22, 0xF0])) == nil)
        #expect(Sony.AdvertisementInfo(manufacturerData: Data([0x2D, 0x01, 0x03])) == nil)
    }

    @Test("FF02 notifications decode to camera events")
    func statusDecoding() {
        #expect(Sony.decode(status: Data([0x02, 0x3F, 0x20])) == .focusAcquired)
        #expect(Sony.decode(status: Data([0x02, 0x3F, 0x00])) == .focusLost)
        #expect(Sony.decode(status: Data([0x02, 0xA0, 0x20])) == .shutterActive)
        #expect(Sony.decode(status: Data([0x02, 0xA0, 0x00])) == .shutterReady)
        #expect(Sony.decode(status: Data([0x02, 0xD5, 0x20])) == .recording(true))
        #expect(Sony.decode(status: Data([0x02, 0x99, 0x01])) == .unknown(characteristic: Sony.ff02, value: Data([0x02, 0x99, 0x01])))
        #expect(Sony.decode(status: Data([0x02, 0x3F])) == .unknown(characteristic: Sony.ff02, value: Data([0x02, 0x3F])))
    }

    @Test("FF02 decodes by code and state bit 0x20, like alpharemote")
    func statusDecodingByBit() {
        #expect(Sony.decode(status: Data([0x02, 0xA0, 0x60])) == .shutterActive)
        #expect(Sony.decode(status: Data([0x02, 0xA0, 0x40])) == .shutterReady)
        #expect(Sony.decode(status: Data([0x02, 0x3F, 0x20, 0x00])) == .focusAcquired)
        #expect(Sony.decode(status: Data([0x02, 0xD5, 0x00])) == .recording(false))
    }

    @Test("Bulb toggles: press and release opens, a second press and release closes")
    func bulbToggles() {
        let script = SonyDriver.script
        func bytes(_ steps: [ShotStep]) -> [String] {
            steps.compactMap { step -> String? in
                if case .write(let write) = step { return write.data.hexString }
                return nil
            }
        }
        #expect(script.unlatchToggles)
        #expect(bytes(script.latch) == ["01 09", "01 08", "01 06"])
        #expect(ShotScript.confirmsShutter(script.latch), "the open press is held until the shutter ack")
        #expect(bytes(script.unlatch) == ["01 07", "01 09", "01 08", "01 06"])
        let closeFires = script.unlatch.contains {
            if case .write(let write) = $0 { return write.firesShutter }
            return false
        }
        #expect(!closeFires, "the closing press is not counted as a shot")
    }

    @Test("Shot script order is half-down, full-down, ack, full-up, half-up")
    func scriptOrder() {
        let script = SonyDriver.script
        let single = script.focusPress + script.shootFromFocus + script.focusRelease
        let bytes = single.compactMap { step -> String? in
            if case .write(let write) = step { return write.data.hexString }
            return nil
        }
        #expect(bytes == ["01 07", "01 09", "01 08", "01 06"])
        #expect(ShotScript.confirmsShutter(script.shootFromFocus))
        #expect(SonyDriver.descriptor.capabilities.contains([.ackFocus, .ackShutter, .halfPress]))
    }
}

@Suite("Sony driver on a fake camera")
struct SonyDriverTests {
    private func pairingAdvertisement(pairable: Bool) -> Advertisement {
        var data = FakeCamera.advertisementData
        data[9] = pairable ? 0xF0 : 0xB0
        return Advertisement(peripheralID: UUID(), localName: "ILCE-7M4", rssi: -50, manufacturerData: data,
                             serviceUUIDs: [], isConnectable: true)
    }

    @Test("First pairing in pairing mode writes EE01 once")
    func pairWritesRegistration() async throws {
        let camera = FakeCamera(behavior: .instant)
        let driver = SonyDriver(transport: camera)
        let steps = StepRecorder()
        let identity = try await driver.pair(pairingAdvertisement(pairable: true), client: .generate()) {
            steps.append($0)
        }
        #expect(identity == .bondOnly)
        let ee01 = await camera.received.filter { $0.characteristic == Sony.ee01 }
        #expect(ee01.map(\.data) == [Sony.registration])
        #expect(steps.values == [.bonding, .registering, .done])
    }

    @Test("EE01 is never written outside pairing mode or on reconnect")
    func noRegistrationOutsidePairing() async throws {
        let camera = FakeCamera(behavior: .instant)
        let driver = SonyDriver(transport: camera)
        _ = try await driver.pair(pairingAdvertisement(pairable: false), client: .generate()) { _ in }
        try await driver.reconnect(identity: .bondOnly, client: .generate())
        #expect(await camera.received.isEmpty)
    }

    @Test("ATT 0x90 on FF01 means Bluetooth Rmt Ctrl is off")
    func remoteControlOff() async throws {
        let camera = FakeCamera(behavior: FakeCamera.Behavior(remoteControlOff: true))
        let driver = SonyDriver(transport: camera)
        try await driver.reconnect(identity: .bondOnly, client: .generate())
        await #expect(throws: CameraError.remoteControlOff) {
            _ = try await driver.press(.shutter)
        }
    }

    @Test("Events come from FF02")
    func events() async throws {
        let camera = FakeCamera(behavior: .instant)
        let driver = SonyDriver(transport: camera)
        try await driver.reconnect(identity: .bondOnly, client: .generate())
        let stream = driver.events()
        _ = try await driver.press(.focus)
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == .focusAcquired)
    }

    @Test("Disconnect releases every button before dropping the link")
    func disconnectReleases() async throws {
        let camera = FakeCamera(behavior: .instant)
        let driver = SonyDriver(transport: camera)
        try await driver.reconnect(identity: .bondOnly, client: .generate())
        await driver.disconnect()
        #expect(await camera.commands().map(\.hexString) == ["01 08", "01 06"])
        #expect(await camera.isLinkUp == false)
    }
}

/// Collects values from a `@Sendable` callback.
final class StepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [PairingStep] = []

    func append(_ step: PairingStep) {
        lock.lock()
        stored.append(step)
        lock.unlock()
    }

    var values: [PairingStep] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}

@Suite("Transcript")
struct TranscriptTests {
    @Test("Recording transport logs writes and notifications as JSON Lines")
    func recording() async throws {
        let logger = TranscriptLogger(header: TranscriptHeader(startedAt: Date(timeIntervalSince1970: 0), os: "test",
                                                               device: "test", appVersion: "0"))
        let camera = FakeCamera(behavior: .instant)
        let driver = SonyDriver(transport: RecordingTransport(camera, logger: logger))
        try await driver.reconnect(identity: .bondOnly, client: .generate())
        _ = try await driver.press(.focus)
        try await Task.sleep(for: .milliseconds(50))

        let entries = await logger.snapshot()
        #expect(entries.contains { $0.op == .write && $0.char == "FF01" && $0.bytes == "01 07" })
        #expect(entries.contains { $0.op == .notify && $0.char == "FF02" && $0.bytes == "02 3f 20" })
        #expect(entries.contains { $0.op == .subscribe && $0.char == "FF02" })

        let lines = String(decoding: try await logger.exportJSONLines(), as: UTF8.self)
            .split(separator: "\n")
        #expect(lines.first?.contains("\"schema\":1") == true)
        #expect(lines.count == entries.count + 1)
    }

    @Test("A full transcript keeps the newest entries, oldest first")
    func ring() async {
        let logger = TranscriptLogger(header: TranscriptHeader(startedAt: Date(timeIntervalSince1970: 0), os: "test",
                                                               device: "test", appVersion: "0"),
                                      capacity: 3)
        for index in 0..<5 { await logger.log(.note, note: "\(index)") }
        #expect(await logger.snapshot().compactMap(\.note) == ["2", "3", "4"])
        await logger.clear()
        await logger.log(.note, note: "after")
        #expect(await logger.snapshot().compactMap(\.note) == ["after"])
    }
}
