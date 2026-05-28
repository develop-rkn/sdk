import Foundation

/// Terminal outcome the SDK reports back to the host app.
///
/// Treat `.approved` as informational only — the **authoritative** verdict
/// always comes from the webhook that the Faced backend POSTs to your server
/// at the end of the session.
public enum FacedResult: Equatable {
    case approved(sessionId: String)
    case needsReview(sessionId: String, reason: String?)
    case rejected(sessionId: String, reason: String?)
    case canceled(sessionId: String?)
    case failed(error: FacedError)

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

/// Errors surfaced by the SDK to the host app. Detailed diagnostics live
/// server-side; the SDK only reports user-actionable categories.
public enum FacedError: Error, Equatable {
    case notConfigured
    case invalidClientToken
    case network(String)
    case permissionDenied(String)
    case unsupportedDevice(String)
    case internalError(String)

    public var localizedDescription: String {
        switch self {
        case .notConfigured:
            return "Faced SDK has not been configured. Call FacedSDK.configure(_:) at launch."
        case .invalidClientToken:
            return "The client token is missing, malformed, or has expired."
        case .network(let message):
            return "Network error: \(message)"
        case .permissionDenied(let message):
            return "Permission denied: \(message)"
        case .unsupportedDevice(let message):
            return "Unsupported device: \(message)"
        case .internalError(let message):
            return message
        }
    }
}
