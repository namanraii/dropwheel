import AppKit
import Foundation
import PDFKit

enum ImageConverter {
    static func convert(
        _ source: URL,
        to format: Format,
        settings: ConvertSettings,
        bins: BinaryAvailability
    ) async throws -> [URL] {
        let parent = source.deletingLastPathComponent()
        let dest = OutputPaths.uniqueFile(
            in: parent,
            base: OutputPaths.baseName(of: source),
            ext: format.fileExtension
        )
        if format == .pdf {
            let wrote = await MainActor.run { () -> Bool in
                do {
                    try ImagePDF.write(imageURL: source, to: dest)
                    return true
                } catch {
                    try? FileManager.default.removeItem(at: dest)
                    return false
                }
            }
            if wrote { return [dest] }
        }
        if bins.magick != nil {
            try await magick(source, to: dest, format: format, quality: settings.imageQuality, bins: bins)
            return [dest]
        }
        try await sips(source, to: dest, format: format, quality: settings.imageQuality, bins: bins)
        return [dest]
    }

    static func compress(
        _ source: URL,
        tiny: Bool,
        bins: BinaryAvailability
    ) async throws -> [URL] {
        guard bins.magick != nil else {
            throw ConvertError.missingTool("ImageMagick (brew install imagemagick)")
        }
        let ext = OutputPaths.normalizedExtension(source)
        let dest = OutputPaths.uniqueFile(
            in: source.deletingLastPathComponent(),
            base: OutputPaths.baseName(of: source),
            ext: ext.isEmpty ? "jpg" : ext
        )
        let quality = tiny ? 40 : 70
        if tiny && (ext == "png" || ext == "gif") {
            try await Shell.runChecked(bins.magick!, [
                source.path, "-auto-orient", "-strip", "-colors", "128", dest.path,
            ])
        } else if ext == "png" {
            try await Shell.runChecked(bins.magick!, [
                source.path, "-auto-orient", "-strip", "-define", "png:compression-level=9", dest.path,
            ])
        } else {
            try await Shell.runChecked(bins.magick!, [
                "\(source.path)[0]", "-auto-orient", "-strip",
                "-background", "white", "-alpha", "remove", "-alpha", "off",
                "-quality", String(quality), dest.path,
            ])
        }
        return [dest]
    }

    static func matte(_ source: URL, bins: BinaryAvailability) async throws -> [URL] {
        guard let magick = bins.magick else {
            throw ConvertError.missingTool("ImageMagick (brew install imagemagick)")
        }
        let ext = OutputPaths.normalizedExtension(source)
        let dest = OutputPaths.uniqueFile(
            in: source.deletingLastPathComponent(),
            base: OutputPaths.baseName(of: source),
            ext: ext.isEmpty ? "png" : ext
        )
        try await Shell.runChecked(magick, [
            source.path, "-background", "white", "-gravity", "center", "-extent", "125%x125%", dest.path,
        ])
        return [dest]
    }

    static func centerCrop(_ source: URL, bins: BinaryAvailability) async throws -> [URL] {
        guard let magick = bins.magick else {
            throw ConvertError.missingTool("ImageMagick (brew install imagemagick)")
        }
        let ext = OutputPaths.normalizedExtension(source)
        let dest = OutputPaths.uniqueFile(
            in: source.deletingLastPathComponent(),
            base: OutputPaths.baseName(of: source),
            ext: ext.isEmpty ? "jpg" : ext
        )
        try await Shell.runChecked(magick, [
            source.path, "-gravity", "center", "-crop", "80%x80%+0+0", "+repage", dest.path,
        ])
        return [dest]
    }

    static func strip(_ source: URL, bins: BinaryAvailability) async throws -> [URL] {
        guard let magick = bins.magick else {
            throw ConvertError.missingTool("ImageMagick (brew install imagemagick)")
        }
        let ext = OutputPaths.normalizedExtension(source)
        let dest = OutputPaths.uniqueFile(
            in: source.deletingLastPathComponent(),
            base: OutputPaths.baseName(of: source),
            ext: ext.isEmpty ? "jpg" : ext
        )
        try await Shell.runChecked(magick, [source.path, "-auto-orient", "-strip", dest.path])
        return [dest]
    }

    private static func magick(
        _ source: URL,
        to dest: URL,
        format: Format,
        quality: Int,
        bins: BinaryAvailability
    ) async throws {
        guard let magick = bins.magick else {
            throw ConvertError.missingTool("ImageMagick (brew install imagemagick)")
        }
        let single: Set<Format> = [.jpg, .png, .webp, .heic, .tiff, .avif, .bmp]
        let input = single.contains(format) ? "\(source.path)[0]" : source.path
        var args = [input, "-auto-orient"]
        if format == .jpg || format == .bmp {
            args += ["-background", "white", "-alpha", "remove", "-alpha", "off"]
        }
        if format == .jpg || format == .webp || format == .heic || format == .avif {
            let q = (format == .avif) ? min(quality, 62) : quality
            args += ["-quality", String(q)]
        }
        if format == .png {
            args += ["-define", "png:compression-level=9"]
        }
        args.append(dest.path)
        try await Shell.runChecked(magick, args)
    }

    private static func sips(
        _ source: URL,
        to dest: URL,
        format: Format,
        quality: Int,
        bins: BinaryAvailability
    ) async throws {
        guard let sips = bins.sips else {
            throw ConvertError.missingTool("sips")
        }
        let name: String
        switch format {
        case .jpg: name = "jpeg"
        case .png: name = "png"
        case .tiff: name = "tiff"
        case .bmp: name = "bmp"
        case .gif: name = "gif"
        case .heic: name = "heic"
        case .pdf: name = "pdf"
        default:
            throw ConvertError.unsupported("Install ImageMagick for \(format.title). brew install imagemagick")
        }
        var args = ["-s", "format", name]
        if format == .jpg {
            args += ["-s", "formatOptions", String(quality)]
        }
        args += [source.path, "--out", dest.path]
        try await Shell.runChecked(sips, args)
    }
}

@MainActor
enum ImagePDF {
    static func write(imageURL: URL, to output: URL) throws {
        guard let image = NSImage(contentsOf: imageURL), image.size.width > 0, image.size.height > 0 else {
            throw ConvertError.failed("Could not read this image.")
        }
        let document = PDFDocument()
        guard let page = PDFPage(image: image) else {
            throw ConvertError.failed("Could not draw this image.")
        }
        document.insert(page, at: 0)
        guard document.write(to: output) else {
            throw ConvertError.failed("Could not write the PDF.")
        }
    }

    static func combine(_ sources: [URL]) throws -> URL {
        guard let first = sources.first else {
            throw ConvertError.failed("Choose at least one image.")
        }
        let document = PDFDocument()
        for (index, source) in sources.enumerated() {
            guard let image = NSImage(contentsOf: source), let page = PDFPage(image: image) else {
                throw ConvertError.failed("Could not read \(source.lastPathComponent).")
            }
            document.insert(page, at: index)
        }
        let dest = OutputPaths.uniqueFile(
            in: first.deletingLastPathComponent(),
            base: "Combined",
            ext: "pdf"
        )
        guard document.write(to: dest) else {
            throw ConvertError.failed("Could not write the PDF.")
        }
        return dest
    }
}
