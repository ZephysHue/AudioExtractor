import AudioCore
import PhotosUI
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var player: PlayerService
    @State private var photoItem: PhotosPickerItem?
    @State private var showFileImporter = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                PhotosPicker(selection: $photoItem, matching: .videos, photoLibrary: .shared()) {
                    ActionCard(icon: "film.stack", title: "从相册提取",
                               subtitle: "选择视频，一键导出音频", prominent: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pickFromPhotos")

                Button { showFileImporter = true } label: {
                    ActionCard(icon: "folder", title: "从文件导入",
                               subtitle: "视频或音频文件 · 剪辑 / 格式转换", prominent: false)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pickFromFiles")

                featureGrid

                if !app.items.isEmpty { recent }
            }
            .padding(16)
        }
        .background(Theme.pageBackground)
        .navigationTitle("音频提取")
        .safeAreaInset(edge: .bottom) { MiniPlayerBar() }
        .onChange(of: photoItem) { item in
            guard let item else { return }
            loadPhoto(item)
        }
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: ImportService.importableTypes,
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { app.importFile(at: url) }
            case .failure(let error):
                app.alertMessage = error.localizedDescription
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("把视频里的声音带走")
                .font(.title2.weight(.bold))
            Text("提取 · 剪辑 · 淡入淡出 · 6 种格式，全程本地处理，不上传任何文件。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private var featureGrid: some View {
        let features: [(String, String)] = [
            ("scissors", "精准剪辑"),
            ("waveform.path", "波形预览"),
            ("dial.medium", "码率可调"),
            ("speaker.wave.2", "音量调节"),
            ("arrow.left.arrow.right", "格式互转"),
            ("square.and.arrow.up", "一键分享"),
        ]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(features.indices, id: \.self) { i in
                VStack(spacing: 8) {
                    Image(systemName: features[i].0).font(.title3).foregroundStyle(Theme.gradient)
                    Text(features[i].1).font(.caption.weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("最近导出").font(.headline)
                Spacer()
                Button("查看全部") { app.selectedTab = .library }
                    .font(.subheadline)
            }
            VStack(spacing: 0) {
                ForEach(app.items.prefix(3)) { item in
                    Button {
                        player.play(item, url: app.url(for: item))
                    } label: {
                        LibraryRow(item: item, isPlaying: player.current?.id == item.id && player.isPlaying)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    if item.id != app.items.prefix(3).last?.id {
                        Divider().padding(.leading, 70)
                    }
                }
            }
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) {
        app.isImporting = true
        Task {
            defer {
                app.isImporting = false
                photoItem = nil
            }
            do {
                guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                    app.alertMessage = "无法读取这个视频"
                    return
                }
                let name = movie.url.deletingPathExtension().lastPathComponent
                app.openEditor(with: ImportedSource(url: movie.url, displayName: name))
            } catch {
                app.alertMessage = "导入失败：\(error.localizedDescription)"
            }
        }
    }
}

private struct ActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let prominent: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .semibold))
                .frame(width: 56, height: 56)
                .background(prominent ? AnyShapeStyle(.white.opacity(0.22)) : AnyShapeStyle(Theme.gradient),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title3.weight(.bold))
                Text(subtitle).font(.subheadline).opacity(0.85)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.headline).opacity(0.6)
        }
        .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(18)
        .background(prominent ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.cardBackground),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(Rectangle())
    }
}
