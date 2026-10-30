import Foundation

enum OfficeConverter {
    static func convert(
        _ source: URL,
        to format: Format,
        settings: ConvertSettings,
        bins: BinaryAvailability
    ) async throws -> [URL] {
        switch format {
        case .pdf:
            return [try await toPDF(source, settings: settings, bins: bins)]
        case .txt, .md:
            return [try await toText(source, markdown: format == .md, bins: bins)]
        case .html:
            return [try await toHTML(source, bins: bins)]
        case .docx:
            return [try await toDocx(source, bins: bins)]
        case .pages:
            throw ConvertError.unsupported("Saving a Pages file needs the Pages app.")
        case .epub:
            let text = try await plainText(source, bins: bins)
            let dest = OutputPaths.uniqueFile(
                in: source.deletingLastPathComponent(),
                base: OutputPaths.baseName(of: source),
                ext: "epub"
            )
            try await Epub.write(title: OutputPaths.baseName(of: source), text: text, to: dest, bins: bins)
            return [dest]
        case .pptx:
            return [try await soffice(source, target: "pptx", ext: "pptx", bins: bins)]
        case .ods:
            return [try await soffice(source, target: "ods", ext: "ods", bins: bins)]
        case .png, .jpg:
            let pdf = try await materializePDF(source, settings: settings, bins: bins)
            let owned = pdf != source && !isPreview(pdf, of: source)
            defer { if owned { try? FileManager.default.removeItem(at: pdf) } }
            return try await PDFConverter.render(pdf, format: format, dpi: settings.pdfDPI)
        case .csv:
            return [try await delimited(source, separator: ",", ext: "csv", bins: bins)]
        case .tsv:
            return [try await delimited(source, separator: "\t", ext: "tsv", bins: bins)]
        case .xlsx:
            return [try await soffice(source, target: "xlsx", ext: "xlsx", bins: bins)]
        default:
            throw ConvertError.unsupported("Dropwheel can't turn this file into \(format.title).")
        }
    }

    static func tool(
        _ tool: Tool,
        source: URL,
        settings: ConvertSettings,
        bins: BinaryAvailability
    ) async throws -> [URL] {
        switch tool {
        case .toPDF:
            return try await convert(source, to: .pdf, settings: settings, bins: bins)
        case .toText, .pdfText:
            return try await convert(source, to: .txt, settings: settings, bins: bins)
        case .toHTML:
            return try await convert(source, to: .html, settings: settings, bins: bins)
        case .toCSV:
            return try await convert(source, to: .csv, settings: settings, bins: bins)
        case .toTSV:
            return try await convert(source, to: .tsv, settings: settings, bins: bins)
        case .toXLSX:
            return try await convert(source, to: .xlsx, settings: settings, bins: bins)
        case .pdfImages:
            return try await convert(source, to: .png, settings: settings, bins: bins)
        default:
            throw ConvertError.unsupported("That tool does not apply to this file.")
        }
    }

    private static func toPDF(_ source: URL, settings: ConvertSettings, bins: BinaryAvailability) async throws -> URL {
        if let preview = PackagePreview.pdf(in: source), bins.libreOffice == nil {
            return try copy(preview, beside: source, ext: "pdf")
        }
        if bins.libreOffice != nil && !isPlainText(source) {
            return try await soffice(source, target: "pdf", ext: "pdf", bins: bins)
        }
        let text = try await plainText(source, bins: bins)
        let dest = OutputPaths.uniqueFile(
            in: source.deletingLastPathComponent(),
            base: OutputPaths.baseName(of: source),
            ext: "pdf"
        )
        try TextPDF.write(text, to: dest)
        return dest
    }

    private static func materializePDF(_ source: URL, settings: ConvertSettings, bins: BinaryAvailability) async throws -> URL {
        if OutputPaths.normalizedExtension(source) == "pdf" { return source }
        if let preview = PackagePreview.pdf(in: source) { return preview }
        return try await toPDF(source, settings: settings, bins: bins)
    }

    private static func isPreview(_ url: URL, of source: URL) -> Bool {
        PackagePreview.pdf(in: source)?.path == url.path
    }

