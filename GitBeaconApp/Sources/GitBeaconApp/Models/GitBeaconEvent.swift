import Foundation

struct GitBeaconEvent: Identifiable, Equatable {
    let id = UUID()
    let timestamp: String   // "HH:MM"
    let icon: String        // emoji
    let label: String       // "Approved", "CI passed", etc.
    let repo: String        // "owner/repo"
    let title: String       // detail line
    let url: URL?           // GitHub URL, nil if absent
}
