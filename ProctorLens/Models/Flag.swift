import Foundation

/// The integrity events the app can detect.
enum FlagType: String, Codable, CaseIterable {
    case noFace          = "no_face"
    case multipleFaces   = "multiple_faces"
    case headTurnedAway  = "head_turned_away"
    case appBackgrounded = "app_backgrounded"   // candidate left the exam app

    var displayName: String {
        switch self {
        case .noFace:          return "No face detected"
        case .multipleFaces:   return "Multiple faces"
        case .headTurnedAway:  return "Head turned away"
        case .appBackgrounded: return "Left the exam app"
        }
    }

    /// The camera-based violations the IntegrityAnalyzer can produce.
    /// appBackgrounded is excluded — it comes from the app lifecycle, not Vision.
    static var cameraDetectable: [FlagType] {
        [.noFace, .multipleFaces, .headTurnedAway]
    }

    /// How serious this violation is, used to compute a session severity score.
    /// Leaving the exam app is the strongest signal; a brief head turn is mild.
    var severity: Int {
        switch self {
        case .appBackgrounded: return 3
        case .multipleFaces:   return 2
        case .noFace:          return 2
        case .headTurnedAway:  return 1
        }
    }
}

/// A single integrity event captured during a session.
struct IntegrityFlag: Identifiable, Codable {
    let id: UUID
    let sessionID: String
    let type: FlagType
    let timestamp: Date

    init(sessionID: String, type: FlagType) {
        self.id        = UUID()
        self.sessionID = sessionID
        self.type      = type
        self.timestamp = Date()
    }

    // MARK: - Coding Keys (matches the REST API shape)
    enum CodingKeys: String, CodingKey {
        case id
        case sessionID  = "session_id"
        case type       = "flag_type"
        case timestamp
    }
}
