import XCTest
@testable import ProctorLens

final class FlagTypeTests: XCTestCase {

    func testSeverityOrdering() {
        // Leaving the app is the most serious; a brief head turn the mildest.
        XCTAssertGreaterThan(FlagType.appBackgrounded.severity, FlagType.multipleFaces.severity)
        XCTAssertGreaterThan(FlagType.multipleFaces.severity, FlagType.headTurnedAway.severity)
        XCTAssertEqual(FlagType.appBackgrounded.severity, 3)
        XCTAssertEqual(FlagType.headTurnedAway.severity, 1)
    }

    func testCameraDetectableExcludesBackgrounding() {
        // appBackgrounded comes from the app lifecycle, never from Vision.
        XCTAssertFalse(FlagType.cameraDetectable.contains(.appBackgrounded))
        XCTAssertTrue(FlagType.cameraDetectable.contains(.noFace))
        XCTAssertTrue(FlagType.cameraDetectable.contains(.multipleFaces))
        XCTAssertTrue(FlagType.cameraDetectable.contains(.headTurnedAway))
    }

    func testEveryTypeHasADisplayName() {
        for type in FlagType.allCases {
            XCTAssertFalse(type.displayName.isEmpty, "\(type) is missing a display name")
        }
    }

    func testRawValuesMatchBackendContract() {
        // These strings are the REST API contract — must not drift.
        XCTAssertEqual(FlagType.noFace.rawValue, "no_face")
        XCTAssertEqual(FlagType.multipleFaces.rawValue, "multiple_faces")
        XCTAssertEqual(FlagType.headTurnedAway.rawValue, "head_turned_away")
        XCTAssertEqual(FlagType.appBackgrounded.rawValue, "app_backgrounded")
    }
}
