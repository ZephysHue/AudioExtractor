import AVFoundation
import CLame
import Foundation

/// Receives interleaved Float32 PCM and encodes it to a file.
protocol AudioSink: AnyObject {
    func write(_ samples: UnsafeBufferPointer<Float>, frames: Int) throws
    func finish() throws
    func abort()
}

// MARK: - Core Audio formats (M4A / AAC / WAV / AIFF / FLAC)

final class AVAudioFileSink: AudioSink {
    private var file: AVAudioFile?
    private let channels: Int

    init(url: URL, format: AudioFormat, sampleRate: Int, channels: Int, bitrateKbps: Int) throws {
        self.channels = channels
        var lastError: Error?
        // AAC encoders reject some bitrate/rate/channel combinations; step down until one is accepted.
        let candidates = format.supportsBitrate
            ? [bitrateKbps] + Bitrates.all.filter { $0 < bitrateKbps }.reversed()
            : [0]
        for kbps in candidates {
            do {
                let settings = Self.settings(format: format, sampleRate: sampleRate, channels: channels, bitrateKbps: kbps)
                file = try AVAudioFile(forWriting: url, settings: settings,
                                       commonFormat: .pcmFormatFloat32, interleaved: true)
                break
            } catch {
                lastError = error
                try? FileManager.default.removeItem(at: url)
            }
        }
        guard file != nil else {
            throw AudioEngineError.encoderFailed(lastError?.localizedDescription ?? format.displayName)
        }
    }

    static func settings(format: AudioFormat, sampleRate: Int, channels: Int, bitrateKbps: Int) -> [String: Any] {
        var s: [String: Any] = [
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
        ]
        switch format {
        case .m4a, .aac:
            s[AVFormatIDKey] = kAudioFormatMPEG4AAC
            s[AVEncoderBitRateKey] = bitrateKbps * 1000
            s[AVEncoderAudioQualityKey] = AVAudioQuality.high.rawValue
        case .wav, .aiff:
            s[AVFormatIDKey] = kAudioFormatLinearPCM
            s[AVLinearPCMBitDepthKey] = 16
            s[AVLinearPCMIsFloatKey] = false
            s[AVLinearPCMIsBigEndianKey] = format == .aiff
            s[AVLinearPCMIsNonInterleaved] = false
        case .flac:
            s[AVFormatIDKey] = kAudioFormatFLAC
            s[AVEncoderBitDepthHintKey] = 16
        case .mp3:
            preconditionFailure("MP3 is encoded by MP3Sink")
        }
        return s
    }

    func write(_ samples: UnsafeBufferPointer<Float>, frames: Int) throws {
        guard let file, frames > 0, let base = samples.baseAddress else { return }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(frames)) else {
            throw AudioEngineError.encoderFailed("无法分配缓冲区")
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        let abl = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        guard let dst = abl[0].mData else { throw AudioEngineError.encoderFailed("缓冲区为空") }
        let bytes = frames * channels * MemoryLayout<Float>.size
        dst.copyMemory(from: base, byteCount: min(bytes, Int(abl[0].mDataByteSize)))
        do {
            try file.write(from: buffer)
        } catch {
            throw AudioEngineError.encoderFailed(error.localizedDescription)
        }
    }

    func finish() throws {
        // Releasing the AVAudioFile flushes the encoder and closes the file.
        file = nil
    }

    func abort() { file = nil }
}

// MARK: - MP3 via LAME

final class MP3Sink: AudioSink {
    private var lame: OpaquePointer?
    private let handle: FileHandle
    private let channels: Int
    private var left = [Float]()
    private var right = [Float]()
    private var mp3Buffer = [UInt8]()

    init(url: URL, sampleRate: Int, channels: Int, bitrateKbps: Int) throws {
        guard let l = lame_init() else { throw AudioEngineError.encoderFailed("LAME 初始化失败") }
        lame_set_in_samplerate(l, Int32(sampleRate))
        lame_set_out_samplerate(l, Int32(sampleRate))
        lame_set_num_channels(l, Int32(channels))
        lame_set_mode(l, channels == 1 ? MONO : JOINT_STEREO)
        lame_set_VBR(l, vbr_off)
        lame_set_brate(l, Int32(bitrateKbps))
        lame_set_quality(l, 2)
        lame_set_write_id3tag_automatic(l, 0)
        guard lame_init_params(l) >= 0 else {
            lame_close(l)
            throw AudioEngineError.encoderFailed("不支持的 MP3 参数 (\(sampleRate) Hz, \(bitrateKbps) kbps)")
        }
        guard FileManager.default.createFile(atPath: url.path, contents: nil),
              let h = try? FileHandle(forWritingTo: url) else {
            lame_close(l)
            throw AudioEngineError.encoderFailed("无法创建文件")
        }
        lame = l
        handle = h
        self.channels = channels
    }

    deinit {
        if let lame { lame_close(lame) }
        try? handle.close()
    }

    func write(_ samples: UnsafeBufferPointer<Float>, frames: Int) throws {
        guard let lame, frames > 0 else { return }
        if left.count < frames {
            left = [Float](repeating: 0, count: frames)
            right = [Float](repeating: 0, count: frames)
        }
        for f in 0..<frames {
            if channels == 1 {
                left[f] = samples[f]
            } else {
                left[f] = samples[f * channels]
                right[f] = samples[f * channels + 1]
            }
        }
        let needed = frames * 5 / 4 + 7200
        if mp3Buffer.count < needed { mp3Buffer = [UInt8](repeating: 0, count: needed) }
        let capacity = Int32(mp3Buffer.count)
        let n = left.withUnsafeBufferPointer { l in
            right.withUnsafeBufferPointer { r in
                mp3Buffer.withUnsafeMutableBufferPointer { out in
                    lame_encode_buffer_ieee_float(lame, l.baseAddress, r.baseAddress, Int32(frames),
                                                  out.baseAddress, capacity)
                }
            }
        }
        guard n >= 0 else { throw AudioEngineError.encoderFailed("LAME 错误码 \(n)") }
        if n > 0 { try handle.write(contentsOf: mp3Buffer[0..<Int(n)]) }
    }

    func finish() throws {
        guard let lame else { return }
        if mp3Buffer.count < 7200 { mp3Buffer = [UInt8](repeating: 0, count: 7200) }
        let capacity = Int32(mp3Buffer.count)
        let n = mp3Buffer.withUnsafeMutableBufferPointer { lame_encode_flush(lame, $0.baseAddress, capacity) }
        if n > 0 { try handle.write(contentsOf: mp3Buffer[0..<Int(n)]) }
        lame_close(lame)
        self.lame = nil
        try handle.close()
    }

    func abort() {
        if let lame { lame_close(lame) }
        lame = nil
        try? handle.close()
    }
}
