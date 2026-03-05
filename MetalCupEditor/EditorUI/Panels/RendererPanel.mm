/// RendererPanel.mm
/// Defines the ImGui Renderer panel rendering and interaction logic.
/// Created by Kaden Cringle.

#import "RendererPanel.h"

#import "../../EditorCore/Bridge/RendererSettingsBridge.h"
#import "../Widgets/UIConstants.h"
#import "../Widgets/UIWidgets.h"
#import "../../ImGui/imgui.h"
#include <cmath>

extern "C" void MCEEditorRequestActiveSkyRebuild(MCE_CTX);

namespace {
    void *EngineContextFromMCE(void *context) {
        return MCEContextGetEngineContext(context);
    }

    void ApplyBloomPresetDefaults(void *engineContext, int presetIndex) {
        // Keep max mips artist-tweakable while presets control primary quality knobs.
        if (presetIndex == 0) { // Low
            MCERendererSetBloomResolutionScale(engineContext, 2);
            MCERendererSetBloomMaxMips(engineContext, 4);
        } else if (presetIndex == 1) { // Medium
            MCERendererSetBloomResolutionScale(engineContext, 4);
            MCERendererSetBloomMaxMips(engineContext, 4);
        } else if (presetIndex == 2) { // High
            MCERendererSetBloomResolutionScale(engineContext, 4);
            MCERendererSetBloomMaxMips(engineContext, 5);
        } else if (presetIndex == 3) { // Ultra
            MCERendererSetBloomResolutionScale(engineContext, 4);
            MCERendererSetBloomMaxMips(engineContext, 6);
        }
    }
}


enum RendererSettingsSectionMask : uint32_t {
    RendererSectionCore = 1 << 0,
    RendererSectionOutline = 1 << 1,
    RendererSectionShadows = 1 << 2,
    RendererSectionGrid = 1 << 3,
    RendererSectionLighting = 1 << 4,
    RendererSectionPerformance = 1 << 5,
    RendererSectionDebug = 1 << 6,
    RendererSectionAll = 0xFFFFFFFFu
};

static bool SectionEnabled(uint32_t sectionMask, RendererSettingsSectionMask section) {
    return (sectionMask & section) != 0;
}

static void SectionTitle(const char *title) {
    EditorUI::SectionHeader(title);
}

