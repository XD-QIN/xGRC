import SwiftUI

extension Tally {
    /// The glyph that goes with each signal colour. Always shown next to a word.
    public enum Glyph {
        /// ◐ In progress: focusing, connecting, countdown, searching.
        public static let pending = "◐"
        /// ✓ Confirmed by the camera.
        public static let confirmed = "✓"
        /// ◎ Location: geotag running, current fix, accuracy.
        public static let location = "◎"
        /// ! Fault.
        public static let fault = "!"
        /// ↑ Sent without an acknowledgement.
        public static let sent = "↑"
    }
}

// MARK: - Buttons

/// The three button kinds on board 04 · Controls: *Pair* (primary),
/// *Intervalometer ›* (secondary) and *Stop geotagging* (destructive).
/// Large buttons are 60 pt (anything you hit while shooting); small ones are
/// 44 pt (banner actions, chips).
public struct TallyButtonStyle: ButtonStyle {
    public enum Kind: Sendable {
        /// Primary text fill, ground-coloured label.
        case primary
        /// Raised fill, primary label.
        case secondary
        /// Fault outline and label.
        case destructive
    }

    public enum Size: Sendable {
        case large
        case small
    }

    let kind: Kind
    let size: Size
    let fullWidth: Bool

    public init(_ kind: Kind, size: Size = .large, fullWidth: Bool = false) {
        self.kind = kind
        self.size = size
        self.fullWidth = fullWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        TallyButtonBody(configuration: configuration, kind: kind, size: size, fullWidth: fullWidth)
    }
}

extension ButtonStyle where Self == TallyButtonStyle {
    /// A Tally button, e.g. `.buttonStyle(.tally(.destructive))`.
    public static func tally(_ kind: TallyButtonStyle.Kind, size: TallyButtonStyle.Size = .large,
                             fullWidth: Bool = false) -> TallyButtonStyle {
        TallyButtonStyle(kind, size: size, fullWidth: fullWidth)
    }
}

private struct TallyButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: TallyButtonStyle.Kind
    let size: TallyButtonStyle.Size
    let fullWidth: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let large = size == .large
        let shape = TallyButtonShape(radius: large ? Tally.Radius.card : Tally.Radius.chip)
        configuration.label
            .tallyText(large ? .headline : .subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(foreground)
            .padding(.horizontal, large ? Tally.Space.l : Tally.Space.m)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: large ? Tally.Target.shooting : Tally.Target.minimum)
            .background(fill, in: shape)
            .overlay {
                if kind == .destructive {
                    shape.stroke(Tally.Palette.fault, lineWidth: 1)
                }
            }
            .contentShape(shape)
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }

    private var foreground: Color {
        switch kind {
        case .primary: Tally.Palette.background
        case .secondary: Tally.Palette.textPrimary
        case .destructive: Tally.Palette.fault
        }
    }

    private var fill: Color {
        switch kind {
        case .primary: Tally.Palette.textPrimary
        case .secondary: Tally.Palette.raised
        case .destructive: .clear
        }
    }
}

/// Rounded on iPhone and iPad; a capsule on the watch, as drawn on board 06.
private struct TallyButtonShape: InsettableShape {
    let radius: CGFloat
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: inset, dy: inset)
        #if os(watchOS)
        return Capsule(style: .continuous).path(in: rect)
        #else
        return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
        #endif
    }

    func inset(by amount: CGFloat) -> TallyButtonShape {
        TallyButtonShape(radius: radius, inset: inset + amount)
    }
}

// MARK: - Chips

/// A status-strip chip: "● Connected", "◎ GPS ±3 m". 32 pt tall on a surface
/// fill; put the glyph or `LinkDot` first.
public struct TallyChip<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: Tally.Space.xs) {
            content
        }
        .tallyText(.subheadline)
        .fontWeight(.semibold)
        .foregroundStyle(Tally.Palette.textPrimary)
        .padding(.horizontal, Tally.Space.s)
        .frame(minHeight: Tally.Space.xl)
        .background(Tally.Palette.surface, in: RoundedRectangle(cornerRadius: Tally.Radius.chip, style: .continuous))
    }
}

