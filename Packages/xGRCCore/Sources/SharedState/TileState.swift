import Foundation

/// What the watch's Smart Stack tile and the iPhone's controls show (product spec §
/// Apple Watch › Smart Stack tile). The app writes it into the App Group
/// container and reloads them only when they would look different; the
/// widget extensions read it.
public struct TileState: Codable, Hashable, Sendable {
    public enum Link: String, Codable, Hashable, Sendable {
        case noSession
        case connecting
        case connected
        case off
        case busy
        case pairAgain
    }

    public enum Geotag: String, Codable, Hashable, Sendable {
        case off
        case waiting
        case tagging
        case paused
        case noFix
        case failed
    }

    public var cameraName: String?
    public var link: Link
    /// The mode uses the remote.
    public var usesRemote: Bool
    /// The tile and the iPhone's Shoot control offer *Shoot*: a remote mode,
    /// connected, and a brand that can shoot with the app in the background.
    public var canShoot: Bool
    public var geotag: Geotag
    public var geotagStartedAt: Date?
    /// The last location the camera took. The tile shows its age only once
    /// pushes stop, when it no longer changes.
    public var lastPushAt: Date?

    public init(cameraName: String? = nil, link: Link = .noSession, usesRemote: Bool = true,
                canShoot: Bool? = nil, geotag: Geotag = .off, geotagStartedAt: Date? = nil,
                lastPushAt: Date? = nil) {
        self.cameraName = cameraName
        self.link = link
        self.usesRemote = usesRemote
        self.canShoot = canShoot ?? (usesRemote && link == .connected)
        self.geotag = geotag
        self.geotagStartedAt = geotagStartedAt
        self.lastPushAt = lastPushAt
    }

    private enum CodingKeys: String, CodingKey {
        case cameraName, link, usesRemote, canShoot, geotag, geotagStartedAt, lastPushAt
    }

    /// A file an older version wrote has no `canShoot`; it follows the link.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(cameraName: try container.decodeIfPresent(String.self, forKey: .cameraName),
                  link: try container.decode(Link.self, forKey: .link),
                  usesRemote: try container.decode(Bool.self, forKey: .usesRemote),
                  canShoot: try container.decodeIfPresent(Bool.self, forKey: .canShoot),
                  geotag: try container.decode(Geotag.self, forKey: .geotag),
                  geotagStartedAt: try container.decodeIfPresent(Date.self, forKey: .geotagStartedAt),
                  lastPushAt: try container.decodeIfPresent(Date.self, forKey: .lastPushAt))
    }

    /// A session is open: the tile's Double Tap shortcut and *Shoot* are live.
    public var sessionRunning: Bool { link != .noSession }

    /// Whether the tile would look different. While tagging, pushes every few
    /// seconds would otherwise spend the widget reload budget.
    public func differsVisibly(from other: TileState) -> Bool {
        var a = self
        var b = other
        if a.geotag == .tagging, b.geotag == .tagging {
            a.lastPushAt = nil
            b.lastPushAt = nil
        }
        return a != b
    }

    public static let fileName = "TileState.json"

    /// The saved state, or no session when there is none or it is unreadable.
    public static func load(from directory: URL) -> TileState {
        let url = directory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(TileState.self, from: data) else { return TileState() }
        return state
    }

    public func save(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        try data.write(to: directory.appendingPathComponent(Self.fileName), options: .atomic)
    }
}