    private static func toText(_ source: URL, markdown: Bool, bins: BinaryAvailability) async throws -> URL {
        if let preview = PackagePreview.pdf(in: source), !textutilCanRead(source) {
            let files = try await PDFConverter.convert(preview, to: markdown ? .md : .txt, settings: .standard, bins: bins)
            guard let produced = files.first else { throw ConvertError.failed("No text was written.") }
            let dest = OutputPaths.uniqueFile(
                in: source.deletingLastPathComponent(),
                base: OutputPaths.baseName(of: source),
                ext: markdown ? "md" : "txt"
            )
            try FileManager.default.moveItem(at: produced, to: dest)
            return dest
        }
        let text = try await plainText(source, bins: bins)
        let dest = OutputPaths.uniqueFile(
            in: source.deletingLastPathComponent(),
            base: OutputPaths.baseName(of: source),
            ext: markdown ? "md" : "txt"
        )
        try Data(text.utf8).write(to: dest)
        return dest
    }

    private static func toHTML(_ source: URL, bins: BinaryAvailability) async throws -> URL {
        if textutilCanRead(source), let textutil = bins.textutil {
            let dest = OutputPaths.uniqueFile(
                in: source.deletingLastPathComponent(),
                base: OutputPaths.baseName(of: source),
                ext: "html"
            )
            try await Shell.runChecked(textutil, ["-convert", "html", "-output", dest.path, source.path])
            return dest
        }
        let text = try await plainText(source, bins: bins)
        let body = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
        let html = "<!doctype html><meta charset=\"utf-8\"><pre>\(body)</pre>\n"
        let dest = OutputPaths.uniqueFile(
            in: source.deletingLastPathComponent(),
            base: OutputPaths.baseName(of: source),
            ext: "html"
        )
        try Data(html.utf8).write(to: dest)
        return dest
    }

    private static func toDocx(_ source: URL, bins: BinaryAvailability) async throws -> URL {
        guard let textutil = bins.textutil else {
            throw ConvertError.missingTool("textutil")
        }
        let input: URL
        let cleanup: URL?
        if textutilCanRead(source) {
            input = source
            cleanup = nil
        } else {
            let text = try await plainText(source, bins: bins)
            let temp = try OutputPaths.makeTempDirectory().appendingPathComponent("input.txt")
            try Data(text.utf8).write(to: temp)
            input = temp
            cleanup = temp.deletingLastPathComponent()
        }
        defer { if let cleanup { try? FileManager.default.removeItem(at: cleanup) } }
        let dest = OutputPaths.uniqueFile(
            in: source.deletingLastPathComponent(),
            base: OutputPaths.baseName(of: source),
            ext: "docx"
        )
        try await Shell.runChecked(textutil, ["-convert", "docx", "-output", dest.path, input.path])
        return dest
    }

    private static func delimited(
        _ source: URL,
        separator: String,
        ext: String,
        bins: BinaryAvailability
    ) async throws -> URL {
        let kindExt = OutputPaths.normalizedExtension(source)
        let rows: [[String]]
        if kindExt == "csv" || kindExt == "tsv" || kindExt == "txt" {
            let raw = try String(contentsOf: source, encoding: .utf8)
            let incoming: Character = kindExt == "tsv" ? "\t" : ","
            rows = DelimitedText.parse(raw, separator: incoming)
        } else if bins.libreOffice != nil {
            let produced = try await soffice(source, target: "csv", ext: "csv", bins: bins)
            let raw = try String(contentsOf: produced, encoding: .utf8)
            rows = DelimitedText.parse(raw, separator: ",")
            if ext != "csv" { try? FileManager.default.removeItem(at: produced) }
            if ext == "csv" { return produced }
        } else {
            throw ConvertError.missingTool("LibreOffice (brew install --cask libreoffice)")
        }
        let dest = OutputPaths.uniqueFile(
            in: source.deletingLastPathComponent(),
            base: OutputPaths.baseName(of: source),
            ext: ext
        )
        let character: Character = separator == "\t" ? "\t" : ","
        try Data(DelimitedText.write(rows, separator: character).utf8).write(to: dest)
        return dest
    }

    static func libreOffice(_ source: URL, target: String, ext: String, bins: BinaryAvailability) async throws -> URL {
        try await soffice(source, target: target, ext: ext, bins: bins)
    }

