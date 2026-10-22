import CameraKit
import Foundation
import Persistence

/// What the track list and a track's screen say about a GPS track, the same
/// on the watch and the phone: "128 points · 12 shots · 12 min".
struct TrackSummary: Equatable {
    /// Fix rows.
    let points: Int
    /// Remote shots marked on the track.
    let shots: Int
    let duration: TimeInterval

    init(_ rows: [TrackPoint]) {
        shots = rows.filter(\.isShot).count
        points = rows.count - shots
        if let first = rows.first?.fix.timestamp, let last = rows.last?.fix.timestamp {
            duration = max(last.timeIntervalSince(first), 0)
        } else {
            duration = 0
        }
    }

    var text: String {
        var parts = [points == 1 ? String(localized: "1 point") : String(localized: "\(points) points")]
        if shots > 0 {
            parts.append(shots == 1 ? String(localized: "1 shot") : String(localized: "\(shots) shots"))
        }
        parts.append(Self.duration(duration))
        return parts.joined(separator: " · ")
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        switch total {
        case ..<60: return "\(total) s"
        case ..<3600: return String(localized: "\(total / 60) min")
        default: return String(localized: "\(total / 3600) h \(total % 3600 / 60) min")
        }
    }
}

extension TrackStore {
    /// A track's rows, or none when the file cannot be read.
    func rows(of track: TrackFile) -> [TrackPoint] {
        (try? points(of: track)) ?? []
    }
}
