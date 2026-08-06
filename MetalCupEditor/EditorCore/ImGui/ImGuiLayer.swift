/// ImGuiLayer.swift
/// Defines the editor layer that drives ImGui rendering and input capture.
/// Created by Kaden Cringle.

import MetalKit
import Foundation
import MetalCupEngine
import simd
#if canImport(GameController)
import GameController
#endif

final class ImGuiLayer: Layer {

    private let context: MCEContext
    private let contextPtr: UnsafeMutableRawPointer
    private let imguiBridge: ImGuiBridge
    private let sceneContext = EditorSceneContext()
    private var previewTexture: MTLTexture?
    private var previewDepthTexture: MTLTexture?
    private var previewSelectedEntityId: UUID?
    private var previewLastTransform = TransformComponent()
    private var previewLastCamera = CameraComponent()
    private var previewFrameCounter: UInt64 = 0
    private var previewLastUpdateFrame: UInt64 = 0
    private let previewUpdateInterval: UInt64 = 8
    private let previewTextureSize = SIMD2<Int>(256, 256)
    private var lastFrameTime: FrameTime?
    private var persistedSelectedEntityId: String = ""

    nonisolated override init(name: String) {
        fatalError("Use init(name:context:contextPtr:)")
    }

    init(name: String, context: MCEContext, contextPtr: UnsafeMutableRawPointer) {
        self.context = context
        self.contextPtr = contextPtr
        let bridge = ImGuiBridge(context: contextPtr)
        self.imguiBridge = bridge
        self.context.imguiBridge = bridge
        super.init(name: name)
    }

    nonisolated override func onUpdate(frame: FrameContext) {
        context.engineContext.debugDraw.beginFrame()
        lastFrameTime = frame.time
        sceneContext.editorScene = context.editorSceneController.editorScene
        sceneContext.runtimeScene = context.editorSceneController.runtimeScene
        sceneContext.isPlaying = context.editorSceneController.isPlaying
        sceneContext.isPaused = context.editorSceneController.isPaused

        let viewportSize = imguiBridge.viewportImageSize()
        let viewportOrigin = imguiBridge.viewportImageOrigin()
        if viewportSize.width > 1, viewportSize.height > 1 {
            context.editorSceneController.updateViewportSize(SIMD2<Float>(Float(viewportSize.width), Float(viewportSize.height)))
            let origin = SIMD2<Float>(Float(viewportOrigin.x), Float(viewportOrigin.y))
            let size = SIMD2<Float>(Float(viewportSize.width), Float(viewportSize.height))
            context.engineContext.renderer?.inputAccumulator?.setViewportRect(origin: origin, size: size)
        }
        sceneContext.viewportOrigin = SIMD2<Float>(Float(viewportOrigin.x), Float(viewportOrigin.y))
        sceneContext.viewportSize = SIMD2<Float>(Float(viewportSize.width), Float(viewportSize.height))
        context.editorSceneController.update(frame: frame)
        if !context.editorSceneController.isPlaying,
           let scene = sceneContext.activeScene {
            context.engineContext.debugDraw.submitGridXZ(SceneRenderer.gridParams(scene: scene))
        }
        let physicsSettings = context.engineContext.physicsSettings
        let allowPhysicsDebug = physicsSettings.debugDrawEnabled
            && (!sceneContext.isPlaying || physicsSettings.debugDrawInPlay)
        if allowPhysicsDebug,
           let scene = sceneContext.activeScene {
            PhysicsSystem.submitDebugDraw(
                scene: scene,
                debugDraw: context.engineContext.debugDraw,
                selectionId: sceneContext.selectedEntityIds.first
            )
        }
        if let scene = sceneContext.activeScene {
            submitSelectedCameraFrustumGizmoIfNeeded(scene: scene)
            submitReflectionProbeDebugGizmosIfNeeded(scene: scene)
        }
        context.engineContext.debugDraw.endFrame()

        let controllerSelection = context.editorSceneController.selectedEntityUUIDs()
        if sceneContext.selectedEntityIds != controllerSelection {
            sceneContext.selectedEntityIds = controllerSelection
        }

        if let activeScene = sceneContext.activeScene {
            sceneContext.selectedEntityIds.removeAll { activeScene.ecs.entity(with: $0) == nil }
        }
        if sceneContext.selectedEntityIds != context.editorSceneController.selectedEntityUUIDs() {
            context.editorSceneController.setSelectedEntityIds(
                sceneContext.selectedEntityIds,
                primary: sceneContext.selectedEntityIds.last
            )
        }
        if let primary = context.editorSceneController.selectedEntityUUID() {
            persistSelectedEntityIfNeeded(primary.uuidString)
        } else {
            persistSelectedEntityIfNeeded("")
        }
    }

