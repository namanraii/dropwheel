import Foundation

enum AudioConverter {
    static func convert(
        _ source: URL,
        to format: Format,
        settings: ConvertSettings,
        bins: BinaryAvailability
    ) async throws -> [URL] {
        let dest = OutputPaths.uniqueFile(
            in: source.deletingLastPathComponent(),
            base: OutputPaths.baseName(of: source),
            ext: format.fileExtension
        )
        try await encode(
            source,
            to: dest,
            format: format,
            bitrate: settings.audioBitrateKbps,
            normalize: false,
            bins: bins
        )
        return [dest]
    }

    static func tool(_ tool: Tool, source: URL, bins: BinaryAvailability) async throws -> [URL] {
        let format = outputFormat(for: source, tool: tool)
        let bitrate: Int
        let normalize: Bool
        switch tool {
        case .audio128:
            bitrate = 128
            normalize = false
        case .audio192:
            bitrate = 192
            normalize = false
        case .normalize:
            bitrate = 192
            normalize = true
        default:
            throw ConvertError.unsupported("That tool does not apply to audio.")
        }
        let dest = OutputPaths.uniqueFile(
            in: source.deletingLastPathComponent(),
            base: OutputPaths.baseName(of: source),
            ext: format.fileExtension
        )
        try await encode(source, to: dest, format: format, bitrate: bitrate, normalize: normalize, bins: bins)
        return [dest]
    }

    private static func outputFormat(for source: URL, tool: Tool) -> Format {
        if tool == .normalize {
            switch OutputPaths.normalizedExtension(source) {
            case "mp3": return .mp3
            case "ogg": return .ogg
            case "opus": return .opus
            case "flac": return .flac
            case "wav": return .wav
            case "aiff": return .aiff
            case "wma": return .wma
            default: return .m4a
            }
        }
        switch OutputPaths.normalizedExtension(source) {
        case "mp3": return .mp3
        case "ogg": return .ogg
        case "opus": return .opus
        case "m4a": return .m4a
        case "wma": return .wma
        default: return .m4a
        }
    }

    private static func encode(
        _ source: URL,
        to dest: URL,
        format: Format,
        bitrate: Int,
        normalize: Bool,
        bins: BinaryAvailability
    ) async throws {
        guard let ffmpeg = bins.ffmpeg else {
            throw ConvertError.missingTool("ffmpeg (brew install ffmpeg)")
        }
        var args = ["-hide_banner", "-loglevel", "error", "-y", "-i", source.path, "-vn"]
        if normalize {
            args += ["-af", "loudnorm=I=-16:TP=-1.5:LRA=11"]
        }
        args += codecArguments(format: format, bitrate: bitrate)
        args.append(dest.path)
        try await Shell.runChecked(ffmpeg, args)
    }

    private static func codecArguments(format: Format, bitrate: Int) -> [String] {
        switch format {
        case .mp3:
            return ["-c:a", "libmp3lame", "-b:a", "\(bitrate)k"]
        case .m4a:
            return ["-c:a", "aac", "-b:a", "\(bitrate)k"]
        case .wav:
            return ["-c:a", "pcm_s16le"]
        case .flac:
            return ["-c:a", "flac"]
        case .ogg:
            return ["-c:a", "libvorbis", "-q:a", "5"]
        case .opus:
            return ["-c:a", "libopus", "-b:a", "\(min(bitrate, 160))k"]
        case .aiff:
            return ["-c:a", "pcm_s16be"]
        case .wma:
            return ["-c:a", "wmav2", "-b:a", "\(bitrate)k"]
        default:
            return ["-c:a", "aac", "-b:a", "\(bitrate)k"]
        }
    }
}
