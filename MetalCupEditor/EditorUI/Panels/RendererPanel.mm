// RendererPanel.mm
// Defines the ImGui Renderer panel rendering and interaction logic.
// Created by Kaden Cringle.

#import "RendererPanel.h"

#import "../../EditorCore/Bridge/RendererSettingsBridge.h"
#import "../Widgets/UIConstants.h"
#import "../Widgets/UIWidgets.h"
#import "../../ImGui/imgui.h"
#include <cmath>

extern "C" void MCEEditorRequestActiveSkyRebuild(MCE_CTX);

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

    void *EngineContextFromMCE(void *context) {
        return MCEContextGetEngineContext(context);
    }

    int ResolveBloomPresetIndex(void *engineContext) {
        const uint32_t halfRes = MCERendererGetHalfResBloom(engineContext);
        const uint32_t blurPasses = MCERendererGetBlurPasses(engineContext);
        const uint32_t maxMips = MCERendererGetBloomMaxMips(engineContext);
        const float upsampleScale = MCERendererGetBloomUpsampleScale(engineContext);
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

    void ApplyBloomPreset(void *engineContext, int presetIndex) {
        if (presetIndex <= 0) { return; }
        const BloomPreset &preset = kBloomPresets[presetIndex - 1];
        MCERendererSetHalfResBloom(engineContext, preset.halfRes);
        MCERendererSetBlurPasses(engineContext, preset.blurPasses);
        MCERendererSetBloomUpsampleScale(engineContext, preset.upsampleScale);
        MCERendererSetBloomMaxMips(engineContext, preset.maxMips);
    }

}

