import Foundation

/// Terminal outcome the SDK reports back to the host app.
///
/// Treat `.approved` as informational only — the **authoritative** verdict
/// always comes from the webhook that the RKN-Check backend POSTs to your server
/// at the end of the session.
public enum RKNCheckResult: Equatable {
    case approved(sessionId: String)
    case needsReview(sessionId: String, reason: String?)
    case rejected(sessionId: String, reason: String?)
    case canceled(sessionId: String?)
    case failed(error: RKNCheckError)

    public var sessionId: String? {
        switch self {
        case .approved(let id):
            return id
        case .needsReview(let id, _):
            return id
        case .rejected(let id, _):
            return id
        case .canceled(let id):
            return id
        case .failed:
            return nil
        }
    }
}

/// Errors surfaced by the SDK.
///
/// The cases are deliberately narrow so integrators can branch on them. For
/// `.network`, inspect `URLError.code` (e.g. `.notConnectedToInternet`,
/// `.cannotConnectToHost`, `.appTransportSecurityRequiresSecureConnection`)
/// to give the user actionable guidance.
public enum RKNCheckError: Error, Equatable {
    /// `RKNCheckSDK.configure(_:)` was never called.
    case notConfigured

    /// Client token is not a parseable RKN-Check token.
    case clientTokenMalformed

    /// Client token's signed `exp` claim has already passed.
    case clientTokenExpired(expiredAt: Date)

    /// The backend rejected the client token (signature mismatch, revoked, etc.).
    case clientTokenUnauthorized

    /// Transport-layer failure. Inspect the wrapped `URLError.code` for the
    /// specific reason — `.notConnectedToInternet` on a private-range host
    /// usually means the app is missing `NSLocalNetworkUsageDescription`.
    case network(URLError)

    /// The backend returned an HTTP error other than 401/403.
    case server(statusCode: Int, message: String)

    /// A required user permission (camera, NFC, local network) was denied.
    case permissionDenied(String)

    /// The device is missing a hardware capability the flow needs.
    case unsupportedDevice(String)

    /// Anything else — usually a programming bug. Please report.
    case internalError(String)

    public var localizedDescription: String {
        switch self {
        case .notConfigured:
            return "RKN-Check SDK has not been configured. Call RKNCheckSDK.configure(_:) at launch."
        case .clientTokenMalformed:
            return "The client token is malformed."
        case .clientTokenExpired(let expiredAt):
            return "The client token expired at \(expiredAt). Mint a new one server-side."
        case .clientTokenUnauthorized:
            return "The backend rejected the client token."
        case .network(let urlError):
            return Self.describe(urlError)
        case .server(let statusCode, let message):
            return "Backend returned HTTP \(statusCode): \(message)"
        case .permissionDenied(let message):
            return "Permission denied: \(message)"
        case .unsupportedDevice(let message):
            return "Unsupported device: \(message)"
        case .internalError(let message):
            return message
        }
    }

    private static func describe(_ urlError: URLError) -> String {
        switch urlError.code {
        case .notConnectedToInternet:
            return "The phone reports no internet connectivity. If your RKN-Check host is on a private IP (10.x / 172.16-31.x / 192.168.x), make sure the app has NSLocalNetworkUsageDescription in Info.plist and that local-network permission was granted."
        case .cannotConnectToHost:
            return "Could not reach the RKN-Check host. Check the URL and that the backend is running."
        case .timedOut:
            return "The request to the RKN-Check host timed out."
        case .appTransportSecurityRequiresSecureConnection:
            return "App Transport Security blocked the request. If your host is HTTP, add an NSAppTransportSecurity exception in Info.plist."
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot:
            return "TLS handshake with the RKN-Check host failed: \(urlError.localizedDescription)"
        case .cannotFindHost:
            return "DNS lookup failed for the RKN-Check host. Check the URL."
        default:
            return "Network error: \(urlError.localizedDescription) (URLError.code \(urlError.code.rawValue))"
        }
    }
}
