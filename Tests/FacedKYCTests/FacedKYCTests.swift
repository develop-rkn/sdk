import XCTest
@testable import FacedKYC

final class FacedKYCTests: XCTestCase {

    func testSDKVersionIsExposed() {
        XCTAssertFalse(FacedSDK.version.isEmpty)
    }

    func testIsConfiguredReflectsConfigure() {
        // Note: this is a process-wide singleton; test order can leak state.
        guard let host = URL(string: "https://kyc.test.invalid") else {
            return XCTFail("Could not build host URL")
        }
        FacedSDK.configure(FacedConfiguration(host: host))
        XCTAssertTrue(FacedSDK.isConfigured)
        XCTAssertEqual(FacedSDK.currentConfiguration?.host, host)
    }

    func testFacedResultExposesSessionId() {
        XCTAssertEqual(FacedResult.approved(sessionId: "abc").sessionId, "abc")
        XCTAssertEqual(FacedResult.rejected(sessionId: "x", reason: "no_match").sessionId, "x")
        XCTAssertNil(FacedResult.failed(error: .notConfigured).sessionId)
    }
}
