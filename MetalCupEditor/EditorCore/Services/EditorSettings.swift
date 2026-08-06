/// EditorSettings.swift
/// Defines the EditorSettings types and helpers for the editor.
/// Created by Kaden Cringle.

import Foundation
import MetalCupEngine

enum ViewportDebugVisualizationCategory: Int32, CaseIterable {
    case worldIcons = 0
    case cameraFrustums = 1
    case reflectionProbeInfluence = 2
    case reflectionProbeBlendShell = 3
    case reflectionProbeLinks = 4
    case physics = 5
    case genericLines = 6
    case genericShapes = 7
}

struct ViewportDebugStyle: Codable {
    var enabled: Bool
    var colorR: Float
    var colorG: Float
    var colorB: Float
    var opacity: Float
    var thickness: Float

    init(enabled: Bool = true,
         colorR: Float = 1.0,
         colorG: Float = 1.0,
         colorB: Float = 1.0,
         opacity: Float = 1.0,
         thickness: Float = 0.03) {
        self.enabled = enabled
        self.colorR = colorR
        self.colorG = colorG
        self.colorB = colorB
        self.opacity = opacity
        self.thickness = thickness
    }
}

struct ViewportWorldIconSettings: Codable {
    var enabled: Bool
    var baseSize: Float
    var distanceScale: Float
    var minSize: Float
    var maxSize: Float
    var opacity: Float

    init(enabled: Bool = true,
         baseSize: Float = 18.0,
         distanceScale: Float = 0.75,
         minSize: Float = 11.0,
         maxSize: Float = 28.0,
         opacity: Float = 1.0) {
        self.enabled = enabled
        self.baseSize = baseSize
        self.distanceScale = distanceScale
        self.minSize = minSize
        self.maxSize = maxSize
        self.opacity = opacity
    }
}

struct ViewportProbeBlendShellSettings: Codable {
    var style: ViewportDebugStyle
    var showInnerBox: Bool
    var showOuterBox: Bool
    var showConnectorLines: Bool

    init(style: ViewportDebugStyle = ViewportDebugStyle(
            enabled: true,
            colorR: 0.25,
            colorG: 0.95,
            colorB: 0.95,
            opacity: 0.55,
            thickness: 0.03
         ),
         showInnerBox: Bool = true,
         showOuterBox: Bool = true,
         showConnectorLines: Bool = true) {
        self.style = style
        self.showInnerBox = showInnerBox
        self.showOuterBox = showOuterBox
        self.showConnectorLines = showConnectorLines
    }
}

struct ViewportDebugVisualizationSettings: Codable {
    var worldIcons: ViewportWorldIconSettings
    var cameraFrustums: ViewportDebugStyle
    var reflectionProbeInfluence: ViewportDebugStyle
    var reflectionProbeBlendShell: ViewportProbeBlendShellSettings
    var reflectionProbeLinks: ViewportDebugStyle
    var physics: ViewportDebugStyle
    var genericLines: ViewportDebugStyle
    var genericShapes: ViewportDebugStyle

    init(worldIcons: ViewportWorldIconSettings = ViewportWorldIconSettings(),
         cameraFrustums: ViewportDebugStyle = ViewportDebugStyle(
            enabled: true,
            colorR: 1.0,
            colorG: 0.78,
            colorB: 0.25,
            opacity: 0.95,
            thickness: 0.03
         ),
         reflectionProbeInfluence: ViewportDebugStyle = ViewportDebugStyle(
            enabled: true,
            colorR: 0.25,
            colorG: 0.95,
            colorB: 0.95,
            opacity: 0.95,
            thickness: 0.04
         ),
         reflectionProbeBlendShell: ViewportProbeBlendShellSettings = ViewportProbeBlendShellSettings(),
         reflectionProbeLinks: ViewportDebugStyle = ViewportDebugStyle(
            enabled: true,
            colorR: 1.0,
            colorG: 0.72,
            colorB: 0.22,
            opacity: 0.95,
            thickness: 0.03
         ),
         physics: ViewportDebugStyle = ViewportDebugStyle(
            enabled: false,
            colorR: 0.9,
            colorG: 0.95,
            colorB: 0.3,
            opacity: 0.95,
            thickness: 0.03
         ),
         genericLines: ViewportDebugStyle = ViewportDebugStyle(
            enabled: true,
            colorR: 0.95,
            colorG: 0.95,
            colorB: 1.0,
            opacity: 0.95,
            thickness: 0.03
         ),
         genericShapes: ViewportDebugStyle = ViewportDebugStyle(
            enabled: true,
            colorR: 0.8,
            colorG: 0.9,
            colorB: 1.0,
            opacity: 0.9,
            thickness: 0.03
         )) {
        self.worldIcons = worldIcons
        self.cameraFrustums = cameraFrustums
        self.reflectionProbeInfluence = reflectionProbeInfluence
        self.reflectionProbeBlendShell = reflectionProbeBlendShell
        self.reflectionProbeLinks = reflectionProbeLinks
        self.physics = physics
        self.genericLines = genericLines
        self.genericShapes = genericShapes
    }

