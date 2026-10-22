import Foundation

/// What Settings › About shows, the same on the watch and the phone.
enum AboutInfo {
    /// "1.0.0 (1)": the marketing version and the build.
    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        guard let build = info?["CFBundleVersion"] as? String else { return short }
        return "\(short) (\(build))"
    }

    struct Link: Identifiable {
        let title: String
        let url: URL
        /// The site's name beside the title. The legal pages are links only.
        var showsHost = true
        var id: URL { url }
    }

    static let links: [Link] = [
        Link(title: String(localized: "Privacy Policy"), url: URL(string: "https://xdqin.com/xGRC/privacy-policy")!,
             showsHost: false),
        Link(title: String(localized: "User Agreement"), url: URL(string: "https://xdqin.com/xGRC/user-agreement")!,
             showsHost: false),
        Link(title: String(localized: "Developer"), url: URL(string: "https://xdqin.com")!),
        Link(title: String(localized: "GitHub"), url: URL(string: "https://github.com/XD-QIN/xGRC")!),
    ]
}
