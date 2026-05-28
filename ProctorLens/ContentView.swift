import SwiftUI

/// Root view — shows the quiz shell while a session is active,
/// and the reviewer dashboard after it ends.
struct ContentView: View {

    @StateObject private var session = SessionManager()
    @State private var showDashboard = false

    /// Services — all share the view's lifetime.
    private let camera   = CameraMonitor()
    private let analyzer = IntegrityAnalyzer()
    private let logger   = FlagLogger()

    var body: some View {
        ZStack(alignment: .topTrailing) {

            if showDashboard {
                DashboardView(localFlags: session.flags, sessionID: session.sessionID)
                    .transition(.move(edge: .trailing))
            } else {
                quizShell
                    .transition(.move(edge: .leading))
            }
        }
        .animation(.easeInOut, value: showDashboard)
    }

    // MARK: - Quiz shell

    private var quizShell: some View {
        ZStack(alignment: .bottom) {
            WebView {
                // Quiz submitted → end session and show dashboard.
                session.endSession()
                withAnimation { showDashboard = true }
            }
            .ignoresSafeArea()

            sessionBanner
        }
        .onAppear {
            session.startSession()

            // Wire the frame pipeline: camera → analyzer → session + logger
            camera.onFrame = { [session, analyzer, logger] sampleBuffer in
                let flags = analyzer.analyze(
                    sampleBuffer: sampleBuffer,
                    sessionID: session.sessionID
                )
                for flag in flags {
                    session.recordFlag(flag)
                    logger.log(flag)       // fire-and-forget POST to backend
                }
            }

            // Simulator fallback: realistic distribution — most ticks are clean,
            // ~30% produce a random violation. Exercises the full pipeline without
            // spamming every flag on every tick.
            camera.onSimulatorTick = { [session, logger] in
                guard Int.random(in: 0..<10) < 3,          // ~30% chance
                      let type = FlagType.allCases.randomElement()
                else { return }
                let flag = IntegrityFlag(sessionID: session.sessionID, type: type)
                session.recordFlag(flag)
                logger.log(flag)
            }

            camera.start()
        }
        .onDisappear {
            camera.stop()
            camera.onFrame = nil
            camera.onSimulatorTick = nil
        }
    }

    /// Thin status bar at the bottom showing session state.
    private var sessionBanner: some View {
        HStack {
            Circle()
                .fill(session.isActive ? Color.green : Color.gray)
                .frame(width: 10, height: 10)

            Text(session.isActive ? "Session active · \(session.sessionID.prefix(8))" : "Session ended")
                .font(.caption)
                .foregroundStyle(.white)

            Spacer()

            Text("\(session.flags.count) flag\(session.flags.count == 1 ? "" : "s")")
                .font(.caption.bold())
                .foregroundStyle(session.flags.isEmpty ? .white : .yellow)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.black.opacity(0.6))
    }
}

#Preview {
    ContentView()
}
