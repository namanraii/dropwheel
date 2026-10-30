import AppKit
import ApplicationServices
import DropwheelCore
import SwiftUI

enum Log {
    static var url: URL {
        let logs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs", isDirectory: true)
        return logs.appendingPathComponent("Dropwheel.log")
    }

    static func write(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        fputs(line, stderr)
        let target = url
        let existing = (try? String(contentsOf: target, encoding: .utf8)) ?? ""
        let trimmed = existing.count > 200_000 ? String(existing.suffix(80_000)) : existing
        try? (trimmed + line).write(to: target, atomically: true, encoding: .utf8)
    }
}

enum MenuIcon {
    static func image() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let ring = rect.insetBy(dx: 2.2, dy: 2.2)
            let path = NSBezierPath(ovalIn: ring)
            path.lineWidth = 1.6
            NSColor.black.setStroke()
            path.stroke()
            let dot = NSRect(x: rect.midX - 1.7, y: ring.maxY - 3.4, width: 3.4, height: 3.4)
            NSColor.black.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static var retained: AppDelegate?

    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = MenuIcon.image()
        item.button?.toolTip = "Dropwheel"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        DragMonitor.shared.start()
        Log.write("Dropwheel launched")
        if !UserDefaults.standard.bool(forKey: "DropwheelDidShowIntro") {
            UserDefaults.standard.set(true, forKey: "DropwheelDidShowIntro")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                WheelController.shared.showPreview()
            }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let legend = NSMenuItem(title: "Drag a file, then tap Shift", action: nil, keyEquivalent: "")
        legend.isEnabled = false
        menu.addItem(legend)
        menu.addItem(disabled("⇧  Opens the wheel"))
        menu.addItem(disabled("⌘  Tools, after it is open"))
        menu.addItem(disabled("⌃  Actions, after it is open"))
        menu.addItem(.separator())
        menu.addItem(item("Convert Files…", #selector(convertFiles), "o"))
        menu.addItem(item("Try the Wheel", #selector(tryWheel), ""))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(showSettings), ","))
        if !AXIsProcessTrusted() {
            menu.addItem(item("Enable Keyboard Cancel…", #selector(enableKeyboard), ""))
        }
        menu.addItem(item("Open Log", #selector(openLog), ""))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Dropwheel", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func convertFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.message = "Choose files. Dropwheel opens the wheel next."
        AppActivation.activate()
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        WheelController.shared.showFiles(panel.urls)
    }

    @objc private func tryWheel() {
        WheelController.shared.showPreview()
    }

    @objc private func showSettings() {
        SettingsController.shared.show()
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(Log.url)
    }

    @objc private func enableKeyboard() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func installMainMenu() {
        let main = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Dropwheel", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)
        NSApp.mainMenu = main
    }
}

@main
enum Main {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.contains("--help") || args.contains("-h") {
            print(helpText)
            return
        }
        if args.contains("--self-check") {
            Task {
                let ok = await SelfCheck.run()
                exit(ok ? 0 : 1)
            }
            dispatchMain()
        }
        if let index = args.firstIndex(of: "--convert") {
            runConvert(args, index: index)
            return
        }
        if let index = args.firstIndex(of: "--snapshot") {
            Task { @MainActor in
                runSnapshot(args, index: index)
                exit(0)
            }
            dispatchMain()
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        AppDelegate.retained = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

private let helpText = """
Dropwheel converts files on this Mac.

Drag a file, then tap Shift to open the wheel.
Command and Option do not open it.
After it is open, Command shows tools and Control shows actions.

Dropwheel --convert file.png jpg
Dropwheel --snapshot /tmp/dropwheel-preview
"""

private func runConvert(_ args: [String], index: Int) {
    guard index + 2 < args.count else {
        fputs("Usage: Dropwheel --convert file format\n", stderr)
        exit(2)
    }
    let source = URL(fileURLWithPath: args[index + 1])
    let name = args[index + 2].lowercased()
    guard let format = Format(rawValue: name) else {
        fputs("Unknown format \(name).\n", stderr)
        exit(2)
    }
    Task {
        do {
            let urls = try await Engine.runOne(.convert(format), file: source)
            for url in urls { print(url.path) }
            exit(0)
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
    dispatchMain()
}

@MainActor
private func runSnapshot(_ args: [String], index: Int) {
    let directory: URL
    if index + 1 < args.count {
        directory = URL(fileURLWithPath: args[index + 1])
    } else {
        directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dropwheel-preview")
    }
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    _ = NSApplication.shared
    let sample = URL(fileURLWithPath: "/tmp/Photo.png")
    let bins = BinaryAvailability.current()
    let shots: [(String, WheelMode, Int?)] = [
        ("convert", .convert, 0),
        ("tools", .tools, 0),
        ("actions", .actions, 1),
    ]
    for shot in shots {
        let model = WheelModel()
        model.purpose = .preview
        model.appeared = true
        model.mode = shot.1
        model.items = Catalog.items(files: [sample], mode: shot.1, binaries: bins)
        model.summary = "Photo.png"
        model.badge = "Image"
        model.highlighted = shot.2
        let view = WheelView(model: model, backdrop: Color(red: 0.93, green: 0.94, blue: 0.96), onCommit: { _ in }, onDismiss: {})
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: WheelMetrics.windowSize, height: WheelMetrics.windowSize)
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            fputs("Could not render \(shot.0)\n", stderr)
            exit(1)
        }
        let url = directory.appendingPathComponent("\(shot.0).png")
        try? png.write(to: url)
        print(url.path)
    }
}
