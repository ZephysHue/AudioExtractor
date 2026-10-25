import Foundation

public enum Formatting {
    /// 75.4 -> "01:15", 3725 -> "1:02:05". With `fraction`, "01:15.4".
    public static func time(_ seconds: Double, fraction: Bool = false) -> String {
        guard seconds.isFinite, seconds >= 0 else { return fraction ? "00:00.0" : "00:00" }
        if fraction {
            let tenths = Int((seconds * 10).rounded())
            let total = tenths / 10
            let m = total / 60, s = total % 60
            let base = m >= 60
                ? String(format: "%d:%02d:%02d", m / 60, m % 60, s)
                : String(format: "%02d:%02d", m, s)
            return base + ".\(tenths % 10)"
        }
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    public static func fileSize(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }

    /// Rough output size estimate in bytes, used for the "预计大小" hint before export.
    public static func estimatedSize(duration: Double, format: AudioFormat, bitrateKbps: Int,
                                     sampleRate: Int, channels: Int) -> Int64 {
        let bytesPerSecond: Double
        switch format {
        case .mp3, .m4a, .aac: bytesPerSecond = Double(bitrateKbps) * 1000 / 8
        case .wav, .aiff: bytesPerSecond = Double(sampleRate * channels * 2)
        case .flac: bytesPerSecond = Double(sampleRate * channels * 2) * 0.6
        }
        return Int64(max(0, duration) * bytesPerSecond)
    }
}
