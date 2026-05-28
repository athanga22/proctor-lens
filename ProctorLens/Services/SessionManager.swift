import Foundation
import Combine

/// Owns the session lifecycle: start, stop, and the list of flags for the current run.
final class SessionManager: ObservableObject {

    // MARK: - Published state
    @Published private(set) var isActive: Bool = false
    @Published private(set) var flags: [IntegrityFlag] = []
    @Published private(set) var sessionID: String = ""

    // MARK: - Session control

    func startSession() {
        sessionID = UUID().uuidString
        flags     = []
        isActive  = true
    }

    func endSession() {
        isActive = false
    }

    /// Called by IntegrityAnalyzer whenever a violation is detected.
    func recordFlag(_ flag: IntegrityFlag) {
        DispatchQueue.main.async {
            self.flags.append(flag)
        }
    }
}
