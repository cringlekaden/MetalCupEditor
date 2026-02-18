/// EditorSceneController.swift
/// Centralized editor-owned scene lifecycle controller.
/// Created by refactor.

import Foundation
import simd
import MetalCupEngine

final class EditorSceneController {
    private let prefabSystem: PrefabSystem

    init(prefabSystem: PrefabSystem) {
        self.prefabSystem = prefabSystem
    }

    private(set) var editorScene: EngineScene?
    private(set) var runtimeScene: EngineScene?
    private(set) var isPlaying: Bool = false
    private(set) var isPaused: Bool = false

    private var editorSnapshot: SceneDocument?
    private var selectedEntityId: UUID?

    // MARK: - Scene Accessors

    func setScene(_ scene: EngineScene) {
        editorScene = scene
    }

    func activeScene() -> EngineScene? {
        if isPlaying { return runtimeScene }
        return editorScene
    }

    // MARK: - Per-frame Update

    func update() {
        guard let scene = activeScene() else { return }
        prefabSystem.applyIfNeeded(scene: scene)
        if isPlaying {
            updateRuntimeScene(scene)
        } else {
            updateEditorScene(scene)
        }
    }

    func updateViewportSize(_ size: SIMD2<Float>) {
        Renderer.ViewportSize = size
        activeScene()?.updateAspectRatio()
    }

    func markPrefabsDirty(handles: [AssetHandle]) {
        prefabSystem.markAllDirty(handles: handles)
    }

    // MARK: - Play/Pause/Stop

    func play() {
        if isPlaying { return }
        guard let editorScene else { return }
        editorSnapshot = editorScene.toDocument(rendererSettingsOverride: RendererSettingsDTO(settings: Renderer.settings))
        if let snapshot = editorSnapshot {
            runtimeScene = SerializedScene(document: snapshot, prefabSystem: prefabSystem)
        } else {
            let empty = SceneDocument(id: UUID(), name: "Untitled", entities: [])
            runtimeScene = SerializedScene(document: empty, prefabSystem: prefabSystem)
        }
        Time.Reset()
        isPlaying = true
        isPaused = false
    }

    func stop() {
        if !isPlaying { return }
        if let snapshot = editorSnapshot, let editorScene {
            editorScene.apply(document: snapshot)
            if let settings = snapshot.rendererSettingsOverride {
                Renderer.settings = settings.makeRendererSettings()
            }
        }
        editorSnapshot = nil
        runtimeScene = nil
        isPlaying = false
        isPaused = false
        Time.Reset()
    }

    func pause() {
        if !isPlaying { return }
        isPaused = true
    }

    func resume() {
        if !isPlaying { return }
        isPaused = false
    }

    // MARK: - Serialization

    func saveScene(to url: URL) throws {
        guard let editorScene else { return }
        try SceneSerializer.save(scene: editorScene, to: url)
    }

    func loadScene(from url: URL) throws {
        let document = try SceneSerializer.load(from: url)
        if let settings = document.rendererSettingsOverride {
            Renderer.settings = settings.makeRendererSettings()
        }
        let scene = SerializedScene(document: document, prefabSystem: prefabSystem)
        editorScene = scene
        if isPlaying {
            runtimeScene = SerializedScene(document: document, prefabSystem: prefabSystem)
        }
    }

    // MARK: - Selection

    func setSelectedEntityId(_ value: String) {
        selectedEntityId = UUID(uuidString: value)
    }

    func selectedEntityUUID() -> UUID? {
        selectedEntityId
    }

    // MARK: - Internals

    private func updateRuntimeScene(_ scene: EngineScene) {
        scene.onUpdate(isPlaying: true, isPaused: isPaused)
        scene.runtime.play()
        if isPaused {
            scene.runtime.pause()
        } else {
            scene.runtime.resume()
        }
        scene.runtime.update(scene: scene)

        if isPaused {
            _ = Time.ConsumeFixedSteps()
            return
        }
        let steps = Time.ConsumeFixedSteps()
        if steps > 0 {
            for _ in 0..<steps {
                scene.runtime.fixedUpdate(scene: scene)
            }
        }
    }

    private func updateEditorScene(_ scene: EngineScene) {
        scene.onUpdate(isPlaying: false, isPaused: false)
        scene.runtime.stop()
        scene.runtime.update(scene: scene)
    }
}
