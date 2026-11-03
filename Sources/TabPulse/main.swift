import Cocoa

// TabPulse: live Claude Code session status in the macOS menu bar and in Ghostty tab titles.
// Session state comes from ~/.claude/tabpulse/sessions/*.json, written by plugin/hooks/tabpulse-hook.sh.

let args = CommandLine.arguments
if args.contains("--version") {
    print("TabPulse \(StatusApp.version)")
    exit(0)
}
if let i = args.firstIndex(of: "--render-preview") {
    _ = NSApplication.shared
    Preview.render(to: i + 1 < args.count ? args[i + 1] : ".")
    exit(0)
}
if args.contains("--menu-demo") {
    Preview.menuDemo()
    exit(0)
}
if let i = args.firstIndex(of: "--style-gallery") {
    let filter = i + 1 < args.count && !args[i + 1].hasPrefix("-") ? args[i + 1] : nil
    Preview.gallery(only: filter)
    exit(0)
}

let app = NSApplication.shared
let delegate = StatusApp()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
