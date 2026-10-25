import AudioCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @AppStorage(SettingsKey.format) private var format: AudioFormat = .mp3
    @AppStorage(SettingsKey.bitrate) private var bitrate: Int = 192
    @AppStorage(SettingsKey.sampleRate) private var sampleRate: SampleRateOption = .original
    @AppStorage(SettingsKey.channels) private var channels: ChannelOption = .original
    @State private var cacheSize: Int64 = 0

    private var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = info?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        Form {
            Section {
                Picker("格式", selection: $format) {
                    ForEach(AudioFormat.allCases) { Text("\($0.displayName) · \($0.subtitle)").tag($0) }
                }
                Picker("码率", selection: $bitrate) {
                    ForEach(Bitrates.all, id: \.self) { Text("\($0) kbps").tag($0) }
                }
                .disabled(!format.supportsBitrate)
                Picker("采样率", selection: $sampleRate) {
                    ForEach(SampleRateOption.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("声道", selection: $channels) {
                    ForEach(ChannelOption.allCases) { Text($0.displayName).tag($0) }
                }
            } header: {
                Text("默认导出设置")
            } footer: {
                Text("新打开的编辑页会使用这些设置，每次导出时仍可单独修改。")
            }

            Section("存储") {
                LabeledContent("作品数量", value: "\(app.items.count)")
                LabeledContent("作品占用", value: Formatting.fileSize(app.store.totalSize))
                Button("清除导入缓存（\(Formatting.fileSize(cacheSize))）") {
                    ImportService.clearCache()
                    cacheSize = ImportService.cacheSize()
                }
                .disabled(cacheSize == 0)
            }

            Section {
                Label("导出的文件保存在「文件」App › 我的 iPhone › 音频提取，可直接用电脑或其他 App 访问。", systemImage: "folder")
                Label("在其他 App 中分享视频时选择「音频提取」，即可直接打开编辑。", systemImage: "square.and.arrow.down")
                Label("所有处理都在本机完成，不会上传任何文件。", systemImage: "lock.shield")
            } header: {
                Text("小提示")
            }
            .font(.subheadline)

            Section("关于") {
                LabeledContent("版本", value: version)
                NavigationLink("开源许可") { LicensesView() }
            }
        }
        .navigationTitle("设置")
        .onAppear { cacheSize = ImportService.cacheSize() }
    }
}

struct LicensesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("LAME MP3 Encoder 3.99.5").font(.headline)
                Text("""
                本应用使用 LAME 进行 MP3 编码。LAME 以 GNU Lesser General Public License (LGPL) v2 或更高版本授权。
                LAME 源代码可在 https://lame.sourceforge.io 获取，本应用使用的源码随项目一同提供（Packages/AudioCore/Sources/CLame）。

                Copyright (c) 1999-2011 The LAME Project
                """)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("开源许可")
    }
}
