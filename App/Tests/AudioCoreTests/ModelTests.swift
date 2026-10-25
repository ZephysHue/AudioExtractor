import XCTest
@testable import AudioCore

final class ExportOptionsTests: XCTestCase {
    func testResolvedSampleRate() {
        XCTAssertEqual(ExportOptions(format: .wav).resolvedSampleRate(source: 96_000), 96_000)
        XCTAssertEqual(ExportOptions(format: .mp3).resolvedSampleRate(source: 96_000), 48_000)
        XCTAssertEqual(ExportOptions(format: .m4a).resolvedSampleRate(source: 44_100), 44_100)
        XCTAssertEqual(ExportOptions(format: .mp3, sampleRate: .hz22050).resolvedSampleRate(source: 48_000), 22_050)
        // Odd rates are snapped for lossy codecs.
        XCTAssertEqual(ExportOptions(format: .mp3).resolvedSampleRate(source: 44_000), 44_100)
        XCTAssertEqual(ExportOptions(format: .mp3).resolvedSampleRate(source: 0), 44_100)
    }

    func testResolvedChannels() {
        XCTAssertEqual(ExportOptions(channels: .original).resolvedChannels(source: 6), 2)
        XCTAssertEqual(ExportOptions(channels: .original).resolvedChannels(source: 1), 1)
        XCTAssertEqual(ExportOptions(channels: .mono).resolvedChannels(source: 2), 1)
        XCTAssertEqual(ExportOptions(channels: .stereo).resolvedChannels(source: 1), 2)
    }

    func testResolvedRange() {
        XCTAssertEqual(ExportOptions().resolvedRange(duration: 10), 0...10)
        XCTAssertEqual(ExportOptions(trimStart: -3, trimEnd: 50).resolvedRange(duration: 10), 0...10)
        XCTAssertEqual(ExportOptions(trimStart: 8, trimEnd: 2).resolvedRange(duration: 10), 8...8)
        XCTAssertEqual(ExportOptions(trimStart: 2, trimEnd: 4).resolvedRange(duration: 10), 2...4)
    }

    func testFormatExtensionsRoundTrip() {
        for f in AudioFormat.allCases {
            XCTAssertEqual(AudioFormat(fileExtension: f.fileExtension), f)
        }
        XCTAssertEqual(AudioFormat(fileExtension: "AIFF"), .aiff)
        XCTAssertNil(AudioFormat(fileExtension: "mov"))
    }

    func testCodableRoundTrip() throws {
        let o = ExportOptions(format: .flac, bitrateKbps: 320, sampleRate: .hz48000, channels: .mono,
                              trimStart: 1, trimEnd: 2, fadeIn: 0.5, fadeOut: 1, volume: 1.5)
        let decoded = try JSONDecoder().decode(ExportOptions.self, from: JSONEncoder().encode(o))
        XCTAssertEqual(decoded, o)
    }
}

final class GainProcessorTests: XCTestCase {
    func testIdentityLeavesSamplesUntouched() {
        let p = GainProcessor(options: ExportOptions(), length: 1, sampleRate: 100, channels: 2)
        XCTAssertTrue(p.isIdentity)
        var s: [Float] = [0.5, -0.5, 0.25, -0.25]
        p.apply(&s, frames: 2, startFrame: 0)
        XCTAssertEqual(s, [0.5, -0.5, 0.25, -0.25])
    }

    func testFadeCurve() {
        let p = GainProcessor(options: ExportOptions(fadeIn: 0.1, fadeOut: 0.1), length: 1, sampleRate: 100, channels: 1)
        XCTAssertEqual(p.gain(at: 0), 0)
        XCTAssertEqual(p.gain(at: 5), 0.5, accuracy: 0.001)
        XCTAssertEqual(p.gain(at: 50), 1)
        XCTAssertEqual(p.gain(at: 95), 0.5, accuracy: 0.001)
        XCTAssertEqual(p.gain(at: 100), 0)
    }

    func testOverlongFadesAreScaled() {
        let p = GainProcessor(options: ExportOptions(fadeIn: 3, fadeOut: 1), length: 2, sampleRate: 100, channels: 1)
        XCTAssertEqual(p.fadeInFrames + p.fadeOutFrames, 200)
        XCTAssertEqual(p.fadeInFrames, 150)
    }

