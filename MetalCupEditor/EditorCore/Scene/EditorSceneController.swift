/// EditorSceneController.swift
/// Centralized editor-owned scene lifecycle controller.
/// Created by Kaden Cringle

import Foundation
import QuartzCore
import simd
import MetalCupEngine

final class EditorSceneController {
    private let prefabSystem: PrefabSystem
    private weak var engineContext: EngineContext?

    init(prefabSystem: PrefabSystem, engineContext: EngineContext) {
        self.prefabSystem = prefabSystem
        self.engineContext = engineContext
    }

    private(set) var editorScene: EngineScene?
    private(set) var runtimeScene: EngineScene?
    private(set) var isPlaying: Bool = false
    private(set) var isPaused: Bool = false
    private(set) var isSimulating: Bool = false
    private var playState: PlayState = .editing

    private var editorSnapshot: SceneDocument?
    private var simulateSnapshot: SceneDocument?
    private var selectedEntityId: UUID?
    private var selectedEntityIds: [UUID] = []
    private var fixedAccumulator: Float = 0.0
    private var simulateAccumulator: Float = 0.0
    private let maxFixedSteps: Int = 16
    private let runtimeSafetyMaxSubsteps: Int = 5
    private var cachedScriptRuntime: ScriptRuntime?
    private var prePlayPhysicsSettings: PhysicsSettings?
    private var lastFrameTime: FrameTime?
    private var timeBaseTotal: Float = 0.0
    private var timeBaseUnscaled: Float = 0.0
    private var timeBaseFrameCount: UInt64 = 0

    private enum PlayState {
        case editing
        case startingPlay
        case playing
        case paused
        case stoppingPlay
    }

    private enum FixedStepScheduleMode {
        case play
        case simulate
    }

    // MARK: - Scene Accessors

    func setScene(_ scene: EngineScene) {
        scene.engineContext = engineContext
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
        activeScene()?.updateAspectRatio()
    }

    func markPrefabsDirty(handles: [AssetHandle]) {
        prefabSystem.markAllDirty(handles: handles)
    }

    // MARK: - Play/Pause/Stop

    func play() {
        if playState != .editing { return }
        if isSimulating {
            resetSimulation()
        }
        guard let editorScene else { return }
        playState = .startingPlay
        engineContext?.debugDraw.beginFrame()
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
                // The editor drives fixed-step from the render/main loop. Keep physics single-threaded
                // during play to avoid barrier waits from UI-interactive thread -> worker threads.
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
        resetTimingBase()
        fixedAccumulator = 0.0
        isPlaying = true
        isPaused = false
        playState = .playing
    }

    func stop() {
        if playState == .editing || playState == .stoppingPlay { return }
        playState = .stoppingPlay
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
        isPlaying = false
        isPaused = false
        resetTimingBase()
        fixedAccumulator = 0.0
        playState = .editing
    }

    func simulate() {
        if isPlaying || isSimulating { return }
        guard let editorScene else { return }
        let rendererSettings = engineContext?.rendererSettings ?? RendererSettings()
        let physicsSettings = engineContext?.physicsSettings ?? PhysicsSettings()
        simulateSnapshot = editorScene.toDocument(
            rendererSettingsOverride: RendererSettingsDTO(settings: rendererSettings),
            physicsSettingsOverride: PhysicsSettingsDTO(settings: physicsSettings)
        )
        editorScene.startPhysics(settings: physicsSettings)
        resetTimingBase()
        simulateAccumulator = 0.0
        isSimulating = true
    }

    func resetSimulation() {
        guard isSimulating else { return }
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
        isSimulating = false
        resetTimingBase()
        simulateAccumulator = 0.0
    }

    func pause() {
        if playState != .playing { return }
        isPaused = true
        playState = .paused
        fixedAccumulator = 0.0
    }

    func resume() {
        if playState != .paused { return }
        isPaused = false
        playState = .playing
    }

    // MARK: - Serialization

    func saveScene(to url: URL) throws {
        guard let editorScene else { return }
        try SceneSerializer.save(scene: editorScene, to: url)
    }

    func loadScene(from url: URL) throws {
        if isSimulating {
            resetSimulation()
        }
        let document = try SceneSerializer.load(from: url)
        if let settings = document.rendererSettingsOverride {
            engineContext?.rendererSettings = settings.makeRendererSettings()
        }
        if let settings = document.physicsSettingsOverride {
            engineContext?.physicsSettings = settings.makePhysicsSettings()
        }
        let scene = SerializedScene(
            document: document,
            prefabSystem: prefabSystem,
            engineContext: engineContext
        )
        editorScene = scene
        if isPlaying {
            runtimeScene = SerializedScene(
                document: document,
                prefabSystem: prefabSystem,
                engineContext: engineContext
            )
        }
    }

    // MARK: - Selection

    func setSelectedEntityId(_ value: String) {
        if let parsed = UUID(uuidString: value) {
            selectedEntityId = parsed
            selectedEntityIds = [parsed]
        } else {
            selectedEntityId = nil
            selectedEntityIds = []
        }
    }

    func selectedEntityUUID() -> UUID? {
        selectedEntityId
    }

