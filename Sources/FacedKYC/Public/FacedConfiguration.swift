import Foundation

/// Per-deployment configuration for the Faced SDK.
public struct FacedConfiguration {
    /// Base URL of the Faced deployment, e.g. `https://kyc.acme-bank.com`.
    /// Must include scheme; can include a path prefix if the backend lives
    /// behind a gateway.
    public let host: URL

    /// Optional visual customization. The SDK ships with a neutral default.
    public let theme: FacedTheme

    /// Network timeout for SDK requests in seconds.
    public let networkTimeoutSeconds: TimeInterval

    public init(
        host: URL,
        theme: FacedTheme = .default,
        networkTimeoutSeconds: TimeInterval = 30
    ) {
        self.host = host
        self.theme = theme
        self.networkTimeoutSeconds = networkTimeoutSeconds
    }
}
