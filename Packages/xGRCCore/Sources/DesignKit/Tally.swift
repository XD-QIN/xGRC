/// Tally: the xGRC design system.
///
/// A dark-first instrument palette for a camera remote used outdoors, on the
/// wrist and in gloves. Principles (product spec § User experience & UI design):
/// glanceable, thumb-first, works with gloves, and status is colour + glyph +
/// word + haptic, never colour alone.
///
/// The visual reference is the "xGRC Design System" canvas. This namespace is
/// its source of truth in code: views use `Tally.Palette`, `Tally.Space`,
/// `Tally.Radius`, `Tally.Target`, the `tallyText(_:)` modifier and
/// `TallyHaptic`, never literal colours or sizes.
public enum Tally {}
