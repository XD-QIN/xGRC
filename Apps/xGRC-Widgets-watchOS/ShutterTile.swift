import AppIntents
import DesignKit
import SharedState
import SwiftUI
import WidgetKit

/// The Smart Stack tile and, on watchOS 26+, the Shoot control (product spec §
/// Apple Watch › Smart Stack tile). Reads `TileState.json`, which the app
/// writes into the App Group whenever the tile would look different.
@main
struct ShutterTileBundle: WidgetBundle {
    init() {
        AppLanguage.activate()
    }

    var body: some Widget {
        ShutterTile()
        #if compiler(>=6.2)
        if #available(watchOS 26.0, *) {
            ShootControl()
        }
        #endif
    }
}

struct ShutterTile: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppGroup.tileKind, provider: Provider()) { entry in
            TileView(entry: entry)
                .containerBackground(Tally.Palette.oled, for: .widget)
        }
        .configurationDisplayName("xGRC")
        .description("Camera link, geotag state and Shoot.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular])
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let state: TileState
    /// No location has reached the camera for 30 minutes.
    var pushStale = false
}

struct Provider: TimelineProvider {
    /// After this long without a push the tile turns red, as Fujifilm's own icon does.
    static let staleAfter: TimeInterval = 30 * 60

    func placeholder(in context: Context) -> Entry {
        Entry(date: .now, state: TileState(cameraName: "α7C II", link: .connected, geotag: .tagging,
                                           geotagStartedAt: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entries().first!)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // The app reloads the tile on every visible change; the only change it
        // cannot announce is a push going stale, so that one is scheduled.
        completion(Timeline(entries: entries(), policy: .never))
    }

    private func entries() -> [Entry] {
        let state = AppGroup.directory.map(TileState.load(from:)) ?? TileState()
        let now = Date()
        var entries = [Entry(date: now, state: state)]
        if state.geotag != .tagging, state.geotag != .off, let last = state.lastPushAt {
            let stale = last.addingTimeInterval(Self.staleAfter)
            if stale <= now {
                entries[0].pushStale = true
            } else {
                entries.append(Entry(date: stale, state: state, pushStale: true))
            }
        }
        return entries
    }
}

struct TileView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    private var state: TileState { entry.state }
    private var canShoot: Bool { state.canShoot }

    var body: some View {
        switch family {
        case .accessoryCircular:
            shootButton {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "camera.aperture")
                        .tallyText(.title3)
                        .foregroundStyle(state.link.indicator.color)
                        .widgetAccentable()
                }
            }
            // A Shoot button says so; the link is its value.
            .accessibilityLabel(isShootButton ? Text("Shoot") : Text(linkText))
            .accessibilityValue(isShootButton ? Text(linkText) : Text(verbatim: ""))
        default:
            // Board 07, watch Smart Stack: name, "● Linked · pushed 9 s",
            // and a primary-text Shoot capsule.
            HStack(spacing: Tally.Space.xs) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.cameraName ?? String(localized: "xGRC"))
                        .tallyText(.headline)
                        .foregroundStyle(Tally.Palette.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: Tally.Space.xxs) {
                        LinkDot(state.link.indicator, size: 6)
                        Text(linkText)
                            .foregroundStyle(Tally.Palette.textSecondary)
                            .lineLimit(1)
                    }
                    .tallyText(.footnote)
                    geotagLine
                        .tallyText(.footnote)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                if canShoot {
                    shootButton {
                        Text("Shoot")
                            .tallyText(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(Tally.Palette.oled)
                            .padding(.horizontal, Tally.Space.s)
                            .frame(minHeight: Tally.Target.minimum)
                            .background(Tally.Palette.textPrimary, in: Capsule())
                            .widgetAccentable()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var geotagLine: some View {
        switch state.geotag {
        case .off:
            EmptyView()
        case .tagging:
            // A running geotag session is a location state (board 01).
            if let started = state.geotagStartedAt {
                (Text(verbatim: "\(Tally.Glyph.location) ") + Text("Tagging · ") + Text(started, style: .timer))
                    .monospacedDigit()
                    .foregroundStyle(Tally.Palette.location)
            }
        case .waiting:
            (Text(verbatim: "\(Tally.Glyph.pending) ") + Text("Waiting for GPS"))
                .foregroundStyle(Tally.Palette.pending)
        case .paused, .noFix, .failed:
            if let last = state.lastPushAt {
                (Text(verbatim: "\(entry.pushStale ? Tally.Glyph.fault : Tally.Glyph.pending) ")
                    + Text("Last push ") + Text(last, style: .relative))
                    .monospacedDigit()
                    .foregroundStyle(entry.pushStale ? Tally.Palette.fault : Tally.Palette.pending)
            } else {
                (Text(verbatim: "\(Tally.Glyph.fault) ") + Text("No location sent"))
                    .foregroundStyle(Tally.Palette.fault)
            }
        }
    }

    /// `shootButton` draws a Button (not only its label).
    private var isShootButton: Bool {
        if #available(watchOS 11.0, *) { return canShoot }
        return false
    }

    /// *Shoot* while a session is connected (interactive widgets, watchOS 11+);
    /// otherwise tapping the tile opens xGRC. Double Tap is declared only while
    /// a session runs, so opening the Smart Stack cannot fire the camera.
    @ViewBuilder
    private func shootButton(@ViewBuilder label: () -> some View) -> some View {
        if #available(watchOS 11.0, *), canShoot {
            Button(intent: ShootIntent(), label: label)
                .buttonStyle(.plain)
                .handGestureShortcut(.primaryAction, isEnabled: state.sessionRunning)
        } else {
            label()
        }
    }

    private var linkText: String {
        switch state.link {
        case .noSession: String(localized: "Open to start a session")
        case .connecting: String(localized: "Connecting…")
        case .connected: String(localized: "Connected")
        case .off: String(localized: "Camera off or out of range")
        case .busy: String(localized: "Linked to another device")
        case .pairAgain: String(localized: "Pair again")
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

#if compiler(>=6.2)
/// The watch app's own Shoot control (watchOS 26+): Control Center and the
/// Smart Stack. The Action Button is not supported.
@available(watchOS 26.0, *)
struct ShootControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "xGRC.shoot") {
            ControlWidgetButton(action: ShootIntent()) {
                Label("Shoot", systemImage: "camera.aperture")
            }
        }
        .displayName("Shoot")
        .description("Takes a photo on the connected camera.")
    }
}
#endif
