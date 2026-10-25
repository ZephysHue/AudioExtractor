import AudioCore
import AVFoundation
import Combine
import SwiftUI

/// Plays exported files from the library (one at a time).
@MainActor
final class PlayerService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var current: SavedAudio?
    @Published private(set) var isPlaying = false
    @Published var currentTime: Double = 0
    @Published private(set) var duration: Double = 0

    private var player: AVAudioPlayer?
    private var timer: AnyCancellable?

    static func configureSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    }

    func play(_ item: SavedAudio, url: URL) {
        if current?.id == item.id, player != nil {
            toggle()
            return
        }
        stop()
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.prepareToPlay()
            p.play()
            player = p
            current = item
            duration = p.duration
            isPlaying = true
            startTimer()
        } catch {
            current = nil
        }
    }

    func toggle() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func seek(to time: Double) {
        player?.currentTime = time
        currentTime = time
    }

    func stop() {
        player?.stop()
        player = nil
        current = nil
        isPlaying = false
        currentTime = 0
        timer = nil
    }

    /// Stop if the item being played was deleted / renamed.
    func itemRemoved(_ id: UUID) {
        if current?.id == id { stop() }
    }

    private func startTimer() {
        timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self, let p = self.player else { return }
            self.currentTime = p.currentTime
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTime = 0
        }
    }
}

/// Compact player shown above the tab bar while something is playing.
struct MiniPlayerBar: View {
    @EnvironmentObject private var player: PlayerService

    var body: some View {
        if let item = player.current {
            VStack(spacing: 6) {
                HStack(spacing: 12) {
                    FormatBadge(format: item.format)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text("\(Formatting.time(player.currentTime)) / \(Formatting.time(player.duration))")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { player.toggle() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title3)
                            .frame(width: 36, height: 36)
                    }
                    .accessibilityIdentifier("miniPlayerToggle")
                    Button { player.stop() } label: {
                        Image(systemName: "xmark").font(.subheadline.weight(.bold))
                            .frame(width: 30, height: 30)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("关闭播放器")
                }
                Slider(value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }),
                       in: 0...max(player.duration, 0.1))
                    .controlSize(.mini)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            .accessibilityIdentifier("miniPlayer")
        }
    }
}
