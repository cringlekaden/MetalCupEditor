/// EditorSettings.swift
/// Defines the EditorSettings types and helpers for the editor.
/// Created by Kaden Cringle.

import Foundation
import MetalCupEngine

struct EditorSettingsDocument: Codable {
    var schemaVersion: Int
    var recentProjects: [String]
    var panelVisibility: [String: Bool]
    var headerStates: [String: Bool]
    var lastSelectedEntityId: String
    var lastContentBrowserPath: String
    var layerNames: [String]
    var viewportGizmoOperation: Int
    var viewportGizmoSpaceMode: Int
    var viewportSnapEnabled: Bool
    var themeMode: Int
    var themeAccentR: Float
    var themeAccentG: Float
    var themeAccentB: Float
    var themeUIScale: Float
    var themeRoundedUI: Bool
    var themeCornerRounding: Float
    var themeSpacingPreset: Int
    var viewportShowWorldIcons: Bool
    var viewportWorldIconBaseSize: Float
    var viewportWorldIconDistanceScale: Float
    var viewportWorldIconMinSize: Float
    var viewportWorldIconMaxSize: Float
    var viewportShowSelectedCameraFrustum: Bool
    var viewportPreviewEnabled: Bool
    var viewportPreviewSize: Float
    var viewportPreviewPosition: Int
    var editorDebugGridEnabled: Bool
    var editorDebugOutlineEnabled: Bool
    var editorDebugPhysicsEnabled: Bool

