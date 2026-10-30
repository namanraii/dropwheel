import AppKit
import CoreGraphics
import CoreText
import Foundation
import PDFKit

enum PDFConverter {
    static func convert(
        _ source: URL,
        to format: Format,
        settings: ConvertSettings,
        bins: BinaryAvailability
    ) async throws -> [URL] {
        switch format {
        case .png, .jpg:
            return try await render(source, format: format, dpi: settings.pdfDPI)
        case .txt:
            return try await MainActor.run { try writeText(source, markdown: false) }
        case .md:
            return try await MainActor.run { try writeText(source, markdown: true) }
        case .html:
            let textFile = try await MainActor.run { try writeText(source, markdown: false) }
            guard let textURL = textFile.first, let text = try? String(contentsOf: textURL, encoding: .utf8) else {
                return textFile
            }
            let html = htmlDocument(text)
            let dest = OutputPaths.uniqueFile(
                in: source.deletingLastPathComponent(),
                base: OutputPaths.baseName(of: source),
                ext: "html"
            )
            try html.data(using: .utf8)?.write(to: dest)
            try? FileManager.default.removeItem(at: textURL)
            return [dest]
        case .docx:
            let textFile = try await MainActor.run { try writeText(source, markdown: false) }
            guard let textURL = textFile.first else { return [] }
            defer { try? FileManager.default.removeItem(at: textURL) }
            guard let textutil = bins.textutil else {
                throw ConvertError.missingTool("textutil")
            }
            let dest = OutputPaths.uniqueFile(
                in: source.deletingLastPathComponent(),
                base: OutputPaths.baseName(of: source),
                ext: "docx"
            )
            try await Shell.runChecked(textutil, ["-convert", "docx", "-output", dest.path, textURL.path])
            return [dest]
        case .epub:
            let textFile = try await MainActor.run { try writeText(source, markdown: false) }
            defer {
                for file in textFile {
                    try? FileManager.default.removeItem(at: file)
                }
            }
            guard let textURL = textFile.first, let text = try? String(contentsOf: textURL, encoding: .utf8) else {
                throw ConvertError.failed("Could not read this PDF.")
            }
            let dest = OutputPaths.uniqueFile(
                in: source.deletingLastPathComponent(),
                base: OutputPaths.baseName(of: source),
                ext: "epub"
            )
            try await Epub.write(title: OutputPaths.baseName(of: source), text: text, to: dest, bins: bins)
            return [dest]
        case .pptx, .xlsx:
            let target = format.fileExtension
            return [try await OfficeConverter.libreOffice(source, target: target, ext: target, bins: bins)]
        default:
            throw ConvertError.unsupported("Dropwheel can't turn a PDF into \(format.title).")
        }
    }

    static func compress(_ source: URL, strong: Bool, bins: BinaryAvailability) async throws -> [URL] {
        guard let gs = bins.ghostscript else {
            throw ConvertError.missingTool("Ghostscript (brew install ghostscript)")
        }
        let dest = OutputPaths.uniqueFile(
            in: source.deletingLastPathComponent(),
            base: OutputPaths.baseName(of: source),
            ext: "pdf"
        )
        let setting = strong ? "/screen" : "/ebook"
        try await Shell.runChecked(gs, [
            "-sDEVICE=pdfwrite",
            "-dCompatibilityLevel=1.4",
            "-dPDFSETTINGS=\(setting)",
            "-dNOPAUSE",
            "-dQUIET",
            "-dBATCH",
            "-sOutputFile=\(dest.path)",
            source.path,
        ])
        return [dest]
    }

    @MainActor
    static func split(_ source: URL) throws -> [URL] {
        guard let doc = PDFDocument(url: source), doc.pageCount > 0 else {
            throw ConvertError.failed("Could not open this PDF.")
        }
        var urls: [URL] = []
        let base = OutputPaths.baseName(of: source)
        let dir = source.deletingLastPathComponent()
        for index in 0..<doc.pageCount {
            guard let page = doc.page(at: index) else { continue }
            let out = PDFDocument()
            out.insert(page, at: 0)
            let dest = OutputPaths.uniqueFile(in: dir, base: "\(base)-page-\(index + 1)", ext: "pdf")
            guard out.write(to: dest) else {
                throw ConvertError.failed("Could not write page \(index + 1).")
            }
            urls.append(dest)
        }
        return urls
    }

