import SwiftUI

/// App flow:
///   Gate (camera check) → Quiz (monitored) → Dashboard (review)
///
/// The quiz never loads unless the camera is either active (real device)
/// or explicitly in simulator demo mode. Permission denied = hard block.
struct ContentView: View {

    @StateObject private var session = SessionManager()
    @StateObject private var camera  = CameraMonitor()

    @Environment(\.scenePhase) private var scenePhase

    private let analyzer  = IntegrityAnalyzer()
    private let coalescer = FlagCoalescer()
    private let logger    = FlagLogger()

    enum Screen { case gate, quiz, dashboard }
    @State private var screen: Screen = .gate

    var body: some View {
        Group {
            switch screen {
            case .gate:
                CameraGateView(state: camera.state) {
                    // Camera is ready — wire pipeline then start session.
                    wirePipeline()
                    coalescer.reset()
                    session.startSession()
                    withAnimation { screen = .quiz }
                }
                .onAppear { camera.requestAndStart() }

            case .quiz:
                quizShell

            case .dashboard:
                DashboardView(
                    localFlags: session.flags,
                    sessionID: session.sessionID,
                    terminated: session.status == .terminated,
                    terminationReason: session.terminationReason
                )
            }
        }
        .animation(.easeInOut, value: screen)
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)
        }
        .onChange(of: session.status) { _, status in
            // Auto-terminate: end the exam and jump to the review screen.
            if status == .terminated {
                camera.stop()
                withAnimation { screen = .dashboard }
            }
        }
    }

    /// Detects the candidate leaving the exam app (home swipe, app switcher,
    /// Control Center, notification). iOS can't *prevent* this without kiosk
    /// mode, but a proctoring app must at least detect and flag every exit.
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        guard screen == .quiz, session.isActive else { return }
        guard oldPhase == .active, newPhase != .active else { return }

        let flag = IntegrityFlag(sessionID: session.sessionID, type: .appBackgrounded)
        session.recordFlag(flag)
        logger.log(flag)
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
        .overlay(alignment: .top) {
            if session.status == .warning {
                warningBanner
            }
        }
    }

    /// Shown to the candidate once they cross the warning threshold — a real
    /// system makes the consequence visible before auto-terminating.
    private var warningBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("Integrity warning — repeated violations will end your exam.")
                .font(.callout.bold())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.red.opacity(0.9))
        .transition(.move(edge: .top))
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
        // Real camera frames → Vision (detected types) → coalesce → session + backend.
        // Coalescing means one flag per continuous violation, not one per frame.
        camera.onFrame = { [session, analyzer, coalescer, logger] sampleBuffer in
            guard let detected = analyzer.analyze(sampleBuffer: sampleBuffer) else {
                return   // analysis failed this frame — leave state untouched
            }
            let started = coalescer.update(current: detected)
            for type in started {
                let flag = IntegrityFlag(sessionID: session.sessionID, type: type)
                session.recordFlag(flag)
                logger.log(flag)
            }
        }

        // Simulator demo: realistic sparse synthetic flags (discrete, no coalescing).
        camera.onSimulatorTick = { [session, logger] in
            guard Int.random(in: 0..<10) < 3,
                  let type = FlagType.cameraDetectable.randomElement()
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
