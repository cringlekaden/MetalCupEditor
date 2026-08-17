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
extern "C" void MCESceneNotifyMutation(MCE_CTX);
extern "C" int32_t MCEProjectShaderSourceStatus(MCE_CTX, char *buffer, int32_t bufferSize);
extern "C" uint32_t MCEProjectGetExposureSettings(MCE_CTX,
                                                   uint32_t *mode, float *compensation, float *manualEV100,
                                                   float *aperture, float *shutterSeconds, float *iso,
                                                   uint32_t *meteringMode, float *histogramLogMin, float *histogramLogMax,
                                                   float *lowPercentile, float *highPercentile,
                                                   float *minimumEV100, float *maximumEV100,
                                                   float *darkAdaptationRate, float *lightAdaptationRate,
                                                   float *skyInfluenceCap, float *daylightKey, float *twilightKey,
                                                   float *nightKey, uint32_t *useOutdoorPrior);
extern "C" void MCEProjectSetExposureSettings(MCE_CTX,
                                               uint32_t mode, float compensation, float manualEV100,
                                               float aperture, float shutterSeconds, float iso,
                                               uint32_t meteringMode, float histogramLogMin, float histogramLogMax,
                                               float lowPercentile, float highPercentile,
                                               float minimumEV100, float maximumEV100,
                                               float darkAdaptationRate, float lightAdaptationRate,
                                               float skyInfluenceCap, float daylightKey, float twilightKey,
                                               float nightKey, uint32_t useOutdoorPrior);

namespace {
    void *EngineContextFromMCE(void *context) {
        return MCEContextGetEngineContext(context);
    }

    void NotifyRendererSettingsChanged(void *context) {
        if (context != nullptr) {
            MCESceneNotifyMutation(context);
        }
    }

    void ApplyBloomPresetDefaults(void *engineContext, int presetIndex) {
        if (presetIndex == 0) { // Low
            MCERendererSetBloomResolutionScale(engineContext, 4);
            MCERendererSetBloomMaxMips(engineContext, 3);
            MCERendererSetBloomThreshold(engineContext, 1.35f);
            MCERendererSetBloomKnee(engineContext, 0.22f);
            MCERendererSetBloomIntensity(engineContext, 0.14f);
        } else if (presetIndex == 1) { // Medium
            MCERendererSetBloomResolutionScale(engineContext, 4);
            MCERendererSetBloomMaxMips(engineContext, 4);
            MCERendererSetBloomThreshold(engineContext, 1.5f);
            MCERendererSetBloomKnee(engineContext, 0.18f);
            MCERendererSetBloomIntensity(engineContext, 0.13f);
        } else if (presetIndex == 2) { // High
            MCERendererSetBloomResolutionScale(engineContext, 2);
            MCERendererSetBloomMaxMips(engineContext, 4);
            MCERendererSetBloomThreshold(engineContext, 1.65f);
            MCERendererSetBloomKnee(engineContext, 0.16f);
            MCERendererSetBloomIntensity(engineContext, 0.12f);
        } else if (presetIndex == 3) { // Ultra
            MCERendererSetBloomResolutionScale(engineContext, 2);
            MCERendererSetBloomMaxMips(engineContext, 5);
            MCERendererSetBloomThreshold(engineContext, 1.8f);
            MCERendererSetBloomKnee(engineContext, 0.14f);
            MCERendererSetBloomIntensity(engineContext, 0.11f);
        }
    }