    init(schemaVersion: Int = 1,
         recentProjects: [String] = [],
         panelVisibility: [String: Bool] = [:],
         headerStates: [String: Bool] = [:],
         lastSelectedEntityId: String = "",
         lastContentBrowserPath: String = "",
         layerNames: [String] = LayerCatalog.defaultNames(),
         viewportGizmoOperation: Int = 1,
         viewportGizmoSpaceMode: Int = 0,
         viewportSnapEnabled: Bool = false,
         themeMode: Int = 0,
         themeAccentR: Float = 0.18,
         themeAccentG: Float = 0.58,
         themeAccentB: Float = 0.84,
         themeUIScale: Float = 1.0,
         themeRoundedUI: Bool = true,
         themeCornerRounding: Float = 6.0,
         themeSpacingPreset: Int = 1,
         viewportShowWorldIcons: Bool = true,
         viewportWorldIconBaseSize: Float = 18.0,
         viewportWorldIconDistanceScale: Float = 0.75,
         viewportWorldIconMinSize: Float = 11.0,
         viewportWorldIconMaxSize: Float = 28.0,
         viewportShowSelectedCameraFrustum: Bool = true,
         viewportPreviewEnabled: Bool = true,
         viewportPreviewSize: Float = 0.28,
         viewportPreviewPosition: Int = 3,
         editorDebugGridEnabled: Bool = true,
         editorDebugOutlineEnabled: Bool = true,
         editorDebugPhysicsEnabled: Bool = false) {
        self.schemaVersion = schemaVersion
        self.recentProjects = recentProjects
        self.panelVisibility = panelVisibility
        self.headerStates = headerStates
        self.lastSelectedEntityId = lastSelectedEntityId
        self.lastContentBrowserPath = lastContentBrowserPath
        self.layerNames = LayerCatalog.normalizedNames(layerNames)
        self.viewportGizmoOperation = viewportGizmoOperation
        self.viewportGizmoSpaceMode = viewportGizmoSpaceMode
        self.viewportSnapEnabled = viewportSnapEnabled
        self.themeMode = themeMode
        self.themeAccentR = themeAccentR
        self.themeAccentG = themeAccentG
        self.themeAccentB = themeAccentB
        self.themeUIScale = themeUIScale
        self.themeRoundedUI = themeRoundedUI
        self.themeCornerRounding = themeCornerRounding
        self.themeSpacingPreset = themeSpacingPreset
        self.viewportShowWorldIcons = viewportShowWorldIcons
        self.viewportWorldIconBaseSize = viewportWorldIconBaseSize
        self.viewportWorldIconDistanceScale = viewportWorldIconDistanceScale
        self.viewportWorldIconMinSize = viewportWorldIconMinSize
        self.viewportWorldIconMaxSize = viewportWorldIconMaxSize
        self.viewportShowSelectedCameraFrustum = viewportShowSelectedCameraFrustum
        self.viewportPreviewEnabled = viewportPreviewEnabled
        self.viewportPreviewSize = viewportPreviewSize
        self.viewportPreviewPosition = viewportPreviewPosition
        self.editorDebugGridEnabled = editorDebugGridEnabled
        self.editorDebugOutlineEnabled = editorDebugOutlineEnabled
        self.editorDebugPhysicsEnabled = editorDebugPhysicsEnabled
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case recentProjects
        case panelVisibility
        case headerStates
        case lastSelectedEntityId
        case lastContentBrowserPath
        case layerNames
        case viewportGizmoOperation
        case viewportGizmoSpaceMode
        case viewportSnapEnabled
        case themeMode
        case themeAccentR
        case themeAccentG
        case themeAccentB
        case themeUIScale
        case themeRoundedUI
        case themeCornerRounding
        case themeSpacingPreset
        case viewportShowWorldIcons
        case viewportWorldIconBaseSize
        case viewportWorldIconDistanceScale
        case viewportWorldIconMinSize
        case viewportWorldIconMaxSize
        case viewportShowSelectedCameraFrustum
        case viewportPreviewEnabled
        case viewportPreviewSize
        case viewportPreviewPosition
        case editorDebugGridEnabled
        case editorDebugOutlineEnabled
        case editorDebugPhysicsEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        recentProjects = try container.decodeIfPresent([String].self, forKey: .recentProjects) ?? []
        panelVisibility = try container.decodeIfPresent([String: Bool].self, forKey: .panelVisibility) ?? [:]
        headerStates = try container.decodeIfPresent([String: Bool].self, forKey: .headerStates) ?? [:]
        lastSelectedEntityId = try container.decodeIfPresent(String.self, forKey: .lastSelectedEntityId) ?? ""
        lastContentBrowserPath = try container.decodeIfPresent(String.self, forKey: .lastContentBrowserPath) ?? ""
        let decodedNames = try container.decodeIfPresent([String].self, forKey: .layerNames) ?? LayerCatalog.defaultNames()
        layerNames = LayerCatalog.normalizedNames(decodedNames)
        viewportGizmoOperation = try container.decodeIfPresent(Int.self, forKey: .viewportGizmoOperation) ?? 1
        viewportGizmoSpaceMode = try container.decodeIfPresent(Int.self, forKey: .viewportGizmoSpaceMode) ?? 0
        viewportSnapEnabled = try container.decodeIfPresent(Bool.self, forKey: .viewportSnapEnabled) ?? false
        themeMode = try container.decodeIfPresent(Int.self, forKey: .themeMode) ?? 0
        themeAccentR = try container.decodeIfPresent(Float.self, forKey: .themeAccentR) ?? 0.18
        themeAccentG = try container.decodeIfPresent(Float.self, forKey: .themeAccentG) ?? 0.58
        themeAccentB = try container.decodeIfPresent(Float.self, forKey: .themeAccentB) ?? 0.84
        themeUIScale = try container.decodeIfPresent(Float.self, forKey: .themeUIScale) ?? 1.0
        themeRoundedUI = try container.decodeIfPresent(Bool.self, forKey: .themeRoundedUI) ?? true
        themeCornerRounding = try container.decodeIfPresent(Float.self, forKey: .themeCornerRounding) ?? 6.0
        themeSpacingPreset = try container.decodeIfPresent(Int.self, forKey: .themeSpacingPreset) ?? 1
        viewportShowWorldIcons = try container.decodeIfPresent(Bool.self, forKey: .viewportShowWorldIcons) ?? true
        viewportWorldIconBaseSize = try container.decodeIfPresent(Float.self, forKey: .viewportWorldIconBaseSize) ?? 18.0
        viewportWorldIconDistanceScale = try container.decodeIfPresent(Float.self, forKey: .viewportWorldIconDistanceScale) ?? 0.75
        viewportWorldIconMinSize = try container.decodeIfPresent(Float.self, forKey: .viewportWorldIconMinSize) ?? 11.0
        viewportWorldIconMaxSize = try container.decodeIfPresent(Float.self, forKey: .viewportWorldIconMaxSize) ?? 28.0
        viewportShowSelectedCameraFrustum = try container.decodeIfPresent(Bool.self, forKey: .viewportShowSelectedCameraFrustum) ?? true
        viewportPreviewEnabled = try container.decodeIfPresent(Bool.self, forKey: .viewportPreviewEnabled) ?? true
        viewportPreviewSize = try container.decodeIfPresent(Float.self, forKey: .viewportPreviewSize) ?? 0.28
        viewportPreviewPosition = try container.decodeIfPresent(Int.self, forKey: .viewportPreviewPosition) ?? 3
        editorDebugGridEnabled = try container.decodeIfPresent(Bool.self, forKey: .editorDebugGridEnabled) ?? true
        editorDebugOutlineEnabled = try container.decodeIfPresent(Bool.self, forKey: .editorDebugOutlineEnabled) ?? true
        editorDebugPhysicsEnabled = try container.decodeIfPresent(Bool.self, forKey: .editorDebugPhysicsEnabled) ?? false
    }
}

