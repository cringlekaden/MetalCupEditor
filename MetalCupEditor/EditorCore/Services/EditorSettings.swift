/// EditorSettings.swift
/// Defines the EditorSettings types and helpers for the editor.
/// Created by Kaden Cringle.

import Foundation

struct EditorSettingsDocument: Codable {
    var schemaVersion: Int
    var recentProjects: [String]
    var panelVisibility: [String: Bool]
    var headerStates: [String: Bool]
    var lastSelectedEntityId: String
    var lastContentBrowserPath: String

    init(schemaVersion: Int = 1,
         recentProjects: [String] = [],
         panelVisibility: [String: Bool] = [:],
         headerStates: [String: Bool] = [:],
         lastSelectedEntityId: String = "",
         lastContentBrowserPath: String = "") {
        self.schemaVersion = schemaVersion
        self.recentProjects = recentProjects
        self.panelVisibility = panelVisibility
        self.headerStates = headerStates
        self.lastSelectedEntityId = lastSelectedEntityId
        self.lastContentBrowserPath = lastContentBrowserPath
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case recentProjects
        case panelVisibility
        case headerStates
        case lastSelectedEntityId
        case lastContentBrowserPath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        recentProjects = try container.decodeIfPresent([String].self, forKey: .recentProjects) ?? []
        panelVisibility = try container.decodeIfPresent([String: Bool].self, forKey: .panelVisibility) ?? [:]
        headerStates = try container.decodeIfPresent([String: Bool].self, forKey: .headerStates) ?? [:]
        lastSelectedEntityId = try container.decodeIfPresent(String.self, forKey: .lastSelectedEntityId) ?? ""
        lastContentBrowserPath = try container.decodeIfPresent(String.self, forKey: .lastContentBrowserPath) ?? ""
    }
}

final class EditorSettingsStore {
    static let shared = EditorSettingsStore()
    private(set) var recentProjects: [String] = []
    private(set) var panelVisibility: [String: Bool] = [:]
    private(set) var headerStates: [String: Bool] = [:]
    private(set) var lastSelectedEntityId: String = ""
    private(set) var lastContentBrowserPath: String = ""

    private init() {}

    func load() {
        let url = settingsURL()
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: url),
           let document = try? decoder.decode(EditorSettingsDocument.self, from: data) {
            recentProjects = document.recentProjects
            panelVisibility = document.panelVisibility
            headerStates = document.headerStates
            lastSelectedEntityId = document.lastSelectedEntityId
            lastContentBrowserPath = document.lastContentBrowserPath
        }
    }

    func save() {
        let url = settingsURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let document = EditorSettingsDocument(
            recentProjects: recentProjects,
            panelVisibility: panelVisibility,
            headerStates: headerStates,
            lastSelectedEntityId: lastSelectedEntityId,
            lastContentBrowserPath: lastContentBrowserPath
        )
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

    func panelIsVisible(_ panelId: String, defaultValue: Bool) -> Bool {
        if let value = panelVisibility[panelId] {
            return value
        }
        return defaultValue
    }

    func setPanelVisible(_ panelId: String, visible: Bool) {
        panelVisibility[panelId] = visible
    }

    func headerIsOpen(_ headerId: String, defaultValue: Bool) -> Bool {
        if let value = headerStates[headerId] {
            return value
        }
        return defaultValue
    }

    func setHeaderOpen(_ headerId: String, open: Bool) {
        headerStates[headerId] = open
    }

    func setLastSelectedEntityId(_ entityId: String) {
        lastSelectedEntityId = entityId
    }

    func setLastContentBrowserPath(_ path: String) {
        lastContentBrowserPath = path
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
        EditorLogCenter.shared.logError(message, category: .editor)
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
