// RendererPanel.mm
// Defines the ImGui Renderer panel rendering and interaction logic.
// Created by Kaden Cringle.

#import "RendererPanel.h"

#import "../../EditorCore/Bridge/RendererSettingsBridge.h"
#import "../Widgets/UIConstants.h"
#import "../Widgets/UIWidgets.h"
#import "../../ImGui/imgui.h"
#include <cmath>

namespace {
    struct BloomPreset {
        const char *label;
        uint32_t halfRes;
        uint32_t blurPasses;
        float upsampleScale;
        uint32_t maxMips;
    };

    const BloomPreset kBloomPresets[] = {
        {"Low", 1, 2, 0.8f, 3},
        {"Medium", 1, 3, 1.0f, 4},
        {"High", 0, 4, 1.1f, 5},
        {"Ultra", 0, 6, 1.25f, 6}
    };

    bool NearlyEqual(float a, float b, float epsilon = 0.01f) {
        return fabsf(a - b) <= epsilon;
    }

    int ResolveBloomPresetIndex() {
        const uint32_t halfRes = MCERendererGetHalfResBloom();
        const uint32_t blurPasses = MCERendererGetBlurPasses();
        const uint32_t maxMips = MCERendererGetBloomMaxMips();
        const float upsampleScale = MCERendererGetBloomUpsampleScale();
        for (int i = 0; i < static_cast<int>(IM_ARRAYSIZE(kBloomPresets)); ++i) {
            const BloomPreset &preset = kBloomPresets[i];
            if (preset.halfRes == halfRes &&
                preset.blurPasses == blurPasses &&
                preset.maxMips == maxMips &&
                NearlyEqual(preset.upsampleScale, upsampleScale)) {
                return i + 1;
            }
        }
        return 0;
    }

    void ApplyBloomPreset(int presetIndex) {
        if (presetIndex <= 0) { return; }
        const BloomPreset &preset = kBloomPresets[presetIndex - 1];
        MCERendererSetHalfResBloom(preset.halfRes);
        MCERendererSetBlurPasses(preset.blurPasses);
        MCERendererSetBloomUpsampleScale(preset.upsampleScale);
        MCERendererSetBloomMaxMips(preset.maxMips);
    }

}

