import AppKit
import SwiftUI

private func enforceOneInstance() {
    let peers = NSRunningApplication.runningApplications(
        withBundleIdentifier: Bundle.main.bundleIdentifier ?? ""
    )
    if peers.count > 1 {
        exit(0)
    }
}

final class AppState: ObservableObject {
    static let shared: AppState = {
        enforceOneInstance()
        let state = AppState()
        state.daemon.start()
        return state
    }()

    let eventLog = EventLogWatcher()
    let daemon = DaemonManager()
    let sound = SoundManager()

    private init() {}
}

@main
struct GitBeaconApp: App {
    @ObservedObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                eventLog: state.eventLog,
                daemon: state.daemon,
                sound: state.sound
            )
        } label: {
            Label("GitBeacon", systemImage: "bell.badge")
        }
        .menuBarExtraStyle(.window)
    }
}
