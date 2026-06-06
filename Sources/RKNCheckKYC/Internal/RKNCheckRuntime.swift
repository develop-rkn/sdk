import Foundation

/// Process-wide singleton holding the configuration passed to
/// `RKNCheckSDK.configure(_:)`. Internal-only — never exposed.
final class RKNCheckRuntime {
    static let shared = RKNCheckRuntime()

    private let lock = NSLock()
    private var _configuration: RKNCheckConfiguration?

    private init() {}

    var configuration: RKNCheckConfiguration? {
        lock.lock()
        defer { lock.unlock() }
        return _configuration
    }

    func configure(_ configuration: RKNCheckConfiguration) {
        lock.lock()
        defer { lock.unlock() }
        _configuration = configuration
    }

    func makeAPIClient(clientToken: String) -> RKNCheckAPIClient? {
        guard let configuration = self.configuration else { return nil }
        return RKNCheckAPIClient(host: configuration.host, clientToken: clientToken, timeout: configuration.networkTimeoutSeconds)
    }
}
