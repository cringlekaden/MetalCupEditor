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

    int ResolveBloomPresetIndex(void *context) {
        const uint32_t halfRes = MCERendererGetHalfResBloom(context);
        const uint32_t blurPasses = MCERendererGetBlurPasses(context);
        const uint32_t maxMips = MCERendererGetBloomMaxMips(context);
        const float upsampleScale = MCERendererGetBloomUpsampleScale(context);
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

    void ApplyBloomPreset(void *context, int presetIndex) {
        if (presetIndex <= 0) { return; }
        const BloomPreset &preset = kBloomPresets[presetIndex - 1];
        MCERendererSetHalfResBloom(context, preset.halfRes);
        MCERendererSetBlurPasses(context, preset.blurPasses);
        MCERendererSetBloomUpsampleScale(context, preset.upsampleScale);
        MCERendererSetBloomMaxMips(context, preset.maxMips);
    }

}

void ImGuiRendererPanelDraw(void *context, bool *isOpen) {
    if (!isOpen || !*isOpen) { return; }
    if (!EditorUI::BeginPanel("Renderer", isOpen)) {
        EditorUI::EndPanel();
        return;
    }
    ImGui::BeginChild("RendererScroll", ImVec2(0, 0), false, ImGuiWindowFlags_AlwaysVerticalScrollbar);

    bool bloomOpen = EditorUI::BeginSection(context, "Bloom", "Renderer.Bloom", true);
    if (bloomOpen) {
        if (EditorUI::BeginPropertyTable("BloomTable")) {
            bool bloomEnabled = MCERendererGetBloomEnabled(context) != 0;
            if (EditorUI::PropertyBool("Enable Bloom", &bloomEnabled)) {
                MCERendererSetBloomEnabled(context, bloomEnabled ? 1 : 0);
            }

            const char* qualityItems[] = { "Custom", "Low", "Medium", "High", "Ultra" };
            int qualityIndex = ResolveBloomPresetIndex(context);
            if (EditorUI::PropertyCombo("Quality Preset", &qualityIndex, qualityItems, IM_ARRAYSIZE(qualityItems))) {
                ApplyBloomPreset(context, qualityIndex);
            }

            float threshold = MCERendererGetBloomThreshold(context);
            if (EditorUI::PropertyFloat("Threshold", &threshold, EditorUIConstants::kBloomThresholdStep,
                                        EditorUIConstants::kBloomThresholdMin, EditorUIConstants::kBloomThresholdMax, "%.3f", true, true, EditorUIConstants::kDefaultBloomThreshold)) {
                MCERendererSetBloomThreshold(context, threshold);
            }
            float knee = MCERendererGetBloomKnee(context);
            if (EditorUI::PropertyFloat("Knee", &knee, EditorUIConstants::kBloomKneeStep,
                                        EditorUIConstants::kBloomKneeMin, EditorUIConstants::kBloomKneeMax, "%.3f", true, true, EditorUIConstants::kDefaultBloomKnee)) {
                MCERendererSetBloomKnee(context, knee);
            }
            float intensity = MCERendererGetBloomIntensity(context);
            if (EditorUI::PropertyFloat("Intensity", &intensity, EditorUIConstants::kBloomIntensityStep,
                                        EditorUIConstants::kBloomIntensityMin, EditorUIConstants::kBloomIntensityMax, "%.3f", true, true, EditorUIConstants::kDefaultBloomIntensity)) {
                MCERendererSetBloomIntensity(context, intensity);
            }
            float upsampleScale = MCERendererGetBloomUpsampleScale(context);
            if (EditorUI::PropertyFloat("Upsample Scale", &upsampleScale, EditorUIConstants::kBloomUpsampleStep,
                                        EditorUIConstants::kBloomUpsampleMin, EditorUIConstants::kBloomUpsampleMax, "%.3f", true, true, EditorUIConstants::kDefaultBloomUpsample)) {
                MCERendererSetBloomUpsampleScale(context, upsampleScale);
            }
            float dirtIntensity = MCERendererGetBloomDirtIntensity(context);
            if (EditorUI::PropertyFloat("Dirt Intensity", &dirtIntensity, EditorUIConstants::kBloomDirtStep,
                                        EditorUIConstants::kBloomDirtMin, EditorUIConstants::kBloomDirtMax, "%.3f", true, true, EditorUIConstants::kDefaultBloomDirt)) {
                MCERendererSetBloomDirtIntensity(context, dirtIntensity);
            }
            int blurPasses = static_cast<int>(MCERendererGetBlurPasses(context));
            if (EditorUI::PropertyInt("Blur Passes (per mip)", &blurPasses, 0, 8)) {
                MCERendererSetBlurPasses(context, static_cast<uint32_t>(blurPasses));
            }
            int maxMips = static_cast<int>(MCERendererGetBloomMaxMips(context));
            if (EditorUI::PropertyInt("Max Mip Levels", &maxMips, 1, 8)) {
                MCERendererSetBloomMaxMips(context, static_cast<uint32_t>(maxMips));
            }
            bool halfRes = MCERendererGetHalfResBloom(context) != 0;
            if (EditorUI::PropertyBool("Half-Res Bloom", &halfRes)) {
                MCERendererSetHalfResBloom(context, halfRes ? 1 : 0);
            }
            EditorUI::EndPropertyTable();
        }
    }

    bool tonemapOpen = EditorUI::BeginSection(context, "Tonemap", "Renderer.Tonemap", true);
    if (tonemapOpen) {
        if (EditorUI::BeginPropertyTable("TonemapTable")) {
            const char* tonemapItems[] = { "None", "Reinhard", "ACES", "MetalCup Custom" };
            int tonemap = static_cast<int>(MCERendererGetTonemap(context));
            if (EditorUI::PropertyCombo("Tonemap", &tonemap, tonemapItems, IM_ARRAYSIZE(tonemapItems))) {
                MCERendererSetTonemap(context, static_cast<uint32_t>(tonemap));
            }
            float exposure = MCERendererGetExposure(context);
            if (EditorUI::PropertyFloat("Exposure", &exposure, EditorUIConstants::kExposureStep,
                                        EditorUIConstants::kExposureMin, EditorUIConstants::kExposureMax, "%.3f", true, true, EditorUIConstants::kDefaultExposure)) {
                MCERendererSetExposure(context, exposure);
            }
            float gamma = MCERendererGetGamma(context);
            if (EditorUI::PropertyFloat("Gamma", &gamma, EditorUIConstants::kGammaStep,
                                        EditorUIConstants::kGammaMin, EditorUIConstants::kGammaMax, "%.3f", true, true, EditorUIConstants::kDefaultGamma)) {
                MCERendererSetGamma(context, gamma);
            }
            EditorUI::EndPropertyTable();
        }
    }

    bool outlineOpen = EditorUI::BeginSection(context, "Selection Outline", "Renderer.Outline", true);
    if (outlineOpen) {
        if (EditorUI::BeginPropertyTable("OutlineTable")) {
            bool outlineEnabled = MCERendererGetOutlineEnabled(context) != 0;
            if (EditorUI::PropertyBool("Enable Outline", &outlineEnabled)) {
                MCERendererSetOutlineEnabled(context, outlineEnabled ? 1 : 0);
            }
            int thickness = static_cast<int>(MCERendererGetOutlineThickness(context));
            if (EditorUI::PropertyInt("Thickness (px)", &thickness, 1, 4)) {
                MCERendererSetOutlineThickness(context, static_cast<uint32_t>(thickness));
            }
            float opacity = MCERendererGetOutlineOpacity(context);
            if (EditorUI::PropertyFloat("Opacity", &opacity, EditorUIConstants::kOutlineOpacityStep,
                                        EditorUIConstants::kOutlineOpacityMin, EditorUIConstants::kOutlineOpacityMax, "%.2f", true, true, EditorUIConstants::kDefaultOutlineOpacity)) {
                MCERendererSetOutlineOpacity(context, opacity);
            }
            float outlineColor[3];
            MCERendererGetOutlineColor(context, &outlineColor[0], &outlineColor[1], &outlineColor[2]);
            if (EditorUI::PropertyColor3("Color", outlineColor, EditorUIConstants::kDefaultOutlineColor, true)) {
                MCERendererSetOutlineColor(context, outlineColor[0], outlineColor[1], outlineColor[2]);
            }
            EditorUI::EndPropertyTable();
        }
    }

    bool gridOpen = EditorUI::BeginSection(context, "Viewport Grid", "Renderer.Grid", true);
    if (gridOpen) {
        if (EditorUI::BeginPropertyTable("GridTable")) {
            bool gridEnabled = MCERendererGetGridEnabled(context) != 0;
            if (EditorUI::PropertyBool("Enable Grid", &gridEnabled)) {
                MCERendererSetGridEnabled(context, gridEnabled ? 1 : 0);
            }
            float gridOpacity = MCERendererGetGridOpacity(context);
            if (EditorUI::PropertyFloat("Opacity", &gridOpacity, EditorUIConstants::kGridOpacityStep,
                                        EditorUIConstants::kGridOpacityMin, EditorUIConstants::kGridOpacityMax, "%.2f", true, true, EditorUIConstants::kDefaultGridOpacity)) {
                MCERendererSetGridOpacity(context, gridOpacity);
            }
            float gridFade = MCERendererGetGridFadeDistance(context);
            if (EditorUI::PropertyFloat("Fade Distance", &gridFade, EditorUIConstants::kGridFadeStep,
                                        EditorUIConstants::kGridFadeMin, EditorUIConstants::kGridFadeMax, "%.1f", true, true, EditorUIConstants::kDefaultGridFadeDistance)) {
                MCERendererSetGridFadeDistance(context, gridFade);
            }
            float gridMajor = MCERendererGetGridMajorLineEvery(context);
            if (EditorUI::PropertyFloat("Major Line Every", &gridMajor, EditorUIConstants::kGridMajorLineStep,
                                        EditorUIConstants::kGridMajorLineMin, EditorUIConstants::kGridMajorLineMax, "%.0f", true, true, EditorUIConstants::kDefaultGridMajorLineEvery)) {
                MCERendererSetGridMajorLineEvery(context, gridMajor);
            }
            EditorUI::EndPropertyTable();
        }
    }

    bool iblOpen = EditorUI::BeginSection(context, "IBL", "Renderer.IBL", true);
    if (iblOpen) {
        if (EditorUI::BeginPropertyTable("IBLTable")) {
            bool iblEnabled = MCERendererGetIBLEnabled(context) != 0;
            if (EditorUI::PropertyBool("Enable IBL", &iblEnabled)) {
                MCERendererSetIBLEnabled(context, iblEnabled ? 1 : 0);
            }
            float iblIntensity = MCERendererGetIBLIntensity(context);
            if (EditorUI::PropertyFloat("IBL Intensity", &iblIntensity, EditorUIConstants::kIBLIntensityStep,
                                        EditorUIConstants::kIBLIntensityMin, EditorUIConstants::kIBLIntensityMax, "%.3f", true, true, EditorUIConstants::kDefaultIBLIntensity)) {
                MCERendererSetIBLIntensity(context, iblIntensity);
            }
            const char* iblItems[] = { "Low", "Medium", "High", "Ultra", "Custom" };
            int iblPreset = static_cast<int>(MCERendererGetIBLQualityPreset(context));
            if (iblPreset < 0 || iblPreset > 4) { iblPreset = 4; }
            if (EditorUI::PropertyCombo("IBL Quality", &iblPreset, iblItems, IM_ARRAYSIZE(iblItems))) {
                MCERendererSetIBLQualityPreset(context, static_cast<uint32_t>(iblPreset));
            }
            EditorUI::EndPropertyTable();
        }
    }

    bool materialsOpen = EditorUI::BeginSection(context, "Materials", "Renderer.Materials", true);
    if (materialsOpen) {
        if (EditorUI::BeginPropertyTable("MaterialSettingsTable")) {
            bool globalFlip = MCERendererGetNormalFlipYGlobal(context) != 0;
            if (EditorUI::PropertyBool("Global Normal Flip (Y)", &globalFlip)) {
                MCERendererSetNormalFlipYGlobal(context, globalFlip ? 1 : 0);
            }
            EditorUI::EndPropertyTable();
        }
    }

    bool performanceOpen = EditorUI::BeginSection(context, "Performance", "Renderer.Performance", true);
    if (performanceOpen) {
        if (EditorUI::BeginPropertyTable("PerformanceTable")) {
            bool disableSpecAA = MCERendererGetDisableSpecularAA(context) != 0;
            if (EditorUI::PropertyBool("Disable Specular AA", &disableSpecAA)) {
                MCERendererSetDisableSpecularAA(context, disableSpecAA ? 1 : 0);
            }
            bool disableClearcoat = MCERendererGetDisableClearcoat(context) != 0;
            if (EditorUI::PropertyBool("Disable Clearcoat", &disableClearcoat)) {
                MCERendererSetDisableClearcoat(context, disableClearcoat ? 1 : 0);
            }
            bool disableSheen = MCERendererGetDisableSheen(context) != 0;
            if (EditorUI::PropertyBool("Disable Sheen", &disableSheen)) {
                MCERendererSetDisableSheen(context, disableSheen ? 1 : 0);
            }
            bool skipSpecIBL = MCERendererGetSkipSpecIBLHighRoughness(context) != 0;
            if (EditorUI::PropertyBool("Skip Spec IBL (Rough>0.9)", &skipSpecIBL)) {
                MCERendererSetSkipSpecIBLHighRoughness(context, skipSpecIBL ? 1 : 0);
            }
            EditorUI::EndPropertyTable();
        }
    }

    ImGui::EndChild();
    EditorUI::EndPanel();
}
