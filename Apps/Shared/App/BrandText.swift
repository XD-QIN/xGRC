import CameraKit
import Foundation

/// Wording that depends on the camera brand, the same on the watch and the
/// phone. Menu paths differ between bodies and firmware; the device test
/// pass (Phase 6) checks each against a real camera.
enum BrandText {
    struct PairingSteps: Identifiable {
        let brand: String
        let steps: String
        var id: String { brand }
    }

    /// How to put each brand in pairing mode, shown above the scan results.
    static var pairingSteps: [PairingSteps] { [
        PairingSteps(brand: "Sony", steps: String(localized: """
            MENU › Network › Bluetooth › Pairing (2020–21 bodies: Network › Transfer/Remote › Bluetooth Function, \
            then Pairing). Turn Bluetooth Rmt Ctrl On to use the remote.
            """)),
        PairingSteps(brand: "Fujifilm", steps: String(localized: """
            Network/USB Setting › Bluetooth/Smartphone Setting › Pairing Registration. Confirm the code on the \
            camera within 30 s. For geotags, turn on Location sync there too.
            """)),
        PairingSteps(brand: "Canon", steps: String(localized: """
            Remote: pair a wireless remote (BR-E1) in the camera's Bluetooth menu and set the drive mode to \
            Self-timer: 10 s/remote or 2 s/remote. Smartphone (adds geotags): pair a smartphone, choose OK on the \
            camera, then set GPS device settings › Select GPS device › Smartphone.
            """)),
        PairingSteps(brand: "Nikon", steps: String(localized: """
            Pair a wireless remote (ML-L7): Setup menu › Wireless remote (ML-L7) options › Save wireless remote. \
            SnapBridge (smart device) pairing is not supported.
            """)),
        PairingSteps(brand: "Ricoh GR", steps: String(localized: """
            Set Bluetooth to On in the camera's communication settings, then confirm the passkey shown on the camera. \
            For geotags, turn on Store Location Info.
            """)),
    ] }

    /// The brand shown as a badge under the camera's name, e.g. "Sony".
    static func brandName(driverID: String?) -> String? {
        guard let driverID, let name = DriverRegistry.standard.driverType(id: driverID)?.descriptor.displayName,
              !name.isEmpty else { return nil }
        return name
    }

    /// The device the user confirms the system dialog on.
    static var thisDevice: String {
        #if os(watchOS)
        String(localized: "this watch")
        #else
        String(localized: "this iPhone")
        #endif
    }

    /// The pairing step where the user has to act, per brand.
    static func bonding(driverID: String) -> String {
        #if os(watchOS)
        let device = String(localized: "the watch")
        #else
        let device = String(localized: "the iPhone")
        #endif
        switch driverID {
        case FujifilmDriver.descriptor.id:
            return String(localized: "Confirm on \(device), then confirm the code on the camera within 30 s")
        case CanonSmartDriver.descriptor.id:
            return String(localized: "Confirm on \(device), then choose OK on the camera")
        case RicohDriver.descriptor.id:
            return String(localized: "Confirm the passkey shown on the camera")
        default:
            return String(localized: "Confirm on \(device), then on the camera")
        }
    }

    /// The camera's own location setting is off.
    static func locationOff(driverID: String?) -> String {
        switch driverID {
        case CanonSmartDriver.descriptor.id?:
            String(localized: "On the camera, set GPS device settings › Select GPS device › Smartphone")
        case RicohDriver.descriptor.id?:
            String(localized: "Turn on Store Location Info. on the camera")
        case FujifilmDriver.descriptor.id?:
            String(localized: "Turn on Location sync in the camera's Bluetooth settings")
        default:
            String(localized: "Turn on Location Info. Link on the camera")
        }
    }

    /// A pull-model camera (Fujifilm) has not asked for a location yet.
    static var waitingForCamera: String {
        String(localized: "Waiting for the camera to ask. It asks every 10 s while Location sync is on.")
    }

    /// A standing note on the shutter page for brands with a camera-side catch.
    static func shutterNote(driverID: String?) -> String? {
        switch driverID {
        case CanonRemoteDriver.descriptor.id?:
            String(localized: "The camera reacts only in Self-timer: 10 s/remote or 2 s/remote drive mode.")
        case NikonRemoteDriver.descriptor.id?:
            String(localized: "Bulb runs as Time: set the camera's shutter speed to Time.")
        default:
            nil
        }
    }
}
