import SwiftUI

/// Shown before the quiz loads — ensures the user understands camera monitoring
/// is required and blocks entry if permission was denied.
struct CameraGateView: View {

    let state: CameraState
    let onProceed: () -> Void   // called only when state is .active or .simulatorDemo

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            icon
            heading
            description

            Spacer()

            actionArea

            Spacer()
        }
        .padding(40)
        .onChange(of: state) { _, newState in
            // Auto-advance once the camera becomes ready — no tap needed.
            if newState == .active || newState == .simulatorDemo {
                onProceed()
            }
        }
    }

    // MARK: - Sub-views

    private var icon: some View {
        Image(systemName: iconName)
            .font(.system(size: 72))
            .foregroundStyle(iconColor)
    }

    private var heading: some View {
        Text(headingText)
            .font(.largeTitle.bold())
            .multilineTextAlignment(.center)
    }

    private var description: some View {
        Text(descriptionText)
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
    }

    @ViewBuilder
    private var actionArea: some View {
        switch state {
        case .unknown, .requesting:
            ProgressView("Checking camera…")

        case .permissionDenied:
            VStack(spacing: 16) {
                Text("Camera access is required to take this exam.\nOpen Settings and enable camera for ProctorLens.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }

        case .active, .simulatorDemo:
            // Auto-proceeded via onChange — show a brief "Starting…" so there's
            // no blank flash if the view lingers for a frame.
            ProgressView("Starting session…")
        }
    }

    // MARK: - Computed strings / colors

    private var iconName: String {
        switch state {
        case .permissionDenied: return "camera.slash"
        default:                return "camera.fill"
        }
    }

    private var iconColor: Color {
        switch state {
        case .permissionDenied: return .red
        case .simulatorDemo:    return .orange
        default:                return .blue
        }
    }

    private var headingText: String {
        switch state {
        case .permissionDenied: return "Camera Access Required"
        case .simulatorDemo:    return "Demo Mode"
        default:                return "Camera Monitoring"
        }
    }

    private var descriptionText: String {
        switch state {
        case .permissionDenied:
            return "This exam requires continuous camera monitoring to verify your identity. You cannot proceed without granting access."
        case .simulatorDemo:
            return "No camera hardware detected. Running in demo mode — synthetic integrity events will be generated so you can see the full pipeline."
        default:
            return "ProctorLens monitors you through the front camera throughout this exam. No video is recorded — only integrity flags are logged."
        }
    }
}

#Preview {
    CameraGateView(state: .permissionDenied) {}
}
