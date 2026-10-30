import AppKit
import DropwheelCore
import SwiftUI

enum WheelPurpose: String {
    case drag
    case click
    case preview
}

@MainActor
final class WheelModel: ObservableObject {
    @Published var items: [CatalogItem] = []
    @Published var highlighted: Int?
    @Published var mode: WheelMode = .convert
    @Published var summary = ""
    @Published var badge = ""
    @Published var emptyMessage = ""
    @Published var appeared = false
    @Published var purpose: WheelPurpose = .drag

    var selectedItem: CatalogItem? {
        guard let highlighted, items.indices.contains(highlighted) else { return nil }
        return items[highlighted]
    }

    func highlight(at point: CGPoint, viewSize: CGSize) {
        let index = Self.index(at: point, viewSize: viewSize, count: items.count)
        guard index != highlighted else { return }
        highlighted = index
        if index != nil {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    func cycle(_ delta: Int) {
        guard !items.isEmpty else { return }
        let start = highlighted ?? (delta > 0 ? -1 : 0)
        let next = Self.wrap(start + delta, items.count)
        guard next != highlighted else { return }
        highlighted = next
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    static func index(at point: CGPoint, viewSize: CGSize, count: Int) -> Int? {
        let x = Double(point.x - viewSize.width / 2)
        let y = Double(point.y - viewSize.height / 2)
        return WheelMetrics.hitIndex(x: x, y: y, count: count)
    }

    private static func wrap(_ value: Int, _ count: Int) -> Int {
        let remainder = value % count
        return remainder >= 0 ? remainder : remainder + count
    }
}

@MainActor
final class WheelController: NSObject {
    static let shared = WheelController()

    let model = WheelModel()
    private var panel: KeyablePanel?
    private var host: NSHostingView<WheelView>?
    private var timer: Timer?
    private var files: [URL] = []
    private(set) var isVisible = false

    func showPreview() {
        let sample = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Photo.png")
        present(files: [sample], mode: .convert, purpose: .preview, anchor: .center)
    }

    func showFiles(_ files: [URL]) {
        present(files: files, mode: .convert, purpose: .click, anchor: .center)
    }

    func showDrag(files: [URL], mode: WheelMode) {
        present(files: files, mode: mode, purpose: .drag, anchor: .cursor)
    }

    /// Keep the wheel where it opened, but rebuild the wedges when the dragged files or the key changes.
    func updateDrag(files: [URL], mode: WheelMode) {
        let incoming = files.map(\.standardizedFileURL.path)
        let current = self.files.map(\.standardizedFileURL.path)
        guard isVisible, model.purpose == .drag else {
            showDrag(files: files, mode: mode)
            return
        }
        if incoming == current, model.mode == mode { return }
        if incoming != current {
            model.highlighted = nil
        }
        self.files = files
        apply(files: files, mode: mode)
    }

    func switchMode(to mode: WheelMode) {
        guard isVisible, model.mode != mode else { return }
        apply(files: files, mode: mode)
    }

    func commitSelected() {
        guard let item = model.selectedItem else {
            dismiss(animated: true)
            return
        }
        commit(item)
    }

    func dismiss(animated: Bool) {
        stopTimer()
        isVisible = false
        panel?.orderOut(nil)
        model.appeared = false
    }

    func trackMouse() {
        guard isVisible, model.purpose == .drag, let panel, let host else { return }
        let screenPoint = NSEvent.mouseLocation
        let windowPoint = panel.convertPoint(fromScreen: screenPoint)
        let local = host.convert(windowPoint, from: nil)
        let point = host.isFlipped ? local : CGPoint(x: local.x, y: host.bounds.height - local.y)
        model.highlight(at: point, viewSize: host.bounds.size)
    }

    private func present(files: [URL], mode: WheelMode, purpose: WheelPurpose, anchor: Anchor) {
        self.files = files
        let firstShow = panel == nil || !isVisible
        ensurePanel()
        model.purpose = purpose
        apply(files: files, mode: mode)
        guard let panel else { return }
        panel.ignoresMouseEvents = purpose == .drag
        panel.allowsKey = purpose != .drag
        let size = panel.frame.size
        let origin = anchor == .cursor ? cursorOrigin(size: size) : centerOrigin(size: size)
        panel.setFrameOrigin(origin)
        if firstShow {
            model.appeared = false
            panel.orderFrontRegardless()
            isVisible = true
            if purpose != .drag {
                panel.makeKey()
            }
            DispatchQueue.main.async { [weak self] in
                self?.model.appeared = true
            }
        } else {
            panel.orderFrontRegardless()
            isVisible = true
        }
        if purpose == .drag {
            startTimer()
        } else {
            stopTimer()
        }
    }

    private func apply(files: [URL], mode: WheelMode) {
        let bins = BinaryAvailability.current()
        let items = Catalog.items(files: files, mode: mode, binaries: bins)
        model.mode = mode
        model.items = items
        model.summary = Catalog.summary(for: files)
        model.badge = Catalog.badge(for: files)
        model.emptyMessage = items.isEmpty ? Catalog.emptyMessage(files: files, mode: mode, binaries: bins) : ""
        if let highlighted = model.highlighted, !items.indices.contains(highlighted) {
            model.highlighted = nil
        }
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let side = WheelMetrics.windowSize
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: side, height: side),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: WheelView(
            model: model,
            onCommit: { [weak self] item in self?.commit(item) },
            onDismiss: { [weak self] in self?.dismiss(animated: true) }
        ))
        host.frame = NSRect(x: 0, y: 0, width: side, height: side)
        panel.contentView = host
        self.panel = panel
        self.host = host
    }

    private func commit(_ item: CatalogItem) {
        let chosenFiles = files
        let purpose = model.purpose
        dismiss(animated: false)
        if purpose == .preview {
            ProgressController.shared.flash("Preview only. Drag a real file, then tap Shift.")
            return
        }
        let real = chosenFiles.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !real.isEmpty else {
            ProgressController.shared.flash("That file is no longer there.")
            return
        }
        JobCenter.shared.run(files: real, operation: item.operation)
    }

    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.trackMouse()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func cursorOrigin(size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        return NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height / 2)
    }

    private func centerOrigin(size: NSSize) -> NSPoint {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
    }

    private enum Anchor {
        case cursor
        case center
    }
}

final class KeyablePanel: NSPanel {
    var allowsKey = false
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}
