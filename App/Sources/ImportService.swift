import AVFoundation
import CoreTransferable
import Foundation
import UniformTypeIdentifiers

enum ImportService {
    static var inboxDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Inbox", isDirectory: true)
    }

    static let importableTypes: [UTType] = [.movie, .video, .audiovisualContent, .audio, .mpeg4Movie, .quickTimeMovie, .mp3, .wav, .aiff, .mpeg4Audio]

    /// A fresh, unique location in the inbox that keeps the original file name.
    static func makeInboxURL(fileName: String) throws -> URL {
        let dir = inboxDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = fileName.isEmpty ? "media.mov" : fileName
        return dir.appendingPathComponent(name)
    }

    /// Copies the file off the main thread. Handles security-scoped URLs from the document picker.
    static func copyToInbox(_ url: URL) async throws -> ImportedSource {
        try await Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let dest = try makeInboxURL(fileName: url.lastPathComponent)
            try FileManager.default.copyItem(at: url, to: dest)
            return ImportedSource(url: dest, displayName: url.deletingPathExtension().lastPathComponent)
        }.value
    }

    static func cacheSize() -> Int64 {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: inboxDirectory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in e {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    static func clearCache() {
        try? FileManager.default.removeItem(at: inboxDirectory)
    }
}

/// Lets PhotosPicker hand us a video file (copied into our inbox).
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dest = try ImportService.makeInboxURL(fileName: received.file.lastPathComponent)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedMovie(url: dest)
        }
    }
}

/// Used by the UI tests (launch argument `-uiTestingTone`): writes a 4 s stereo tone file.
enum UITestSupport {
    static var isUITesting: Bool { ProcessInfo.processInfo.arguments.contains("-uiTesting") }
    static var wantsTone: Bool { ProcessInfo.processInfo.arguments.contains("-uiTestingTone") }

    static func makeTone() throws -> ImportedSource {
        let url = try ImportService.makeInboxURL(fileName: "测试音频.wav")
        let sr = 44_100.0
        let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sr, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
        ])
        let frames = AVAudioFrameCount(sr * 4)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for c in 0..<2 {
            let p = buffer.floatChannelData![c]
            for i in 0..<Int(frames) {
                let env = Float(0.3 + 0.7 * abs(sin(Double(i) / sr * 1.5)))
                p[i] = 0.5 * env * Float(sin(2 * .pi * 440 * Double(i) / sr))
            }
        }
        try file.write(from: buffer)
        return ImportedSource(url: url, displayName: "测试音频")
    }

    /// Isolated library folder so UI tests never touch real data.
    static func testLibraryDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("UITestLibrary", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        return dir
    }
}