    func testVolumeClipsToUnitRange() {
        let p = GainProcessor(options: ExportOptions(volume: 2), length: 1, sampleRate: 10, channels: 1)
        var s: [Float] = [0.8, -0.8, 0.2]
        p.apply(&s, frames: 3, startFrame: 0)
        XCTAssertEqual(s, [1, -1, 0.4])
    }
}

final class FormattingTests: XCTestCase {
    func testTime() {
        XCTAssertEqual(Formatting.time(0), "00:00")
        XCTAssertEqual(Formatting.time(75.4), "01:15")
        XCTAssertEqual(Formatting.time(3725), "1:02:05")
        XCTAssertEqual(Formatting.time(75.44, fraction: true), "01:15.4")
        XCTAssertEqual(Formatting.time(59.96, fraction: true), "01:00.0")
        XCTAssertEqual(Formatting.time(.nan), "00:00")
        XCTAssertEqual(Formatting.time(-1, fraction: true), "00:00.0")
    }

    func testEstimatedSize() {
        XCTAssertEqual(Formatting.estimatedSize(duration: 10, format: .mp3, bitrateKbps: 128, sampleRate: 44_100, channels: 2), 160_000)
        XCTAssertEqual(Formatting.estimatedSize(duration: 1, format: .wav, bitrateKbps: 0, sampleRate: 44_100, channels: 2), 176_400)
    }
}

final class LibraryStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("LibraryStoreTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeFile(_ store: LibraryStore, name: String, format: AudioFormat = .mp3) throws -> ExportResult {
        let url = store.uniqueURL(baseName: name, format: format)
        try Data(repeating: 1, count: 1234).write(to: url)
        return ExportResult(url: url, duration: 3, fileSize: 1234, format: format, sampleRate: 44_100, channels: 2)
    }

    func testSanitize() {
        XCTAssertEqual(LibraryStore.sanitize("  a/b:c  "), "a_b_c")
        XCTAssertEqual(LibraryStore.sanitize("..hidden"), "hidden")
        XCTAssertEqual(LibraryStore.sanitize("我的 音频"), "我的 音频")
        XCTAssertEqual(LibraryStore.sanitize(String(repeating: "x", count: 300)).count, 120)
    }

    func testAddPersistsAcrossInstances() throws {
        let store = LibraryStore(directory: dir)
        let item = store.add(result: try makeFile(store, name: "歌曲"), sourceName: "IMG_0001")
        XCTAssertEqual(item.title, "歌曲")
        let reopened = LibraryStore(directory: dir)
        XCTAssertEqual(reopened.items, [item])
    }

    func testUniqueNames() throws {
        let store = LibraryStore(directory: dir)
        _ = store.add(result: try makeFile(store, name: "a"))
        let second = store.add(result: try makeFile(store, name: "a"))
        XCTAssertEqual(second.fileName, "a (2).mp3")
        XCTAssertEqual(store.items.count, 2)
    }

    func testRenameMovesFile() throws {
        let store = LibraryStore(directory: dir)
        let item = store.add(result: try makeFile(store, name: "old"))
        let renamed = try store.rename(item.id, to: "新名字")
        XCTAssertEqual(renamed.fileName, "新名字.mp3")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: renamed).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("old.mp3").path))
        // Renaming to the same name is a no-op, not "(2)".
        XCTAssertEqual(try store.rename(item.id, to: "新名字").fileName, "新名字.mp3")
        XCTAssertThrowsError(try store.rename(item.id, to: "   "))
    }

    func testDeleteRemovesFile() throws {
        let store = LibraryStore(directory: dir)
        let item = store.add(result: try makeFile(store, name: "x"))
        store.delete(item.id)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(for: item).path))
    }

    func testReconcileAdoptsAndDrops() throws {
        let store = LibraryStore(directory: dir)
        let item = store.add(result: try makeFile(store, name: "keep"))
        try FileManager.default.removeItem(at: store.url(for: item))
        try Data(count: 10).write(to: dir.appendingPathComponent("dropped-in.wav"))
        try Data(count: 10).write(to: dir.appendingPathComponent("notes.txt"))
        store.reconcile()
        XCTAssertEqual(store.items.map(\.fileName), ["dropped-in.wav"])
        XCTAssertEqual(store.items.first?.format, .wav)
    }

    func testItemsSortedNewestFirst() throws {
        let store = LibraryStore(directory: dir)
        _ = store.add(result: try makeFile(store, name: "first"))
        Thread.sleep(forTimeInterval: 0.01)
        _ = store.add(result: try makeFile(store, name: "second"))
        XCTAssertEqual(store.items.first?.title, "second")
    }
}
