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
#import <Cocoa/Cocoa.h>

static bool g_ImGuiInitialized = false;
static bool g_ViewportHovered = false;
static bool g_ViewportFocused = false;
static CGSize g_ViewportContentSize = {0, 0};
static CGPoint g_ViewportContentOrigin = {0, 0};
static bool g_ShowRendererPanel = true;

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
            if (ImGui::MenuItem("Quit")) {
                [NSApp terminate:nil];
            }
            ImGui::EndMenu();
        }
        ImGui::EndMenuBar();
    }

    ImGui::PopStyleVar(3);

    // --- Panels ---
    bool rendererOpen = g_ShowRendererPanel;
    ImGui::Begin("Renderer", &rendererOpen);

    if (ImGui::CollapsingHeader("Bloom", ImGuiTreeNodeFlags_DefaultOpen)) {
        bool bloomEnabled = MCERendererGetBloomEnabled() != 0;
        if (ImGui::Checkbox("Enable Bloom", &bloomEnabled)) {
            MCERendererSetBloomEnabled(bloomEnabled ? 1 : 0);
        }
        ImGui::TextUnformatted("Multi-scale bloom (mip chain + per-mip blur)");

        const char* qualityItems[] = { "Low", "Medium", "High", "Ultra" };
        static int qualityIndex = 2;
        if (ImGui::Combo("Quality Preset", &qualityIndex, qualityItems, IM_ARRAYSIZE(qualityItems))) {
            switch (qualityIndex) {
            case 0: // Low
                MCERendererSetHalfResBloom(1);
                MCERendererSetBlurPasses(2);
                MCERendererSetBloomUpsampleScale(0.8f);
                MCERendererSetBloomMaxMips(3);
                break;
            case 1: // Medium
                MCERendererSetHalfResBloom(1);
                MCERendererSetBlurPasses(3);
                MCERendererSetBloomUpsampleScale(1.0f);
                MCERendererSetBloomMaxMips(4);
                break;
            case 2: // High
                MCERendererSetHalfResBloom(0);
                MCERendererSetBlurPasses(4);
                MCERendererSetBloomUpsampleScale(1.1f);
                MCERendererSetBloomMaxMips(5);
                break;
            case 3: // Ultra
                MCERendererSetHalfResBloom(0);
                MCERendererSetBlurPasses(6);
                MCERendererSetBloomUpsampleScale(1.25f);
                MCERendererSetBloomMaxMips(6);
                break;
            default:
                break;
            }
        }

        float threshold = MCERendererGetBloomThreshold();
        if (ImGui::SliderFloat("Threshold", &threshold, 0.0f, 10.0f)) {
            MCERendererSetBloomThreshold(threshold);
        }
        float knee = MCERendererGetBloomKnee();
        if (ImGui::SliderFloat("Knee", &knee, 0.0f, 1.0f)) {
            MCERendererSetBloomKnee(knee);
        }
        float intensity = MCERendererGetBloomIntensity();
        if (ImGui::SliderFloat("Intensity", &intensity, 0.0f, 3.0f)) {
            MCERendererSetBloomIntensity(intensity);
        }
        float upsampleScale = MCERendererGetBloomUpsampleScale();
        if (ImGui::SliderFloat("Upsample Scale", &upsampleScale, 0.5f, 2.0f)) {
            MCERendererSetBloomUpsampleScale(upsampleScale);
        }
        float dirtIntensity = MCERendererGetBloomDirtIntensity();
        if (ImGui::SliderFloat("Dirt Intensity", &dirtIntensity, 0.0f, 2.0f)) {
            MCERendererSetBloomDirtIntensity(dirtIntensity);
        }
        int blurPasses = static_cast<int>(MCERendererGetBlurPasses());
        if (ImGui::SliderInt("Blur Passes (per mip)", &blurPasses, 0, 8)) {
            MCERendererSetBlurPasses(static_cast<uint32_t>(blurPasses));
        }
        int maxMips = static_cast<int>(MCERendererGetBloomMaxMips());
        if (ImGui::SliderInt("Max Mip Levels", &maxMips, 1, 8)) {
            MCERendererSetBloomMaxMips(static_cast<uint32_t>(maxMips));
        }
        bool halfRes = MCERendererGetHalfResBloom() != 0;
        if (ImGui::Checkbox("Half-Res Bloom", &halfRes)) {
            MCERendererSetHalfResBloom(halfRes ? 1 : 0);
        }
    }

    if (ImGui::CollapsingHeader("Tonemap", ImGuiTreeNodeFlags_DefaultOpen)) {
        const char* tonemapItems[] = { "None", "Reinhard", "ACES", "Hazel" };
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

    if (ImGui::CollapsingHeader("Sky", ImGuiTreeNodeFlags_DefaultOpen)) {
        bool skyEnabled = MCESkyGetEnabled() != 0;
        if (ImGui::Checkbox("Enabled", &skyEnabled)) {
            MCESkySetEnabled(skyEnabled ? 1 : 0);
        }

        const char* skyModes[] = { "HDRI", "Procedural" };
        int skyMode = static_cast<int>(MCESkyGetMode());
        if (ImGui::Combo("Mode", &skyMode, skyModes, IM_ARRAYSIZE(skyModes))) {
            MCESkySetMode(static_cast<uint32_t>(skyMode));
        }

        static bool skyInit = false;
        static float skyIntensity = 1.0f;
        static float skyTurbidity = 2.0f;
        static float skyAzimuth = 0.0f;
        static float skyElevation = 30.0f;
        static float skyTint[3] = {1.0f, 1.0f, 1.0f};

        if (!skyInit) {
            skyIntensity = MCESkyGetIntensity();
            skyTurbidity = MCESkyGetTurbidity();
            skyAzimuth = MCESkyGetAzimuthDegrees();
            skyElevation = MCESkyGetElevationDegrees();
            MCESkyGetTint(&skyTint[0], &skyTint[1], &skyTint[2]);
            skyInit = true;
        }

        if (ImGui::SliderFloat("Intensity##Sky", &skyIntensity, 0.0f, 10.0f)) {
            MCESkySetIntensity(skyIntensity);
        }

        if (ImGui::ColorEdit3("Sky Tint", skyTint)) {
            MCESkySetTint(skyTint[0], skyTint[1], skyTint[2]);
        }

        if (skyMode == 1) {
            if (ImGui::SliderFloat("Turbidity", &skyTurbidity, 1.0f, 10.0f)) {
                MCESkySetTurbidity(skyTurbidity);
            }

            if (ImGui::SliderFloat("Azimuth (deg)", &skyAzimuth, 0.0f, 360.0f)) {
                MCESkySetAzimuthDegrees(skyAzimuth);
            }

            if (ImGui::SliderFloat("Elevation (deg)", &skyElevation, 0.0f, 90.0f)) {
                MCESkySetElevationDegrees(skyElevation);
            }
        } else {
            ImGui::TextUnformatted("HDRI asset picker not hooked up yet.");
        }

        bool realtime = MCESkyGetRealtimeUpdate() != 0;
        if (ImGui::Checkbox("Real-time Update", &realtime)) {
            MCESkySetRealtimeUpdate(realtime ? 1 : 0);
        }
        if (ImGui::Button("Regenerate")) {
            MCESkyRegenerate();
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

    if (ImGui::CollapsingHeader("Materials", ImGuiTreeNodeFlags_DefaultOpen)) {
        bool globalFlip = MCERendererGetNormalFlipYGlobal() != 0;
        if (ImGui::Checkbox("Global Normal Flip (Y)", &globalFlip)) {
            MCERendererSetNormalFlipYGlobal(globalFlip ? 1 : 0);
        }
    }

    if (ImGui::CollapsingHeader("Performance", ImGuiTreeNodeFlags_DefaultOpen)) {
        bool disableSpecAA = MCERendererGetDisableSpecularAA() != 0;
        if (ImGui::Checkbox("Disable Specular AA", &disableSpecAA)) {
            MCERendererSetDisableSpecularAA(disableSpecAA ? 1 : 0);
        }
        bool disableClearcoat = MCERendererGetDisableClearcoat() != 0;
        if (ImGui::Checkbox("Disable Clearcoat", &disableClearcoat)) {
            MCERendererSetDisableClearcoat(disableClearcoat ? 1 : 0);
        }
        bool disableSheen = MCERendererGetDisableSheen() != 0;
        if (ImGui::Checkbox("Disable Sheen", &disableSheen)) {
            MCERendererSetDisableSheen(disableSheen ? 1 : 0);
        }
        bool skipSpecIBL = MCERendererGetSkipSpecIBLHighRoughness() != 0;
        if (ImGui::Checkbox("Skip Spec IBL (Rough>0.9)", &skipSpecIBL)) {
            MCERendererSetSkipSpecIBLHighRoughness(skipSpecIBL ? 1 : 0);
        }
    }

    if (ImGui::CollapsingHeader("Profiling", ImGuiTreeNodeFlags_DefaultOpen)) {
        float frameMs = MCERendererGetFrameMs();
        float updateMs = MCERendererGetUpdateMs();
        float sceneMs = MCERendererGetSceneMs();
        float renderMs = MCERendererGetRenderMs();
        float bloomMs = MCERendererGetBloomMs();
        float bloomExtractMs = MCERendererGetBloomExtractMs();
        float bloomDownsampleMs = MCERendererGetBloomDownsampleMs();
        float bloomBlurMs = MCERendererGetBloomBlurMs();
        float compositeMs = MCERendererGetCompositeMs();
        float overlaysMs = MCERendererGetOverlaysMs();
        float presentMs = MCERendererGetPresentMs();
        float gpuMs = MCERendererGetGpuMs();

        ImGui::Text("Frame:   %.2f ms", frameMs);
        ImGui::Text("Update:  %.2f ms", updateMs);
        ImGui::Text("Scene:   %.2f ms", sceneMs);
        ImGui::Text("Render:  %.2f ms", renderMs);
        ImGui::Text("Bloom:   %.2f ms", bloomMs);
        ImGui::Text("  - Extract:    %.2f ms", bloomExtractMs);
        ImGui::Text("  - Downsample: %.2f ms", bloomDownsampleMs);
        ImGui::Text("  - Blur:       %.2f ms", bloomBlurMs);
        ImGui::Text("Composite: %.2f ms", compositeMs);
        ImGui::Text("Overlays:  %.2f ms", overlaysMs);
        ImGui::Text("Present:   %.2f ms", presentMs);
        ImGui::Text("GPU:       %.2f ms", gpuMs);
    }

    ImGui::End();

    if (!rendererOpen) {
        g_ShowRendererPanel = false;
        [NSApp terminate:nil];
    }

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
