import CoreGraphics
import Foundation

public enum SelfCheck {
    public static func run() async -> Bool {
        var failed = 0
        failed += await check("wedge geometry", wedge)
        failed += await check("names", names)
        failed += await check("archive paths", archivePaths)
        failed += await check("catalog", catalog)
        failed += await check("csv", csv)
        failed += await check("image", image)
        failed += await check("pdf", pdf)
        failed += await check("audio", audio)
        failed += await check("document and zip", documentAndZip)
        failed += await check("video subtitles epub", videoSubtitlesAndEpub)
        if failed == 0 {
            print("self-check ok")
            return true
        }
        print("self-check failed: \(failed)")
        return false
    }

    private static func check(_ name: String, _ body: () async throws -> Void) async -> Int {
        do {
            try await body()
            print("ok  \(name)")
            return 0
        } catch {
            print("FAIL \(name): \(error)")
            return 1
        }
    }

    private static func wedge() throws {
        let center = CGPoint(x: 100, y: 100)
        let top = WedgeGeometry.polar(from: center, to: CGPoint(x: 100, y: 40))
        try expect(abs(top.angle) < 0.001, "top angle \(top.angle)")
        try expect(abs(top.radius - 60) < 0.001, "top radius")
        let right = WedgeGeometry.polar(from: center, to: CGPoint(x: 160, y: 100))
        try expect(abs(right.angle - .pi / 2) < 0.001, "right angle")
        let geometry = WedgeGeometry(count: 4, innerRadius: 20, outerRadius: 100)
        try expect(geometry.index(angle: 0, radius: 50) == 0, "index 0")
        try expect(geometry.index(angle: .pi / 2, radius: 50) == 1, "index 1")
        try expect(geometry.index(angle: .pi, radius: 50) == 2, "index 2")
        try expect(geometry.index(angle: 3 * .pi / 2, radius: 50) == 3, "index 3")
        try expect(geometry.index(angle: 0, radius: 10) == nil, "inside hub")
        try expect(geometry.index(angle: 0, radius: 140) == nil, "outside")
    }

    private static func names() throws {
        let dir = try OutputPaths.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = OutputPaths.uniqueFile(in: dir, base: "Photo", ext: "jpg")
        try Data("a".utf8).write(to: first)
        let second = OutputPaths.uniqueFile(in: dir, base: "Photo", ext: "jpg")
        try expect(first.lastPathComponent == "Photo.jpg", first.lastPathComponent)
        try expect(second.lastPathComponent == "Photo-2.jpg", second.lastPathComponent)
        try expect(OutputPaths.baseName(of: URL(fileURLWithPath: "/tmp/Archive.tar.gz")) == "Archive", "base")
        try expect(OutputPaths.normalizedExtension(URL(fileURLWithPath: "/tmp/a.JPEG")) == "jpg", "jpeg")
        try expect(OutputPaths.normalizedExtension(URL(fileURLWithPath: "/tmp/a.tar.gz")) == "tgz", "tgz")
    }

    private static func archivePaths() throws {
        try expect(!ArchiveSafety.isUnsafe(entry: "src/inside.txt"), "safe")
        try expect(ArchiveSafety.isUnsafe(entry: "../secret"), "dotdot")
        try expect(ArchiveSafety.isUnsafe(entry: "/etc/passwd"), "absolute")
        try expect(ArchiveSafety.isUnsafe(entry: "folder/../../outside"), "nested")
    }

