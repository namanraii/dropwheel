import Foundation

public enum FileKind: String, Sendable, Equatable {
    case image
    case audio
    case pdf
    case document
    case slides
    case spreadsheet
    case video
    case subtitle
    case archive
    case folder
    case other

    public static func of(_ url: URL) -> FileKind {
        let ext = OutputPaths.normalizedExtension(url)
        let packages: Set<String> = ["pages", "rtfd", "key", "numbers", "app"]
        if !packages.contains(ext) {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                return .folder
            }
        }
        switch ext {
        case "jpg", "png", "webp", "heic", "tiff", "avif", "bmp", "gif", "svg", "ico", "jp2":
            return .image
        case "mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "wma", "caf":
            return .audio
        case "mp4", "m4v", "mov", "mkv", "webm", "avi", "wmv", "mpg", "mpeg", "flv", "3gp", "ts", "mts", "m2ts":
            return .video
        case "srt", "vtt", "ass", "ssa":
            return .subtitle
        case "pdf":
            return .pdf
        case "ppt", "pptx", "odp", "key":
            return .slides
        case "xls", "xlsx", "xlsm", "ods", "csv", "tsv", "numbers":
            return .spreadsheet
        case "zip", "tar", "gz", "tgz", "rar":
            return .archive
        case "doc", "docx", "rtf", "rtfd", "odt", "pages", "txt", "md", "html", "wordml", "epub":
            return .document
        default:
            return .other
        }
    }

    public var badge: String {
        switch self {
        case .image: return "Image"
        case .audio: return "Audio"
        case .video: return "Video"
        case .subtitle: return "Subtitles"
        case .pdf: return "PDF"
        case .document: return "Document"
        case .slides: return "Slides"
        case .spreadsheet: return "Sheet"
        case .archive: return "Archive"
        case .folder: return "Folder"
        case .other: return "File"
        }
    }
}

public enum Format: String, CaseIterable, Sendable, Equatable, Codable {
    case jpg, png, webp, heic, tiff, avif, bmp, gif, pdf
    case mp3, m4a, wav, flac, ogg, opus, aiff, wma
    case mp4, mov, mkv, webm, avi, wmv
    case txt, md, html, docx, epub, pptx, pages
    case csv, tsv, xlsx, ods
    case srt, vtt
    case zip, tar, tgz

    public var title: String { rawValue.uppercased() }

    public var fileExtension: String { rawValue }

    public var detail: String {
        switch self {
        case .jpg: return "JPEG image"
        case .png: return "PNG image"
        case .webp: return "WebP image"
        case .heic: return "HEIC image"
        case .tiff: return "TIFF image"
        case .avif: return "AVIF image"
        case .bmp: return "BMP image"
        case .gif: return "GIF image"
        case .pdf: return "PDF document"
        case .mp3: return "MP3 audio"
        case .m4a: return "AAC audio"
        case .wav: return "WAV audio"
        case .flac: return "FLAC audio"
        case .ogg: return "Ogg audio"
        case .opus: return "Opus audio"
        case .aiff: return "AIFF audio"
        case .wma: return "Windows Media audio"
        case .mp4: return "MPEG-4 video"
        case .mov: return "QuickTime video"
        case .mkv: return "Matroska video"
        case .webm: return "WebM video"
        case .avi: return "AVI video"
        case .wmv: return "Windows Media video"
        case .txt: return "Plain text"
        case .md: return "Markdown"
        case .html: return "Web page"
        case .docx: return "Word document"
        case .epub: return "EPUB book"
        case .pptx: return "PowerPoint slides"
        case .pages: return "Pages document"
        case .csv: return "Comma-separated"
        case .tsv: return "Tab-separated"
        case .xlsx: return "Excel workbook"
        case .ods: return "OpenDocument sheet"
        case .srt: return "SubRip subtitles"
        case .vtt: return "Web subtitles"
        case .zip: return "Zip archive"
        case .tar: return "Tar archive"
        case .tgz: return "Gzipped tar"
        }
    }

    public func matches(normalizedExtension ext: String) -> Bool {
        ext == fileExtension
    }

    public var isVideoContainer: Bool {
        switch self {
        case .mp4, .mov, .mkv, .webm, .avi, .wmv: return true
        default: return false
        }
    }
}

public enum Tool: String, Sendable, Equatable, Codable {
    case compress
    case compressMore
    case stripMetadata
    case audio128
    case audio192
    case normalize
    case pdfCompress
    case pdfCompressMore
    case pdfSplit
    case pdfImages
    case pdfText
    case pdfMerge
    case imagesToPDF
    case toPDF
    case toText
    case toHTML
    case toCSV
    case toTSV
    case toXLSX
    case extractArchive
    case videoStill
    case videoDouble
    case videoHalf
    case videoMute
    case editPhoto
    case annotatePhoto
    case addBackground
    case cropImage
    case redactImage
    case trimVideo
    case cropVideo
    case splitVideo
    case redactVideo
    case organizePDF

