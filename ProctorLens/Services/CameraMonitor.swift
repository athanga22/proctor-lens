import AVFoundation
import Combine

/// The states the camera can be in from the app's perspective.
enum CameraState {
    /// Haven't asked the OS yet.
    case unknown
    /// Permission request is in flight.
    case requesting
    /// Real front camera is running — monitoring is live.
    case active
    /// User denied permission. Quiz must be blocked.
    case permissionDenied
    /// Simulator build — no real hardware, synthetic ticks running.
    case simulatorDemo
}

/// Captures front-camera frames at a fixed interval using AVFoundation.
/// Publishes its `state` so the UI can gate quiz entry on real monitoring.
///
/// Real device flow:
///   unknown → requesting → active          (permission granted)
///   unknown → requesting → permissionDenied (permission denied → block quiz)
///
/// Simulator flow:
///   unknown → simulatorDemo                (skip AVFoundation entirely)
final class CameraMonitor: NSObject, ObservableObject {

    // MARK: - Published state

    @Published private(set) var state: CameraState = .unknown

    // MARK: - Configuration

    /// Seconds between sampled frames. Matches PRD default (one every 2 s).
    var sampleInterval: TimeInterval = 2.0

    /// Called on a background queue with each real camera frame.
    var onFrame: ((CMSampleBuffer) -> Void)?

    /// Called on the main queue each tick in simulator demo mode.
    var onSimulatorTick: (() -> Void)?

    // MARK: - Private

    private let captureSession = AVCaptureSession()
    private let output         = AVCaptureVideoDataOutput()
    private let queue          = DispatchQueue(label: "com.ashish.proctorLens.cameraQueue", qos: .userInitiated)
    private var lastSampleTime: CMTime = .invalid
    private var simulatorTimer: Timer?

    // MARK: - Public API

    /// Checks / requests permission, then starts the appropriate path.
    /// Safe to call multiple times — no-ops once past the `.unknown` state.
    func requestAndStart() {
        guard state == .unknown else { return }

        #if targetEnvironment(simulator)
        startSimulatorDemo()
        #else
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            DispatchQueue.main.async { self.state = .requesting }
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.configureAndStart()
                    } else {
                        self?.state = .permissionDenied
                    }
                }
            }
        default:
            // .denied or .restricted
            DispatchQueue.main.async { self.state = .permissionDenied }
        }
        #endif
    }

    func stop() {
        simulatorTimer?.invalidate()
        simulatorTimer = nil
        queue.async { [weak self] in
            self?.captureSession.stopRunning()
        }
    }

    // MARK: - Real camera path

    private func configureAndStart() {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                try self.configure()
                self.captureSession.startRunning()
                DispatchQueue.main.async { self.state = .active }
            } catch {
                // Hardware unavailable even though permission was granted.
                // This should not happen on a real device — treat as denied
                // so the quiz is blocked rather than proceeding unmonitored.
                print("[CameraMonitor] Setup error: \(error)")
                DispatchQueue.main.async { self.state = .permissionDenied }
            }
        }
    }

    private func configure() throws {
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        captureSession.sessionPreset = .medium

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            throw CameraError.noFrontCamera
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard captureSession.canAddInput(input) else { throw CameraError.cannotAddInput }
        captureSession.addInput(input)

        output.setSampleBufferDelegate(self, queue: queue)
        output.alwaysDiscardsLateVideoFrames = true
        guard captureSession.canAddOutput(output) else { throw CameraError.cannotAddOutput }
        captureSession.addOutput(output)

        if let connection = output.connection(with: .video),
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }

    // MARK: - Simulator demo path

    private func startSimulatorDemo() {
        print("[CameraMonitor] Simulator — running in demo mode with synthetic flags.")
        state = .simulatorDemo
        simulatorTimer = Timer.scheduledTimer(withTimeInterval: sampleInterval, repeats: true) { [weak self] _ in
            self?.onSimulatorTick?()
        }
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
        if lastSampleTime == .invalid ||
           CMTimeGetSeconds(CMTimeSubtract(presentationTime, lastSampleTime)) >= sampleInterval {
            lastSampleTime = presentationTime
            onFrame?(sampleBuffer)
        }
    }
}
