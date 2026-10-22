import Foundation

/// One position fix as the drivers need it. Altitude is above mean sea level
/// (`CLLocation.altitude`), which is what EXIF expects (architecture doc § Geotag defaults).
public struct GeoFix: Hashable, Sendable, Codable {
    public var latitude: Double
    public var longitude: Double
    /// Metres above mean sea level, when the fix has one.
    public var altitude: Double?
    /// Horizontal accuracy in metres (radius of uncertainty).
    public var horizontalAccuracy: Double
    /// When the fix was taken.
    public var timestamp: Date

    public init(latitude: Double, longitude: Double, altitude: Double? = nil,
                horizontalAccuracy: Double, timestamp: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.timestamp = timestamp
    }

    /// Great-circle distance in metres (haversine), enough for movement triggers.
    public func distance(to other: GeoFix) -> Double {
        let r = 6_371_000.0
        let φ1 = latitude * .pi / 180, φ2 = other.latitude * .pi / 180
        let dφ = (other.latitude - latitude) * .pi / 180
        let dλ = (other.longitude - longitude) * .pi / 180
        let a = sin(dφ / 2) * sin(dφ / 2) + cos(φ1) * cos(φ2) * sin(dλ / 2) * sin(dλ / 2)
        return 2 * r * atan2(a.squareRoot(), (1 - a).squareRoot())
    }
}

/// How the camera takes locations once the link is enabled.
public enum LocationLinkMode: Hashable, Sendable {
    /// We push fixes on our interval (Sony, Canon Smart, Nikon Smart, Ricoh).
    case push
    /// The camera asks and we answer (Fujifilm).
    case pull
}

/// A periodic write that keeps the camera from powering off (Sony `CC02`).
/// Executed by `GeoTagStreamer`, not the driver.
public struct KeepAlivePolicy: Hashable, Sendable {
    public let interval: Duration
    public let write: ShotWrite

    public init(interval: Duration, write: ShotWrite) {
        self.interval = interval
        self.write = write
    }
}

/// Brand rules the streamer applies to fixes (architecture doc § Geotag defaults).
public struct GeotagRules: Hashable, Sendable {
    /// A fix older than this is never sent: Sony 10 s, everyone else 30 s.
    public var maximumFixAge: Duration
    /// Shortest push interval the camera accepts (Ricoh 10 s).
    public var minimumInterval: Duration
    /// Stamp packets with the send time (Sony, Fujifilm, Canon) or the fix time (Ricoh, Nikon).
    public var stampsSendTime: Bool

    public init(maximumFixAge: Duration = .seconds(30), minimumInterval: Duration = .seconds(1),
                stampsSendTime: Bool = true) {
        self.maximumFixAge = maximumFixAge
        self.minimumInterval = minimumInterval
        self.stampsSendTime = stampsSendTime
    }
}
