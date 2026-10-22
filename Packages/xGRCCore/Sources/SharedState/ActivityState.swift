import Foundation

/// The Live Activity's dynamic content on iPhone (product spec § Dynamic Island /
/// Live Activity). Small on purpose: static and dynamic content together must
/// stay under 4 KB.
public struct ActivityState: Codable, Hashable, Sendable {
    /// How the last shot ended, in the words the Island shows.
    public enum Shot: String, Codable, Hashable, Sendable {
        case taken
        case sent
        case notConfirmed
        case failed
    }

    public var cameraName: String
    public var link: TileState.Link
    public var geotag: TileState.Geotag
    public var accuracy: Double?
    public var lastPushAt: Date?
    public var confirmed: Int
    public var sent: Int
    /// A release-delay countdown: when it ends and how long it is.
    public var countdownEnds: Date?
    public var countdownSeconds: Int?
    /// A timed bulb is open: when it closes and how long it is.
    public var bulbEnds: Date?
    public var bulbSeconds: Int?
    /// The shutter button shows: a remote mode, connected, and a brand that
    /// can shoot with the app in the background.
    public var canShoot: Bool
    public var timelapseRunning: Bool
    public var lastShot: Shot?

    public init(cameraName: String = "", link: TileState.Link = .noSession, geotag: TileState.Geotag = .off,
                accuracy: Double? = nil, lastPushAt: Date? = nil, confirmed: Int = 0, sent: Int = 0,
                countdownEnds: Date? = nil, countdownSeconds: Int? = nil,
                bulbEnds: Date? = nil, bulbSeconds: Int? = nil, canShoot: Bool = false,
                timelapseRunning: Bool = false, lastShot: Shot? = nil) {
        self.cameraName = cameraName
        self.link = link
        self.geotag = geotag
        self.accuracy = accuracy
        self.lastPushAt = lastPushAt
        self.confirmed = confirmed
        self.sent = sent
        self.countdownEnds = countdownEnds
        self.countdownSeconds = countdownSeconds
        self.bulbEnds = bulbEnds
        self.bulbSeconds = bulbSeconds
        self.canShoot = canShoot
        self.timelapseRunning = timelapseRunning
        self.lastShot = lastShot
    }

    /// The same state apart from numbers that change all the time (counters,
    /// accuracy, push time). Those updates are throttled; anything else goes
    /// out at once.
    public func sameStatus(as other: ActivityState) -> Bool {
        var a = self
        var b = other
        a.confirmed = 0
        b.confirmed = 0
        a.sent = 0
        b.sent = 0
        a.accuracy = nil
        b.accuracy = nil
        a.lastPushAt = nil
        b.lastPushAt = nil
        return a == b
    }
}