final class EditorSettingsStore {
    private(set) var recentProjects: [String] = []
    private(set) var panelVisibility: [String: Bool] = [:]
    private(set) var headerStates: [String: Bool] = [:]
    private(set) var lastSelectedEntityId: String = ""
    private(set) var lastContentBrowserPath: String = ""
    private(set) var layerNames: [String] = LayerCatalog.defaultNames()
    private(set) var viewportGizmoOperation: Int = 1
    private(set) var viewportGizmoSpaceMode: Int = 0
    private(set) var viewportSnapEnabled: Bool = false
    private(set) var themeMode: Int = 0
    private(set) var themeAccentR: Float = 0.18
    private(set) var themeAccentG: Float = 0.58
    private(set) var themeAccentB: Float = 0.84
    private(set) var themeUIScale: Float = 1.0
    private(set) var themeRoundedUI: Bool = true
    private(set) var themeCornerRounding: Float = 6.0
    private(set) var themeSpacingPreset: Int = 1
    private(set) var viewportShowWorldIcons: Bool = true
    private(set) var viewportWorldIconBaseSize: Float = 18.0
    private(set) var viewportWorldIconDistanceScale: Float = 0.75
    private(set) var viewportWorldIconMinSize: Float = 11.0
    private(set) var viewportWorldIconMaxSize: Float = 28.0
    private(set) var viewportShowSelectedCameraFrustum: Bool = true
    private(set) var viewportPreviewEnabled: Bool = true
    private(set) var viewportPreviewSize: Float = 0.28
    private(set) var viewportPreviewPosition: Int = 3
    private(set) var editorDebugGridEnabled: Bool = true
    private(set) var editorDebugOutlineEnabled: Bool = true
    private(set) var editorDebugPhysicsEnabled: Bool = false

    init() {}

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
            layerNames = document.layerNames
            viewportGizmoOperation = document.viewportGizmoOperation
            viewportGizmoSpaceMode = document.viewportGizmoSpaceMode
            viewportSnapEnabled = document.viewportSnapEnabled
            themeMode = document.themeMode
            themeAccentR = document.themeAccentR
            themeAccentG = document.themeAccentG
            themeAccentB = document.themeAccentB
            themeUIScale = document.themeUIScale
            themeRoundedUI = document.themeRoundedUI
            themeCornerRounding = document.themeCornerRounding
            themeSpacingPreset = document.themeSpacingPreset
            viewportShowWorldIcons = document.viewportShowWorldIcons
            viewportWorldIconBaseSize = document.viewportWorldIconBaseSize
            viewportWorldIconDistanceScale = document.viewportWorldIconDistanceScale
            viewportWorldIconMinSize = document.viewportWorldIconMinSize
            viewportWorldIconMaxSize = document.viewportWorldIconMaxSize
            viewportShowSelectedCameraFrustum = document.viewportShowSelectedCameraFrustum
            viewportPreviewEnabled = document.viewportPreviewEnabled
            viewportPreviewSize = document.viewportPreviewSize
            viewportPreviewPosition = document.viewportPreviewPosition
            editorDebugGridEnabled = document.editorDebugGridEnabled
            editorDebugOutlineEnabled = document.editorDebugOutlineEnabled
            editorDebugPhysicsEnabled = document.editorDebugPhysicsEnabled
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
            lastContentBrowserPath: lastContentBrowserPath,
            layerNames: layerNames,
            viewportGizmoOperation: viewportGizmoOperation,
            viewportGizmoSpaceMode: viewportGizmoSpaceMode,
            viewportSnapEnabled: viewportSnapEnabled,
            themeMode: themeMode,
            themeAccentR: themeAccentR,
            themeAccentG: themeAccentG,
            themeAccentB: themeAccentB,
            themeUIScale: themeUIScale,
            themeRoundedUI: themeRoundedUI,
            themeCornerRounding: themeCornerRounding,
            themeSpacingPreset: themeSpacingPreset,
            viewportShowWorldIcons: viewportShowWorldIcons,
            viewportWorldIconBaseSize: viewportWorldIconBaseSize,
            viewportWorldIconDistanceScale: viewportWorldIconDistanceScale,
            viewportWorldIconMinSize: viewportWorldIconMinSize,
            viewportWorldIconMaxSize: viewportWorldIconMaxSize,
            viewportShowSelectedCameraFrustum: viewportShowSelectedCameraFrustum,
            viewportPreviewEnabled: viewportPreviewEnabled,
            viewportPreviewSize: viewportPreviewSize,
            viewportPreviewPosition: viewportPreviewPosition,
            editorDebugGridEnabled: editorDebugGridEnabled,
            editorDebugOutlineEnabled: editorDebugOutlineEnabled,
            editorDebugPhysicsEnabled: editorDebugPhysicsEnabled
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

