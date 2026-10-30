import AppKit
import DropwheelCore

/// The wheel stays where it opened. The pointer moves onto a wedge, and the file
/// is still owned by the drag in Finder. Mouse-up is what commits.
@MainActor
final class DragMonitor {
    static let shared = DragMonitor()

    private var monitors: [Any] = []
    private var downPoint: CGPoint?
    private var moved = false
    private var files: [URL] = []
    private var lastFlags: NSEvent.ModifierFlags = []
    private var lastStamp: (NSEvent.EventType, TimeInterval)?
    private var loggedEmptyDrag = false

    func start() {
        lastFlags = NSEvent.modifierFlags.intersection([.shift, .command, .option, .control])
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .flagsChanged, .keyDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            Task { @MainActor in
                self?.handle(event, local: false)
            }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let consume = MainActor.assumeIsolated {
                self?.handle(event, local: true) ?? false
            }
            return consume ? nil : event
        }) {
            monitors.append(local as Any)
        }
    }

    @discardableResult
    func handle(_ event: NSEvent, local: Bool) -> Bool {
        let stamp = (event.type, event.timestamp)
        if lastStamp?.0 == stamp.0 && lastStamp?.1 == stamp.1 { return false }
        lastStamp = stamp

        switch event.type {
        case .leftMouseDown:
            downPoint = NSEvent.mouseLocation
            moved = false
            files = []
            loggedEmptyDrag = false
            let wheel = WheelController.shared
            if wheel.isVisible && wheel.model.purpose == .drag {
                wheel.dismiss(animated: false)
            } else if wheel.isVisible && !local {
                wheel.dismiss(animated: true)
            }
            return false
        case .rightMouseDown:
            if WheelController.shared.isVisible {
                WheelController.shared.dismiss(animated: true)
                return true
            }
            return false
        case .leftMouseDragged:
            guard let downPoint else { return false }
            let now = NSEvent.mouseLocation
            guard hypot(now.x - downPoint.x, now.y - downPoint.y) >= 6 else { return false }
            moved = true
            _ = refreshDraggedFiles()
            guard !files.isEmpty else { return false }
            let wheel = WheelController.shared
            if wheel.isVisible && wheel.model.purpose == .drag {
                wheel.updateDrag(files: files, mode: wheel.model.mode)
                return false
            }
            if Self.plainShift(NSEvent.modifierFlags) {
                wheel.updateDrag(files: files, mode: .convert)
            }
            return false
        case .flagsChanged:
            let held = event.modifierFlags
            let newFlags = held.intersection([.shift, .command, .option, .control])
            let pressed = newFlags.subtracting(lastFlags)
            lastFlags = newFlags
            guard moved, let mode = Self.mode(pressed: pressed, held: held) else { return false }
            _ = refreshDraggedFiles()
            guard !files.isEmpty else { return false }
            WheelController.shared.updateDrag(files: files, mode: mode)
            return false
        case .leftMouseUp:
            let wheel = WheelController.shared
            if wheel.isVisible && wheel.model.purpose == .drag {
                if wheel.model.selectedItem != nil {
                    wheel.commitSelected()
                } else {
                    wheel.dismiss(animated: true)
                }
            }
            downPoint = nil
            files = []
            moved = false
            return false
        case .keyDown:
            return handleKey(event)
        default:
            return false
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let wheel = WheelController.shared
        guard wheel.isVisible else { return false }
        switch event.keyCode {
        case 53:
            wheel.dismiss(animated: true)
            return true
        case 36, 76:
            wheel.commitSelected()
            return true
        case 123, 125:
            wheel.model.cycle(-1)
            return true
        case 124, 126:
            wheel.model.cycle(1)
            return true
        default:
            return false
        }
    }

    /// The drag pasteboard can still list the previous file for the first moments of a new drag.
    /// Keep reading it, and replace the wheel as soon as the paths change.
    private func refreshDraggedFiles() -> Bool {
        let latest = Self.readDraggedFiles()
        if latest.isEmpty {
            if !loggedEmptyDrag && moved {
                loggedEmptyDrag = true
                let types = NSPasteboard(name: .drag).types?.map(\.rawValue) ?? []
                Log.write("Drag had no files. Pasteboard types: \(types.joined(separator: ", "))")
            }
            return !files.isEmpty
        }
        let incoming = latest.map(\.standardizedFileURL.path)
        let current = files.map(\.standardizedFileURL.path)
        if incoming != current {
            files = latest
            Log.write("Drag files: \(latest.map(\.lastPathComponent).joined(separator: ", "))")
        }
        return true
    }

    static func readDraggedFiles() -> [URL] {
        let pasteboard = NSPasteboard(name: .drag)
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
        ]) as? [URL], !urls.isEmpty {
            return urls
        }
        let legacy = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        if let names = pasteboard.propertyList(forType: legacy) as? [String], !names.isEmpty {
            return names.map { URL(fileURLWithPath: $0) }
        }
        if let raw = pasteboard.string(forType: .fileURL), let url = URL(string: raw) {
            return [url]
        }
        return []
    }

    /// Shift alone opens the convert wheel. Command and Option do nothing until it is open.
    /// After it is open, Command shows tools and Control shows actions.
    static func mode(pressed: NSEvent.ModifierFlags, held: NSEvent.ModifierFlags) -> WheelMode? {
        let wheel = WheelController.shared
        let open = wheel.isVisible && wheel.model.purpose == .drag
        if !open {
            guard pressed.contains(.shift), plainShift(held) else { return nil }
            return .convert
        }
        if pressed.contains(.command) { return .tools }
        if pressed.contains(.control) { return .actions }
        if pressed.contains(.shift) { return .convert }
        return nil
    }

    static func plainShift(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.contains(.shift)
            && !flags.contains(.command)
            && !flags.contains(.option)
            && !flags.contains(.control)
    }
}
