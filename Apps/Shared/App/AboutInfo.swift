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

    /// Computed, not stored, so the titles follow a language change in Settings.
    static var links: [Link] {
        [
            Link(title: String(localized: "Privacy Policy"), url: URL(string: "https://xdqin.com/xGRC/privacy-policy")!,
                 showsHost: false),
            Link(title: String(localized: "User Agreement"), url: URL(string: "https://xdqin.com/xGRC/user-agreement")!,
                 showsHost: false),
            Link(title: String(localized: "Developer"), url: URL(string: "https://xdqin.com")!),
        ]
    }

    /// The source code. About lists it last, after the License row, with the
    /// open-source note below it.
    static var sourceLink: Link {
        Link(title: String(localized: "GitHub"), url: URL(string: "https://github.com/XD-QIN/xGRC")!)
    }

    // MARK: - License

    /// Beside the License row.
    static let licenseName = "GPLv3"

    /// Below the GitHub link: what the GPL means for commercial use.
    static var openSourceNote: String {
        String(localized: "xGRC is open source under the GNU GPL v3. You may use it commercially, but if you distribute xGRC or a work based on it, you must license it under GPLv3 and make its complete source code available. xGRC comes with no warranty.")
    }

    /// Where the license is published, in case the bundled copy is missing.
    static let licenseURL = URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!

    /// The repository's LICENSE, which project.yml copies into both apps, as
    /// paragraphs with the hard line breaks taken out so the text wraps to the
    /// screen. In English: the only version of the GPL that binds.
    static let licenseParagraphs: [String] = {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: nil),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.components(separatedBy: "\n\n").compactMap { paragraph in
            let lines = paragraph.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            let joined = lines.filter { !$0.isEmpty }.joined(separator: " ")
            return joined.isEmpty ? nil : joined
        }
    }()
}
