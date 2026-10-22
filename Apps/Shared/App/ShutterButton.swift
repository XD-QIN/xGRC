import DesignKit
import SessionKit
import SwiftUI

/// The shutter control. A real `Button` with a plain `ButtonStyle` whose action
/// is *Shoot*, so watchOS treats it as a control: the hand Double Tap
/// (`handGestureShortcut(.primaryAction)`), VoiceOver and the Smart Stack all
/// perform a shot. A custom `PrimitiveButtonStyle` replaced the button with a
/// bare view, and Double Tap then fell back to the system's scroll and paging.
/// Screen touches go through the label's own gesture, which reports touch-down
/// and touch-up only; `ShotSequencer` turns them into focus, double tap and, in
/// bulb mode, the timed bulb (product spec § Apple Watch › Controls).
struct ShutterButton: View {
    let appearance: ShutterAppearance
    /// An open timed bulb: when it opened and when it closes.
    let bulb: (since: Date, ends: Date)?
    /// A bulb time is set: one tap opens the bulb.
    var bulbMode = false
    /// A release-delay countdown: when it ends and how long it is.
    let countdown: (ends: Date, total: Duration)?
    var confirmed = 0
    var sent = 0
    let isEnabled: Bool
    /// The link is coming back: the shutter stays dimmed and ignores screen
    /// touches, but a Double Tap still lands here and is held until the
    /// camera is ready, rather than scrolling the page away.
    var holdsShot = false
    let doubleTapEnabled: Bool
    let onInput: (ShutterInput) -> Void

    @State private var isDown = false
    @State private var lastTouchUp = Date.distantPast
    /// True while the label's gesture runs; unlike `isDown` it also resets
    /// when the gesture is cancelled (a scroll or page swipe takes the
    /// touch, the button is disabled under the finger).
    @GestureState private var touching = false

    var body: some View {
        Button {
            // A screen touch already reached the sequencer through the label's
            // gesture; only Double Tap, VoiceOver and the Smart Stack shoot here.
            guard !touchJustHappened else { return }
            onInput(.shoot)
        } label: {
            ShutterDisc(appearance: appearance, bulb: bulb, countdown: countdown,
                        confirmed: confirmed, sent: sent)
                .contentShape(Circle())
                .gesture(touchGesture)
        }
        .buttonStyle(ShutterButtonStyle(dimmed: !isEnabled))
        .disabled(!isEnabled && !holdsShot)
        .shutterHandGesture(enabled: doubleTapEnabled && (isEnabled || holdsShot))
        .accessibilityLabel("Shutter")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(bulbMode ? "Activate to open the bulb" : "Activate to take a photo")
        // VoiceOver's single tap only selects and its double tap activates
        // (Shoot), so the gesture model is offered as actions (product spec § Accessibility).
        .accessibilityAction(named: "Focus") { onInput(.focus) }
        .accessibilityActions {
            if bulbMode || bulb != nil {
                Button(bulb == nil ? "Start bulb" : "Stop bulb") { onInput(.toggleBulb) }
            }
            if countdown != nil {
                Button("Cancel countdown") { onInput(.cancel) }
            }
        }
        .onChange(of: touching) { _, isTouching in
            guard !isTouching else { return }
            // A lift runs `onEnded` as well; let it go first, so only a
            // cancelled gesture is left to clean up.
            Task { @MainActor in cancelTouch() }
        }
        .onChange(of: isEnabled) { _, enabled in
            if !enabled { cancelTouch() }
        }
        .onDisappear { cancelTouch() }
    }

    /// The state for VoiceOver, without glyphs: the countdown and the bulb
    /// with their time left.
    private var accessibilityValue: Text {
        if let countdown {
            return Text("Release delay, ")
                + Text(timerInterval: Date.now...max(countdown.ends, Date.now), countsDown: true)
        }
        if let bulb {
            return Text("Bulb open, closes in ")
                + Text(timerInterval: Date.now...max(bulb.ends, Date.now), countsDown: true)
        }
        return Text(appearance.accessibilityValue)
    }

