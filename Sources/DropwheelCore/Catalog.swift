import Foundation

public enum Catalog {
    public static func items(files: [URL], mode: WheelMode, binaries: BinaryAvailability) -> [CatalogItem] {
        switch mode {
        case .actions:
            return Action.allCases.map { action in
                CatalogItem(
                    id: "action-\(action.rawValue)",
                    title: action.title.uppercased(),
                    detail: action.detail,
                    symbol: action.symbol,
                    operation: .action(action)
                )
            }
        case .convert:
            return convertItems(files: files, binaries: binaries)
        case .tools:
            return toolItems(files: files, binaries: binaries)
        }
    }

    public static func summary(for files: [URL]) -> String {
        switch files.count {
        case 0: return "No files"
        case 1: return files[0].lastPathComponent
        case 2:
            let a = files[0].lastPathComponent
            let b = files[1].lastPathComponent
            if a.count + b.count < 28 { return "\(a)  \(b)" }
            return "2 files"
        default:
            return "\(files.count) files"
        }
    }

    public static func badge(for files: [URL]) -> String {
        let kinds = Set(files.map(FileKind.of))
        guard let kind = kinds.first, kinds.count == 1 else { return "Mixed" }
        return kind.badge
    }

    public static func emptyMessage(files: [URL], mode: WheelMode, binaries: BinaryAvailability) -> String {
        guard !files.isEmpty else { return "Drop a file onto the wheel." }
        let kinds = Set(files.map(FileKind.of))
        if kinds.count != 1 {
            return "These files are different kinds. Drag one kind, or use Actions."
        }
        switch (kinds.first!, mode) {
        case (.folder, .tools):
            return "Folders have no edit tools. Shift archives them. Control is for actions."
        case (.other, .tools):
            return "Shift can wrap this file. Control is for actions."
        case (.audio, .convert) where binaries.ffmpeg == nil:
            return "Install ffmpeg to convert audio. brew install ffmpeg"
        case (.video, .convert) where binaries.ffmpeg == nil:
            return "Install ffmpeg to convert video. brew install ffmpeg"
        case (.video, .tools) where binaries.ffmpeg == nil:
            return "Install ffmpeg to convert video. brew install ffmpeg"
        case (.archive, .tools):
            if files.contains(where: { OutputPaths.normalizedExtension($0) == "rar" }), binaries.unar == nil {
                return "Install unar to extract RAR. brew install unar"
            }
            return "No tools for this archive."
        case (.slides, .convert), (.spreadsheet, .convert), (.slides, .tools), (.spreadsheet, .tools):
            let preview = files.allSatisfy { PackagePreview.pdf(in: $0) != nil }
            if binaries.libreOffice == nil && !preview {
                return "Install LibreOffice for Office files. brew install --cask libreoffice"
            }
            return "Nothing else for this file."
        default:
            return "Nothing else for this file."
        }
    }

    private static func convertItems(files: [URL], binaries: BinaryAvailability) -> [CatalogItem] {
        let kinds = Set(files.map(FileKind.of))
        guard let kind = kinds.first, kinds.count == 1 else { return [] }
        var formats = candidateFormats(kind: kind, files: files, binaries: binaries)
        if let shared = sharedExtension(files) {
            let filtered = formats.filter { !$0.matches(normalizedExtension: shared) }
            if !filtered.isEmpty { formats = filtered }
        }
        return formats.map { format in
            CatalogItem(
                id: "convert-\(format.rawValue)",
                title: format.title,
                detail: format.detail,
                symbol: "",
                operation: .convert(format)
            )
        }
    }

    private static func toolItems(files: [URL], binaries: BinaryAvailability) -> [CatalogItem] {
        toolSpecs(files: files, binaries: binaries).map { spec in
            CatalogItem(
                id: "tool-\(spec.tool.rawValue)",
                title: spec.title,
                detail: spec.detail,
                symbol: spec.symbol,
                operation: .tool(spec.tool)
            )
        }
    }

