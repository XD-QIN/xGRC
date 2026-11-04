import BLEKit
import Foundation

/// Simulated bodies for the Phase 5 brands, built on `SimulatedPeripheral`
/// with the GATT layouts from the protocol reference. Each answers
/// the way the real camera is documented to; the device test pass (Phase 6)
/// checks the documentation.
extension SimulatedPeripheral {
    // MARK: Fujifilm

    /// The pairing status a secure body returns before registration (furble: `0x07960000`).
    public static let fujifilmStatus = Data([0x07, 0x96, 0x00, 0x00])

    /// An X-series body, secure or legacy firmware. It asks for a location
    /// only when the test calls `notify(Fujifilm.locationRequest, on: Fujifilm.geotagRequest)`.
    public static func fujifilm(secure: Bool = true) -> SimulatedPeripheral {
        var state: [GATTCharacteristicID: CharacteristicProperties] = [
            Fujifilm.apState: [.indicate], Fujifilm.transferState: [.indicate],
            Fujifilm.dateSyncState: [.notify], Fujifilm.geotagRequest: [.notify],
        ]
        var services: [GATTService] = []
        if secure {
            state[Fujifilm.vitalState] = [.notify]
            services.append(.simulated(Fujifilm.securePairingService, [
                Fujifilm.secureStatus: [.read, .write], Fujifilm.secureName: [.write],
            ]))
            var settings: [GATTCharacteristicID: CharacteristicProperties] = [
                Fujifilm.locationSyncCycle: [.read, .write, .notify],
            ]
            for chr in Fujifilm.settingsNotifications { settings[chr] = [.read, .notify] }
            services.append(.simulated(Fujifilm.settingsService, settings))
        } else {
            state[Fujifilm.legacyIndication] = [.indicate]
            services.append(.simulated(Fujifilm.legacyPairingService, [
                Fujifilm.legacyToken: [.write], Fujifilm.legacyName: [.write],
            ]))
        }
        services += [
            .simulated(Fujifilm.stateService, state),
            .simulated(Fujifilm.geotagService, [Fujifilm.geotagPacket: [.write]]),
            .simulated(Fujifilm.shutterService, [Fujifilm.shutter: [.write]]),
        ]
        return SimulatedPeripheral(services: services, values: secure ? [Fujifilm.secureStatus: fujifilmStatus] : [:])
    }

    // MARK: Canon

    /// A body pairing a wireless remote. Its control characteristic takes
    /// writes without response only, as the protocol reference describes.
    public static func canonRemote() -> SimulatedPeripheral {
        SimulatedPeripheral(services: [
            .simulated(Canon.remoteService, [
                Canon.remoteIdentify: [.write], Canon.remoteControl: [.writeWithoutResponse],
            ]),
        ])
    }

    /// What the user does on the camera's Accept prompt.
    public enum CanonAnswer: Sendable {
        case accept
        case reject
        /// Nobody answers; the camera gives up.
        case none
    }

    /// A body pairing a smartphone. It answers the pairing after our platform
    /// byte, asks for location after the shoot-mode write, and says
    /// "enabled" once we enable, unless its GPS device is not set to Smartphone.
    public static func canonSmart(answer: CanonAnswer = .accept, gpsFromSmartphone: Bool = true) -> SimulatedPeripheral {
        SimulatedPeripheral(services: [
            .simulated(Canon.smartService, [
                Canon.smartName: [.write, .indicate], Canon.smartIdentity: [.write],
            ]),
            .simulated(Canon.shootingService, [
                Canon.mode: [.write], Canon.shutter: [.write], Canon.triggerState: [.notify],
            ]),
            .simulated(Canon.locationService, [
                Canon.location: [.write], Canon.locationIndication: [.indicate],
            ]),
        ], responder: { write, camera in
            switch (write.characteristic, write.data.first) {
            case (Canon.smartIdentity, 0x05?):
                switch answer {
                case .accept: await camera.notify(Data([Canon.pairAccepted]), on: Canon.smartName)
                case .reject: await camera.notify(Data([Canon.pairRejected]), on: Canon.smartName)
                case .none: break
                }
            case (Canon.mode, _) where gpsFromSmartphone:
                await camera.notify(Data([Canon.locationRequest]), on: Canon.locationIndication)
            case (Canon.location, 0x01?) where write.data.count == 1:
                await camera.notify(Data([Canon.locationEnabled]), on: Canon.locationIndication)
            default:
                break
            }
        })
    }

    // MARK: Nikon

    /// The serial a simulated Nikon sends in its stage 4.
    public static let nikonSerial = "30012345"