/// The *AF HOLD* chip: a `confirmed` fill with a ✓ when on, a hairline
/// outline when off. 44 pt tall.
public struct TallyChipToggleStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Tally.Radius.chip, style: .continuous)
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: Tally.Space.xxs) {
                configuration.label
                if configuration.isOn {
                    Text(verbatim: Tally.Glyph.confirmed)
                }
            }
            .tallyText(.captionCaps)
            .fontWeight(.bold)
            .foregroundStyle(configuration.isOn ? Tally.Palette.onSignal : Tally.Palette.textSecondary)
            .padding(.horizontal, Tally.Space.m)
            .frame(minHeight: Tally.Target.minimum)
            .background(configuration.isOn ? Tally.Palette.confirmed : .clear, in: shape)
            .overlay(shape.stroke(configuration.isOn ? Tally.Palette.confirmed : Tally.Palette.line, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        // Read as a switch with its state, not as a plain button.
        .accessibilityAddTraits(configuration.isOn ? [.isToggle, .isSelected] : .isToggle)
        .accessibilityValue(configuration.isOn ? Text("On") : Text("Off"))
    }
}

extension ToggleStyle where Self == TallyChipToggleStyle {
    /// The *AF HOLD* chip.
    public static var tallyChip: TallyChipToggleStyle { TallyChipToggleStyle() }
}

// MARK: - Counter

/// "12 ✓ confirmed · 13 ↑ sent": confirmed and sent shown apart wherever they
/// can differ. `words: false` gives the compact watch form "12 ✓ · 13 ↑".
public struct ShotCounter: View {
    private let confirmed: Int
    private let sent: Int
    private let words: Bool

    public init(confirmed: Int, sent: Int, words: Bool = true) {
        self.confirmed = confirmed
        self.sent = sent
        self.words = words
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tally.Space.xs) {
            Text(verbatim: "\(confirmed) \(Tally.Glyph.confirmed)")
                .foregroundStyle(Tally.Palette.confirmed)
            if words {
                Text("confirmed").tallyText(.footnote).foregroundStyle(Tally.Palette.textSecondary)
            }
            Text(verbatim: "·").foregroundStyle(Tally.Palette.line)
            Text(verbatim: "\(sent) \(Tally.Glyph.sent)")
                .foregroundStyle(Tally.Palette.textSecondary)
            if words {
                Text("sent").tallyText(.footnote).foregroundStyle(Tally.Palette.textSecondary)
            }
        }
        .tallyText(.readoutS)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(confirmed) confirmed, \(sent) sent"))
    }
}

// MARK: - Banners

/// A banner from board 04 · Banners & notes: a 28 pt badge, a title, a line
/// saying what to do, and an optional action. Fault and pending banners have
/// an outline in their colour; an info note has none.
public struct TallyBanner<Action: View>: View {
    public enum Kind: Sendable {
        /// ! Bluetooth off, location off, no card.
        case fault
        /// Square badge: another device holds the camera.
        case busy
        /// ◐ No GPS fix, waiting.
        case pending
        /// i A camera-side setting to check.
        case info
    }

    private let kind: Kind
    private let title: Text
    private let message: Text?
    private let action: Action

    public init(_ kind: Kind, title: Text, message: Text? = nil, @ViewBuilder action: () -> Action) {
        self.kind = kind
        self.title = title
        self.message = message
        self.action = action()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tally.Radius.card, style: .continuous)
        HStack(spacing: Tally.Space.s) {
            badge
                .frame(width: Self.badgeSize, height: Self.badgeSize)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                title
                    .tallyText(.headline)
                    .foregroundStyle(Tally.Palette.textPrimary)
                if let message {
                    message
                        .tallyText(.subheadline)
                        .foregroundStyle(Tally.Palette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            action
        }
        .padding(.horizontal, Tally.Space.m)
        .padding(.vertical, Tally.Space.s)
        .background(Tally.Palette.surface, in: shape)
        .overlay {
            if let outline {
                shape.strokeBorder(outline, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The banner badge, as drawn on the board.
    static var badgeSize: CGFloat { 28 }

    private var outline: Color? {
        switch kind {
        case .fault, .busy: Tally.Palette.fault
        case .pending: Tally.Palette.pending
        case .info: nil
        }
    }

    @ViewBuilder
    private var badge: some View {
        switch kind {
        case .fault:
            Circle()
                .fill(Tally.Palette.fault)
                .overlay {
                    Text(verbatim: Tally.Glyph.fault)
                        .tallyText(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(Tally.Palette.onSignal)
                }
        case .busy:
            LinkDot(.busy, size: Self.badgeSize)
        case .pending:
            LinkDot(.connecting, size: Self.badgeSize)
        case .info:
            Circle()
                .strokeBorder(Tally.Palette.textTertiary, lineWidth: 2)
                .overlay {
                    Text(verbatim: "i")
                        .tallyText(.footnote)
                        .fontWeight(.bold)
                        .foregroundStyle(Tally.Palette.textSecondary)
                }
        }
    }
}

extension TallyBanner where Action == EmptyView {
    public init(_ kind: Kind, title: Text, message: Text? = nil) {
        self.init(kind, title: title, message: message) { EmptyView() }
    }
}