    /// The touch ended without the lift reaching `onEnded`: release what the
    /// touch-down started (focus), without shooting.
    private func cancelTouch() {
        guard isDown else { return }
        isDown = false
        lastTouchUp = .now
        onInput(.touchMoved)
    }

    /// Touch-down and touch-up on the screen. It takes the touch from the
    /// button's own tap; the action's guard covers a system that fires both.
    private var touchGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($touching) { _, state, _ in state = true }
            .onChanged { _ in
                guard isEnabled, !isDown else { return }
                isDown = true
                onInput(.touchDown)
            }
            .onEnded { value in
                // Also for a touch ignored while dimmed, so the button's own
                // tap does not shoot behind it.
                lastTouchUp = .now
                guard isDown else { return }
                isDown = false
                onInput(Self.liftsOnShutter(value.location) ? .touchUp : .touchMoved)
            }
    }

    /// How far past the disc's edge a lift still counts as a tap. A finger
    /// in the field drifts while it taps (a moving wrist, gloves); only a
    /// lift well off the shutter is a scroll or a change of mind.
    static let liftSlop: CGFloat = 24

    /// The lift ended on the shutter, or near enough: a tap, not a slide
    /// off it. `location` is in the disc's own space.
    static func liftsOnShutter(_ location: CGPoint) -> Bool {
        let radius = ShutterDisc.size / 2
        return hypot(location.x - radius, location.y - radius) <= radius + liftSlop
    }

    /// True while a finger is on the shutter and just after it lifts.
    private var touchJustHappened: Bool {
        isDown || Date.now.timeIntervalSince(lastTouchUp) < 0.5
    }
}

/// Draws the label as it is, dimmed when disabled, clipped to the disc so the
/// Double Tap highlight is a circle. Pressing does not restyle it: the
/// sequencer's appearance shows focus and shots.
struct ShutterButtonStyle: ButtonStyle {
    /// Drawn as disabled while the button still takes a Double Tap.
    var dimmed = false

    func makeBody(configuration: Configuration) -> some View {
        ShutterButtonBody(configuration: configuration, dimmed: dimmed)
    }
}

private struct ShutterButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let dimmed: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .opacity(isEnabled && !dimmed ? 1 : 0.4)
            .clipShape(Circle())
    }
}

/// Ring and disc drawn from DesignKit's `ShutterAppearance` (board 03).
/// The disc carries a short label: SHUTTER, AF, AF ✓, ✓ 13, ↑ 13 or !.
/// A release-delay countdown and an open bulb replace the disc with a raised
/// one and a `pending` ring. An open bulb shows the time left until it closes.
struct ShutterDisc: View {
    let appearance: ShutterAppearance
    let bulb: (since: Date, ends: Date)?
    var countdown: (ends: Date, total: Duration)?
    /// The confirmed and sent counts, for the label after a shot.
    var confirmed = 0
    var sent = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The control's side; the label's frame.
    #if os(watchOS)
    static let size = Tally.Target.shutterWatch
    #else
    static let size = Tally.Target.shutterPhone
    #endif

