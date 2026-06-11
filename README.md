# RKN-Check iOS SDK

Passport-based identity verification for iOS apps: document capture, MRZ
scan, optional NFC chip read, and active liveness — all driven by the
RKN platform.

> **Rebranded from FacedKYC.** v0.3.0 renames the package and public types
> to RKN-Check. Existing code using `FacedSDK`, `FacedConfiguration`,
> `FacedResult`, `FacedError`, `FacedTheme` continues to compile with
> deprecation warnings; replace each with its `RKNCheck…` counterpart
> when convenient. The deprecated typealiases are removed in v0.4.0.

## Requirements

- iOS 16 or later
- Xcode 15 or later
- An RKN platform deployment URL (`https://<your-rkn-host>/biometrics`)
  and a short-lived client token minted by your backend through the
  RKN platform's API

## Installation

Swift Package Manager. In Xcode: **File → Add Package Dependencies…**

```
https://github.com/develop-rkn/rkn-check-ios-sdk.git
```

Or in `Package.swift`:

```swift
.package(url: "https://github.com/develop-rkn/rkn-check-ios-sdk.git", from: "0.3.0")
```

## Info.plist

Always required:

```xml
<key>NSCameraUsageDescription</key>
<string>Used to capture your passport and selfie for identity verification.</string>
```

Required only when your flow includes the NFC step:

```xml
<key>NFCReaderUsageDescription</key>
<string>Used to read your passport chip during verification.</string>
```

Required only when your `host` is on a **private IP** (`10.x`, `172.16.x–172.31.x`, `192.168.x`) — typical for dev/staging:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Used to reach the verification backend on your local network.</string>
```

Required only when your `host` is **plain HTTP** or uses a self-signed cert — also typical for dev/staging. Production hosts should use HTTPS with a trusted cert and skip this entirely:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <!-- Either allow the specific host: -->
    <key>NSExceptionDomains</key>
    <dict>
        <key>10.0.0.42</key>
        <dict>
            <key>NSExceptionAllowsInsecureHTTPLoads</key><true/>
            <key>NSIncludesSubdomains</key><true/>
        </dict>
    </dict>
    <!-- …or for dev only, allow local-network HTTP entirely: -->
    <key>NSAllowsLocalNetworking</key><true/>
</dict>
```

## Entitlements

Required only when your flow includes the NFC step:

```xml
<key>com.apple.developer.nfc.readersession.formats</key>
<array>
    <string>TAG</string>
</array>
```

## Quickstart

### 1. Configure once at launch

```swift
import RKNCheckKYC

@main
struct MyApp: App {
    init() {
        RKNCheckSDK.configure(
            RKNCheckConfiguration(host: URL(string: "https://api.your-rkn-host.com/biometrics")!)
        )
    }
    var body: some Scene { WindowGroup { ContentView() } }
}
```

`host` is the RKN platform's biometrics path that your operator provides
you. **It is required at construction with no default** — the SDK will
not compile if you omit it. This is intentional: it stops anyone from
shipping a release tag with the deployment FQDN baked in as a fallback.

### 2. (Optional but recommended) Preflight on launch

```swift
.task {
    do {
        try await RKNCheckSDK.preflight()
        startButtonIsEnabled = true
    } catch {
        startButtonIsEnabled = false
        configError = (error as? RKNCheckError)?.localizedDescription
    }
}
```

`preflight()` calls `GET /health` against the configured host with a 10-second
timeout. It throws a precise `RKNCheckError` (DNS / ATS / local network /
TLS / non-RKN-Check response) so misconfigurations surface before the user
taps Start.

### 3. Get a client token from your backend

Your backend mints a short-lived token by calling `POST /v1/verification-sessions`
on the RKN platform with your API key, then returns the token to the app.
The API key never lives in the mobile app. Tokens are valid for ~15 minutes
in production (24 h in UAT) — request a fresh one for each verification attempt.

### 4. Present the flow

**SwiftUI:**

```swift
.rknCheckVerification(
    isPresented: $showVerification,
    clientToken: token,
    onResult: handle
)
```