    func setSelectedEntityIds(_ values: [UUID], primary: UUID? = nil) {
        var deduped: [UUID] = []
        deduped.reserveCapacity(values.count)
        for id in values where !deduped.contains(id) {
            deduped.append(id)
        }
        selectedEntityIds = deduped
        if let primary, deduped.contains(primary) {
            selectedEntityId = primary
        } else {
            selectedEntityId = deduped.last
        }
    }

    func selectedEntityUUIDs() -> [UUID] {
        selectedEntityIds
    }

    // MARK: - Internals

    private func updateRuntimeScene(_ scene: EngineScene, frame: FrameContext) {
        scene.runtime.play()
        if isPaused {
            scene.runtime.pause()
        } else {
            scene.runtime.resume()
        }
        // Order: variable-dt update, then fixed-step simulation.
        recordProfilerScope(.sceneUpdate) {
            scene.updatePlay(frame: frame, isPaused: isPaused)
        }

        if isPaused { return }
        let fixedStepResult = executeFixedStepSchedule(scene: scene,
                                                       frameTime: frame.time,
                                                       mode: .play,
                                                       accumulator: &fixedAccumulator)
        scene.setFixedStepDiagnostics(
            .init(renderDeltaTime: frame.time.unscaledDeltaTime,
                  fixedDeltaTime: fixedStepResult.fixedDeltaTime,
                  fixedStepsThisFrame: fixedStepResult.stepsExecuted,
                  fixedStepsLastSecond: 0,
                  accumulatorBefore: fixedStepResult.accumulatorBefore,
                  accumulatorAfter: fixedStepResult.accumulatorAfter,
                  interpolationAlpha: fixedStepResult.interpolationAlpha)
        )
        scene.refreshRuntimeCamera(frame: frame)
    }

    private func updateEditorScene(_ scene: EngineScene, frame: FrameContext) {
        recordProfilerScope(.sceneUpdate) {
            if isSimulating {
                scene.updateSimulate(frame: frame, scriptsEnabled: false)
            } else {
                scene.updateEdit(frame: frame)
            }
        }
        if isSimulating {
            _ = executeFixedStepSchedule(scene: scene,
                                         frameTime: frame.time,
                                         mode: .simulate,
                                         accumulator: &simulateAccumulator)
        }
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

    private struct FixedStepPolicy {
        var fixedDeltaTime: Float
        var maxSubsteps: Int
        var maxAccumulatedDelta: Float
    }

    private struct FixedStepExecutionResult {
        var stepsExecuted: Int
        var fixedDeltaTime: Float
        var accumulatorBefore: Float
        var accumulatorAfter: Float
        var interpolationAlpha: Float
    }

    private func makeFixedStepPolicy(frameTime: FrameTime, mode: FixedStepScheduleMode) -> FixedStepPolicy {
        let settings = engineContext?.physicsSettings
        let requestedFixedDelta = settings?.fixedDeltaTime ?? frameTime.fixedDeltaTime
        let requestedMaxSubsteps = settings?.maxSubsteps ?? maxFixedSteps
        let safetyClamp = mode == .play ? runtimeSafetyMaxSubsteps : maxFixedSteps
        return FixedStepPolicy(
            fixedDeltaTime: max(0.0001, requestedFixedDelta),
            maxSubsteps: max(1, min(requestedMaxSubsteps, safetyClamp, maxFixedSteps)),
            maxAccumulatedDelta: 0.1
        )
    }

    private func executeFixedStepSchedule(scene: EngineScene,
                                          frameTime: FrameTime,
                                          mode: FixedStepScheduleMode,
                                          accumulator: inout Float) -> FixedStepExecutionResult {
        let policy = makeFixedStepPolicy(frameTime: frameTime, mode: mode)
        let accumulatorBefore = accumulator
        accumulator += max(0.0, frameTime.unscaledDeltaTime)
        accumulator = min(accumulator, policy.maxAccumulatedDelta)

        var stepsExecuted = 0
        if accumulator >= policy.fixedDeltaTime {
            let fixedStart = CACurrentMediaTime()
            while accumulator >= policy.fixedDeltaTime && stepsExecuted < policy.maxSubsteps {
                switch mode {
                case .play:
                    _ = scene.runPlayFixedStep(fixedDeltaOverride: policy.fixedDeltaTime)
                case .simulate:
                    _ = scene.runSimulateFixedStep(fixedDeltaOverride: policy.fixedDeltaTime)
                }
                accumulator -= policy.fixedDeltaTime
                stepsExecuted += 1
            }
            engineContext?.renderer?.profiler.record(.fixedUpdate, seconds: CACurrentMediaTime() - fixedStart)
        }

        let interpolationAlpha = policy.fixedDeltaTime > 1.0e-6
            ? simd_clamp(accumulator / policy.fixedDeltaTime, 0.0, 1.0)
            : 0.0
        return FixedStepExecutionResult(stepsExecuted: stepsExecuted,
                                        fixedDeltaTime: policy.fixedDeltaTime,
                                        accumulatorBefore: accumulatorBefore,
                                        accumulatorAfter: accumulator,
                                        interpolationAlpha: interpolationAlpha)
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

    private func recordProfilerScope(_ scope: RendererProfiler.Scope, _ body: () -> Void) {
        guard let profiler = engineContext?.renderer?.profiler else {
            body()
            return
        }
        let start = CACurrentMediaTime()
        body()
        profiler.record(scope, seconds: CACurrentMediaTime() - start)
    }
}