    /// A body in *Connection to remote*. `acceptsStage1: false` answers with a
    /// stage 2 that is not all zero, as a camera that refuses us would.
    /// `smartDevice: true` is a body set to pair a smart device (SnapBridge).
    public static func nikonRemote(acceptsStage1: Bool = true, smartDevice: Bool = false) -> SimulatedPeripheral {
        let characteristics: [GATTCharacteristicID: CharacteristicProperties] = smartDevice
            ? [Nikon.smartPairing: [.write, .indicate]]
            : [Nikon.remoteIndication: [.indicate], Nikon.remotePairing: [.write, .indicate],
               Nikon.remoteShutter: [.write]]
        return SimulatedPeripheral(services: [.simulated(Nikon.service, characteristics)], responder: { write, camera in
            guard write.characteristic == Nikon.remotePairing else { return }
            switch write.data.first {
            case 0x01?:
                var stage2 = Nikon.stage2
                if !acceptsStage1 { stage2[16] = 0xFF }
                await camera.notify(stage2, on: Nikon.remotePairing)
            case 0x03?:
                let stage4 = Data([0x04] + [UInt8](repeating: 0, count: 8)) + Data(nikonSerial.utf8)
                await camera.notify(stage4, on: Nikon.remotePairing)
            default:
                break
            }
        })
    }

    // MARK: Ricoh

    /// A GR IIIx. `storeLocation` is the camera's *Store Location Info.* switch.
    public static func ricoh(storeLocation: Bool = true) -> SimulatedPeripheral {
        SimulatedPeripheral(services: [
            .simulated(Ricoh.infoService, [Ricoh.modelNumber: [.read]]),
            .simulated(Ricoh.cameraService, [
                Ricoh.power: [.read, .notify], Ricoh.operationMode: [.read, .notify],
                Ricoh.geoTag: [.read, .write, .notify],
            ]),
            .simulated(Ricoh.shootingService, [
                Ricoh.operationRequest: [.write], Ricoh.shootingFlavour: [.read, .write],
                Ricoh.captureStatus: [.notify], Ricoh.afStatus: [.notify],
            ]),
            .simulated(Ricoh.gpsService, [Ricoh.gpsInformation: [.write]]),
        ], values: [
            Ricoh.modelNumber: Data("RICOH GR IIIx".utf8),
            Ricoh.power: Data([0x01]),
            Ricoh.geoTag: Data([storeLocation ? 0x01 : 0x00]),
        ])
    }

    // MARK: Panasonic LUMIX

    /// An S5-style body. After our name it notifies `01` on both ready
    /// characteristics, as lux-lat-long-log saw, unless `sendsReady` is off.
    public static func lumix(sendsReady: Bool = true) -> SimulatedPeripheral {
        SimulatedPeripheral(services: [
            .simulated(Lumix.sessionService, [Lumix.sessionInit: [.write], Lumix.deviceName: [.write]]),
            .simulated(Lumix.controlService, [Lumix.control: [.write]]),
            .simulated(Lumix.locationService, [Lumix.location: [.write], Lumix.locationReady: [.notify]]),
            .simulated(Lumix.clockService, [Lumix.clock: [.write], Lumix.clockReady: [.notify]]),
        ], responder: { write, camera in
            guard sendsReady, write.characteristic == Lumix.deviceName else { return }
            await camera.notify(Data([0x01]), on: Lumix.locationReady)
            await camera.notify(Data([0x01]), on: Lumix.clockReady)
        })
    }
}

extension SimulatedPeripheral {
    // MARK: GoPro

    /// A HERO body. It answers Set Shutter with `02 01 <status>` (general
    /// header, command 01) and every other command with success.
    public static func gopro(shutterStatus: UInt8 = GoPro.statusSuccess) -> SimulatedPeripheral {
        SimulatedPeripheral(services: [
            .simulated(GoPro.controlService, [
                GoPro.command: [.write], GoPro.commandResponse: [.notify],
                GoPro.settings: [.write], GoPro.settingsResponse: [.notify],
            ]),
        ], responder: { write, camera in
            guard write.characteristic == GoPro.command, write.data.count >= 2 else { return }
            let id = write.data[write.data.startIndex + 1]
            let status = id == GoPro.CommandID.setShutter ? shutterStatus : GoPro.statusSuccess
            await camera.notify(Data([0x02, id, status]), on: GoPro.commandResponse)
        })
    }

    // MARK: Ricoh THETA

    /// A THETA X, or another model by its model string.
    public static func theta(model: String = "RICOH THETA X") -> SimulatedPeripheral {
        SimulatedPeripheral(services: [
            .simulated(Theta.infoService, [Theta.modelNumber: [.read]]),
            .simulated(Theta.controlService, [
                Theta.notifyState: [.notify], Theta.setOptions: [.write], Theta.requestShutter: [.write],
            ]),
        ], values: [Theta.modelNumber: Data(model.utf8)])
    }
}
