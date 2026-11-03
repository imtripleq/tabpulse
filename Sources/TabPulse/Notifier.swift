import Foundation
import UserNotifications

/// Finished-session banners. TabPulse's own notifications come first, because clicking one jumps to the tab.
/// macOS refuses them on some Macs (often for apps that aren't notarized), and then the banner goes out
/// through `osascript`, which every Mac allows but shows under Script Editor's name.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    var onClick: ((String) -> Void)?
    /// UNUserNotificationCenter throws without a real app bundle, e.g. under `swift run` or Xcode's Run.
    private let bundled = Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"

    /// Asks once at launch so the permission prompt shows up right away, not on the first finished session.
    func start() {
        guard bundled else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error { NSLog("TabPulse: own notifications unavailable, using osascript (\(error.localizedDescription))") }
        }
    }

    func post(title: String, body: String, tty: String) {
        guard bundled else { Self.postWithOsascript(title: title, body: body); return }
        // Asking again is silent once answered, and picks up changes made in System Settings since launch.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default
                content.userInfo = ["tty": tty]
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            } else if error != nil {
                Self.postWithOsascript(title: title, body: body)
            }
            // Neither: you turned TabPulse's notifications off, so stay quiet.
        }
    }

    /// Text goes in as arguments rather than into the script, so a tab title can't change what runs.
    private static func postWithOsascript(title: String, body: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "on run argv", "-e", "display notification (item 2 of argv) with title (item 1 of argv)",
                       "-e", "end run", title, body]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        let tty = response.notification.request.content.userInfo["tty"] as? String ?? ""
        DispatchQueue.main.async { self.onClick?(tty) }
        done()
    }
}