    private static func catalog() throws {
        let bins = BinaryAvailability(
            magick: "/opt/homebrew/bin/magick",
            ffmpeg: "/opt/homebrew/bin/ffmpeg",
            textutil: "/usr/bin/textutil",
            sips: "/usr/bin/sips"
        )
        let png = URL(fileURLWithPath: "/tmp/a.png")
        let titles = Catalog.items(files: [png], mode: .convert, binaries: bins).map(\.title)
        try expect(titles.contains("JPG") && titles.contains("WEBP") && titles.contains("PDF"), titles.joined(separator: ","))
        try expect(!titles.contains("PNG") && !titles.contains("MP3"), "filtered")
        let mixed = Catalog.items(
            files: [png, URL(fileURLWithPath: "/tmp/a.mp3")],
            mode: .convert,
            binaries: bins
        )
        try expect(mixed.isEmpty, "mixed")
        try expect(Catalog.items(files: [png], mode: .actions, binaries: bins).count == 6, "actions")
        let tools = Catalog.items(files: [png], mode: .tools, binaries: bins).map(\.title)
        try expect(tools == ["COMPRESS", "METADATA", "EDIT", "ANNOTATE", "ADD BG", "CROP", "REDACT"], tools.joined(separator: ","))
        let pdf = Catalog.items(files: [URL(fileURLWithPath: "/tmp/a.pdf")], mode: .convert, binaries: bins).map(\.title)
        try expect(pdf.first == "DOCX" && pdf.contains("PAGES") && pdf.contains("MD"), pdf.joined(separator: ","))
        let slides = Catalog.items(files: [URL(fileURLWithPath: "/tmp/deck.pptx")], mode: .convert, binaries: bins).map(\.title)
        try expect(slides == ["PDF", "JPG", "PNG"], slides.joined(separator: ","))
        try expect(WheelMetrics.hitIndex(x: 0, y: -80, count: 8) == 0, "top petal")
        try expect(WheelMetrics.hitIndex(x: -80, y: 0, count: 3) == 0, "left petal")
        let video = Catalog.items(files: [URL(fileURLWithPath: "/tmp/clip.mp4")], mode: .convert, binaries: bins).map(\.title)
        try expect(video.contains("GIF") && video.contains("MP3") && video.contains("WEBM") && video.contains("WMV"), video.joined(separator: ","))
        let subs = Catalog.items(files: [URL(fileURLWithPath: "/tmp/captions.srt")], mode: .convert, binaries: bins).map(\.title)
        try expect(subs.contains("VTT") && subs.contains("TXT") && !subs.contains("SRT"), subs.joined(separator: ","))
    }

    private static func csv() throws {
        let rows = DelimitedText.parse("name,note\nAda,\"hello, world\"\n", separator: ",")
        try expect(rows.count == 2 && rows[1][1] == "hello, world", "parse")
        let written = DelimitedText.write(rows, separator: "\t")
        try expect(DelimitedText.parse(written, separator: "\t") == rows, "round trip")
    }

    private static func image() async throws {
        let bins = BinaryAvailability.current()
        if bins.magick == nil { print("skip image, no magick"); return }
        let dir = try OutputPaths.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let png = dir.appendingPathComponent("pixel.png")
        let bytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        try bytes.write(to: png)
        let jpg = try await Engine.runOne(.convert(.jpg), file: png)
        let data = try Data(contentsOf: jpg[0])
        try expect(Array(data.prefix(2)) == [0xFF, 0xD8], "jpeg header")
        let webp = try await Engine.runOne(.convert(.webp), file: png)
        let webpData = try Data(contentsOf: webp[0])
        try expect(String(data: webpData.prefix(4), encoding: .ascii) == "RIFF", "webp")
    }