void ImGuiRendererPanelDraw(bool *isOpen) {
    if (!isOpen || !*isOpen) { return; }
    if (!EditorUI::BeginPanel("Renderer", isOpen)) {
        EditorUI::EndPanel();
        return;
    }
    ImGui::BeginChild("RendererScroll", ImVec2(0, 0), false, ImGuiWindowFlags_AlwaysVerticalScrollbar);

    bool bloomOpen = EditorUI::BeginSection("Bloom", "Renderer.Bloom", true);
    if (bloomOpen) {
        if (EditorUI::BeginPropertyTable("BloomTable")) {
            bool bloomEnabled = MCERendererGetBloomEnabled() != 0;
            if (EditorUI::PropertyBool("Enable Bloom", &bloomEnabled)) {
                MCERendererSetBloomEnabled(bloomEnabled ? 1 : 0);
            }

            const char* qualityItems[] = { "Custom", "Low", "Medium", "High", "Ultra" };
            int qualityIndex = ResolveBloomPresetIndex();
            if (EditorUI::PropertyCombo("Quality Preset", &qualityIndex, qualityItems, IM_ARRAYSIZE(qualityItems))) {
                ApplyBloomPreset(qualityIndex);
            }

            float threshold = MCERendererGetBloomThreshold();
            if (EditorUI::PropertyFloat("Threshold", &threshold, EditorUIConstants::kBloomThresholdStep,
                                        EditorUIConstants::kBloomThresholdMin, EditorUIConstants::kBloomThresholdMax, "%.3f", true, true, EditorUIConstants::kDefaultBloomThreshold)) {
                MCERendererSetBloomThreshold(threshold);
            }
            float knee = MCERendererGetBloomKnee();
            if (EditorUI::PropertyFloat("Knee", &knee, EditorUIConstants::kBloomKneeStep,
                                        EditorUIConstants::kBloomKneeMin, EditorUIConstants::kBloomKneeMax, "%.3f", true, true, EditorUIConstants::kDefaultBloomKnee)) {
                MCERendererSetBloomKnee(knee);
            }
            float intensity = MCERendererGetBloomIntensity();
            if (EditorUI::PropertyFloat("Intensity", &intensity, EditorUIConstants::kBloomIntensityStep,
                                        EditorUIConstants::kBloomIntensityMin, EditorUIConstants::kBloomIntensityMax, "%.3f", true, true, EditorUIConstants::kDefaultBloomIntensity)) {
                MCERendererSetBloomIntensity(intensity);
            }
            float upsampleScale = MCERendererGetBloomUpsampleScale();
            if (EditorUI::PropertyFloat("Upsample Scale", &upsampleScale, EditorUIConstants::kBloomUpsampleStep,
                                        EditorUIConstants::kBloomUpsampleMin, EditorUIConstants::kBloomUpsampleMax, "%.3f", true, true, EditorUIConstants::kDefaultBloomUpsample)) {
                MCERendererSetBloomUpsampleScale(upsampleScale);
            }
            float dirtIntensity = MCERendererGetBloomDirtIntensity();
            if (EditorUI::PropertyFloat("Dirt Intensity", &dirtIntensity, EditorUIConstants::kBloomDirtStep,
                                        EditorUIConstants::kBloomDirtMin, EditorUIConstants::kBloomDirtMax, "%.3f", true, true, EditorUIConstants::kDefaultBloomDirt)) {
                MCERendererSetBloomDirtIntensity(dirtIntensity);
            }
            int blurPasses = static_cast<int>(MCERendererGetBlurPasses());
            if (EditorUI::PropertyInt("Blur Passes (per mip)", &blurPasses, 0, 8)) {
                MCERendererSetBlurPasses(static_cast<uint32_t>(blurPasses));
            }
            int maxMips = static_cast<int>(MCERendererGetBloomMaxMips());
            if (EditorUI::PropertyInt("Max Mip Levels", &maxMips, 1, 8)) {
                MCERendererSetBloomMaxMips(static_cast<uint32_t>(maxMips));
            }
            bool halfRes = MCERendererGetHalfResBloom() != 0;
            if (EditorUI::PropertyBool("Half-Res Bloom", &halfRes)) {
                MCERendererSetHalfResBloom(halfRes ? 1 : 0);
            }
            EditorUI::EndPropertyTable();
        }
    }

    bool tonemapOpen = EditorUI::BeginSection("Tonemap", "Renderer.Tonemap", true);
    if (tonemapOpen) {
        if (EditorUI::BeginPropertyTable("TonemapTable")) {
            const char* tonemapItems[] = { "None", "Reinhard", "ACES", "MetalCup Custom" };
            int tonemap = static_cast<int>(MCERendererGetTonemap());
            if (EditorUI::PropertyCombo("Tonemap", &tonemap, tonemapItems, IM_ARRAYSIZE(tonemapItems))) {
                MCERendererSetTonemap(static_cast<uint32_t>(tonemap));
            }
            float exposure = MCERendererGetExposure();
            if (EditorUI::PropertyFloat("Exposure", &exposure, EditorUIConstants::kExposureStep,
                                        EditorUIConstants::kExposureMin, EditorUIConstants::kExposureMax, "%.3f", true, true, EditorUIConstants::kDefaultExposure)) {
                MCERendererSetExposure(exposure);
            }
            float gamma = MCERendererGetGamma();
            if (EditorUI::PropertyFloat("Gamma", &gamma, EditorUIConstants::kGammaStep,
                                        EditorUIConstants::kGammaMin, EditorUIConstants::kGammaMax, "%.3f", true, true, EditorUIConstants::kDefaultGamma)) {
                MCERendererSetGamma(gamma);
            }
            EditorUI::EndPropertyTable();
        }
    }

    bool outlineOpen = EditorUI::BeginSection("Selection Outline", "Renderer.Outline", true);
    if (outlineOpen) {
        if (EditorUI::BeginPropertyTable("OutlineTable")) {
            bool outlineEnabled = MCERendererGetOutlineEnabled() != 0;
            if (EditorUI::PropertyBool("Enable Outline", &outlineEnabled)) {
                MCERendererSetOutlineEnabled(outlineEnabled ? 1 : 0);
            }
            int thickness = static_cast<int>(MCERendererGetOutlineThickness());
            if (EditorUI::PropertyInt("Thickness (px)", &thickness, 1, 4)) {
                MCERendererSetOutlineThickness(static_cast<uint32_t>(thickness));
            }
            float opacity = MCERendererGetOutlineOpacity();
            if (EditorUI::PropertyFloat("Opacity", &opacity, EditorUIConstants::kOutlineOpacityStep,
                                        EditorUIConstants::kOutlineOpacityMin, EditorUIConstants::kOutlineOpacityMax, "%.2f", true, true, EditorUIConstants::kDefaultOutlineOpacity)) {
                MCERendererSetOutlineOpacity(opacity);
            }
            float outlineColor[3];
            MCERendererGetOutlineColor(&outlineColor[0], &outlineColor[1], &outlineColor[2]);
            if (EditorUI::PropertyColor3("Color", outlineColor, EditorUIConstants::kDefaultOutlineColor, true)) {
                MCERendererSetOutlineColor(outlineColor[0], outlineColor[1], outlineColor[2]);
            }
            EditorUI::EndPropertyTable();
        }
    }

    bool gridOpen = EditorUI::BeginSection("Viewport Grid", "Renderer.Grid", true);
    if (gridOpen) {
        if (EditorUI::BeginPropertyTable("GridTable")) {
            bool gridEnabled = MCERendererGetGridEnabled() != 0;
            if (EditorUI::PropertyBool("Enable Grid", &gridEnabled)) {
                MCERendererSetGridEnabled(gridEnabled ? 1 : 0);
            }
            float gridOpacity = MCERendererGetGridOpacity();
            if (EditorUI::PropertyFloat("Opacity", &gridOpacity, EditorUIConstants::kGridOpacityStep,
                                        EditorUIConstants::kGridOpacityMin, EditorUIConstants::kGridOpacityMax, "%.2f", true, true, EditorUIConstants::kDefaultGridOpacity)) {
                MCERendererSetGridOpacity(gridOpacity);
            }
            float gridFade = MCERendererGetGridFadeDistance();
            if (EditorUI::PropertyFloat("Fade Distance", &gridFade, EditorUIConstants::kGridFadeStep,
                                        EditorUIConstants::kGridFadeMin, EditorUIConstants::kGridFadeMax, "%.1f", true, true, EditorUIConstants::kDefaultGridFadeDistance)) {
                MCERendererSetGridFadeDistance(gridFade);
            }
            float gridMajor = MCERendererGetGridMajorLineEvery();
            if (EditorUI::PropertyFloat("Major Line Every", &gridMajor, EditorUIConstants::kGridMajorLineStep,
                                        EditorUIConstants::kGridMajorLineMin, EditorUIConstants::kGridMajorLineMax, "%.0f", true, true, EditorUIConstants::kDefaultGridMajorLineEvery)) {
                MCERendererSetGridMajorLineEvery(gridMajor);
            }
            EditorUI::EndPropertyTable();
        }
    }

    bool iblOpen = EditorUI::BeginSection("IBL", "Renderer.IBL", true);
    if (iblOpen) {
        if (EditorUI::BeginPropertyTable("IBLTable")) {
            bool iblEnabled = MCERendererGetIBLEnabled() != 0;
            if (EditorUI::PropertyBool("Enable IBL", &iblEnabled)) {
                MCERendererSetIBLEnabled(iblEnabled ? 1 : 0);
            }
            float iblIntensity = MCERendererGetIBLIntensity();
            if (EditorUI::PropertyFloat("IBL Intensity", &iblIntensity, EditorUIConstants::kIBLIntensityStep,
                                        EditorUIConstants::kIBLIntensityMin, EditorUIConstants::kIBLIntensityMax, "%.3f", true, true, EditorUIConstants::kDefaultIBLIntensity)) {
                MCERendererSetIBLIntensity(iblIntensity);
            }
            const char* iblItems[] = { "Low", "Medium", "High", "Ultra", "Custom" };
            int iblPreset = static_cast<int>(MCERendererGetIBLQualityPreset());
            if (iblPreset < 0 || iblPreset > 4) { iblPreset = 4; }
            if (EditorUI::PropertyCombo("IBL Quality", &iblPreset, iblItems, IM_ARRAYSIZE(iblItems))) {
                MCERendererSetIBLQualityPreset(static_cast<uint32_t>(iblPreset));
            }
            EditorUI::EndPropertyTable();
        }
    }

    bool materialsOpen = EditorUI::BeginSection("Materials", "Renderer.Materials", true);
    if (materialsOpen) {
        if (EditorUI::BeginPropertyTable("MaterialSettingsTable")) {
            bool globalFlip = MCERendererGetNormalFlipYGlobal() != 0;
            if (EditorUI::PropertyBool("Global Normal Flip (Y)", &globalFlip)) {
                MCERendererSetNormalFlipYGlobal(globalFlip ? 1 : 0);
            }
            EditorUI::EndPropertyTable();
        }
    }

    bool performanceOpen = EditorUI::BeginSection("Performance", "Renderer.Performance", true);
    if (performanceOpen) {
        if (EditorUI::BeginPropertyTable("PerformanceTable")) {
            bool disableSpecAA = MCERendererGetDisableSpecularAA() != 0;
            if (EditorUI::PropertyBool("Disable Specular AA", &disableSpecAA)) {
                MCERendererSetDisableSpecularAA(disableSpecAA ? 1 : 0);
            }
            bool disableClearcoat = MCERendererGetDisableClearcoat() != 0;
            if (EditorUI::PropertyBool("Disable Clearcoat", &disableClearcoat)) {
                MCERendererSetDisableClearcoat(disableClearcoat ? 1 : 0);
            }
            bool disableSheen = MCERendererGetDisableSheen() != 0;
            if (EditorUI::PropertyBool("Disable Sheen", &disableSheen)) {
                MCERendererSetDisableSheen(disableSheen ? 1 : 0);
            }
            bool skipSpecIBL = MCERendererGetSkipSpecIBLHighRoughness() != 0;
            if (EditorUI::PropertyBool("Skip Spec IBL (Rough>0.9)", &skipSpecIBL)) {
                MCERendererSetSkipSpecIBLHighRoughness(skipSpecIBL ? 1 : 0);
            }
            EditorUI::EndPropertyTable();
        }
    }

    ImGui::EndChild();
    EditorUI::EndPanel();
}