    nonisolated override func onRender(encoder: MTLRenderCommandEncoder, frameContext: RendererFrameContext) {
        sceneContext.activeScene?.onRender(encoder: encoder, frameContext: frameContext)
    }
    
    nonisolated override func onOverlayRender(view: MTKView, commandBuffer: MTLCommandBuffer, frameContext: RendererFrameContext) {
        imguiBridge.setup(with: view)
        let deltaTime = lastFrameTime?.deltaTime ?? 0.0
        imguiBridge.newFrame(with: view, deltaTime: deltaTime)
        // The renderer graph publishes its final composite here; ImGui samples it as the
        // viewport scene image, then renders editor UI into the drawable render pass.
        let sceneTex = context.engineContext.assets.texture(handle: BuiltinAssets.finalColorRender)
        let previewTex = updateCameraPreviewIfNeeded(view: view, commandBuffer: commandBuffer, frameContext: frameContext)
        imguiBridge.buildUI(withSceneTexture: sceneTex, previewTexture: previewTex)
        if let rpd = view.currentRenderPassDescriptor {
            imguiBridge.render(with: commandBuffer, renderPassDescriptor: rpd)
        }
    }
    
    nonisolated override func onEvent(_ event: Event) {
        if !context.editorSceneController.isPlaying,
           let mouseEvent = event as? MouseButtonPressedEvent,
           mouseEvent.button == MouseCodes.left.rawValue {
            let viewportHovered = imguiBridge.viewportIsHovered()
            let viewportUIHovered = imguiBridge.viewportIsUIHovered()
            let wantsMouse = imguiBridge.wantsCaptureMouse()
            if viewportHovered && !viewportUIHovered && !wantsMouse {
                let viewportOrigin = imguiBridge.viewportImageOrigin()
                let viewportImageSize = imguiBridge.viewportImageSize()
                let pickTexture = context.engineContext.assets.texture(handle: BuiltinAssets.pickIdRender)
                let textureWidth = Float(pickTexture?.width ?? 0)
                let textureHeight = Float(pickTexture?.height ?? 0)
                let mousePos = imguiBridge.mousePosition()
                let local = SIMD2<Float>(Float(mousePos.x - viewportOrigin.x),
                                         Float(mousePos.y - viewportOrigin.y))
                if local.x < 0 || local.y < 0
                    || local.x >= Float(viewportImageSize.width)
                    || local.y >= Float(viewportImageSize.height) {
                    return
                }
                if textureWidth > 1, textureHeight > 1,
                   viewportImageSize.width > 1, viewportImageSize.height > 1 {
                    let viewportSize = SIMD2<Float>(
                        max(1.0, Float(viewportImageSize.width)),
                        max(1.0, Float(viewportImageSize.height))
                    )
                    var uv = local / viewportSize
                    uv.x = max(0.0, min(uv.x, 1.0))
                    uv.y = max(0.0, min(uv.y, 1.0))
                    let pixelX = Int(uv.x * textureWidth)
                    let pixelY = Int(uv.y * textureHeight)
                    let clampedX = max(0, min(pixelX, Int(textureWidth) - 1))
                    let clampedY = max(0, min(pixelY, Int(textureHeight) - 1))

                    if !viewportUIHovered {
                        sceneContext.pendingPickRequest = SIMD2<Int>(clampedX, clampedY)
                        context.engineContext.pickingSystem.requestPick(pixel: SIMD2<Int>(clampedX, clampedY), mask: .all)
                    }
                }
            }
        }
        if shouldCaptureEvent(event) {
            event.handled = true
            return
        }
        sceneContext.activeScene?.onEvent(event)
    }

