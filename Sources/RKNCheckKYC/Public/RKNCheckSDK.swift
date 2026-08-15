import Foundation

/// Modules a client's RKN licence covers, decoded from the licence key set in
/// `RKNCheckConfiguration.licenseKey`. Display-level only: the SDK decodes the
/// key's payload so the app can hide unlicensed flows up front, but signature
/// verification and enforcement happen on the backend — a tampered key just
/// gets its calls refused server-side.
public struct RKNCheckEntitlements {
    /// The client name the licence was issued to.
    public let client: String
    /// Module identifiers the licence covers, e.g. `["screening",
    /// "transactions", "faced", "doc_extraction"]`. `screening` is the base
    /// module and is always present in a well-formed licence.
    public let modules: [String]

    public var includesFaced: Bool { modules.contains("faced") || modules.contains("all") }
    public var includesTransactions: Bool { modules.contains("transactions") || modules.contains("all") }
    public var includesDocumentExtraction: Bool { modules.contains("doc_extraction") || modules.contains("all") }
}

/// One-time configuration for the RKN-Check SDK.
///
/// A fintech configures `RKNCheckSDK` once at app launch with the URL of their
/// RKN-Check backend. No secrets ever ship in the mobile app — the SDK only ever
/// holds short-lived, session-scoped client tokens minted server-side.
public enum RKNCheckSDK {

    /// Configure the SDK. Call this once, typically from your `AppDelegate`
    /// or SwiftUI `App` initializer.
    ///
    /// - Parameter configuration: Hostname of the RKN-Check deployment plus any
    ///   optional overrides (theme, locale).
    public static func configure(_ configuration: RKNCheckConfiguration) {
        RKNCheckRuntime.shared.configure(configuration)
    }

    /// The configuration that's currently in effect, if any.
    public static var currentConfiguration: RKNCheckConfiguration? {
        RKNCheckRuntime.shared.configuration
    }

    /// SDK version string included in user-agent headers.
    public static let version: String = "0.3.0"

    /// Returns `true` once `configure(_:)` has been called.
    public static var isConfigured: Bool {
        RKNCheckRuntime.shared.configuration != nil
    }

    /// Entitlements decoded from the configured licence key, or `nil` when no
    /// key is set or the key is malformed. Use this to hide flows the client
    /// didn't buy (e.g. skip the biometric step when `includesFaced` is
    /// false) instead of letting the user hit a server refusal mid-flow.
    public static var entitlements: RKNCheckEntitlements? {
        guard let key = RKNCheckRuntime.shared.configuration?.licenseKey else { return nil }
        return decodeEntitlements(from: key)
    }

    /// Decode a licence key's payload without verifying its signature (the
    /// backend does that). `RKN1.<base64url payload>.<signature>`.
    static func decodeEntitlements(from key: String) -> RKNCheckEntitlements? {
        let parts = key.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".")
        guard parts.count == 3, parts[0] == "RKN1" else { return nil }
        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard
            let data = Data(base64Encoded: b64),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let client = object["client"] as? String,
            let modules = object["modules"] as? [String]
        else { return nil }
        return RKNCheckEntitlements(client: client, modules: modules)
    }

    /// Verifies that the configured host is reachable and responds like a
    /// RKN-Check backend. Throws a `RKNCheckError` describing exactly what's wrong
    /// (DNS failure, ATS, missing local-network permission, TLS, etc.).
    ///
    /// Call this from your launch path or just before showing your "Start
    /// verification" button. If it throws, surface the message and disable
    /// the entry point — much better UX than letting the user tap Start and
    /// then hit the failure inside the SDK's modal.
    public static func preflight() async throws {
        guard let configuration = RKNCheckRuntime.shared.configuration else {
            throw RKNCheckError.notConfigured
        }

        var request = URLRequest(url: configuration.host.appendingPathComponent("health"))
        request.httpMethod = "GET"
        request.timeoutInterval = min(configuration.networkTimeoutSeconds, 10)
        request.setValue("RKNCheckKYC-iOS/\(version)", forHTTPHeaderField: "User-Agent")

        let session = URLSession(configuration: .ephemeral)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw RKNCheckError.network(urlError)
        } catch {
            throw RKNCheckError.internalError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw RKNCheckError.internalError("Health check did not return an HTTP response.")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RKNCheckError.server(statusCode: http.statusCode, message: body)
        }
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            object["status"] as? String == "ok"
        else {
            throw RKNCheckError.internalError("Configured host did not respond with a RKN-Check-shaped /health payload.")
        }
    }
}
