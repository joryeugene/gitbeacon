import Foundation

/// Reads and writes the sfx-state file to toggle sound on/off.
/// The daemon reads this file each poll cycle, so changes take effect immediately.
final class SoundManager: ObservableObject {
    @Published var soundEnabled = true

    private let sfxPath: String

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        sfxPath = "\(home)/.config/gitbeacon/sfx-state"
        reload()
    }

    func toggle() {
        soundEnabled.toggle()
        let value = soundEnabled ? "ON" : "OFF"
        try? value.write(toFile: sfxPath, atomically: true, encoding: .utf8)
    }

    func reload() {
        guard let data = FileManager.default.contents(atPath: sfxPath),
              let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            soundEnabled = true
            return
        }
        soundEnabled = (str == "ON")
    }
}