void ImGuiRendererPanelDraw(void *context, bool *isOpen) {
    if (!isOpen || !*isOpen) { return; }
    if (!EditorUI::BeginPanel("Renderer", isOpen)) {
        EditorUI::EndPanel();
        return;
    }
    ImGui::BeginChild("RendererScroll", ImVec2(0, 0), false, ImGuiWindowFlags_AlwaysVerticalScrollbar);

    void *engineContext = EngineContextFromMCE(context);
    bool bloomOpen = EditorUI::BeginSection(context, "Bloom", "Renderer.Bloom", true);
    if (bloomOpen) {
        if (EditorUI::BeginPropertyTable("BloomTable")) {
            bool bloomEnabled = MCERendererGetBloomEnabled(engineContext) != 0;
            if (EditorUI::PropertyBool("Enable Bloom", &bloomEnabled)) {
                MCERendererSetBloomEnabled(engineContext, bloomEnabled ? 1 : 0);
            }

            const char* qualityItems[] = { "Custom", "Low", "Medium", "High", "Ultra" };
            int qualityIndex = ResolveBloomPresetIndex(engineContext);
            if (EditorUI::PropertyCombo("Quality Preset", &qualityIndex, qualityItems, IM_ARRAYSIZE(qualityItems))) {
                ApplyBloomPreset(engineContext, qualityIndex);
            }

            float threshold = MCERendererGetBloomThreshold(engineContext);
            if (EditorUI::PropertyFloat("Threshold", &threshold, EditorUIConstants::kBloomThresholdStep,
                                        EditorUIConstants::kBloomThresholdMin, EditorUIConstants::kBloomThresholdMax, "%.3f", true, true, EditorUIConstants::kDefaultBloomThreshold)) {
                MCERendererSetBloomThreshold(engineContext, threshold);
            }
            float knee = MCERendererGetBloomKnee(engineContext);
            if (EditorUI::PropertyFloat("Knee", &knee, EditorUIConstants::kBloomKneeStep,
                                        EditorUIConstants::kBloomKneeMin, EditorUIConstants::kBloomKneeMax, "%.3f", true, true, EditorUIConstants::kDefaultBloomKnee)) {
                MCERendererSetBloomKnee(engineContext, knee);
            }
            float intensity = MCERendererGetBloomIntensity(engineContext);
            if (EditorUI::PropertyFloat("Intensity", &intensity, EditorUIConstants::kBloomIntensityStep,
                                        EditorUIConstants::kBloomIntensityMin, EditorUIConstants::kBloomIntensityMax, "%.3f", true, true, EditorUIConstants::kDefaultBloomIntensity)) {
                MCERendererSetBloomIntensity(engineContext, intensity);
            }
            float upsampleScale = MCERendererGetBloomUpsampleScale(engineContext);
            if (EditorUI::PropertyFloat("Upsample Scale", &upsampleScale, EditorUIConstants::kBloomUpsampleStep,
                                        EditorUIConstants::kBloomUpsampleMin, EditorUIConstants::kBloomUpsampleMax, "%.3f", true, true, EditorUIConstants::kDefaultBloomUpsample)) {
                MCERendererSetBloomUpsampleScale(engineContext, upsampleScale);
            }
            float dirtIntensity = MCERendererGetBloomDirtIntensity(engineContext);
            if (EditorUI::PropertyFloat("Dirt Intensity", &dirtIntensity, EditorUIConstants::kBloomDirtStep,
                                        EditorUIConstants::kBloomDirtMin, EditorUIConstants::kBloomDirtMax, "%.3f", true, true, EditorUIConstants::kDefaultBloomDirt)) {
                MCERendererSetBloomDirtIntensity(engineContext, dirtIntensity);
            }
            int blurPasses = static_cast<int>(MCERendererGetBlurPasses(engineContext));
            if (EditorUI::PropertyInt("Blur Passes (per mip)", &blurPasses, 0, 8)) {
                MCERendererSetBlurPasses(engineContext, static_cast<uint32_t>(blurPasses));
            }
            int maxMips = static_cast<int>(MCERendererGetBloomMaxMips(engineContext));
            if (EditorUI::PropertyInt("Max Mip Levels", &maxMips, 1, 8)) {
                MCERendererSetBloomMaxMips(engineContext, static_cast<uint32_t>(maxMips));
            }
            bool halfRes = MCERendererGetHalfResBloom(engineContext) != 0;
            if (EditorUI::PropertyBool("Half-Res Bloom", &halfRes)) {
                MCERendererSetHalfResBloom(engineContext, halfRes ? 1 : 0);
            }
            EditorUI::EndPropertyTable();
        }
    }

    bool tonemapOpen = EditorUI::BeginSection(context, "Tonemap", "Renderer.Tonemap", true);
    if (tonemapOpen) {
        if (EditorUI::BeginPropertyTable("TonemapTable")) {
            const char* tonemapItems[] = { "None", "Reinhard", "ACES", "MetalCup Custom" };
            int tonemap = static_cast<int>(MCERendererGetTonemap(engineContext));
            if (EditorUI::PropertyCombo("Tonemap", &tonemap, tonemapItems, IM_ARRAYSIZE(tonemapItems))) {
                MCERendererSetTonemap(engineContext, static_cast<uint32_t>(tonemap));
            }
            float exposure = MCERendererGetExposure(engineContext);
            if (EditorUI::PropertyFloat("Exposure", &exposure, EditorUIConstants::kExposureStep,
                                        EditorUIConstants::kExposureMin, EditorUIConstants::kExposureMax, "%.3f", true, true, EditorUIConstants::kDefaultExposure)) {
                MCERendererSetExposure(engineContext, exposure);
            }
            float gamma = MCERendererGetGamma(engineContext);
            if (EditorUI::PropertyFloat("Gamma", &gamma, EditorUIConstants::kGammaStep,
                                        EditorUIConstants::kGammaMin, EditorUIConstants::kGammaMax, "%.3f", true, true, EditorUIConstants::kDefaultGamma)) {
                MCERendererSetGamma(engineContext, gamma);
            }
            EditorUI::EndPropertyTable();
        }
    }

    bool outlineOpen = EditorUI::BeginSection(context, "Selection Outline", "Renderer.Outline", true);
    if (outlineOpen) {
        if (EditorUI::BeginPropertyTable("OutlineTable")) {
            bool outlineEnabled = MCERendererGetOutlineEnabled(engineContext) != 0;
            if (EditorUI::PropertyBool("Enable Outline", &outlineEnabled)) {
                MCERendererSetOutlineEnabled(engineContext, outlineEnabled ? 1 : 0);
            }
            int thickness = static_cast<int>(MCERendererGetOutlineThickness(engineContext));
            if (EditorUI::PropertyInt("Thickness (px)", &thickness, 1, 4)) {
                MCERendererSetOutlineThickness(engineContext, static_cast<uint32_t>(thickness));
            }
            float opacity = MCERendererGetOutlineOpacity(engineContext);
            if (EditorUI::PropertyFloat("Opacity", &opacity, EditorUIConstants::kOutlineOpacityStep,
                                        EditorUIConstants::kOutlineOpacityMin, EditorUIConstants::kOutlineOpacityMax, "%.2f", true, true, EditorUIConstants::kDefaultOutlineOpacity)) {
                MCERendererSetOutlineOpacity(engineContext, opacity);
            }
            float outlineColor[3];
            MCERendererGetOutlineColor(engineContext, &outlineColor[0], &outlineColor[1], &outlineColor[2]);
            if (EditorUI::PropertyColor3("Color", outlineColor, EditorUIConstants::kDefaultOutlineColor, true)) {
                MCERendererSetOutlineColor(engineContext, outlineColor[0], outlineColor[1], outlineColor[2]);
            }
            EditorUI::EndPropertyTable();
        }
    }

    bool shadowsOpen = EditorUI::BeginSection(context, "Shadows", "Renderer.Shadows", true);
    if (shadowsOpen) {
        if (EditorUI::BeginPropertyTable("ShadowsTable")) {
            bool shadowsEnabled = MCERendererGetShadowsEnabled(engineContext) != 0;
            if (EditorUI::PropertyBool("Enable Shadows", &shadowsEnabled)) {
                MCERendererSetShadowsEnabled(engineContext, shadowsEnabled ? 1 : 0);
            }
            bool directionalEnabled = MCERendererGetDirectionalShadowsEnabled(engineContext) != 0;
            if (EditorUI::PropertyBool("Directional Shadows", &directionalEnabled)) {
                MCERendererSetDirectionalShadowsEnabled(engineContext, directionalEnabled ? 1 : 0);
            }

            const char* resolutionItems[] = { "1024", "2048", "4096" };
            uint32_t currentRes = MCERendererGetShadowMapResolution(engineContext);
            int resIndex = currentRes == 1024 ? 0 : (currentRes == 4096 ? 2 : 1);
            if (EditorUI::PropertyCombo("Resolution", &resIndex, resolutionItems, IM_ARRAYSIZE(resolutionItems))) {
                uint32_t resolution = (resIndex == 0) ? 1024 : (resIndex == 2 ? 4096 : 2048);
                MCERendererSetShadowMapResolution(engineContext, resolution);
            }

            int cascades = static_cast<int>(MCERendererGetShadowCascadeCount(engineContext));
            if (EditorUI::PropertyInt("Cascades", &cascades, 1, 4)) {
                MCERendererSetShadowCascadeCount(engineContext, static_cast<uint32_t>(cascades));
            }
            float splitLambda = MCERendererGetShadowSplitLambda(engineContext);
            if (EditorUI::PropertyFloat("Split Lambda", &splitLambda,
                                        EditorUIConstants::kShadowSplitLambdaStep,
                                        EditorUIConstants::kShadowSplitLambdaMin,
                                        EditorUIConstants::kShadowSplitLambdaMax, "%.2f", true, true, 0.65f)) {
                MCERendererSetShadowSplitLambda(engineContext, splitLambda);
            }

            float depthBias = MCERendererGetShadowDepthBias(engineContext);
            if (EditorUI::PropertyFloat("Depth Bias", &depthBias,
                                        EditorUIConstants::kShadowDepthBiasStep,
                                        EditorUIConstants::kShadowDepthBiasMin,
                                        EditorUIConstants::kShadowDepthBiasMax, "%.5f", true, true, 0.0005f)) {
                MCERendererSetShadowDepthBias(engineContext, depthBias);
            }
            float normalBias = MCERendererGetShadowNormalBias(engineContext);
            if (EditorUI::PropertyFloat("Normal Bias", &normalBias,
                                        EditorUIConstants::kShadowNormalBiasStep,
                                        EditorUIConstants::kShadowNormalBiasMin,
                                        EditorUIConstants::kShadowNormalBiasMax, "%.3f", true, true, 0.01f)) {
                MCERendererSetShadowNormalBias(engineContext, normalBias);
            }
            const char* filterItems[] = { "Hard", "PCF", "PCSS (Experimental)" };
            int filterMode = static_cast<int>(MCERendererGetShadowFilterMode(engineContext));
            if (EditorUI::PropertyCombo("Filter Mode", &filterMode, filterItems, IM_ARRAYSIZE(filterItems))) {
                MCERendererSetShadowFilterMode(engineContext, static_cast<uint32_t>(filterMode));
            }
            if (filterMode == 1) {
                float pcfRadius = MCERendererGetShadowPCFRadius(engineContext);
                if (EditorUI::PropertyFloat("PCF Radius", &pcfRadius,
                                            EditorUIConstants::kShadowPCFRadiusStep,
                                            EditorUIConstants::kShadowPCFRadiusMin,
                                            EditorUIConstants::kShadowPCFRadiusMax, "%.2f", true, true, 1.5f)) {
                    MCERendererSetShadowPCFRadius(engineContext, pcfRadius);
                }
            } else if (filterMode == 2) {
                float lightSize = MCERendererGetShadowPCSSLightWorldSize(engineContext);
                if (EditorUI::PropertyFloat("Light Size", &lightSize,
                                            EditorUIConstants::kShadowPCSSLightSizeStep,
                                            EditorUIConstants::kShadowPCSSLightSizeMin,
                                            EditorUIConstants::kShadowPCSSLightSizeMax, "%.2f", true, true, 1.0f)) {
                    MCERendererSetShadowPCSSLightWorldSize(engineContext, lightSize);
                }
                float minRadius = MCERendererGetShadowPCSSMinRadius(engineContext);
                if (EditorUI::PropertyFloat("Min Radius (px)", &minRadius,
                                            EditorUIConstants::kShadowPCSSMinRadiusStep,
                                            EditorUIConstants::kShadowPCSSMinRadiusMin,
                                            EditorUIConstants::kShadowPCSSMinRadiusMax, "%.2f", true, true, 1.0f)) {
                    MCERendererSetShadowPCSSMinRadius(engineContext, minRadius);
                }
                float maxRadius = MCERendererGetShadowPCSSMaxRadius(engineContext);
                if (EditorUI::PropertyFloat("Max Radius (px)", &maxRadius,
                                            EditorUIConstants::kShadowPCSSMaxRadiusStep,
                                            EditorUIConstants::kShadowPCSSMaxRadiusMin,
                                            EditorUIConstants::kShadowPCSSMaxRadiusMax, "%.2f", true, true, 8.0f)) {
                    MCERendererSetShadowPCSSMaxRadius(engineContext, maxRadius);
                }
                float blockerRadius = MCERendererGetShadowPCSSBlockerRadius(engineContext);
                if (EditorUI::PropertyFloat("Blocker Radius (px)", &blockerRadius,
                                            EditorUIConstants::kShadowPCSSBlockerRadiusStep,
                                            EditorUIConstants::kShadowPCSSBlockerRadiusMin,
                                            EditorUIConstants::kShadowPCSSBlockerRadiusMax, "%.2f", true, true, 4.0f)) {
                    MCERendererSetShadowPCSSBlockerRadius(engineContext, blockerRadius);
                }
                int blockerSamples = static_cast<int>(MCERendererGetShadowPCSSBlockerSamples(engineContext));
                if (EditorUI::PropertyInt("Blocker Samples", &blockerSamples, 1, 32)) {
                    MCERendererSetShadowPCSSBlockerSamples(engineContext, static_cast<uint32_t>(blockerSamples));
                }
                int filterSamples = static_cast<int>(MCERendererGetShadowPCSSFilterSamples(engineContext));
                if (EditorUI::PropertyInt("Filter Samples", &filterSamples, 1, 32)) {
                    MCERendererSetShadowPCSSFilterSamples(engineContext, static_cast<uint32_t>(filterSamples));
                }
                bool noiseEnabled = MCERendererGetShadowPCSSNoiseEnabled(engineContext) != 0;
                if (EditorUI::PropertyBool("Rotate Kernel", &noiseEnabled)) {
                    MCERendererSetShadowPCSSNoiseEnabled(engineContext, noiseEnabled ? 1 : 0);
                }
            }
            float maxDistance = MCERendererGetShadowMaxDistance(engineContext);
            if (EditorUI::PropertyFloat("Max Distance", &maxDistance,
                                        EditorUIConstants::kShadowMaxDistanceStep,
                                        EditorUIConstants::kShadowMaxDistanceMin,
                                        EditorUIConstants::kShadowMaxDistanceMax, "%.1f", true, true, 100.0f)) {
                MCERendererSetShadowMaxDistance(engineContext, maxDistance);
            }
            float fadeOut = MCERendererGetShadowFadeOutDistance(engineContext);
            if (EditorUI::PropertyFloat("Fade Out", &fadeOut,
                                        EditorUIConstants::kShadowFadeOutStep,
                                        EditorUIConstants::kShadowFadeOutMin,
                                        EditorUIConstants::kShadowFadeOutMax, "%.1f", true, true, 10.0f)) {
                MCERendererSetShadowFadeOutDistance(engineContext, fadeOut);
            }
            EditorUI::EndPropertyTable();
        }
    }

    bool gridOpen = EditorUI::BeginSection(context, "Viewport Grid", "Renderer.Grid", true);
    if (gridOpen) {
        if (EditorUI::BeginPropertyTable("GridTable")) {
            bool gridEnabled = MCERendererGetGridEnabled(engineContext) != 0;
            if (EditorUI::PropertyBool("Enable Grid", &gridEnabled)) {
                MCERendererSetGridEnabled(engineContext, gridEnabled ? 1 : 0);
            }
            float gridOpacity = MCERendererGetGridOpacity(engineContext);
            if (EditorUI::PropertyFloat("Opacity", &gridOpacity, EditorUIConstants::kGridOpacityStep,
                                        EditorUIConstants::kGridOpacityMin, EditorUIConstants::kGridOpacityMax, "%.2f", true, true, EditorUIConstants::kDefaultGridOpacity)) {
                MCERendererSetGridOpacity(engineContext, gridOpacity);
            }
            float gridFade = MCERendererGetGridFadeDistance(engineContext);
            if (EditorUI::PropertyFloat("Fade Distance", &gridFade, EditorUIConstants::kGridFadeStep,
                                        EditorUIConstants::kGridFadeMin, EditorUIConstants::kGridFadeMax, "%.1f", true, true, EditorUIConstants::kDefaultGridFadeDistance)) {
                MCERendererSetGridFadeDistance(engineContext, gridFade);
            }
            float gridMajor = MCERendererGetGridMajorLineEvery(engineContext);
            if (EditorUI::PropertyFloat("Major Line Every", &gridMajor, EditorUIConstants::kGridMajorLineStep,
                                        EditorUIConstants::kGridMajorLineMin, EditorUIConstants::kGridMajorLineMax, "%.0f", true, true, EditorUIConstants::kDefaultGridMajorLineEvery)) {
                MCERendererSetGridMajorLineEvery(engineContext, gridMajor);
            }
            EditorUI::EndPropertyTable();
        }
    }

    bool iblOpen = EditorUI::BeginSection(context, "IBL", "Renderer.IBL", true);
    if (iblOpen) {
        bool rebuildIBL = false;
        if (EditorUI::BeginPropertyTable("IBLTable")) {
            bool iblEnabled = MCERendererGetIBLEnabled(engineContext) != 0;
            if (EditorUI::PropertyBool("Enable IBL", &iblEnabled)) {
                MCERendererSetIBLEnabled(engineContext, iblEnabled ? 1 : 0);
            }
            float iblIntensity = MCERendererGetIBLIntensity(engineContext);
            if (EditorUI::PropertyFloat("IBL Intensity", &iblIntensity, EditorUIConstants::kIBLIntensityStep,
                                        EditorUIConstants::kIBLIntensityMin, EditorUIConstants::kIBLIntensityMax, "%.3f", true, true, EditorUIConstants::kDefaultIBLIntensity)) {
                MCERendererSetIBLIntensity(engineContext, iblIntensity);
            }
            const char* iblItems[] = { "Low", "Medium", "High", "Ultra", "Custom" };
            int iblPreset = static_cast<int>(MCERendererGetIBLQualityPreset(engineContext));
            if (iblPreset < 0 || iblPreset > 4) { iblPreset = 4; }
            if (EditorUI::PropertyCombo("IBL Quality", &iblPreset, iblItems, IM_ARRAYSIZE(iblItems))) {
                MCERendererSetIBLQualityPreset(engineContext, static_cast<uint32_t>(iblPreset));
                rebuildIBL = true;
            }
            bool fireflyClampEnabled = MCERendererGetIBLFireflyClampEnabled(engineContext) != 0;
            if (EditorUI::PropertyBool("Firefly Clamp", &fireflyClampEnabled)) {
                MCERendererSetIBLFireflyClampEnabled(engineContext, fireflyClampEnabled ? 1 : 0);
                rebuildIBL = true;
            }
            float fireflyClamp = MCERendererGetIBLFireflyClamp(engineContext);
            if (EditorUI::PropertyFloat("Firefly Threshold", &fireflyClamp, 1.0f, 0.0f, 10000.0f, "%.1f", true, true, 100.0f)) {
                MCERendererSetIBLFireflyClamp(engineContext, fireflyClamp);
                rebuildIBL = true;
            }
            float sampleMultiplier = MCERendererGetIBLSampleMultiplier(engineContext);
            if (EditorUI::PropertyFloat("Sample Multiplier", &sampleMultiplier, 0.05f, 0.1f, 4.0f, "%.2f", true, true, 1.0f)) {
                MCERendererSetIBLSampleMultiplier(engineContext, sampleMultiplier);
                rebuildIBL = true;
            }
            float skyboxMipBias = MCERendererGetSkyboxMipBias(engineContext);
            if (EditorUI::PropertyFloat("Skybox Mip Bias", &skyboxMipBias,
                                        EditorUIConstants::kSkyboxMipBiasStep,
                                        EditorUIConstants::kSkyboxMipBiasMin,
                                        EditorUIConstants::kSkyboxMipBiasMax,
                                        "%.2f", true, true, EditorUIConstants::kDefaultSkyboxMipBias)) {
                MCERendererSetSkyboxMipBias(engineContext, skyboxMipBias);
            }
            EditorUI::EndPropertyTable();
        }
        if (rebuildIBL) {
            MCEEditorRequestActiveSkyRebuild(context);
        }
    }

    bool performanceOpen = EditorUI::BeginSection(context, "Performance", "Renderer.Performance", true);
    if (performanceOpen) {
        if (EditorUI::BeginPropertyTable("PerformanceTable")) {
            bool disableSpecAA = MCERendererGetDisableSpecularAA(engineContext) != 0;
            if (EditorUI::PropertyBool("Disable Specular AA", &disableSpecAA)) {
                MCERendererSetDisableSpecularAA(engineContext, disableSpecAA ? 1 : 0);
            }
            bool disableClearcoat = MCERendererGetDisableClearcoat(engineContext) != 0;
            if (EditorUI::PropertyBool("Disable Clearcoat", &disableClearcoat)) {
                MCERendererSetDisableClearcoat(engineContext, disableClearcoat ? 1 : 0);
            }
            bool disableSheen = MCERendererGetDisableSheen(engineContext) != 0;
            if (EditorUI::PropertyBool("Disable Sheen", &disableSheen)) {
                MCERendererSetDisableSheen(engineContext, disableSheen ? 1 : 0);
            }
            bool skipSpecIBL = MCERendererGetSkipSpecIBLHighRoughness(engineContext) != 0;
            if (EditorUI::PropertyBool("Skip Spec IBL (Rough>0.9)", &skipSpecIBL)) {
                MCERendererSetSkipSpecIBLHighRoughness(engineContext, skipSpecIBL ? 1 : 0);
            }
            EditorUI::EndPropertyTable();
        }
    }

    bool debugOpen = EditorUI::BeginSection(context, "Shading Debug", "Renderer.Debug", true);
    if (debugOpen) {
        if (EditorUI::BeginPropertyTable("DebugTable")) {
            const char* debugItems[] = {
                "Off",
                "World Normal",
                "Reflection",
                "Roughness",
                "Metallic",
                "NdotV",
                "Specular Mip",
                "Diffuse IBL",
                "Specular IBL",
                "Direct Lighting",
                "Roughness (Before AA)",
                "Roughness (After AA)",
                "Material Validation"
            };
            int debugMode = static_cast<int>(MCERendererGetShadingDebugMode(engineContext));
            if (EditorUI::PropertyCombo("Debug View", &debugMode, debugItems, IM_ARRAYSIZE(debugItems))) {
                MCERendererSetShadingDebugMode(engineContext, static_cast<uint32_t>(debugMode));
            }
            EditorUI::EndPropertyTable();
        }
    }

    ImGui::EndChild();
    EditorUI::EndPanel();
}