    var body: some View {
        let size = Self.size
        let disc = size * ShutterAppearance.discRatio
        ZStack {
            if let countdown {
                CountdownRing(ends: countdown.ends, total: countdown.total, size: size, animated: !reduceMotion)
            } else if let bulb {
                Circle()
                    .strokeBorder(Tally.Palette.pending, lineWidth: size * 6 / 140)
                Circle().fill(Tally.Palette.raised).frame(width: disc, height: disc)
                VStack(spacing: Tally.Space.xxs) {
                    RoundedRectangle(cornerRadius: size * 4 / 140, style: .continuous)
                        .fill(Tally.Palette.pending)
                        .frame(width: size * 22 / 140, height: size * 22 / 140)
                    Text(timerInterval: bulb.since...max(bulb.ends, bulb.since), countsDown: true)
                        .tallyText(.readoutS)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Tally.Palette.textPrimary)
                }
            } else {
                Circle()
                    .strokeBorder(appearance.ring,
                                  style: StrokeStyle(lineWidth: size * appearance.ringWidthRatio,
                                                     dash: appearance.ringIsDashed ? [6, 4] : []))
                if let fill = appearance.discFill {
                    Circle().fill(fill).frame(width: disc, height: disc)
                } else {
                    Circle().strokeBorder(appearance.discStroke, lineWidth: size * 3 / 140)
                        .frame(width: disc, height: disc)
                }
                Text(verbatim: label)
                    .tallyText(.captionCaps)
                    .foregroundStyle(appearance.discLabelColor)
                    .lineLimit(1)
                    // Some languages' word for shutter is twice the English.
                    .allowsTightening(true)
                    .minimumScaleFactor(0.45)
                    .frame(width: disc * 0.8)
            }
        }
        .frame(width: size, height: size)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: appearance)
    }

    private var label: String {
        switch appearance {
        case .idle: String(localized: "Shutter")
        case .focusing: "AF"
        case .focused: "AF \(Tally.Glyph.confirmed)"
        case .fired: "\(Tally.Glyph.confirmed) \(confirmed)"
        case .sent: "\(Tally.Glyph.sent) \(sent)"
        case .notConfirmed: Tally.Glyph.fault
        }
    }
}

/// The caption under the shutter: the state's glyph and word in its colour,
/// "◐ Delay 10 s" during a countdown and "◐ Bulb open" while bulb is latched.
struct ShutterCaption: View {
    let appearance: ShutterAppearance
    let bulb: (since: Date, ends: Date)?
    let countdown: (ends: Date, total: Duration)?

    var body: some View {
        Group {
            if let countdown {
                Text(verbatim: "\(Tally.Glyph.pending) ") + Text("Delay \(countdown.total.components.seconds) s")
            } else if bulb != nil {
                Text(verbatim: "\(Tally.Glyph.pending) ") + Text("Bulb open")
            } else {
                Text(appearance.caption)
            }
        }
        .foregroundStyle(countdown != nil || bulb != nil ? Tally.Palette.pending : appearance.captionColor)
    }
}

/// A draining `pending` ring on a hairline track around a raised disc, with
/// the time left in `pending`. The time is `Text(timerInterval:)`, so it
/// keeps counting on the dimmed (Always On) screen with no per-second
/// redraw. With Reduce Motion, and while dimmed, the ring stays still.
private struct CountdownRing: View {
    let ends: Date
    let total: Duration
    let size: CGFloat
    let animated: Bool
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        let ringWidth = size * 6 / 140
        let disc = size * ShutterAppearance.discRatio
        ZStack {
            Circle()
                .inset(by: ringWidth / 2)
                .stroke(Tally.Palette.line, lineWidth: ringWidth)
            if animated && !isLuminanceReduced {
                TimelineView(.periodic(from: .now, by: 0.1)) { context in
                    let totalSeconds = max(Double(total.components.seconds), 1)
                    ring(to: max(ends.timeIntervalSince(context.date), 0) / totalSeconds, width: ringWidth)
                }
            } else {
                ring(to: 1, width: ringWidth)
            }
            Circle().fill(Tally.Palette.raised).frame(width: disc, height: disc)
            Text(timerInterval: Date.now...max(ends, Date.now), countsDown: true, showsHours: false)
                .tallyText(.readoutL)
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: disc * 0.85)
                .foregroundStyle(Tally.Palette.pending)
        }
        .accessibilityHidden(true)
    }

    private func ring(to fraction: Double, width: CGFloat) -> some View {
        Circle()
            .inset(by: width / 2)
            .trim(from: 0, to: fraction)
            .rotation(.degrees(-90))
            .stroke(Tally.Palette.pending, style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}

extension View {
    /// Hand Double Tap performs the shutter's primary action (watchOS 11+,
    /// Series 9 / Ultra 2 and newer), only while the Shutter page is selected.
    @ViewBuilder
    func shutterHandGesture(enabled: Bool) -> some View {
        #if os(watchOS)
        if #available(watchOS 11.0, *) {
            handGestureShortcut(.primaryAction, isEnabled: enabled)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