static void DrawRendererSettingsBody(void *context, const char *childId, uint32_t sectionMask = RendererSectionAll) {
    ImGui::BeginChild(childId, ImVec2(0, 0), false, ImGuiWindowFlags_AlwaysVerticalScrollbar);

    void *engineContext = EngineContextFromMCE(context);
    if (SectionEnabled(sectionMask, RendererSectionCore)) {
        SectionTitle("Post Processing");
        if (EditorUI::BeginPropertyTable("PostProcessTable")) {
            bool bloomEnabled = MCERendererGetBloomEnabled(engineContext) != 0;
            EditorUI::SetNextPropertyInfoTooltip("Enable bloom post-processing.\nUnits: boolean.\nPerformance: medium GPU cost.\nPersistence: Project.");
            if (EditorUI::PropertyBool("Bloom Enabled", &bloomEnabled)) {
                MCERendererSetBloomEnabled(engineContext, bloomEnabled ? 1 : 0);
            }

            if (bloomEnabled) {
                const char* qualityItems[] = { "Low", "Medium", "High", "Ultra", "Custom" };
                int qualityIndex = static_cast<int>(MCERendererGetBloomQualityPreset(engineContext));
                qualityIndex = qualityIndex < 0 || qualityIndex > 4 ? 2 : qualityIndex;
                EditorUI::SetNextPropertyInfoTooltip("Bloom quality preset.\nUnits: preset.\nPerformance: higher presets increase blur quality/cost.\nPersistence: Project.");
                if (EditorUI::PropertyCombo("Bloom Quality", &qualityIndex, qualityItems, IM_ARRAYSIZE(qualityItems))) {
                    MCERendererSetBloomQualityPreset(engineContext, static_cast<uint32_t>(qualityIndex));
                    if (qualityIndex >= 0 && qualityIndex <= 3) {
                        ApplyBloomPresetDefaults(engineContext, qualityIndex);
                    }
                }

                const char* resolutionItems[] = { "1/2", "1/4" };
                uint32_t bloomScale = MCERendererGetBloomResolutionScale(engineContext);
                int scaleIndex = bloomScale <= 2 ? 0 : 1;
                EditorUI::SetNextPropertyInfoTooltip("Bloom base resolution scale.\nUnits: relative to viewport.\nPerformance: 1/4 is much faster.\nPersistence: Project.");
                if (EditorUI::PropertyCombo("Resolution Scale", &scaleIndex, resolutionItems, IM_ARRAYSIZE(resolutionItems))) {
                    MCERendererSetBloomResolutionScale(engineContext, scaleIndex == 0 ? 2 : 4);
                }

                float threshold = MCERendererGetBloomThreshold(engineContext);
                EditorUI::SetNextPropertyInfoTooltip("Luminance threshold where bloom starts.\nUnits: linear HDR luminance.\nPersistence: Project.");
                if (EditorUI::PropertyFloat("Threshold", &threshold, EditorUIConstants::kBloomThresholdStep,
                                            EditorUIConstants::kBloomThresholdMin, EditorUIConstants::kBloomThresholdMax, "%.3f", true, true, EditorUIConstants::kDefaultBloomThreshold)) {
                    MCERendererSetBloomThreshold(engineContext, threshold);
                }
                float knee = MCERendererGetBloomKnee(engineContext);
                EditorUI::SetNextPropertyInfoTooltip("Soft-knee around threshold.\nUnits: normalized.\nPersistence: Project.");
                if (EditorUI::PropertyFloat("Knee", &knee, EditorUIConstants::kBloomKneeStep,
                                            EditorUIConstants::kBloomKneeMin, EditorUIConstants::kBloomKneeMax, "%.3f", true, true, EditorUIConstants::kDefaultBloomKnee)) {
                    MCERendererSetBloomKnee(engineContext, knee);
                }
                float intensity = MCERendererGetBloomIntensity(engineContext);
                if (EditorUI::PropertyFloat("Intensity", &intensity, EditorUIConstants::kBloomIntensityStep,
                                            EditorUIConstants::kBloomIntensityMin, EditorUIConstants::kBloomIntensityMax, "%.3f", true, true, EditorUIConstants::kDefaultBloomIntensity)) {
                    MCERendererSetBloomIntensity(engineContext, intensity);
                }
                int maxMips = static_cast<int>(MCERendererGetBloomMaxMips(engineContext));
                if (EditorUI::PropertyInt("Max Mips", &maxMips, 1, 8)) {
                    MCERendererSetBloomMaxMips(engineContext, static_cast<uint32_t>(maxMips));
                }
            }
            EditorUI::EndPropertyTable();
        }
        EditorUI::StandardSpacing();
    }

    if (SectionEnabled(sectionMask, RendererSectionCore)) {
        SectionTitle("Tonemap");
        if (EditorUI::BeginPropertyTable("TonemapTable")) {
            const char* tonemapItems[] = { "None", "Reinhard", "ACES", "MetalCup Custom" };
            int tonemap = static_cast<int>(MCERendererGetTonemap(engineContext));
            EditorUI::SetNextPropertyInfoTooltip("Tone mapping operator.\nUnits: enum.\nPerformance: low.\nPersistence: Project.");
            if (EditorUI::PropertyCombo("Tonemap", &tonemap, tonemapItems, IM_ARRAYSIZE(tonemapItems))) {
                MCERendererSetTonemap(engineContext, static_cast<uint32_t>(tonemap));
            }
            float exposure = MCERendererGetExposure(engineContext);
            EditorUI::SetNextPropertyInfoTooltip("Global exposure compensation.\nUnits: EV-like scalar.\nPerformance: low.\nPersistence: Project.");
            if (EditorUI::PropertyFloat("Exposure", &exposure, EditorUIConstants::kExposureStep,
                                        EditorUIConstants::kExposureMin, EditorUIConstants::kExposureMax, "%.3f", true, true, EditorUIConstants::kDefaultExposure)) {
                MCERendererSetExposure(engineContext, exposure);
            }
            float gamma = MCERendererGetGamma(engineContext);
            EditorUI::SetNextPropertyInfoTooltip("Display gamma.\nUnits: gamma value.\nPerformance: low.\nPersistence: Project.");
            if (EditorUI::PropertyFloat("Gamma", &gamma, EditorUIConstants::kGammaStep,
                                        EditorUIConstants::kGammaMin, EditorUIConstants::kGammaMax, "%.3f", true, true, EditorUIConstants::kDefaultGamma)) {
                MCERendererSetGamma(engineContext, gamma);
            }
            EditorUI::EndPropertyTable();
        }
        EditorUI::StandardSpacing();
    }

    if (SectionEnabled(sectionMask, RendererSectionOutline)) {
        SectionTitle("Selection Outline");
        if (EditorUI::BeginPropertyTable("OutlineTable")) {
            bool outlineEnabled = MCERendererGetOutlineEnabled(engineContext) != 0;
            EditorUI::SetNextPropertyInfoTooltip("Enable selected-entity outline.\nUnits: boolean.\nPerformance: low-to-medium.\nPersistence: Editor.");
            if (EditorUI::PropertyBool("Enable Outline", &outlineEnabled)) {
                MCERendererSetOutlineEnabled(engineContext, outlineEnabled ? 1 : 0);
            }
            int thickness = static_cast<int>(MCERendererGetOutlineThickness(engineContext));
            EditorUI::SetNextPropertyInfoTooltip("Outline thickness.\nUnits: pixels.\nPerformance: low.\nPersistence: Project.");
            if (EditorUI::PropertyInt("Thickness (px)", &thickness, 1, 4)) {
                MCERendererSetOutlineThickness(engineContext, static_cast<uint32_t>(thickness));
            }
            float opacity = MCERendererGetOutlineOpacity(engineContext);
            EditorUI::SetNextPropertyInfoTooltip("Outline opacity.\nUnits: 0..1.\nPerformance: low.\nPersistence: Project.");
            if (EditorUI::PropertyFloat("Opacity", &opacity, EditorUIConstants::kOutlineOpacityStep,
                                        EditorUIConstants::kOutlineOpacityMin, EditorUIConstants::kOutlineOpacityMax, "%.2f", true, true, EditorUIConstants::kDefaultOutlineOpacity)) {
                MCERendererSetOutlineOpacity(engineContext, opacity);
            }
            EditorUI::EndPropertyTable();
        }
        EditorUI::StandardSpacing();
    }

    if (SectionEnabled(sectionMask, RendererSectionShadows)) {
        SectionTitle("Lighting");
        if (EditorUI::BeginPropertyTable("LightingShadowTable")) {
            bool shadowsEnabled = MCERendererGetShadowsEnabled(engineContext) != 0;
            EditorUI::SetNextPropertyInfoTooltip("Master directional shadow switch.\nUnits: boolean.\nPerformance: medium-to-high GPU cost.\nPersistence: Project.");
            if (EditorUI::PropertyBool("Enable Shadows", &shadowsEnabled)) {
                MCERendererSetShadowsEnabled(engineContext, shadowsEnabled ? 1 : 0);
            }
            if (shadowsEnabled) {
                bool directionalEnabled = MCERendererGetDirectionalShadowsEnabled(engineContext) != 0;
                EditorUI::SetNextPropertyInfoTooltip("Directional light shadow maps.\nUnits: boolean.\nPerformance: medium-to-high GPU cost.\nPersistence: Project.");
                if (EditorUI::PropertyBool("Directional Shadows", &directionalEnabled)) {
                    MCERendererSetDirectionalShadowsEnabled(engineContext, directionalEnabled ? 1 : 0);
                }
            }
            EditorUI::EndPropertyTable();
        }
        EditorUI::StandardSpacing();

        SectionTitle("Shadows");
        if (EditorUI::BeginPropertyTable("ShadowsTable")) {
            bool shadowsEnabled = MCERendererGetShadowsEnabled(engineContext) != 0;
            if (shadowsEnabled) {
                const char* resolutionItems[] = { "1024", "2048", "4096" };
                uint32_t currentRes = MCERendererGetShadowMapResolution(engineContext);
                int resIndex = currentRes == 1024 ? 0 : (currentRes == 4096 ? 2 : 1);
                EditorUI::SetNextPropertyInfoTooltip("Shadow map resolution.\nUnits: pixels.\nPerformance: higher values increase VRAM + GPU cost.\nPersistence: Project.");
                if (EditorUI::PropertyCombo("Resolution", &resIndex, resolutionItems, IM_ARRAYSIZE(resolutionItems))) {
                    uint32_t resolution = (resIndex == 0) ? 1024 : (resIndex == 2 ? 4096 : 2048);
                    MCERendererSetShadowMapResolution(engineContext, resolution);
                }

                int cascades = static_cast<int>(MCERendererGetShadowCascadeCount(engineContext));
                EditorUI::SetNextPropertyInfoTooltip("Directional shadow cascade count.\nUnits: count.\nPerformance: each cascade adds render cost.\nPersistence: Project.");
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

                const char* pcfPresetItems[] = { "Low", "Medium", "High", "Ultra", "Custom" };
                int pcfPreset = static_cast<int>(MCERendererGetShadowPCFQualityPreset(engineContext));
                pcfPreset = pcfPreset < 0 || pcfPreset > 4 ? 2 : pcfPreset;
                EditorUI::SetNextPropertyInfoTooltip("Per-cascade PCF tap preset.\nUnits: preset.\nPerformance: higher presets cost more near camera.\nPersistence: Project.");
                if (EditorUI::PropertyCombo("PCF Preset", &pcfPreset, pcfPresetItems, IM_ARRAYSIZE(pcfPresetItems))) {
                    MCERendererSetShadowPCFQualityPreset(engineContext, static_cast<uint32_t>(pcfPreset));
                }

                int taps0 = static_cast<int>(MCERendererGetShadowPCFTapsCascade0(engineContext));
                int taps1 = static_cast<int>(MCERendererGetShadowPCFTapsCascade1(engineContext));
                int taps2 = static_cast<int>(MCERendererGetShadowPCFTapsCascade2(engineContext));
                int taps3 = static_cast<int>(MCERendererGetShadowPCFTapsCascade3(engineContext));
                if (EditorUI::PropertyInt("Cascade 0 Taps", &taps0, EditorUIConstants::kShadowPCFTapsMin, EditorUIConstants::kShadowPCFTapsMax)) {
                    MCERendererSetShadowPCFTapsCascade0(engineContext, static_cast<uint32_t>(taps0));
                }
                if (EditorUI::PropertyInt("Cascade 1 Taps", &taps1, EditorUIConstants::kShadowPCFTapsMin, EditorUIConstants::kShadowPCFTapsMax)) {
                    MCERendererSetShadowPCFTapsCascade1(engineContext, static_cast<uint32_t>(taps1));
                }
                if (EditorUI::PropertyInt("Cascade 2 Taps", &taps2, EditorUIConstants::kShadowPCFTapsMin, EditorUIConstants::kShadowPCFTapsMax)) {
                    MCERendererSetShadowPCFTapsCascade2(engineContext, static_cast<uint32_t>(taps2));
                }
                if (EditorUI::PropertyInt("Cascade 3 Taps", &taps3, EditorUIConstants::kShadowPCFTapsMin, EditorUIConstants::kShadowPCFTapsMax)) {
                    MCERendererSetShadowPCFTapsCascade3(engineContext, static_cast<uint32_t>(taps3));
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
                float pcfRadius = MCERendererGetShadowPCFRadius(engineContext);
                if (EditorUI::PropertyFloat("PCF Radius", &pcfRadius,
                                            EditorUIConstants::kShadowPCFRadiusStep,
                                            EditorUIConstants::kShadowPCFRadiusMin,
                                            EditorUIConstants::kShadowPCFRadiusMax, "%.2f", true, true, 1.5f)) {
                    MCERendererSetShadowPCFRadius(engineContext, pcfRadius);
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
            }
            EditorUI::EndPropertyTable();
        }
        EditorUI::StandardSpacing();
    }

    if (SectionEnabled(sectionMask, RendererSectionGrid)) {
        SectionTitle("Viewport Grid");
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
        EditorUI::StandardSpacing();
    }

    if (SectionEnabled(sectionMask, RendererSectionLighting)) {
        SectionTitle("IBL");
        bool rebuildIBL = false;
        if (EditorUI::BeginPropertyTable("IBLTable")) {
            bool iblEnabled = MCERendererGetIBLEnabled(engineContext) != 0;
            EditorUI::SetNextPropertyInfoTooltip("Enable image-based lighting.\nUnits: boolean.\nPerformance: medium GPU cost.\nPersistence: Project.");
            if (EditorUI::PropertyBool("Enable IBL", &iblEnabled)) {
                MCERendererSetIBLEnabled(engineContext, iblEnabled ? 1 : 0);
            }
            if (iblEnabled) {
            float iblIntensity = MCERendererGetIBLIntensity(engineContext);
            EditorUI::SetNextPropertyInfoTooltip("IBL contribution strength.\nUnits: scalar.\nPerformance: low.\nPersistence: Project.");
            if (EditorUI::PropertyFloat("IBL Intensity", &iblIntensity, EditorUIConstants::kIBLIntensityStep,
                                        EditorUIConstants::kIBLIntensityMin, EditorUIConstants::kIBLIntensityMax, "%.3f", true, true, EditorUIConstants::kDefaultIBLIntensity)) {
                MCERendererSetIBLIntensity(engineContext, iblIntensity);
            }
            const char* iblItems[] = { "Low", "Medium", "High", "Ultra", "Custom" };
            int iblPreset = static_cast<int>(MCERendererGetIBLQualityPreset(engineContext));
            if (iblPreset < 0 || iblPreset > 4) { iblPreset = 4; }
            EditorUI::SetNextPropertyInfoTooltip("IBL generation quality preset.\nUnits: preset.\nPerformance: higher presets increase build time and cost.\nPersistence: Project.");
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
            }
            EditorUI::EndPropertyTable();
        }
        if (rebuildIBL) {
            MCEEditorRequestActiveSkyRebuild(context);
        }
        EditorUI::StandardSpacing();
    }

    if (SectionEnabled(sectionMask, RendererSectionPerformance)) {
        SectionTitle("Performance");
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
            bool forwardPlusEnabled = MCERendererGetForwardPlusEnabled(engineContext) != 0;
            EditorUI::SetNextPropertyInfoTooltip("Enable Forward+ light culling path.\nUnits: boolean.\nPerformance: reduces per-pixel light loop cost at higher light counts.\nPersistence: Project.");
            if (EditorUI::PropertyBool("Forward+ Enabled", &forwardPlusEnabled)) {
                MCERendererSetForwardPlusEnabled(engineContext, forwardPlusEnabled ? 1 : 0);
            }
            EditorUI::EndPropertyTable();
        }
        EditorUI::StandardSpacing();
    }

    if (SectionEnabled(sectionMask, RendererSectionDebug)) {
        SectionTitle("Shading Debug");
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
                "Material Validation",
                "Geometric World Normal",
                "Normal Mismatch",
                "To-Camera Mismatch",
                "Light Heatmap (Forward+)",
                "Cluster Z Slice",
                "Cluster Grid",
                "Tile Light Count"
            };
            int debugMode = static_cast<int>(MCERendererGetShadingDebugMode(engineContext));
            if (EditorUI::PropertyCombo("Debug View", &debugMode, debugItems, IM_ARRAYSIZE(debugItems))) {
                MCERendererSetShadingDebugMode(engineContext, static_cast<uint32_t>(debugMode));
                if ((debugMode == 16 || debugMode == 17 || debugMode == 18 || debugMode == 19) && MCERendererGetForwardPlusEnabled(engineContext) == 0) {
                    MCERendererSetForwardPlusEnabled(engineContext, 1);
                }
            }
            if (debugMode == 16) {
                const uint32_t maxPerCluster = MCERendererGetForwardPlusMaxLightsPerCluster(engineContext);
                if (MCERendererGetForwardPlusEnabled(engineContext) == 0) {
                    ImGui::TextDisabled("Forward+ is disabled. Heatmap is unavailable.");
                }
                const uint32_t b0 = 0u;
                const uint32_t b1 = maxPerCluster / 4u;
                const uint32_t b2 = maxPerCluster / 2u;
                const uint32_t b3 = (maxPerCluster * 3u) / 4u;
                const uint32_t nearOverflow = (maxPerCluster > 1u) ? (maxPerCluster - 2u) : maxPerCluster;
                ImGui::TextDisabled("Legend (max %u): Black %u  Blue %u..%u  Green %u..%u",
                                    maxPerCluster, b0, b0 + 1u, b1, b1 + 1u, b2);
                ImGui::TextDisabled("Legend: Yellow %u..%u  Red %u..%u  Magenta overflow",
                                    b2 + 1u, b3, b3 + 1u, nearOverflow);
            } else if (debugMode == 17) {
                ImGui::TextDisabled("Cluster Z Slice: colors map logarithmic depth slices (near to far).");
            } else if (debugMode == 18) {
                ImGui::TextDisabled("Cluster Grid: visualizes Forward+ tile boundaries in screen space.");
            } else if (debugMode == 19) {
                ImGui::TextDisabled("Tile Light Count: visualizes 2D tile bins before cluster Z culling.");
            }
            const uint32_t tileOverflow = MCERendererGetForwardPlusTileOverflowCount(engineContext);
            const uint32_t clusterOverflow = MCERendererGetForwardPlusClusterOverflowCount(engineContext);
            const uint32_t tileIndices = MCERendererGetForwardPlusTileIndicesWritten(engineContext);
            const uint32_t clusterIndices = MCERendererGetForwardPlusClusterIndicesWritten(engineContext);
            const uint32_t totalTiles = MCERendererGetForwardPlusTotalTiles(engineContext);
            const uint32_t totalClusters = MCERendererGetForwardPlusTotalClusters(engineContext);
            const uint32_t activeTilesCount = MCERendererGetForwardPlusActiveTilesCount(engineContext);
            const uint32_t missingDepthFrames = MCERendererGetForwardPlusMissingDepthFrames(engineContext);
            const uint32_t cullingDepthSource = MCERendererGetForwardPlusCullingDepthSource(engineContext);
            const char* cullingDepthSourceText = "None";
            if (cullingDepthSource == 1u) {
                cullingDepthSourceText = "Prepass";
            } else if (cullingDepthSource == 2u) {
                cullingDepthSourceText = "Fallback";
            }
            ImGui::TextDisabled("Forward+ Stats: Tiles %u  Active Tiles %u  Clusters %u", totalTiles, activeTilesCount, totalClusters);
            ImGui::TextDisabled("Culling Depth Source: %s", cullingDepthSourceText);
            ImGui::TextDisabled("Missing Depth Frames: %u", missingDepthFrames);
            ImGui::TextDisabled("Indices: Tile %u  Cluster %u", tileIndices, clusterIndices);
            ImGui::TextDisabled("Overflow: Tile %u  Cluster %u", tileOverflow, clusterOverflow);
            EditorUI::EndPropertyTable();
        }
        EditorUI::StandardSpacing();
    }

        ImGui::EndChild();
}

void ImGuiRendererSettingsCategoryDraw(void *context, ImGuiRendererSettingsCategory category) {
    switch (category) {
    case ImGuiRendererSettingsCategoryCore:
        DrawRendererSettingsBody(context,
                                 "RendererSettingsCoreScroll",
                                 RendererSectionCore | RendererSectionPerformance | RendererSectionDebug);
        break;
    case ImGuiRendererSettingsCategoryLighting:
        DrawRendererSettingsBody(context, "RendererSettingsLightingScroll", RendererSectionLighting);
        break;
    case ImGuiRendererSettingsCategoryShadows:
        DrawRendererSettingsBody(context, "RendererSettingsShadowsScroll", RendererSectionShadows);
        break;
    }
}

void ImGuiRendererPanelDraw(void *context, bool *isOpen) {
    (void)context;
    (void)isOpen;
    IM_ASSERT(false && "ImGuiRendererPanelDraw is deprecated. Use ImGuiRendererSettingsCategoryDraw from Settings modal.");
}

void ImGuiRendererSettingsDraw(void *context) {
    (void)context;
    IM_ASSERT(false && "ImGuiRendererSettingsDraw is deprecated. Use ImGuiRendererSettingsCategoryDraw from Settings modal.");
}
