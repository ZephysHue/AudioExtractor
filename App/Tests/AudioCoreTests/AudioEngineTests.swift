import AVFoundation
import XCTest
@testable import AudioCore

final class AudioEngineTests: XCTestCase {
    private var outDir: URL!

    override func setUpWithError() throws {
        outDir = FileManager.default.temporaryDirectory.appendingPathComponent("AudioEngineTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: outDir)
    }

    private func fixture(_ name: String) throws -> URL {
        let parts = name.split(separator: ".")
        let url = Bundle(for: Self.self).url(forResource: String(parts[0]), withExtension: String(parts[1]))
        return try XCTUnwrap(url, "missing fixture \(name)")
    }

    private func out(_ name: String) -> URL { outDir.appendingPathComponent(name) }

    /// Reads a whole file as interleaved-free channel 0 float samples.
    private func readSamples(_ url: URL) throws -> (samples: [Float], sampleRate: Double, channels: Int) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let ch0 = buffer.floatChannelData![0]
        return (Array(UnsafeBufferPointer(start: ch0, count: Int(buffer.frameLength))), format.sampleRate, Int(format.channelCount))
    }

    private func rms(_ s: ArraySlice<Float>) -> Float {
        guard !s.isEmpty else { return 0 }
        return (s.reduce(0) { $0 + $1 * $1 } / Float(s.count)).squareRoot()
    }

    // MARK: Inspect

    func testInspectVideo() async throws {
        let info = try await AudioEngine.inspect(try fixture("sample_video.mp4"))
        XCTAssertEqual(info.duration, 3, accuracy: 0.1)
        XCTAssertTrue(info.hasVideo)
        XCTAssertEqual(info.channelCount, 2)
        XCTAssertEqual(info.sampleRate, 48_000, accuracy: 1)
    }

    func testInspectVideoWithoutAudioThrows() async throws {
        do {
            _ = try await AudioEngine.inspect(try fixture("video_no_audio.mp4"))
            XCTFail("expected noAudioTrack")
        } catch let e as AudioEngineError {
            XCTAssertEqual(e, .noAudioTrack)
        }
    }

    // MARK: Export every format

