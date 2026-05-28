import Foundation
import Combine

/// Where the session stands relative to the integrity thresholds.
enum SessionStatus {
    case monitoring   // within tolerance
    case warning      // crossed the warning threshold — candidate is notified
    case terminated   // crossed the termination threshold — exam ended
}

/// Owns the session lifecycle: start, stop, the flag list, and the escalation
/// model that warns the candidate and auto-terminates after too many violations.
final class SessionManager: ObservableObject {

    // MARK: - Published state
    @Published private(set) var isActive: Bool = false
    @Published private(set) var flags: [IntegrityFlag] = []
    @Published private(set) var sessionID: String = ""
    @Published private(set) var status: SessionStatus = .monitoring
    @Published private(set) var severityScore: Int = 0
    @Published private(set) var terminationReason: String?

    // MARK: - Thresholds (weighted severity points)
    /// Notify the candidate once accumulated severity reaches this.
    let warningThreshold = 4
    /// End the exam once accumulated severity reaches this.
    let terminationThreshold = 8

    // MARK: - Session control

    /// Starts a session. Pass the backend-issued ID when available; falls back
    /// to a local UUID so the app still works offline.
    func startSession(id: String = UUID().uuidString) {
        sessionID         = id
        flags             = []
        severityScore     = 0
        status            = .monitoring
        terminationReason = nil
        isActive          = true
    }

    func endSession() {
        isActive = false
    }

    /// Records a flag, updates the severity score, and escalates if needed.
    func recordFlag(_ flag: IntegrityFlag) {
        DispatchQueue.main.async {
            guard self.isActive else { return }   // ignore flags after termination/end
            self.flags.append(flag)
            self.severityScore += flag.type.severity
            self.evaluateStatus()
        }
    }

    // MARK: - Escalation

    private func evaluateStatus() {
        if severityScore >= terminationThreshold {
            status = .terminated
            terminationReason = "Exam ended automatically: integrity violations "
                + "exceeded the allowed limit (\(severityScore) points)."
            isActive = false
        } else if severityScore >= warningThreshold {
            status = .warning
        }
    }
}
