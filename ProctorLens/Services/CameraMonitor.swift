import AVFoundation
import CoreImage
import UIKit

/// Captures front-camera frames at a fixed interval using AVFoundation.
/// Delivers one CMSampleBuffer per tick to whoever sets `onFrame`.
/// No video is stored — buffers are handed off and released after analysis.
final class CameraMonitor: NSObject {

    // MARK: - Configuration

    /// Seconds between sampled frames. Default matches PRD (one every 2 s).
    var sampleInterval: TimeInterval = 2.0

    /// Called on a background queue with each sampled frame.
    var onFrame: ((CMSampleBuffer) -> Void)?

    // MARK: - Private state

    private let session   = AVCaptureSession()
    private let output    = AVCaptureVideoDataOutput()
    private let queue     = DispatchQueue(label: "com.ashish.proctorLens.cameraQueue", qos: .userInitiated)
    private var lastSampleTime: CMTime = .invalid
    private var isRunning = false

    // MARK: - Public API

    /// Requests camera permission, configures the session, then starts capturing.
    /// Safe to call multiple times — no-ops if already running.
    func start() {
        guard !isRunning else { return }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { self?.configureAndStart() }
            }
        default:
            // Denied or restricted — the app will flag "no face" continuously,
            // which is the correct behaviour: we can't monitor, so we flag.
            print("[CameraMonitor] Camera permission denied.")
        }
    }

    func stop() {
        guard isRunning else { return }
        queue.async { [weak self] in
            self?.session.stopRunning()
            self?.isRunning = false
        }
    }

    // MARK: - Private setup

    private func configureAndStart() {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                try self.configure()
                self.session.startRunning()
                self.isRunning = true
            } catch {
                print("[CameraMonitor] Setup error: \(error)")
            }
        }
    }

    private func configure() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .medium   // Enough for face detection; saves power.

        // Front camera input
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            throw CameraError.noFrontCamera
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
        session.addInput(input)

        // Video output — we decode frames on `queue`
        output.setSampleBufferDelegate(self, queue: queue)
        output.alwaysDiscardsLateVideoFrames = true
        guard session.canAddOutput(output) else { throw CameraError.cannotAddOutput }
        session.addOutput(output)

        // Portrait orientation for iPad
        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
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

        // Throttle: only forward a frame once per `sampleInterval`.
        if lastSampleTime == .invalid ||
           CMTimeGetSeconds(CMTimeSubtract(presentationTime, lastSampleTime)) >= sampleInterval {
            lastSampleTime = presentationTime
            onFrame?(sampleBuffer)
        }
    }
}
