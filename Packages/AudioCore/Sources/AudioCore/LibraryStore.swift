import Foundation

public struct LibraryItem: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var fileName: String
    public var format: AudioFormat
    public var duration: Double
    public var fileSize: Int64
    public var createdAt: Date
    public var sourceName: String?

    public init(id: UUID = UUID(), title: String, fileName: String, format: AudioFormat,
                duration: Double, fileSize: Int64, createdAt: Date = Date(), sourceName: String? = nil) {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.format = format
        self.duration = duration
        self.fileSize = fileSize
        self.createdAt = createdAt
        self.sourceName = sourceName
    }
}

public enum LibraryError: LocalizedError, Equatable {
    case notFound
    case invalidName

    public var errorDescription: String? {
        switch self {
        case .notFound: return "找不到这个文件"
        case .invalidName: return "名称不能为空"
        }
    }
}

/// Exported audio files plus a small JSON index, stored in one directory
/// (by default Documents/, so files are also visible in the Files app).
public final class LibraryStore {
    public let directory: URL
    private let indexURL: URL
    private let fm = FileManager.default
    public private(set) var items: [LibraryItem] = []

    public init(directory: URL) {
        self.directory = directory
        self.indexURL = directory.appendingPathComponent(".library.json")
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    public static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    public func url(for item: LibraryItem) -> URL {
        directory.appendingPathComponent(item.fileName)
    }

    // MARK: Persistence

    private func load() {
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? Self.decoder.decode([LibraryItem].self, from: data) {
            items = decoded
        }
        reconcile()
    }

    /// Drop entries whose file was deleted (e.g. from the Files app) and adopt
    /// audio files dropped into the folder by the user.
    public func reconcile() {
        let before = items
        items.removeAll { !fm.fileExists(atPath: url(for: $0).path) }
        let known = Set(items.map(\.fileName))
        let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey])) ?? []
        for file in files where !known.contains(file.lastPathComponent) {
            guard let format = AudioFormat(fileExtension: file.pathExtension) else { continue }
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
            items.append(LibraryItem(title: file.deletingPathExtension().lastPathComponent,
                                     fileName: file.lastPathComponent,
                                     format: format,
                                     duration: 0,
                                     fileSize: Int64(values?.fileSize ?? 0),
                                     createdAt: values?.creationDate ?? Date()))
        }
        sort()
        if items != before { save() }
    }

    private func save() {
        guard let data = try? Self.encoder.encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private func sort() {
        items.sort { $0.createdAt > $1.createdAt }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: Naming

    /// Removes characters that are illegal in file names and trims whitespace.
    public static func sanitize(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t")
        let cleaned = name.components(separatedBy: illegal).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let noLeadingDot = cleaned.drop(while: { $0 == "." })
        return String(noLeadingDot.prefix(120))
    }

    /// A destination in the library folder that doesn't collide with an existing file.
    public func uniqueURL(baseName: String, format: AudioFormat, excluding: URL? = nil) -> URL {
        var base = Self.sanitize(baseName)
        if base.isEmpty { base = "音频" }
        var candidate = directory.appendingPathComponent(base).appendingPathExtension(format.fileExtension)
        var n = 2
        while fm.fileExists(atPath: candidate.path), candidate.standardizedFileURL != excluding?.standardizedFileURL {
            candidate = directory.appendingPathComponent("\(base) (\(n))").appendingPathExtension(format.fileExtension)
            n += 1
        }
        return candidate
    }

    // MARK: Mutations

    /// Register a file that was already written into `directory` (e.g. by `AudioEngine.export`).
    @discardableResult
    public func add(result: ExportResult, title: String? = nil, sourceName: String? = nil) -> LibraryItem {
        let fileName = result.url.lastPathComponent
        items.removeAll { $0.fileName == fileName }
        let item = LibraryItem(title: title ?? result.url.deletingPathExtension().lastPathComponent,
                               fileName: fileName,
                               format: result.format,
                               duration: result.duration,
                               fileSize: result.fileSize,
                               sourceName: sourceName)
        items.append(item)
        sort()
        save()
        return item
    }

    /// Renames the item and the underlying file.
    @discardableResult
    public func rename(_ id: UUID, to newTitle: String) throws -> LibraryItem {
        guard let index = items.firstIndex(where: { $0.id == id }) else { throw LibraryError.notFound }
        let clean = Self.sanitize(newTitle)
        guard !clean.isEmpty else { throw LibraryError.invalidName }
        var item = items[index]
        let oldURL = url(for: item)
        let newURL = uniqueURL(baseName: clean, format: item.format, excluding: oldURL)
        if newURL.standardizedFileURL != oldURL.standardizedFileURL {
            try fm.moveItem(at: oldURL, to: newURL)
        }
        item.title = newURL.deletingPathExtension().lastPathComponent
        item.fileName = newURL.lastPathComponent
        items[index] = item
        save()
        return item
    }

    public func delete(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        try? fm.removeItem(at: url(for: items[index]))
        items.remove(at: index)
        save()
    }

    public func updateDuration(_ id: UUID, duration: Double) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].duration = duration
        save()
    }

    public var totalSize: Int64 { items.reduce(0) { $0 + $1.fileSize } }
}
