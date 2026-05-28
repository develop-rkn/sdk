import Foundation

/// One-time configuration for the Faced SDK.
///
/// A fintech configures `FacedSDK` once at app launch with the URL of their
/// Faced backend. No secrets ever ship in the mobile app — the SDK only ever
/// holds short-lived, session-scoped client tokens minted server-side.
public enum FacedSDK {

    /// Configure the SDK. Call this once, typically from your `AppDelegate`
    /// or SwiftUI `App` initializer.
    ///
    /// - Parameter configuration: Hostname of the Faced deployment plus any
    ///   optional overrides (theme, locale).
    public static func configure(_ configuration: FacedConfiguration) {
        FacedRuntime.shared.configure(configuration)
    }

    /// The configuration that's currently in effect, if any.
    public static var currentConfiguration: FacedConfiguration? {
        FacedRuntime.shared.configuration
    }

    /// SDK version string included in user-agent headers.
    public static let version: String = "0.1.0"

    /// Returns `true` once `configure(_:)` has been called.
    public static var isConfigured: Bool {
        FacedRuntime.shared.configuration != nil
    }
}
