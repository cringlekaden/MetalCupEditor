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
        DebugDraw.beginFrame()
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
            Renderer.activeRenderer?.inputAccumulator?.setViewportRect(origin: origin, size: size)
        }
        sceneContext.viewportOrigin = SIMD2<Float>(Float(viewportOrigin.x), Float(viewportOrigin.y))
        sceneContext.viewportSize = SIMD2<Float>(Float(viewportSize.width), Float(viewportSize.height))
        context.editorSceneController.update(frame: frame)
        if !context.editorSceneController.isPlaying,
           let scene = sceneContext.activeScene {
            DebugDraw.submitGridXZ(SceneRenderer.gridParams(scene: scene))
        }
        DebugDraw.endFrame()

        if let selected = context.editorSceneController.selectedEntityUUID() {
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
            context.editorSceneController.setSelectedEntityId("")
            imguiBridge.setSelectedEntityId("")
        } else if let selectedId = sceneContext.selectedEntityIds.first {
            context.editorSceneController.setSelectedEntityId(selectedId.uuidString)
            imguiBridge.setSelectedEntityId(selectedId.uuidString)
        } else {
            context.editorSceneController.setSelectedEntityId("")
            imguiBridge.setSelectedEntityId("")
        }
    }

    nonisolated override func onRender(encoder: MTLRenderCommandEncoder, frameContext: RendererFrameContext) {
        sceneContext.activeScene?.onRender(encoder: encoder, frameContext: frameContext)
    }
    
    nonisolated override func onOverlayRender(view: MTKView, commandBuffer: MTLCommandBuffer, frameContext: RendererFrameContext) {
        imguiBridge.setup(with: view)
        let deltaTime = lastFrameTime?.deltaTime ?? 0.0
        imguiBridge.newFrame(with: view, deltaTime: deltaTime)
        let sceneTex = AssetManager.texture(handle: BuiltinAssets.finalColorRender)
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
                let pickTexture = AssetManager.texture(handle: BuiltinAssets.pickIdRender)
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
                        PickingSystem.requestPick(pixel: SIMD2<Int>(clampedX, clampedY), mask: .all)
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
            let fallback = (Renderer.DrawableSize.x > 1 && Renderer.DrawableSize.y > 1)
                ? Renderer.DrawableSize
                : Renderer.ViewportSize
            return SIMD2<Float>(max(1, fallback.x), max(1, fallback.y))
        }()
        let activeScene = sceneContext.activeScene
        let matrices = activeScene.map { SceneRenderer.cameraMatrices(scene: $0) }
        let cameraPosition = activeScene.map { SceneRenderer.cameraPosition(scene: $0) } ?? .zero
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
        guard let scene = sceneContext.activeScene else { return }
        if result.pickedId == 0 {
            sceneContext.selectedEntityIds = []
            sceneContext.lastPickResult = nil
            context.editorSceneController.setSelectedEntityId("")
            imguiBridge.setSelectedEntityId("")
            return
        }
        if let entity = PickingSystem.entity(for: result.pickedId),
           let hit = scene.raycast(hitEntity: entity, mask: result.mask) {
            sceneContext.selectedEntityIds = [hit.id]
            sceneContext.lastPickResult = hit.id
            context.editorSceneController.setSelectedEntityId(hit.id.uuidString)
            imguiBridge.setSelectedEntityId(hit.id.uuidString)
        } else {
            sceneContext.selectedEntityIds = []
            sceneContext.lastPickResult = nil
            context.editorSceneController.setSelectedEntityId("")
            imguiBridge.setSelectedEntityId("")
        }
    }

    private func shouldCaptureEvent(_ event: Event) -> Bool {
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
