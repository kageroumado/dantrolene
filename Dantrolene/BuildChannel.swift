import Foundation

/// Which distribution channel this binary was built for.
///
/// Both channels ship the same marketing version in lockstep (App Store Connect rejects
/// non-numeric version strings, so the channel must never be encoded in the version); the
/// binary itself is the differentiator. The channel is surfaced in the popover footer and
/// the launch log so support screenshots and log excerpts identify the edition.
enum BuildChannel {
    #if APPSTORE
    static let name: String? = "App Store"
    #else
    static let name: String? = nil
    #endif

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    /// "1.2 (App Store)" on the App Store channel, "1.2" on direct distribution.
    static var description: String {
        name.map { "\(version) (\($0))" } ?? version
    }
}