    private static func sharedExtension(_ files: [URL]) -> String? {
        let exts = Set(files.map(OutputPaths.normalizedExtension))
        guard exts.count == 1, let ext = exts.first, !ext.isEmpty else { return nil }
        return ext
    }

    private static let imageExts: Set<String> = ["jpg", "png", "webp", "heic", "tiff", "svg", "avif", "bmp"]
    private static let photoToolExts: Set<String> = ["jpg", "png", "webp", "heic", "tiff"]
    private static let audioExts: Set<String> = ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "wma"]
    private static let simpleAudioExts: Set<String> = ["mp3", "m4a", "wav", "flac"]
    private static let videoExts: Set<String> = ["mp4", "mov", "mkv", "webm", "avi", "wmv"]
    private static let mainVideoExts: Set<String> = ["mp4", "mov", "mkv", "webm", "avi", "wmv"]
    private static let documentExts: Set<String> = ["docx", "pages", "md", "rtf", "rtfd", "html", "txt", "odt", "wordml"]
    private static let sheetExts: Set<String> = ["xlsx", "xls", "ods", "csv", "tsv"]
    private static let archiveExts: Set<String> = ["zip", "tar", "gz", "tgz", "rar"]

    private static func outputs(for ext: String) -> [Format] {
        if imageExts.contains(ext) {
            return [.jpg, .png, .webp, .heic, .tiff, .avif, .bmp, .pdf]
        }
        if audioExts.contains(ext) {
            return [.mp3, .m4a, .wav, .flac, .ogg, .opus, .aiff, .wma]
        }
        if videoExts.contains(ext) {
            return [.mp4, .mov, .mkv, .webm, .avi, .wmv, .gif, .mp3]
        }
        if ext == "gif" {
            return [.mp4, .mov, .mkv, .webm, .avi, .wmv]
        }
        if ext == "pdf" {
            return [.docx, .pages, .pptx, .xlsx, .jpg, .png, .epub, .txt, .md]
        }
        if ext == "ppt" || ext == "pptx" || ext == "key" || ext == "odp" {
            return [.pdf, .jpg, .png]
        }
        if sheetExts.contains(ext) {
            return [.xlsx, .ods, .csv, .tsv, .pdf]
        }
        if documentExts.contains(ext) {
            return [.docx, .pages, .pdf, .txt, .md, .html, .epub, .png, .jpg]
        }
        if ext == "epub" {
            return [.pdf, .docx, .pages, .txt, .md, .html]
        }
        if ext == "srt" || ext == "vtt" || ext == "ass" || ext == "ssa" {
            return [.srt, .vtt, .txt]
        }
        if archiveExts.contains(ext) || ext.isEmpty {
            return [.zip, .tar, .tgz]
        }
        return [.zip, .tar, .tgz]
    }

    private static func candidateFormats(kind: FileKind, files: [URL], binaries: BinaryAvailability) -> [Format] {
        let lists = files.map { outputs(for: OutputPaths.normalizedExtension($0)) }
        guard var common = lists.first else { return [] }
        for list in lists.dropFirst() {
            let allowed = Set(list)
            common.removeAll { !allowed.contains($0) }
        }
        if binaries.ffmpeg == nil {
            common.removeAll { audioExts.contains($0.fileExtension) || videoExts.contains($0.fileExtension) || $0 == .gif && kind == .video }
        }
        _ = kind
        return common
    }

    private struct ToolSpec {
        var title: String
        var detail: String
        var symbol: String
        var tool: Tool
    }

    private static func toolSpecs(files: [URL], binaries: BinaryAvailability) -> [ToolSpec] {
        let exts = files.map { OutputPaths.normalizedExtension($0) }
        guard let first = exts.first else { return [] }
        let branch = toolBranch(first)
        guard exts.allSatisfy({ toolBranch($0) == branch }) else { return [] }
        let count = files.count
        switch branch {
        case .photo:
            if count > 1 {
                return [
                    spec("COMPRESS", "Smaller file", "arrow.down.right.and.arrow.up.left", .compress),
                    spec("METADATA", "Remove metadata", "tag", .stripMetadata),
                    spec("CROP", "Crop the image", "crop", .cropImage),
                    spec("CREATE PDF", "One PDF", "doc.badge.plus", .imagesToPDF),
                ]
            }
            return [
                spec("COMPRESS", "Smaller file", "arrow.down.right.and.arrow.up.left", .compress),
                spec("METADATA", "Remove metadata", "tag", .stripMetadata),
                spec("EDIT", "Edit the photo", "slider.horizontal.3", .editPhoto),
                spec("ANNOTATE", "Annotate the photo", "pencil.and.outline", .annotatePhoto),
                spec("ADD BG", "Add a background", "photo", .addBackground),
                spec("CROP", "Crop the image", "crop", .cropImage),
                spec("REDACT", "Redact the photo", "eye.slash", .redactImage),
            ]
        case .audio:
            return [
                spec("COMPRESS", "Smaller audio", "arrow.down.right.and.arrow.up.left", .audio128),
                spec("METADATA", "Remove metadata", "tag", .stripMetadata),
                spec("NORMALIZE", "Even out volume", "waveform", .normalize),
            ]
        case .video:
            if count > 1 {
                return [
                    spec("COMPRESS", "Smaller video", "arrow.down.right.and.arrow.up.left", .compress),
                    spec("METADATA", "Remove metadata", "tag", .stripMetadata),
                    spec("MUTE", "Remove the sound", "speaker.slash.fill", .videoMute),
                    spec("SPEED", "Double speed", "speedometer", .videoDouble),
                ]
            }
            return [
                spec("COMPRESS", "Smaller video", "arrow.down.right.and.arrow.up.left", .compress),
                spec("METADATA", "Remove metadata", "tag", .stripMetadata),
                spec("MUTE", "Remove the sound", "speaker.slash.fill", .videoMute),
                spec("TRIM", "Trim the video", "scissors", .trimVideo),
                spec("CROP", "Crop the video", "crop", .cropVideo),
                spec("SPEED", "Double speed", "speedometer", .videoDouble),
                spec("SNAPSHOT", "One JPEG frame", "camera", .videoStill),
                spec("SPLIT", "Split the video", "film", .splitVideo),
                spec("REDACT", "Redact the video", "eye.slash", .redactVideo),
            ]
        case .gif:
            return [spec("METADATA", "Remove metadata", "tag", .stripMetadata)]
        case .pdf:
            if count > 1 {
                return [
                    spec("COMPRESS", "Smaller PDF", "arrow.down.right.and.arrow.up.left", .pdfCompress),
                    spec("METADATA", "Remove metadata", "tag", .stripMetadata),
                    spec("SPLIT", "One file per page", "rectangle.split.2x1", .pdfSplit),
                    spec("MERGE", "One PDF", "doc.on.doc", .pdfMerge),
                ]
            }
            return [
                spec("COMPRESS", "Smaller PDF", "arrow.down.right.and.arrow.up.left", .pdfCompress),
                spec("METADATA", "Remove metadata", "tag", .stripMetadata),
                spec("SPLIT", "One file per page", "rectangle.split.2x1", .pdfSplit),
                spec("ORGANIZE", "Reorder pages", "square.grid.2x2", .organizePDF),
            ]
        case .archive:
            return [spec("EXTRACT", "Into a folder", "archivebox", .extractArchive)]
        case .none:
            return []
        }
    }

    private enum ToolBranch {
        case photo, audio, video, gif, pdf, archive, none
    }

    private static func toolBranch(_ ext: String) -> ToolBranch {
        if photoToolExts.contains(ext) { return .photo }
        if simpleAudioExts.contains(ext) { return .audio }
        if mainVideoExts.contains(ext) { return .video }
        if ext == "gif" { return .gif }
        if ext == "pdf" { return .pdf }
        if archiveExts.contains(ext) { return .archive }
        return .none
    }

    private static func spec(_ title: String, _ detail: String, _ symbol: String, _ tool: Tool) -> ToolSpec {
        ToolSpec(title: title, detail: detail, symbol: symbol, tool: tool)
    }
}
