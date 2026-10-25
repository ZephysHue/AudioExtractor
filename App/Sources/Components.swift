import AudioCore
import SwiftUI
import UIKit

enum Theme {
    static let accent = Color("AccentColor")
    static let gradient = LinearGradient(colors: [Color(red: 0.42, green: 0.36, blue: 0.98),
                                                  Color(red: 0.13, green: 0.62, blue: 0.98)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let pageBackground = Color(uiColor: .systemGroupedBackground)

    static func color(for format: AudioFormat) -> Color {
        switch format {
        case .mp3: return .orange
        case .m4a: return .pink
        case .aac: return .purple
        case .wav: return .blue
        case .aiff: return .teal
        case .flac: return .green
        }
    }
}

struct FormatBadge: View {
    let format: AudioFormat
    var body: some View {
        Text(format.displayName)
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(Theme.color(for: format).gradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

struct Card<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title).font(.headline)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Horizontal row of selectable chips.
struct ChipPicker<Value: Hashable, Label: View>: View {
    let values: [Value]
    @Binding var selection: Value
    var identifier: (Value) -> String
    @ViewBuilder var label: (Value, Bool) -> Label

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(values, id: \.self) { value in
                    let selected = value == selection
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { selection = value }
                    } label: {
                        label(value, selected)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(selected ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color(uiColor: .tertiarySystemFill)),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(selected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(identifier(value))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }
}

/// UIKit share sheet (used for multi-option sharing incl. "Save to Files").
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// Empty-state placeholder (ContentUnavailableView is iOS 17+).
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Theme.gradient)
            Text(title).font(.title3.weight(.semibold))
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }
}

struct LoadingOverlay: View {
    let text: String
    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().controlSize(.large)
                Text(text).font(.subheadline.weight(.medium))
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .transition(.opacity)
    }
}
