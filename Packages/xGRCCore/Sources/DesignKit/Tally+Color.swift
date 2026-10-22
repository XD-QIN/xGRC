import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension Tally {
    /// Colour tokens. Each token has a dark and a light value; watchOS, the
    /// Dynamic Island and the Smart Stack always use the dark value.
    ///
    /// Signal colours are the only colours with meaning, and they step apart in
    /// lightness (pending › confirmed › location › fault) so they stay
    /// distinguishable with colour-blindness. Every use pairs one with a glyph
    /// and a word.
    public enum Palette {
        // MARK: Ground

        /// ink-0. OLED ground: watch, Dynamic Island, Smart Stack. Black in every appearance.
        public static let oled = Color(hex: 0x000000)
        /// ink-1 / bg. App ground.
        public static let background = Color(dark: 0x0E0F11, light: 0xF4F4F1)
        /// ink-2 / surface. Card, list row, sheet.
        public static let surface = Color(dark: 0x17191C, light: 0xFFFFFF)
        /// ink-3 / raised. Raised, pressed, chip.
        public static let raised = Color(dark: 0x22252A, light: 0xEBEBE7)
        /// Hairline, ring track, divider.
        public static let line = Color(dark: 0x2E3238, light: 0xDADBD6)

        // MARK: Text

        /// Primary text and the idle shutter disc. 17.4 : 1 on ink-1.
        public static let textPrimary = Color(dark: 0xF4F4F2, light: 0x121316)
        /// Secondary text, labels. 8.3 : 1 on ink-1.
        public static let textSecondary = Color(dark: 0xA6ABB3, light: 0x5A5F68)
        /// Hints, units, the gesture line. 5.7 : 1 on ink-1.
        public static let textTertiary = Color(dark: 0x868C96, light: 0x6B707A)

        // MARK: Signal

        /// ◐ Focusing, connecting, release-delay countdown, bulb open, no GPS fix after 30 s.
        public static let pending = Color(dark: 0xFFB020, light: 0x9A5800)
        /// ✓ Focused, fired and confirmed by the camera, connected, GPS fix good, clock synced.
        public static let confirmed = Color(dark: 0x2CC56A, light: 0x0E7A3C)
        /// ◎ Geotag session running, push sent, current fix, accuracy readout.
        public static let location = Color(dark: 0x5AB0FF, light: 0x0A64C2)
        /// ! Not confirmed, busy, pair again, Bluetooth or location off, no card, camera battery low.
        public static let fault = Color(dark: 0xFF6A4D, light: 0xC73A1E)
        /// Text and glyphs drawn on a signal fill.
        public static let onSignal = Color(dark: 0x000000, light: 0xFFFFFF)
    }
}

extension Color {
    /// A colour from a 24-bit sRGB value, e.g. `Color(hex: 0x2CC56A)`.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// A colour that follows the system appearance on iOS and iPadOS, and is
    /// always `dark` on watchOS and elsewhere.
    init(dark: UInt32, light: UInt32) {
        #if os(iOS)
        self.init(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .light ? light : dark))
        })
        #else
        self.init(hex: dark)
        #endif
    }
}
