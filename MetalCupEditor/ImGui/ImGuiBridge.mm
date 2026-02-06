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

#import "RendererSettingsBridge.h"

static bool g_ImGuiInitialized = false;
static bool g_ViewportHovered = false;
static bool g_ViewportFocused = false;
static CGSize g_ViewportContentSize = {0, 0};
static CGPoint g_ViewportContentOrigin = {0, 0};

@implementation ImGuiBridge

+ (void)setupWithView:(MTKView *)view {
    if (g_ImGuiInitialized) { return; }
    g_ImGuiInitialized = true;

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO();
    (void)io;

    // Store ImGui config in Application Support so it persists with or without sandbox.
    NSArray<NSURL *> *appSupport = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory
                                                                          inDomains:NSUserDomainMask];
    NSURL *supportURL = appSupport.firstObject;
    if (supportURL) {
        NSURL *configDir = [supportURL URLByAppendingPathComponent:@"MetalCupEditor" isDirectory:YES];
        [[NSFileManager defaultManager] createDirectoryAtURL:configDir
                                 withIntermediateDirectories:YES
                                                  attributes:nil
                                                       error:nil];
        NSString *iniPath = [[configDir URLByAppendingPathComponent:@"imgui.ini"] path];
        io.IniFilename = strdup(iniPath.UTF8String);
    }

    // Nice defaults
    io.ConfigFlags |= ImGuiConfigFlags_DockingEnable;
    io.ConfigFlags |= ImGuiConfigFlags_ViewportsEnable;
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;

    ImGui::StyleColorsDark();
    ImGuiStyle& style = ImGui::GetStyle();
    if (io.ConfigFlags & ImGuiConfigFlags_ViewportsEnable) {
        style.WindowRounding = 0.0f;
        style.Colors[ImGuiCol_WindowBg].w = 1.0f;
    }

    // Backends
    // OS X backend needs the NSView
    ImGui_ImplOSX_Init(view);
    ImGui_ImplOSX_SetKeyboardInputEnabled(view);
    // Metal backend now only needs the device
    ImGui_ImplMetal_Init(view.device);
}