    void DrawProjectExposureSettings(void *context) {
        uint32_t mode = 0;
        float compensation = 0.0f;
        float manualEV100 = 14.0f;
        float aperture = 16.0f;
        float shutterSeconds = 1.0f / 125.0f;
        float iso = 100.0f;
        uint32_t meteringMode = 1;
        float histogramLogMin = -20.0f;
        float histogramLogMax = 16.0f;
        float lowPercentile = 0.05f;
        float highPercentile = 0.95f;
        float minimumEV100 = 2.0f;
        float maximumEV100 = 17.0f;
        float darkAdaptationRate = 3.0f;
        float lightAdaptationRate = 8.0f;
        float skyInfluenceCap = 0.35f;
        float daylightKey = 0.18f;
        float twilightKey = 0.09f;
        float nightKey = 0.04f;
        uint32_t useOutdoorPrior = 1;
        if (MCEProjectGetExposureSettings(context, &mode, &compensation, &manualEV100,
                                          &aperture, &shutterSeconds, &iso, &meteringMode,
                                          &histogramLogMin, &histogramLogMax, &lowPercentile,
                                          &highPercentile, &minimumEV100, &maximumEV100,
                                          &darkAdaptationRate, &lightAdaptationRate,
                                          &skyInfluenceCap, &daylightKey, &twilightKey,
                                          &nightKey, &useOutdoorPrior) == 0) {
            ImGui::TextDisabled("Open a project to edit inherited exposure defaults.");
            return;
        }

        bool dirty = false;
        int modeIndex = static_cast<int>(mode);
        const char *modeItems[] = {"Automatic Histogram", "Manual EV100", "Physical Camera"};
        if (EditorUI::BeginPropertyTable("ProjectExposureBasic")) {
            EditorUI::SetNextPropertyInfoTooltip("Default policy inherited by cameras unless a higher-priority source overrides this field. New projects use Automatic Histogram.");
            dirty |= EditorUI::PropertyCombo("Mode", &modeIndex, modeItems, IM_ARRAYSIZE(modeItems));
            EditorUI::SetNextPropertyInfoTooltip("Artistic offset applied after metering, in photographic stops.");
            dirty |= EditorUI::PropertyFloat("Compensation", &compensation, 0.05f, -5.0f, 5.0f, "%+.2f stops", true, true, 0.0f);
            if (modeIndex == 1) {
                EditorUI::SetNextPropertyInfoTooltip("Deterministic EV100. Engine scene-linear calibration uses EV100 15 as unity gain.");
                dirty |= EditorUI::PropertyFloat("Manual EV100", &manualEV100, 0.1f, -8.0f, 24.0f, "%.2f EV100", true, true, 14.0f);
            } else if (modeIndex == 2) {
                dirty |= EditorUI::PropertyFloat("Aperture (f)", &aperture, 0.1f, 0.7f, 64.0f, "f/%.1f", true, true, 16.0f);
                dirty |= EditorUI::PropertyFloat("Shutter (s)", &shutterSeconds, 0.0001f, 0.00001f, 60.0f, "%.5f s", true, true, 1.0f / 125.0f);
                dirty |= EditorUI::PropertyFloat("ISO", &iso, 1.0f, 1.0f, 204800.0f, "%.0f", true, true, 100.0f);
            }
            EditorUI::EndPropertyTable();
        }

        if (ImGui::TreeNodeEx("ProjectExposureAdvanced", ImGuiTreeNodeFlags_None, "Advanced")) {
            int meteringIndex = static_cast<int>(meteringMode);
            const char *meteringItems[] = {"Average", "Center Weighted", "Spot", "Texture Mask"};
            bool outdoorPrior = useOutdoorPrior != 0;
            if (EditorUI::BeginPropertyTable("ProjectExposureAdvancedTable")) {
                dirty |= EditorUI::PropertyCombo("Metering", &meteringIndex, meteringItems, IM_ARRAYSIZE(meteringItems));
                dirty |= EditorUI::PropertyFloat("Low Percentile", &lowPercentile, 0.005f, 0.0f, 0.49f, "%.3f", true, true, 0.05f);
                dirty |= EditorUI::PropertyFloat("High Percentile", &highPercentile, 0.005f, 0.51f, 1.0f, "%.3f", true, true, 0.95f);
                dirty |= EditorUI::PropertyFloat("Histogram Min", &histogramLogMin, 0.25f, -32.0f, 0.0f, "%.1f EV", true, true, -20.0f);
                dirty |= EditorUI::PropertyFloat("Histogram Max", &histogramLogMax, 0.25f, 1.0f, 32.0f, "%.1f EV", true, true, 16.0f);
                dirty |= EditorUI::PropertyFloat("Minimum EV100", &minimumEV100, 0.1f, -8.0f, 24.0f, "%.2f", true, true, 2.0f);
                dirty |= EditorUI::PropertyFloat("Maximum EV100", &maximumEV100, 0.1f, -8.0f, 24.0f, "%.2f", true, true, 17.0f);
                dirty |= EditorUI::PropertyFloat("Dark Adaptation", &darkAdaptationRate, 0.1f, 0.01f, 32.0f, "%.2f EV/s", true, true, 3.0f);
                dirty |= EditorUI::PropertyFloat("Light Adaptation", &lightAdaptationRate, 0.1f, 0.01f, 32.0f, "%.2f EV/s", true, true, 8.0f);
                dirty |= EditorUI::PropertyFloat("Sky Influence Cap", &skyInfluenceCap, 0.01f, 0.0f, 1.0f, "%.2f", true, true, 0.35f);
                dirty |= EditorUI::PropertyBool("Outdoor Prior", &outdoorPrior);
                dirty |= EditorUI::PropertyFloat("Day Target Key", &daylightKey, 0.005f, 0.005f, 1.0f, "%.3f", true, true, 0.18f);
                dirty |= EditorUI::PropertyFloat("Twilight Target Key", &twilightKey, 0.005f, 0.005f, 1.0f, "%.3f", true, true, 0.09f);
                dirty |= EditorUI::PropertyFloat("Night Target Key", &nightKey, 0.005f, 0.005f, 1.0f, "%.3f", true, true, 0.04f);
                EditorUI::EndPropertyTable();
            }
            meteringMode = static_cast<uint32_t>(meteringIndex);
            useOutdoorPrior = outdoorPrior ? 1u : 0u;
            ImGui::TreePop();
        }

        if (dirty) {
            MCEProjectSetExposureSettings(context, static_cast<uint32_t>(modeIndex), compensation,
                                          manualEV100, aperture, shutterSeconds, iso, meteringMode,
                                          histogramLogMin, histogramLogMax, lowPercentile, highPercentile,
                                          minimumEV100, maximumEV100, darkAdaptationRate,
                                          lightAdaptationRate, skyInfluenceCap, daylightKey,
                                          twilightKey, nightKey, useOutdoorPrior);
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
        SectionTitle("Shader Source");
        char shaderStatus[1024] = {};
        if (MCEProjectShaderSourceStatus(context, shaderStatus, sizeof(shaderStatus)) > 0) {
            ImGui::TextWrapped("%s", shaderStatus);
        } else {
            ImGui::TextDisabled("Canonical Engine shaders");
        }
        EditorUI::StandardSpacing();

        SectionTitle("Project Exposure");
        DrawProjectExposureSettings(context);
        EditorUI::StandardSpacing();

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
            const uint32_t maxSceneMSAA = MCERendererGetMaxSceneMSAASampleCount(engineContext);
            const char* msaaItems[] = { "Off", "4x", "8x" };
            const int msaaItemCount = maxSceneMSAA >= 8 ? 3 : 2;
            uint32_t sceneMSAA = MCERendererGetSceneMSAASampleCount(engineContext);
            int msaaIndex = sceneMSAA >= 8 ? 2 : (sceneMSAA >= 4 ? 1 : 0);
            if (msaaIndex >= msaaItemCount) {
                msaaIndex = msaaItemCount - 1;
            }
            EditorUI::SetNextPropertyInfoTooltip("Scene geometry multisample anti-aliasing.\nUnits: sample count.\nPerformance: medium-to-high GPU bandwidth cost.\nPersistence: Editor.\nApplies to scene geometry only; post overlays and some cutout materials are not covered.");
            if (EditorUI::PropertyCombo("Scene MSAA", &msaaIndex, msaaItems, msaaItemCount)) {
                const uint32_t msaaValue = (msaaIndex == 0) ? 0u : (msaaIndex == 2 ? 8u : 4u);
                MCERendererSetSceneMSAASampleCount(engineContext, msaaValue);
            }
            EditorUI::EndPropertyTable();
        }
        EditorUI::StandardSpacing();
    }

