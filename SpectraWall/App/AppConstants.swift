import Foundation

enum AppConstants {
    static let appName = "SpectraWall"
    static let bundleId = "com.spectrawall.app"

    static let author = "Giggs Lynx"
    static let license = "MIT"
    static let githubURLString = "https://github.com/giggs-lynx/SpectraWall"
    static var githubURL: URL? { URL(string: githubURLString) }

    static var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}