    func setLayerNames(_ names: [String]) {
        layerNames = LayerCatalog.normalizedNames(names)
    }

    func setViewportGizmoOperation(_ value: Int) {
        viewportGizmoOperation = value
    }

    func setViewportGizmoSpaceMode(_ value: Int) {
        viewportGizmoSpaceMode = value
    }

    func setViewportSnapEnabled(_ value: Bool) {
        viewportSnapEnabled = value
    }

    func setThemeMode(_ value: Int) { themeMode = value }
    func setThemeAccent(r: Float, g: Float, b: Float) {
        themeAccentR = r
        themeAccentG = g
        themeAccentB = b
    }
    func setThemeUIScale(_ value: Float) { themeUIScale = value }
    func setThemeRoundedUI(_ value: Bool) { themeRoundedUI = value }
    func setThemeCornerRounding(_ value: Float) { themeCornerRounding = value }
    func setThemeSpacingPreset(_ value: Int) { themeSpacingPreset = value }
    func setViewportShowWorldIcons(_ value: Bool) { viewportShowWorldIcons = value }
    func setViewportWorldIconBaseSize(_ value: Float) { viewportWorldIconBaseSize = value }
    func setViewportWorldIconDistanceScale(_ value: Float) { viewportWorldIconDistanceScale = value }
    func setViewportWorldIconMinSize(_ value: Float) { viewportWorldIconMinSize = value }
    func setViewportWorldIconMaxSize(_ value: Float) { viewportWorldIconMaxSize = value }
    func setViewportShowSelectedCameraFrustum(_ value: Bool) { viewportShowSelectedCameraFrustum = value }
    func setViewportPreviewEnabled(_ value: Bool) { viewportPreviewEnabled = value }
    func setViewportPreviewSize(_ value: Float) { viewportPreviewSize = value }
    func setViewportPreviewPosition(_ value: Int) { viewportPreviewPosition = value }
    func setEditorDebugGridEnabled(_ value: Bool) { editorDebugGridEnabled = value }
    func setEditorDebugOutlineEnabled(_ value: Bool) { editorDebugOutlineEnabled = value }
    func setEditorDebugPhysicsEnabled(_ value: Bool) { editorDebugPhysicsEnabled = value }

    private func settingsURL() -> URL {
        return EditorFileSystem.editorSettingsURL()
    }
}

final class EditorAlertCenter {
    private var messages: [String] = []
    private let logCenter: EngineLogger

    init(logCenter: EngineLogger) {
        self.logCenter = logCenter
    }

    func enqueueError(_ message: String) {
        messages.append(message)
        logCenter.logError(message, category: .editor)
    }

    func popNext() -> String? {
        if messages.isEmpty { return nil }
        return messages.removeFirst()
    }
}

@_cdecl("MCEEditorPopNextAlert")
public func MCEEditorPopNextAlert(_ contextPtr: UnsafeMutableRawPointer,
                                  _ buffer: UnsafeMutablePointer<CChar>?,
                                  _ bufferSize: Int32) -> UInt32 {
    guard let buffer, bufferSize > 0 else { return 0 }
    let context = Unmanaged<MCEContext>.fromOpaque(contextPtr).takeUnretainedValue()
    guard let message = context.editorAlertCenter.popNext() else { return 0 }
    return message.withCString { ptr in
        let length = min(Int(bufferSize - 1), strlen(ptr))
        if length > 0 {
            memcpy(buffer, ptr, length)
        }
        buffer[length] = 0
        return 1
    }
}
