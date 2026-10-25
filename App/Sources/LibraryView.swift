import AudioCore
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var player: PlayerService
    @State private var query = ""
    @State private var renaming: LibraryItem?
    @State private var newName = ""
    @State private var shareURL: URL?
    @State private var filter: AudioFormat?

    private var filtered: [LibraryItem] {
        app.items.filter { item in
            (filter == nil || item.format == filter) &&
            (query.isEmpty || item.title.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        Group {
            if app.items.isEmpty {
                EmptyStateView(systemImage: "music.note.list", title: "还没有作品",
                               message: "在「提取」页选择视频，导出的音频会出现在这里。\n也可以在「文件」App › 我的 iPhone › 音频提取 中找到它们。")
                    .frame(maxHeight: .infinity)
            } else {
                list
            }
        }
        .background(Theme.pageBackground)
        .navigationTitle("作品库")
        .safeAreaInset(edge: .bottom) { MiniPlayerBar() }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Picker("格式", selection: $filter) {
                        Text("全部格式").tag(AudioFormat?.none)
                        ForEach(AudioFormat.allCases) { Text($0.displayName).tag(AudioFormat?.some($0)) }
                    }
                } label: {
                    Image(systemName: filter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityLabel("筛选")
            }
        }
        .refreshable { app.refresh() }
        .alert("重命名", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("名称", text: $newName)
                .accessibilityIdentifier("renameField")
            Button("取消", role: .cancel) { renaming = nil }
            Button("保存") {
                if let item = renaming {
                    player.itemRemoved(item.id)
                    app.rename(item, to: newName)
                }
                renaming = nil
            }
            .accessibilityIdentifier("renameSave")
        }
        .sheet(item: Binding(get: { shareURL.map(ShareItem.init) }, set: { shareURL = $0?.url })) { share in
            ShareSheet(items: [share.url])
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(filtered) { item in
                    Button {
                        player.play(item, url: app.url(for: item))
                    } label: {
                        LibraryRow(item: item, isPlaying: player.current?.id == item.id && player.isPlaying)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("libraryRow")
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { delete(item) } label: { Label("删除", systemImage: "trash") }
                        Button { startRename(item) } label: { Label("重命名", systemImage: "pencil") }
                            .tint(.orange)
                    }
                    .swipeActions(edge: .leading) {
                        Button { shareURL = app.url(for: item) } label: { Label("分享", systemImage: "square.and.arrow.up") }
                            .tint(.blue)
                    }
                    .contextMenu {
                        Button { player.play(item, url: app.url(for: item)) } label: { Label("播放", systemImage: "play") }
                        Button { shareURL = app.url(for: item) } label: { Label("分享 / 存储到文件", systemImage: "square.and.arrow.up") }
                        Button { startRename(item) } label: { Label("重命名", systemImage: "pencil") }
                        Button { app.reedit(item) } label: { Label("再次编辑 / 转换格式", systemImage: "scissors") }
                        Divider()
                        Button(role: .destructive) { delete(item) } label: { Label("删除", systemImage: "trash") }
                    }
                }
            } footer: {
                Text("共 \(app.items.count) 个 · \(Formatting.fileSize(app.store.totalSize))  ·  左滑删除/重命名，长按更多操作")
            }
        }
        .searchable(text: $query, prompt: "搜索作品")
    }

    private func startRename(_ item: LibraryItem) {
        newName = item.title
        renaming = item
    }

    private func delete(_ item: LibraryItem) {
        player.itemRemoved(item.id)
        app.delete(item)
    }
}

struct LibraryRow: View {
    let item: LibraryItem
    var isPlaying: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                FormatBadge(format: item.format)
                if isPlaying {
                    RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.black.opacity(0.35))
                        .frame(width: 44, height: 44)
                    Image(systemName: "speaker.wave.2.fill").foregroundStyle(.white)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.body.weight(.medium)).lineLimit(1)
                Text("\(item.duration > 0 ? Formatting.time(item.duration) : "--:--") · \(Formatting.fileSize(item.fileSize)) · \(item.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