**UIKit:**

```swift
RKNCheckVerification(clientToken: token, onResult: handle)
    .present(from: self)
```

### 5. Handle the result

`RKNCheckResult` carries useful payload on every case:

```swift
public enum RKNCheckResult: Equatable {
    case approved(sessionId: String)
    case needsReview(sessionId: String, reason: String?)
    case rejected(sessionId: String, reason: String?)
    case canceled(sessionId: String?)
    case failed(error: RKNCheckError)
}
```

Typical handling:

```swift
func handle(_ result: RKNCheckResult) {
    switch result {
    case .approved(let sessionId):
        // The verdict you see here matches what the RKN platform persisted on
        // the customer record in the same request cycle. The authoritative
        // copy is on the RKN side; treat this as the SDK's confirmation that
        // the user finished the flow with a successful identity check.
        analytics.log("kyc.mobile_approved", ["sessionId": sessionId])

    case .needsReview(let sessionId, let reason),
         .rejected(let sessionId, let reason):
        analytics.log("kyc.not_approved", [
            "sessionId": sessionId,
            "reason": reason ?? "unspecified"
        ])
        showRetryScreen()

    case .canceled(let sessionId):
        analytics.log("kyc.canceled", ["sessionId": sessionId ?? "—"])

    case .failed(let error):
        show(error.localizedDescription)
    }
}
```

### Errors worth branching on

`RKNCheckError` is a closed enum so you can switch exhaustively:

```swift
case .clientTokenExpired(let expiredAt):
    // Mint a new token server-side and retry.
case .clientTokenUnauthorized, .clientTokenMalformed:
    // Backend signing key changed, or someone tampered with the token.
case .network(let urlError):
    // Inspect urlError.code for the specific URLSession reason.
case .server(let statusCode, _):
    // Backend reachable but unhappy. Likely a deploy issue.
case .notConfigured, .permissionDenied, .unsupportedDevice, .internalError:
    break
}
```

For `.network`, `URLError.code` tells you what's actually wrong —
`.notConnectedToInternet` on a private-IP host almost always means
`NSLocalNetworkUsageDescription` is missing; `.appTransportSecurityRequiresSecureConnection`
means ATS blocked an HTTP request.

## Theming

```swift
RKNCheckSDK.configure(
    RKNCheckConfiguration(
        host: URL(string: "https://api.your-rkn-host.com/biometrics")!,
        theme: RKNCheckTheme(accentColor: .blue)
    )
)
```

The theme styles the SDK's prompt screens. Camera previews and capture
overlays use neutral system colors so they read correctly under any brand.

## Sample app

A complete working integration is in
[`Examples/SampleApp/AcmeBankApp.swift`](Examples/SampleApp/AcmeBankApp.swift).

## Migration from FacedKYC (v0.2.x → v0.3.0)

1. Update the package URL in your `Package.swift` from
   `https://github.com/develop-rkn/sdk.git` to
   `https://github.com/develop-rkn/rkn-check-ios-sdk.git` (the old URL
   still resolves via GitHub's repo-rename redirect, but the new one is
   canonical going forward).
2. Bump the version constraint to `from: "0.3.0"`.
3. Change `import FacedKYC` to `import RKNCheckKYC`.
4. Rename references: `FacedSDK` → `RKNCheckSDK`, `FacedConfiguration` →
   `RKNCheckConfiguration`, `FacedResult` → `RKNCheckResult`, `FacedError`
   → `RKNCheckError`, `FacedTheme` → `RKNCheckTheme`. Deprecated typealiases
   on the old names keep your code compiling during the migration but
   surface warnings in Xcode.
5. Replace the SwiftUI presenter `.facedVerification(…)` with `.rknCheckVerification(…)`,
   and the UIKit one `FacedVerification(…)` with `RKNCheckVerification(…)`.

There are no behavioural changes between v0.2.x and v0.3.0 — only renames.
The wire format, host requirements, and Info.plist requirements are
unchanged.

## License

MIT — see [LICENSE](LICENSE).
