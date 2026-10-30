import AppKit
import DropwheelCore

@MainActor
final class JobCenter {
    static let shared = JobCenter()

    private var tail: Task<Void, Never>?

    func run(files: [URL], operation: FileJob) {
        let previous = tail
        let task = Task { @MainActor in
            await previous?.value
            await self.execute(files: files, operation: operation)
        }
        tail = task
    }

    private func execute(files: [URL], operation: FileJob) async {
        switch operation {
        case .action(let action):
            await Actions.perform(action, files: files)
        case .convert, .tool:
            await convert(files: files, operation: operation)
        }
    }

    private func convert(files: [URL], operation: FileJob) async {
        let settings = ConvertSettings.load()
        let progress = ProgressController.shared
        if operation.isBatch {
            let row = ProgressRow(
                title: Catalog.summary(for: files),
                detail: operation.detail,
                phase: .running
            )
            progress.begin([row])
            do {
                let outputs = try await Engine.runBatch(operation, files: files, settings: settings)
                progress.mark(0, .done, detail: Self.detail(for: outputs))
                progress.finish(outputs: outputs)
                if settings.revealInFinder { Self.reveal(outputs) }
                progress.scheduleClose(after: 4)
            } catch {
                progress.mark(0, .failed, detail: error.localizedDescription)
                progress.finish(outputs: [])
                Log.write("Batch failed: \(error.localizedDescription)")
            }
            return
        }

        var rows: [ProgressRow] = files.map {
            ProgressRow(title: $0.lastPathComponent, detail: operation.title, phase: .waiting)
        }
        progress.begin(rows)
        var outputs: [URL] = []
        var failed = false
        for index in files.indices {
            rows[index].phase = .running
            rows[index].detail = "Working…"
            progress.mark(index, .running, detail: "Working…")
            do {
                let made = try await Engine.runOne(operation, file: files[index], settings: settings)
                outputs.append(contentsOf: made)
                let detail = Self.detail(for: made)
                rows[index].phase = .done
                progress.mark(index, .done, detail: detail)
            } catch {
                failed = true
                progress.mark(index, .failed, detail: error.localizedDescription)
                Log.write("Failed \(files[index].lastPathComponent): \(error.localizedDescription)")
            }
        }
        progress.finish(outputs: outputs)
        if settings.revealInFinder && !outputs.isEmpty {
            Self.reveal(outputs)
        }
        if !failed {
            progress.scheduleClose(after: 4)
        }
    }

    static func detail(for urls: [URL]) -> String {
        if urls.count == 1 {
            let url = urls[0]
            return "\(url.lastPathComponent) · \(ByteFormat.string(OutputPaths.fileSize(url)))"
        }
        return "\(urls.count) files"
    }

    static func reveal(_ urls: [URL]) {
        guard let first = urls.first else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls.count > 40 ? [first] : urls)
    }
}

enum Actions {
    @MainActor
    static func perform(_ action: Action, files: [URL]) async {
        switch action {
        case .airdrop:
            airdrop(files)
        case .float:
            FloatController.shared.float(files)
            ProgressController.shared.flash(files.count == 1 ? "Pinned. Drag the icon out." : "Pinned \(files.count) files.")
        case .copy:
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects(files as [NSURL])
            ProgressController.shared.flash("Copied \(files.count == 1 ? "the file" : "\(files.count) files") to the clipboard.")
        case .move:
            move(files)
        case .copyPath:
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(files.map(\.path).joined(separator: "\n"), forType: .string)
            ProgressController.shared.flash("Copied the path.")
        case .terminal:
            terminal(files)
        }
    }

    @MainActor
    private static func airdrop(_ files: [URL]) {
        guard let service = NSSharingService(named: .sendViaAirDrop) else {
            ProgressController.shared.flash("AirDrop is not available.")
            return
        }
        guard service.canPerform(withItems: files) else {
            ProgressController.shared.flash("AirDrop can't send these items.")
            return
        }
        AppActivation.activate()
        service.perform(withItems: files)
    }

    @MainActor
    private static func move(_ files: [URL]) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Move Here"
        panel.message = files.count == 1 ? "Move \(files[0].lastPathComponent)" : "Move \(files.count) items"
        AppActivation.activate()
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        var moved: [URL] = []
        var errors: [String] = []
        for file in files {
            let dest = destination(for: file, in: folder)
            do {
                try FileManager.default.moveItem(at: file, to: dest)
                moved.append(dest)
            } catch {
                errors.append("\(file.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if errors.isEmpty {
            ProgressController.shared.flash("Moved \(moved.count == 1 ? "the file" : "\(moved.count) files").")
            if ConvertSettings.load().revealInFinder { JobCenter.reveal(moved) }
        } else {
            ProgressController.shared.flash(errors.joined(separator: " "))
        }
    }

    @MainActor
    private static func terminal(_ files: [URL]) {
        var dirs: [String] = []
        for file in files {
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: file.path, isDirectory: &isDir)
            if exists && isDir.boolValue && file.pathExtension.isEmpty {
                dirs.append(file.path)
            } else {
                dirs.append(file.deletingLastPathComponent().path)
            }
        }
        for dir in Array(Set(dirs)) {
            let quoted = "'" + dir.replacingOccurrences(of: "'", with: "'\\''") + "'"
            let source = """
            tell application "Terminal"
              activate
              do script "cd \(quoted)"
            end tell
            """
            var error: NSDictionary?
            if NSAppleScript(source: source)?.executeAndReturnError(&error) == nil, let message = error?[NSAppleScript.errorMessage] as? String {
                ProgressController.shared.flash(message)
                return
            }
        }
        ProgressController.shared.flash("Opened Terminal.")
    }

    private static func destination(for source: URL, in folder: URL) -> URL {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: source.path, isDirectory: &isDir)
        let ext = source.pathExtension
        if exists && isDir.boolValue && ext.isEmpty {
            return OutputPaths.uniqueDirectory(in: folder, base: source.lastPathComponent)
        }
        if ext.isEmpty {
            var candidate = folder.appendingPathComponent(source.lastPathComponent)
            var n = 2
            while FileManager.default.fileExists(atPath: candidate.path) {
                candidate = folder.appendingPathComponent("\(source.lastPathComponent)-\(n)")
                n += 1
            }
            return candidate
        }
        return OutputPaths.uniqueFile(in: folder, base: OutputPaths.baseName(of: source), ext: ext)
    }
}

enum AppActivation {
    @MainActor
    static func activate() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
