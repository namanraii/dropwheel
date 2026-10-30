import Foundation

enum Epub {
    static func write(title: String, text: String, to dest: URL, bins: BinaryAvailability) async throws {
        guard let zip = bins.zip else { throw ConvertError.missingTool("zip") }
        let root = try OutputPaths.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let meta = root.appendingPathComponent("META-INF", isDirectory: true)
        let oebps = root.appendingPathComponent("OEBPS", isDirectory: true)
        try FileManager.default.createDirectory(at: meta, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: oebps, withIntermediateDirectories: true)
        try Data("application/epub+zip".utf8).write(to: root.appendingPathComponent("mimetype"))
        try Data(containerXML.utf8).write(to: meta.appendingPathComponent("container.xml"))
        try Data(packageXML(title: title).utf8).write(to: oebps.appendingPathComponent("content.opf"))
        try Data(chapterXHTML(title: title, text: text).utf8).write(to: oebps.appendingPathComponent("chapter.xhtml"))
        try await Shell.runChecked(zip, ["-X0", dest.path, "mimetype"], cwd: root)
        try await Shell.runChecked(zip, ["-Xr", dest.path, "META-INF", "OEBPS"], cwd: root)
    }

    static func readText(_ source: URL, bins: BinaryAvailability) async throws -> String {
        guard let tar = bins.tar else { throw ConvertError.missingTool("tar") }
        let root = try OutputPaths.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try await Shell.runChecked(tar, ["-xf", source.path, "-C", root.path])
        let names = try FileManager.default.subpathsOfDirectory(atPath: root.path)
        var chapters: [String] = []
        for name in names {
            let url = root.appendingPathComponent(name)
            let ext = url.pathExtension.lowercased()
            guard ext == "xhtml" || ext == "html" || ext == "htm" else { continue }
            let name = url.lastPathComponent.lowercased()
            if name.contains("nav") || name.contains("toc") { continue }
            guard let html = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let text = plainText(fromHTML: html).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { chapters.append(text) }
        }
        let joined = chapters.joined(separator: "\n\n")
        guard !joined.isEmpty else { throw ConvertError.failed("This EPUB has no readable text.") }
        return joined
    }

    static func plainText(fromHTML html: String) -> String {
        var text = html
        let blocks = ["(?is)<script\\b[^>]*>.*?</script>", "(?is)<style\\b[^>]*>.*?</style>"]
        for pattern in blocks {
            text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        text = text.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</p>", with: "\n\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'"]
        for (entity, value) in entities {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        let lines = text.components(separatedBy: "\n").map { line in
            line.replacingOccurrences(of: "[ ]+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
        return lines.joined(separator: "\n")
    }

    private static let containerXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
      </rootfiles>
    </container>
    """

    private static func packageXML(title: String) -> String {
        let safe = escape(title)
        let identifier = UUID().uuidString
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="uid">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>\(safe)</dc:title>
            <dc:language>en</dc:language>
            <dc:identifier id="uid">urn:uuid:\(identifier)</dc:identifier>
          </metadata>
          <manifest>
            <item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="chapter"/>
          </spine>
        </package>
        """
    }

    private static func chapterXHTML(title: String, text: String) -> String {
        let paragraphs = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { "<p>\(escape($0))</p>" }
            .joined(separator: "\n")
        let body = paragraphs.isEmpty ? "<p></p>" : paragraphs
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml">
        <head><title>\(escape(title))</title></head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
