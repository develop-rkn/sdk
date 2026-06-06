import Foundation

/// Per-deployment configuration for the RKN-Check SDK.
public struct RKNCheckConfiguration {
    /// Base URL of the RKN-Check deployment, e.g. `https://kyc.acme-bank.com`.
    /// Must include scheme; can include a path prefix if the backend lives
    /// behind a gateway.
    public let host: URL

    /// Optional visual customization. The SDK ships with a neutral default.
    public let theme: RKNCheckTheme

    /// Network timeout for SDK requests in seconds.
    public let networkTimeoutSeconds: TimeInterval

    public init(
        host: URL,
        theme: RKNCheckTheme = .default,
        networkTimeoutSeconds: TimeInterval = 30
    ) {
        self.host = host
        self.theme = theme
        self.networkTimeoutSeconds = networkTimeoutSeconds
    }
}
