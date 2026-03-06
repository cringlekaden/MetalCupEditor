/// MCEContext.swift
/// Defines the editor context that owns engine/editor services.
/// Created by Kaden Cringle

import Foundation
import MetalCupEngine

protocol EditorBridgeServices: AnyObject {
    var isPlaying: Bool { get }
    var isSimulating: Bool { get }
    var runtimeScene: EngineScene? { get }

    func activeScene() -> EngineScene?
    func selectedEntityIds() -> [UUID]
    func setSelectedEntityIds(_ ids: [UUID], primary: UUID?)

    func notifySceneMutation()
    func assetMetadataSnapshot() -> [AssetMetadata]
    func assetURL(for handle: AssetHandle) -> URL?
    func performAssetMutation(_ body: () throws -> Bool) -> Bool
    var supportsUndoTransactions: Bool { get }
    func recordUndoTransaction(_ label: String)
}

final class DefaultEditorBridgeServices: EditorBridgeServices {
    private unowned let context: MCEContext

    init(context: MCEContext) {
        self.context = context
    }

    var isPlaying: Bool { context.editorSceneController.isPlaying }
    var isSimulating: Bool { context.editorSceneController.isSimulating }
    var runtimeScene: EngineScene? { context.editorSceneController.runtimeScene }

    func activeScene() -> EngineScene? {
        context.editorSceneController.activeScene()
    }

    func selectedEntityIds() -> [UUID] {
        context.editorSceneController.selectedEntityUUIDs()
    }

    func setSelectedEntityIds(_ ids: [UUID], primary: UUID?) {
        context.editorSceneController.setSelectedEntityIds(ids, primary: primary)
    }

    func notifySceneMutation() {
        context.editorProjectManager.notifySceneMutation()
    }

    func assetMetadataSnapshot() -> [AssetMetadata] {
        context.editorProjectManager.assetMetadataSnapshot()
    }

    func assetURL(for handle: AssetHandle) -> URL? {
        context.editorProjectManager.assetURL(for: handle)
    }

    func performAssetMutation(_ body: () throws -> Bool) -> Bool {
        context.editorProjectManager.performAssetMutation(body)
    }

    var supportsUndoTransactions: Bool { false }

    func recordUndoTransaction(_ label: String) {
        _ = label
    }
}

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
    let importFailed: Bool
    let importFailureReason: String
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
    let importController: ImportController
    let panelState: UnsafeMutableRawPointer
    var imguiBridge: ImGuiBridge?
    lazy var bridgeServices: EditorBridgeServices = DefaultEditorBridgeServices(context: self)

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
        self.editorSceneController = EditorSceneController(prefabSystem: engineContext.prefabSystem, engineContext: engineContext)
        self.editorProjectManager = EditorProjectManager(
            settingsStore: editorSettingsStore,
            uiState: editorUIState,
            logCenter: engineContext.log,
            alertCenter: editorAlertCenter,
            sceneController: editorSceneController,
            layerCatalog: engineContext.layerCatalog,
            engineContext: engineContext
        )
        self.importController = ImportController(projectManager: editorProjectManager, logCenter: engineContext.log)
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

@_cdecl("MCEContextGetEngineContext")
public func MCEContextGetEngineContext(_ contextPtr: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let contextPtr else { return nil }
    let context = Unmanaged<MCEContext>.fromOpaque(contextPtr).takeUnretainedValue()
    return Unmanaged.passUnretained(context.engineContext).toOpaque()
}

@_cdecl("MCEImGuiSetGizmoCapture")
public func MCEImGuiSetGizmoCapture(_ contextPtr: UnsafeMutableRawPointer,
                                    _ wantsMouse: UInt32,
                                    _ wantsKeyboard: UInt32) {
    let context = Unmanaged<MCEContext>.fromOpaque(contextPtr).takeUnretainedValue()
    context.imguiBridge?.setGizmoCaptureMouse(wantsMouse != 0, keyboard: wantsKeyboard != 0)
}
