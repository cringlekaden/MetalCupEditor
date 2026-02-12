import MetalKit
import MetalCupEngine
#if canImport(GameController)
import GameController
#endif

final class ImGuiLayer: Layer {
    
    nonisolated override init(name: String) {
        super.init(name: name)
    }

    nonisolated override func onUpdate() {
        let viewportSize = ImGuiBridge.viewportContentSize()
        let viewportOrigin = ImGuiBridge.viewportContentOrigin()
        if viewportSize.width > 1, viewportSize.height > 1 {
            SceneManager.updateViewportSize(SIMD2<Float>(Float(viewportSize.width), Float(viewportSize.height)))
            Mouse.SetViewportRect(
                origin: SIMD2<Float>(Float(viewportOrigin.x), Float(viewportOrigin.y)),
                size: SIMD2<Float>(Float(viewportSize.width), Float(viewportSize.height))
            )
        }
        SceneManager.update()
    }

    nonisolated override func onRender(encoder: MTLRenderCommandEncoder) {
        SceneManager.render(renderCommandEncoder: encoder)
    }
    
    nonisolated override func onOverlayRender(view: MTKView, commandBuffer: MTLCommandBuffer) {
        ImGuiBridge.setup(with: view)
        ImGuiBridge.newFrame(with: view, deltaTime: GameTime.DeltaTime)
        let sceneTex = AssetManager.texture(handle: BuiltinAssets.finalColorRender)
        ImGuiBridge.buildUI(withSceneTexture: sceneTex)
        if let rpd = view.currentRenderPassDescriptor {
            ImGuiBridge.render(with: commandBuffer, renderPassDescriptor: rpd)
        }
    }
    
    nonisolated override func onEvent(_ event: Event) {
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
            return wantsMouse && !viewportHovered
        case is KeyPressedEvent, is KeyReleasedEvent:
            return wantsKeyboard && !viewportFocused
        default:
            return false
        }
    }
}
