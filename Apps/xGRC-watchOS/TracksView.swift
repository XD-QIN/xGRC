import CameraKit
import DesignKit
import Persistence
import SwiftUI

/// GPS tracks on the watch: the list and each track's CSV to share. The map
/// of a track is on iPhone and iPad only.
struct TrackListView: View {
    @Environment(AppModel.self) private var model
    @State private var tracks: [TrackFile] = []
    @State private var recording: TrackFile?

    var body: some View {
        List {
            if tracks.isEmpty {
                Text("Every session that geotags keeps its GPS track here. Share one as a CSV file.")
                    .tallyText(.footnote)
                    .foregroundStyle(Tally.Palette.textSecondary)
            }
            ForEach(tracks) { track in
                NavigationLink {
                    TrackDetailView(track: track) { Task { await reload() } }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.name)
                            .tallyText(.footnote)
                            .monospacedDigit()
                        if track == recording {
                            Text("Recording")
                                .tallyText(.footnote)
                                .foregroundStyle(Tally.Palette.location)
                        }
                    }
                }
            }
        }
        .navigationTitle("GPS tracks")
        .task { await reload() }
    }

    private func reload() async {
        let store = model.coordinator.stores.tracks
        tracks = await store.list()
        recording = await store.current()
    }
}

private struct TrackDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let track: TrackFile
    let deleted: () -> Void
    @State private var summary: TrackSummary?
    @State private var confirmDelete = false

    var body: some View {
        List {
            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .tallyText(.footnote)
                    .monospacedDigit()
                Text(summary?.text ?? " ")
                    .tallyText(.footnote)
                    .foregroundStyle(Tally.Palette.textSecondary)
            }
            ShareLink(item: track.url) { Label("Share CSV", systemImage: "square.and.arrow.up") }
            Button("Delete", role: .destructive) { confirmDelete = true }
        }
        .navigationTitle("Track")
        .confirmationDialog("Delete this track?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                Task {
                    try? await model.coordinator.stores.tracks.delete(track)
                    deleted()
                    dismiss()
                }
            }
        }
        .task(id: track) { summary = TrackSummary(await model.coordinator.stores.tracks.rows(of: track)) }
    }
}
