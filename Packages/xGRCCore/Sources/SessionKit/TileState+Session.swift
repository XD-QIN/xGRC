import Foundation
import Persistence
import SharedState

extension TileState {
    /// The tile's view of the running session. `backgroundShooting`: the
    /// brand can shoot while the app is in the background.
    public init(session: SessionSnapshot, geotag: GeotagSnapshot, mode: SessionMode,
                backgroundShooting: Bool = true) {
        let link: Link
        switch session.link {
        case .ready?: link = .connected
        case .connecting?, .bonding?, .registering?, .reconnecting?: link = .connecting
        case .outOfRange?: link = .off
        case .busy?: link = .busy
        case .pairAgain?, .firmwareChanged?, .failed?: link = .pairAgain
        case .ended?, nil: link = .noSession
        }
        let status: Geotag
        switch geotag.status {
        case .off: status = .off
        case .starting, .waitingForFix, .waitingForCamera: status = .waiting
        case .tagging: status = .tagging
        case .paused: status = .paused
        case .noFix: status = .noFix
        // The camera refuses the fixes: as untagged as a failed start.
        case .failed, .cameraNotTagging: status = .failed
        }
        self.init(cameraName: link == .noSession ? nil : session.camera?.name,
                  link: link,
                  usesRemote: mode.usesRemote,
                  canShoot: mode.usesRemote && link == .connected && backgroundShooting,
                  geotag: link == .noSession ? .off : status,
                  geotagStartedAt: geotag.startedAt,
                  lastPushAt: geotag.lastPushAt)
    }
}
