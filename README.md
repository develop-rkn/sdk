# FacedKYC

Passport-based identity verification for iOS apps: document capture, MRZ
scan, optional NFC chip read, and active liveness — all driven by your
Faced backend.

## Requirements

- iOS 16 or later
- Xcode 15 or later
- A Faced deployment URL and a client token minted by your backend

## Installation

Swift Package Manager. In Xcode: **File → Add Package Dependencies…**

```
https://github.com/develop-rkn/sdk.git
```

Or in `Package.swift`:

```swift
.package(url: "https://github.com/develop-rkn/sdk.git", from: "0.2.0")
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
import FacedKYC

@main
struct MyApp: App {
    init() {
        FacedSDK.configure(
            FacedConfiguration(host: URL(string: "https://kyc.your-bank.com")!)
        )
    }
    var body: some Scene { WindowGroup { ContentView() } }
}
```

### 2. (Optional but recommended) Preflight on launch

```swift
.task {
    do {
        try await FacedSDK.preflight()
        startButtonIsEnabled = true
    } catch {
        startButtonIsEnabled = false
        configError = (error as? FacedError)?.localizedDescription
    }
}
```

`preflight()` calls `GET /health` against the configured host with a 10-second
timeout. It throws a precise `FacedError` (DNS / ATS / local network /
TLS / non-Faced response) so misconfigurations surface before the user taps
Start.

### 3. Get a client token from your backend

Your backend mints a short-lived token by calling `POST /v1/sessions` on the
Faced deployment with your secret key, then returns the token to the app.
The secret key never lives in the mobile app. Tokens are valid for ~15 minutes
by default — request a fresh one for each verification attempt.

### 4. Present the flow

**SwiftUI:**

```swift
.facedVerification(
    isPresented: $showVerification,
    clientToken: token,
    onResult: handle
)
```

**UIKit:**

```swift
FacedVerification(clientToken: token, onResult: handle)
    .present(from: self)
```

### 5. Handle the result

`FacedResult` carries useful payload on every case:

```swift
public enum FacedResult: Equatable {
    case approved(sessionId: String)
    case needsReview(sessionId: String, reason: String?)
    case rejected(sessionId: String, reason: String?)
    case canceled(sessionId: String?)
    case failed(error: FacedError)
}
```

Typical handling:

```swift
func handle(_ result: FacedResult) {
    switch result {
    case .approved(let sessionId):
        // Mobile flow finished. The webhook your backend receives moments
        // later is the authoritative verdict — treat this as informational.
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

`FacedError` is a closed enum so you can switch exhaustively:

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
FacedSDK.configure(
    FacedConfiguration(
        host: URL(string: "https://kyc.your-bank.com")!,
        theme: FacedTheme(accentColor: .blue)
    )
)
```

The theme styles the SDK's prompt screens. Camera previews and capture
overlays use neutral system colors so they read correctly under any brand.

## Sample app

A complete working integration is in
[`Examples/SampleApp/AcmeBankApp.swift`](Examples/SampleApp/AcmeBankApp.swift).

## License

MIT — see [LICENSE](LICENSE).
