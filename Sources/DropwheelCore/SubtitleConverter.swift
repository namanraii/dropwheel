import Foundation

enum SubtitleConverter {
    static func convert(_ source: URL, to format: Format) throws -> [URL] {
        let raw = try String(contentsOf: source, encoding: .utf8)
        let cues = Cue.parse(raw)
        let body: String
        switch format {
        case .srt:
            guard !cues.isEmpty else { throw ConvertError.failed("No subtitles found in this file.") }
            body = Cue.writeSRT(cues)
        case .vtt:
            guard !cues.isEmpty else { throw ConvertError.failed("No subtitles found in this file.") }
            body = Cue.writeVTT(cues)
        case .txt:
            let lines = cues.map(\.text).filter { !$0.isEmpty }
            guard !lines.isEmpty else { throw ConvertError.failed("No subtitles found in this file.") }
            body = lines.joined(separator: "\n")
        default:
            throw ConvertError.unsupported("Dropwheel can't turn subtitles into \(format.title).")
        }
        let dest = OutputPaths.uniqueFile(
            in: source.deletingLastPathComponent(),
            base: OutputPaths.baseName(of: source),
            ext: format.fileExtension
        )
        try Data(body.utf8).write(to: dest)
        return [dest]
    }
}

struct Cue: Equatable {
    var start: String
    var end: String
    var text: String

    static func parse(_ raw: String) -> [Cue] {
        let blocks = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n\n")
        var cues: [Cue] = []
        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let timing = lines[timingIndex]
            let parts = timing.components(separatedBy: "-->")
            guard parts.count >= 2 else { continue }
            let start = normalizeTime(parts[0])
            let end = normalizeTime(parts[1])
            guard let start, let end else { continue }
            let text = lines.dropFirst(timingIndex + 1).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            cues.append(Cue(start: start, end: end, text: text))
        }
        return cues
    }

    static func writeSRT(_ cues: [Cue]) -> String {
        cues.enumerated().map { index, cue in
            "\(index + 1)\n\(clock(cue.start, separator: ",")) --> \(clock(cue.end, separator: ","))\n\(cue.text)\n"
        }.joined(separator: "\n")
    }

    static func writeVTT(_ cues: [Cue]) -> String {
        let body = cues.map { cue in
            "\(clock(cue.start, separator: ".")) --> \(clock(cue.end, separator: "."))\n\(cue.text)\n"
        }.joined(separator: "\n")
        return "WEBVTT\n\n\(body)"
    }

    private static func normalizeTime(_ raw: String) -> String? {
        let token = raw.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        let cleaned = token.replacingOccurrences(of: ",", with: ".")
        let pieces = cleaned.split(separator: ":").map(String.init)
        guard pieces.count == 2 || pieces.count == 3 else { return nil }
        let secondsPart = pieces.last ?? ""
        let secondBits = secondsPart.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard let seconds = Int(secondBits[0]) else { return nil }
        let millisText = secondBits.count > 1 ? secondBits[1] : "0"
        let millis = Int(millisText.padding(toLength: 3, withPad: "0", startingAt: 0).prefix(3)) ?? 0
        let minutes = Int(pieces[pieces.count - 2]) ?? 0
        let hours = pieces.count == 3 ? (Int(pieces[0]) ?? 0) : 0
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, seconds, millis)
    }

    private static func clock(_ normalized: String, separator: Character) -> String {
        var copy = normalized
        if let dot = copy.lastIndex(of: ".") {
            copy.replaceSubrange(dot...dot, with: String(separator))
        }
        return copy
    }
}
