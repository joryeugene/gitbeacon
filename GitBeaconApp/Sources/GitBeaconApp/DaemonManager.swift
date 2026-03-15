import Foundation

/// Manages the lifecycle of gitbeacon-daemon.sh.
/// Not @MainActor so it can be called from any context.
/// Published property updates are dispatched to main thread explicitly.
final class DaemonManager: ObservableObject {
    @Published var isRunning = false
    @Published var errorMessage: String?

    private var process: Process?
    private var healthTimer: Timer?

    private let stateDir: String
    private let daemonScriptPath: String
    private let lockDir: String

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        stateDir = "\(home)/.config/gitbeacon"
        daemonScriptPath = "\(stateDir)/gitbeacon-daemon.sh"
        lockDir = "\(stateDir)/.daemon.lock"
    }

    deinit {
        healthTimer?.invalidate()
    }

    /// Start or adopt the daemon. Called on app launch.
    func start() {
        // Ensure state dir exists
        try? FileManager.default.createDirectory(
            atPath: stateDir,
            withIntermediateDirectories: true
        )

        // Initialize sfx-state if missing
        let sfxPath = "\(stateDir)/sfx-state"
        if !FileManager.default.fileExists(atPath: sfxPath) {
            try? "ON".write(toFile: sfxPath, atomically: true, encoding: .utf8)
        }

        // Touch required files
        for name in ["events.log", "seen-ids"] {
            let path = "\(stateDir)/\(name)"
            if !FileManager.default.fileExists(atPath: path) {
                FileManager.default.createFile(atPath: path, contents: nil)
            }
        }

        // Install daemon script from app bundle if needed
        installDaemonScript()

        // Try adopting an existing healthy daemon first
        if let existingPid = lockPid(), isProcessAlive(existingPid) {
            isRunning = true
            startHealthCheck()
            return
        }

        spawnDaemon()
    }

    /// Kill the daemon. Called on app quit.
    func stop() {
        healthTimer?.invalidate()
        healthTimer = nil

        if let pid = lockPid(), isProcessAlive(pid) {
            kill(pid, SIGTERM)
        }

        process?.terminate()
        process = nil
        isRunning = false
    }

    /// Restart: kill then re-spawn.
    func restart() {
        stop()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.spawnDaemon()
        }
    }

    // MARK: - Private

    private func spawnDaemon() {
        guard FileManager.default.fileExists(atPath: daemonScriptPath) else {
            DispatchQueue.main.async { [weak self] in
                self?.errorMessage = "Daemon script not found"
                self?.isRunning = false
            }
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: resolveBash())
        proc.arguments = [daemonScriptPath]
        proc.currentDirectoryURL = URL(fileURLWithPath: stateDir)

        // Build PATH with bundled binaries + Homebrew + system paths
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = buildDaemonPath()
        proc.environment = env

        proc.terminationHandler = { [weak self] p in
            DispatchQueue.main.async {
                self?.isRunning = false
                if p.terminationStatus != 0 {
                    self?.errorMessage = "Daemon exited with code \(p.terminationStatus)"
                }
            }
        }

        do {
            try proc.run()
            process = proc
            DispatchQueue.main.async { [weak self] in
                self?.isRunning = true
                self?.errorMessage = nil
            }
            startHealthCheck()
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.errorMessage = "Failed to launch daemon: \(error.localizedDescription)"
                self?.isRunning = false
            }
        }
    }

    private func startHealthCheck() {
        DispatchQueue.main.async { [weak self] in
            self?.healthTimer?.invalidate()
            self?.healthTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
                guard let self else { return }
                if let pid = self.lockPid(), self.isProcessAlive(pid) {
                    self.isRunning = true
                } else {
                    self.isRunning = false
                }
            }
        }
    }

    private func lockPid() -> pid_t? {
        let pidPath = "\(lockDir)/pid"
        guard let data = FileManager.default.contents(atPath: pidPath),
              let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(str) else { return nil }
        return pid
    }

    private func isProcessAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0
    }

    /// Find bash 4+ (required for associative arrays in the daemon script).
    /// macOS ships bash 3.2 at /bin/bash; Homebrew installs bash 5 elsewhere.
    private func resolveBash() -> String {
        for path in ["/opt/homebrew/bin/bash", "/usr/local/bin/bash"] {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return "/bin/bash"
    }

    /// Build a complete PATH for the daemon subprocess.
    /// Bundled binaries first, then common Homebrew/MacPorts locations,
    /// then the system PATH.
    private func buildDaemonPath() -> String {
        var paths: [String] = []

        // Bundled binaries (for release builds with gh+jq inside .app)
        if let resourcePath = Bundle.main.resourcePath {
            let binPath = "\(resourcePath)/bin"
            if FileManager.default.fileExists(atPath: binPath) {
                paths.append(binPath)
            }
        }

        // Homebrew (Apple Silicon and Intel)
        paths.append("/opt/homebrew/bin")
        paths.append("/usr/local/bin")

        // MacPorts
        paths.append("/opt/local/bin")

        // System
        paths.append("/usr/bin")
        paths.append("/bin")
        paths.append("/usr/sbin")
        paths.append("/sbin")

        // Also include existing PATH if present
        if let existing = ProcessInfo.processInfo.environment["PATH"] {
            for p in existing.split(separator: ":").map(String.init) {
                if !paths.contains(p) {
                    paths.append(p)
                }
            }
        }

        return paths.joined(separator: ":")
    }

    private func installDaemonScript() {
        guard let bundledScript = Bundle.main.path(forResource: "gitbeacon-daemon", ofType: "sh") else {
            return
        }

        let installed = daemonScriptPath
        let fm = FileManager.default

        if fm.fileExists(atPath: installed),
           let bundledAttrs = try? fm.attributesOfItem(atPath: bundledScript),
           let installedAttrs = try? fm.attributesOfItem(atPath: installed),
           let bundledSize = bundledAttrs[.size] as? UInt64,
           let installedSize = installedAttrs[.size] as? UInt64,
           bundledSize == installedSize {
            return
        }

        try? fm.copyItem(atPath: bundledScript, toPath: installed)

        var perms = (try? fm.attributesOfItem(atPath: installed))?[.posixPermissions] as? Int ?? 0o644
        perms |= 0o111
        try? fm.setAttributes([.posixPermissions: perms], ofItemAtPath: installed)
    }
}
