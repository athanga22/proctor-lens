import Foundation

/// Talks to the backend: creates an authenticated session, then posts flags
/// using the issued bearer token. Flag posting is fire-and-forget — failures
/// are logged but never block the analysis pipeline.
///
/// If no session token is held (backend unreachable at start), `log` no-ops,
/// so the app still runs locally without spamming failed requests.
final class FlagLogger {

    // MARK: - Configuration

    /// Change to your machine's LAN IP when running on a real device.
    /// The simulator can reach localhost directly.
    static let backendBaseURL = "http://127.0.0.1:8765"

    struct SessionCredentials: Decodable {
        let sessionID: String
        let token: String

        enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case token
        }
    }

    // MARK: - Private

    private var token: String?

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

    // MARK: - Session lifecycle

    /// Creates a backend session and stores its write token.
    /// - Returns: the issued credentials, or nil if the backend is unreachable.
    func createSession() async -> SessionCredentials? {
        guard let url = URL(string: "\(Self.backendBaseURL)/sessions") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 201 else {
                print("[FlagLogger] Session creation failed — running without backend logging.")
                return nil
            }
            let creds = try JSONDecoder().decode(SessionCredentials.self, from: data)
            token = creds.token
            return creds
        } catch {
            print("[FlagLogger] Backend unreachable (\(error.localizedDescription)) — local-only mode.")
            return nil
        }
    }

    /// Clears the held token — call when a session ends.
    func reset() {
        token = nil
    }

    // MARK: - Flag posting

    /// Encodes and POSTs the flag asynchronously. Returns immediately.
    /// No-ops if we have no session token (backend was unreachable at start).
    func log(_ flag: IntegrityFlag) {
        guard let token else { return }
        guard let url = URL(string: "\(Self.backendBaseURL)/flags") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            request.httpBody = try encoder.encode(flag)
        } catch {
            print("[FlagLogger] Encode error: \(error)")
            return
        }

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
