import ActivityKit
import AppIntents
import DesignKit
import SharedState
import SwiftUI
import WidgetKit

/// The session's Live Activity: Lock Screen, Dynamic Island, and on watchOS
/// 11+ a small view in the watch's Smart Stack labelled "iPhone · camera"
/// with no shutter, so only the watch's own tile fires the watch's camera
/// (product spec § Dynamic Island / Live Activity).
struct SessionLiveActivity: Widget {
    // One widget for both versions: an opaque result may change type across
    // an `if #available`, which the widget bundle builder cannot express.
    var body: some WidgetConfiguration {
        if #available(iOS 18.0, *) {
            return SessionActivityConfiguration.make()
                .supplementalActivityFamilies([.small])
        } else {
            return SessionActivityConfiguration.make()
        }
    }
}

@MainActor
enum SessionActivityConfiguration {
    static func make() -> ActivityConfiguration<SessionActivityAttributes> {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            ActivityContentView(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(Tally.Palette.surface)
                .activitySystemActionForegroundColor(Tally.Palette.textPrimary)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(state.cameraName).tallyText(.title3).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LinkBadge(link: state.link)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: Tally.Space.s) {
                        DetailLine(state: state)
                        // Stale: the app stopped updating (it may have been killed),
                        // so a press could do nothing, as on the Lock Screen.
                        if state.canShoot, !context.isStale, state.bulbEnds == nil { ShutterButtonView(state: state) }
                    }
                }
            } compactLeading: {
                HStack(spacing: Tally.Space.xxs) {
                    Image(systemName: "camera")
                        .foregroundStyle(Tally.Palette.textPrimary)
                    LinkDot(state.link.indicator, size: 6)
                }
            } compactTrailing: {
                if let ends = state.countdownEnds ?? state.bulbEnds {
                    Text(timerInterval: Date.now...max(ends, .now), countsDown: true)
                        .tallyText(.readoutS)
                        .foregroundStyle(Tally.Palette.pending)
                        .frame(maxWidth: 40)
                } else if state.geotag != .off {
                    GPSText(state: state)
                        .tallyText(.readoutS)
                }
            } minimal: {
                Image(systemName: "camera")
                    .foregroundStyle(Tally.Palette.textPrimary)
                    .overlay(alignment: .topTrailing) {
                        LinkDot(state.link.indicator, size: 6)
                    }
            }
        }
    }
}

/// The Lock Screen, or on iOS 18+ the small watch Smart Stack family.
private struct ActivityContentView: View {
    let state: SharedState.ActivityState
    let isStale: Bool

    var body: some View {
        if #available(iOS 18.0, *) {
            FamilyAwareView(state: state, isStale: isStale)
        } else {
            LockScreenView(state: state, isStale: isStale)
        }
    }
}

/// On the watch: "IPHONE · CAMERA", labelled and never a shutter (board 07).
@available(iOS 18.0, *)
private struct FamilyAwareView: View {
    @Environment(\.activityFamily) private var family
    let state: SharedState.ActivityState
    let isStale: Bool

    var body: some View {
        switch family {
        case .small:
            VStack(alignment: .leading, spacing: 2) {
                Text("iPhone · camera")
                    .tallyText(.captionCaps)
                    .foregroundStyle(Tally.Palette.textTertiary)
                HStack(spacing: Tally.Space.xxs) {
                    LinkDot(state.link.indicator, size: 6)
                    Text(state.cameraName).tallyText(.headline).lineLimit(1)
                }
                if state.geotag != .off { GPSText(state: state).tallyText(.footnote) }
            }
            .padding(Tally.Space.xs)
        default:
            LockScreenView(state: state, isStale: isStale)
        }
    }
}

private struct LockScreenView: View {
    let state: SharedState.ActivityState
    let isStale: Bool

    var body: some View {
        HStack(spacing: Tally.Space.m) {
            VStack(alignment: .leading, spacing: Tally.Space.xs) {
                HStack {
                    Text(state.cameraName).tallyText(.headline).lineLimit(1)
                    Spacer()
                    LinkBadge(link: state.link)
                }
                DetailLine(state: state)
                if state.canShoot, !isStale, state.countdownEnds == nil, state.bulbEnds == nil {
                    ShutterButtonView(state: state)
                }
            }
            if let ends = state.countdownEnds, let seconds = state.countdownSeconds {
                CountdownDial(ends: ends, seconds: seconds, label: "Release delay")
            } else if let ends = state.bulbEnds, let seconds = state.bulbSeconds {
                // The timed bulb closes itself; the dial drains until it does.
                CountdownDial(ends: ends, seconds: seconds, label: "Bulb open")
            }
        }
        .foregroundStyle(Tally.Palette.textPrimary)
        .padding(Tally.Space.m)
        .opacity(isStale ? 0.6 : 1)
    }
}

