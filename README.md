# 音频提取 AudioExtractor (iOS)

从视频中提取音频，支持剪辑、淡入淡出、音量调节和 6 种格式导出的 iOS App（SwiftUI，iOS 16+）。

## 功能
- **提取**：从相册（PhotosPicker，无需相册权限）或「文件」导入视频/音频；也可在其他 App 里「用音频提取打开」
- **剪辑**：波形预览、拖动起止手柄、±0.1 秒微调、按播放位置设为起点/终点、试听选区
- **效果**：淡入 / 淡出（0–5 秒）、音量 0–200%
- **格式**：MP3（LAME）、M4A、AAC、WAV、AIFF、FLAC；码率 64–320 kbps、采样率、单/立体声
- **作品库**：播放（迷你播放器）、搜索、按格式筛选、重命名、删除、分享 / 存储到文件、再次编辑
- 导出文件同时出现在「文件」App › 我的 iPhone › 音频提取；全部本地处理

## 构建
需要 macOS + Xcode（含 iOS 模拟器）。

```bash
scripts/build.sh test   # 生成工程并在模拟器跑单元测试 + UI 测试
scripts/build.sh ipa    # 输出未签名 build/AudioExtractor-unsigned.ipa
scripts/build.sh        # 两者都做
```
脚本会自动下载 XcodeGen 生成 `AudioExtractor.xcodeproj`。GitHub Actions（`.github/workflows/ios.yml`）用同一脚本在 macOS runner 上测试并把 IPA 作为 artifact 上传。

未签名 IPA 需用你自己的证书重签后安装（Bundle ID 默认 `com.soren.audioextractor`，可在 `project.yml` 修改）。

## 结构
- `Packages/AudioCore` — 引擎：AVAssetReader 解码 → 增益/淡入淡出 → AVAudioFile / LAME 编码；波形；作品库存储
- `App/Sources` — SwiftUI 界面
- `App/Tests` — 引擎单元测试（含测试素材）与 UI 测试

## 许可
MP3 编码使用 LAME 3.99.5（LGPL），源码位于 `Packages/AudioCore/Sources/CLame`。
