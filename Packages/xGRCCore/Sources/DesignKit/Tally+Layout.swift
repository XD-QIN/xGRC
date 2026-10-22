import CoreGraphics

extension Tally {
    /// Spacing on a 4 pt grid.
    public enum Space {
        /// 4. Glyph to label.
        public static let xxs: CGFloat = 4
        /// 8. Inside chips.
        public static let xs: CGFloat = 8
        /// 12. Row content.
        public static let s: CGFloat = 12
        /// 16. Screen margin, card padding.
        public static let m: CGFloat = 16
        /// 24. Between groups.
        public static let l: CGFloat = 24
        /// 32. Around the shutter.
        public static let xl: CGFloat = 32
        /// 48. Section breaks on iPad.
        public static let xxl: CGFloat = 48
    }

    /// Corner radii. Use with `RoundedRectangle(cornerRadius:style: .continuous)`;
    /// the shutter, pills and dots are `Capsule` or `Circle`.
    public enum Radius {
        /// 10. Chips, toggles, small buttons.
        public static let chip: CGFloat = 10
        /// 14. Cards, list groups, large buttons.
        public static let card: CGFloat = 14
        /// 22. Sheets and the live specimen panels.
        public static let sheet: CGFloat = 22
    }

    /// Hit-target sizes, sized for gloves.
    public enum Target {
        /// 44. Minimum for any control.
        public static let minimum: CGFloat = 44
        /// 60. Anything you hit while shooting: primary buttons, list rows.
        public static let shooting: CGFloat = 60
        /// 140. Shutter button on iPhone and iPad.
        public static let shutterPhone: CGFloat = 140
        /// 110. Shutter button on Apple Watch.
        public static let shutterWatch: CGFloat = 110
    }
}
