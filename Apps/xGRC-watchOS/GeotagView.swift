import CameraKit
import DesignKit
import SessionKit
import SwiftUI

/// Page 2 of the session: fix quality, last push, elapsed time, altitude, and
/// Start/Stop (product spec § Apple Watch). The location session keeps running with
/// the wrist down and after leaving the app.
struct GeotagPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let geotag = model.geotag
        ScrollView {
            VStack(alignment: .leading, spacing: Tally.Space.xs) {
                // "◎ GPS ±5 m": glyph + word + colour (board 06).
                HStack(spacing: Tally.Space.xs) {
                    Text(verbatim: fixGlyph)
                        .foregroundStyle(fixColor)
                    Text("GPS")
                        .fontWeight(.semibold)
                    if let fix = geotag.fix, geotag.isActive {
                        Text("±\(Int(fix.horizontalAccuracy.rounded())) m")
                            .tallyText(.readoutS)
                            .foregroundStyle(Tally.Palette.location)
                    }
                }
                .tallyText(.subheadline)
                .accessibilityElement(children: .combine)

                if geotag.isActive {
                    if let started = geotag.startedAt {
                        Text(started, style: .timer)
                            .tallyText(.readoutL)
                            .accessibilityLabel(Text("Geotagging for ") + Text(started, style: .relative))
                    }
                    if let last = geotag.lastPushAt {
                        HStack(spacing: Tally.Space.xxs) {
                            Text("Pushed")
                            Text(last, style: .relative)
                                .monospacedDigit()
                                .foregroundStyle(Tally.Palette.textPrimary)
                        }
                        .tallyText(.footnote)
                        .foregroundStyle(Tally.Palette.textSecondary)
                    }
                    HStack(spacing: Tally.Space.s) {
                        Text("\(geotag.pushes) ↑")
                            .accessibilityLabel(geotag.pushes == 1 ? "1 location sent" : "\(geotag.pushes) locations sent")
                        if let altitude = geotag.fix?.altitude {
                            Text("\(Int(altitude.rounded())) m")
                                .accessibilityLabel("Altitude \(Int(altitude.rounded())) metres")
                        }
                    }
                    .tallyText(.readoutS)
                    .foregroundStyle(Tally.Palette.textSecondary)
                }

                if let message = model.geotagMessage {
                    Text(message.text)
                        .tallyText(.footnote)
                        .foregroundStyle(message.isFault ? Tally.Palette.fault : Tally.Palette.pending)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if geotag.isActive {
                    Button("Stop", role: .destructive) { model.stopGeotag() }
                        .buttonStyle(.tally(.destructive, size: .small, fullWidth: true))
                } else {
                    Button("Start geotagging") { model.startGeotag() }
                        .buttonStyle(.tally(.primary, size: .small, fullWidth: true))
                        .disabled(!model.isReady)
                }

                if model.session.camera?.driverID == SonyDriver.descriptor.id {
                    Text("Sony bodies older than the α7 IV pause location while Bluetooth Rmt Ctrl is On. Choose Geotag only in Settings › Mode and turn Bluetooth Rmt Ctrl off.")
                        .tallyText(.footnote)
                        .foregroundStyle(Tally.Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var fixGlyph: String {
        switch model.geotag.status {
        case .tagging, .off: Tally.Glyph.location
        case .waitingForFix, .waitingForCamera, .starting, .paused: Tally.Glyph.pending
        case .noFix, .cameraNotTagging, .failed: Tally.Glyph.fault
        }
    }

    private var fixColor: Color {
        switch model.geotag.status {
        case .tagging: Tally.Palette.location
        case .waitingForFix, .waitingForCamera, .starting, .paused: Tally.Palette.pending
        case .noFix, .cameraNotTagging, .failed: Tally.Palette.fault
        case .off: Tally.Palette.textTertiary
        }
    }
}
