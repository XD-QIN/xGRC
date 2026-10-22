import SwiftUI

/// A camera's link state as shown on a camera row and the status strip
/// (product spec § iPhone / iPad screens and § States & errors).
///
/// The dot's shape carries the state as well as its colour: filled = live,
/// half = in progress, ring = saved, dashed = powered off, square = busy,
/// red ring = needs pairing. Always shown next to `label`.
public enum LinkIndicator: CaseIterable, Sendable {
    case connected
    case connecting
    case saved
    case off
    case busy
    case pairAgain

    public var label: LocalizedStringResource {
        switch self {
        case .connected: "Connected"
        case .connecting: "Connecting…"
        case .saved: "Saved"
        case .off: "Off"
        case .busy: "Busy"
        case .pairAgain: "Pair again"
        }
    }

    public var color: Color {
        switch self {
        case .connected: Tally.Palette.confirmed
        case .connecting: Tally.Palette.pending
        case .saved, .off: Tally.Palette.textTertiary
        case .busy, .pairAgain: Tally.Palette.fault
        }
    }

    /// Label colour; quiet states use secondary text rather than their dot colour.
    public var labelColor: Color {
        switch self {
        case .saved, .off: Tally.Palette.textSecondary
        default: color
        }
    }
}

/// The link-state dot. 12 pt on camera rows, 8 pt in chips.
public struct LinkDot: View {
    private let state: LinkIndicator
    private let size: CGFloat

    public init(_ state: LinkIndicator, size: CGFloat = 12) {
        self.state = state
        self.size = size
    }

    public var body: some View {
        shape
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var shape: some View {
        let stroke = max(1.5, size / 6)
        switch state {
        case .connected:
            Circle().fill(state.color)
        case .connecting:
            Circle()
                .strokeBorder(state.color, lineWidth: stroke)
                .background(
                    Circle().fill(state.color).mask {
                        HStack(spacing: 0) {
                            Rectangle()
                            Color.clear
                        }
                    }
                )
        case .saved, .pairAgain:
            Circle().strokeBorder(state.color, lineWidth: stroke)
        case .off:
            Circle().strokeBorder(state.color, style: StrokeStyle(lineWidth: stroke, dash: [2, 2]))
        case .busy:
            RoundedRectangle(cornerRadius: size / 4, style: .continuous).fill(state.color)
        }
    }
}
