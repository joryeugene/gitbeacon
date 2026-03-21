import Foundation
import Combine

/// Watches ~/.config/gitbeacon/events.log for changes using kqueue (DispatchSource)
/// with a Timer fallback for edge cases like file rotation.
final class EventLogWatcher: ObservableObject {
    @Published var events: [GitBeaconEvent] = []
    @Published var totalEventCount: Int = 0

    private let logPath: String
    private var fileHandle: FileHandle?
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var fallbackTimer: Timer?
    private var lastInode: UInt64 = 0
    private var lastOffset: UInt64 = 0

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.logPath = "\(home)/.config/gitbeacon/events.log"
        reloadFull()
        openDispatchSource()

        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkForChanges()
        }
    }

    deinit {
        dispatchSource?.cancel()
        fileHandle?.closeFile()
        fallbackTimer?.invalidate()
    }

    private func openDispatchSource() {
        dispatchSource?.cancel()
        fileHandle?.closeFile()

        guard FileManager.default.fileExists(atPath: logPath) else { return }
        guard let handle = FileHandle(forReadingAtPath: logPath) else { return }
        fileHandle = handle
        lastInode = inodeForPath(logPath)
        lastOffset = handle.seekToEndOfFile()

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: handle.fileDescriptor,
            eventMask: [.write, .extend, .rename, .delete],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.onFileChanged()
        }

        source.setCancelHandler { [weak handle] in
            handle?.closeFile()
        }

        source.resume()
        dispatchSource = source
    }

    private func onFileChanged() {
        guard let handle = fileHandle else { return }
        handle.seek(toFileOffset: lastOffset)
        let newData = handle.readDataToEndOfFile()
        lastOffset = handle.offsetInFile

        guard !newData.isEmpty, let text = String(data: newData, encoding: .utf8) else { return }

        let newEvents = EventParser.parse(text)
        if !newEvents.isEmpty {
            totalEventCount += newEvents.count
            events.append(contentsOf: newEvents)
            if events.count > 500 {
                events = Array(events.suffix(500))
            }
        }
    }

    private func checkForChanges() {
        guard FileManager.default.fileExists(atPath: logPath) else { return }

        let currentInode = inodeForPath(logPath)
        if currentInode != lastInode {
            reloadFull()
            openDispatchSource()
        }
    }

    private func reloadFull() {
        guard let data = FileManager.default.contents(atPath: logPath),
              let text = String(data: data, encoding: .utf8) else {
            events = []
            return
        }
        events = EventParser.parse(text)
        totalEventCount = events.count
        if events.count > 500 {
            events = Array(events.suffix(500))
        }
    }

    private func inodeForPath(_ path: String) -> UInt64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let inode = attrs[.systemFileNumber] as? UInt64 else { return 0 }
        return inode
    }
}
