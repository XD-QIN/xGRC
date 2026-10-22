import SwiftUI

extension Tally {
    /// Text styles. SF Pro for words, SF Mono for numbers that change while
    /// you watch them (accuracy, push age, counters, countdowns), so they never
    /// jitter. Every style scales with Dynamic Type. watchOS uses the same
    /// names; the system makes them one step smaller there.
    public enum TextStyle: CaseIterable, Sendable {
        /// 34 / bold. "Cameras"
        case largeTitle
        /// 28 / semibold. "Sony α7C II"
        case title
        /// 20 / semibold. "Geotagging"
        case title3
        /// 17 / semibold. "Connected"
        case headline
        /// 17 / regular. "Put the camera in pairing mode"
        case body
        /// 15 / regular. "tap = focus · 2× = shoot"
        case subheadline
        /// 13 / regular. "Looking for α7C II"
        case footnote
        /// 12 / semibold, tracked, upper case. Brand badges: "SONY · −52 dBm"
        case captionCaps
        /// 56 / medium, monospaced. Session time: "00:42:17"
        case readoutXL
        /// 28 / medium, monospaced. "±4 m · 6 s"
        case readoutL
        /// 15 / medium, monospaced. Counters: "12 ✓ · 13 ↑"
        case readoutS
    }
}

extension View {
    /// Applies a Tally text style, e.g. `Text("00:42:17").tallyText(.readoutXL)`.
    public func tallyText(_ style: Tally.TextStyle) -> some View {
        modifier(TallyTextModifier(style: style))
    }
}

private struct TallyTextModifier: ViewModifier {
    let style: Tally.TextStyle

    // Readouts are larger than any system text style, so they scale relative
    // to the nearest one instead of using it directly.
    @ScaledMetric(relativeTo: .largeTitle) private var readoutXLSize: CGFloat = 56
    @ScaledMetric(relativeTo: .title) private var readoutLSize: CGFloat = 28
    @ScaledMetric(relativeTo: .subheadline) private var readoutSSize: CGFloat = 15

    @ViewBuilder
    func body(content: Content) -> some View {
        switch style {
        case .largeTitle:
            content.font(.largeTitle.weight(.bold))
        case .title:
            content.font(.title.weight(.semibold))
        case .title3:
            content.font(.title3.weight(.semibold))
        case .headline:
            content.font(.headline)
        case .body:
            content.font(.body)
        case .subheadline:
            content.font(.subheadline)
        case .footnote:
            content.font(.footnote)
        case .captionCaps:
            content
                .font(.caption.weight(.semibold))
                .tracking(0.7)
                .textCase(.uppercase)
        case .readoutXL:
            content
                .font(.system(size: readoutXLSize, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .tracking(-1)
        case .readoutL:
            content
                .font(.system(size: readoutLSize, weight: .medium, design: .monospaced))
                .monospacedDigit()
        case .readoutS:
            content
                .font(.system(size: readoutSSize, weight: .medium, design: .monospaced))
                .monospacedDigit()
        }
    }
}