    func style(for category: ViewportDebugVisualizationCategory) -> ViewportDebugStyle {
        switch category {
        case .worldIcons:
            return ViewportDebugStyle(
                enabled: worldIcons.enabled,
                colorR: 1.0,
                colorG: 1.0,
                colorB: 1.0,
                opacity: worldIcons.opacity,
                thickness: 0.0
            )
        case .cameraFrustums:
            return cameraFrustums
        case .reflectionProbeInfluence:
            return reflectionProbeInfluence
        case .reflectionProbeBlendShell:
            return reflectionProbeBlendShell.style
        case .reflectionProbeLinks:
            return reflectionProbeLinks
        case .physics:
            return physics
        case .genericLines:
            return genericLines
        case .genericShapes:
            return genericShapes
        }
    }

    mutating func setStyle(_ style: ViewportDebugStyle, for category: ViewportDebugVisualizationCategory) {
        switch category {
        case .worldIcons:
            worldIcons.enabled = style.enabled
            worldIcons.opacity = style.opacity
        case .cameraFrustums:
            cameraFrustums = style
        case .reflectionProbeInfluence:
            reflectionProbeInfluence = style
        case .reflectionProbeBlendShell:
            reflectionProbeBlendShell.style = style
        case .reflectionProbeLinks:
            reflectionProbeLinks = style
        case .physics:
            physics = style
        case .genericLines:
            genericLines = style
        case .genericShapes:
            genericShapes = style
        }
    }

