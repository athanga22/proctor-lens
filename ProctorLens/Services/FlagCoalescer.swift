import Foundation

/// Collapses continuous per-frame violation detections into discrete events.
///
/// Without this, holding a violation (e.g. looking away for 10s) would fire a
/// flag every sampled frame. A real proctoring system logs ONE event when a
/// violation starts, not one per tick. This tracks which violation types are
/// currently active and reports only the transitions from absent → present.
///
/// Example over four frames:
///   [headTurnedAway]            → emits [headTurnedAway]   (started)
///   [headTurnedAway]            → emits []                 (still active)
///   [headTurnedAway, noFace]    → emits [noFace]           (new one started)
///   []                          → emits []                 (all cleared)
final class FlagCoalescer {

    private var active: Set<FlagType> = []

    /// Updates the active set with the violations seen this frame.
    /// - Parameter current: violation types present in the current frame.
    /// - Returns: types that just transitioned from inactive to active.
    func update(current: Set<FlagType>) -> [FlagType] {
        let started = current.subtracting(active)
        active = current
        return Array(started)
    }

    /// Clears all active state — call at the start of a new session.
    func reset() {
        active = []
    }
}
