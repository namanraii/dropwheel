import CoreGraphics
import Foundation

public enum OutputPaths {
    public static func normalizedExtension(_ url: URL) -> String {
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") { return "tgz" }
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpeg", "jpg": return "jpg"
        case "tif", "tiff": return "tiff"
        case "heif", "heic": return "heic"
        case "aif", "aiff": return "aiff"
        case "aac", "m4b", "m4a": return "m4a"
        case "htm", "html": return "html"
        case "markdown", "md": return "md"
        case "wave", "wav": return "wav"
        case "oga", "ogg": return "ogg"
        case "tgz": return "tgz"
        default: return ext
        }
    }

    public static func baseName(of url: URL) -> String {
        let name = url.lastPathComponent
        let lower = name.lowercased()
        if lower.hasSuffix(".tar.gz") {
            let trimmed = String(name.dropLast(".tar.gz".count))
            return trimmed.isEmpty ? "file" : trimmed
        }
        let base = url.deletingPathExtension().lastPathComponent
        return base.isEmpty ? "file" : base
    }

    public static func uniqueFile(in directory: URL, base: String, ext: String) -> URL {
        let fm = FileManager.default
        var candidate = directory.appendingPathComponent(base).appendingPathExtension(ext)
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)-\(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }

    public static func uniqueDirectory(in directory: URL, base: String) -> URL {
        let fm = FileManager.default
        var candidate = directory.appendingPathComponent(base, isDirectory: true)
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)-\(n)", isDirectory: true)
            n += 1
        }
        return candidate
    }

    public static func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dropwheel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
        if let allocated = values?.totalFileAllocatedSize { return Int64(allocated) }
        if let size = values?.fileSize { return Int64(size) }
        return 0
    }
}

public struct WedgeGeometry: Sendable, Equatable {
    public var count: Int
    public var innerRadius: Double
    public var outerRadius: Double

    public init(count: Int, innerRadius: Double, outerRadius: Double) {
        self.count = count
        self.innerRadius = innerRadius
        self.outerRadius = outerRadius
    }

    public static func polar(from center: CGPoint, to point: CGPoint) -> (angle: Double, radius: Double) {
        let dx = Double(point.x - center.x)
        let dy = Double(point.y - center.y)
        let radius = hypot(dx, dy)
        var angle = atan2(dx, -dy)
        if angle < 0 { angle += 2 * Double.pi }
        if angle >= 2 * Double.pi { angle = 0 }
        return (angle, radius)
    }

    /// Angle 0 is the top of the wheel. It increases clockwise in a y-down view.
    public func index(angle: Double, radius: Double) -> Int? {
        guard count > 0 else { return nil }
        guard radius >= innerRadius, radius <= outerRadius else { return nil }
        var turn = angle.truncatingRemainder(dividingBy: 2 * Double.pi)
        if turn < 0 { turn += 2 * Double.pi }
        let sweep = (2 * Double.pi) / Double(count)
        var idx = Int(turn / sweep)
        if idx >= count { idx = count - 1 }
        if idx < 0 { idx = 0 }
        return idx
    }

    public func midAngle(for index: Int) -> Double {
        guard count > 0 else { return 0 }
        let sweep = (2 * Double.pi) / Double(count)
        return (Double(index) + 0.5) * sweep
    }
}

public enum PackagePreview {
    public static func pdf(in package: URL) -> URL? {
        let candidates = [
            package.appendingPathComponent("QuickLook/Preview.pdf"),
            package.appendingPathComponent("preview.pdf"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}

public enum ArchiveSafety {
    public static func isUnsafe(entry: String) -> Bool {
        let name = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name == "." || name == "./" { return false }
        if name.hasPrefix("/") || name.hasPrefix("\\") { return true }
        if name.hasPrefix("~") { return true }
        let normalized = name.replacingOccurrences(of: "\\", with: "/")
        let parts = normalized.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        return parts.contains("..")
    }
}