    private static func pdf() async throws {
        let dir = try OutputPaths.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pdf = dir.appendingPathComponent("note.pdf")
        try TextPDF.write("Hello Dropwheel\nSecond line", to: pdf)
        let text = try await Engine.runOne(.convert(.txt), file: pdf)
        let body = try String(contentsOf: text[0], encoding: .utf8)
        try expect(body.contains("Hello Dropwheel"), body)
        let pages = try await Engine.runOne(.tool(.pdfSplit), file: pdf)
        try expect(pages.count == 1, "split")
        let settings = ConvertSettings(imageQuality: 90, audioBitrateKbps: 192, pdfDPI: 72, revealInFinder: false)
        let pngs = try await Engine.runOne(.convert(.png), file: pdf, settings: settings)
        let header = try Data(contentsOf: pngs[0]).prefix(8)
        try expect(Array(header) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], "png")
    }

    private static func audio() async throws {
        let bins = BinaryAvailability.current()
        guard let ffmpeg = bins.ffmpeg else { print("skip audio, no ffmpeg"); return }
        let dir = try OutputPaths.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let mp3 = dir.appendingPathComponent("tone.mp3")
        try await Shell.runChecked(ffmpeg, [
            "-hide_banner", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "anullsrc=r=44100:cl=mono",
            "-t", "0.2", mp3.path,
        ])
        let wav = try await Engine.runOne(.convert(.wav), file: mp3)
        let data = try Data(contentsOf: wav[0])
        try expect(String(data: data.prefix(4), encoding: .ascii) == "RIFF", "wav")
    }

    private static func documentAndZip() async throws {
        let bins = BinaryAvailability.current()
        if bins.textutil == nil || bins.ditto == nil || bins.tar == nil {
            print("skip document, missing tool")
            return
        }
        let dir = try OutputPaths.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let note = dir.appendingPathComponent("note.txt")
        try Data("hello dropwheel".utf8).write(to: note)
        let docx = try await Engine.runOne(.convert(.docx), file: note)
        let back = try await Engine.runOne(.convert(.txt), file: docx[0])
        let body = try String(contentsOf: back[0], encoding: .utf8)
        try expect(body.lowercased().contains("hello dropwheel"), body)

        let sheet = dir.appendingPathComponent("sheet.csv")
        try Data("name,city\nAda,Paris\n".utf8).write(to: sheet)
        let tsv = try await Engine.runOne(.convert(.tsv), file: sheet)
        let table = try String(contentsOf: tsv[0], encoding: .utf8)
        try expect(table.contains("Ada\tParis"), table)

        let folder = dir.appendingPathComponent("pack", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("inside".utf8).write(to: folder.appendingPathComponent("inside.txt"))
        let zip = try await Engine.runOne(.convert(.zip), file: folder)
        let extracted = try await Engine.runOne(.tool(.extractArchive), file: zip[0])
        let match = try FileManager.default.subpathsOfDirectory(atPath: extracted[0].path).first { $0.hasSuffix("inside.txt") }
        try expect(match != nil, "missing extracted file")
        if let match {
            let text = try String(contentsOf: extracted[0].appendingPathComponent(match), encoding: .utf8)
            try expect(text == "inside", text)
        }
    }

    private static func videoSubtitlesAndEpub() async throws {
        let bins = BinaryAvailability.current()
        try expect(bins.ffmpeg != nil && bins.zip != nil && bins.tar != nil, "ffmpeg, zip, and tar")
        let dir = try OutputPaths.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let clip = dir.appendingPathComponent("clip.mp4")
        try await Shell.runChecked(bins.ffmpeg!, [
            "-hide_banner", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "testsrc=size=160x120:rate=10",
            "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=44100",
            "-t", "0.4", "-shortest",
            "-pix_fmt", "yuv420p", "-c:v", "libx264", "-c:a", "aac",
            clip.path,
        ])
        let avi = try await Engine.runOne(.convert(.avi), file: clip)
        try expect(OutputPaths.fileSize(avi[0]) > 0, "avi")
        let gif = try await Engine.runOne(.convert(.gif), file: clip)
        let gifHeader = try Data(contentsOf: gif[0]).prefix(3)
        try expect(String(data: gifHeader, encoding: .ascii) == "GIF", "gif")
        let mp3 = try await Engine.runOne(.convert(.mp3), file: clip)
        try expect(OutputPaths.fileSize(mp3[0]) > 0, "mp3 from video")
        let still = try await Engine.runOne(.tool(.videoStill), file: clip)
        let jpeg = try Data(contentsOf: still[0]).prefix(2)
        try expect(Array(jpeg) == [0xFF, 0xD8], "still")
        let wma = try await Engine.runOne(.convert(.wma), file: mp3[0])
        try expect(wma[0].pathExtension == "wma" && OutputPaths.fileSize(wma[0]) > 0, "wma")

        let srt = dir.appendingPathComponent("captions.srt")
        try Data("1\n00:00:01,000 --> 00:00:03,000\nHello Dropwheel\n".utf8).write(to: srt)
        let vtt = try await Engine.runOne(.convert(.vtt), file: srt)
        let vttBody = try String(contentsOf: vtt[0], encoding: .utf8)
        try expect(vttBody.contains("WEBVTT") && vttBody.contains("Hello Dropwheel"), vttBody)

        let note = dir.appendingPathComponent("chapter.txt")
        try Data("A short chapter.\n".utf8).write(to: note)
        let epub = try await Engine.runOne(.convert(.epub), file: note)
        let back = try await Engine.runOne(.convert(.txt), file: epub[0])
        let chapter = try String(contentsOf: back[0], encoding: .utf8)
        try expect(chapter.contains("A short chapter"), chapter)
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw CheckError(message) }
    }
}

private struct CheckError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}
