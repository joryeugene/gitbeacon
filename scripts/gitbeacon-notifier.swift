import AppKit
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        var title = "", body = "", subtitle = ""
        var i = 1
        let argv = CommandLine.arguments
        while i < argv.count {
            let flag = argv[i]; i += 1
            if flag == "-version" { print("1.0"); exit(0) }
            guard i < argv.count else { continue }
            switch flag {
            case "-title":    title    = argv[i]; i += 1
            case "-message":  body     = argv[i]; i += 1
            case "-subtitle": subtitle = argv[i]; i += 1
            default: break
            }
        }
        guard !body.isEmpty else { NSApp.terminate(nil); return }
        send(title: title, body: body, subtitle: subtitle)
    }

    func send(title: String, body: String, subtitle: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [self] settings in
            if settings.authorizationStatus == .notDetermined {
                center.requestAuthorization(options: [.alert, .sound]) { _, _ in
                    self.deliver(center: center, title: title, body: body, subtitle: subtitle)
                }
            } else {
                deliver(center: center, title: title, body: body, subtitle: subtitle)
            }
        }
    }

    func deliver(center: UNUserNotificationCenter, title: String, body: String, subtitle: String) {
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized ||
                  settings.authorizationStatus == .provisional else { exit(1) }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            if !subtitle.isEmpty { content.subtitle = subtitle }
            let request = UNNotificationRequest(
                identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(request) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSApp.terminate(nil)
                }
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
