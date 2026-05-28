import Foundation

/// Posts integrity flags to the backend REST API.
/// Fire-and-forget: failures are logged but don't block the analysis pipeline.
final class FlagLogger {

    // MARK: - Configuration

    /// Change this to your machine's LAN IP when running on a real device.
    /// The simulator can reach localhost directly.
    static let backendBaseURL = "http://127.0.0.1:8765"

    // MARK: - Private

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        return URLSession(configuration: config)
    }()

    private let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return enc
    }()

    // MARK: - Public API

    /// Encodes and POSTs the flag asynchronously. Returns immediately.
    func log(_ flag: IntegrityFlag) {
        guard let url = URL(string: "\(Self.backendBaseURL)/flags") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try encoder.encode(flag)
        } catch {
            print("[FlagLogger] Encode error: \(error)")
            return
        }

        // Detach: we don't need the response on the critical analysis path.
        session.dataTask(with: request) { _, response, error in
            if let error {
                print("[FlagLogger] Network error: \(error.localizedDescription)")
                return
            }
            if let http = response as? HTTPURLResponse, http.statusCode != 201 {
                print("[FlagLogger] Unexpected status: \(http.statusCode)")
            }
        }.resume()
    }
}
