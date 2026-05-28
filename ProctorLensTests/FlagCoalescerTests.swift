import XCTest
@testable import ProctorLens

/// Coalescing is the trickiest piece of logic, so it gets the most coverage.
/// The rule: emit a type only on its transition from absent → present.
final class FlagCoalescerTests: XCTestCase {

    func testNewViolationIsEmitted() {
        let coalescer = FlagCoalescer()
        let started = coalescer.update(current: [.headTurnedAway])
        XCTAssertEqual(Set(started), [.headTurnedAway])
    }

    func testContinuousViolationEmittedOnlyOnce() {
        let coalescer = FlagCoalescer()

        let first = coalescer.update(current: [.noFace])
        XCTAssertEqual(Set(first), [.noFace], "First frame should emit the violation")

        let second = coalescer.update(current: [.noFace])
        XCTAssertTrue(second.isEmpty, "Holding the same violation must not re-emit")

        let third = coalescer.update(current: [.noFace])
        XCTAssertTrue(third.isEmpty, "Still held — still silent")
    }

    func testClearedThenReappearingEmitsAgain() {
        let coalescer = FlagCoalescer()

        XCTAssertEqual(Set(coalescer.update(current: [.headTurnedAway])), [.headTurnedAway])
        XCTAssertTrue(coalescer.update(current: []).isEmpty, "Clean frame clears state, emits nothing")

        let reappeared = coalescer.update(current: [.headTurnedAway])
        XCTAssertEqual(Set(reappeared), [.headTurnedAway], "A fresh occurrence is a new event")
    }

    func testOnlyNewlyStartedTypesAreEmitted() {
        let coalescer = FlagCoalescer()

        XCTAssertEqual(Set(coalescer.update(current: [.headTurnedAway])), [.headTurnedAway])

        // headTurnedAway still active, noFace newly appears → only noFace emitted.
        let started = coalescer.update(current: [.headTurnedAway, .noFace])
        XCTAssertEqual(Set(started), [.noFace])
    }

    func testCleanFrameFromStartEmitsNothing() {
        let coalescer = FlagCoalescer()
        XCTAssertTrue(coalescer.update(current: []).isEmpty)
    }

    func testResetClearsActiveState() {
        let coalescer = FlagCoalescer()

        XCTAssertEqual(Set(coalescer.update(current: [.multipleFaces])), [.multipleFaces])
        coalescer.reset()

        // After reset the same violation counts as new again.
        XCTAssertEqual(Set(coalescer.update(current: [.multipleFaces])), [.multipleFaces])
    }
}
