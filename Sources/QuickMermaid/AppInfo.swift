import Foundation

/// Bundle identity shown to the user (name, version) and whether this is a local dev build.
///
/// A dev build is one whose version was never injected: release builds (CI /
/// `release.sh`) set `CFBundleShortVersionString` before `build.sh` runs, so only a
/// plain local `./build.sh` keeps the `0.0.0` placeholder from the source Info.plist.
/// `build.sh` stamps such builds with the git commit (`QMBuildCommit`) so a running
/// dev copy can be traced back to the source it was built from.
enum AppInfo {
    static let name = "QuickMermaid"
    private static let devVersion = "0.0.0"

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? devVersion
    }

    static var isDevBuild: Bool { version == devVersion }

    private static var buildCommit: String? {
        Bundle.main.infoDictionary?["QMBuildCommit"] as? String
    }

    /// Version as displayed in Settings: `1.2.0`, or `0.0.0 (Dev build · abc1234)`.
    static var displayVersion: String {
        guard isDevBuild else { return version }
        let tag = [L10n.t("app.devBuild"), buildCommit].compactMap { $0 }.joined(separator: " · ")
        return "\(version) (\(tag))"
    }

    /// App name as displayed in the menu: `QuickMermaid`, or `QuickMermaid (Dev build)`.
    static var displayName: String {
        isDevBuild ? "\(name) (\(L10n.t("app.devBuild")))" : name
    }
}