    public var title: String {
        switch self {
        case .compress: return "Smaller"
        case .compressMore: return "Tiny"
        case .stripMetadata: return "Strip"
        case .audio128: return "128 kbps"
        case .audio192: return "192 kbps"
        case .normalize: return "Normalize"
        case .pdfCompress: return "Compress"
        case .pdfCompressMore: return "Tiny"
        case .pdfSplit: return "Split"
        case .pdfImages: return "Pages"
        case .pdfText: return "Text"
        case .pdfMerge: return "Merge"
        case .imagesToPDF: return "Combine"
        case .toPDF: return "PDF"
        case .toText: return "Text"
        case .toHTML: return "HTML"
        case .toCSV: return "CSV"
        case .toTSV: return "TSV"
        case .toXLSX: return "XLSX"
        case .extractArchive: return "Extract"
        case .videoStill: return "Still"
        case .videoDouble: return "2×"
        case .videoHalf: return "½"
        case .videoMute: return "Mute"
        case .editPhoto: return "Edit"
        case .annotatePhoto: return "Annotate"
        case .addBackground: return "Add BG"
        case .cropImage: return "Crop"
        case .redactImage: return "Redact"
        case .trimVideo: return "Trim"
        case .cropVideo: return "Crop"
        case .splitVideo: return "Split"
        case .redactVideo: return "Redact"
        case .organizePDF: return "Organize"
        }
    }

    public var detail: String {
        switch self {
        case .compress: return "Lower quality"
        case .compressMore: return "Much smaller"
        case .stripMetadata: return "Remove metadata"
        case .audio128: return "Smaller audio"
        case .audio192: return "Standard audio"
        case .normalize: return "Even out volume"
        case .pdfCompress: return "Smaller PDF"
        case .pdfCompressMore: return "Screen-size PDF"
        case .pdfSplit: return "One file per page"
        case .pdfImages: return "PNG pages"
        case .pdfText: return "Extract words"
        case .pdfMerge: return "One PDF"
        case .imagesToPDF: return "One PDF from images"
        case .toPDF: return "Save as PDF"
        case .toText: return "Plain words"
        case .toHTML: return "Web page"
        case .toCSV: return "Comma-separated"
        case .toTSV: return "Tab-separated"
        case .toXLSX: return "Excel workbook"
        case .extractArchive: return "Into a folder"
        case .videoStill: return "One JPEG frame"
        case .videoDouble: return "Double speed"
        case .videoHalf: return "Half speed"
        case .videoMute: return "Remove the sound"
        case .editPhoto: return "Edit the photo"
        case .annotatePhoto: return "Annotate the photo"
        case .addBackground: return "Add a background"
        case .cropImage: return "Crop the image"
        case .redactImage: return "Redact the photo"
        case .trimVideo: return "Trim the video"
        case .cropVideo: return "Crop the video"
        case .splitVideo: return "Split the video"
        case .redactVideo: return "Redact the video"
        case .organizePDF: return "Reorder pages"
        }
    }

    public var symbol: String {
        switch self {
        case .compress, .pdfCompress: return "arrow.down.circle"
        case .compressMore, .pdfCompressMore: return "arrow.down.circle.fill"
        case .stripMetadata: return "tag.slash"
        case .audio128, .audio192: return "waveform"
        case .normalize: return "waveform.path"
        case .pdfSplit: return "rectangle.split.3x1"
        case .pdfImages: return "photo.on.rectangle"
        case .pdfText, .toText: return "text.alignleft"
        case .pdfMerge, .imagesToPDF: return "rectangle.stack"
        case .toPDF: return "doc.richtext"
        case .toHTML: return "globe"
        case .toCSV, .toTSV, .toXLSX: return "tablecells"
        case .extractArchive: return "arrow.up.bin"
        case .videoStill: return "photo"
        case .videoDouble: return "forward.fill"
        case .videoHalf: return "backward.fill"
        case .videoMute: return "speaker.slash.fill"
        case .editPhoto: return "slider.horizontal.3"
        case .annotatePhoto: return "pencil.and.outline"
        case .addBackground: return "photo"
        case .cropImage, .cropVideo: return "crop"
        case .redactImage, .redactVideo: return "eye.slash"
        case .trimVideo: return "scissors"
        case .splitVideo: return "film"
        case .organizePDF: return "square.grid.2x2"
        }
    }

    public var isBatch: Bool {
        switch self {
        case .pdfMerge, .imagesToPDF: return true
        default: return false
        }
    }
}

public enum Action: String, Sendable, Equatable, Codable, CaseIterable {
    case airdrop
    case float
    case copy
    case move
    case copyPath
    case terminal

    public var title: String {
        switch self {
        case .airdrop: return "AirDrop"
        case .float: return "Float"
        case .copy: return "Copy"
        case .move: return "Move"
        case .copyPath: return "Copy Path"
        case .terminal: return "Terminal"
        }
    }

    public var detail: String {
        switch self {
        case .airdrop: return "Send nearby"
        case .float: return "Keep it on screen"
        case .copy: return "Copy the file"
        case .move: return "Choose a folder"
        case .copyPath: return "Copy the path"
        case .terminal: return "Open this folder"
        }
    }

