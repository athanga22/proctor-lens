import Vision
import CoreMedia
import CoreML

/// Runs the three integrity checks on a single camera frame.
///
/// Checks:
///   1. noFace         — Vision ran and found zero faces
///   2. multipleFaces  — Vision ran and found more than one face
///   3. headTurnedAway — yaw or pitch exceeds threshold
///
/// Uses `VNDetectFaceRectanglesRequest` (revision 3) rather than the landmarks
/// request: we only need face count + head pose (yaw/pitch), not landmark points,
/// and the lighter request is more likely to run on CPU in the simulator.
///
/// Important correctness rule: a Vision *failure* is NOT the same as "no face".
/// If the request can't run, we emit no flags rather than fabricating a noFace.
final class IntegrityAnalyzer {

    // MARK: - Configuration

    /// Radians. ~20° = "clearly looking away" without false positives.
    var yawThreshold:   Float = 0.35
    var pitchThreshold: Float = 0.35

    /// CPU compute device, resolved once. Forcing CPU lets Vision run in the
    /// simulator, which has no Neural Engine ("Could not create inference context").
    private let cpuDevice: MLComputeDevice? = MLComputeDevice.allComputeDevices.first {
        if case .cpu = $0 { return true }
        return false
    }

    /// Set true after the first successful Vision run, so we only warn once
    /// if analysis is unavailable (e.g. simulator without CPU support).
    private var hasLoggedFailure = false

    // MARK: - Public API

    /// Analyzes one frame synchronously. Returns flags only when Vision actually ran.
    /// Returns an empty array on analysis failure — never a fabricated noFace.
    func analyze(sampleBuffer: CMSampleBuffer, sessionID: String) -> [IntegrityFlag] {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return []
        }

        let semaphore = DispatchSemaphore(value: 0)
        var observations: [VNFaceObservation] = []
        var visionSucceeded = false

        let request = VNDetectFaceRectanglesRequest { req, error in
            defer { semaphore.signal() }
            if let error {
                if !self.hasLoggedFailure {
                    print("[IntegrityAnalyzer] Vision unavailable: \(error.localizedDescription)")
                    self.hasLoggedFailure = true
                }
                return
            }
            observations = req.results as? [VNFaceObservation] ?? []
            visionSucceeded = true
        }

        // Revision 3 provides yaw AND pitch (pitch requires rev 3, iOS 15+).
        request.revision = VNDetectFaceRectanglesRequestRevision3

        // Force CPU so the request runs without a Neural Engine (simulator).
        if let cpuDevice {
            request.setComputeDevice(cpuDevice, for: .main)
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
        } catch {
            if !hasLoggedFailure {
                print("[IntegrityAnalyzer] Handler error: \(error.localizedDescription)")
                hasLoggedFailure = true
            }
            semaphore.signal()
        }
        semaphore.wait()

        // If Vision couldn't run, emit nothing — do not fabricate a noFace flag.
        guard visionSucceeded else { return [] }

        var flags: [IntegrityFlag] = []

        if let countFlag = checkFaceCount(observations, sessionID: sessionID) {
            flags.append(countFlag)
        }

        // Head pose only meaningful with exactly one face.
        if observations.count == 1,
           let poseFlag = checkHeadPose(observations[0], sessionID: sessionID) {
            flags.append(poseFlag)
        }

        return flags
    }

    // MARK: - Individual checks

    private func checkFaceCount(_ observations: [VNFaceObservation], sessionID: String) -> IntegrityFlag? {
        switch observations.count {
        case 0:   return IntegrityFlag(sessionID: sessionID, type: .noFace)
        case 2...: return IntegrityFlag(sessionID: sessionID, type: .multipleFaces)
        default:  return nil
        }
    }

    private func checkHeadPose(_ face: VNFaceObservation, sessionID: String) -> IntegrityFlag? {
        guard let yaw   = face.yaw?.floatValue,
              let pitch = face.pitch?.floatValue else {
            return nil   // pose unavailable — skip silently
        }

        if abs(yaw) > yawThreshold || abs(pitch) > pitchThreshold {
            return IntegrityFlag(sessionID: sessionID, type: .headTurnedAway)
        }
        return nil
    }
}
