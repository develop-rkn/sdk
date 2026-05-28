import Foundation

/// Process-wide singleton holding the configuration passed to
/// `FacedSDK.configure(_:)`. Internal-only — never exposed.
final class FacedRuntime {
    static let shared = FacedRuntime()

    private let lock = NSLock()
    private var _configuration: FacedConfiguration?

    private init() {}

    var configuration: FacedConfiguration? {
        lock.lock()
        defer { lock.unlock() }
        return _configuration
    }

    func configure(_ configuration: FacedConfiguration) {
        lock.lock()
        defer { lock.unlock() }
        _configuration = configuration
    }

    func makeAPIClient(clientToken: String) -> FacedAPIClient? {
        guard let configuration = self.configuration else { return nil }
        return FacedAPIClient(host: configuration.host, clientToken: clientToken, timeout: configuration.networkTimeoutSeconds)
    }
}
