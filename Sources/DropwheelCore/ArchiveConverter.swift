import Foundation

enum ArchiveConverter {
    static func convert(_ source: URL, to format: Format, bins: BinaryAvailability) async throws -> [URL] {
        switch format {
        case .zip, .tar, .tgz:
            break
        default:
            throw ConvertError.unsupported("Dropwheel can't turn this into \(format.title).")
        }
        let dest = OutputPaths.uniqueFile(
            in: source.deletingLastPathComponent(),
            base: OutputPaths.baseName(of: source),
            ext: format.fileExtension
        )
        if FileKind.of(source) == .archive {
            let tmp = try OutputPaths.makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: tmp) }
            let contents = tmp.appendingPathComponent("contents", isDirectory: true)
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            try await extract(source, to: contents, bins: bins)
            try await pack(directory: contents, to: dest, format: format, bins: bins, includeParent: false)
        } else {
            try await pack(directory: source, to: dest, format: format, bins: bins, includeParent: true)
        }
        return [dest]
    }

    static func extract(_ source: URL, bins: BinaryAvailability) async throws -> [URL] {
        let dest = OutputPaths.uniqueDirectory(
            in: source.deletingLastPathComponent(),
            base: OutputPaths.baseName(of: source)
        )
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try await extract(source, to: dest, bins: bins)
        return [dest]
    }

    private static func extract(_ source: URL, to dest: URL, bins: BinaryAvailability) async throws {
        if isPlainGzip(source) {
            try await extractGzip(source, to: dest, bins: bins)
            return
        }
        if OutputPaths.normalizedExtension(source) == "rar" {
            try await extractRar(source, to: dest, bins: bins)
            return
        }
        guard let tar = bins.tar else { throw ConvertError.missingTool("tar") }
        try await validate(source, tar: tar)
        try await Shell.runChecked(tar, ["-xf", source.path, "-C", dest.path])
        let junk = dest.appendingPathComponent("__MACOSX")
        try? FileManager.default.removeItem(at: junk)
    }

    private static func validate(_ source: URL, tar: String) async throws {
        let names = try await Shell.runChecked(tar, ["-tf", source.path])
        for line in names.stdout.split(whereSeparator: \.isNewline) {
            if ArchiveSafety.isUnsafe(entry: String(line)) {
                throw ConvertError.failed("This archive contains an unsafe path (\(line)).")
            }
        }
        let verbose = try await Shell.runChecked(tar, ["-tvf", source.path])
        for line in verbose.stdout.split(whereSeparator: \.isNewline) {
            let raw = String(line)
            if raw.first == "l" || raw.contains(" -> ") {
                throw ConvertError.failed("This archive contains a link, so Dropwheel did not extract it.")
            }
        }
    }

    private static func extractGzip(_ source: URL, to dest: URL, bins: BinaryAvailability) async throws {
        guard let gzip = bins.gzip else { throw ConvertError.missingTool("gzip") }
        var name = source.lastPathComponent
        if name.lowercased().hasSuffix(".gz") {
            name = String(name.dropLast(3))
        }
        if name.isEmpty { name = "file" }
        let output = dest.appendingPathComponent(name)
        try await Shell.runChecked(gzip, ["-dc", source.path], stdoutFile: output)
    }

    private static func extractRar(_ source: URL, to dest: URL, bins: BinaryAvailability) async throws {
        guard let unar = bins.unar else {
            throw ConvertError.missingTool("unar (brew install unar)")
        }
        try await Shell.runChecked(unar, ["-quiet", "-force-overwrite", "-output-directory", dest.path, source.path])
    }

    private static func pack(
        directory: URL,
        to dest: URL,
        format: Format,
        bins: BinaryAvailability,
        includeParent: Bool
    ) async throws {
        switch format {
        case .zip:
            if includeParent {
                guard let ditto = bins.ditto else { throw ConvertError.missingTool("ditto") }
                try await Shell.runChecked(ditto, ["-c", "-k", "--keepParent", directory.path, dest.path])
            } else {
                guard let zip = bins.zip else { throw ConvertError.missingTool("zip") }
                let names = try childNames(directory)
                try await Shell.runChecked(zip, ["-r", "-X", dest.path] + names, cwd: directory)
            }
        case .tar, .tgz:
            guard let tar = bins.tar else { throw ConvertError.missingTool("tar") }
            let flags = format == .tgz ? "-czf" : "-cf"
            if includeParent {
                let parent = directory.deletingLastPathComponent()
                try await Shell.runChecked(tar, [flags, dest.path, "-C", parent.path, directory.lastPathComponent])
            } else {
                let names = try childNames(directory)
                try await Shell.runChecked(tar, [flags, dest.path, "-C", directory.path] + names)
            }
        default:
            throw ConvertError.unsupported("That is not an archive format.")
        }
    }

    private static func childNames(_ directory: URL) throws -> [String] {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0 != ".DS_Store" }
        if names.isEmpty { throw ConvertError.failed("There is nothing to archive.") }
        return names
    }

    private static func isPlainGzip(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name.hasSuffix(".gz") && !name.hasSuffix(".tar.gz")
    }
}
