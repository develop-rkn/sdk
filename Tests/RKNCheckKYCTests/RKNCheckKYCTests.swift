import XCTest
@testable import RKNCheckKYC

final class RKNCheckKYCTests: XCTestCase {

    func testSDKVersionIsExposed() {
        XCTAssertFalse(RKNCheckSDK.version.isEmpty)
    }

    func testIsConfiguredReflectsConfigure() {
        // Note: this is a process-wide singleton; test order can leak state.
        guard let host = URL(string: "https://kyc.test.invalid") else {
            return XCTFail("Could not build host URL")
        }
        RKNCheckSDK.configure(RKNCheckConfiguration(host: host))
        XCTAssertTrue(RKNCheckSDK.isConfigured)
        XCTAssertEqual(RKNCheckSDK.currentConfiguration?.host, host)
    }

    func testRKNCheckResultExposesSessionId() {
        XCTAssertEqual(RKNCheckResult.approved(sessionId: "abc").sessionId, "abc")
        XCTAssertEqual(RKNCheckResult.rejected(sessionId: "x", reason: "no_match").sessionId, "x")
        XCTAssertNil(RKNCheckResult.failed(error: .notConfigured).sessionId)
    }

    // Regression test for the host-path-prefix bug discovered during the KYC
    // platform's reverse-proxy integration. When KYC mounts the SDK proxy at
    // `/biometrics/*`, the SDK MUST preserve that prefix on every endpoint
    // call — the old `URL(string:relativeTo:)` implementation silently
    // stripped it because absolute paths replace the host's path.
    func testComposeURLPreservesHostPathPrefix() throws {
        let host = try XCTUnwrap(URL(string: "https://kyc-host.example.com/biometrics"))
        let url = try XCTUnwrap(RKNCheckAPIClient.composeURL(host: host, path: "/v1/sessions/abc/document"))
        XCTAssertEqual(url.absoluteString, "https://kyc-host.example.com/biometrics/v1/sessions/abc/document")
    }

    func testComposeURLHandlesHostTrailingSlash() throws {
        let host = try XCTUnwrap(URL(string: "https://kyc-host.example.com/biometrics/"))
        let url = try XCTUnwrap(RKNCheckAPIClient.composeURL(host: host, path: "/v1/sessions/abc"))
        XCTAssertEqual(url.absoluteString, "https://kyc-host.example.com/biometrics/v1/sessions/abc")
    }

    func testComposeURLHandlesNoPathPrefix() throws {
        let host = try XCTUnwrap(URL(string: "https://kyc-host.example.com"))
        let url = try XCTUnwrap(RKNCheckAPIClient.composeURL(host: host, path: "/v1/sessions/abc"))
        XCTAssertEqual(url.absoluteString, "https://kyc-host.example.com/v1/sessions/abc")
    }

    func testComposeURLHandlesPathWithoutLeadingSlash() throws {
        let host = try XCTUnwrap(URL(string: "https://kyc-host.example.com/biometrics"))
        let url = try XCTUnwrap(RKNCheckAPIClient.composeURL(host: host, path: "v1/sessions/abc"))
        XCTAssertEqual(url.absoluteString, "https://kyc-host.example.com/biometrics/v1/sessions/abc")
    }
}
