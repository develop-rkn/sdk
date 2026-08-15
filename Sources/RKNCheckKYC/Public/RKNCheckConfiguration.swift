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

    /// The RKN licence key the fintech received with its contract
    /// (`RKN1.<payload>.<signature>`). ONE key encodes every module the
    /// client bought — screening, transactions, faced biometrics, document
    /// extraction. When set, the SDK sends it as `X-RKN-License` on every
    /// backend call and exposes the decoded entitlements via
    /// `RKNCheckSDK.entitlements`, so the app can hide flows the licence
    /// doesn't cover before the backend refuses them. The key is NOT a
    /// secret (it's signed, not encrypted, and grants nothing by itself),
    /// so shipping it in the app is safe; the backend remains the enforcer.
    public let licenseKey: String?

    public init(
        host: URL,
        theme: RKNCheckTheme = .default,
        networkTimeoutSeconds: TimeInterval = 30,
        licenseKey: String? = nil
    ) {
        self.host = host
        self.theme = theme
        self.networkTimeoutSeconds = networkTimeoutSeconds
        self.licenseKey = licenseKey
    }
}