/// The release-delay or timed-bulb ring: drains in `pending` with the
/// seconds left (board 07, Lock Screen). Driven by the system timer, so it
/// needs no updates.
private struct CountdownDial: View {
    let ends: Date
    let seconds: Int
    let label: LocalizedStringKey

    var body: some View {
        let start = ends.addingTimeInterval(-Double(seconds))
        ZStack {
            ProgressView(timerInterval: start...max(ends, start), countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.circular)
            .tint(Tally.Palette.pending)
            Text(timerInterval: Date.now...max(ends, .now), countsDown: true, showsHours: false)
                .tallyText(.readoutS)
                .foregroundStyle(Tally.Palette.pending)
                .multilineTextAlignment(.center)
        }
        .frame(width: Tally.Target.shooting, height: Tally.Target.shooting)
        .accessibilityLabel(label)
    }
}

/// "◎ ±4 m · 6 s · 12 ✓ · 13 ↑" in monospaced readout figures.
private struct DetailLine: View {
    let state: SharedState.ActivityState

    var body: some View {
        HStack(spacing: Tally.Space.xs) {
            if state.geotag != .off { GPSText(state: state) }
            if state.link == .connected, state.sent > 0 || state.confirmed > 0 {
                (Text(verbatim: "\(state.confirmed) \(Tally.Glyph.confirmed)").foregroundStyle(Tally.Palette.confirmed)
                    + Text(verbatim: " · \(state.sent) \(Tally.Glyph.sent)"))
                    .accessibilityLabel("\(state.confirmed) confirmed, \(state.sent) sent")
            }
            Spacer(minLength: 0)
        }
        .tallyText(.readoutS)
        .foregroundStyle(Tally.Palette.textSecondary)
    }
}

/// The geotag state as glyph + words: ◎ location while tagging, ◐ pending
/// while waiting, ! fault when it stopped.
private struct GPSText: View {
    let state: SharedState.ActivityState

    var body: some View {
        switch state.geotag {
        case .tagging:
            HStack(spacing: Tally.Space.xxs) {
                Text(verbatim: Tally.Glyph.location).foregroundStyle(Tally.Palette.location)
                if let accuracy = state.accuracy {
                    Text(verbatim: "±\(Int(accuracy.rounded())) m").foregroundStyle(Tally.Palette.textPrimary)
                }
                if let last = state.lastPushAt {
                    Text(last, style: .relative).foregroundStyle(Tally.Palette.textTertiary)
                }
            }
        case .waiting:
            (Text(verbatim: "\(Tally.Glyph.pending) ") + Text("GPS…")).foregroundStyle(Tally.Palette.pending)
        case .paused, .noFix:
            (Text(verbatim: "\(Tally.Glyph.pending) ") + Text("No GPS")).foregroundStyle(Tally.Palette.pending)
        case .failed:
            (Text(verbatim: "\(Tally.Glyph.fault) ") + Text("Geotag off")).foregroundStyle(Tally.Palette.fault)
        case .off:
            EmptyView()
        }
    }
}

/// Link dot and word, in the link state's colour.
private struct LinkBadge: View {
    let link: TileState.Link

    var body: some View {
        HStack(spacing: Tally.Space.xs) {
            LinkDot(link.indicator, size: 8)
            Text(text)
                .tallyText(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(link.indicator.labelColor)
        }
    }

    private var text: LocalizedStringKey {
        switch link {
        case .connected: "Linked"
        case .connecting: "Connecting…"
        case .off: "Out of range"
        case .busy: "Busy"
        case .pairAgain: "Pair again"
        case .noSession: "Ended"
        }
    }
}

extension TileState.Link {
    /// The DesignKit link state, for its dot shape and colour.
    var indicator: LinkIndicator {
        switch self {
        case .connected: .connected
        case .connecting: .connecting
        case .off: .off
        case .busy: .busy
        case .pairAgain: .pairAgain
        case .noSession: .saved
        }
    }
}

/// The Island's shutter: a `LiveActivityIntent`, performed in the app. A
/// primary-text capsule with a ring glyph, 60 pt tall (board 07).
private struct ShutterButtonView: View {
    let state: SharedState.ActivityState

    var body: some View {
        Button(intent: ShootLiveActivityIntent()) {
            HStack(spacing: Tally.Space.xs) {
                if let ends = state.countdownEnds {
                    Text(timerInterval: Date.now...max(ends, .now), countsDown: true)
                        .tallyText(.readoutS)
                } else {
                    Circle()
                        .strokeBorder(Tally.Palette.background, lineWidth: 3)
                        .frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                    Text("Shutter")
                }
            }
            .tallyText(.headline)
            .fontWeight(.bold)
            .foregroundStyle(Tally.Palette.background)
            .frame(maxWidth: .infinity, minHeight: Tally.Target.shooting)
            .background(Tally.Palette.textPrimary, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