+ (void)newFrameWithView:(MTKView *)view deltaTime:(float)dt {
    if (!g_ImGuiInitialized) { [self setupWithView:view]; }

    ImGuiIO& io = ImGui::GetIO();
    io.DeltaTime = (dt > 0.0f) ? dt : (1.0f / 60.0f);

    ImGui_ImplMetal_NewFrame(view.currentRenderPassDescriptor);
    ImGui_ImplOSX_NewFrame(view);
    ImGui_ImplOSX_SetKeyboardInputEnabled(view);
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

    if (ImGui::CollapsingHeader("Bloom", ImGuiTreeNodeFlags_DefaultOpen)) {
        bool bloomEnabled = MCERendererGetBloomEnabled() != 0;
        if (ImGui::Checkbox("Enable Bloom", &bloomEnabled)) {
            MCERendererSetBloomEnabled(bloomEnabled ? 1 : 0);
        }
        float threshold = MCERendererGetBloomThreshold();
        if (ImGui::SliderFloat("Threshold", &threshold, 0.0f, 5.0f)) {
            MCERendererSetBloomThreshold(threshold);
        }
        float knee = MCERendererGetBloomKnee();
        if (ImGui::SliderFloat("Knee", &knee, 0.0f, 1.0f)) {
            MCERendererSetBloomKnee(knee);
        }
        float intensity = MCERendererGetBloomIntensity();
        if (ImGui::SliderFloat("Intensity", &intensity, 0.0f, 2.0f)) {
            MCERendererSetBloomIntensity(intensity);
        }
        int blurPasses = static_cast<int>(MCERendererGetBlurPasses());
        if (ImGui::SliderInt("Blur Passes", &blurPasses, 0, 8)) {
            MCERendererSetBlurPasses(static_cast<uint32_t>(blurPasses));
        }
        bool halfRes = MCERendererGetHalfResBloom() != 0;
        if (ImGui::Checkbox("Half-Res Bloom", &halfRes)) {
            MCERendererSetHalfResBloom(halfRes ? 1 : 0);
        }
    }

    if (ImGui::CollapsingHeader("Tonemap", ImGuiTreeNodeFlags_DefaultOpen)) {
        const char* tonemapItems[] = { "None", "Reinhard", "ACES" };
        int tonemap = static_cast<int>(MCERendererGetTonemap());
        if (ImGui::Combo("Tonemap##Mode", &tonemap, tonemapItems, IM_ARRAYSIZE(tonemapItems))) {
            MCERendererSetTonemap(static_cast<uint32_t>(tonemap));
        }
        float exposure = MCERendererGetExposure();
        if (ImGui::SliderFloat("Exposure", &exposure, 0.1f, 4.0f)) {
            MCERendererSetExposure(exposure);
        }
        float gamma = MCERendererGetGamma();
        if (ImGui::SliderFloat("Gamma", &gamma, 1.8f, 2.4f)) {
            MCERendererSetGamma(gamma);
        }
    }

    if (ImGui::CollapsingHeader("IBL", ImGuiTreeNodeFlags_DefaultOpen)) {
        bool iblEnabled = MCERendererGetIBLEnabled() != 0;
        if (ImGui::Checkbox("Enable IBL", &iblEnabled)) {
            MCERendererSetIBLEnabled(iblEnabled ? 1 : 0);
        }
        float iblIntensity = MCERendererGetIBLIntensity();
        if (ImGui::SliderFloat("IBL Intensity", &iblIntensity, 0.0f, 3.0f)) {
            MCERendererSetIBLIntensity(iblIntensity);
        }
    }

    if (ImGui::CollapsingHeader("Debug")) {
        bool showAlbedo = MCERendererGetShowAlbedo() != 0;
        if (ImGui::Checkbox("Show Albedo", &showAlbedo)) {
            MCERendererSetShowAlbedo(showAlbedo ? 1 : 0);
        }
        bool showNormals = MCERendererGetShowNormals() != 0;
        if (ImGui::Checkbox("Show Normals", &showNormals)) {
            MCERendererSetShowNormals(showNormals ? 1 : 0);
        }
        bool showRoughness = MCERendererGetShowRoughness() != 0;
        if (ImGui::Checkbox("Show Roughness", &showRoughness)) {
            MCERendererSetShowRoughness(showRoughness ? 1 : 0);
        }
        bool showMetallic = MCERendererGetShowMetallic() != 0;
        if (ImGui::Checkbox("Show Metallic", &showMetallic)) {
            MCERendererSetShowMetallic(showMetallic ? 1 : 0);
        }
        bool showEmissive = MCERendererGetShowEmissive() != 0;
        if (ImGui::Checkbox("Show Emissive", &showEmissive)) {
            MCERendererSetShowEmissive(showEmissive ? 1 : 0);
        }
        bool showBloom = MCERendererGetShowBloom() != 0;
        if (ImGui::Checkbox("Show Bloom", &showBloom)) {
            MCERendererSetShowBloom(showBloom ? 1 : 0);
        }
    }

    if (ImGui::CollapsingHeader("Profiling", ImGuiTreeNodeFlags_DefaultOpen)) {
        ImGui::Text("Frame:  %.2f ms", MCERendererGetFrameMs());
        ImGui::Text("Update: %.2f ms", MCERendererGetUpdateMs());
        ImGui::Text("Render: %.2f ms", MCERendererGetRenderMs());
        ImGui::Text("Bloom:  %.2f ms", MCERendererGetBloomMs());
        ImGui::Text("Present:%.2f ms", MCERendererGetPresentMs());
        ImGui::Text("GPU:    %.2f ms", MCERendererGetGpuMs());
    }

    ImGui::End();

    // --- Viewport ---
    ImGui::Begin("Viewport");

    ImVec2 avail = ImGui::GetContentRegionAvail();
    g_ViewportContentSize = CGSizeMake(avail.x, avail.y);
    g_ViewportHovered = ImGui::IsWindowHovered(ImGuiHoveredFlags_RootAndChildWindows);
    g_ViewportFocused = ImGui::IsWindowFocused(ImGuiFocusedFlags_RootAndChildWindows);
    ImVec2 contentMin = ImGui::GetWindowContentRegionMin();
    ImVec2 windowPos = ImGui::GetWindowPos();
    g_ViewportContentOrigin = CGPointMake(windowPos.x + contentMin.x, windowPos.y + contentMin.y);
    if (sceneTexture && avail.x > 1 && avail.y > 1) {
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

    ImGuiIO& io = ImGui::GetIO();
    if (io.ConfigFlags & ImGuiConfigFlags_ViewportsEnable) {
        ImGui::UpdatePlatformWindows();
        ImGui::RenderPlatformWindowsDefault();
    }
}

+ (bool)wantsCaptureMouse {
    if (!g_ImGuiInitialized) { return false; }
    ImGuiIO& io = ImGui::GetIO();
    return io.WantCaptureMouse;
}

+ (bool)wantsCaptureKeyboard {
    if (!g_ImGuiInitialized) { return false; }
    ImGuiIO& io = ImGui::GetIO();
    return io.WantCaptureKeyboard;
}

+ (bool)viewportIsHovered {
    return g_ViewportHovered;
}

+ (bool)viewportIsFocused {
    return g_ViewportFocused;
}

+ (CGSize)viewportContentSize {
    return g_ViewportContentSize;
}

+ (CGPoint)viewportContentOrigin {
    return g_ViewportContentOrigin;
}

@end
