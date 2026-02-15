/// ImGuiLayer.swift
/// Defines the editor layer that drives ImGui rendering and input capture.
/// Created by Kaden Cringle.

import MetalKit
import MetalCupEngine
import simd
#if canImport(GameController)
import GameController
#endif

final class ImGuiLayer: Layer {

    private var previewTexture: MTLTexture?
    private var previewDepthTexture: MTLTexture?
    private var previewSelectedEntityId: UUID?
    private var previewLastTransform = TransformComponent()
    private var previewLastCamera = CameraComponent()
    private var previewFrameCounter: UInt64 = 0
    private var previewLastUpdateFrame: UInt64 = 0
    private let previewUpdateInterval: UInt64 = 8
    private let previewTextureSize = SIMD2<Int>(256, 256)
    
    nonisolated override init(name: String) {
        super.init(name: name)
    }

    nonisolated override func onUpdate() {
        let viewportSize = ImGuiBridge.viewportImageSize()
        let viewportOrigin = ImGuiBridge.viewportImageOrigin()
        if viewportSize.width > 1, viewportSize.height > 1 {
            SceneManager.updateViewportSize(SIMD2<Float>(Float(viewportSize.width), Float(viewportSize.height)))
            Mouse.SetViewportRect(
                origin: SIMD2<Float>(Float(viewportOrigin.x), Float(viewportOrigin.y)),
                size: SIMD2<Float>(Float(viewportSize.width), Float(viewportSize.height))
            )
        }
        SceneManager.update()
        if !SceneManager.isPlaying {
            if let result = SceneManager.consumePickResult() {
                switch result {
                case .none:
                    SceneManager.setSelectedEntityId("")
                    ImGuiBridge.setSelectedEntityId("")
                case .entity(let entity):
                    SceneManager.setSelectedEntityId(entity.id.uuidString)
                    ImGuiBridge.setSelectedEntityId(entity.id.uuidString)
                }
            }
        }
    }

    nonisolated override func onRender(encoder: MTLRenderCommandEncoder) {
        SceneManager.render(renderCommandEncoder: encoder)
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
                SceneManager.setSelectedEntityId("")
                ImGuiBridge.setSelectedEntityId("")
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
                    SceneManager.setSelectedEntityId("")
                    ImGuiBridge.setSelectedEntityId("")
                    return
                }
                if textureWidth > 1, textureHeight > 1,
                   viewportImageSize.width > 1, viewportImageSize.height > 1 {
                    let scaleX = textureWidth / Float(viewportImageSize.width)
                    let scaleY = textureHeight / Float(viewportImageSize.height)
                    let x = Int(local.x * scaleX)
                    let y = Int(local.y * scaleY)
                    SceneManager.requestPick(at: SIMD2<Int>(x, y))
                }
            }
        }
        if shouldCaptureEvent(event) {
            event.handled = true
            return
        }
        SceneManager.currentScene.onEvent(event)
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
