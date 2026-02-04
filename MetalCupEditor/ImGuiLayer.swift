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
        SceneManager.Update()
    }

    nonisolated override func onRender(encoder: MTLRenderCommandEncoder) {
        SceneManager.Render(renderCommandEncoder: encoder)
    }
    
    nonisolated override func onOverlayRender(view: MTKView, commandBuffer: MTLCommandBuffer) {
        ImGuiBridge.setup(with: view)
        ImGuiBridge.newFrame(with: view, deltaTime: GameTime.DeltaTime)
        let sceneTex = Assets.Textures[.FinalColorRender]
        ImGuiBridge.buildUI(withSceneTexture: sceneTex)
        if let rpd = view.currentRenderPassDescriptor {
            ImGuiBridge.render(with: commandBuffer, renderPassDescriptor: rpd)
        }
    }
    
    nonisolated override func onEvent(_ event: Event) {
        SceneManager.currentScene.onEvent(event)
    }
}