    if (SectionEnabled(sectionMask, RendererSectionCore)) {
        SectionTitle("Ambient Occlusion");
        bool aoEnabled = MCERendererGetAOEnabled(engineContext) != 0;
        ImGui::PushID("AmbientOcclusion");
        if (EditorUI::BeginPropertyTable("AOTable")) {
            EditorUI::SetNextPropertyInfoTooltip("Enable ambient occlusion.\nUnits: boolean.\nPersistence: Project.\nUse AO Raw and AO Filtered debug views in the Debug section to inspect grounding and denoise quality.");
            if (EditorUI::PropertyBool("Enabled", &aoEnabled)) {
                MCERendererSetAOEnabled(engineContext, aoEnabled ? 1 : 0);
            }
            int aoMethod = static_cast<int>(MCERendererGetAOMethod(engineContext));
            const char* aoMethodItems[] = { "SAO" };
            EditorUI::SetNextPropertyInfoTooltip("Ambient occlusion implementation.\nPersistence: Project.\nSAO is the only active screen-space AO path in the renderer right now.");
            if (EditorUI::PropertyCombo("Method", &aoMethod, aoMethodItems, IM_ARRAYSIZE(aoMethodItems))) {
                MCERendererSetAOMethod(engineContext, static_cast<uint32_t>(aoMethod));
            }
            if (aoEnabled) {
                float aoRadius = MCERendererGetAORadius(engineContext);
                EditorUI::SetNextPropertyInfoTooltip("Grounding reach in view-space units.\nUnits: scalar.\nIncrease for broader mesh-to-ground and mesh-to-mesh grounding; keep it low enough to avoid broad ambient staining.");
                if (EditorUI::PropertyFloat("Radius", &aoRadius, 0.01f, 0.10f, 1.00f, "%.3f", true, true, 0.35f)) {
                    MCERendererSetAORadius(engineContext, aoRadius);
                }
                float aoIntensity = MCERendererGetAOIntensity(engineContext);
                EditorUI::SetNextPropertyInfoTooltip("Overall AO strength.\nUnits: scalar.\nTune this after radius; use it to scale visible grounding without changing contact footprint.");
                if (EditorUI::PropertyFloat("Intensity", &aoIntensity, 0.025f, 0.0f, 3.0f, "%.3f", true, true, 1.25f)) {
                    MCERendererSetAOIntensity(engineContext, aoIntensity);
                }
            }
            EditorUI::EndPropertyTable();
        }

        if (aoEnabled) {
            ImGui::Spacing();
            if (ImGui::TreeNodeEx("AOAdvancedTuning", ImGuiTreeNodeFlags_None, "Advanced")) {
                ImGui::TextWrapped("Advanced controls refine the current SAO pass after the main AO shape is set with Radius and Intensity.");
                ImGui::Spacing();
                if (EditorUI::BeginPropertyTable("AOAdvancedTable")) {
                    float aoBias = MCERendererGetAOBias(engineContext);
                    EditorUI::SetNextPropertyInfoTooltip("Minimum receiver-plane separation before a nearby sample can occlude.\nUnits: scalar.\nRaise this if smooth surfaces self-darken; lower it if contact patches disappear.");
                    if (EditorUI::PropertyFloat("Bias", &aoBias, 0.001f, 0.0f, 0.05f, "%.3f", true, true, 0.008f)) {
                        MCERendererSetAOBias(engineContext, aoBias);
                    }
                    float aoSharpness = MCERendererGetAOSharpness(engineContext);
                    EditorUI::SetNextPropertyInfoTooltip("Bilateral blur edge preservation.\nUnits: scalar.\nHigher values keep narrow contacts tighter; lower values smooth harder but can wash out grounding.");
                    if (EditorUI::PropertyFloat("Sharpness", &aoSharpness, 0.25f, 4.0f, 40.0f, "%.2f", true, true, 24.0f)) {
                        MCERendererSetAOSharpness(engineContext, aoSharpness);
                    }
                    float aoPower = MCERendererGetAOPower(engineContext);
                    EditorUI::SetNextPropertyInfoTooltip("Post-evaluate contrast shaping.\nUnits: scalar.\nHigher values tighten contact contrast; lower values preserve more mid-strength ambient response.");
                    if (EditorUI::PropertyFloat("Power", &aoPower, 0.05f, 0.5f, 2.0f, "%.3f", true, true, 1.0f)) {
                        MCERendererSetAOPower(engineContext, aoPower);
                    }
                    EditorUI::EndPropertyTable();
                }
                ImGui::TreePop();
            }
        }
        ImGui::PopID();

        EditorUI::StandardSpacing();
    }

    if (SectionEnabled(sectionMask, RendererSectionCore)) {
        SectionTitle("Output");
        if (EditorUI::BeginPropertyTable("TonemapTable")) {
            const char* outputItems[] = { "MetalCup Filmic v1" };
            int outputIndex = 0;
            EditorUI::SetNextPropertyInfoTooltip("Phase 1 fixed output transform. Scene-linear HDR is exposed once, mapped with MetalCup Filmic v1, then encoded to sRGB once.");
            ImGui::BeginDisabled(true);
            EditorUI::PropertyCombo("Transform", &outputIndex, outputItems, IM_ARRAYSIZE(outputItems));
            const char* encodingItems[] = { "sRGB (single encode)" };
            int encodingIndex = 0;
            EditorUI::PropertyCombo("Encoding", &encodingIndex, encodingItems, IM_ARRAYSIZE(encodingItems));
            ImGui::EndDisabled();
            EditorUI::EndPropertyTable();
        }
        EditorUI::StandardSpacing();
    }

    if (SectionEnabled(sectionMask, RendererSectionCore)) {
        SectionTitle("Local Fog");
        ImGui::TextWrapped("Local participating-medium controls live on the active Environment component. Renderer-global fog color, start-distance, horizon, and extra-distance compensation controls are inert compatibility data.");
        ImGui::TextDisabled("Use the Environment inspector to author extinction, scattering albedo, base height, scale height, and anisotropy.");
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
            float outlineColor[3] = { 1.0f, 0.9f, 0.2f };
            MCERendererGetOutlineColor(engineContext, &outlineColor[0], &outlineColor[1], &outlineColor[2]);
            EditorUI::SetNextPropertyInfoTooltip("Outline color tint.\nUnits: RGB.\nPerformance: low.\nPersistence: Project.");
            if (EditorUI::PropertyColor3("Color", outlineColor)) {
                MCERendererSetOutlineColor(engineContext, outlineColor[0], outlineColor[1], outlineColor[2]);
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
                NotifyRendererSettingsChanged(context);
            }
            if (shadowsEnabled) {
                bool directionalEnabled = MCERendererGetDirectionalShadowsEnabled(engineContext) != 0;
                EditorUI::SetNextPropertyInfoTooltip("Directional light shadow maps.\nUnits: boolean.\nPerformance: medium-to-high GPU cost.\nPersistence: Project.");
                if (EditorUI::PropertyBool("Directional Shadows", &directionalEnabled)) {
                    MCERendererSetDirectionalShadowsEnabled(engineContext, directionalEnabled ? 1 : 0);
                    NotifyRendererSettingsChanged(context);
                }
            }
            EditorUI::EndPropertyTable();
        }
        EditorUI::StandardSpacing();