    func testExportEveryFormatFromVideo() async throws {
        let src = try fixture("sample_video.mp4")
        for format in AudioFormat.allCases {
            let dest = out("all.\(format.fileExtension)")
            let result = try await AudioEngine.export(source: src, to: dest,
                                                      options: ExportOptions(format: format, bitrateKbps: 192))
            XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path), "\(format)")
            XCTAssertGreaterThan(result.fileSize, 1_000, "\(format)")
            XCTAssertEqual(result.duration, 3, accuracy: 0.1, "\(format)")
            let info = try await AudioEngine.inspect(dest)
            XCTAssertFalse(info.hasVideo, "\(format)")
            XCTAssertEqual(info.duration, 3, accuracy: 0.2, "\(format) re-read duration")
            XCTAssertEqual(info.channelCount, 2, "\(format)")
        }
    }

    func testMP3BitrateAffectsSize() async throws {
        let src = try fixture("sample_video.mp4")
        let low = try await AudioEngine.export(source: src, to: out("low.mp3"), options: ExportOptions(format: .mp3, bitrateKbps: 64))
        let high = try await AudioEngine.export(source: src, to: out("high.mp3"), options: ExportOptions(format: .mp3, bitrateKbps: 320))
        XCTAssertGreaterThan(high.fileSize, low.fileSize * 3)
        // CBR: size ≈ bitrate * duration / 8
        XCTAssertEqual(Double(high.fileSize), 320_000 / 8 * 3, accuracy: 320_000 / 8 * 0.5)
    }

    func testMonoAndSampleRateConversion() async throws {
        let src = try fixture("sample_video.mp4")
        let opts = ExportOptions(format: .mp3, bitrateKbps: 96, sampleRate: .hz22050, channels: .mono)
        let r = try await AudioEngine.export(source: src, to: out("mono.mp3"), options: opts)
        XCTAssertEqual(r.channels, 1)
        XCTAssertEqual(r.sampleRate, 22_050)
        let info = try await AudioEngine.inspect(r.url)
        XCTAssertEqual(info.channelCount, 1)
        XCTAssertEqual(info.sampleRate, 22_050, accuracy: 1)
    }

    func testMonoSourceToStereoWav() async throws {
        let r = try await AudioEngine.export(source: try fixture("mono_tone.mp3"), to: out("st.wav"),
                                             options: ExportOptions(format: .wav, channels: .stereo))
        let info = try await AudioEngine.inspect(r.url)
        XCTAssertEqual(info.channelCount, 2)
        XCTAssertEqual(info.duration, 2, accuracy: 0.15)
    }

    func testHighSampleRateIsCappedForLossy() async throws {
        let src = try fixture("hires_96k.wav")
        let mp3 = try await AudioEngine.export(source: src, to: out("hi.mp3"), options: ExportOptions(format: .mp3))
        XCTAssertEqual(mp3.sampleRate, 48_000)
        let m4a = try await AudioEngine.export(source: src, to: out("hi.m4a"), options: ExportOptions(format: .m4a, bitrateKbps: 320))
        XCTAssertEqual(m4a.sampleRate, 48_000)
        let wav = try await AudioEngine.export(source: src, to: out("hi.wav"), options: ExportOptions(format: .wav))
        XCTAssertEqual(wav.sampleRate, 96_000, "lossless keeps original rate")
    }

    func testAACMonoHighBitrateFallsBack() async throws {
        // 320 kbps mono AAC is rejected by the encoder; the sink must step down instead of failing.
        let r = try await AudioEngine.export(source: try fixture("mono_tone.mp3"), to: out("m.m4a"),
                                             options: ExportOptions(format: .m4a, bitrateKbps: 320, channels: .mono))
        XCTAssertGreaterThan(r.fileSize, 1_000)
    }

    // MARK: Trim / effects

    func testTrimRange() async throws {
        let src = try fixture("sample_video.mp4")
        let r = try await AudioEngine.export(source: src, to: out("trim.m4a"),
                                             options: ExportOptions(format: .m4a, trimStart: 1.0, trimEnd: 2.2))
        XCTAssertEqual(r.duration, 1.2, accuracy: 0.05)
        let info = try await AudioEngine.inspect(r.url)
        XCTAssertEqual(info.duration, 1.2, accuracy: 0.1)
    }

    func testTrimEndBeyondDurationIsClamped() async throws {
        let r = try await AudioEngine.export(source: try fixture("sample_video.mp4"), to: out("c.wav"),
                                             options: ExportOptions(format: .wav, trimStart: 2.5, trimEnd: 99))
        XCTAssertEqual(r.duration, 0.5, accuracy: 0.05)
    }

    func testEmptySelectionThrows() async throws {
        do {
            _ = try await AudioEngine.export(source: try fixture("sample_video.mp4"), to: out("e.mp3"),
                                             options: ExportOptions(trimStart: 1, trimEnd: 1.01))
            XCTFail("expected emptySelection")
        } catch let e as AudioEngineError {
            XCTAssertEqual(e, .emptySelection)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: out("e.mp3").path))
    }

    func testFadeInAndOut() async throws {
        let r = try await AudioEngine.export(source: try fixture("sample_video.mp4"), to: out("fade.wav"),
                                             options: ExportOptions(format: .wav, fadeIn: 1, fadeOut: 1))
        let (s, sr, _) = try readSamples(r.url)
        let n = Int(sr * 0.02)
        let head = rms(s[0..<n])
        let mid = rms(s[Int(sr * 1.5)..<Int(sr * 1.5) + n])
        let tail = rms(s[(s.count - n)..<s.count])
        XCTAssertLessThan(head, 0.05)
        XCTAssertLessThan(tail, 0.05)
        XCTAssertGreaterThan(mid, 0.2)
    }

    func testVolumeZeroIsSilent() async throws {
        let r = try await AudioEngine.export(source: try fixture("sample_video.mp4"), to: out("mute.wav"),
                                             options: ExportOptions(format: .wav, volume: 0))
        let (s, _, _) = try readSamples(r.url)
        XCTAssertEqual(s.map(abs).max() ?? 1, 0, accuracy: 0.0001)
    }

    func testVolumeBoostIncreasesLevelAndClips() async throws {
        let src = try fixture("sample_video.mp4")
        let normal = try await AudioEngine.export(source: src, to: out("n.wav"), options: ExportOptions(format: .wav))
        let loud = try await AudioEngine.export(source: src, to: out("l.wav"), options: ExportOptions(format: .wav, volume: 2))
        let a = try readSamples(normal.url).samples, b = try readSamples(loud.url).samples
        XCTAssertGreaterThan(rms(b[...]), rms(a[...]) * 1.5)
        XCTAssertLessThanOrEqual(b.map(abs).max() ?? 2, 1.0)
    }

    func testCancellationRemovesPartialFile() async throws {
        let src = try fixture("sample_video.mp4")
        let dest = out("cancel.wav")
        let task = Task { try await AudioEngine.export(source: src, to: dest, options: ExportOptions(format: .wav)) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch {
            // CancellationError from the encode loop, or an NSError if AVFoundation noticed first.
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path))
    }

    func testProgressReachesOne() async throws {
        let box = ProgressBox()
        _ = try await AudioEngine.export(source: try fixture("sample_video.mp4"), to: out("p.mp3"),
                                         options: ExportOptions()) { box.append($0) }
        let values = box.values
        XCTAssertFalse(values.isEmpty)
        XCTAssertEqual(values.last ?? 0, 1, accuracy: 0.0001)
        XCTAssertEqual(values, values.sorted(), "progress must be monotonic")
    }

    func testOverwritesExistingDestination() async throws {
        let dest = out("o.mp3")
        try Data(repeating: 7, count: 10).write(to: dest)
        let r = try await AudioEngine.export(source: try fixture("sample_video.mp4"), to: dest, options: ExportOptions())
        XCTAssertGreaterThan(r.fileSize, 10_000)
    }

    // MARK: Waveform

    func testWaveform() async throws {
        let peaks = try await AudioEngine.waveform(for: try fixture("sample_video.mp4"), bins: 100)
        XCTAssertEqual(peaks.count, 100)
        XCTAssertEqual(peaks.max() ?? 0, 1, accuracy: 0.0001)
        XCTAssertGreaterThan(peaks.filter { $0 > 0.5 }.count, 80, "constant sine should be flat")
    }
}

final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Double] = []
    func append(_ v: Double) { lock.lock(); storage.append(v); lock.unlock() }
    var values: [Double] { lock.lock(); defer { lock.unlock() }; return storage }
}
