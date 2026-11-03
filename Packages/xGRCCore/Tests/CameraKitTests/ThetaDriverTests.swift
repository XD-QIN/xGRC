import BLEKit
@testable import CameraKit
import Foundation
import Testing

@Suite("Ricoh THETA")
struct ThetaTests {
    private func advertisement(_ name: String?, services: [UUID] = []) -> Advertisement {
        Advertisement(peripheralID: UUID(), localName: name, rssi: -50, manufacturerData: nil,
                      serviceUUIDs: services, isConnectable: true)
    }

    @Test("Matched by THETA's name pattern or its control service, before the Ricoh GR")
    func matching() throws {
        let x = try #require(DriverRegistry.standard.match(advertisement("14001234")))
        #expect(x.driverID == ThetaDriver.descriptor.id)
        #expect(x.displayName == "THETA 14001234")
        #expect(DriverRegistry.standard.match(advertisement("AB12345678"))?.driverID == ThetaDriver.descriptor.id)
        // A THETA that also advertises the Camera Information service the GR shares.
        #expect(DriverRegistry.standard.match(advertisement("14001234", services: [Ricoh.infoService]))?.driverID
                == ThetaDriver.descriptor.id)
        #expect(ThetaDriver.matches(advertisement(nil, services: [Theta.controlService]))?.displayName
                == "RICOH THETA")
        #expect(DriverRegistry.standard.match(advertisement("RICOH GR IIIx"))?.driverID == RicohDriver.descriptor.id)
        for name in ["1400123", "140012345", "abc12345678", "THETA"] {
            #expect(ThetaDriver.matches(advertisement(name)) == nil, "\(name)")
        }
    }

    @Test("Connect puts the camera in still mode (remote only); a shot is one takePicture command")
    func shot() async throws {
        let camera = SimulatedPeripheral.theta()
        let driver = ThetaDriver(transport: camera)
        #expect(try await driver.pair(advertisement("14001234"), client: .generate()) { _ in } == .bondOnly)
        #expect(await camera.isSubscribed(Theta.notifyState))
        #expect(await camera.writes(to: Theta.setOptions) == [Data(#"{"captureMode":"image"}"#.utf8)])
        #expect(try await driver.press(.shutter) == .sent)
        #expect(await camera.writes(to: Theta.requestShutter) == [Data(#"{"name":"camera.takePicture"}"#.utf8)])
        #expect(try await driver.press(.focus) == .unsupported)

        let script = ThetaDriver.script
        #expect(!ShotScript.confirmsShutter(script.shootWithoutFocus))
        #expect(script.shootWithoutFocus.count == 1)
        #expect(script.releaseAll.isEmpty)

        let geotagOnly = SimulatedPeripheral.theta()
        let other = ThetaDriver(transport: geotagOnly)
        await other.setFeatures(remote: false, geotag: true)
        try await other.reconnect(identity: .bondOnly, client: .generate())
        #expect(await geotagOnly.writes(to: Theta.setOptions).isEmpty)
    }

    @Test("Z1 and V need a Wi-Fi registration first, so they are refused")
    func needsRegistration() async throws {
        for model in ["RICOH THETA Z1", "RICOH THETA V"] {
            let driver = ThetaDriver(transport: SimulatedPeripheral.theta(model: model))
            await #expect(throws: CameraError.unsupported) {
                try await driver.reconnect(identity: .bondOnly, client: .generate())
            }
        }
        #expect(!Theta.needsWiFiRegistration(model: "RICOH THETA X"))
        #expect(!Theta.needsWiFiRegistration(model: "RICOH360 THETA A1"))
    }
}
