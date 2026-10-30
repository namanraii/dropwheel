import AppKit

@MainActor
final class FloatController {
    static let shared = FloatController()
    private var panels: [FloatPanel] = []

    func float(_ files: [URL]) {
        let origin = NSEvent.mouseLocation
        for (index, url) in files.enumerated() {
            let panel = FloatPanel(url: url)
            panel.setFrameOrigin(NSPoint(x: origin.x + 24, y: origin.y - 90 - CGFloat(index) * 72))
            panel.orderFrontRegardless()
            panel.onClose = { [weak self, weak panel] in
                self?.panels.removeAll { $0 === panel }
            }
            panels.append(panel)
        }
    }
}

final class FloatPanel: NSPanel {
    var onClose: (() -> Void)?

    init(url: URL) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 248, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        contentView = FloatContentView(url: url) { [weak self] in
            self?.onClose?()
            self?.close()
        }
    }
}

final class FloatContentView: NSView {
    private let fileURL: URL
    private let onClose: () -> Void
    private let iconView: DragIconView

    init(url: URL, onClose: @escaping () -> Void) {
        self.fileURL = url
        self.onClose = onClose
        self.iconView = DragIconView(url: url)
        super.init(frame: NSRect(x: 0, y: 0, width: 248, height: 64))
        wantsLayer = true

        let effect = NSVisualEffectView(frame: bounds)
        effect.material = .hudWindow
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true
        effect.autoresizingMask = [.width, .height]
        addSubview(effect)

        iconView.frame = NSRect(x: 10, y: 12, width: 40, height: 40)
        iconView.image = NSWorkspace.shared.icon(forFile: url.path)
        addSubview(iconView)

        let label = NSTextField(labelWithString: url.lastPathComponent)
        label.frame = NSRect(x: 58, y: 22, width: 150, height: 20)
        label.lineBreakMode = .byTruncatingMiddle
        label.font = .systemFont(ofSize: 13, weight: .medium)
        addSubview(label)

        let close = NSButton(frame: NSRect(x: 216, y: 36, width: 22, height: 22))
        close.isBordered = false
        close.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")
        close.target = self
        close.action = #selector(closeClicked)
        addSubview(close)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    @objc private func closeClicked() { onClose() }
}

final class DragIconView: NSImageView, NSDraggingSource {
    let fileURL: URL

    init(url: URL) {
        self.fileURL = url
        super.init(frame: .zero)
        imageScaling = .scaleProportionallyUpOrDown
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func mouseDragged(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
        let icon = image ?? NSImage()
        item.setDraggingFrame(bounds, contents: icon)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}
