import Foundation

/// One-time configuration for the Faced SDK.
///
/// A fintech configures `FacedSDK` once at app launch with the URL of their
/// Faced backend. No secrets ever ship in the mobile app — the SDK only ever
/// holds short-lived, session-scoped client tokens minted server-side.
public enum FacedSDK {

    /// Configure the SDK. Call this once, typically from your `AppDelegate`
    /// or SwiftUI `App` initializer.
    ///
    /// - Parameter configuration: Hostname of the Faced deployment plus any
    ///   optional overrides (theme, locale).
    public static func configure(_ configuration: FacedConfiguration) {
        FacedRuntime.shared.configure(configuration)
    }

    /// The configuration that's currently in effect, if any.
    public static var currentConfiguration: FacedConfiguration? {
        FacedRuntime.shared.configuration
    }

    /// SDK version string included in user-agent headers.
    public static let version: String = "0.2.0"

    /// Returns `true` once `configure(_:)` has been called.
    public static var isConfigured: Bool {
        FacedRuntime.shared.configuration != nil
    }

    /// Verifies that the configured host is reachable and responds like a
    /// Faced backend. Throws a `FacedError` describing exactly what's wrong
    /// (DNS failure, ATS, missing local-network permission, TLS, etc.).
    ///
    /// Call this from your launch path or just before showing your "Start
    /// verification" button. If it throws, surface the message and disable
    /// the entry point — much better UX than letting the user tap Start and
    /// then hit the failure inside the SDK's modal.
    public static func preflight() async throws {
        guard let configuration = FacedRuntime.shared.configuration else {
            throw FacedError.notConfigured
        }

        var request = URLRequest(url: configuration.host.appendingPathComponent("health"))
        request.httpMethod = "GET"
        request.timeoutInterval = min(configuration.networkTimeoutSeconds, 10)
        request.setValue("FacedKYC-iOS/\(version)", forHTTPHeaderField: "User-Agent")

        let session = URLSession(configuration: .ephemeral)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw FacedError.network(urlError)
        } catch {
            throw FacedError.internalError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw FacedError.internalError("Health check did not return an HTTP response.")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw FacedError.server(statusCode: http.statusCode, message: body)
        }
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            object["status"] as? String == "ok"
        else {
            throw FacedError.internalError("Configured host did not respond with a Faced-shaped /health payload.")
        }
    }
}
