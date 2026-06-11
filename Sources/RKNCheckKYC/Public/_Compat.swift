import Foundation

// MARK: - Deprecated typealiases (FacedKYC → RKN-Check rebrand)
//
// These exist so existing integrations on the previous `FacedKYC` package
// receive a clean migration path: code that still uses `FacedSDK`,
// `FacedConfiguration`, `FacedResult`, `FacedError`, `FacedTheme`, etc.
// continues to compile, but Xcode surfaces a deprecation warning pointing
// at the new RKN-Check-prefixed type to migrate to. We keep these for one
// release (v0.3.x). They are removed in v0.4.0.

@available(*, deprecated, renamed: "RKNCheckSDK", message: "FacedKYC was rebranded to RKN-Check. Use `RKNCheckSDK`. This typealias is removed in v0.4.0.")
public typealias FacedSDK = RKNCheckSDK

@available(*, deprecated, renamed: "RKNCheckConfiguration", message: "FacedKYC was rebranded to RKN-Check. Use `RKNCheckConfiguration`. This typealias is removed in v0.4.0.")
public typealias FacedConfiguration = RKNCheckConfiguration

@available(*, deprecated, renamed: "RKNCheckResult", message: "FacedKYC was rebranded to RKN-Check. Use `RKNCheckResult`. This typealias is removed in v0.4.0.")
public typealias FacedResult = RKNCheckResult

@available(*, deprecated, renamed: "RKNCheckError", message: "FacedKYC was rebranded to RKN-Check. Use `RKNCheckError`. This typealias is removed in v0.4.0.")
public typealias FacedError = RKNCheckError

@available(*, deprecated, renamed: "RKNCheckTheme", message: "FacedKYC was rebranded to RKN-Check. Use `RKNCheckTheme`. This typealias is removed in v0.4.0.")
public typealias FacedTheme = RKNCheckTheme
