import AppKit
import DropwheelCore
import SwiftUI

enum RowPhase: Equatable {
    case waiting
    case running
    case done
    case failed
}

struct ProgressRow: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var detail: String
    var phase: RowPhase
}

@MainActor
final class ProgressModel: ObservableObject {
    @Published var rows: [ProgressRow] = []
    @Published var finished = false
    var onClose: () -> Void = {}
    var onReveal: () -> Void = {}

    func close() { onClose() }
    func reveal() { onReveal() }
}

/// 16px ring, track #b6bfb3, top edge #f35b28, one turn every 0.7s.
struct ProcessingSpinner: View {
    @State private var spinning = false

    var body: some View {
        Circle()
            .stroke(Color(red: 182 / 255, green: 191 / 255, blue: 179 / 255), lineWidth: 2)
            .overlay(
                Circle()
                    .trim(from: 0, to: 0.25)
                    .stroke(Color(red: 243 / 255, green: 91 / 255, blue: 40 / 255), lineWidth: 2)
            )
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .frame(width: 16, height: 16)
            .onAppear {
                withAnimation(.linear(duration: 0.7).repeatForever(autoreverses: false)) {
                    spinning = true
                }
            }
    }
}

struct ProgressListView: View {
    @ObservedObject var model: ProgressModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Dropwheel")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                Button(action: model.close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            ForEach(model.rows) { row in
                HStack(alignment: .top, spacing: 8) {
                    phaseIcon(row.phase)
                        .frame(width: 16, height: 16)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(row.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(row.phase == .failed ? Color.red : Color.secondary)
                            .lineLimit(3)
                    }
                }
            }
            if model.finished && model.rows.contains(where: { $0.phase == .done }) {
                Button("Show in Finder", action: model.reveal)
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func phaseIcon(_ phase: RowPhase) -> some View {
        switch phase {
        case .waiting:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        case .running:
            ProcessingSpinner()
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}

@MainActor
final class ProgressController {
    static let shared = ProgressController()

    private let model = ProgressModel()
    private var panel: NSPanel?
    private var closeTask: Task<Void, Never>?
    private var revealOutputs: [URL] = []

    func begin(_ rows: [ProgressRow]) {
        closeTask?.cancel()
        model.rows = rows
        model.finished = false
        model.onClose = { [weak self] in self?.close() }
        model.onReveal = { [weak self] in self?.revealNow() }
        show()
    }

    func mark(_ index: Int, _ phase: RowPhase, detail: String) {
        guard model.rows.indices.contains(index) else { return }
        model.rows[index].phase = phase
        model.rows[index].detail = detail
        resize()
    }

    func finish(outputs: [URL]) {
        revealOutputs = outputs
        model.finished = true
        resize()
    }

    func scheduleClose(after seconds: Double) {
        closeTask?.cancel()
        closeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.close()
        }
    }

    func flash(_ message: String) {
        begin([ProgressRow(title: "Dropwheel", detail: message, phase: .done)])
        finish(outputs: [])
        scheduleClose(after: 3.2)
    }

    func close() {
        closeTask?.cancel()
        panel?.orderOut(nil)
    }

    private func revealNow() {
        guard !revealOutputs.isEmpty else { return }
        JobCenter.reveal(revealOutputs)
    }

    private func show() {
        let panel = ensurePanel()
        resize()
        panel.orderFrontRegardless()
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: ProgressListView(model: model))
        self.panel = panel
        return panel
    }

    private func resize() {
        guard let panel else { return }
        let height = min(560, 78 + CGFloat(model.rows.count) * 52 + (model.finished ? 28 : 0))
        let size = NSSize(width: 340, height: height)
        panel.setContentSize(size)
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        panel.setFrameOrigin(NSPoint(
            x: visible.maxX - size.width - 16,
            y: visible.maxY - size.height - 16
        ))
    }
}

enum ByteFormat {
    static func string(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
