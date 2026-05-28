import SwiftUI

/// App flow:
///   Gate (camera check) → Quiz (monitored) → Dashboard (review)
///
/// The quiz never loads unless the camera is either active (real device)
/// or explicitly in simulator demo mode. Permission denied = hard block.
struct ContentView: View {

    @StateObject private var session = SessionManager()
    @StateObject private var camera  = CameraMonitor()

    private let analyzer = IntegrityAnalyzer()
    private let logger   = FlagLogger()

    enum Screen { case gate, quiz, dashboard }
    @State private var screen: Screen = .gate

    var body: some View {
        Group {
            switch screen {
            case .gate:
                CameraGateView(state: camera.state) {
                    // Camera is ready — wire pipeline then start session.
                    wirePipeline()
                    session.startSession()
                    withAnimation { screen = .quiz }
                }
                .onAppear { camera.requestAndStart() }

            case .quiz:
                quizShell

            case .dashboard:
                DashboardView(localFlags: session.flags, sessionID: session.sessionID)
            }
        }
        .animation(.easeInOut, value: screen)
    }

    // MARK: - Quiz shell

    private var quizShell: some View {
        ZStack(alignment: .bottom) {
            WebView {
                session.endSession()
                camera.stop()
                withAnimation { screen = .dashboard }
            }
            .ignoresSafeArea()

            sessionBanner
        }
    }

    /// Bottom status bar — also shows DEMO tag in simulator mode.
    private var sessionBanner: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(session.isActive ? Color.green : Color.gray)
                .frame(width: 10, height: 10)

            Text(session.isActive ? "Session active · \(session.sessionID.prefix(8))" : "Session ended")
                .font(.caption)
                .foregroundStyle(.white)

            if camera.state == .simulatorDemo {
                Text("DEMO")
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange)
                    .clipShape(Capsule())
            }

            Spacer()

            Text("\(session.flags.count) flag\(session.flags.count == 1 ? "" : "s")")
                .font(.caption.bold())
                .foregroundStyle(session.flags.isEmpty ? .white : .yellow)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.black.opacity(0.7))
    }

    // MARK: - Pipeline wiring

    private func wirePipeline() {
        // Real camera frames → Vision → session + backend
        camera.onFrame = { [session, analyzer, logger] sampleBuffer in
            let flags = analyzer.analyze(sampleBuffer: sampleBuffer, sessionID: session.sessionID)
            for flag in flags {
                session.recordFlag(flag)
                logger.log(flag)
            }
        }

        // Simulator demo: realistic sparse synthetic flags
        camera.onSimulatorTick = { [session, logger] in
            guard Int.random(in: 0..<10) < 3,
                  let type = FlagType.allCases.randomElement()
            else { return }
            let flag = IntegrityFlag(sessionID: session.sessionID, type: type)
            session.recordFlag(flag)
            logger.log(flag)
        }
    }
}

#Preview {
    ContentView()
}
