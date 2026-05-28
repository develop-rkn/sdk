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
.package(url: "https://github.com/develop-rkn/sdk.git", from: "0.1.0")
```

## Info.plist and entitlements

Add to your app's `Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Used to capture your passport and selfie for identity verification.</string>
```

If your flow includes the NFC step, also add:

```xml
<key>NFCReaderUsageDescription</key>
<string>Used to read your passport chip during verification.</string>
```

…and this entitlement:

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

### 2. Get a client token from your backend

Your backend mints a short-lived token by calling `POST /v1/sessions` on the
Faced deployment with your secret key, then returns the token to the app.
The secret key never lives in the mobile app.

### 3. Present the flow

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

### 4. Handle the result

```swift
func handle(_ result: FacedResult) {
    switch result {
    case .approved(let sessionId):
        // The mobile flow finished. Treat this as informational — the
        // authoritative verdict comes from the webhook your backend
        // receives moments later.
        showSuccessScreen()
    case .needsReview, .rejected:
        showRetryScreen()
    case .canceled:
        break
    case .failed(let error):
        show(error.localizedDescription)
    }
}
```

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
