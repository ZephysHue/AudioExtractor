import AudioCore
import SwiftUI

struct EditorView: View {
    @EnvironmentObject private var app: AppModel
    @StateObject private var model: EditorModel
    @FocusState private var nameFocused: Bool

    init(source: ImportedSource, defaults: ExportOptions) {
        _model = StateObject(wrappedValue: EditorModel(source: source, defaults: defaults))
    }

    var body: some View {
        Group {
            if let error = model.loadError {
                EmptyStateView(systemImage: "exclamationmark.triangle", title: "无法打开", message: error)
            } else if !model.isLoaded {
                ProgressView("正在解析…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
        }
        .background(Theme.pageBackground)
        .navigationTitle("编辑")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .onDisappear { model.stopPreview() }
        .sheet(isPresented: Binding(get: { model.phase != .idle },
                                    set: { if !$0, model.phase != .exporting { model.phase = .idle } })) {
            ExportSheet(model: model)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { nameFocused = false }
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 14) {
                sourceCard
                trimCard
                effectsCard
                formatCard
                nameCard
            }
            .padding(16)
            .padding(.bottom, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { exportBar }
    }

    // MARK: Cards

    private var sourceCard: some View {
        Card {
            HStack(spacing: 12) {
                Image(systemName: model.info?.hasVideo == true ? "film" : "music.note")
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.source.displayName).font(.headline).lineLimit(1)
                    if let info = model.info {
                        Text("\(Formatting.time(info.duration)) · \(String(format: "%.1f", info.sampleRate / 1000)) kHz · \(info.channelCount == 1 ? "单声道" : "\(info.channelCount) 声道")\(info.hasVideo ? " · 视频" : "")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var trimCard: some View {
        Card(title: "选取片段") {
            WaveformTrimView(samples: model.waveform,
                             duration: model.duration,
                             start: model.start,
                             end: model.end,
                             playhead: model.playhead,
                             onStartChange: model.setStart,
                             onEndChange: model.setEnd,
                             onSeek: model.seek)
                .frame(height: 96)
                .overlay {
                    if model.waveform.isEmpty { ProgressView() }
                }
                .padding(.horizontal, 4)

            HStack(alignment: .top) {
                timeAdjuster(label: "起点", value: model.start, id: "start",
                             minus: { model.nudgeStart(-0.1) }, plus: { model.nudgeStart(0.1) })
                Spacer()
                VStack(spacing: 4) {
                    Text("已选").font(.caption).foregroundStyle(.secondary)
                    Text(Formatting.time(model.selectionLength, fraction: true))
                        .font(.headline.monospacedDigit())
                        .accessibilityIdentifier("selectionLength")
                }
                Spacer()
                timeAdjuster(label: "终点", value: model.end, id: "end",
                             minus: { model.nudgeEnd(-0.1) }, plus: { model.nudgeEnd(0.1) })
            }

            HStack(spacing: 10) {
                Button { model.markStartAtPlayhead() } label: {
                    Label("设为起点", systemImage: "arrow.right.to.line").font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                Spacer()
                Button { model.togglePlay() } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .frame(width: 54, height: 54)
                        .background(Theme.gradient, in: Circle())
                        .foregroundStyle(.white)
                }
                .accessibilityLabel(model.isPlaying ? "暂停试听" : "试听")
                .accessibilityIdentifier("previewButton")
                Spacer()
                Button { model.markEndAtPlayhead() } label: {
                    Label("设为终点", systemImage: "arrow.left.to.line").font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.small)

            HStack {
                Text("当前 \(Formatting.time(model.playhead, fraction: true))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Button("全选") { model.selectAll() }.font(.caption)
            }
        }
    }

    private func timeAdjuster(label: String, value: Double, id: String,
                              minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(Formatting.time(value, fraction: true)).font(.subheadline.monospacedDigit().weight(.semibold))
                .accessibilityIdentifier("\(id)Time")
            HStack(spacing: 6) {
                stepButton("minus", action: minus).accessibilityIdentifier("\(id)Minus")
                stepButton("plus", action: plus).accessibilityIdentifier("\(id)Plus")
            }
        }
    }

    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.caption.weight(.bold))
                .frame(width: 30, height: 26)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(icon == "minus" ? "减少 0.1 秒" : "增加 0.1 秒")
    }

    private var effectsCard: some View {
        Card(title: "效果") {
            sliderRow(title: "淡入", value: $model.options.fadeIn, range: 0...5, step: 0.5,
                      text: model.options.fadeIn == 0 ? "关" : String(format: "%.1f 秒", model.options.fadeIn))
            sliderRow(title: "淡出", value: $model.options.fadeOut, range: 0...5, step: 0.5,
                      text: model.options.fadeOut == 0 ? "关" : String(format: "%.1f 秒", model.options.fadeOut))
            let volume = Binding<Double>(get: { Double(model.options.volume) }, set: { model.options.volume = Float($0) })
            sliderRow(title: "音量", value: volume, range: 0...2, step: 0.05,
                      text: "\(Int((model.options.volume * 100).rounded()))%")
        }
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>,
                           step: Double, text: String) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.subheadline).frame(width: 36, alignment: .leading)
            Slider(value: value, in: range, step: step)
            Text(text).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 58, alignment: .trailing)
        }
    }

    private var formatCard: some View {
        Card(title: "输出格式") {
            ChipPicker(values: AudioFormat.allCases, selection: $model.options.format,
                       identifier: { "format_\($0.rawValue)" }) { format, _ in
                VStack(spacing: 2) {
                    Text(format.displayName).font(.subheadline.weight(.bold))
                    Text(format.subtitle).font(.system(size: 10))
                        .opacity(0.8)
                }
            }

            if model.options.format.supportsBitrate {
                VStack(alignment: .leading, spacing: 8) {
                    Text("码率").font(.subheadline).foregroundStyle(.secondary)
                    ChipPicker(values: Bitrates.all, selection: $model.options.bitrateKbps,
                               identifier: { "bitrate_\($0)" }) { kbps, _ in
                        Text("\(kbps)k").font(.subheadline.weight(.semibold).monospacedDigit())
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("采样率").font(.subheadline).foregroundStyle(.secondary)
                Picker("采样率", selection: $model.options.sampleRate) {
                    ForEach(SampleRateOption.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("声道").font(.subheadline).foregroundStyle(.secondary)
                Picker("声道", selection: $model.options.channels) {
                    ForEach(ChannelOption.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Text("输出：\(model.options.format.displayName) · \(model.resolvedSampleRate) Hz · \(model.resolvedChannels == 1 ? "单声道" : "立体声")\(model.options.format.supportsBitrate ? " · \(model.options.bitrateKbps) kbps" : "")")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var nameCard: some View {
        Card(title: "文件名") {
            HStack {
                TextField("文件名", text: $model.fileName)
                    .textFieldStyle(.plain)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .accessibilityIdentifier("fileNameField")
                Text(".\(model.options.format.fileExtension)").foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var exportBar: some View {
        Button {
            nameFocused = false
            model.export(into: app)
        } label: {
            VStack(spacing: 2) {
                Text("导出 \(model.options.format.displayName)").font(.headline)
                Text("\(Formatting.time(model.selectionLength)) · 预计 \(Formatting.fileSize(model.estimatedSize))")
                    .font(.caption).opacity(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundStyle(.white)
        }
        .disabled(model.selectionLength < EditorModel.minLength)
        .accessibilityIdentifier("exportButton")
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(.bar)
    }
}

// MARK: - Export progress / result

struct ExportSheet: View {
    @ObservedObject var model: EditorModel
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var player: PlayerService
    @State private var shareURL: URL?

    var body: some View {
        VStack(spacing: 18) {
            switch model.phase {
            case .idle, .exporting:
                ZStack {
                    Circle().stroke(Color(uiColor: .tertiarySystemFill), lineWidth: 10)
                    Circle().trim(from: 0, to: model.progress)
                        .stroke(Theme.gradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.15), value: model.progress)
                    Text("\(Int(model.progress * 100))%").font(.title2.weight(.bold).monospacedDigit())
                }
                .frame(width: 120, height: 120)
                .accessibilityIdentifier("exportProgress")
                Text("正在导出…").font(.headline)
                Button("取消", role: .cancel) { model.cancelExport() }
                    .buttonStyle(.bordered)

            case .done(let item):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("exportDone")
                VStack(spacing: 4) {
                    Text("导出完成").font(.title3.weight(.bold))
                    Text("\(item.fileName)").font(.subheadline).lineLimit(1)
                    Text("\(Formatting.time(item.duration)) · \(Formatting.fileSize(item.fileSize))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Button {
                        player.play(item, url: app.url(for: item))
                    } label: {
                        Label(player.current?.id == item.id && player.isPlaying ? "暂停" : "播放",
                              systemImage: player.current?.id == item.id && player.isPlaying ? "pause.fill" : "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button {
                        shareURL = app.url(for: item)
                    } label: {
                        Label("分享", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("shareButton")
                }
                .controlSize(.large)
                HStack(spacing: 12) {
                    Button("继续编辑") { model.phase = .idle }
                        .accessibilityIdentifier("continueEditing")
                    Spacer()
                    Button("去作品库") {
                        model.phase = .idle
                        app.selectedTab = .library
                    }
                    .accessibilityIdentifier("goToLibrary")
                }
                .font(.subheadline.weight(.medium))

            case .failed(let message):
                Image(systemName: "xmark.octagon.fill").font(.system(size: 56)).foregroundStyle(.red)
                Text("导出失败").font(.title3.weight(.bold))
                Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                HStack {
                    Button("关闭") { model.phase = .idle }.buttonStyle(.bordered)
                    Button("重试") { model.export(into: app) }.buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .presentationDetents([.medium])
        .interactiveDismissDisabled(model.phase == .exporting)
        .sheet(item: Binding(get: { shareURL.map(ShareItem.init) }, set: { shareURL = $0?.url })) { share in
            ShareSheet(items: [share.url])
        }
    }
}

struct ShareItem: Identifiable {
    let url: URL
    var id: URL { url }
}
