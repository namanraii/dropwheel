import Foundation

enum VideoConverter {
    static func convert(
        _ source: URL,
        to format: Format,
        settings: ConvertSettings,
        bins: BinaryAvailability
    ) async throws -> [URL] {
        switch format {
        case .mp3, .m4a, .wav, .flac, .ogg, .opus, .aiff, .wma:
            return try await AudioConverter.convert(source, to: format, settings: settings, bins: bins)
        case .jpg, .png:
            return try await still(source, format: format, bins: bins)
        case .gif:
            return [try await renderGIF(source, bins: bins)]
        case .mp4, .mov, .mkv, .webm, .avi, .wmv:
            return [try await transcode(source, to: format, profile: .standard, speed: nil, mute: false, bins: bins)]
        default:
            throw ConvertError.unsupported("Dropwheel can't turn this video into \(format.title).")
        }
    }

    static func compress(_ source: URL, tiny: Bool, bins: BinaryAvailability) async throws -> [URL] {
        let format = container(for: source)
        let profile: Profile = tiny ? .tiny : .smaller
        return [try await transcode(source, to: format, profile: profile, speed: nil, mute: false, bins: bins)]
    }

    static func still(_ source: URL, bins: BinaryAvailability) async throws -> [URL] {
        try await still(source, format: .jpg, bins: bins)
    }

    static func speed(_ source: URL, factor: Double, bins: BinaryAvailability) async throws -> [URL] {
        let format = container(for: source)
        return [try await transcode(source, to: format, profile: .standard, speed: factor, mute: false, bins: bins)]
    }

    static func stripContainer(_ source: URL, bins: BinaryAvailability) async throws -> [URL] {
        guard let ffmpeg = bins.ffmpeg else {
            throw ConvertError.missingTool("ffmpeg (brew install ffmpeg)")
        }
        let ext = source.pathExtension.isEmpty ? "mp4" : source.pathExtension
        let dest = OutputPaths.uniqueFile(
            in: source.deletingLastPathComponent(),
            base: OutputPaths.baseName(of: source),
            ext: ext
        )
        try await Shell.runChecked(ffmpeg, [
            "-hide_banner", "-loglevel", "error", "-y",
            "-i", source.path,
            "-map_metadata", "-1",
            "-c", "copy",
            dest.path,
        ])
        return [dest]
    }

    static func mute(_ source: URL, bins: BinaryAvailability) async throws -> [URL] {
        let format = container(for: source)
        return [try await transcode(source, to: format, profile: .standard, speed: nil, mute: true, bins: bins)]
    }

    private enum Profile {
        case standard
        case smaller
        case tiny

        var crf: Int {
            switch self {
            case .standard: return 23
            case .smaller: return 28
            case .tiny: return 34
            }
        }

        var maxWidth: Int? {
            switch self {
            case .standard: return nil
            case .smaller: return 1280
            case .tiny: return 854
            }
        }
    }

    private static func container(for source: URL) -> Format {
        switch OutputPaths.normalizedExtension(source) {
        case "mov": return .mov
        case "mkv": return .mkv
        case "webm": return .webm
        case "avi": return .avi
        case "wmv": return .wmv
        default: return .mp4
        }
    }

    private static func still(_ source: URL, format: Format, bins: BinaryAvailability) async throws -> [URL] {
        guard let ffmpeg = bins.ffmpeg else {
            throw ConvertError.missingTool("ffmpeg (brew install ffmpeg)")
        }
        let dest = OutputPaths.uniqueFile(
            in: source.deletingLastPathComponent(),
            base: OutputPaths.baseName(of: source),
            ext: format == .png ? "png" : "jpg"
        )
        try await Shell.runChecked(ffmpeg, [
            "-hide_banner", "-loglevel", "error", "-y",
            "-i", source.path,
            "-frames:v", "1",
            dest.path,
        ])
        return [dest]
    }

    private static func renderGIF(_ source: URL, bins: BinaryAvailability) async throws -> URL {
        guard let ffmpeg = bins.ffmpeg else {
            throw ConvertError.missingTool("ffmpeg (brew install ffmpeg)")
        }
        let dest = OutputPaths.uniqueFile(
            in: source.deletingLastPathComponent(),
            base: OutputPaths.baseName(of: source),
            ext: "gif"
        )
        try await Shell.runChecked(ffmpeg, [
            "-hide_banner", "-loglevel", "error", "-y",
            "-i", source.path,
            "-t", "8",
            "-vf", "fps=12,scale=480:-2:flags=lanczos,split[s0][s1];[s0]palettegen=stats_mode=diff[p];[s1][p]paletteuse",
            "-loop", "0",
            dest.path,
        ])
        return dest
    }

    private static func transcode(
        _ source: URL,
        to format: Format,
        profile: Profile,
        speed: Double?,
        mute: Bool,
        bins: BinaryAvailability
    ) async throws -> URL {
        guard let ffmpeg = bins.ffmpeg else {
            throw ConvertError.missingTool("ffmpeg (brew install ffmpeg)")
        }
        let dest = OutputPaths.uniqueFile(
            in: source.deletingLastPathComponent(),
            base: OutputPaths.baseName(of: source),
            ext: format.fileExtension
        )
        var args = ["-hide_banner", "-loglevel", "error", "-y", "-i", source.path]
        if let filter = videoFilter(speed: speed, maxWidth: profile.maxWidth) {
            args += ["-vf", filter]
        }
        args += ["-map", "0:v:0"]
        if mute {
            args += ["-an"]
        } else {
            args += ["-map", "0:a:0?"]
            if let speed, abs(speed - 1) > 0.01 {
                args += ["-af", "atempo=\(speed)"]
            }
        }
        args += codecArguments(format: format, profile: profile, mute: mute)
        if format == .mp4 || format == .mov {
            args += ["-movflags", "+faststart"]
        }
        args.append(dest.path)
        try await Shell.runChecked(ffmpeg, args)
        return dest
    }

    private static func videoFilter(speed: Double?, maxWidth: Int?) -> String? {
        var parts: [String] = []
        if let speed, abs(speed - 1) > 0.01 {
            let scale = 1 / speed
            parts.append(String(format: "setpts=%.4f*PTS", scale))
        }
        if let maxWidth {
            parts.append("scale='min(\(maxWidth),iw)':-2")
        } else {
            parts.append("scale=trunc(iw/2)*2:trunc(ih/2)*2")
        }
        return parts.joined(separator: ",")
    }

    private static func codecArguments(format: Format, profile: Profile, mute: Bool) -> [String] {
        var args: [String]
        switch format {
        case .webm:
            args = ["-c:v", "libvpx-vp9", "-crf", "\(profile.crf + 8)", "-b:v", "0", "-cpu-used", "4", "-row-mt", "1"]
            if !mute { args += ["-c:a", "libopus", "-b:a", "96k"] }
        case .avi:
            args = ["-c:v", "mpeg4", "-q:v", profile == .tiny ? "10" : "5"]
            if !mute { args += ["-c:a", "libmp3lame", "-b:a", "160k"] }
        case .wmv:
            let rate = profile == .tiny ? "600k" : (profile == .smaller ? "1000k" : "1800k")
            args = ["-c:v", "wmv2", "-b:v", rate]
            if !mute { args += ["-c:a", "wmav2", "-b:a", "128k"] }
        default:
            args = ["-c:v", "libx264", "-preset", "medium", "-crf", "\(profile.crf)", "-pix_fmt", "yuv420p"]
            if !mute { args += ["-c:a", "aac", "-b:a", "160k"] }
        }
        return args
    }
}
