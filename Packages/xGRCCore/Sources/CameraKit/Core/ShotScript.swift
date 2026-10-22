import BLEKit
import Foundation

/// One GATT write from a brand's shot recipe.
public struct ShotWrite: Hashable, Sendable {
    public let data: Data
    public let characteristic: GATTCharacteristicID
    public let withResponse: Bool
    /// This write opens the shutter (the full press). The sequencer counts a
    /// shot as *sent* once it has gone out.
    public let firesShutter: Bool

    public init(_ data: Data, to characteristic: GATTCharacteristicID, withResponse: Bool = true,
                firesShutter: Bool = false) {
        self.data = data
        self.characteristic = characteristic
        self.withResponse = withResponse
        self.firesShutter = firesShutter
    }
}

/// Which confirmation a step waits for.
public enum AckKind: Hashable, Sendable {
    case focus
    case shutter
    /// The camera is ready for the next frame (Sony `02 A0 00`); the
    /// intervalometer waits for it so a slow card write delays a frame
    /// instead of dropping it.
    case ready

    /// Whether a camera event satisfies this ack.
    public func isSatisfied(by event: CameraEvent) -> Bool {
        switch (self, event) {
        case (.focus, .focusAcquired), (.shutter, .shutterActive), (.ready, .shutterReady): true
        default: false
        }
    }
}

public enum ShotStep: Hashable, Sendable {
    case write(ShotWrite)
    /// Wait for a camera confirmation opened by our own press. A non-optional
    /// ack that times out makes the shot *unconfirmed*; the remaining steps
    /// (the releases) still run.
    case awaitAck(AckKind, timeout: Duration, optional: Bool)
    case hold(Duration)
}

/// A brand's press/release recipe as step lists the sequencer executes
/// (architecture doc § Key abstractions). Composition by the sequencer:
///
/// - touch-down: `focusPress`
/// - single tap ends (grace over): `focusRelease`
/// - double tap with focus held: `shootFromFocus`, then `focusRelease`
/// - Shoot with nothing held: `focusPress`, `awaitAck(.focus, 2 s, optional)`,
///   `shootFromFocus`, `focusRelease` (or `shootWithoutFocus` without half-press)
/// - bulb mode, one tap: `focusPress`, the focus wait, `latch`; when the
///   bulb time ends or on the next tap: `unlatch`
/// - after a link loss or scene change: `releaseAll`, after `unlatch` when
///   a bulb may still be open
/// - after a write error: `releaseAll` (or `unlatch` once a latch press went out)
public struct ShotScript: Hashable, Sendable {
    public let focusSupported: Bool
    public let focusPress: [ShotStep]
    public let focusRelease: [ShotStep]
    /// Full press, shutter ack, full release; focus is held around it.
    public let shootFromFocus: [ShotStep]
    /// For brands with no half-press: the complete single shot.
    public let shootWithoutFocus: [ShotStep]
    /// Bulb open; focus is held. A toggling latch (Sony, Nikon Time) may
    /// release every button once the shutter is open.
    public let latch: [ShotStep]
    /// Bulb close, including the focus release.
    public let unlatch: [ShotStep]
    /// Every button up, in a safe order. Errors are ignored.
    public let releaseAll: [ShotStep]
    public let minimumWriteGap: Duration
    /// The camera reports focus (Sony `02 3F 20`). Without it, Shoot with
    /// nothing held waits `focusSettle` after the half-press instead of the
    /// focus ack, and never shows the no-focus-confirmation hint.
    public let acknowledgesFocus: Bool
    public let focusSettle: Duration
    /// `unlatch` presses the shutter again (Nikon Time, Sony bulb with a
    /// Bluetooth remote): sent to a camera whose bulb is not open, it opens
    /// one. The sequencer sends it only when the latch press is known to have
    /// gone out and, where the latch waits for a shutter ack, the ack came.
    public let unlatchToggles: Bool

    public init(focusSupported: Bool, focusPress: [ShotStep], focusRelease: [ShotStep],
                shootFromFocus: [ShotStep], shootWithoutFocus: [ShotStep], latch: [ShotStep],
                unlatch: [ShotStep], releaseAll: [ShotStep], minimumWriteGap: Duration,
                acknowledgesFocus: Bool = true, focusSettle: Duration = .zero, unlatchToggles: Bool = false) {
        self.acknowledgesFocus = acknowledgesFocus
        self.unlatchToggles = unlatchToggles
        self.focusSettle = focusSettle
        self.focusSupported = focusSupported
        self.focusPress = focusPress
        self.focusRelease = focusRelease
        self.shootFromFocus = shootFromFocus
        self.shootWithoutFocus = shootWithoutFocus
        self.latch = latch
        self.unlatch = unlatch
        self.releaseAll = releaseAll
        self.minimumWriteGap = minimumWriteGap
    }

    /// The writes of `releaseAll`, which every driver's `disconnect()` sends.
    public var releaseAllWrites: [ShotWrite] {
        releaseAll.compactMap { step in
            if case .write(let write) = step { return write }
            return nil
        }
    }

    /// Whether any step of `steps` waits for a shutter ack.
    public static func confirmsShutter(_ steps: [ShotStep]) -> Bool {
        steps.contains {
            if case .awaitAck(.shutter, _, false) = $0 { return true }
            return false
        }
    }
}

/// Every shot reports how it was confirmed. The UI and the intervalometer
/// branch on this (architecture doc § Key abstractions).
public enum ShotResult: Hashable, Sendable {
    /// The camera reported the exposure.
    case acknowledged(focusLatency: Duration?, shutterLatency: Duration)
    /// The protocol has no report; a timed press was used. Shown as "Sent".
    case assumed(heldFor: Duration)
    /// The press went out but the ack timed out or the link was lost.
    case unconfirmed(UnconfirmedReason)
    case cancelled
    /// Nothing went out: the write failed before the full press.
    case failed(ShotError)

    /// Counts towards the *sent* counter.
    public var wasSent: Bool {
        switch self {
        case .acknowledged, .assumed, .unconfirmed: true
        case .cancelled, .failed: false
        }
    }

    /// Counts towards the *confirmed* counter.
    public var isConfirmed: Bool {
        if case .acknowledged = self { return true }
        return false
    }
}

public enum UnconfirmedReason: Hashable, Sendable {
    case shutterTimedOut
    /// The focus ack and the shutter ack both timed out.
    case focusTimedOut
    case linkLost
}

public enum ShotError: Error, Hashable, Sendable {
    case notConnected
    case remoteControlOff
    case busy
    case transport(GATTError)
}