    public var symbol: String {
        switch self {
        case .airdrop: return "wifi"
        case .float: return "pin.fill"
        case .copy: return "doc.on.doc"
        case .move: return "folder.fill"
        case .copyPath: return "link"
        case .terminal: return "terminal"
        }
    }
}

public enum FileJob: Sendable, Equatable {
    case convert(Format)
    case tool(Tool)
    case action(Action)

    public var title: String {
        switch self {
        case .convert(let format): return format.title
        case .tool(let tool): return tool.title
        case .action(let action): return action.title
        }
    }

    public var detail: String {
        switch self {
        case .convert(let format): return format.detail
        case .tool(let tool): return tool.detail
        case .action(let action): return action.detail
        }
    }

    public var isBatch: Bool {
        if case .tool(let tool) = self { return tool.isBatch }
        return false
    }
}

public enum WheelMode: String, Sendable, Equatable, CaseIterable {
    case convert
    case tools
    case actions

    public var title: String {
        switch self {
        case .convert: return "Convert"
        case .tools: return "Tools"
        case .actions: return "Actions"
        }
    }

    public var symbol: String {
        switch self {
        case .convert: return "arrow.triangle.2.circlepath"
        case .tools: return "wrench.and.screwdriver"
        case .actions: return "bolt.fill"
        }
    }
}

public struct CatalogItem: Identifiable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var detail: String
    public var symbol: String
    public var operation: FileJob

    public init(id: String, title: String, detail: String, symbol: String, operation: FileJob) {
        self.id = id
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.operation = operation
    }
}

public struct ConvertSettings: Codable, Sendable, Equatable {
    public var imageQuality: Int
    public var audioBitrateKbps: Int
    public var pdfDPI: Int
    public var revealInFinder: Bool

    public static let standard = ConvertSettings(
        imageQuality: 90,
        audioBitrateKbps: 192,
        pdfDPI: 300,
        revealInFinder: true
    )

    public init(imageQuality: Int, audioBitrateKbps: Int, pdfDPI: Int, revealInFinder: Bool) {
        self.imageQuality = imageQuality
        self.audioBitrateKbps = audioBitrateKbps
        self.pdfDPI = pdfDPI
        self.revealInFinder = revealInFinder
    }

    public func clamped() -> ConvertSettings {
        var copy = self
        copy.imageQuality = min(98, max(50, imageQuality))
        let allowed = [128, 160, 192, 256, 320]
        if !allowed.contains(copy.audioBitrateKbps) {
            copy.audioBitrateKbps = 192
        }
        if ![72, 150, 300].contains(copy.pdfDPI) {
            copy.pdfDPI = 300
        }
        return copy
    }

    private static let key = "DropwheelSettings.v1"

    public static func load() -> ConvertSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode(ConvertSettings.self, from: data) else {
            return .standard
        }
        return value.clamped()
    }

    public func save() {
        let value = clamped()
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

public enum ConvertError: LocalizedError, Sendable, Equatable {
    case missingTool(String)
    case failed(String)
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .missingTool(let name):
            return "\(name) is not installed."
        case .failed(let message):
            return message
        case .unsupported(let message):
            return message
        }
    }

    static func clean(_ text: String) -> String {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let joined = lines.suffix(4).joined(separator: " ")
        if joined.isEmpty { return "Conversion failed." }
        if joined.count <= 280 { return joined }
        return String(joined.suffix(280))
    }
}

public enum WheelMetrics {
    /// Same radii as the public Tangerine wheel, in points.
    public static let windowSize: Double = 320
    public static let innerRadius: Double = 48 * 0.8 * 1.1 + 8 * 0.8
    public static let outerRadius: Double = 166 * 0.8 * 0.9
    public static let hitOuterRadius: Double = 166 * 0.8 * 0.9
    public static let gap: Double = 5 * 0.8
    public static let corner: Double = 28 * 0.8 * 0.9
    public static let labelInner: Double = 50 * 0.8

    public static var labelRadius: Double {
        labelInner + (outerRadius - labelInner) * 0.56
    }

    /// Index 0 sits at the top, except a 3-item wheel, where it sits on the left.
    public static func centerAngle(index: Int, count: Int) -> Double {
        let base = count == 3 ? Double.pi : Double.pi / 2
        return base - 2 * Double.pi * Double(index) / Double(count)
    }

    public static func hitIndex(x: Double, y: Double, count: Int) -> Int? {
        let radius = hypot(x, y)
        guard count > 0, radius >= innerRadius, radius <= outerRadius else { return nil }
        let angle = atan2(-y, x)
        let sweep = 2 * Double.pi / Double(count)
        var turn = centerAngle(index: 0, count: count) - angle
        turn = turn.truncatingRemainder(dividingBy: 2 * Double.pi)
        if turn < 0 { turn += 2 * Double.pi }
        let index = Int(round(turn / sweep)) % count
        let target = centerAngle(index: index, count: count)
        let offset = atan2(sin(angle - target), cos(angle - target))
        let limit = sweep / 2 - asin(min(0.95, gap / 2 / radius))
        if abs(offset) > limit { return nil }
        return index
    }
}
