import AVFoundation
import CoreImage
import UIKit

/// Captures front-camera frames at a fixed interval using AVFoundation.
/// Delivers one CMSampleBuffer per tick to whoever sets `onFrame`.
/// No video is stored — buffers are handed off and released after analysis.
///
/// **Simulator note**: iOS simulators have no camera hardware. When a real
/// camera is unavailable, `CameraMonitor` falls back to a timer that calls
/// `onSimulatorTick` instead, so the full pipeline (analyzer → logger →
/// dashboard) can be exercised without a physical device.
final class CameraMonitor: NSObject {

    // MARK: - Configuration

    /// Seconds between sampled frames. Default matches PRD (one every 2 s).
    var sampleInterval: TimeInterval = 2.0

    /// Called on a background queue with each real camera frame.
    var onFrame: ((CMSampleBuffer) -> Void)?

    /// Called on the main queue each tick when running in simulator mode.
    /// The caller should inject synthetic flags directly into the session.
    var onSimulatorTick: (() -> Void)?

    // MARK: - Private state

    private let captureSession = AVCaptureSession()
    private let output         = AVCaptureVideoDataOutput()
    private let queue          = DispatchQueue(label: "com.ashish.proctorLens.cameraQueue", qos: .userInitiated)
    private var lastSampleTime: CMTime = .invalid
    private var isRunning      = false
    private var simulatorTimer: Timer?

    // MARK: - Public API

    /// Requests camera permission, configures the session, then starts capturing.
    /// Falls back to simulator mode automatically if no camera is available.
    /// Safe to call multiple times — no-ops if already running.
    func start() {
        guard !isRunning else { return }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.configureAndStart()
                } else {
                    self?.startSimulatorFallback()
                }
            }
        default:
            // Permission denied → treat like simulator: we can't see the user,
            // so synthetic "no face" ticks are the honest fallback.
            startSimulatorFallback()
        }
    }

    func stop() {
        simulatorTimer?.invalidate()
        simulatorTimer = nil
        guard isRunning else { return }
        queue.async { [weak self] in
            self?.captureSession.stopRunning()
            self?.isRunning = false
        }
    }

    // MARK: - Real camera path

    private func configureAndStart() {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                try self.configure()
                self.captureSession.startRunning()
                self.isRunning = true
            } catch {
                print("[CameraMonitor] Camera unavailable (\(error)) — using simulator mode.")
                DispatchQueue.main.async { self.startSimulatorFallback() }
            }
        }
    }

    private func configure() throws {
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        captureSession.sessionPreset = .medium   // Enough for face detection; saves power.

        // On a real device: use the front camera.
        // In the simulator: the Mac's FaceTime camera is mapped as the rear/unspecified
        // camera — fall back to it so Vision runs on real frames instead of synthetic ones.
        #if targetEnvironment(simulator)
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                  ?? AVCaptureDevice.default(for: .video)
        #else
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        #endif

        guard let device else {
            throw CameraError.noFrontCamera
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard captureSession.canAddInput(input) else { throw CameraError.cannotAddInput }
        captureSession.addInput(input)

        // Video output — we decode frames on `queue`
        output.setSampleBufferDelegate(self, queue: queue)
        output.alwaysDiscardsLateVideoFrames = true
        guard captureSession.canAddOutput(output) else { throw CameraError.cannotAddOutput }
        captureSession.addOutput(output)

        // Portrait orientation for iPad
        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
    }

    // MARK: - Simulator fallback

    /// Fires `onSimulatorTick` at the same cadence as real frame sampling.
    /// The caller injects whatever synthetic flags it wants to test with.
    private func startSimulatorFallback() {
        guard simulatorTimer == nil else { return }
        print("[CameraMonitor] Running in simulator mode — no real camera frames.")
        simulatorTimer = Timer.scheduledTimer(withTimeInterval: sampleInterval, repeats: true) { [weak self] _ in
            self?.onSimulatorTick?()
        }
        isRunning = true
    }

    // MARK: - Errors

    enum CameraError: Error {
        case noFrontCamera
        case cannotAddInput
        case cannotAddOutput
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraMonitor: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // Throttle: only forward a frame once per `sampleInterval`.
        if lastSampleTime == .invalid ||
           CMTimeGetSeconds(CMTimeSubtract(presentationTime, lastSampleTime)) >= sampleInterval {
            lastSampleTime = presentationTime
            onFrame?(sampleBuffer)
        }
    }
}