        SectionTitle("Shadows");
        if (EditorUI::BeginPropertyTable("ShadowsTable")) {
            bool shadowsEnabled = MCERendererGetShadowsEnabled(engineContext) != 0;
            if (shadowsEnabled) {
                const char* filterItems[] = { "Hard", "PCF", "PCSS (Experimental)" };
                int filterMode = static_cast<int>(MCERendererGetShadowFilterMode(engineContext));
                filterMode = filterMode < 0 || filterMode > 2 ? 1 : filterMode;

                const char* resolutionItems[] = { "1024", "2048", "4096" };
                uint32_t currentRes = MCERendererGetShadowMapResolution(engineContext);
                int resIndex = currentRes == 1024 ? 0 : (currentRes == 4096 ? 2 : 1);
                EditorUI::SetNextPropertyInfoTooltip("Shadow map resolution.\nUnits: pixels.\nPerformance: higher values increase VRAM + GPU cost.\nPersistence: Project.");
                if (EditorUI::PropertyCombo("Resolution", &resIndex, resolutionItems, IM_ARRAYSIZE(resolutionItems))) {
                    uint32_t resolution = (resIndex == 0) ? 1024 : (resIndex == 2 ? 4096 : 2048);
                    MCERendererSetShadowMapResolution(engineContext, resolution);
                    NotifyRendererSettingsChanged(context);
                }

                int cascades = static_cast<int>(MCERendererGetShadowCascadeCount(engineContext));
                EditorUI::SetNextPropertyInfoTooltip("Directional shadow cascade count.\nUnits: count.\nPerformance: each cascade adds render cost.\nPersistence: Project.");
                if (EditorUI::PropertyInt("Cascades", &cascades, 1, 4)) {
                    MCERendererSetShadowCascadeCount(engineContext, static_cast<uint32_t>(cascades));
                    NotifyRendererSettingsChanged(context);
                }
                float splitLambda = MCERendererGetShadowSplitLambda(engineContext);
                if (EditorUI::PropertyFloat("Split Lambda", &splitLambda,
                                            EditorUIConstants::kShadowSplitLambdaStep,
                                            EditorUIConstants::kShadowSplitLambdaMin,
                                            EditorUIConstants::kShadowSplitLambdaMax, "%.2f", true, true, 0.65f)) {
                    MCERendererSetShadowSplitLambda(engineContext, splitLambda);
                    NotifyRendererSettingsChanged(context);
                }

                float depthBias = MCERendererGetShadowDepthBias(engineContext);
                if (EditorUI::PropertyFloat("Depth Bias", &depthBias,
                                            EditorUIConstants::kShadowDepthBiasStep,
                                            EditorUIConstants::kShadowDepthBiasMin,
                                            EditorUIConstants::kShadowDepthBiasMax, "%.5f", true, true, 0.0005f)) {
                    MCERendererSetShadowDepthBias(engineContext, depthBias);
                    NotifyRendererSettingsChanged(context);
                }
                float normalBias = MCERendererGetShadowNormalBias(engineContext);
                if (EditorUI::PropertyFloat("Normal Bias", &normalBias,
                                            EditorUIConstants::kShadowNormalBiasStep,
                                            EditorUIConstants::kShadowNormalBiasMin,
                                            EditorUIConstants::kShadowNormalBiasMax, "%.3f", true, true, 0.01f)) {
                    MCERendererSetShadowNormalBias(engineContext, normalBias);
                    NotifyRendererSettingsChanged(context);
                }
                float maxDistance = MCERendererGetShadowMaxDistance(engineContext);
                if (EditorUI::PropertyFloat("Max Distance", &maxDistance,
                                            EditorUIConstants::kShadowMaxDistanceStep,
                                            EditorUIConstants::kShadowMaxDistanceMin,
                                            EditorUIConstants::kShadowMaxDistanceMax, "%.1f", true, true, 100.0f)) {
                    MCERendererSetShadowMaxDistance(engineContext, maxDistance);
                    NotifyRendererSettingsChanged(context);
                }
                float fadeOut = MCERendererGetShadowFadeOutDistance(engineContext);
                if (EditorUI::PropertyFloat("Fade Out", &fadeOut,
                                            EditorUIConstants::kShadowFadeOutStep,
                                            EditorUIConstants::kShadowFadeOutMin,
                                            EditorUIConstants::kShadowFadeOutMax, "%.1f", true, true, 10.0f)) {
                    MCERendererSetShadowFadeOutDistance(engineContext, fadeOut);
                    NotifyRendererSettingsChanged(context);
                }

                EditorUI::SetNextPropertyInfoTooltip("Selects the active shadow filtering path.\nUnits: enum.\nPerformance: Hard is cheapest, PCSS is the most expensive.\nPersistence: Project.");
                if (EditorUI::PropertyCombo("Shadow Filter", &filterMode, filterItems, IM_ARRAYSIZE(filterItems))) {
                    MCERendererSetShadowFilterMode(engineContext, static_cast<uint32_t>(filterMode));
                    NotifyRendererSettingsChanged(context);
                }

                if (filterMode == 1) {
                    float pcfRadius = MCERendererGetShadowPCFRadius(engineContext);
                    EditorUI::SetNextPropertyInfoTooltip("PCF kernel radius.\nUnits: shadow texels.\nPerformance: higher values soften and cost more.\nPersistence: Project.");
                    if (EditorUI::PropertyFloat("PCF Radius", &pcfRadius,
                                                EditorUIConstants::kShadowPCFRadiusStep,
                                                EditorUIConstants::kShadowPCFRadiusMin,
                                                EditorUIConstants::kShadowPCFRadiusMax, "%.2f", true, true, 1.0f)) {
                        MCERendererSetShadowPCFRadius(engineContext, pcfRadius);
                        NotifyRendererSettingsChanged(context);
                    }

                    const char* pcfPresetItems[] = { "Low", "Medium", "High", "Ultra", "Custom" };
                    int pcfPreset = static_cast<int>(MCERendererGetShadowPCFQualityPreset(engineContext));
                    pcfPreset = pcfPreset < 0 || pcfPreset > 4 ? 2 : pcfPreset;
                    EditorUI::SetNextPropertyInfoTooltip("Per-cascade PCF tap preset. Editing this section keeps shadows in PCF mode.\nUnits: preset.\nPerformance: higher presets cost more near camera.\nPersistence: Project.");
                    if (EditorUI::PropertyCombo("PCF Preset", &pcfPreset, pcfPresetItems, IM_ARRAYSIZE(pcfPresetItems))) {
                        MCERendererSetShadowPCFQualityPreset(engineContext, static_cast<uint32_t>(pcfPreset));
                        filterMode = 1;
                        NotifyRendererSettingsChanged(context);
                    }

                    if (pcfPreset == 4) {
                        int taps0 = static_cast<int>(MCERendererGetShadowPCFTapsCascade0(engineContext));
                        int taps1 = static_cast<int>(MCERendererGetShadowPCFTapsCascade1(engineContext));
                        int taps2 = static_cast<int>(MCERendererGetShadowPCFTapsCascade2(engineContext));
                        int taps3 = static_cast<int>(MCERendererGetShadowPCFTapsCascade3(engineContext));
                        EditorUI::SetNextPropertyInfoTooltip("Manual taps for the nearest cascade. Editing tap counts keeps shadows in PCF mode.\nUnits: samples.\nPerformance: higher values increase filter cost.\nPersistence: Project.");
                        if (EditorUI::PropertyInt("Cascade 0 Taps", &taps0, EditorUIConstants::kShadowPCFTapsMin, EditorUIConstants::kShadowPCFTapsMax)) {
                            MCERendererSetShadowPCFTapsCascade0(engineContext, static_cast<uint32_t>(taps0));
                            filterMode = 1;
                            NotifyRendererSettingsChanged(context);
                        }
                        if (EditorUI::PropertyInt("Cascade 1 Taps", &taps1, EditorUIConstants::kShadowPCFTapsMin, EditorUIConstants::kShadowPCFTapsMax)) {
                            MCERendererSetShadowPCFTapsCascade1(engineContext, static_cast<uint32_t>(taps1));
                            filterMode = 1;
                            NotifyRendererSettingsChanged(context);
                        }
                        if (EditorUI::PropertyInt("Cascade 2 Taps", &taps2, EditorUIConstants::kShadowPCFTapsMin, EditorUIConstants::kShadowPCFTapsMax)) {
                            MCERendererSetShadowPCFTapsCascade2(engineContext, static_cast<uint32_t>(taps2));
                            filterMode = 1;
                            NotifyRendererSettingsChanged(context);
                        }
                        if (EditorUI::PropertyInt("Cascade 3 Taps", &taps3, EditorUIConstants::kShadowPCFTapsMin, EditorUIConstants::kShadowPCFTapsMax)) {
                            MCERendererSetShadowPCFTapsCascade3(engineContext, static_cast<uint32_t>(taps3));
                            filterMode = 1;
                            NotifyRendererSettingsChanged(context);
                        }
                    }
                } else if (filterMode == 2) {
                    float lightWorldSize = MCERendererGetShadowPCSSLightWorldSize(engineContext);
                    EditorUI::SetNextPropertyInfoTooltip("Apparent shadow-casting light size used by PCSS penumbra estimation.\nUnits: world units.\nPerformance: low direct cost, changes softness.\nPersistence: Project.");
                    if (EditorUI::PropertyFloat("Light World Size", &lightWorldSize,
                                                EditorUIConstants::kShadowPCSSLightSizeStep,
                                                EditorUIConstants::kShadowPCSSLightSizeMin,
                                                EditorUIConstants::kShadowPCSSLightSizeMax, "%.2f", true, true, 1.0f)) {
                        MCERendererSetShadowPCSSLightWorldSize(engineContext, lightWorldSize);
                        NotifyRendererSettingsChanged(context);
                    }

                    float minRadius = MCERendererGetShadowPCSSMinRadius(engineContext);
                    EditorUI::SetNextPropertyInfoTooltip("Minimum PCSS filter radius clamp.\nUnits: shadow texels.\nPersistence: Project.");
                    if (EditorUI::PropertyFloat("Min Filter Radius", &minRadius,
                                                EditorUIConstants::kShadowPCSSMinRadiusStep,
                                                EditorUIConstants::kShadowPCSSMinRadiusMin,
                                                EditorUIConstants::kShadowPCSSMinRadiusMax, "%.2f", true, true, 1.0f)) {
                        MCERendererSetShadowPCSSMinRadius(engineContext, minRadius);
                        NotifyRendererSettingsChanged(context);
                    }

                    float maxRadius = MCERendererGetShadowPCSSMaxRadius(engineContext);
                    EditorUI::SetNextPropertyInfoTooltip("Maximum PCSS filter radius clamp.\nUnits: shadow texels.\nPerformance: higher values can get expensive.\nPersistence: Project.");
                    if (EditorUI::PropertyFloat("Max Filter Radius", &maxRadius,
                                                EditorUIConstants::kShadowPCSSMaxRadiusStep,
                                                EditorUIConstants::kShadowPCSSMaxRadiusMin,
                                                EditorUIConstants::kShadowPCSSMaxRadiusMax, "%.2f", true, true, 6.0f)) {
                        MCERendererSetShadowPCSSMaxRadius(engineContext, maxRadius);
                        NotifyRendererSettingsChanged(context);
                    }

                    float blockerRadius = MCERendererGetShadowPCSSBlockerRadius(engineContext);
                    EditorUI::SetNextPropertyInfoTooltip("Blocker search radius for PCSS.\nUnits: shadow texels.\nPerformance: larger searches are costlier.\nPersistence: Project.");
                    if (EditorUI::PropertyFloat("Blocker Search Radius", &blockerRadius,
                                                EditorUIConstants::kShadowPCSSBlockerRadiusStep,
                                                EditorUIConstants::kShadowPCSSBlockerRadiusMin,
                                                EditorUIConstants::kShadowPCSSBlockerRadiusMax, "%.2f", true, true, 3.0f)) {
                        MCERendererSetShadowPCSSBlockerRadius(engineContext, blockerRadius);
                        NotifyRendererSettingsChanged(context);
                    }

                    int blockerSamples = static_cast<int>(MCERendererGetShadowPCSSBlockerSamples(engineContext));
                    EditorUI::SetNextPropertyInfoTooltip("Number of blocker search samples.\nUnits: samples.\nPerformance: higher values increase PCSS cost.\nPersistence: Project.");
                    if (EditorUI::PropertyInt("Blocker Samples", &blockerSamples, 1, 64)) {
                        MCERendererSetShadowPCSSBlockerSamples(engineContext, static_cast<uint32_t>(blockerSamples));
                        NotifyRendererSettingsChanged(context);
                    }

                    int filterSamples = static_cast<int>(MCERendererGetShadowPCSSFilterSamples(engineContext));
                    EditorUI::SetNextPropertyInfoTooltip("Number of PCSS filter samples.\nUnits: samples.\nPerformance: higher values increase soft shadow quality and cost.\nPersistence: Project.");
                    if (EditorUI::PropertyInt("Filter Samples", &filterSamples, 1, 64)) {
                        MCERendererSetShadowPCSSFilterSamples(engineContext, static_cast<uint32_t>(filterSamples));
                        NotifyRendererSettingsChanged(context);
                    }

                    bool noiseEnabled = MCERendererGetShadowPCSSNoiseEnabled(engineContext) != 0;
                    EditorUI::SetNextPropertyInfoTooltip("Enables PCSS noise/jittering to break up sampling patterns.\nUnits: boolean.\nPersistence: Project.");
                    if (EditorUI::PropertyBool("Noise", &noiseEnabled)) {
                        MCERendererSetShadowPCSSNoiseEnabled(engineContext, noiseEnabled ? 1 : 0);
                        NotifyRendererSettingsChanged(context);
                    }
                }
            }
            EditorUI::EndPropertyTable();
        }