    private static func soffice(_ source: URL, target: String, ext: String, bins: BinaryAvailability) async throws -> URL {
        guard let soffice = bins.libreOffice else {
            throw ConvertError.missingTool("LibreOffice (brew install --cask libreoffice)")
        }
        let tmp = try OutputPaths.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let profile = tmp.appendingPathComponent("profile", isDirectory: true)
        let outdir = tmp.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: outdir, withIntermediateDirectories: true)
        let installation = profile.absoluteURL.absoluteString
        let result = try await Shell.run(soffice, [
            "--headless", "--norestore", "--nolockcheck", "--nologo",
            "-env:UserInstallation=\(installation)",
            "--convert-to", target,
            "--outdir", outdir.path,
            source.path,
        ])
        let produced = try FileManager.default.contentsOfDirectory(at: outdir, includingPropertiesForKeys: nil)
        guard result.status == 0, let file = produced.first else {
            throw ConvertError.failed(ConvertError.clean(result.stderr.isEmpty ? "LibreOffice did not write a file." : result.stderr))
        }
        let dest = OutputPaths.uniqueFile(
            in: source.deletingLastPathComponent(),
            base: OutputPaths.baseName(of: source),
            ext: ext
        )
        try move(file, to: dest)
        return dest
    }

    private static func plainText(_ source: URL, bins: BinaryAvailability) async throws -> String {
        let ext = OutputPaths.normalizedExtension(source)
        if ext == "epub" {
            return try await Epub.readText(source, bins: bins)
        }
        if ext == "txt" || ext == "md" || ext == "csv" || ext == "tsv" {
            return try String(contentsOf: source, encoding: .utf8)
        }
        if let preview = PackagePreview.pdf(in: source) {
            let files = try await MainActor.run { try PDFConverter.writeText(preview, markdown: false) }
            defer {
                for file in files {
                    try? FileManager.default.removeItem(at: file)
                }
            }
            if let first = files.first, let text = try? String(contentsOf: first, encoding: .utf8) {
                return text
            }
        }
        if textutilCanRead(source), let textutil = bins.textutil {
            let tmp = try OutputPaths.makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: tmp) }
            let dest = tmp.appendingPathComponent("out.txt")
            try await Shell.runChecked(textutil, ["-convert", "txt", "-stdout", source.path], stdoutFile: dest)
            return try String(contentsOf: dest, encoding: .utf8)
        }
        if bins.libreOffice != nil {
            let produced = try await soffice(source, target: "txt", ext: "txt", bins: bins)
            defer { try? FileManager.default.removeItem(at: produced) }
            return try String(contentsOf: produced, encoding: .utf8)
        }
        throw ConvertError.missingTool("LibreOffice (brew install --cask libreoffice)")
    }

    private static func textutilCanRead(_ url: URL) -> Bool {
        ["doc", "docx", "rtf", "rtfd", "odt", "html", "txt", "wordml"].contains(OutputPaths.normalizedExtension(url))
    }

    private static func isPlainText(_ url: URL) -> Bool {
        ["txt", "md", "csv", "tsv", "html"].contains(OutputPaths.normalizedExtension(url))
    }

    private static func copy(_ source: URL, beside original: URL, ext: String) throws -> URL {
        let dest = OutputPaths.uniqueFile(
            in: original.deletingLastPathComponent(),
            base: OutputPaths.baseName(of: original),
            ext: ext
        )
        try FileManager.default.copyItem(at: source, to: dest)
        return dest
    }

    private static func move(_ source: URL, to dest: URL) throws {
        do {
            try FileManager.default.moveItem(at: source, to: dest)
        } catch {
            try FileManager.default.copyItem(at: source, to: dest)
        }
    }
}

enum DelimitedText {
    static func parse(_ text: String, separator: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let chars = Array(text)
        var index = 0
        while index < chars.count {
            let char = chars[index]
            if inQuotes {
                if char == "\"" {
                    if index + 1 < chars.count && chars[index + 1] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(char)
                }
            } else if char == "\"" && field.isEmpty {
                inQuotes = true
            } else if char == separator {
                row.append(field)
                field = ""
            } else if char == "\n" || char == "\r" {
                if char == "\r" && index + 1 < chars.count && chars[index + 1] == "\n" {
                    index += 1
                }
                row.append(field)
                field = ""
                if row != [""] { rows.append(row) }
                row = []
            } else {
                field.append(char)
            }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            if row != [""] { rows.append(row) }
        }
        return rows
    }

    static func write(_ rows: [[String]], separator: Character) -> String {
        rows.map { row in
            row.map { field in
                if field.contains(separator) || field.contains("\"") || field.contains("\n") {
                    return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                }
                return field
            }.joined(separator: String(separator))
        }.joined(separator: "\n")
    }
}
