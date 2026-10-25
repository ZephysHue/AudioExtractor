import AudioCore
import AVFoundation
import SwiftUI

@MainActor
final class EditorModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case exporting
        case done(SavedAudio)
        case failed(String)
    }

    static let minLength = 0.2
    static let waveformBins = 160

    let source: ImportedSource

    @Published private(set) var info: SourceInfo?
    @Published private(set) var loadError: String?
    @Published private(set) var waveform: [Float] = []

    @Published var options: ExportOptions
    @Published var start: Double = 0
    @Published var end: Double = 0
    @Published var fileName: String

    @Published private(set) var playhead: Double = 0
    @Published private(set) var isPlaying = false

    @Published var phase: Phase = .idle
    @Published private(set) var progress: Double = 0

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var exportTask: Task<Void, Never>?

    init(source: ImportedSource, defaults: ExportOptions) {
        self.source = source
        self.options = defaults
        self.fileName = source.displayName
    }

    var duration: Double { info?.duration ?? 0 }
    var selectionLength: Double { max(0, end - start) }
    var isLoaded: Bool { info != nil }

    var resolvedSampleRate: Int { options.resolvedSampleRate(source: info?.sampleRate ?? 44_100) }
    var resolvedChannels: Int { options.resolvedChannels(source: info?.channelCount ?? 2) }

    var estimatedSize: Int64 {
        Formatting.estimatedSize(duration: selectionLength, format: options.format,
                                 bitrateKbps: options.bitrateKbps,
                                 sampleRate: resolvedSampleRate, channels: resolvedChannels)
    }

    // MARK: Loading

    func load() async {
        guard info == nil, loadError == nil else { return }
        do {
            let i = try await AudioEngine.inspect(source.url)
            info = i
            start = 0
            end = i.duration
            setupPlayer()
            waveform = try await AudioEngine.waveform(for: source.url, bins: Self.waveformBins)
        } catch {
            if info == nil { loadError = error.localizedDescription }
        }
    }

    // MARK: Trim

    func setStart(_ t: Double) {
        start = min(max(0, t), max(0, end - Self.minLength))
        if playhead < start { seek(start) }
    }

    func setEnd(_ t: Double) {
        end = max(min(duration, t), min(duration, start + Self.minLength))
        if playhead > end { seek(start) }
    }

    func nudgeStart(_ delta: Double) { setStart(start + delta) }
    func nudgeEnd(_ delta: Double) { setEnd(end + delta) }

    func selectAll() {
        start = 0
        end = duration
    }

    /// Set start/end to the current playhead position (common "mark in / out" UX).
    func markStartAtPlayhead() { setStart(playhead) }
    func markEndAtPlayhead() { setEnd(playhead) }

    // MARK: Preview playback

    private func setupPlayer() {
        let p = AVPlayer(url: source.url)
        p.actionAtItemEnd = .pause
        timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            Task { @MainActor in self?.tick(time.seconds) }
        }
        player = p
    }

    private func tick(_ t: Double) {
        guard isPlaying, t.isFinite else { return }
        playhead = t
        if t >= end - 0.01 {
            player?.pause()
            isPlaying = false
            playhead = start
        }
    }

    func togglePlay() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            return
        }
        if playhead < start || playhead >= end - 0.05 { playhead = start }
        try? AVAudioSession.sharedInstance().setActive(true)
        player.seek(to: CMTime(seconds: playhead, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        player.volume = min(1, options.volume)
        player.play()
        isPlaying = true
    }

    func seek(_ t: Double) {
        playhead = min(max(0, t), duration)
        player?.seek(to: CMTime(seconds: playhead, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func stopPreview() {
        player?.pause()
        isPlaying = false
    }

    func tearDown() {
        stopPreview()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player = nil
    }

    // MARK: Export

    func export(into app: AppModel) {
        guard phase != .exporting else { return }
        stopPreview()
        var opts = options
        opts.trimStart = start
        opts.trimEnd = end
        let name = fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? source.displayName : fileName
        let dest = app.store.uniqueURL(baseName: name, format: opts.format)
        let src = source
        progress = 0
        phase = .exporting
        exportTask = Task {
            do {
                let result = try await AudioEngine.export(source: src.url, to: dest, options: opts) { [weak self] p in
                    Task { @MainActor in self?.progress = p }
                }
                progress = 1
                let item = app.add(result: result, sourceName: src.displayName)
                phase = .done(item)
            } catch is CancellationError {
                phase = .idle
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func cancelExport() {
        exportTask?.cancel()
    }
}
