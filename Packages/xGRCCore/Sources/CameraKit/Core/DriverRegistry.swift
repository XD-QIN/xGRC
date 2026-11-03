import BLEKit
import Foundation

/// The drivers this build knows, and the lookup from an advertisement or a
/// persisted `driverID` to a driver type.
public struct DriverRegistry: Sendable {
    public let drivers: [any CameraDriver.Type]

    public init(drivers: [any CameraDriver.Type]) {
        self.drivers = drivers
    }

    /// Every brand. Order matters only where two could match one
    /// advertisement: Sony and Fujifilm match by company ID; Canon, Nikon,
    /// Panasonic LUMIX and GoPro by service; Ricoh GR by service or name;
    /// RICOH THETA by name. THETA comes before the GR because the two share
    /// the Camera Information service UUID.
    public static let standard = DriverRegistry(drivers: [
        SonyDriver.self, FujifilmDriver.self, CanonRemoteDriver.self, CanonSmartDriver.self,
        NikonRemoteDriver.self, ThetaDriver.self, RicohDriver.self, LumixDriver.self, GoProDriver.self,
    ])

    public func match(_ advertisement: Advertisement) -> CameraMatch? {
        for driver in drivers {
            if let match = driver.matches(advertisement) { return match }
        }
        return nil
    }

    public func driverType(id: String) -> (any CameraDriver.Type)? {
        drivers.first { $0.descriptor.id == id }
    }

    public func makeDriver(id: String, transport: any GATTTransport) -> (any CameraDriver)? {
        driverType(id: id).map { $0.init(transport: transport) }
    }
}