        if (MCERendererGetShadowsEnabled(engineContext) != 0 && ImGui::TreeNodeEx("ShadowModeGuidance", ImGuiTreeNodeFlags_DefaultOpen, "Filter Mode Guidance")) {
            const uint32_t filterMode = MCERendererGetShadowFilterMode(engineContext);
            if (filterMode == 0) {
                ImGui::TextWrapped("Hard shadows use no soft filtering. This is the fastest mode and is useful for bias tuning and debugging.");
            } else if (filterMode == 1) {
                ImGui::TextWrapped("PCF softens edges with fixed-kernel filtering. Adjusting PCF preset or tap counts keeps the renderer in PCF mode.");
            } else {
                ImGui::TextWrapped("PCSS is exposed for editor experimentation. It estimates penumbra size from blocker depth and is the softest, most expensive option.");
            }
            ImGui::TreePop();
        }
        EditorUI::StandardSpacing();
    }

    if (SectionEnabled(sectionMask, RendererSectionGrid)) {
        SectionTitle("Viewport Grid");
        if (EditorUI::BeginPropertyTable("GridTable")) {
            bool gridEnabled = MCERendererGetGridEnabled(engineContext) != 0;
            if (EditorUI::PropertyBool("Enable Grid", &gridEnabled)) {
                MCERendererSetGridEnabled(engineContext, gridEnabled ? 1 : 0);
                NotifyRendererSettingsChanged(context);
            }
            float gridOpacity = MCERendererGetGridOpacity(engineContext);
            if (EditorUI::PropertyFloat("Opacity", &gridOpacity, EditorUIConstants::kGridOpacityStep,
                                        EditorUIConstants::kGridOpacityMin, EditorUIConstants::kGridOpacityMax, "%.2f", true, true, EditorUIConstants::kDefaultGridOpacity)) {
                MCERendererSetGridOpacity(engineContext, gridOpacity);
                NotifyRendererSettingsChanged(context);
            }
            float gridFade = MCERendererGetGridFadeDistance(engineContext);
            if (EditorUI::PropertyFloat("Fade Distance", &gridFade, EditorUIConstants::kGridFadeStep,
                                        EditorUIConstants::kGridFadeMin, EditorUIConstants::kGridFadeMax, "%.1f", true, true, EditorUIConstants::kDefaultGridFadeDistance)) {
                MCERendererSetGridFadeDistance(engineContext, gridFade);
                NotifyRendererSettingsChanged(context);
            }
            float gridMajor = MCERendererGetGridMajorLineEvery(engineContext);
            if (EditorUI::PropertyFloat("Major Line Every", &gridMajor, EditorUIConstants::kGridMajorLineStep,
                                        EditorUIConstants::kGridMajorLineMin, EditorUIConstants::kGridMajorLineMax, "%.0f", true, true, EditorUIConstants::kDefaultGridMajorLineEvery)) {
                MCERendererSetGridMajorLineEvery(engineContext, gridMajor);
                NotifyRendererSettingsChanged(context);
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
            const char* iblItems[] = { "Low", "Medium", "High", "Ultra", "Custom" };
            int iblPreset = static_cast<int>(MCERendererGetIBLQualityPreset(engineContext));
            if (iblPreset < 0 || iblPreset > 4) { iblPreset = 4; }
            EditorUI::SetNextPropertyInfoTooltip("IBL generation quality preset.\nUnits: preset.\nPerformance: higher presets increase build time and cost.\nPersistence: Project.");
            if (EditorUI::PropertyCombo("IBL Quality", &iblPreset, iblItems, IM_ARRAYSIZE(iblItems))) {
                MCERendererSetIBLQualityPreset(engineContext, static_cast<uint32_t>(iblPreset));
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
        if (MCERendererGetIBLEnabled(engineContext) != 0
            && ImGui::TreeNodeEx("IBLAdvancedTuning", ImGuiTreeNodeFlags_None, "Advanced IBL Tuning")) {
            ImGui::TextWrapped("These controls are intended for renderer experimentation and compatibility tuning. Normal indirect brightness should come from the sky model and exposure, not manual global IBL gain. Use these controls only for specular response, specular AA behavior, and compatibility debugging.");
            ImGui::Spacing();
            if (EditorUI::BeginPropertyTable("IBLAdvancedTable")) {
                float minRoughness = MCERendererGetIBLSpecularMinRoughness(engineContext);
                EditorUI::SetNextPropertyInfoTooltip("Minimum roughness used for specular IBL lookup.\nUnits: roughness.\nPerformance: negligible.\nPersistence: Project.");
                if (EditorUI::PropertyFloat("Specular Min Roughness", &minRoughness, 0.005f, 0.0f, 1.0f, "%.3f", true, true, 0.06f)) {
                    MCERendererSetIBLSpecularMinRoughness(engineContext, minRoughness);
                }

                float specularAAStrength = MCERendererGetSpecularAAStrength(engineContext);
                EditorUI::SetNextPropertyInfoTooltip("Strength of specular anti-aliasing applied before lighting.\nUnits: scalar.\nPerformance: low.\nPersistence: Project.");
                if (EditorUI::PropertyFloat("Specular AA Strength", &specularAAStrength, 0.05f, 0.0f, 4.0f, "%.2f", true, true, 1.0f)) {
                    MCERendererSetSpecularAAStrength(engineContext, specularAAStrength);
                }

                float normalMipBias = MCERendererGetNormalMapMipBias(engineContext);
                EditorUI::SetNextPropertyInfoTooltip("Global mip bias for normal map sampling.\nUnits: mip bias.\nPerformance: negligible.\nPersistence: Project.");
                if (EditorUI::PropertyFloat("Normal Map Mip Bias", &normalMipBias, 0.05f, -4.0f, 4.0f, "%.2f", true, true, 0.0f)) {
                    MCERendererSetNormalMapMipBias(engineContext, normalMipBias);
                }

                float grazingNormalMipBias = MCERendererGetNormalMapMipBiasGrazing(engineContext);
                EditorUI::SetNextPropertyInfoTooltip("Additional normal map mip bias applied at grazing angles.\nUnits: mip bias.\nPerformance: negligible.\nPersistence: Project.");
                if (EditorUI::PropertyFloat("Normal Mip Bias (Grazing)", &grazingNormalMipBias, 0.05f, 0.0f, 4.0f, "%.2f", true, true, 0.6f)) {
                    MCERendererSetNormalMapMipBiasGrazing(engineContext, grazingNormalMipBias);
                }
                EditorUI::EndPropertyTable();
            }
            ImGui::TreePop();
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
            bool disableLocalProbeParallaxCorrection = MCERendererGetDisableLocalProbeParallaxCorrection(engineContext) != 0;
            EditorUI::SetNextPropertyInfoTooltip("Diagnostic A/B toggle for local reflection probes. When enabled, local probe specular sampling falls back to the older uncorrected lookup direction.\nUnits: boolean.\nPerformance: negligible.\nPersistence: Project.");
            if (EditorUI::PropertyBool("Disable Probe Parallax Correction", &disableLocalProbeParallaxCorrection)) {
                MCERendererSetDisableLocalProbeParallaxCorrection(engineContext, disableLocalProbeParallaxCorrection ? 1 : 0);
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
                "Tile Light Count",
                "Shadow Cascade Index",
                "Shadow Cascade Blend",
                "Shadow Factor",
                "Shadow Bias Stress",
                "Scene Depth",
                "Scene Normals (View)",
                "Scene Normals (World)",
                "AO Raw",
                "AO Filtered",
                "AO Normals (View)",
                "Reconstructed View Position",
                "Fog Factor",
                "Fog Transmittance",
                "Global Specular IBL",
                "Local Probe Specular IBL",
                "Local Probe Weight",
                "Direct + Global Specular",
                "Direct + Local Specular",
                "Direct + Mixed Specular",
                "Direct Specular Only",
                "Sun Vector Alignment",
                "Fog Optical Depth",
                "Fog In-scattered Radiance",
                "Fog Linear Distance",
                "Fog Density",
                "Fog Ambient Scattering",
                "Fog Directional Scattering",
                "Fog Pixel Classification",
                "AO Valid Samples",
                "AO Obscurance",
                "AO Production Depth",
                "AO Indirect Factor"
            };
            int debugMode = static_cast<int>(MCERendererGetShadingDebugMode(engineContext));
            EditorUI::SetNextPropertyInfoTooltip("Visualization mode for renderer debugging.\nIncludes shadow-specific views for cascade selection, blend bands, final shadowing, and bias pressure.\nPersistence: Project.");
            if (EditorUI::PropertyCombo("Debug View", &debugMode, debugItems, IM_ARRAYSIZE(debugItems))) {
                MCERendererSetShadingDebugMode(engineContext, static_cast<uint32_t>(debugMode));
                if ((debugMode == 16 || debugMode == 17 || debugMode == 18 || debugMode == 19) && MCERendererGetForwardPlusEnabled(engineContext) == 0) {
                    MCERendererSetForwardPlusEnabled(engineContext, 1);
                }
            }
            bool orientationSkybox = MCERendererGetDiagnosticOrientationSkyboxEnabled(engineContext) != 0;
            EditorUI::SetNextPropertyInfoTooltip("Render the generated cubemap orientation pattern as the visible sky/background. Diagnostic only; does not change authored Environment settings.\nPersistence: Project.");
            if (EditorUI::PropertyBool("Orientation Pattern Skybox", &orientationSkybox)) {
                MCERendererSetDiagnosticOrientationSkyboxEnabled(engineContext, orientationSkybox ? 1 : 0);
            }
            bool orientationGlobalIBL = MCERendererGetDiagnosticOrientationGlobalIBLEnabled(engineContext) != 0;
            EditorUI::SetNextPropertyInfoTooltip("Use the generated cubemap orientation pattern as the global environment, irradiance, and prefiltered IBL source. Diagnostic only.\nPersistence: Project.");
            if (EditorUI::PropertyBool("Orientation Pattern Global IBL", &orientationGlobalIBL)) {
                MCERendererSetDiagnosticOrientationGlobalIBLEnabled(engineContext, orientationGlobalIBL ? 1 : 0);
            }
            bool orientationLocalProbe = MCERendererGetDiagnosticOrientationLocalProbeEnabled(engineContext) != 0;
            EditorUI::SetNextPropertyInfoTooltip("Override selected local reflection probe prefiltered texture with the generated orientation pattern. Diagnostic only; probe capture and blending are unchanged.\nPersistence: Project.");
            if (EditorUI::PropertyBool("Orientation Pattern Local Probe", &orientationLocalProbe)) {
                MCERendererSetDiagnosticOrientationLocalProbeEnabled(engineContext, orientationLocalProbe ? 1 : 0);
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
            } else if (debugMode == 20) {
                ImGui::TextDisabled("Shadow Cascade Index: visualizes which directional-shadow cascade shades each pixel.");
            } else if (debugMode == 21) {
                ImGui::TextDisabled("Shadow Cascade Blend: visualizes the active cross-fade band between adjacent cascades.");
            } else if (debugMode == 22) {
                ImGui::TextDisabled("Shadow Factor: visualizes final directional shadow attenuation after filtering and fades.");
            } else if (debugMode == 23) {
                ImGui::TextDisabled("Shadow Bias Stress: heatmap of how aggressive the current bias is relative to cascade texel density.");
            } else if (debugMode == 24) {
                ImGui::TextDisabled("Scene Depth: visualizes canonical scene.depth as true linear view-space depth normalized against the camera far plane.");
            } else if (debugMode == 25) {
                ImGui::TextDisabled("Scene Normals (View): visualizes canonical scene.normals directly in view space.");
            } else if (debugMode == 26) {
                ImGui::TextDisabled("Scene Normals (World): decodes canonical scene.normals and transforms them by inverse view for easier inspection.");
            } else if (debugMode == 27) {
                ImGui::TextDisabled("AO Raw: full-resolution AO before denoise. Use this to judge radius coverage, grounding, and whether contacts are too mesh-local.");
            } else if (debugMode == 28) {
                ImGui::TextDisabled("AO Filtered: bilateral-denoised AO intermediate. Watch for washed detail, edge halos, and unstable wide dark bands.");
            } else if (debugMode == 29) {
                ImGui::TextDisabled("AO Normals (View): visualizes the dedicated AO normals buffer used by the screen-space AO path.");
            } else if (debugMode == 30) {
                ImGui::TextDisabled("Reconstructed View Position: visualizes reconstructed view-space XY and depth from scene.depth to validate screen-to-view reprojection.");
            } else if (debugMode == 31) {
                ImGui::TextDisabled("Fog Factor: grayscale fog coverage from the active height fog evaluation. Black is clear, white is fully fogged.");
            } else if (debugMode == 32) {
                ImGui::TextDisabled("Fog Transmittance: grayscale surviving scene contribution after height fog. White is clear, black is fully extinguished.");
            } else if (debugMode == 33) {
                ImGui::TextDisabled("Global Specular IBL: shows only the global prefiltered environment specular term before local probe mixing.");
            } else if (debugMode == 34) {
                ImGui::TextDisabled("Local Probe Specular IBL: shows only the selected local reflection probe specular term, black when no local probe contributes.");
            } else if (debugMode == 35) {
                ImGui::TextDisabled("Local Probe Weight: grayscale visualization of active local reflection probe influence.");
            } else if (debugMode == 36) {
                ImGui::TextDisabled("Direct + Global Specular: direct lighting plus global prefiltered environment specular, excluding diffuse IBL and local probe specular.");
            } else if (debugMode == 37) {
                ImGui::TextDisabled("Direct + Local Specular: direct lighting plus selected local probe specular, excluding diffuse IBL and global specular.");
            } else if (debugMode == 38) {
                ImGui::TextDisabled("Direct + Mixed Specular: direct lighting plus normal mixed specular IBL, excluding diffuse IBL.");
            } else if (debugMode == 39) {
                ImGui::TextDisabled("Direct Specular Only: analytic direct BRDF specular from lights only, excluding direct diffuse, IBL, local probes, and emissive.");
            } else if (debugMode == 40) {
                ImGui::TextDisabled("Sun Vector Alignment: sharp mirror lobe from the brightest directional light vector only, excluding BRDF, roughness, IBL, shadows, and emissive.");
            } else if (debugMode == 48) {
                ImGui::TextDisabled("AO Valid Samples: fraction of the fixed spatial kernel with valid, in-radius geometry taps. White means all taps were valid.");
            } else if (debugMode == 49) {
                ImGui::TextDisabled("AO Obscurance: normalized production obscurance before intensity and power convert it to visibility.");
            } else if (debugMode == 50) {
                ImGui::TextDisabled("AO Production Depth: linear depth from the AO-owned single-sample depth/normal raster pass.");
            } else if (debugMode == 51) {
                ImGui::TextDisabled("AO Indirect Factor: filtered visibility consumed by indirect diffuse and specular lighting; direct analytic light is excluded.");
            } else if (debugMode == 41) {
                ImGui::TextDisabled("Fog Optical Depth: grayscale tau / 8; white means tau >= 8.");
            } else if (debugMode == 42) {
                ImGui::TextDisabled("Fog In-scattered Radiance: scene-linear ambient plus directional scattering.");
            } else if (debugMode == 43) {
                ImGui::TextDisabled("Fog Linear Distance: geometry distance / 100; background is white.");
            } else if (debugMode == 44) {
                ImGui::TextDisabled("Fog Density: extinction coefficient at the camera height.");
            } else if (debugMode == 45) {
                ImGui::TextDisabled("Fog Ambient Scattering: irradiance-derived scene-linear contribution.");
            } else if (debugMode == 46) {
                ImGui::TextDisabled("Fog Directional Scattering: authoritative analytic-Sun contribution.");
            } else if (debugMode == 47) {
                ImGui::TextDisabled("Fog Pixel Classification: green geometry, blue background.");
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
    case ImGuiRendererSettingsCategoryViewportOverlays:
        DrawRendererSettingsBody(context, "RendererSettingsViewportOverlayScroll", RendererSectionGrid);
        break;
    case ImGuiRendererSettingsCategorySelection:
        DrawRendererSettingsBody(context, "RendererSettingsSelectionScroll", RendererSectionOutline);
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
