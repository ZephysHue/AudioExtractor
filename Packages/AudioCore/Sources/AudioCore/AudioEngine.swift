import AVFoundation
import Foundation

public enum AudioEngineError: LocalizedError, Equatable {
    case noAudioTrack
    case emptySelection
    case readerFailed(String)
    case encoderFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noAudioTrack: return "这个文件里没有音轨"
        case .emptySelection: return "选中的片段太短了"
        case .readerFailed(let m): return "读取失败：\(m)"
        case .encoderFailed(let m): return "编码失败：\(m)"
        }
    }
}

public struct SourceInfo: Equatable, Sendable {
    public let duration: Double
    public let sampleRate: Double
    public let channelCount: Int
    public let hasVideo: Bool
}

public struct ExportResult: Equatable, Sendable {
    public let url: URL
    public let duration: Double
    public let fileSize: Int64
    public let format: AudioFormat
    public let sampleRate: Int
    public let channels: Int
}

/// Extract / trim / convert audio. All work is done off the main actor.
public enum AudioEngine {

    // MARK: Inspect

    public static func inspect(_ url: URL) async throws -> SourceInfo {
        try await inspect(asset: AVURLAsset(url: url))
    }

    static func inspect(asset: AVAsset) async throws -> SourceInfo {
        let duration = try await asset.load(.duration).seconds
        let audio = try await asset.loadTracks(withMediaType: .audio)
        guard let track = audio.first else { throw AudioEngineError.noAudioTrack }
        var sampleRate = 44_100.0
        var channels = 2
        let descriptions = try await track.load(.formatDescriptions)
        if let desc = descriptions.first,
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee {
            if asbd.mSampleRate > 0 { sampleRate = asbd.mSampleRate }
            if asbd.mChannelsPerFrame > 0 { channels = Int(asbd.mChannelsPerFrame) }
        }
        let video = try await asset.loadTracks(withMediaType: .video)
        return SourceInfo(duration: duration.isFinite ? max(0, duration) : 0,
                          sampleRate: sampleRate,
                          channelCount: channels,
                          hasVideo: !video.isEmpty)
    }

    // MARK: Export

    /// Decode `source` (video or audio), apply trim / fades / gain, encode to `destination`.
    /// `progress` is called with values in 0...1 (from a background thread).
    public static func export(source: URL,
                              to destination: URL,
                              options: ExportOptions,
                              progress: (@Sendable (Double) -> Void)? = nil) async throws -> ExportResult {
        let asset = AVURLAsset(url: source)
        let info = try await inspect(asset: asset)
        let tracks = try await asset.loadTracks(withMediaType: .audio)

        let range = options.resolvedRange(duration: info.duration)
        let length = range.upperBound - range.lowerBound
        guard length >= 0.05 else { throw AudioEngineError.emptySelection }

        let sampleRate = options.resolvedSampleRate(source: info.sampleRate)
        let channels = options.resolvedChannels(source: info.channelCount)

        let fm = FileManager.default
        try? fm.removeItem(at: destination)
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        let timeRange = CMTimeRange(start: CMTime(seconds: range.lowerBound, preferredTimescale: 44_100),
                                    duration: CMTime(seconds: length, preferredTimescale: 44_100))
        let reader = try PCMReader(asset: asset, tracks: tracks, sampleRate: sampleRate,
                                   channels: channels, timeRange: timeRange)

        let sink: AudioSink
        do {
            switch options.format {
            case .mp3:
                sink = try MP3Sink(url: destination, sampleRate: sampleRate, channels: channels,
                                   bitrateKbps: options.bitrateKbps)
            default:
                sink = try AVAudioFileSink(url: destination, format: options.format, sampleRate: sampleRate,
                                           channels: channels, bitrateKbps: options.bitrateKbps)
            }
        } catch {
            reader.cancel()
            throw error
        }

        let processor = GainProcessor(options: options, length: length, sampleRate: sampleRate, channels: channels)
        var written = 0
        var lastReported = -1.0
        do {
            while let chunk = try reader.next() {
                try Task.checkCancellation()
                var samples = chunk
                let frames = samples.count / channels
                guard frames > 0 else { continue }
                processor.apply(&samples, frames: frames, startFrame: written)
                try samples.withUnsafeBufferPointer { try sink.write($0, frames: frames) }
                written += frames
                let p = min(1, Double(written) / Double(processor.totalFrames))
                if p - lastReported >= 0.005 {
                    lastReported = p
                    progress?(p)
                }
            }
            try sink.finish()
        } catch {
            reader.cancel()
            sink.abort()
            try? fm.removeItem(at: destination)
            throw error
        }
        progress?(1)

        let attributes = try? fm.attributesOfItem(atPath: destination.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        return ExportResult(url: destination,
                            duration: Double(written) / Double(sampleRate),
                            fileSize: size,
                            format: options.format,
                            sampleRate: sampleRate,
                            channels: channels)
    }

    // MARK: Waveform

    /// Peak amplitudes (0...1, normalised) of the whole file, `bins` values.
    public static func waveform(for url: URL, bins: Int) async throws -> [Float] {
        precondition(bins > 0)
        let asset = AVURLAsset(url: url)
        let info = try await inspect(asset: asset)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let rate = 8_000
        let reader = try PCMReader(asset: asset, tracks: tracks, sampleRate: rate, channels: 1, timeRange: nil)
        let total = max(Double(bins), info.duration * Double(rate))
        let perBin = max(1, Int(total / Double(bins)))

        var peaks = [Float]()
        peaks.reserveCapacity(bins)
        var current: Float = 0
        var count = 0
        while let chunk = try reader.next() {
            try Task.checkCancellation()
            for s in chunk {
                let a = abs(s)
                if a > current { current = a }
                count += 1
                if count == perBin {
                    peaks.append(current)
                    current = 0
                    count = 0
                }
            }
        }
        if count > 0 { peaks.append(current) }
        if peaks.count > bins { peaks = Array(peaks.prefix(bins)) }
        while peaks.count < bins { peaks.append(0) }
        let maxPeak = peaks.max() ?? 0
        if maxPeak > 0 { peaks = peaks.map { $0 / maxPeak } }
        return peaks
    }
}

// MARK: - Processing

/// Applies volume and linear fade in/out to interleaved float samples.
struct GainProcessor {
    let volume: Float
    let fadeInFrames: Int
    let fadeOutFrames: Int
    let totalFrames: Int
    let channels: Int

