import AudioCore
import SwiftUI

/// Waveform with two draggable trim handles and a playhead. Tap to seek.
struct WaveformTrimView: View {
    let samples: [Float]
    let duration: Double
    let start: Double
    let end: Double
    let playhead: Double
    var onStartChange: (Double) -> Void
    var onEndChange: (Double) -> Void
    var onSeek: (Double) -> Void

    private let handleWidth: CGFloat = 14
    private let space = "waveform"

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let xs = x(for: start, width: width)
            let xe = x(for: end, width: width)

            ZStack(alignment: .topLeading) {
                bars(width: width, height: height)
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .named(space)) { loc in
                        onSeek(time(at: loc.x, width: width))
                    }

                // Dim outside the selection
                Rectangle().fill(Color.black.opacity(0.18))
                    .frame(width: max(0, xs), height: height)
                    .allowsHitTesting(false)
                Rectangle().fill(Color.black.opacity(0.18))
                    .frame(width: max(0, width - xe), height: height)
                    .offset(x: xe)
                    .allowsHitTesting(false)

                // Selection frame
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Theme.accent, lineWidth: 2)
                    .frame(width: max(2, xe - xs), height: height)
                    .offset(x: xs)
                    .allowsHitTesting(false)

                // Playhead
                if duration > 0 {
                    Rectangle().fill(Color.white)
                        .frame(width: 2, height: height + 8)
                        .shadow(color: .black.opacity(0.4), radius: 1)
                        .offset(x: x(for: playhead, width: width) - 1, y: -4)
                        .allowsHitTesting(false)
                }

                handle(isStart: true)
                    .offset(x: xs - handleWidth / 2 - 8)
                    .gesture(drag(width: width, isStart: true))
                handle(isStart: false)
                    .offset(x: xe - handleWidth / 2 - 8)
                    .gesture(drag(width: width, isStart: false))
            }
            .coordinateSpace(name: space)
        }
    }

    private func bars(width: CGFloat, height: CGFloat) -> some View {
        Canvas { ctx, size in
            guard !samples.isEmpty else { return }
            let count = samples.count
            let step = size.width / CGFloat(count)
            let barWidth = max(1, step * 0.6)
            for (i, s) in samples.enumerated() {
                let x = CGFloat(i) * step + (step - barWidth) / 2
                let h = max(2, CGFloat(s) * size.height * 0.9)
                let rect = CGRect(x: x, y: (size.height - h) / 2, width: barWidth, height: h)
                let t = duration * Double(i) / Double(count)
                let inside = t >= start && t <= end
                ctx.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2),
                         with: .color(inside ? Theme.accent : Color.secondary.opacity(0.4)))
            }
        }
        .frame(width: width, height: height)
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
    }

    private func handle(isStart: Bool) -> some View {
        Capsule()
            .fill(Theme.accent)
            .overlay(
                VStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        Capsule().fill(.white).frame(width: 6, height: 2)
                    }
                }
            )
            .frame(width: handleWidth)
            .padding(.horizontal, 8) // larger touch target
            .contentShape(Rectangle())
            .accessibilityElement()
            .accessibilityLabel(isStart ? "起点" : "终点")
            .accessibilityValue(Formatting.time(isStart ? start : end, fraction: true))
            .accessibilityIdentifier(isStart ? "trimStartHandle" : "trimEndHandle")
            .accessibilityAdjustableAction { direction in
                let delta = direction == .increment ? 0.5 : -0.5
                if isStart { onStartChange(start + delta) } else { onEndChange(end + delta) }
            }
    }

    private func drag(width: CGFloat, isStart: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
            .onChanged { value in
                let t = time(at: value.location.x, width: width)
                if isStart { onStartChange(t) } else { onEndChange(t) }
            }
    }

    private func x(for t: Double, width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(min(max(t / duration, 0), 1)) * width
    }

    private func time(at x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(min(max(x / width, 0), 1)) * duration
    }
}
