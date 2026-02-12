#import "RendererPanel.h"

#import "RendererSettingsBridge.h"
#import "EditorUIConstants.h"
#import "imgui.h"

void ImGuiRendererPanelDraw(bool *isOpen) {
    ImGui::Begin("Renderer", isOpen);
    ImGui::BeginChild("RendererScroll", ImVec2(0, 0), false, ImGuiWindowFlags_AlwaysVerticalScrollbar);

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
        if (ImGui::DragFloat("Threshold", &threshold, EditorUIConstants::kBloomThresholdStep, EditorUIConstants::kBloomThresholdMin, EditorUIConstants::kBloomThresholdMax, "%.3f")) {
            MCERendererSetBloomThreshold(threshold);
        }
        if (ImGui::IsItemHovered() && ImGui::IsMouseDoubleClicked(0)) {
            MCERendererSetBloomThreshold(EditorUIConstants::kDefaultBloomThreshold);
        }
        float knee = MCERendererGetBloomKnee();
        if (ImGui::DragFloat("Knee", &knee, EditorUIConstants::kBloomKneeStep, EditorUIConstants::kBloomKneeMin, EditorUIConstants::kBloomKneeMax, "%.3f")) {
            MCERendererSetBloomKnee(knee);
        }
        if (ImGui::IsItemHovered() && ImGui::IsMouseDoubleClicked(0)) {
            MCERendererSetBloomKnee(EditorUIConstants::kDefaultBloomKnee);
        }
        float intensity = MCERendererGetBloomIntensity();
        if (ImGui::DragFloat("Intensity", &intensity, EditorUIConstants::kBloomIntensityStep, EditorUIConstants::kBloomIntensityMin, EditorUIConstants::kBloomIntensityMax, "%.3f")) {
            MCERendererSetBloomIntensity(intensity);
        }
        if (ImGui::IsItemHovered() && ImGui::IsMouseDoubleClicked(0)) {
            MCERendererSetBloomIntensity(EditorUIConstants::kDefaultBloomIntensity);
        }
        float upsampleScale = MCERendererGetBloomUpsampleScale();
        if (ImGui::DragFloat("Upsample Scale", &upsampleScale, EditorUIConstants::kBloomUpsampleStep, EditorUIConstants::kBloomUpsampleMin, EditorUIConstants::kBloomUpsampleMax, "%.3f")) {
            MCERendererSetBloomUpsampleScale(upsampleScale);
        }
        if (ImGui::IsItemHovered() && ImGui::IsMouseDoubleClicked(0)) {
            MCERendererSetBloomUpsampleScale(EditorUIConstants::kDefaultBloomUpsample);
        }
        float dirtIntensity = MCERendererGetBloomDirtIntensity();
        if (ImGui::DragFloat("Dirt Intensity", &dirtIntensity, EditorUIConstants::kBloomDirtStep, EditorUIConstants::kBloomDirtMin, EditorUIConstants::kBloomDirtMax, "%.3f")) {
            MCERendererSetBloomDirtIntensity(dirtIntensity);
        }
        if (ImGui::IsItemHovered() && ImGui::IsMouseDoubleClicked(0)) {
            MCERendererSetBloomDirtIntensity(EditorUIConstants::kDefaultBloomDirt);
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
        const char* tonemapItems[] = { "None", "Reinhard", "ACES", "MetalCup Custom" };
        int tonemap = static_cast<int>(MCERendererGetTonemap());
        if (ImGui::Combo("Tonemap##Mode", &tonemap, tonemapItems, IM_ARRAYSIZE(tonemapItems))) {
            MCERendererSetTonemap(static_cast<uint32_t>(tonemap));
        }
        float exposure = MCERendererGetExposure();
        if (ImGui::DragFloat("Exposure", &exposure, EditorUIConstants::kExposureStep, EditorUIConstants::kExposureMin, EditorUIConstants::kExposureMax, "%.3f")) {
            MCERendererSetExposure(exposure);
        }
        if (ImGui::IsItemHovered() && ImGui::IsMouseDoubleClicked(0)) {
            MCERendererSetExposure(EditorUIConstants::kDefaultExposure);
        }
        float gamma = MCERendererGetGamma();
        if (ImGui::DragFloat("Gamma", &gamma, EditorUIConstants::kGammaStep, EditorUIConstants::kGammaMin, EditorUIConstants::kGammaMax, "%.3f")) {
            MCERendererSetGamma(gamma);
        }
        if (ImGui::IsItemHovered() && ImGui::IsMouseDoubleClicked(0)) {
            MCERendererSetGamma(EditorUIConstants::kDefaultGamma);
        }
    }


    if (ImGui::CollapsingHeader("IBL", ImGuiTreeNodeFlags_DefaultOpen)) {
        bool iblEnabled = MCERendererGetIBLEnabled() != 0;
        if (ImGui::Checkbox("Enable IBL", &iblEnabled)) {
            MCERendererSetIBLEnabled(iblEnabled ? 1 : 0);
        }
        float iblIntensity = MCERendererGetIBLIntensity();
        if (ImGui::DragFloat("IBL Intensity", &iblIntensity, EditorUIConstants::kIBLIntensityStep, EditorUIConstants::kIBLIntensityMin, EditorUIConstants::kIBLIntensityMax, "%.3f")) {
            MCERendererSetIBLIntensity(iblIntensity);
        }
        if (ImGui::IsItemHovered() && ImGui::IsMouseDoubleClicked(0)) {
            MCERendererSetIBLIntensity(EditorUIConstants::kDefaultIBLIntensity);
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

    ImGui::EndChild();
    ImGui::End();
}
