import SwiftUI

@main
struct ProctorLensApp: App {

    init() {
        loadRocketSimConnect()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }

    /// Loads RocketSim Connect in DEBUG builds only.
    /// This is what lets RocketSim inject a virtual camera into the simulator,
    /// bypassing the broken FigCaptureSourceSimulator stack. It is completely
    /// stripped from release builds.
    private func loadRocketSimConnect() {
        #if DEBUG
        guard Bundle(path: "/Applications/RocketSim.app/Contents/Frameworks/RocketSimConnectLinker.nocache.framework")?.load() == true else {
            print("[RocketSim] Connect framework failed to load — is RocketSim installed at /Applications?")
            return
        }
        print("[RocketSim] Connect loaded.")
        #endif
    }
}
