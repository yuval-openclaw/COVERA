import Foundation

/// Where the legal pages live, and which version of them the user agreed to.
///
/// The address comes from `CoveraLegalBaseURL` in Info.plist (set in
/// `project.yml`) so moving to a custom domain is a one-line change. The pages
/// themselves are in `site/`.
enum Legal {
    /// The date of the privacy policy and terms the consent screen refers to.
    /// Bump it when either changes in a way that needs fresh consent: everyone
    /// sees the consent screen again, and the server records the new version.
    static let version = "2026-09-21"

    static var baseURL: URL {
        if let value = Bundle.main.object(forInfoDictionaryKey: "CoveraLegalBaseURL") as? String,
           let url = URL(string: value), url.scheme == "https" {
            return url
        }
        return URL(string: "https://covera-legal.vercel.app")!
    }

    static var privacy: URL { baseURL.appendingPathComponent("privacy.html") }
    static var terms: URL { baseURL.appendingPathComponent("terms.html") }
    static var healthData: URL { baseURL.appendingPathComponent("health-data.html") }
}
