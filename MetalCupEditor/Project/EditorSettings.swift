import Foundation

struct EditorSettingsDocument: Codable {
    var schemaVersion: Int
    var recentProjects: [String]

    init(schemaVersion: Int = 1, recentProjects: [String] = []) {
        self.schemaVersion = schemaVersion
        self.recentProjects = recentProjects
    }
}

final class EditorSettingsStore {
    private(set) var recentProjects: [String] = []

    func load() {
        let url = settingsURL()
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: url),
           let document = try? decoder.decode(EditorSettingsDocument.self, from: data) {
            recentProjects = document.recentProjects
        }
    }

    func save() {
        let url = settingsURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let document = EditorSettingsDocument(recentProjects: recentProjects)
        if let data = try? encoder.encode(document) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: [.atomic])
        }
    }

    func addRecentProject(_ url: URL) {
        let path = url.standardizedFileURL.path
        recentProjects.removeAll { $0 == path }
        recentProjects.insert(path, at: 0)
        if recentProjects.count > 10 {
            recentProjects = Array(recentProjects.prefix(10))
        }
    }

    func replaceRecentProjects(_ paths: [String]) {
        recentProjects = paths
    }

    func removeRecentProject(at path: String) {
        recentProjects.removeAll { $0 == path }
    }

    private func settingsURL() -> URL {
        return EditorFileSystem.editorSettingsURL()
    }
}

final class EditorAlertCenter {
    static let shared = EditorAlertCenter()

    private var messages: [String] = []

    private init() {}

    func enqueueError(_ message: String) {
        messages.append(message)
    }

    func popNext() -> String? {
        if messages.isEmpty { return nil }
        return messages.removeFirst()
    }
}

@_cdecl("MCEEditorPopNextAlert")
public func MCEEditorPopNextAlert(_ buffer: UnsafeMutablePointer<CChar>?, _ bufferSize: Int32) -> UInt32 {
    guard let buffer, bufferSize > 0 else { return 0 }
    guard let message = EditorAlertCenter.shared.popNext() else { return 0 }
    return message.withCString { ptr in
        let length = min(Int(bufferSize - 1), strlen(ptr))
        if length > 0 {
            memcpy(buffer, ptr, length)
        }
        buffer[length] = 0
        return 1
    }
}
