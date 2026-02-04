//
//  ImGuiBridge.mm
//  MetalCupEditor
//
//  Created by Kaden Cringle on 2/4/26.
//

#import "ImGuiBridge.h"

// ImGui
#import "imgui.h"
#import "backends/imgui_impl_osx.h"
#import "backends/imgui_impl_metal.h"

static bool g_ImGuiInitialized = false;

@implementation ImGuiBridge

+ (void)setupWithView:(MTKView *)view {
    if (g_ImGuiInitialized) { return; }
    g_ImGuiInitialized = true;

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO();
    (void)io;

    // Nice defaults
    io.ConfigFlags |= ImGuiConfigFlags_DockingEnable;
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;

    ImGui::StyleColorsDark();

    // Backends
    // OS X backend needs the NSView
    ImGui_ImplOSX_Init(view);
    // Metal backend now only needs the device
    ImGui_ImplMetal_Init(view.device);
}

+ (void)newFrameWithView:(MTKView *)view deltaTime:(float)dt {
    if (!g_ImGuiInitialized) { [self setupWithView:view]; }

    ImGuiIO& io = ImGui::GetIO();
    io.DeltaTime = (dt > 0.0f) ? dt : (1.0f / 60.0f);

    ImGui_ImplMetal_NewFrame(view.currentRenderPassDescriptor);
    ImGui_ImplOSX_NewFrame(view);
    ImGui::NewFrame();
}

+ (void)buildUIWithSceneTexture:(id<MTLTexture> _Nullable)sceneTexture {
    // Dockspace host window (fills main viewport)
    ImGuiViewport* vp = ImGui::GetMainViewport();
    ImGui::SetNextWindowPos(vp->Pos);
    ImGui::SetNextWindowSize(vp->Size);
    ImGui::SetNextWindowViewport(vp->ID);

    ImGuiWindowFlags hostFlags =
        ImGuiWindowFlags_NoTitleBar |
        ImGuiWindowFlags_NoCollapse |
        ImGuiWindowFlags_NoResize |
        ImGuiWindowFlags_NoMove |
        ImGuiWindowFlags_NoBringToFrontOnFocus |
        ImGuiWindowFlags_NoNavFocus |
        ImGuiWindowFlags_MenuBar;

    ImGui::PushStyleVar(ImGuiStyleVar_WindowRounding, 0.0f);
    ImGui::PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0.0f);
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(0,0));

    ImGui::Begin("DockSpaceHost", nullptr, hostFlags);

    ImGuiID dockspaceId = ImGui::GetID("MainDockspace");
    ImGui::DockSpace(dockspaceId, ImVec2(0,0), ImGuiDockNodeFlags_PassthruCentralNode);

    // Example menu bar
    if (ImGui::BeginMenuBar()) {
        if (ImGui::BeginMenu("File")) {
            ImGui::MenuItem("Quit");
            ImGui::EndMenu();
        }
        ImGui::EndMenuBar();
    }

    ImGui::PopStyleVar(3);

    // --- Panels ---
    ImGui::Begin("Renderer");
    ImGui::Text("ImGui is running.");
    ImGui::Text("Scene texture: %s", sceneTexture ? "bound" : "nil");
    ImGui::End();

    // --- Viewport ---
    ImGui::Begin("Viewport");

    ImVec2 avail = ImGui::GetContentRegionAvail();
    if (sceneTexture && avail.x > 1 && avail.y > 1) {
        // IMPORTANT: UV flip for Metal texture coordinates
        ImVec2 uv0 = ImVec2(0.0f, 0.0f);
        ImVec2 uv1 = ImVec2(1.0f, 1.0f);

        // The Metal backend accepts MTLTexture* as ImTextureID.
        ImGui::Image((ImTextureID)sceneTexture, avail, uv0, uv1);
    } else {
        ImGui::Text("No scene texture (yet).");
    }

    ImGui::End();

    ImGui::End(); // DockSpaceHost
}

+ (void)renderWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
            renderPassDescriptor:(MTLRenderPassDescriptor *)renderPassDescriptor {

    ImGui::Render();

    id<MTLRenderCommandEncoder> encoder =
        [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    if (!encoder) { return; }

    // Draw ImGui into the active render target
    ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), commandBuffer, encoder);

    [encoder endEncoding];
}

@end

