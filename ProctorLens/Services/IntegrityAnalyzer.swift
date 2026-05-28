import Vision
import CoreMedia

/// Runs the three integrity checks on a single camera frame.
/// Checks are intentionally separated into small, readable functions.
///
/// Checks:
///   1. noFace         — zero faces detected
///   2. multipleFaces  — more than one face detected
///   3. headTurnedAway — yaw or pitch exceeds threshold
final class IntegrityAnalyzer {

    // MARK: - Configuration

    /// Radians. ~20° feels right for "clearly looking away" without false positives.
    /// Configurable so tests or callers can adjust without touching this file.
    var yawThreshold:  Float = 0.35    // ~20°
    var pitchThreshold: Float = 0.35   // ~20°

    // MARK: - Public API

    /// Analyzes one frame synchronously on the caller's queue.
    /// Returns zero or more flags. Never throws — errors are swallowed and logged.
    func analyze(sampleBuffer: CMSampleBuffer, sessionID: String) -> [IntegrityFlag] {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return []
        }

        var detectedFlags: [IntegrityFlag] = []

        // Use a semaphore so the Vision request (which is async internally)
        // completes before we return. This keeps the caller's interface simple.
        let semaphore = DispatchSemaphore(value: 0)
        var observations: [VNFaceObservation] = []

        let request = VNDetectFaceLandmarksRequest { req, error in
            defer { semaphore.signal() }
            if let error {
                print("[IntegrityAnalyzer] Vision error: \(error)")
                return
            }
            observations = req.results as? [VNFaceObservation] ?? []
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("[IntegrityAnalyzer] Handler error: \(error)")
            semaphore.signal()
        }
        semaphore.wait()

        // Check 1 & 2: face count
        if let countFlag = checkFaceCount(observations, sessionID: sessionID) {
            detectedFlags.append(countFlag)
        }

        // Check 3: head pose (only meaningful if exactly one face was found)
        if observations.count == 1,
           let poseFlag = checkHeadPose(observations[0], sessionID: sessionID) {
            detectedFlags.append(poseFlag)
        }

        return detectedFlags
    }

    // MARK: - Individual checks

    private func checkFaceCount(_ observations: [VNFaceObservation], sessionID: String) -> IntegrityFlag? {
        switch observations.count {
        case 0:
            return IntegrityFlag(sessionID: sessionID, type: .noFace)
        case 2...:
            return IntegrityFlag(sessionID: sessionID, type: .multipleFaces)
        default:
            return nil
        }
    }

    private func checkHeadPose(_ face: VNFaceObservation, sessionID: String) -> IntegrityFlag? {
        // VNFaceObservation exposes yaw and pitch as NSNumber? (nil if unavailable).
        guard let yaw   = face.yaw?.floatValue,
              let pitch = face.pitch?.floatValue else {
            // Head pose not available on this device/OS — skip silently.
            return nil
        }

        let yawExceeded   = abs(yaw)   > yawThreshold
        let pitchExceeded = abs(pitch) > pitchThreshold

        if yawExceeded || pitchExceeded {
            return IntegrityFlag(sessionID: sessionID, type: .headTurnedAway)
        }
        return nil
    }
}
