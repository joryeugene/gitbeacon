import SwiftUI

struct MenuBarView: View {
    @ObservedObject var eventLog: EventLogWatcher
    @ObservedObject var daemon: DaemonManager
    @ObservedObject var sound: SoundManager

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            eventListSection
            Divider()
            controlsSection
        }
        .frame(width: 360)
        .onAppear {
            daemon.start()
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        HStack {
            Text("GitBeacon")
                .font(.headline)

            Circle()
                .fill(daemon.isRunning ? .green : .red)
                .frame(width: 8, height: 8)

            Spacer()

            Text("\(eventLog.totalEventCount) events")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var eventListSection: some View {
        if let error = daemon.errorMessage {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Restart Daemon") {
                    daemon.restart()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .padding()
        } else if eventLog.events.isEmpty {
            VStack(spacing: 8) {
                Text("No events yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Waiting for GitHub notifications...")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(eventLog.events.suffix(50).reversed()) { event in
                        EventRow(event: event)
                            .onTapGesture {
                                if let url = event.url {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                    }
                }
            }
            .frame(maxHeight: 400)

            if eventLog.events.count >= 500 {
                Text("Showing last 500")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
            }
        }
    }

    private var controlsSection: some View {
        HStack(spacing: 12) {
            Button {
                sound.toggle()
            } label: {
                Label(
                    sound.soundEnabled ? "Sound ON" : "Sound OFF",
                    systemImage: sound.soundEnabled ? "speaker.wave.2" : "speaker.slash"
                )
                .font(.caption)
            }
            .buttonStyle(.plain)
            .focusable(false)

            Spacer()

            Button("Clear") {
                clearLog()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .focusable(false)

            Divider()
                .frame(height: 12)

            Button("Quit") {
                daemon.stop()
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .focusable(false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Actions

    private func clearLog() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let logPath = "\(home)/.config/gitbeacon/events.log"
        try? "".write(toFile: logPath, atomically: true, encoding: .utf8)
        eventLog.events = []
        eventLog.totalEventCount = 0
    }
}

struct EventRow: View {
    let event: GitBeaconEvent

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(event.icon)
                .font(.title3)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(event.label)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text(event.timestamp)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(event.repo)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !event.title.isEmpty {
                    Text(event.title)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onHover { hovering in
            if event.url != nil {
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
    }
}
