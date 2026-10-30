import Foundation

public enum Engine {
    public static func runOne(
        _ operation: FileJob,
        file: URL,
        settings: ConvertSettings = .load()
    ) async throws -> [URL] {
        let source = try prepare(file)
        let settings = settings.clamped()
        let bins = BinaryAvailability.current()
        switch operation {
        case .convert(let format):
            return try await convert(source, to: format, settings: settings, bins: bins)
        case .tool(let tool):
            return try await toolOne(tool, source: source, settings: settings, bins: bins)
        case .action:
            throw ConvertError.unsupported("Actions are handled by the app.")
        }
    }

    public static func runBatch(
        _ operation: FileJob,
        files: [URL],
        settings: ConvertSettings = .load()
    ) async throws -> [URL] {
        let settings = settings.clamped()
        let bins = BinaryAvailability.current()
        let sources = try files.map(prepare)
        switch operation {
        case .tool(.pdfMerge):
            return try await PDFConverter.merge(sources)
        case .tool(.imagesToPDF):
            let dest = try await MainActor.run { try ImagePDF.combine(sources) }
            return [dest]
        default:
            var outputs: [URL] = []
            for source in sources {
                let part = try await runOne(operation, file: source, settings: settings)
                outputs.append(contentsOf: part)
            }
            _ = bins
            return outputs
        }
    }

    private static func convert(
        _ source: URL,
        to format: Format,
        settings: ConvertSettings,
        bins: BinaryAvailability
    ) async throws -> [URL] {
        switch FileKind.of(source) {
        case .image:
            if format.isVideoContainer {
                return try await VideoConverter.convert(source, to: format, settings: settings, bins: bins)
            }
            return try await ImageConverter.convert(source, to: format, settings: settings, bins: bins)
        case .audio:
            return try await AudioConverter.convert(source, to: format, settings: settings, bins: bins)
        case .video:
            return try await VideoConverter.convert(source, to: format, settings: settings, bins: bins)
        case .subtitle:
            return try SubtitleConverter.convert(source, to: format)
        case .pdf:
            return try await PDFConverter.convert(source, to: format, settings: settings, bins: bins)
        case .document, .slides, .spreadsheet:
            return try await OfficeConverter.convert(source, to: format, settings: settings, bins: bins)
        case .archive, .folder, .other:
            return try await ArchiveConverter.convert(source, to: format, bins: bins)
        }
    }

    private static func toolOne(
        _ tool: Tool,
        source: URL,
        settings: ConvertSettings,
        bins: BinaryAvailability
    ) async throws -> [URL] {
        switch tool {
        case .compress, .compressMore:
            let tiny = tool == .compressMore
            switch FileKind.of(source) {
            case .video:
                return try await VideoConverter.compress(source, tiny: tiny, bins: bins)
            case .image:
                return try await ImageConverter.compress(source, tiny: tiny, bins: bins)
            case .audio:
                return try await AudioConverter.tool(.audio128, source: source, bins: bins)
            case .pdf:
                return try await PDFConverter.compress(source, strong: tiny, bins: bins)
            default:
                throw ConvertError.unsupported("Compress works on images, audio, video, and PDFs.")
            }
        case .videoStill:
            return try await VideoConverter.still(source, bins: bins)
        case .videoDouble:
            return try await VideoConverter.speed(source, factor: 2, bins: bins)
        case .videoHalf:
            return try await VideoConverter.speed(source, factor: 0.5, bins: bins)
        case .videoMute:
            return try await VideoConverter.mute(source, bins: bins)
        case .stripMetadata:
            switch FileKind.of(source) {
            case .image:
                return try await ImageConverter.strip(source, bins: bins)
            case .video, .audio:
                return try await VideoConverter.stripContainer(source, bins: bins)
            default:
                throw ConvertError.unsupported("Metadata removal for this file is not available yet.")
            }
        case .addBackground:
            return try await ImageConverter.matte(source, bins: bins)
        case .cropImage:
            return try await ImageConverter.centerCrop(source, bins: bins)
        case .editPhoto, .annotatePhoto, .redactImage, .trimVideo, .cropVideo, .splitVideo, .redactVideo, .organizePDF:
            throw ConvertError.unsupported("\(tool.title) is on the wheel. The editor for it is not in this version yet.")
        case .audio128, .audio192, .normalize:
            return try await AudioConverter.tool(tool, source: source, bins: bins)
        case .pdfCompress:
            return try await PDFConverter.compress(source, strong: false, bins: bins)
        case .pdfCompressMore:
            return try await PDFConverter.compress(source, strong: true, bins: bins)
        case .pdfSplit:
            return try await PDFConverter.split(source)
        case .pdfImages:
            return try await PDFConverter.render(source, format: .png, dpi: settings.pdfDPI)
        case .pdfText:
            if FileKind.of(source) == .pdf {
                return try await PDFConverter.writeText(source, markdown: false)
            }
            return try await OfficeConverter.tool(tool, source: source, settings: settings, bins: bins)
        case .toPDF, .toText, .toHTML, .toCSV, .toTSV, .toXLSX:
            if tool == .toText, FileKind.of(source) == .subtitle {
                return try SubtitleConverter.convert(source, to: .txt)
            }
            return try await OfficeConverter.tool(tool, source: source, settings: settings, bins: bins)
        case .extractArchive:
            return try await ArchiveConverter.extract(source, bins: bins)
        case .pdfMerge, .imagesToPDF:
            throw ConvertError.unsupported("Use a batch for this tool.")
        }
    }

    private static func prepare(_ url: URL) throws -> URL {
        let resolved = resolve(url)
        guard FileManager.default.fileExists(atPath: resolved.path) else {
            throw ConvertError.failed("The file is no longer there.")
        }
        if let values = try? resolved.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
           let status = values.ubiquitousItemDownloadingStatus,
           status != .current {
            try? FileManager.default.startDownloadingUbiquitousItem(at: resolved)
            throw ConvertError.failed("This iCloud file is not on this Mac yet. It is downloading. Try again in a moment.")
        }
        return resolved
    }

    private static func resolve(_ url: URL) -> URL {
        let values = try? url.resourceValues(forKeys: [.isAliasFileKey])
        if values?.isAliasFile == true, let resolved = try? URL(resolvingAliasFileAt: url) {
            return resolved
        }
        return url.resolvingSymlinksInPath()
    }
}
