import MetalKit
import MetalCupEngine
#if canImport(GameController)
import GameController
#endif

final class ImGuiLayer: Layer {
    
    nonisolated override init(name: String) {
        super.init(name: name)
        SceneManager.SetScene(.Sandbox)
    }

    nonisolated override func onUpdate() {
        let viewportSize = ImGuiBridge.viewportContentSize()
        let viewportOrigin = ImGuiBridge.viewportContentOrigin()
        if viewportSize.width > 1, viewportSize.height > 1 {
            SceneManager.UpdateViewportSize(SIMD2<Float>(Float(viewportSize.width), Float(viewportSize.height)))
            Mouse.SetViewportRect(
                origin: SIMD2<Float>(Float(viewportOrigin.x), Float(viewportOrigin.y)),
                size: SIMD2<Float>(Float(viewportSize.width), Float(viewportSize.height))
            )
        }
        SceneManager.Update()
    }

    nonisolated override func onRender(encoder: MTLRenderCommandEncoder) {
        SceneManager.Render(renderCommandEncoder: encoder)
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
        let wantsMouse = ImGuiBridge.wantsCaptureMouse()
        let wantsKeyboard = ImGuiBridge.wantsCaptureKeyboard()
        let viewportHovered = ImGuiBridge.viewportIsHovered()
        let viewportFocused = ImGuiBridge.viewportIsFocused()
        switch event {
        case is MouseMovedEvent, is MouseButtonPressedEvent, is MouseButtonReleasedEvent, is MouseScrolledEvent:
            if wantsMouse && !viewportHovered {
                event.handled = true
                return
            }
        case is KeyPressedEvent, is KeyReleasedEvent:
            if wantsKeyboard && !viewportFocused {
                event.handled = true
                return
            }
        default:
            break
        }
        SceneManager.currentScene.onEvent(event)
    }
}