    @MainActor
    static func merge(_ sources: [URL]) throws -> [URL] {
        guard let first = sources.first else {
            throw ConvertError.failed("Choose at least two PDFs.")
        }
        let out = PDFDocument()
        var cursor = 0
        for source in sources {
            guard let doc = PDFDocument(url: source) else {
                throw ConvertError.failed("Could not open \(source.lastPathComponent).")
            }
            for index in 0..<doc.pageCount {
                guard let page = doc.page(at: index) else { continue }
                out.insert(page, at: cursor)
                cursor += 1
            }
        }
        guard cursor > 0 else { throw ConvertError.failed("These PDFs have no pages.") }
        let dest = OutputPaths.uniqueFile(in: first.deletingLastPathComponent(), base: "Merged", ext: "pdf")
        guard out.write(to: dest) else { throw ConvertError.failed("Could not write the merged PDF.") }
        return [dest]
    }

    @MainActor
    static func render(_ source: URL, format: Format, dpi: Int) async throws -> [URL] {
        guard let doc = PDFDocument(url: source), doc.pageCount > 0 else {
            throw ConvertError.failed("Could not open this PDF.")
        }
        let ext = format == .jpg ? "jpg" : "png"
        let base = OutputPaths.baseName(of: source)
        let dir = source.deletingLastPathComponent()
        var urls: [URL] = []
        for index in 0..<doc.pageCount {
            await Task.yield()
            guard let page = doc.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale = CGFloat(dpi) / 72
            let pixelsWide = max(1, Int(floor(bounds.width * scale)))
            let pixelsHigh = max(1, Int(floor(bounds.height * scale)))
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelsWide,
                pixelsHigh: pixelsHigh,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ) else {
                throw ConvertError.failed("Could not draw page \(index + 1).")
            }
            rep.size = NSSize(width: bounds.width, height: bounds.height)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            if let ctx = NSGraphicsContext.current?.cgContext {
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh))
                ctx.scaleBy(x: scale, y: scale)
                page.draw(with: .mediaBox, to: ctx)
            }
            NSGraphicsContext.restoreGraphicsState()
            let data: Data?
            if format == .jpg {
                data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
            } else {
                data = rep.representation(using: .png, properties: [:])
            }
            guard let data else { throw ConvertError.failed("Could not encode page \(index + 1).") }
            let name = doc.pageCount == 1 ? base : "\(base)-page-\(index + 1)"
            let dest = OutputPaths.uniqueFile(in: dir, base: name, ext: ext)
            try data.write(to: dest)
            urls.append(dest)
        }
        return urls
    }

    @MainActor
    static func writeText(_ source: URL, markdown: Bool) throws -> [URL] {
        guard let doc = PDFDocument(url: source) else {
            throw ConvertError.failed("Could not open this PDF.")
        }
        var pages: [String] = []
        for index in 0..<doc.pageCount {
            let text = doc.page(at: index)?.string ?? ""
            pages.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if pages.allSatisfy(\.isEmpty) {
            throw ConvertError.failed("This PDF has no text. It may be made of scanned images.")
        }
        let body: String
        if markdown {
            body = pages.enumerated().map { index, page in
                "## Page \(index + 1)\n\n\(page)"
            }.joined(separator: "\n\n")
        } else {
            body = pages.joined(separator: "\n\n")
        }
        let dest = OutputPaths.uniqueFile(
            in: source.deletingLastPathComponent(),
            base: OutputPaths.baseName(of: source),
            ext: markdown ? "md" : "txt"
        )
        try Data(body.utf8).write(to: dest)
        return [dest]
    }

    private static func htmlDocument(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <!doctype html>
        <meta charset="utf-8">
        <title>Dropwheel</title>
        <pre style="font: 15px -apple-system, sans-serif; white-space: pre-wrap;">\(escaped)</pre>
        """
    }
}

enum TextPDF {
    static func write(_ text: String, to url: URL) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ConvertError.failed("Could not create the PDF.")
        }
        let font = CTFontCreateWithName("Helvetica" as CFString, 11, nil)
        let color = CGColor(gray: 0.12, alpha: 1)
        let attrs = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: color,
        ] as CFDictionary
        let attributed = CFAttributedStringCreate(nil, text as CFString, attrs)!
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let length = CFAttributedStringGetLength(attributed)
        let margin: CGFloat = 54
        let textRect = CGRect(x: margin, y: margin, width: 612 - margin * 2, height: 792 - margin * 2)
        var index = 0
        var guardPages = 0
        if length == 0 {
            ctx.beginPDFPage(nil)
            ctx.endPDFPage()
        }
        while index < length && guardPages < 200 {
            ctx.beginPDFPage(nil)
            ctx.textMatrix = .identity
            let path = CGPath(rect: textRect, transform: nil)
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: index, length: 0),
                path,
                nil
            )
            CTFrameDraw(frame, ctx)
            let visible = CTFrameGetVisibleStringRange(frame)
            ctx.endPDFPage()
            if visible.length <= 0 { break }
            index += visible.length
            guardPages += 1
        }
        ctx.closePDF()
    }
}