    static func migrated(worldIconsEnabled: Bool,
                         worldIconBaseSize: Float,
                         worldIconDistanceScale: Float,
                         worldIconMinSize: Float,
                         worldIconMaxSize: Float,
                         cameraFrustumEnabled: Bool,
                         physicsEnabled: Bool) -> ViewportDebugVisualizationSettings {
        var settings = ViewportDebugVisualizationSettings()
        settings.worldIcons = ViewportWorldIconSettings(
            enabled: worldIconsEnabled,
            baseSize: worldIconBaseSize,
            distanceScale: worldIconDistanceScale,
            minSize: worldIconMinSize,
            maxSize: worldIconMaxSize,
            opacity: 1.0
        )
        settings.cameraFrustums.enabled = cameraFrustumEnabled
        settings.physics.enabled = physicsEnabled
        return settings
    }
}

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
    var viewportDebugVisualizations: ViewportDebugVisualizationSettings
    var editorDebugGridEnabled: Bool
    var editorDebugOutlineEnabled: Bool
    var editorDebugPhysicsEnabled: Bool

    init(schemaVersion: Int = 2,
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
         viewportDebugVisualizations: ViewportDebugVisualizationSettings = ViewportDebugVisualizationSettings(),
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
        self.viewportDebugVisualizations = viewportDebugVisualizations
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
        case viewportDebugVisualizations
        case editorDebugGridEnabled
        case editorDebugOutlineEnabled
        case editorDebugPhysicsEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 2
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
        viewportDebugVisualizations = try container.decodeIfPresent(ViewportDebugVisualizationSettings.self, forKey: .viewportDebugVisualizations)
            ?? ViewportDebugVisualizationSettings.migrated(
                worldIconsEnabled: viewportShowWorldIcons,
                worldIconBaseSize: viewportWorldIconBaseSize,
                worldIconDistanceScale: viewportWorldIconDistanceScale,
                worldIconMinSize: viewportWorldIconMinSize,
                worldIconMaxSize: viewportWorldIconMaxSize,
                cameraFrustumEnabled: viewportShowSelectedCameraFrustum,
                physicsEnabled: try container.decodeIfPresent(Bool.self, forKey: .editorDebugPhysicsEnabled) ?? false
            )
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
    private(set) var viewportDebugVisualizations = ViewportDebugVisualizationSettings()
    var viewportShowWorldIcons: Bool { viewportDebugVisualizations.worldIcons.enabled }
    var viewportWorldIconBaseSize: Float { viewportDebugVisualizations.worldIcons.baseSize }
    var viewportWorldIconDistanceScale: Float { viewportDebugVisualizations.worldIcons.distanceScale }
    var viewportWorldIconMinSize: Float { viewportDebugVisualizations.worldIcons.minSize }
    var viewportWorldIconMaxSize: Float { viewportDebugVisualizations.worldIcons.maxSize }
    var viewportShowSelectedCameraFrustum: Bool { viewportDebugVisualizations.cameraFrustums.enabled }
    private(set) var viewportPreviewEnabled: Bool = true
    private(set) var viewportPreviewSize: Float = 0.28
    private(set) var viewportPreviewPosition: Int = 3
    private(set) var editorDebugGridEnabled: Bool = true
    private(set) var editorDebugOutlineEnabled: Bool = true
    var editorDebugPhysicsEnabled: Bool { viewportDebugVisualizations.physics.enabled }

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
            viewportDebugVisualizations = document.viewportDebugVisualizations
            viewportPreviewEnabled = document.viewportPreviewEnabled
            viewportPreviewSize = document.viewportPreviewSize
            viewportPreviewPosition = document.viewportPreviewPosition
            editorDebugGridEnabled = document.editorDebugGridEnabled
            editorDebugOutlineEnabled = document.editorDebugOutlineEnabled
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
            viewportDebugVisualizations: viewportDebugVisualizations,
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
    func setViewportShowWorldIcons(_ value: Bool) { viewportDebugVisualizations.worldIcons.enabled = value }
    func setViewportWorldIconBaseSize(_ value: Float) { viewportDebugVisualizations.worldIcons.baseSize = value }
    func setViewportWorldIconDistanceScale(_ value: Float) { viewportDebugVisualizations.worldIcons.distanceScale = value }
    func setViewportWorldIconMinSize(_ value: Float) { viewportDebugVisualizations.worldIcons.minSize = value }
    func setViewportWorldIconMaxSize(_ value: Float) { viewportDebugVisualizations.worldIcons.maxSize = value }
    func setViewportShowSelectedCameraFrustum(_ value: Bool) { viewportDebugVisualizations.cameraFrustums.enabled = value }
    func setViewportPreviewEnabled(_ value: Bool) { viewportPreviewEnabled = value }
    func setViewportPreviewSize(_ value: Float) { viewportPreviewSize = value }
    func setViewportPreviewPosition(_ value: Int) { viewportPreviewPosition = value }
    func setEditorDebugGridEnabled(_ value: Bool) { editorDebugGridEnabled = value }
    func setEditorDebugOutlineEnabled(_ value: Bool) { editorDebugOutlineEnabled = value }
    func setEditorDebugPhysicsEnabled(_ value: Bool) { viewportDebugVisualizations.physics.enabled = value }
    func viewportDebugStyle(for category: ViewportDebugVisualizationCategory) -> ViewportDebugStyle {
        viewportDebugVisualizations.style(for: category)
    }
    func setViewportDebugStyle(_ style: ViewportDebugStyle, for category: ViewportDebugVisualizationCategory) {
        viewportDebugVisualizations.setStyle(style, for: category)
    }
    func viewportProbeBlendShellSettings() -> ViewportProbeBlendShellSettings {
        viewportDebugVisualizations.reflectionProbeBlendShell
    }
    func setViewportProbeBlendShellSettings(_ settings: ViewportProbeBlendShellSettings) {
        viewportDebugVisualizations.reflectionProbeBlendShell = settings
    }

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
