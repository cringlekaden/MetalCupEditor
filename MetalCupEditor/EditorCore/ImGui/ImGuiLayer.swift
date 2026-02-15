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

    private enum MCLog {
        static var onceKeys = Set<String>()

        static func once(_ key: String, _ message: String) {
            if onceKeys.contains(key) { return }
            onceKeys.insert(key)
            NSLog("[MC] \(message)")
        }

        static func trace(_ message: String) {
            NSLog("[MC] \(message)")
        }
    }
    
    nonisolated override init(name: String) {
        super.init(name: name)
    }

    nonisolated override func onUpdate() {
        MCLog.once("EDITOR_LOOP", "Editor loop running (ImGuiLayer.onUpdate reached)")
        DebugDraw.beginFrame()
        sceneContext.editorScene = SceneManager.getEditorScene()
        sceneContext.runtimeScene = SceneManager.isPlaying ? SceneManager.currentScene : sceneContext.runtimeScene
        sceneContext.isPlaying = SceneManager.isPlaying
        sceneContext.isPaused = SceneManager.isPaused
        if let activeScene = sceneContext.activeScene {
            MCLog.once("SCENE_ACTIVE", "Active scene id/name = \(activeScene.id)/\(activeScene.name)")
        }

        let viewportSize = ImGuiBridge.viewportImageSize()
        let viewportOrigin = ImGuiBridge.viewportImageOrigin()
        if viewportSize.width > 1, viewportSize.height > 1 {
            SceneManager.updateViewportSize(SIMD2<Float>(Float(viewportSize.width), Float(viewportSize.height)))
            Mouse.SetViewportRect(
                origin: SIMD2<Float>(Float(viewportOrigin.x), Float(viewportOrigin.y)),
                size: SIMD2<Float>(Float(viewportSize.width), Float(viewportSize.height))
            )
        }
        sceneContext.viewportOrigin = SIMD2<Float>(Float(viewportOrigin.x), Float(viewportOrigin.y))
        sceneContext.viewportSize = SIMD2<Float>(Float(viewportSize.width), Float(viewportSize.height))
        SceneManager.update()
        if !SceneManager.isPlaying {
            DebugDraw.submitGridXZ(SceneRenderer.gridParams(scene: SceneManager.currentScene))
        }
        DebugDraw.endFrame()

        if let selected = SceneManager.selectedEntityUUID() {
            if sceneContext.selectedEntityIds.first != selected {
                sceneContext.selectedEntityIds = [selected]
            }
        } else if !sceneContext.selectedEntityIds.isEmpty {
            sceneContext.selectedEntityIds = []
        }

        if let activeScene = sceneContext.activeScene,
           let selectedId = sceneContext.selectedEntityIds.first,
           activeScene.ecs.entity(with: selectedId) == nil {
            sceneContext.selectedEntityIds = []
            SceneManager.setSelectedEntityId("")
            ImGuiBridge.setSelectedEntityId("")
        } else if let selectedId = sceneContext.selectedEntityIds.first {
            ImGuiBridge.setSelectedEntityId(selectedId.uuidString)
        } else {
            ImGuiBridge.setSelectedEntityId("")
        }
    }

    nonisolated override func onRender(encoder: MTLRenderCommandEncoder) {
        sceneContext.activeScene?.onRender(encoder: encoder)
    }
    
    nonisolated override func onOverlayRender(view: MTKView, commandBuffer: MTLCommandBuffer) {
        ImGuiBridge.setup(with: view)
        ImGuiBridge.newFrame(with: view, deltaTime: Time.DeltaTime)
        let sceneTex = AssetManager.texture(handle: BuiltinAssets.finalColorRender)
        let previewTex = updateCameraPreviewIfNeeded(view: view, commandBuffer: commandBuffer)
        ImGuiBridge.buildUI(withSceneTexture: sceneTex, previewTexture: previewTex)
        if let rpd = view.currentRenderPassDescriptor {
            ImGuiBridge.render(with: commandBuffer, renderPassDescriptor: rpd)
        }
    }
    
    nonisolated override func onEvent(_ event: Event) {
        if !SceneManager.isPlaying,
           let mouseEvent = event as? MouseButtonPressedEvent,
           mouseEvent.button == MouseCodes.left.rawValue {
            let wantsMouse = ImGuiBridge.wantsCaptureMouse()
            let viewportHovered = ImGuiBridge.viewportIsHovered()
            if viewportHovered && !wantsMouse {
                let viewportOrigin = ImGuiBridge.viewportImageOrigin()
                let viewportImageSize = ImGuiBridge.viewportImageSize()
                let pickTexture = AssetManager.texture(handle: BuiltinAssets.pickIdRender)
                let textureWidth = Float(pickTexture?.width ?? 0)
                let textureHeight = Float(pickTexture?.height ?? 0)
                let mousePos = ImGuiBridge.mousePosition()
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
                    let pixelY = Int((1.0 - uv.y) * textureHeight)
                    let clampedX = max(0, min(pixelX, Int(textureWidth) - 1))
                    let clampedY = max(0, min(pixelY, Int(textureHeight) - 1))

                    MCLog.trace("PICK_REQ mouse=\(mousePos.x),\(mousePos.y) viewport=[\(viewportOrigin.x),\(viewportOrigin.y)]..[" +
                        "\(viewportOrigin.x + viewportImageSize.width),\(viewportOrigin.y + viewportImageSize.height)] " +
                        "local=\(local.x),\(local.y) uv=\(uv.x),\(uv.y) " +
                        "pixel=\(clampedX),\(clampedY) tex=\(Int(textureWidth))x\(Int(textureHeight))")

                    sceneContext.pendingPickRequest = SIMD2<Int>(clampedX, clampedY)
                    PickingSystem.requestPick(pixel: SIMD2<Int>(clampedX, clampedY), mask: .all)
                }
            }
        }
        if shouldCaptureEvent(event) {
            event.handled = true
            return
        }
        SceneManager.currentScene.onEvent(event)
    }

    func activeScene() -> EngineScene? {
        sceneContext.activeScene
    }

    func buildSceneView() -> SceneView {
        let viewportSize: SIMD2<Float> = {
            if sceneContext.viewportSize.x > 1, sceneContext.viewportSize.y > 1 {
                return sceneContext.viewportSize
            }
            let fallback = (Renderer.DrawableSize.x > 1 && Renderer.DrawableSize.y > 1)
                ? Renderer.DrawableSize
                : Renderer.ViewportSize
            return SIMD2<Float>(max(1, fallback.x), max(1, fallback.y))
        }()
        let activeScene = sceneContext.activeScene
        let matrices = activeScene.map { SceneRenderer.cameraMatrices(scene: $0) }
        let cameraPosition = activeScene.map { SceneRenderer.cameraPosition(scene: $0) } ?? .zero
        if let scene = activeScene,
           let camera = scene.ecs.activeCamera(allowEditor: true, preferEditor: !sceneContext.isPlaying) {
            MCLog.once(
                "SCENEVIEW",
                "SceneView camera=\(camera.0.id) viewRow0=\(matrices?.view.columns.0 ?? SIMD4<Float>(0,0,0,0)) " +
                    "projRow0=\(matrices?.projection.columns.0 ?? SIMD4<Float>(0,0,0,0)) " +
                    "camPos=\(cameraPosition) viewport=\(viewportSize)"
            )
        }

        return SceneView(
            viewMatrix: matrices?.view ?? matrix_identity_float4x4,
            projectionMatrix: matrices?.projection ?? matrix_identity_float4x4,
            cameraPosition: cameraPosition,
            viewportSize: viewportSize,
            viewportOrigin: sceneContext.viewportOrigin,
            mousePositionInViewport: nil,
            requestPick: sceneContext.pendingPickRequest != nil,
            exposure: 1.0,
            layerMask: .all,
            selectedEntityIds: sceneContext.selectedEntityIds,
            debugFlags: 0,
            isEditorView: !sceneContext.isPlaying
        )
    }

    func handlePickResult(_ result: PickResult) {
        sceneContext.pendingPickRequest = nil
        MCLog.trace("PICK_RESULT pickedId=\(result.pickedId)")
        guard let scene = sceneContext.activeScene else { return }
        if result.pickedId == 0 {
            sceneContext.selectedEntityIds = []
            sceneContext.lastPickResult = nil
            SceneManager.setSelectedEntityId("")
            ImGuiBridge.setSelectedEntityId("")
            return
        }
        if let entity = PickingSystem.entity(for: result.pickedId),
           let hit = scene.raycast(hitEntity: entity, mask: result.mask) {
            sceneContext.selectedEntityIds = [hit.id]
            sceneContext.lastPickResult = hit.id
            SceneManager.setSelectedEntityId(hit.id.uuidString)
            ImGuiBridge.setSelectedEntityId(hit.id.uuidString)
        } else {
            sceneContext.selectedEntityIds = []
            sceneContext.lastPickResult = nil
            SceneManager.setSelectedEntityId("")
            ImGuiBridge.setSelectedEntityId("")
        }
    }

    private func shouldCaptureEvent(_ event: Event) -> Bool {
        let wantsMouse = ImGuiBridge.wantsCaptureMouse()
        let wantsKeyboard = ImGuiBridge.wantsCaptureKeyboard()
        let viewportHovered = ImGuiBridge.viewportIsHovered()
        let viewportFocused = ImGuiBridge.viewportIsFocused()

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
                                             commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        previewFrameCounter &+= 1
        guard let scene = SceneManager.getEditorScene(),
              let selectedId = SceneManager.selectedEntityUUID(),
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
                    viewportSize: SIMD2<Float>(Float(previewTextureSize.x), Float(previewTextureSize.y))
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
