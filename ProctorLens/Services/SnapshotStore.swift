import UIKit
import CoreImage
import CoreMedia

/// Holds a low-resolution thumbnail captured at the moment each camera-based
/// violation started, keyed by the flag's id.
///
/// Privacy stance: these images never leave the device — only flag metadata is
/// transmitted to the backend. The thumbnails exist purely so the local
/// reviewer can see *what* triggered a flag, which a text-only log can't show.
/// Downscaling to a small thumbnail keeps them lightweight and low-fidelity.
final class SnapshotStore: ObservableObject {

    @Published private(set) var images: [UUID: UIImage] = [:]

    private let ciContext = CIContext()
    private let targetWidth: CGFloat = 200   // thumbnail width in pixels

    /// Captures and stores a downscaled thumbnail for the given flag id.
    /// Safe to call from a background queue — publishes on the main queue.
    func capture(from sampleBuffer: CMSampleBuffer, for id: UUID) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let scale = targetWidth / max(ciImage.extent.width, 1)
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = ciContext.createCGImage(scaled, from: scaled.extent) else { return }
        let image = UIImage(cgImage: cgImage)

        DispatchQueue.main.async {
            self.images[id] = image
        }
    }

    func image(for id: UUID) -> UIImage? {
        images[id]
    }

    func reset() {
        DispatchQueue.main.async { self.images = [:] }
    }
}
