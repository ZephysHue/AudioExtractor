import Foundation

/// Output container / codec the user can export to.
public enum AudioFormat: String, CaseIterable, Codable, Identifiable, Sendable {
    case mp3, m4a, aac, wav, aiff, flac

    public var id: String { rawValue }

    public var fileExtension: String {
        switch self {
        case .aiff: return "aif"
        default: return rawValue
        }
    }

    public var displayName: String { rawValue.uppercased() }

    public var subtitle: String {
        switch self {
        case .mp3: return "兼容性最好"
        case .m4a: return "AAC · 体积小音质好"
        case .aac: return "AAC 裸流 (ADTS)"
        case .wav: return "无损 PCM · 体积大"
        case .aiff: return "无损 PCM · Apple"
        case .flac: return "无损压缩"
        }
    }

    /// Lossy formats expose a bitrate choice.
    public var supportsBitrate: Bool {
        switch self {
        case .mp3, .m4a, .aac: return true
        case .wav, .aiff, .flac: return false
        }
    }

    /// Codecs in these formats can't go above 48 kHz.
    public var maxSampleRate: Int? {
        switch self {
        case .mp3, .m4a, .aac: return 48_000
        default: return nil
        }
    }

    public init?(fileExtension ext: String) {
        let e = ext.lowercased()
        if e == "aif" || e == "aiff" { self = .aiff; return }
        self.init(rawValue: e)
    }
}

public enum SampleRateOption: Int, CaseIterable, Codable, Identifiable, Sendable {
    case original = 0
    case hz22050 = 22_050
    case hz44100 = 44_100
    case hz48000 = 48_000

    public var id: Int { rawValue }
    public var displayName: String {
        switch self {
        case .original: return "原始"
        case .hz22050: return "22.05 kHz"
        case .hz44100: return "44.1 kHz"
        case .hz48000: return "48 kHz"
        }
    }
}

public enum ChannelOption: Int, CaseIterable, Codable, Identifiable, Sendable {
    case original = 0
    case mono = 1
    case stereo = 2

    public var id: Int { rawValue }
    public var displayName: String {
        switch self {
        case .original: return "原始"
        case .mono: return "单声道"
        case .stereo: return "立体声"
        }
    }
}

public enum Bitrates {
    public static let all: [Int] = [64, 96, 128, 160, 192, 256, 320]
}

/// Everything that describes one export job: what part of the source, which effects, which output.
public struct ExportOptions: Codable, Equatable, Sendable {
    public var format: AudioFormat
    public var bitrateKbps: Int
    public var sampleRate: SampleRateOption
    public var channels: ChannelOption

    /// Selected range in seconds. `trimEnd == nil` means "until the end".
    public var trimStart: Double
    public var trimEnd: Double?

    /// Fade durations in seconds.
    public var fadeIn: Double
    public var fadeOut: Double

    /// Linear gain, 1.0 = unchanged, 0...2.
    public var volume: Float

    public init(format: AudioFormat = .mp3,
                bitrateKbps: Int = 192,
                sampleRate: SampleRateOption = .original,
                channels: ChannelOption = .original,
                trimStart: Double = 0,
                trimEnd: Double? = nil,
                fadeIn: Double = 0,
                fadeOut: Double = 0,
                volume: Float = 1) {
        self.format = format
        self.bitrateKbps = bitrateKbps
        self.sampleRate = sampleRate
        self.channels = channels
        self.trimStart = trimStart
        self.trimEnd = trimEnd
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
        self.volume = volume
    }

    /// Resolve the concrete sample rate / channel count for a given source.
    public func resolvedSampleRate(source: Double) -> Int {
        var sr = sampleRate == .original ? Int(source.rounded()) : sampleRate.rawValue
        if sr <= 0 { sr = 44_100 }
        if let maxSR = format.maxSampleRate, sr > maxSR { sr = maxSR }
        // LAME / AAC only accept standard rates; snap odd ones to the nearest standard rate.
        if format.maxSampleRate != nil {
            let standard = [8_000, 11_025, 12_000, 16_000, 22_050, 24_000, 32_000, 44_100, 48_000]
            sr = standard.min(by: { abs($0 - sr) < abs($1 - sr) }) ?? 44_100
        }
        return sr
    }

    public func resolvedChannels(source: Int) -> Int {
        switch channels {
        case .mono: return 1
        case .stereo: return 2
        case .original: return min(max(source, 1), 2)
        }
    }

    /// Clamp the trim range into `0...duration` and guarantee a minimum length.
    public func resolvedRange(duration: Double) -> ClosedRange<Double> {
        let start = min(max(0, trimStart), max(0, duration))
        var end = min(trimEnd ?? duration, duration)
        if end < start { end = start }
        return start...end
    }
}