    func activeScene() -> EngineScene? {
        sceneContext.activeScene
    }

    func buildSceneView() -> SceneView {
        let viewportSize: SIMD2<Float> = {
            if sceneContext.viewportSize.x > 1, sceneContext.viewportSize.y > 1 {
                return sceneContext.viewportSize
            }
            let renderer = context.engineContext.renderer
            let fallback = (renderer?.drawableSize.x ?? 0 > 1 && renderer?.drawableSize.y ?? 0 > 1)
                ? (renderer?.drawableSize ?? .zero)
                : (renderer?.viewportSize ?? .zero)
            return SIMD2<Float>(max(1, fallback.x), max(1, fallback.y))
        }()
        let activeScene = sceneContext.activeScene
        let matrices = activeScene.map { SceneRenderer.cameraMatrices(scene: $0) }
        let cameraPosition = activeScene.map { SceneRenderer.cameraPosition(scene: $0) } ?? .zero
        let exposureSettings = activeScene.map { SceneRenderer.cameraExposure(scene: $0) } ?? SceneViewExposureSettings()
        return SceneView(
            viewId: sceneContext.isPlaying ? 2 : 1,
            viewMatrix: matrices?.view ?? matrix_identity_float4x4,
            projectionMatrix: matrices?.projection ?? matrix_identity_float4x4,
            cameraPosition: cameraPosition,
            viewportSize: viewportSize,
            viewportOrigin: sceneContext.viewportOrigin,
            mousePositionInViewport: nil,
            requestPick: sceneContext.pendingPickRequest != nil,
            exposureSettings: exposureSettings,
            layerMask: .all,
            selectedEntityIds: sceneContext.selectedEntityIds,
            debugFlags: 0,
            depthPrepassEnabled: true,
            isEditorView: !sceneContext.isPlaying
        )
    }

    func handlePickResult(_ result: PickResult) {
        sceneContext.pendingPickRequest = nil
        guard let scene = sceneContext.activeScene else { return }
        if result.pickedId == 0 {
            sceneContext.selectedEntityIds = []
            sceneContext.lastPickResult = nil
            context.editorSceneController.setSelectedEntityIds([], primary: nil)
            persistSelectedEntityIfNeeded("")
            return
        }
        if let entity = context.engineContext.pickingSystem.entity(for: result.pickedId),
           let hit = scene.raycast(hitEntity: entity, mask: result.mask) {
            sceneContext.selectedEntityIds = [hit.id]
            sceneContext.lastPickResult = hit.id
            context.editorSceneController.setSelectedEntityIds([hit.id], primary: hit.id)
            persistSelectedEntityIfNeeded(hit.id.uuidString)
        } else {
            sceneContext.selectedEntityIds = []
            sceneContext.lastPickResult = nil
            context.editorSceneController.setSelectedEntityIds([], primary: nil)
            persistSelectedEntityIfNeeded("")
        }
    }

    private func persistSelectedEntityIfNeeded(_ id: String) {
        if persistedSelectedEntityId == id {
            return
        }
        persistedSelectedEntityId = id
        imguiBridge.setSelectedEntityId(id)
    }

