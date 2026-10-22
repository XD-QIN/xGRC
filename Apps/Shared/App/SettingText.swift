import Foundation
import Persistence

/// Setting names and values, worded the same on the watch and the phone.
extension SessionMode {
    var title: String {
        switch self {
        case .remoteAndGeotag: String(localized: "Remote + Geotag")
        case .remoteOnly: String(localized: "Remote only")
        case .geotagOnly: String(localized: "Geotag only")
        }
    }

    var detail: String {
        switch self {
        case .remoteAndGeotag: String(localized: "Shutter and location together.")
        case .remoteOnly: String(localized: "Shutter only. Location is not used.")
        case .geotagOnly: String(localized: "Location starts with the session. The camera's remote setting can stay off.")
        }
    }

    var systemImage: String {
        switch self {
        case .remoteAndGeotag: "camera.badge.ellipsis"
        case .remoteOnly: "camera"
        case .geotagOnly: "location"
        }
    }
}

extension AppearanceSetting {
    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }
}

enum SettingText {
    static let autoDisconnectOptions = [0, 5, 10, 15, 20, 30, 45, 60]

    static func autoDisconnect(_ minutes: Int) -> String {
        minutes == 0 ? String(localized: "Never") : String(localized: "After \(minutes) min")
    }

    /// "1 push", "142 pushes": locations sent to the camera.
    static func pushes(_ count: Int) -> String {
        count == 1 ? String(localized: "1 push") : String(localized: "\(count) pushes")
    }

    static func delay(_ seconds: Int) -> String {
        seconds == 0 ? String(localized: "Off") : "\(seconds) s"
    }

    /// The longest bulb time, "99 min 59 s".
    static var bulbLimit: String { bulb(AppSettings.maxBulbSeconds) }

    /// Minutes and seconds typed or turned separately, as a bulb time in
    /// seconds: seconds past 59 carry into minutes, and the total stops at
    /// the limit. 0 = Off.
    static func bulbSeconds(minutes: Int, seconds: Int) -> Int {
        min(max(minutes, 0) * 60 + max(seconds, 0), AppSettings.maxBulbSeconds)
    }

    static func bulb(_ seconds: Int) -> String {
        switch seconds {
        case ...0: String(localized: "Off")
        case ..<60: "\(seconds) s"
        case _ where seconds % 60 == 0: String(localized: "\(seconds / 60) min")
        default: String(localized: "\(seconds / 60) min \(seconds % 60) s")
        }
    }
}
