import CameraKit
import DesignKit
import MapKit
import Persistence
import SwiftUI

/// GPS tracks: one per session that geotagged, newest first, named by the
/// session's start time. A track opens on a map of its fixes and shots; each exports as
/// its CSV file.
struct TrackListView: View {
    @Environment(AppModel.self) private var model
    @State private var tracks: [TrackFile] = []
    @State private var recording: TrackFile?
    /// An App Store screenshot run opens the newest track's map.
    @State private var opened: TrackFile?

    var body: some View {
        List {
            if tracks.isEmpty {
                Text("Every session that geotags keeps its GPS track here, with a time for each fix. Open one to see it on a map, or export it as a CSV file.")
                    .tallyText(.footnote)
                    .foregroundStyle(Tally.Palette.textSecondary)
            }
            ForEach(tracks) { track in
                NavigationLink {
                    TrackMapView(track: track)
                } label: {
                    TrackRow(track: track, isRecording: track == recording)
                }
                .contextMenu {
                    ShareLink(item: track.url) { Label("Export CSV", systemImage: "square.and.arrow.up") }
                }
            }
            .onDelete { offsets in
                let doomed = offsets.map { tracks[$0] }
                Task {
                    for track in doomed { try? await model.coordinator.stores.tracks.delete(track) }
                    await reload()
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Tally.Palette.background)
        .navigationTitle("GPS tracks")
        .toolbar {
            if !tracks.isEmpty { EditButton() }
        }
        .task {
            await reload()
            if StoreScreens.scene == "track" { opened = tracks.last }
        }
        .refreshable { await reload() }
        .navigationDestination(item: $opened) { TrackMapView(track: $0) }
    }

    private func reload() async {
        let store = model.coordinator.stores.tracks
        tracks = await store.list()
        recording = await store.current()
    }
}

private struct TrackRow: View {
    @Environment(AppModel.self) private var model
    let track: TrackFile
    let isRecording: Bool
    @State private var summary: TrackSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(track.name)
                .tallyText(.readoutS)
                .foregroundStyle(Tally.Palette.textPrimary)
            HStack(spacing: Tally.Space.xs) {
                if isRecording {
                    Text("Recording")
                        .fontWeight(.semibold)
                        .foregroundStyle(Tally.Palette.location)
                }
                Text(summary?.text ?? " ")
                    .foregroundStyle(Tally.Palette.textSecondary)
            }
            .tallyText(.footnote)
        }
        .frame(minHeight: Tally.Target.minimum)
        .task(id: track) { summary = TrackSummary(await model.coordinator.stores.tracks.rows(of: track)) }
    }
}

/// A track on the map: a blue dot for each fix, an orange one where the
/// remote shutter fired, and the CSV to export.
struct TrackMapView: View {
    @Environment(AppModel.self) private var model
    let track: TrackFile
    @State private var rows: [TrackPoint] = []
    @State private var position: MapCameraPosition = .automatic

    /// MapKit draws a few thousand overlays smoothly; a longer track shows
    /// every n-th fix (the CSV keeps them all). Shots are always shown.
    private static let maximumDots = 4000

    var body: some View {
        let fixes = rows.filter { !$0.isShot }.map(\.fix)
        let shots = rows.filter(\.isShot).map(\.fix)
        let radius = Self.dotRadius(rows.map(\.fix))
        let dots = Self.thinned(fixes)
        Map(position: $position) {
            ForEach(dots.indices, id: \.self) { index in
                MapCircle(center: dots[index], radius: radius)
                    .foregroundStyle(Tally.Palette.location)
            }
            // On top, and the same size at every zoom, so a shot is never
            // lost among fixes. A track has far fewer shots than fixes.
            ForEach(shots.indices, id: \.self) { index in
                Annotation("Shot", coordinate: Self.coordinate(shots[index]), anchor: .center) {
                    Circle()
                        .fill(Tally.Palette.pending)
                        .stroke(Tally.Palette.background, lineWidth: 1.5)
                        .frame(width: 11, height: 11)
                }
                .annotationTitles(.hidden)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !rows.isEmpty {
                HStack(spacing: Tally.Space.s) {
                    Text(TrackSummary(rows).text)
                    if !shots.isEmpty {
                        Legend(color: Tally.Palette.location, text: "GPS")
                        Legend(color: Tally.Palette.pending, text: String(localized: "Shot"))
                    }
                }
                .tallyText(.subheadline)
                .foregroundStyle(Tally.Palette.textPrimary)
                .padding(.horizontal, Tally.Space.m)
                .padding(.vertical, Tally.Space.xs)
                .background(Tally.Palette.surface, in: Capsule())
                .padding(.bottom, Tally.Space.s)
            }
        }
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView("No fixes yet", systemImage: "location",
                                       description: Text("This track has no position to show."))
            }
        }
        .navigationTitle(track.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: track.url) { Label("Export CSV", systemImage: "square.and.arrow.up") }
            }
        }
        .task(id: track) {
            rows = await model.coordinator.stores.tracks.rows(of: track)
            position = .automatic
        }
    }

    private static func coordinate(_ fix: GeoFix) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: fix.latitude, longitude: fix.longitude)
    }

    private static func thinned(_ fixes: [GeoFix]) -> [CLLocationCoordinate2D] {
        let step = max(1, (fixes.count + maximumDots - 1) / maximumDots)
        return stride(from: 0, to: fixes.count, by: step).map { coordinate(fixes[$0]) }
    }

    /// Dots in metres, sized to the track so they read as dots at the zoom
    /// that fits it: 1/500 of its extent, between 1.5 m and 60 m.
    private static func dotRadius(_ fixes: [GeoFix]) -> CLLocationDistance {
        guard let first = fixes.first else { return 5 }
        var south = first.latitude, north = first.latitude, west = first.longitude, east = first.longitude
        for fix in fixes {
            south = min(south, fix.latitude)
            north = max(north, fix.latitude)
            west = min(west, fix.longitude)
            east = max(east, fix.longitude)
        }
        let extent = MKMapPoint(CLLocationCoordinate2D(latitude: south, longitude: west))
            .distance(to: MKMapPoint(CLLocationCoordinate2D(latitude: north, longitude: east)))
        return min(max(extent / 500, 1.5), 60)
    }
}

/// A coloured dot and what it marks.
private struct Legend: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: Tally.Space.xxs) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(verbatim: text)
        }
        .accessibilityElement(children: .combine)
    }
}