    private func shouldCaptureEvent(_ event: Event) -> Bool {
        if context.editorSceneController.isPlaying {
            let cursorLocked = runtimeIsCursorLocked()
            // During play with locked cursor, route input directly to runtime controls
            // even if the viewport is not focused yet (first-frame play/start case).
            if cursorLocked {
                switch event {
                case is MouseMovedEvent, is MouseButtonPressedEvent, is MouseButtonReleasedEvent, is MouseScrolledEvent,
                     is KeyPressedEvent, is KeyReleasedEvent:
                    return false
                default:
                    break
                }
            }
        }
        let wantsMouse = imguiBridge.wantsCaptureMouse()
        let wantsKeyboard = imguiBridge.wantsCaptureKeyboard()
        let viewportHovered = imguiBridge.viewportIsHovered()
        let viewportFocused = imguiBridge.viewportIsFocused()

        switch event {
        case is MouseMovedEvent, is MouseButtonPressedEvent, is MouseButtonReleasedEvent, is MouseScrolledEvent:
            return !viewportHovered || wantsMouse
        case is KeyPressedEvent, is KeyReleasedEvent:
            return !viewportFocused || wantsKeyboard
        default:
            return false
        }
    }

    private func updateCameraPreviewIfNeeded(view: MTKView,
                                             commandBuffer: MTLCommandBuffer,
                                             frameContext: RendererFrameContext) -> MTLTexture? {
        previewFrameCounter &+= 1
        guard let scene = context.editorSceneController.activeScene(),
              let selectedId = context.editorSceneController.selectedEntityUUID(),
              let entity = scene.ecs.entity(with: selectedId),
              let camera = scene.ecs.get(CameraComponent.self, for: entity),
              let transform = scene.ecs.get(TransformComponent.self, for: entity) else {
            previewSelectedEntityId = nil
            return nil
        }

        ensurePreviewTextures(device: view.device!)
        guard let previewTexture, let previewDepthTexture else { return nil }

        let shouldUpdate = previewNeedsUpdate(selectedId: selectedId, transform: transform, camera: camera)
        if shouldUpdate {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = previewTexture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0)
            pass.depthAttachment.texture = previewDepthTexture
            pass.depthAttachment.loadAction = .clear
            pass.depthAttachment.storeAction = .store
            pass.depthAttachment.clearDepth = 1.0

            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) {
                scene.renderPreview(
                    encoder: encoder,
                    cameraEntity: entity,
                    viewportSize: SIMD2<Float>(Float(previewTextureSize.x), Float(previewTextureSize.y)),
                    frameContext: frameContext
                )
                encoder.endEncoding()
            }

