import Foundation
import MetalCupEngine

final class RuntimeSessionManager {
    private let prefabSystem: PrefabSystem
    private weak var engineContext: EngineContext?

    private var editorSnapshot: SceneDocument?
    private var simulateSnapshot: SceneDocument?
    private var cachedScriptRuntime: ScriptRuntime?
    private var prePlayPhysicsSettings: PhysicsSettings?

    private(set) var runtimeScene: EngineScene?

    init(prefabSystem: PrefabSystem, engineContext: EngineContext) {
        self.prefabSystem = prefabSystem
        self.engineContext = engineContext
    }

    @discardableResult
    func startPlay(from editorScene: EngineScene) -> Bool {
        let rendererSettings = engineContext?.rendererSettings ?? RendererSettings()
        let physicsSettings = engineContext?.physicsSettings ?? PhysicsSettings()
        editorSnapshot = editorScene.toDocument(
            rendererSettingsOverride: RendererSettingsDTO(settings: rendererSettings),
            physicsSettingsOverride: PhysicsSettingsDTO(settings: physicsSettings)
        )

        if let snapshot = editorSnapshot {
            runtimeScene = SerializedScene(
                document: snapshot,
                prefabSystem: prefabSystem,
                engineContext: engineContext
            )
        } else {
            let empty = SceneDocument(id: UUID(), name: "Untitled", entities: [])
            runtimeScene = SerializedScene(
                document: empty,
                prefabSystem: prefabSystem,
                engineContext: engineContext
            )
        }

        if let engineContext {
            prePlayPhysicsSettings = engineContext.physicsSettings
            if !engineContext.physicsSettings.deterministic {
                var playPhysicsSettings = engineContext.physicsSettings
                playPhysicsSettings.deterministic = true
                engineContext.physicsSettings = playPhysicsSettings
            }
        }

        if let physicsSettings = engineContext?.physicsSettings {
            runtimeScene?.startPhysics(settings: physicsSettings)
        }
        runtimeScene?.resetRuntimeInputState()
        engineContext?.renderer?.inputAccumulator?.resetForRuntimeStart(clearKeys: false, clearMouseButtons: false)

        if let engineContext {
            cachedScriptRuntime = engineContext.scriptRuntime
            engineContext.scriptRuntime = LuaScriptRuntime(engineContext: engineContext)
        }

        runtimeScene?.notifyScriptSceneStart()
        runtimePrepareForPlayStart(lockCursor: true)
        return runtimeScene != nil
    }

    func stopPlay(restoreInto editorScene: EngineScene?) {
        runtimeForceCursorNormal()
        runtimeScene?.notifyScriptSceneStop()
        runtimeScene?.stopPhysics()

        if let engineContext {
            engineContext.scriptRuntime = cachedScriptRuntime ?? NullScriptRuntime()
        }
        cachedScriptRuntime = nil

        if let snapshot = editorSnapshot, let editorScene {
            editorScene.apply(document: snapshot)
            if let settings = snapshot.rendererSettingsOverride {
                engineContext?.rendererSettings = settings.makeRendererSettings()
            }
            if let physicsSettings = snapshot.physicsSettingsOverride {
                engineContext?.physicsSettings = physicsSettings.makePhysicsSettings()
            }
        }

        editorSnapshot = nil
        runtimeScene = nil

        if let engineContext, let prePlayPhysicsSettings {
            engineContext.physicsSettings = prePlayPhysicsSettings
        }
        prePlayPhysicsSettings = nil
    }

    @discardableResult
    func startSimulate(on editorScene: EngineScene) -> Bool {
        let rendererSettings = engineContext?.rendererSettings ?? RendererSettings()
        let physicsSettings = engineContext?.physicsSettings ?? PhysicsSettings()
        simulateSnapshot = editorScene.toDocument(
            rendererSettingsOverride: RendererSettingsDTO(settings: rendererSettings),
            physicsSettingsOverride: PhysicsSettingsDTO(settings: physicsSettings)
        )
        editorScene.startPhysics(settings: physicsSettings)
        return true
    }

    func resetSimulate(on editorScene: EngineScene?) {
        editorScene?.stopPhysics()
        if let snapshot = simulateSnapshot, let editorScene {
            editorScene.apply(document: snapshot)
            if let settings = snapshot.rendererSettingsOverride {
                engineContext?.rendererSettings = settings.makeRendererSettings()
            }
            if let physicsSettings = snapshot.physicsSettingsOverride {
                engineContext?.physicsSettings = physicsSettings.makePhysicsSettings()
            }
        }
        simulateSnapshot = nil
    }

    func replaceRuntimeScene(with document: SceneDocument) {
        runtimeScene = SerializedScene(
            document: document,
            prefabSystem: prefabSystem,
            engineContext: engineContext
        )
    }
}
