import SwiftUI

/// How the shutter button looks in each acknowledged-shooting state
/// (product spec § iPhone / iPad screens, "Remote").
///
/// Filled means the camera confirmed; hollow means it did not. A shot the
/// camera never acknowledged is labelled "Sent", never "Taken". The release-delay
/// countdown and an open bulb are drawn by the button itself (a draining
/// `pending` ring, and a `pending` ring with an elapsed time).
public enum ShutterAppearance: CaseIterable, Sendable {
    /// Connected, nothing held.
    case idle
    /// Half-press sent, waiting for the camera.
    case focusing
    /// The camera confirmed focus; a double tap now shoots.
    case focused
    /// The camera acknowledged the exposure.
    case fired
    /// The brand has no acknowledgement; the press was sent.
    case sent
    /// Timeout, link lost, no card, or the camera is in a menu.
    case notConfirmed

    /// Ring colour around the disc.
    public var ring: Color {
        switch self {
        case .idle: Tally.Palette.textPrimary
        case .focusing: Tally.Palette.pending
        case .focused, .fired: Tally.Palette.confirmed
        case .sent: Tally.Palette.textSecondary
        case .notConfirmed: Tally.Palette.fault
        }
    }

    /// The focusing ring is dashed; every other ring is solid.
    public var ringIsDashed: Bool { self == .focusing }

    /// Ring line width as a fraction of the button diameter
    /// (4 pt, or 6 pt when confirmed, on the 140 pt phone shutter).
    public var ringWidthRatio: CGFloat {
        switch self {
        case .focused, .fired: 6 / 140
        default: 4 / 140
        }
    }

    /// Disc diameter as a fraction of the button diameter.
    public static let discRatio: CGFloat = 112 / 140

    /// Disc fill, or `nil` for a hollow (unconfirmed) disc.
    public var discFill: Color? {
        switch self {
        case .idle, .focusing, .focused: Tally.Palette.textPrimary
        case .fired: Tally.Palette.confirmed
        case .sent, .notConfirmed: nil
        }
    }

    /// Outline of a hollow disc, and the colour of its label.
    public var discStroke: Color {
        switch self {
        case .sent: Tally.Palette.textSecondary
        case .notConfirmed: Tally.Palette.fault
        default: discFill ?? Tally.Palette.textPrimary
        }
    }

    /// Colour of the label inside the disc.
    public var discLabelColor: Color {
        switch self {
        case .idle, .focusing, .focused: Tally.Palette.background
        case .fired: Tally.Palette.onSignal
        case .sent, .notConfirmed: discStroke
        }
    }

    /// The caption under the button: glyph + word.
    public var caption: LocalizedStringResource {
        switch self {
        case .idle: "Ready"
        case .focusing: "◐ Focusing"
        case .focused: "✓ Focused"
        case .fired: "✓ Fired · confirmed"
        case .sent: "↑ Sent"
        case .notConfirmed: "! Not confirmed"
        }
    }

    /// Caption colour.
    public var captionColor: Color {
        switch self {
        case .idle: Tally.Palette.textPrimary
        case .focusing: Tally.Palette.pending
        case .focused, .fired: Tally.Palette.confirmed
        case .sent: Tally.Palette.textSecondary
        case .notConfirmed: Tally.Palette.fault
        }
    }

    /// The state for VoiceOver: the caption's words without the glyph,
    /// which VoiceOver would read out as a symbol name.
    public var accessibilityValue: LocalizedStringResource {
        switch self {
        case .idle: "Ready"
        case .focusing: "Focusing"
        case .focused: "Focused"
        case .fired: "Fired, confirmed"
        case .sent: "Sent"
        case .notConfirmed: "Not confirmed"
        }
    }

    /// What VoiceOver announces on entering this state, or `nil` for none.
    public var announcement: LocalizedStringResource? {
        switch self {
        case .idle: nil
        case .focusing: "Focusing"
        case .focused: "Focused"
        case .fired: "Fired, confirmed"
        case .sent: "Sent. This camera does not confirm shots."
        case .notConfirmed: "Sent, not confirmed"
        }
    }

    /// The haptic played on entering this state, or `nil` for none.
    public var haptic: TallyHaptic? {
        switch self {
        case .idle, .focusing: nil
        case .focused: .focused
        // Unlike the focus click, so a press on a brand without an ack is felt.
        case .sent: .released
        case .fired: .fired
        case .notConfirmed: .notConfirmed
        }
    }
}