            previewSelectedEntityId = selectedId
            previewLastTransform = transform
            previewLastCamera = camera
            previewLastUpdateFrame = previewFrameCounter
        }

        return previewTexture
    }

    private func ensurePreviewTextures(device: MTLDevice) {
        let size = previewTextureSize
        if previewTexture?.width != size.x
            || previewTexture?.height != size.y
            || previewTexture?.pixelFormat != .rgba16Float {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba16Float,
                width: size.x,
                height: size.y,
                mipmapped: false
            )
            descriptor.usage = [.renderTarget, .shaderRead]
            previewTexture = device.makeTexture(descriptor: descriptor)
        }

        if previewDepthTexture?.width != size.x || previewDepthTexture?.height != size.y {
            let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .depth32Float,
                width: size.x,
                height: size.y,
                mipmapped: false
            )
            depthDescriptor.usage = [.renderTarget]
            previewDepthTexture = device.makeTexture(descriptor: depthDescriptor)
        }
    }

    private func previewNeedsUpdate(selectedId: UUID, transform: TransformComponent, camera: CameraComponent) -> Bool {
        if previewSelectedEntityId != selectedId {
            return true
        }
        if previewFrameCounter - previewLastUpdateFrame >= previewUpdateInterval {
            return true
        }
        if !transformApproximatelyEqual(lhs: transform, rhs: previewLastTransform) {
            return true
        }
        if !cameraApproximatelyEqual(lhs: camera, rhs: previewLastCamera) {
            return true
        }
        return false
    }

    private func transformApproximatelyEqual(lhs: TransformComponent, rhs: TransformComponent) -> Bool {
        let epsilon: Float = 0.0001
        return simd_distance_squared(lhs.position, rhs.position) < epsilon
            && simd_distance_squared(lhs.rotation, rhs.rotation) < epsilon
            && simd_distance_squared(lhs.scale, rhs.scale) < epsilon
    }

    private func cameraApproximatelyEqual(lhs: CameraComponent, rhs: CameraComponent) -> Bool {
        let epsilon: Float = 0.0001
        return abs(lhs.fovDegrees - rhs.fovDegrees) < epsilon
            && abs(lhs.orthoSize - rhs.orthoSize) < epsilon
            && abs(lhs.nearPlane - rhs.nearPlane) < epsilon
            && abs(lhs.farPlane - rhs.farPlane) < epsilon
            && lhs.projectionType == rhs.projectionType
            && lhs.isPrimary == rhs.isPrimary
            && lhs.isEditor == rhs.isEditor
    }

    private func submitSelectedCameraFrustumGizmoIfNeeded(scene: EngineScene) {
        if context.editorSceneController.isPlaying || context.editorSceneController.isSimulating {
            return
        }
        if !context.editorProjectManager.viewportDebugStyle(.cameraFrustums).enabled {
            return
        }
        guard let selectedId = context.editorSceneController.selectedEntityUUID(),
              let entity = scene.ecs.entity(with: selectedId),
              let camera = scene.ecs.get(CameraComponent.self, for: entity),
              scene.ecs.get(TransformComponent.self, for: entity) != nil else {
            return
        }
        if camera.isEditor {
            return
        }

        let accent = context.editorProjectManager.themeAccent()
        let color = SIMD4<Float>(accent.0, accent.1, accent.2, 1.0)
        let debugDraw = context.engineContext.debugDraw

        let worldTransform = scene.ecs.worldTransform(for: entity)
        let position = worldTransform.position
        let normalizedRotation = TransformMath.normalizedQuaternion(worldTransform.rotation)
        let rotation = simd_quatf(
            real: normalizedRotation.w,
            imag: SIMD3<Float>(normalizedRotation.x, normalizedRotation.y, normalizedRotation.z)
        )

        let right = safeNormalize(rotation.act(SIMD3<Float>(1, 0, 0)), fallback: SIMD3<Float>(1, 0, 0))
        let up = safeNormalize(rotation.act(SIMD3<Float>(0, 1, 0)), fallback: SIMD3<Float>(0, 1, 0))
        let forward = safeNormalize(rotation.act(SIMD3<Float>(0, 0, -1)), fallback: SIMD3<Float>(0, 0, -1))

        let gizmoLength: Float = 2.0
        let nearDepth = gizmoLength * 0.05
        let farDepth = gizmoLength
        let aspect = max(0.1, sceneContext.viewportSize.x / max(1.0, sceneContext.viewportSize.y))

        let nearHalfW: Float
        let nearHalfH: Float
        let farHalfW: Float
        let farHalfH: Float
        switch camera.projectionType {
        case .perspective:
            let fov = max(1.0, min(179.0, camera.fovDegrees)) * (.pi / 180.0)
            let tanHalfFov = tan(fov * 0.5)
            nearHalfH = nearDepth * tanHalfFov
            nearHalfW = nearHalfH * aspect
            farHalfH = farDepth * tanHalfFov
            farHalfW = farHalfH * aspect
        case .orthographic:
            let baseHalfHeight = max(0.05, camera.orthoSize * 0.5)
            let clampedHalfHeight = min(baseHalfHeight, gizmoLength * 0.75)
            nearHalfH = clampedHalfHeight
            nearHalfW = clampedHalfHeight * aspect
            farHalfH = clampedHalfHeight
            farHalfW = clampedHalfHeight * aspect
        }

        let nearCenter = position + forward * nearDepth
        let farCenter = position + forward * farDepth

        let nearCorners = makeFrustumCorners(center: nearCenter, right: right, up: up, halfWidth: nearHalfW, halfHeight: nearHalfH)
        let farCorners = makeFrustumCorners(center: farCenter, right: right, up: up, halfWidth: farHalfW, halfHeight: farHalfH)

        submitFrustumRect(corners: nearCorners, debugDraw: debugDraw, color: color)
        submitFrustumRect(corners: farCorners, debugDraw: debugDraw, color: color)
        for i in 0..<4 {
            debugDraw.submitLine(category: .cameraFrustum, nearCorners[i], farCorners[i], color: color)
        }
        debugDraw.submitLine(category: .cameraFrustum, position, farCenter, color: color)
    }

    private func makeFrustumCorners(center: SIMD3<Float>,
                                    right: SIMD3<Float>,
                                    up: SIMD3<Float>,
                                    halfWidth: Float,
                                    halfHeight: Float) -> [SIMD3<Float>] {
        [
            center - right * halfWidth + up * halfHeight,
            center + right * halfWidth + up * halfHeight,
            center + right * halfWidth - up * halfHeight,
            center - right * halfWidth - up * halfHeight
        ]
    }

    private func submitFrustumRect(corners: [SIMD3<Float>], debugDraw: DebugDraw, color: SIMD4<Float>) {
        guard corners.count == 4 else { return }
        debugDraw.submitPolyline(category: .cameraFrustum, corners, color: color, closed: true)
    }

    private func safeNormalize(_ v: SIMD3<Float>, fallback: SIMD3<Float>) -> SIMD3<Float> {
        let lenSq = simd_length_squared(v)
        if lenSq < 1e-8 || !lenSq.isFinite {
            return fallback
        }
        return v / sqrt(lenSq)
    }

    private func submitReflectionProbeDebugGizmosIfNeeded(scene: EngineScene) {
        let probeInfluenceEnabled = context.editorProjectManager.viewportDebugStyle(.reflectionProbeInfluence).enabled
        let probeShellEnabled = context.editorProjectManager.viewportDebugStyle(.reflectionProbeBlendShell).enabled
        let probeLinkEnabled = context.editorProjectManager.viewportDebugStyle(.reflectionProbeLinks).enabled
        if !probeInfluenceEnabled && !probeShellEnabled && !probeLinkEnabled {
            return
        }

        let debugDraw = context.engineContext.debugDraw
        let renderer = context.engineContext.renderer
        let selectedEntityID = context.editorSceneController.selectedEntityUUID()
        let accent = context.editorProjectManager.themeAccent()
        let accentColor = SIMD4<Float>(accent.0, accent.1, accent.2, 1.0)

        let selectedReflectionDebug = selectedEntityID.flatMap {
            renderer?.debugReflectionProbeSelection(scene: scene, entityID: $0)
        }
        let selectedProbeEntityID = selectedReflectionDebug?.selectedProbeEntityID

        if probeLinkEnabled {
            if let selectedEntityID,
               let selectedEntity = scene.ecs.entity(with: selectedEntityID),
               let selectedProbeEntityID,
               let selectedProbeEntity = scene.ecs.entity(with: selectedProbeEntityID) {
                let selectedWorld = scene.ecs.worldTransform(for: selectedEntity).position
                let probeWorld = scene.ecs.worldTransform(for: selectedProbeEntity).position
                debugDraw.submitLine(category: .reflectionProbeSelectionLink, selectedWorld, probeWorld, color: accentColor)
            } else if !context.editorSceneController.isPlaying,
                      !context.editorSceneController.isSimulating,
                      let selectedEntityID,
                      let selectedEntity = scene.ecs.entity(with: selectedEntityID),
                      let selectedReflectionDebug,
                      selectedReflectionDebug.fallbackReason != .none {
                let fallbackCenter = scene.ecs.worldTransform(for: selectedEntity).position
                let fallbackColor: SIMD4<Float>
                switch selectedReflectionDebug.fallbackReason {
                case .noEnabledProbes:
                    fallbackColor = SIMD4<Float>(0.65, 0.65, 0.65, 1.0)
                case .noReadyProbes:
                    fallbackColor = SIMD4<Float>(0.95, 0.45, 0.2, 1.0)
                case .outsideInfluence:
                    fallbackColor = SIMD4<Float>(1.0, 0.8, 0.2, 1.0)
                case .none:
                    fallbackColor = accentColor
                }
                debugDraw.submitWireSphere(
                    category: .reflectionProbeSelectionLink,
                    transform: TransformMath.makeMatrix(
                        position: fallbackCenter,
                        rotation: .zero,
                        scale: SIMD3<Float>(repeating: 1.0)
                    ),
                    radius: 0.2,
                    color: fallbackColor,
                    segments: 12
                )
            }
        }

        scene.ecs.viewReflectionProbes { entity, probe in
            guard probe.enabled else { return }
            let worldTransform = scene.ecs.worldTransform(for: entity)
            let transformMatrix = TransformMath.makeMatrix(
                position: worldTransform.position,
                rotation: worldTransform.rotation,
                scale: SIMD3<Float>(repeating: 1.0)
            )
            let halfExtents = max(probe.boxExtents, SIMD3<Float>(repeating: 0.001))
            let outerHalfExtents = max(halfExtents + SIMD3<Float>(repeating: max(probe.blendDistance, 0.0)),
                                       SIMD3<Float>(repeating: 0.001))

            let statusColor = reflectionProbeDebugColor(
                for: renderer?.reflectionProbeBakeStatus(scene: scene, entityID: entity.id)
            )
            let baseColor: SIMD4<Float>
            if selectedEntityID == entity.id {
                baseColor = accentColor
            } else if selectedProbeEntityID == entity.id {
                baseColor = SIMD4<Float>(0.25, 0.95, 0.95, 1.0)
            } else {
                baseColor = statusColor
            }
            let shellOuterColor = SIMD4<Float>(baseColor.x, baseColor.y, baseColor.z, max(0.32, baseColor.w * 0.5))
            let shellConnectorColor = SIMD4<Float>(baseColor.x, baseColor.y, baseColor.z, max(0.55, baseColor.w * 0.78))

            if probeInfluenceEnabled {
                debugDraw.submitWireBox(category: .reflectionProbeInfluence,
                                        transform: transformMatrix,
                                        halfExtents: halfExtents,
                                        color: baseColor)
            }
            if probeShellEnabled && probe.blendDistance > 0.0 {
                debugDraw.submitWireBoxShell(category: .reflectionProbeBlendShell,
                                             transform: transformMatrix,
                                             innerHalfExtents: halfExtents,
                                             outerHalfExtents: outerHalfExtents,
                                             outerColor: shellOuterColor,
                                             connectorColor: shellConnectorColor)
            }
            if probeInfluenceEnabled {
                debugDraw.submitWireSphere(
                    category: .reflectionProbeInfluence,
                    transform: TransformMath.makeMatrix(
                        position: worldTransform.position,
                        rotation: .zero,
                        scale: SIMD3<Float>(repeating: 1.0)
                    ),
                    radius: 0.08,
                    color: baseColor,
                    segments: 10
                )
            }
        }
    }

    private func reflectionProbeDebugColor(for status: ReflectionProbeRuntimeStatus?) -> SIMD4<Float> {
        switch status {
        case .queued:
            return SIMD4<Float>(0.95, 0.75, 0.2, 0.95)
        case .capturing:
            return SIMD4<Float>(1.0, 0.55, 0.2, 0.95)
        case .filtering:
            return SIMD4<Float>(0.95, 0.9, 0.35, 0.95)
        case .ready:
            return SIMD4<Float>(0.25, 0.95, 0.6, 0.95)
        case .failed:
            return SIMD4<Float>(0.95, 0.3, 0.25, 0.95)
        default:
            return SIMD4<Float>(0.6, 0.65, 0.75, 0.75)
        }
    }
}
final class EditorSceneContext {
    var editorScene: EngineScene?
    var runtimeScene: EngineScene?
    var isPlaying: Bool = false
    var isPaused: Bool = false

    var viewportOrigin: SIMD2<Float> = .zero
    var viewportSize: SIMD2<Float> = .zero

    var selectedEntityIds: [UUID] = []
    var pendingPickRequest: SIMD2<Int>?
    var lastPickResult: UUID?

    var activeScene: EngineScene? {
        if isPlaying {
            return runtimeScene
        }
        return editorScene
    }
}