    init(options: ExportOptions, length: Double, sampleRate: Int, channels: Int) {
        var fadeIn = max(0, options.fadeIn)
        var fadeOut = max(0, options.fadeOut)
        // Fades may not overlap more than the clip itself.
        if fadeIn + fadeOut > length, fadeIn + fadeOut > 0 {
            let k = length / (fadeIn + fadeOut)
            fadeIn *= k
            fadeOut *= k
        }
        self.volume = min(max(options.volume, 0), 4)
        self.fadeInFrames = Int(fadeIn * Double(sampleRate))
        self.fadeOutFrames = Int(fadeOut * Double(sampleRate))
        self.totalFrames = max(1, Int((length * Double(sampleRate)).rounded()))
        self.channels = channels
    }

    var isIdentity: Bool { volume == 1 && fadeInFrames == 0 && fadeOutFrames == 0 }

    func gain(at frame: Int) -> Float {
        var g = volume
        if fadeInFrames > 0, frame < fadeInFrames {
            g *= Float(frame) / Float(fadeInFrames)
        }
        if fadeOutFrames > 0 {
            let remain = totalFrames - frame
            if remain < fadeOutFrames {
                g *= max(0, Float(remain) / Float(fadeOutFrames))
            }
        }
        return g
    }

    func apply(_ samples: inout [Float], frames: Int, startFrame: Int) {
        guard !isIdentity else { return }
        samples.withUnsafeMutableBufferPointer { buf in
            for f in 0..<frames {
                let g = gain(at: startFrame + f)
                if g == 1 { continue }
                let base = f * channels
                for c in 0..<channels {
                    let v = buf[base + c] * g
                    buf[base + c] = min(1, max(-1, v))
                }
            }
        }
    }
}

// MARK: - Reader

/// Decodes all audio tracks of an asset to interleaved Float32 PCM at the given rate / channels.
final class PCMReader {
    private let reader: AVAssetReader
    private let output: AVAssetReaderAudioMixOutput

    init(asset: AVAsset, tracks: [AVAssetTrack], sampleRate: Int, channels: Int, timeRange: CMTimeRange?) throws {
        guard !tracks.isEmpty else { throw AudioEngineError.noAudioTrack }
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw AudioEngineError.readerFailed(error.localizedDescription)
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
        ]
        output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw AudioEngineError.readerFailed("无法解码该音轨") }
        reader.add(output)
        if let timeRange { reader.timeRange = timeRange }
        guard reader.startReading() else {
            throw AudioEngineError.readerFailed(reader.error?.localizedDescription ?? "未知错误")
        }
    }

    /// Next chunk of interleaved samples, or nil at the end.
    func next() throws -> [Float]? {
        guard let sample = output.copyNextSampleBuffer() else {
            if reader.status == .failed {
                throw AudioEngineError.readerFailed(reader.error?.localizedDescription ?? "未知错误")
            }
            return nil
        }
        guard let block = CMSampleBufferGetDataBuffer(sample) else { return [] }
        let length = CMBlockBufferGetDataLength(block)
        var data = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
        let status = data.withUnsafeMutableBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return noErr }
            return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: raw.count, destination: base)
        }
        guard status == noErr else { throw AudioEngineError.readerFailed("OSStatus \(status)") }
        return data
    }

    func cancel() {
        if reader.status == .reading { reader.cancelReading() }
    }
}
