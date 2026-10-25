import AudioCore
import AVFoundation
import Foundation
import SwiftUI

/// A local copy of a picked video/audio file, ready to be edited.
struct ImportedSource: Identifiable, Hashable, Sendable {
    let id = UUID()
    let url: URL
    let displayName: String
}

enum AppTab: Hashable {
    case home, library, settings
}

enum SettingsKey {
    static let format = "default.format"
    static let bitrate = "default.bitrate"
    static let sampleRate = "default.sampleRate"
    static let channels = "default.channels"
}

@MainActor
final class AppModel: ObservableObject {
    let store: LibraryStore
    @Published private(set) var items: [SavedAudio] = []
    @Published var selectedTab: AppTab = .home
    @Published var homePath: [ImportedSource] = []
    @Published var isImporting = false
    @Published var alertMessage: String?

    init(directory: URL = LibraryStore.defaultDirectory()) {
        store = LibraryStore(directory: directory)
        items = store.items
    }

    // MARK: Library

    func refresh() {
        store.reconcile()
        items = store.items
    }

    @discardableResult
    func add(result: ExportResult, sourceName: String?) -> SavedAudio {
        let item = store.add(result: result, sourceName: sourceName)
        items = store.items
        return item
    }

    func rename(_ item: SavedAudio, to title: String) {
        do {
            try store.rename(item.id, to: title)
        } catch {
            alertMessage = error.localizedDescription
        }
        items = store.items
    }

    func delete(_ item: SavedAudio) {
        store.delete(item.id)
        items = store.items
    }

    func url(for item: SavedAudio) -> URL { store.url(for: item) }

    /// Durations of files adopted from the Files app are unknown until we inspect them.
    func fillMissingDurations() async {
        for item in items where item.duration <= 0 {
            if let info = try? await AudioEngine.inspect(url(for: item)) {
                store.updateDuration(item.id, duration: info.duration)
            }
        }
        items = store.items
    }

    // MARK: Defaults

    func defaultOptions() -> ExportOptions {
        let d = UserDefaults.standard
        var o = ExportOptions()
        if let f = d.string(forKey: SettingsKey.format).flatMap(AudioFormat.init(rawValue:)) { o.format = f }
        let br = d.integer(forKey: SettingsKey.bitrate)
        if Bitrates.all.contains(br) { o.bitrateKbps = br }
        if let sr = SampleRateOption(rawValue: d.integer(forKey: SettingsKey.sampleRate)) { o.sampleRate = sr }
        if let ch = ChannelOption(rawValue: d.integer(forKey: SettingsKey.channels)) { o.channels = ch }
        return o
    }

    // MARK: Import

    func openEditor(with source: ImportedSource) {
        selectedTab = .home
        homePath = [source]
    }

    /// Copy a (possibly security-scoped) file into our inbox and open the editor.
    func importFile(at url: URL) {
        isImporting = true
        Task {
            defer { isImporting = false }
            do {
                let source = try await ImportService.copyToInbox(url)
                openEditor(with: source)
            } catch {
                alertMessage = "导入失败：\(error.localizedDescription)"
            }
        }
    }

    /// Re-edit an item from the library (trim it again, convert to another format…).
    func reedit(_ item: SavedAudio) {
        importFile(at: url(for: item))
    }
}
