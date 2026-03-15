import Foundation

/// Parses the 2-line event log format written by gitbeacon-daemon.sh.
///
/// Line 1: `[HH:MM] icon LABEL  (repo)\tURL`  (URL and tab are optional)
/// Line 2: `         title`                     (9-space prefix)
enum EventParser {

    /// Parse raw log text into events. Lines are consumed in pairs.
    static func parse(_ text: String) -> [GitBeaconEvent] {
        let lines = text.components(separatedBy: "\n")
        var events: [GitBeaconEvent] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Header lines start with "["
            guard line.hasPrefix("[") else {
                i += 1
                continue
            }

            // Read the detail line if available
            let detail: String
            if i + 1 < lines.count, !lines[i + 1].hasPrefix("[") {
                detail = lines[i + 1].trimmingCharacters(in: .whitespaces)
                i += 2
            } else {
                detail = ""
                i += 1
            }

            if let event = parseHeaderLine(line, detail: detail) {
                events.append(event)
            }
        }

        return events
    }

    /// Parse a single header line + its detail text into a GitBeaconEvent.
    ///
    /// Format: `[HH:MM] icon LABEL  (repo)\tURL`
    /// The tab+URL portion is optional.
    private static func parseHeaderLine(_ line: String, detail: String) -> GitBeaconEvent? {
        // Extract timestamp: [HH:MM]
        guard let closeBracket = line.firstIndex(of: "]") else { return nil }
        let timeStart = line.index(after: line.startIndex) // skip "["
        let timestamp = String(line[timeStart..<closeBracket])

        // Everything after "] "
        let afterTime = line[line.index(closeBracket, offsetBy: 2)...]

        // Split on tab to separate header from URL
        let parts = afterTime.split(separator: "\t", maxSplits: 1)
        let headerPart = String(parts[0])
        let url: URL? = parts.count > 1 ? URL(string: String(parts[1])) : nil

        // headerPart: "icon LABEL  (repo)"
        // Extract repo from parentheses at the end
        guard let parenOpen = headerPart.lastIndex(of: "("),
              let parenClose = headerPart.lastIndex(of: ")") else { return nil }
        let repo = String(headerPart[headerPart.index(after: parenOpen)..<parenClose])

        // Everything before "  (repo)" is "icon LABEL"
        let beforeRepo = headerPart[..<parenOpen].trimmingCharacters(in: .whitespaces)

        // First character cluster is the emoji icon, rest is the label
        guard let firstSpace = beforeRepo.firstIndex(of: " ") else { return nil }
        let icon = String(beforeRepo[..<firstSpace])
        let label = beforeRepo[beforeRepo.index(after: firstSpace)...]
            .trimmingCharacters(in: .whitespaces)

        return GitBeaconEvent(
            timestamp: timestamp,
            icon: icon,
            label: label,
            repo: repo,
            title: detail,
            url: url
        )
    }
}
