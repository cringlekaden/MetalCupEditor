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
    private var fixedAccumulator: Float = 0.0
    private let maxFixedSteps: Int = 5
    private var lastFrameTime: FrameTime?
    private var timeBaseTotal: Float = 0.0
    private var timeBaseUnscaled: Float = 0.0
    private var timeBaseFrameCount: UInt64 = 0

    // MARK: - Scene Accessors

    func setScene(_ scene: EngineScene) {
        editorScene = scene
    }

    func activeScene() -> EngineScene? {
        if isPlaying { return runtimeScene }
        return editorScene
    }

    // MARK: - Per-frame Update

    func update(frame: FrameContext) {
        lastFrameTime = frame.time
        guard let scene = activeScene() else { return }
        prefabSystem.applyIfNeeded(scene: scene)
        if isPlaying {
            updateRuntimeScene(scene, frame: adjustFrame(frame))
        } else {
            updateEditorScene(scene, frame: adjustFrame(frame))
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
        resetTimingBase()
        fixedAccumulator = 0.0
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
        resetTimingBase()
        fixedAccumulator = 0.0
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

    private func updateRuntimeScene(_ scene: EngineScene, frame: FrameContext) {
        scene.onUpdate(frame: frame, isPlaying: true, isPaused: isPaused)
        scene.runtime.play()
        if isPaused {
            scene.runtime.pause()
        } else {
            scene.runtime.resume()
        }
        scene.runtime.update(scene: scene, frame: frame)

        if isPaused {
            _ = consumeFixedSteps(frameTime: frame.time)
            return
        }
        let steps = consumeFixedSteps(frameTime: frame.time)
        if steps > 0 {
            for _ in 0..<steps {
                scene.runtime.fixedUpdate(scene: scene)
            }
        }
    }

    private func updateEditorScene(_ scene: EngineScene, frame: FrameContext) {
        scene.onUpdate(frame: frame, isPlaying: false, isPaused: false)
        scene.runtime.stop()
        scene.runtime.update(scene: scene, frame: frame)
    }

    private func adjustFrame(_ frame: FrameContext) -> FrameContext {
        let adjustedTotal = max(0.0, frame.time.totalTime - timeBaseTotal)
        let adjustedUnscaledTotal = max(0.0, frame.time.unscaledTotalTime - timeBaseUnscaled)
        let adjustedFrameCount: UInt64 = frame.time.frameCount >= timeBaseFrameCount
            ? frame.time.frameCount - timeBaseFrameCount
            : 0
        let adjustedTime = FrameTime(
            deltaTime: frame.time.deltaTime,
            unscaledDeltaTime: frame.time.unscaledDeltaTime,
            timeScale: frame.time.timeScale,
            fixedDeltaTime: frame.time.fixedDeltaTime,
            frameCount: adjustedFrameCount,
            totalTime: adjustedTotal,
            unscaledTotalTime: adjustedUnscaledTotal
        )
        return FrameContext(time: adjustedTime, input: frame.input)
    }

    private func consumeFixedSteps(frameTime: FrameTime) -> Int {
        let maxStepDelta = frameTime.fixedDeltaTime * Float(maxFixedSteps)
        let clampedStepDelta = min(frameTime.deltaTime, maxStepDelta)
        fixedAccumulator += clampedStepDelta
        let availableSteps = Int(fixedAccumulator / frameTime.fixedDeltaTime)
        if availableSteps <= 0 { return 0 }
        let steps = min(availableSteps, maxFixedSteps)
        fixedAccumulator -= Float(steps) * frameTime.fixedDeltaTime
        return steps
    }

    private func resetTimingBase() {
        guard let lastFrameTime else {
            timeBaseTotal = 0.0
            timeBaseUnscaled = 0.0
            timeBaseFrameCount = 0
            return
        }
        timeBaseTotal = lastFrameTime.totalTime
        timeBaseUnscaled = lastFrameTime.unscaledTotalTime
        timeBaseFrameCount = lastFrameTime.frameCount
    }
}
