import SwiftUI

/// Root view — shows the quiz shell while a session is active,
/// and the reviewer dashboard after it ends.
struct ContentView: View {

    @StateObject private var session = SessionManager()
    @State private var showDashboard = false

    /// Camera monitor lives here so it shares the view's lifetime.
    private let camera = CameraMonitor()

    var body: some View {
        ZStack(alignment: .topTrailing) {

            if showDashboard {
                DashboardView(flags: session.flags)
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
            camera.start()
        }
        .onDisappear {
            camera.stop()
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
