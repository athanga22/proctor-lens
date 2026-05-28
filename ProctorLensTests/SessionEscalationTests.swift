import XCTest
@testable import ProctorLens

/// Verifies the warn → terminate escalation thresholds.
final class SessionEscalationTests: XCTestCase {

    private let warning = 4
    private let termination = 8

    private func status(_ score: Int) -> SessionStatus {
        SessionManager.status(
            forScore: score,
            warningThreshold: warning,
            terminationThreshold: termination
        )
    }

    func testBelowWarningIsMonitoring() {
        XCTAssertEqual(status(0), .monitoring)
        XCTAssertEqual(status(3), .monitoring)
    }

    func testAtWarningThresholdIsWarning() {
        XCTAssertEqual(status(4), .warning)
    }

    func testBetweenWarningAndTerminationIsWarning() {
        XCTAssertEqual(status(5), .warning)
        XCTAssertEqual(status(7), .warning)
    }

    func testAtTerminationThresholdTerminates() {
        XCTAssertEqual(status(8), .terminated)
    }

    func testWellAboveTerminationStillTerminates() {
        XCTAssertEqual(status(20), .terminated)
    }
}
