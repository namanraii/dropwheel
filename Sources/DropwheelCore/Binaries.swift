import Foundation

public struct BinaryAvailability: Sendable, Equatable {
    public var magick: String?
    public var ffmpeg: String?
    public var ghostscript: String?
    public var libreOffice: String?
    public var textutil: String?
    public var zip: String?
    public var tar: String?
    public var ditto: String?
    public var gzip: String?
    public var unar: String?
    public var sips: String?

    public init(
        magick: String? = nil,
        ffmpeg: String? = nil,
        ghostscript: String? = nil,
        libreOffice: String? = nil,
        textutil: String? = nil,
        zip: String? = nil,
        tar: String? = nil,
        ditto: String? = nil,
        gzip: String? = nil,
        unar: String? = nil,
        sips: String? = nil
    ) {
        self.magick = magick
        self.ffmpeg = ffmpeg
        self.ghostscript = ghostscript
        self.libreOffice = libreOffice
        self.textutil = textutil
        self.zip = zip
        self.tar = tar
        self.ditto = ditto
        self.gzip = gzip
        self.unar = unar
        self.sips = sips
    }

    public static func current() -> BinaryAvailability {
        BinaryAvailability(
            magick: find("magick"),
            ffmpeg: find("ffmpeg"),
            ghostscript: find("gs"),
            libreOffice: find(
                "soffice",
                extra: ["/Applications/LibreOffice.app/Contents/MacOS/soffice"]
            ),
            textutil: find("textutil"),
            zip: find("zip"),
            tar: find("tar"),
            ditto: find("ditto"),
            gzip: find("gzip"),
            unar: find("unar"),
            sips: find("sips")
        )
    }

    public static func find(_ name: String, extra: [String] = []) -> String? {
        let candidates = extra + [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "/bin/\(name)",
            "/usr/sbin/\(name)",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

enum Shell {
    struct Result: Sendable {
        var status: Int32
        var stdout: String
        var stderr: String
    }

    static func run(
        _ executable: String,
        _ arguments: [String],
        cwd: URL? = nil,
        stdoutFile: URL? = nil
    ) async throws -> Result {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            if let cwd {
                process.currentDirectoryURL = cwd
            }

            let errURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("dropwheel-err-\(UUID().uuidString)")
            FileManager.default.createFile(atPath: errURL.path, contents: nil)
            let errHandle = try FileHandle(forWritingTo: errURL)
            process.standardError = errHandle

            let outURL: URL
            let ownsStdout: Bool
            if let stdoutFile {
                if !FileManager.default.fileExists(atPath: stdoutFile.path) {
                    FileManager.default.createFile(atPath: stdoutFile.path, contents: nil)
                }
                outURL = stdoutFile
                ownsStdout = false
            } else {
                outURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("dropwheel-out-\(UUID().uuidString)")
                FileManager.default.createFile(atPath: outURL.path, contents: nil)
                ownsStdout = true
            }
            let outHandle = try FileHandle(forWritingTo: outURL)
            process.standardOutput = outHandle

            do {
                try process.run()
            } catch {
                try? outHandle.close()
                try? errHandle.close()
                if ownsStdout { try? FileManager.default.removeItem(at: outURL) }
                try? FileManager.default.removeItem(at: errURL)
                throw ConvertError.failed("Could not run \(URL(fileURLWithPath: executable).lastPathComponent).")
            }
            process.waitUntilExit()
            try? outHandle.close()
            try? errHandle.close()

            let stdout = ownsStdout ? ((try? String(contentsOf: outURL, encoding: .utf8)) ?? "") : ""
            let stderr = (try? String(contentsOf: errURL, encoding: .utf8)) ?? ""
            if ownsStdout { try? FileManager.default.removeItem(at: outURL) }
            try? FileManager.default.removeItem(at: errURL)
            return Result(status: process.terminationStatus, stdout: stdout, stderr: stderr)
        }.value
    }

    @discardableResult
    static func runChecked(
        _ executable: String,
        _ arguments: [String],
        cwd: URL? = nil,
        stdoutFile: URL? = nil
    ) async throws -> Result {
        let result = try await run(executable, arguments, cwd: cwd, stdoutFile: stdoutFile)
        guard result.status == 0 else {
            let raw = result.stderr.isEmpty ? result.stdout : result.stderr
            throw ConvertError.failed(ConvertError.clean(raw))
        }
        return result
    }
}
