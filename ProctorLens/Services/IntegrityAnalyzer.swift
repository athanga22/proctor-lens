import Vision
import CoreMedia
import CoreML

/// Runs the camera-based integrity checks on a single frame and reports which
/// violation types are *currently* present. It does not mint flags or track
/// history — coalescing those frame-by-frame detections into discrete events
/// is the job of `FlagCoalescer`.
///
/// Checks:
///   • noFace         — Vision ran and found zero faces
///   • multipleFaces  — Vision ran and found more than one face
///   • headTurnedAway — yaw or pitch exceeds threshold
///
/// Correctness rule: a Vision *failure* is NOT "no face". On failure we return
/// `nil` so the caller knows the frame is indeterminate and leaves state untouched.
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

    private var hasLoggedFailure = false

    // MARK: - Public API

    /// Analyzes one frame synchronously.
    /// - Returns: the set of violation types present this frame (possibly empty
    ///   for a clean frame), or `nil` if Vision could not run.
    func analyze(sampleBuffer: CMSampleBuffer) -> Set<FlagType>? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
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

        guard visionSucceeded else { return nil }   // indeterminate frame

        var detected: Set<FlagType> = []

        switch observations.count {
        case 0:    detected.insert(.noFace)
        case 2...: detected.insert(.multipleFaces)
        default:   break
        }

        // Head pose only meaningful with exactly one face.
        if observations.count == 1, isHeadTurnedAway(observations[0]) {
            detected.insert(.headTurnedAway)
        }

        return detected
    }

    // MARK: - Checks

    private func isHeadTurnedAway(_ face: VNFaceObservation) -> Bool {
        guard let yaw   = face.yaw?.floatValue,
              let pitch = face.pitch?.floatValue else {
            return false   // pose unavailable — don't flag
        }
        return abs(yaw) > yawThreshold || abs(pitch) > pitchThreshold
    }
}
