/// MCEContext.swift
/// Defines the editor context that owns engine/editor services.
/// Created by refactor.

import Foundation
import MetalCupEngine

final class EditorAssetSnapshotStore {
    var snapshot: [AssetMetadata] = []
    var revision: UInt64 = 0
}

final class EditorDirectorySnapshotStore {
    var entries: [DirectoryEntrySnapshot] = []
}

struct DirectoryEntrySnapshot {
    let name: String
    let relativePath: String
    let isDirectory: Bool
    let assetType: Int32
    let handle: String
    let modifiedTime: TimeInterval
}

final class MCEContext {
    #if DEBUG
    static let debugMagicExpected: UInt64 = 0x4D43454354583031 // "MCECTX01"
    static let debugVersionExpected: UInt32 = 1
    let debugMagic: UInt64 = MCEContext.debugMagicExpected
    let debugVersion: UInt32 = MCEContext.debugVersionExpected
    #endif

    let engineContext: EngineContext
    let editorSceneController: EditorSceneController
    let editorProjectManager: EditorProjectManager
    let editorSelection: EditorSelection
    let editorSettingsStore: EditorSettingsStore
    let editorUIState: EditorUIState
    let editorAlertCenter: EditorAlertCenter
    let editorLogCenter: EditorLogCenter
    let assetSnapshotStore: EditorAssetSnapshotStore
    let directorySnapshotStore: EditorDirectorySnapshotStore
    let panelState: UnsafeMutableRawPointer
    var imguiBridge: ImGuiBridge?

    init(engineContext: EngineContext) {
        self.engineContext = engineContext
        self.editorLogCenter = EditorLogCenter(engineLogger: engineContext.log)
        self.editorSettingsStore = EditorSettingsStore()
        self.editorUIState = EditorUIState(settingsStore: editorSettingsStore)
        self.editorSelection = EditorSelection()
        self.editorAlertCenter = EditorAlertCenter(logCenter: engineContext.log)
        self.assetSnapshotStore = EditorAssetSnapshotStore()
        self.directorySnapshotStore = EditorDirectorySnapshotStore()
        self.panelState = MCEUIPanelStateCreate()
        self.editorSceneController = EditorSceneController(prefabSystem: engineContext.prefabSystem)
        self.editorProjectManager = EditorProjectManager(
            settingsStore: editorSettingsStore,
            uiState: editorUIState,
            logCenter: engineContext.log,
            alertCenter: editorAlertCenter,
            sceneController: editorSceneController,
            layerCatalog: engineContext.layerCatalog
        )
    }

    deinit {
        MCEUIPanelStateDestroy(panelState)
    }
}

@_cdecl("MCEContextCreate")
public func MCEContextCreate(_ engineContextPtr: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer {
    let engineContext = Unmanaged<EngineContext>.fromOpaque(engineContextPtr).takeUnretainedValue()
    let context = MCEContext(engineContext: engineContext)
    let ptr = Unmanaged.passRetained(context).toOpaque()
    return ptr
}

@_cdecl("MCEContextDestroy")
public func MCEContextDestroy(_ contextPtr: UnsafeMutableRawPointer) {
    Unmanaged<MCEContext>.fromOpaque(contextPtr).release()
}

@_cdecl("MCEContextGetUIPanelState")
public func MCEContextGetUIPanelState(_ contextPtr: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let contextPtr else { return nil }
    let context = Unmanaged<MCEContext>.fromOpaque(contextPtr).takeUnretainedValue()
    return context.panelState
}

@_cdecl("MCEImGuiSetGizmoCapture")
public func MCEImGuiSetGizmoCapture(_ contextPtr: UnsafeMutableRawPointer,
                                    _ wantsMouse: UInt32,
                                    _ wantsKeyboard: UInt32) {
    let context = Unmanaged<MCEContext>.fromOpaque(contextPtr).takeUnretainedValue()
    context.imguiBridge?.setGizmoCaptureMouse(wantsMouse != 0, keyboard: wantsKeyboard != 0)
}
