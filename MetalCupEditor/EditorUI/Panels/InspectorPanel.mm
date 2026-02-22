// InspectorPanel.mm
// Defines the ImGui Inspector panel rendering and interaction logic.
// Created by Kaden Cringle.

#import "InspectorPanel.h"

#import "../../ImGui/imgui.h"
#import "PanelState.h"
#import "../Widgets/UIWidgets.h"
#import "../Widgets/UIConstants.h"
#include <string.h>
#include <stdint.h>
#include <string>
#include <vector>
#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <cmath>

extern "C" uint32_t MCEEditorEntityHasComponent(MCE_CTX,  const char *entityId, int32_t componentType);
extern "C" uint32_t MCEEditorAddComponent(MCE_CTX,  const char *entityId, int32_t componentType);
extern "C" uint32_t MCEEditorRemoveComponent(MCE_CTX,  const char *entityId, int32_t componentType);
extern "C" uint32_t MCEEditorEntityExists(MCE_CTX,  const char *entityId);
extern "C" int32_t MCEEditorSkyEntityCount(MCE_CTX);
extern "C" int32_t MCEEditorGetActiveSkyId(MCE_CTX,  char *buffer, int32_t bufferSize);
extern "C" uint32_t MCEEditorSetActiveSky(MCE_CTX,  const char *entityId);

extern "C" int32_t MCEEditorGetEntityName(MCE_CTX,  const char *entityId, char *buffer, int32_t bufferSize);
extern "C" void MCEEditorSetEntityName(MCE_CTX,  const char *entityId, const char *name);

extern "C" uint32_t MCEEditorGetTransform(MCE_CTX,  const char *entityId, float *px, float *py, float *pz,
                                          float *rx, float *ry, float *rz,
                                          float *sx, float *sy, float *sz);
extern "C" void MCEEditorSetTransform(MCE_CTX,  const char *entityId, float px, float py, float pz,
                                      float rx, float ry, float rz,
                                      float sx, float sy, float sz);
extern "C" uint32_t MCEEditorGetCamera(MCE_CTX,  const char *entityId,
                                       int32_t *projectionType,
                                       float *fovDegrees,
                                       float *orthoSize,
                                       float *nearPlane,
                                       float *farPlane,
                                       uint32_t *isPrimary,
                                       uint32_t *isEditor);
extern "C" void MCEEditorSetCamera(MCE_CTX,  const char *entityId,
                                   int32_t projectionType,
                                   float fovDegrees,
                                   float orthoSize,
                                   float nearPlane,
                                   float farPlane,
                                   uint32_t isPrimary);

extern "C" uint32_t MCEEditorGetMeshRenderer(MCE_CTX,  const char *entityId, char *meshHandle, int32_t meshHandleSize,
                                             char *materialHandle, int32_t materialHandleSize);
extern "C" void MCEEditorSetMeshRenderer(MCE_CTX,  const char *entityId, const char *meshHandle, const char *materialHandle);
extern "C" void MCEEditorAssignMaterialToEntity(MCE_CTX,  const char *entityId, const char *materialHandle);
extern "C" uint32_t MCEEditorGetMaterialComponent(MCE_CTX,  const char *entityId, char *materialHandle, int32_t materialHandleSize);
extern "C" void MCEEditorSetMaterialComponent(MCE_CTX,  const char *entityId, const char *materialHandle);

extern "C" uint32_t MCEEditorGetLight(MCE_CTX,  const char *entityId, int32_t *type, float *colorX, float *colorY, float *colorZ,
                                      float *brightness, float *range, float *innerCos, float *outerCos,
                                      float *dirX, float *dirY, float *dirZ, uint32_t *castsShadows);
extern "C" void MCEEditorSetLight(MCE_CTX,  const char *entityId, int32_t type, float colorX, float colorY, float colorZ,
                                  float brightness, float range, float innerCos, float outerCos,
                                  float dirX, float dirY, float dirZ, uint32_t castsShadows);

extern "C" uint32_t MCEEditorGetSkyLight(MCE_CTX,  const char *entityId, int32_t *mode, uint32_t *enabled,
                                         float *intensity, float *tintX, float *tintY, float *tintZ,
                                         float *turbidity, float *azimuth, float *elevation, float *sunSize,
                                         float *zenithTintX, float *zenithTintY, float *zenithTintZ,
                                         float *horizonTintX, float *horizonTintY, float *horizonTintZ,
                                         float *gradientStrength,
                                         float *hazeDensity, float *hazeFalloff, float *hazeHeight,
                                         float *ozoneStrength, float *ozoneTintX, float *ozoneTintY, float *ozoneTintZ,
                                         float *sunHaloSize, float *sunHaloIntensity, float *sunHaloSoftness,
                                         uint32_t *cloudsEnabled, float *cloudsCoverage, float *cloudsSoftness,
                                         float *cloudsScale, float *cloudsSpeed,
                                         float *cloudsWindX, float *cloudsWindY,
                                         float *cloudsHeight, float *cloudsThickness,
                                         float *cloudsBrightness, float *cloudsSunInfluence,
                                         uint32_t *autoRebuild, uint32_t *needsRebuild,
                                         char *hdriHandle, int32_t hdriHandleSize);
extern "C" void MCEEditorSetSkyLight(MCE_CTX,  const char *entityId, int32_t mode, uint32_t enabled,
                                     float intensity, float tintX, float tintY, float tintZ,
                                     float turbidity, float azimuth, float elevation, float sunSize,
                                     float zenithTintX, float zenithTintY, float zenithTintZ,
                                     float horizonTintX, float horizonTintY, float horizonTintZ,
                                     float gradientStrength,
                                     float hazeDensity, float hazeFalloff, float hazeHeight,
                                     float ozoneStrength, float ozoneTintX, float ozoneTintY, float ozoneTintZ,
                                     float sunHaloSize, float sunHaloIntensity, float sunHaloSoftness,
                                     uint32_t cloudsEnabled, float cloudsCoverage, float cloudsSoftness,
                                     float cloudsScale, float cloudsSpeed,
                                     float cloudsWindX, float cloudsWindY,
                                     float cloudsHeight, float cloudsThickness,
                                     float cloudsBrightness, float cloudsSunInfluence,
                                     uint32_t autoRebuild,
                                     const char *hdriHandle);
extern "C" void MCEEditorRequestSkyRebuild(MCE_CTX,  const char *entityId);
extern "C" uint32_t MCEEditorGetMaterialAsset(MCE_CTX, 
    const char *handle,
    char *nameBuffer, int32_t nameBufferSize,
    int32_t *version,
    float *baseColorX, float *baseColorY, float *baseColorZ,
    float *metallic, float *roughness, float *ao,
    float *emissiveX, float *emissiveY, float *emissiveZ,
    float *emissiveIntensity,
    int32_t *alphaMode, float *alphaCutoff,
    uint32_t *doubleSided, uint32_t *unlit,
    char *baseColorHandle, int32_t baseColorHandleSize,
    char *normalHandle, int32_t normalHandleSize,
    char *metalRoughnessHandle, int32_t metalRoughnessHandleSize,
    char *metallicHandle, int32_t metallicHandleSize,
    char *roughnessHandle, int32_t roughnessHandleSize,
    char *aoHandle, int32_t aoHandleSize,
    char *emissiveHandle, int32_t emissiveHandleSize);
extern "C" uint32_t MCEEditorSetMaterialAsset(MCE_CTX, 
    const char *handle,
    const char *name,
    int32_t version,
    float baseColorX, float baseColorY, float baseColorZ,
    float metallic, float roughness, float ao,
    float emissiveX, float emissiveY, float emissiveZ,
    float emissiveIntensity,
    int32_t alphaMode, float alphaCutoff,
    uint32_t doubleSided, uint32_t unlit,
    const char *baseColorHandle,
    const char *normalHandle,
    const char *metalRoughnessHandle,
    const char *metallicHandle,
    const char *roughnessHandle,
    const char *aoHandle,
    const char *emissiveHandle);
extern "C" uint32_t MCEEditorGetAssetDisplayName(MCE_CTX,  const char *handle, char *buffer, int32_t bufferSize);
extern "C" uint32_t MCEEditorGetSelectedMaterial(MCE_CTX,  char *buffer, int32_t bufferSize);
extern "C" uint32_t MCEEditorCreateMaterial(MCE_CTX,  const char *relativePath, const char *name, char *outHandle, int32_t outHandleSize);
extern "C" void MCEEditorSetSelectedMaterial(MCE_CTX,  const char *handle);
extern "C" void MCEEditorOpenMaterialEditor(MCE_CTX,  const char *handle);
extern "C" uint32_t MCEEditorConsumeOpenMaterialEditor(MCE_CTX,  char *buffer, int32_t bufferSize);
extern "C" int32_t MCEEditorGetAssetCount(MCE_CTX);
extern "C" uint32_t MCEEditorGetAssetAt(MCE_CTX,  int32_t index,
                                        char *handleBuffer, int32_t handleBufferSize,
                                        int32_t *typeOut,
                                        char *pathBuffer, int32_t pathBufferSize,
                                        char *nameBuffer, int32_t nameBufferSize);
extern "C" void *MCEContextGetUIPanelState(MCE_CTX);

enum ComponentType : int32_t {
    ComponentName = 0,
    ComponentTransform = 1,
    ComponentMeshRenderer = 2,
    ComponentLight = 3,
    ComponentSkyLight = 4,
    ComponentMaterial = 5,
    ComponentCamera = 6
};

namespace {
    constexpr float kDegToRad = 0.0174532925f;
    constexpr float kRadToDeg = 57.2957795f;

    using MCEPanelState::EnvironmentPickerState;
    using MCEPanelState::InspectorMaterialCache;
    using MCEPanelState::InspectorState;
    using MCEPanelState::MaterialEditorState;
    using MCEPanelState::MaterialPickerState;
    using MCEPanelState::MaterialPopupState;
    using MCEPanelState::MeshPickerState;
    using MCEPanelState::PendingSkyState;
    using MCEPanelState::TexturePickerState;

    InspectorState &GetInspectorState(void *context) {
        auto *state = static_cast<MCEPanelState::EditorUIPanelState *>(MCEContextGetUIPanelState(context));
        return state->inspector;
    }

    struct SkyPreset {
        const char *name;
        int32_t mode;
        uint32_t enabled;
        float intensity;
        float tintX;
        float tintY;
        float tintZ;
        float turbidity;
        float azimuth;
        float elevation;
        float sunSize;
        float zenithTintX;
        float zenithTintY;
        float zenithTintZ;
        float horizonTintX;
        float horizonTintY;
        float horizonTintZ;
        float gradientStrength;
        float hazeDensity;
        float hazeFalloff;
        float hazeHeight;
        float ozoneStrength;
        float ozoneTintX;
        float ozoneTintY;
        float ozoneTintZ;
        float sunHaloSize;
        float sunHaloIntensity;
        float sunHaloSoftness;
        uint32_t cloudsEnabled;
        float cloudsCoverage;
        float cloudsSoftness;
        float cloudsScale;
        float cloudsSpeed;
        float cloudsWindX;
        float cloudsWindY;
        float cloudsHeight;
        float cloudsThickness;
        float cloudsBrightness;
        float cloudsSunInfluence;
    };

    static const SkyPreset kSkyPresets[] = {
        {"Clear Day", 1, 1, 1.0f, 1.0f, 1.0f, 1.0f, 2.0f, 0.0f, 35.0f, 0.5f,
         0.24f, 0.45f, 0.95f, 0.95f, 0.75f, 0.55f, 1.0f, 0.25f, 2.0f, 0.0f, 0.35f, 0.55f, 0.7f, 1.0f,
         2.5f, 0.5f, 1.2f, 1, 0.3f, 0.6f, 1.0f, 0.02f, 1.0f, 0.0f, 0.3f, 0.35f, 1.0f, 1.0f},
        {"Golden Hour", 1, 1, 1.2f, 1.0f, 0.95f, 0.85f, 3.2f, 20.0f, 10.0f, 0.6f,
         0.18f, 0.32f, 0.75f, 1.0f, 0.65f, 0.35f, 1.2f, 0.55f, 2.8f, 0.1f, 0.6f, 0.6f, 0.55f, 0.9f,
         3.0f, 0.9f, 1.4f, 1, 0.4f, 0.65f, 1.2f, 0.03f, 0.7f, 0.2f, 0.25f, 0.4f, 1.2f, 1.4f},
        {"Blue Hour", 1, 1, 0.8f, 0.9f, 0.95f, 1.0f, 2.5f, 10.0f, 5.0f, 0.4f,
         0.15f, 0.28f, 0.8f, 0.5f, 0.6f, 1.0f, 1.1f, 0.3f, 2.6f, 0.0f, 0.8f, 0.45f, 0.65f, 1.0f,
         2.0f, 0.4f, 1.4f, 0, 0.0f, 0.6f, 1.0f, 0.0f, 1.0f, 0.0f, 0.3f, 0.3f, 0.9f, 0.8f},
        {"Overcast", 1, 1, 0.9f, 0.9f, 0.92f, 0.95f, 6.0f, 0.0f, 45.0f, 0.7f,
         0.2f, 0.35f, 0.8f, 0.8f, 0.85f, 0.9f, 0.6f, 0.7f, 3.5f, 0.0f, 0.25f, 0.6f, 0.7f, 1.0f,
         2.0f, 0.2f, 1.6f, 1, 0.75f, 0.8f, 1.8f, 0.01f, 1.0f, 0.0f, 0.2f, 0.6f, 1.1f, 0.6f},
        {"Stormy", 1, 1, 0.75f, 0.85f, 0.9f, 1.0f, 8.0f, 15.0f, 20.0f, 0.6f,
         0.12f, 0.2f, 0.6f, 0.5f, 0.6f, 0.7f, 0.5f, 0.9f, 4.0f, 0.0f, 0.1f, 0.45f, 0.6f, 0.9f,
         1.8f, 0.3f, 2.0f, 1, 0.85f, 0.75f, 2.2f, 0.02f, 0.3f, 0.2f, 0.15f, 0.7f, 0.8f, 0.3f},
        {"Desert Haze", 1, 1, 1.1f, 1.0f, 0.98f, 0.92f, 4.5f, 0.0f, 45.0f, 0.55f,
         0.2f, 0.35f, 0.85f, 1.0f, 0.75f, 0.45f, 1.0f, 0.9f, 3.0f, 0.15f, 0.4f, 0.6f, 0.6f, 0.85f,
         2.8f, 0.7f, 1.1f, 0, 0.0f, 0.6f, 1.0f, 0.0f, 1.0f, 0.0f, 0.2f, 0.2f, 1.0f, 0.7f},
        {"Winter Cold", 1, 1, 0.95f, 0.95f, 1.0f, 1.05f, 2.8f, 0.0f, 35.0f, 0.45f,
         0.18f, 0.3f, 0.9f, 0.7f, 0.8f, 1.1f, 1.2f, 0.25f, 2.4f, 0.0f, 0.7f, 0.45f, 0.7f, 1.05f,
         2.2f, 0.45f, 1.3f, 1, 0.4f, 0.65f, 1.1f, 0.015f, 0.9f, 0.1f, 0.3f, 0.3f, 1.0f, 0.9f},
        {"Stylized", 1, 1, 1.1f, 0.9f, 0.9f, 1.1f, 1.5f, 220.0f, 35.0f, 0.8f,
         0.15f, 0.55f, 1.1f, 1.2f, 0.4f, 0.9f, 1.6f, 0.2f, 1.6f, 0.0f, 0.3f, 0.4f, 0.8f, 1.2f,
         3.5f, 1.2f, 0.9f, 1, 0.2f, 0.5f, 1.6f, 0.03f, -0.2f, 1.0f, 0.35f, 0.25f, 1.4f, 1.2f},
        {"Alien", 1, 1, 0.9f, 0.7f, 0.95f, 0.6f, 2.2f, 140.0f, 25.0f, 1.2f,
         0.1f, 0.7f, 0.4f, 0.9f, 0.2f, 0.8f, 1.4f, 0.3f, 2.0f, 0.0f, 0.6f, 0.4f, 0.8f, 0.6f,
         4.0f, 1.0f, 1.2f, 1, 0.5f, 0.6f, 1.8f, 0.02f, 0.7f, -0.3f, 0.25f, 0.4f, 1.2f, 1.5f},
        {"Night Sky", 1, 1, 0.35f, 0.7f, 0.75f, 1.0f, 1.2f, 0.0f, 5.0f, 0.3f,
         0.05f, 0.08f, 0.2f, 0.2f, 0.2f, 0.5f, 0.9f, 0.1f, 2.5f, 0.0f, 0.9f, 0.25f, 0.4f, 0.9f,
         1.0f, 0.25f, 1.6f, 0, 0.0f, 0.6f, 1.0f, 0.0f, 1.0f, 0.0f, 0.25f, 0.2f, 0.6f, 0.5f}
    };

    static const char *kSkyPresetNames[] = {
        "Clear Day",
        "Golden Hour",
        "Blue Hour",
        "Overcast",
        "Stormy",
        "Desert Haze",
        "Winter Cold",
        "Stylized",
        "Alien",
        "Night Sky"
    };

    static float RandomRange(float minValue, float maxValue) {
        const float t = static_cast<float>(rand()) / static_cast<float>(RAND_MAX);
        return minValue + (maxValue - minValue) * t;
    }

    static float ClampFloat(float value, float minValue, float maxValue) {
        return std::max(minValue, std::min(value, maxValue));
    }

    bool LoadMaterialState(void *context, const char *materialHandle, MaterialEditorState &state) {
        if (!materialHandle || materialHandle[0] == 0) { return false; }
        uint32_t doubleSided = 0;
        uint32_t unlit = 0;
        const bool loaded = MCEEditorGetMaterialAsset(
            context,
            materialHandle,
            state.name, sizeof(state.name),
            &state.version,
            &state.baseColor[0], &state.baseColor[1], &state.baseColor[2],
            &state.metallic, &state.roughness, &state.ao,
            &state.emissive[0], &state.emissive[1], &state.emissive[2],
            &state.emissiveIntensity,
            &state.alphaMode, &state.alphaCutoff,
            &doubleSided, &unlit,
            state.baseColorHandle, sizeof(state.baseColorHandle),
            state.normalHandle, sizeof(state.normalHandle),
            state.metalRoughnessHandle, sizeof(state.metalRoughnessHandle),
            state.metallicHandle, sizeof(state.metallicHandle),
            state.roughnessHandle, sizeof(state.roughnessHandle),
            state.aoHandle, sizeof(state.aoHandle),
            state.emissiveHandle, sizeof(state.emissiveHandle)) != 0;
        if (!loaded) {
            return false;
        }
        state.doubleSided = (doubleSided != 0);
        state.unlit = (unlit != 0);
        return true;
    }

    void GetAssetName(void *context, const char *handle, char *buffer, size_t bufferSize) {
        if (!handle || handle[0] == 0) {
            strncpy(buffer, "None", bufferSize - 1);
            buffer[bufferSize - 1] = 0;
            return;
        }
        if (strcmp(handle, "00000000-0000-0000-0000-000000000002") == 0) {
            strncpy(buffer, "Cube", bufferSize - 1);
            buffer[bufferSize - 1] = 0;
            return;
        }
        if (strcmp(handle, "00000000-0000-0000-0000-000000000006") == 0) {
            strncpy(buffer, "Plane", bufferSize - 1);
            buffer[bufferSize - 1] = 0;
            return;
        }
        if (strcmp(handle, "00000000-0000-0000-0000-000000000003") == 0) {
            strncpy(buffer, "Cubemap", bufferSize - 1);
            buffer[bufferSize - 1] = 0;
            return;
        }
        if (strcmp(handle, "00000000-0000-0000-0000-000000000004") == 0) {
            strncpy(buffer, "Skybox", bufferSize - 1);
            buffer[bufferSize - 1] = 0;
            return;
        }
        if (strcmp(handle, "00000000-0000-0000-0000-000000000005") == 0) {
            strncpy(buffer, "Fullscreen Quad", bufferSize - 1);
            buffer[bufferSize - 1] = 0;
            return;
        }
        if (MCEEditorGetAssetDisplayName(context, handle, buffer, static_cast<int32_t>(bufferSize)) == 0) {
            strncpy(buffer, handle, bufferSize - 1);
            buffer[bufferSize - 1] = 0;
        }
    }

    struct AssetOption {
        std::string handle;
        std::string name;
    };

    TexturePickerState &GetTexturePickerState(InspectorState &state) {
        return state.texturePicker;
    }

    EnvironmentPickerState &GetEnvironmentPickerState(InspectorState &state) {
        return state.environmentPicker;
    }

    MeshPickerState &GetMeshPickerState(InspectorState &state) {
        return state.meshPicker;
    }

    MaterialPickerState &GetMaterialPickerState(InspectorState &state) {
        return state.materialPicker;
    }

    void LoadTextureOptions(void *context, std::vector<AssetOption> &options) {
        options.clear();
        const int32_t count = MCEEditorGetAssetCount(context);
        options.reserve(count);
        for (int32_t i = 0; i < count; ++i) {
            char handleBuffer[64] = {0};
            int32_t type = 0;
            char pathBuffer[512] = {0};
            char nameBuffer[128] = {0};
            if (MCEEditorGetAssetAt(context, i,
                                    handleBuffer, sizeof(handleBuffer),
                                    &type,
                                    pathBuffer, sizeof(pathBuffer),
                                    nameBuffer, sizeof(nameBuffer)) == 0) {
                continue;
            }
            if (type != 0) { continue; }
            if (handleBuffer[0] == 0) { continue; }
            AssetOption option;
            option.handle = handleBuffer;
            option.name = nameBuffer[0] != 0 ? nameBuffer : pathBuffer;
            options.push_back(option);
        }
        std::sort(options.begin(), options.end(), [](const AssetOption &a, const AssetOption &b) {
            return a.name < b.name;
        });
    }

    void LoadEnvironmentOptions(void *context, std::vector<AssetOption> &options) {
        options.clear();
        const int32_t count = MCEEditorGetAssetCount(context);
        options.reserve(count);
        for (int32_t i = 0; i < count; ++i) {
            char handleBuffer[64] = {0};
            int32_t type = 0;
            char pathBuffer[512] = {0};
            char nameBuffer[128] = {0};
            if (MCEEditorGetAssetAt(context, i,
                                    handleBuffer, sizeof(handleBuffer),
                                    &type,
                                    pathBuffer, sizeof(pathBuffer),
                                    nameBuffer, sizeof(nameBuffer)) == 0) {
                continue;
            }
            if (type != 3) { continue; }
            if (handleBuffer[0] == 0) { continue; }
            AssetOption option;
            option.handle = handleBuffer;
            option.name = nameBuffer[0] != 0 ? nameBuffer : pathBuffer;
            options.push_back(option);
        }
        std::sort(options.begin(), options.end(), [](const AssetOption &a, const AssetOption &b) {
            return a.name < b.name;
        });
    }

    void LoadMeshOptions(void *context, std::vector<AssetOption> &options) {
        options.clear();
        const int32_t count = MCEEditorGetAssetCount(context);
        options.reserve(count);
        for (int32_t i = 0; i < count; ++i) {
            char handleBuffer[64] = {0};
            int32_t type = 0;
            char pathBuffer[512] = {0};
            char nameBuffer[128] = {0};
            if (MCEEditorGetAssetAt(context, i,
                                    handleBuffer, sizeof(handleBuffer),
                                    &type,
                                    pathBuffer, sizeof(pathBuffer),
                                    nameBuffer, sizeof(nameBuffer)) == 0) {
                continue;
            }
            if (type != 1) { continue; }
            if (handleBuffer[0] == 0) { continue; }
            AssetOption option;
            option.handle = handleBuffer;
            option.name = nameBuffer[0] != 0 ? nameBuffer : pathBuffer;
            options.push_back(option);
        }
        options.push_back({"00000000-0000-0000-0000-000000000002", "Cube"});
        options.push_back({"00000000-0000-0000-0000-000000000006", "Plane"});
        options.push_back({"00000000-0000-0000-0000-000000000003", "Cubemap"});
        options.push_back({"00000000-0000-0000-0000-000000000004", "Skybox"});
        options.push_back({"00000000-0000-0000-0000-000000000005", "Fullscreen Quad"});
        std::sort(options.begin(), options.end(), [](const AssetOption &a, const AssetOption &b) {
            return a.name < b.name;
        });
    }

    void LoadMaterialOptions(void *context, std::vector<AssetOption> &options) {
        options.clear();
        const int32_t count = MCEEditorGetAssetCount(context);
        options.reserve(count);
        for (int32_t i = 0; i < count; ++i) {
            char handleBuffer[64] = {0};
            int32_t type = 0;
            char pathBuffer[512] = {0};
            char nameBuffer[128] = {0};
            if (MCEEditorGetAssetAt(context, i,
                                    handleBuffer, sizeof(handleBuffer),
                                    &type,
                                    pathBuffer, sizeof(pathBuffer),
                                    nameBuffer, sizeof(nameBuffer)) == 0) {
                continue;
            }
            if (type != 2) { continue; }
            if (handleBuffer[0] == 0) { continue; }
            AssetOption option;
            option.handle = handleBuffer;
            option.name = nameBuffer[0] != 0 ? nameBuffer : pathBuffer;
            options.push_back(option);
        }
        std::sort(options.begin(), options.end(), [](const AssetOption &a, const AssetOption &b) {
            return a.name < b.name;
        });
    }

    void OpenTexturePicker(InspectorState &state, const char *label, char *target, const char *materialHandle) {
        auto &picker = GetTexturePickerState(state);
        picker.open = true;
        picker.requestOpen = true;
        picker.target = target;
        snprintf(picker.title, sizeof(picker.title), "Select Texture: %s", label);
        picker.filter[0] = 0;
        if (materialHandle) {
            strncpy(picker.materialHandle, materialHandle, sizeof(picker.materialHandle) - 1);
            picker.materialHandle[sizeof(picker.materialHandle) - 1] = 0;
        } else {
            picker.materialHandle[0] = 0;
        }
    }

    void OpenEnvironmentPicker(InspectorState &state, const char *label, char *target, const char *entityId) {
        auto &picker = GetEnvironmentPickerState(state);
        picker.open = true;
        picker.requestOpen = true;
        picker.target = target;
        snprintf(picker.title, sizeof(picker.title), "Select Environment: %s", label);
        picker.filter[0] = 0;
        if (entityId) {
            strncpy(picker.entityId, entityId, sizeof(picker.entityId) - 1);
            picker.entityId[sizeof(picker.entityId) - 1] = 0;
        } else {
            picker.entityId[0] = 0;
        }
    }

    void OpenMeshPicker(InspectorState &state, const char *label, const char *entityId, const char *materialHandle) {
        auto &picker = GetMeshPickerState(state);
        picker.open = true;
        picker.requestOpen = true;
        snprintf(picker.title, sizeof(picker.title), "Select Mesh: %s", label);
        picker.filter[0] = 0;
        if (entityId) {
            strncpy(picker.entityId, entityId, sizeof(picker.entityId) - 1);
            picker.entityId[sizeof(picker.entityId) - 1] = 0;
        } else {
            picker.entityId[0] = 0;
        }
        if (materialHandle) {
            strncpy(picker.materialHandle, materialHandle, sizeof(picker.materialHandle) - 1);
            picker.materialHandle[sizeof(picker.materialHandle) - 1] = 0;
        } else {
            picker.materialHandle[0] = 0;
        }
    }

    void OpenMaterialPicker(InspectorState &state, const char *label, const char *entityId, const char *meshHandle, bool usesMeshRenderer) {
        auto &picker = GetMaterialPickerState(state);
        picker.open = true;
        picker.requestOpen = true;
        snprintf(picker.title, sizeof(picker.title), "Select Material: %s", label);
        picker.filter[0] = 0;
        picker.usesMeshRenderer = usesMeshRenderer;
        if (entityId) {
            strncpy(picker.entityId, entityId, sizeof(picker.entityId) - 1);
            picker.entityId[sizeof(picker.entityId) - 1] = 0;
        } else {
            picker.entityId[0] = 0;
        }
        if (meshHandle) {
            strncpy(picker.meshHandle, meshHandle, sizeof(picker.meshHandle) - 1);
            picker.meshHandle[sizeof(picker.meshHandle) - 1] = 0;
        } else {
            picker.meshHandle[0] = 0;
        }
    }

    bool DrawTextureSlotRow(void *context,
                            InspectorState &state,
                            const char *label,
                            char *handleBuffer,
                            size_t handleBufferSize,
                            const char *payloadType,
                            const char *materialHandle) {
        bool changed = false;
        ImGui::TableNextRow();
        ImGui::TableSetColumnIndex(0);
        ImGui::TextUnformatted(label);
        ImGui::TableSetColumnIndex(1);

        ImGui::PushID(label);
        char displayName[128] = {0};
        GetAssetName(context, handleBuffer, displayName, sizeof(displayName));
        const float wrapPos = ImGui::GetCursorPosX() + ImGui::GetContentRegionAvail().x - 6.0f;
        ImGui::PushTextWrapPos(wrapPos);
        ImGui::TextUnformatted(displayName);
        ImGui::PopTextWrapPos();
        if (ImGui::BeginDragDropTarget()) {
            if (const ImGuiPayload* payload = ImGui::AcceptDragDropPayload(payloadType)) {
                const char *payloadText = static_cast<const char *>(payload->Data);
                strncpy(handleBuffer, payloadText, handleBufferSize - 1);
                handleBuffer[handleBufferSize - 1] = 0;
                changed = true;
            }
            ImGui::EndDragDropTarget();
        }

        ImGui::TableSetColumnIndex(2);
        if (ImGui::Button((std::string("...##") + label).c_str())) {
            OpenTexturePicker(state, label, handleBuffer, materialHandle);
        }
        ImGui::TableSetColumnIndex(3);
        if (ImGui::Button((std::string("X##") + label).c_str())) {
            handleBuffer[0] = 0;
            changed = true;
        }
        ImGui::PopID();
        return changed;
    }

    bool DrawEnvironmentHandleRow(void *context,
                                  InspectorState &state,
                                  const char *label,
                                  char *handleBuffer,
                                  size_t handleBufferSize,
                                  const char *payloadType,
                                  const char *entityId) {
        bool changed = false;
        EditorUI::PropertyLabel(label);
        ImGui::PushID(label);
        char displayName[128] = {0};
        GetAssetName(context, handleBuffer, displayName, sizeof(displayName));
        const float wrapPos = ImGui::GetCursorPosX() + ImGui::GetContentRegionAvail().x - 120.0f;
        ImGui::PushTextWrapPos(wrapPos);
        ImGui::TextUnformatted(displayName);
        ImGui::PopTextWrapPos();
        if (ImGui::BeginDragDropTarget()) {
            if (const ImGuiPayload* payload = ImGui::AcceptDragDropPayload(payloadType)) {
                const char *payloadText = static_cast<const char *>(payload->Data);
                strncpy(handleBuffer, payloadText, handleBufferSize - 1);
                handleBuffer[handleBufferSize - 1] = 0;
                changed = true;
            }
            ImGui::EndDragDropTarget();
        }
        ImGui::SameLine();
        if (ImGui::Button("Select...")) {
            OpenEnvironmentPicker(state, label, handleBuffer, entityId);
        }
        ImGui::SameLine();
        if (ImGui::Button("Clear")) {
            handleBuffer[0] = 0;
            changed = true;
        }
        ImGui::PopID();
        return changed;
    }

    bool DrawMeshHandleRow(void *context,
                           InspectorState &state,
                           const char *label,
                           char *handleBuffer,
                           size_t handleBufferSize,
                           const char *payloadType,
                           const char *entityId,
                           const char *materialHandle) {
        bool changed = false;
        EditorUI::PropertyLabel(label);
        ImGui::PushID(label);
        char displayName[128] = {0};
        GetAssetName(context, handleBuffer, displayName, sizeof(displayName));
        const float wrapPos = ImGui::GetCursorPosX() + ImGui::GetContentRegionAvail().x - 120.0f;
        ImGui::PushTextWrapPos(wrapPos);
        ImGui::TextUnformatted(displayName);
        ImGui::PopTextWrapPos();
        if (ImGui::BeginDragDropTarget()) {
            if (const ImGuiPayload* payload = ImGui::AcceptDragDropPayload(payloadType)) {
                const char *payloadText = static_cast<const char *>(payload->Data);
                strncpy(handleBuffer, payloadText, handleBufferSize - 1);
                handleBuffer[handleBufferSize - 1] = 0;
                changed = true;
            }
            ImGui::EndDragDropTarget();
        }
        ImGui::SameLine();
        if (ImGui::Button("Select...")) {
            OpenMeshPicker(state, label, entityId, materialHandle);
        }
        ImGui::SameLine();
        if (ImGui::Button("Clear")) {
            handleBuffer[0] = 0;
            changed = true;
        }
        ImGui::PopID();
        return changed;
    }

    bool DrawMaterialHandleRow(void *context,
                               InspectorState &state,
                               const char *label,
                               char *handleBuffer,
                               size_t handleBufferSize,
                               const char *payloadType,
                               const char *entityId,
                               const char *meshHandle,
                               bool usesMeshRenderer) {
        bool changed = false;
        EditorUI::PropertyLabel(label);
        ImGui::PushID(label);
        char displayName[128] = {0};
        GetAssetName(context, handleBuffer, displayName, sizeof(displayName));
        const float wrapPos = ImGui::GetCursorPosX() + ImGui::GetContentRegionAvail().x - 120.0f;
        ImGui::PushTextWrapPos(wrapPos);
        ImGui::TextUnformatted(displayName);
        ImGui::PopTextWrapPos();
        if (ImGui::BeginDragDropTarget()) {
            if (const ImGuiPayload* payload = ImGui::AcceptDragDropPayload(payloadType)) {
                const char *payloadText = static_cast<const char *>(payload->Data);
                strncpy(handleBuffer, payloadText, handleBufferSize - 1);
                handleBuffer[handleBufferSize - 1] = 0;
                changed = true;
            }
            ImGui::EndDragDropTarget();
        }
        ImGui::SameLine();
        if (ImGui::Button("Select...")) {
            OpenMaterialPicker(state, label, entityId, meshHandle, usesMeshRenderer);
        }
        ImGui::SameLine();
        if (handleBuffer[0] != 0) {
            if (ImGui::Button("Edit")) {
                MCEEditorOpenMaterialEditor(context, handleBuffer);
            }
            ImGui::SameLine();
        }
        if (ImGui::Button("Clear")) {
            handleBuffer[0] = 0;
            changed = true;
        }
        ImGui::PopID();
        return changed;
    }

    void EnforceMetalRoughnessRule(MaterialEditorState &state) {
        const bool hasMetalRoughness = state.metalRoughnessHandle[0] != 0;
        const bool hasMetallic = state.metallicHandle[0] != 0;
        const bool hasRoughness = state.roughnessHandle[0] != 0;
        if (hasMetalRoughness) {
            state.metallicHandle[0] = 0;
            state.roughnessHandle[0] = 0;
        } else if (hasMetallic || hasRoughness) {
            state.metalRoughnessHandle[0] = 0;
        }
    }

    MaterialPopupState &GetMaterialPopupState(InspectorState &state) {
        return state.materialPopup;
    }

    void OpenMaterialPopup(void *context, InspectorState &state, const char *materialHandle) {
        if (!materialHandle || materialHandle[0] == 0) { return; }
        auto &popup = GetMaterialPopupState(state);
        memset(&popup.state, 0, sizeof(popup.state));
        if (!LoadMaterialState(context, materialHandle, popup.state)) { return; }
        strncpy(popup.handle, materialHandle, sizeof(popup.handle) - 1);
        popup.handle[sizeof(popup.handle) - 1] = 0;
        popup.dirty = false;
        popup.open = true;
        popup.title = std::string("Material: ") + (popup.state.name[0] != 0 ? popup.state.name : "Material");
        ImGui::OpenPopup(popup.title.c_str());
    }

    bool DrawMaterialTextureInspector(void *context, InspectorState &panelState, MaterialEditorState &materialState, const char *materialHandle) {
        bool dirty = false;
        ImGui::TextUnformatted("Textures");
        ImGui::Separator();

        if (ImGui::BeginTable("InspectorMaterialTextures", 4, ImGuiTableFlags_BordersInnerH | ImGuiTableFlags_RowBg)) {
            ImGui::TableSetupColumn("Slot", ImGuiTableColumnFlags_WidthFixed, 120.0f);
            ImGui::TableSetupColumn("Texture", ImGuiTableColumnFlags_WidthStretch);
            ImGui::TableSetupColumn("Assign", ImGuiTableColumnFlags_WidthFixed, 70.0f);
            ImGui::TableSetupColumn("Clear", ImGuiTableColumnFlags_WidthFixed, 60.0f);
            ImGui::TableHeadersRow();

            dirty |= DrawTextureSlotRow(context, panelState, "Base Color", materialState.baseColorHandle, sizeof(materialState.baseColorHandle), "MCE_ASSET_TEXTURE", materialHandle);
            dirty |= DrawTextureSlotRow(context, panelState, "Normal", materialState.normalHandle, sizeof(materialState.normalHandle), "MCE_ASSET_TEXTURE", materialHandle);
            dirty |= DrawTextureSlotRow(context, panelState, "Metal/Rough", materialState.metalRoughnessHandle, sizeof(materialState.metalRoughnessHandle), "MCE_ASSET_TEXTURE", materialHandle);
            dirty |= DrawTextureSlotRow(context, panelState, "Metallic", materialState.metallicHandle, sizeof(materialState.metallicHandle), "MCE_ASSET_TEXTURE", materialHandle);
            dirty |= DrawTextureSlotRow(context, panelState, "Roughness", materialState.roughnessHandle, sizeof(materialState.roughnessHandle), "MCE_ASSET_TEXTURE", materialHandle);
            dirty |= DrawTextureSlotRow(context, panelState, "AO", materialState.aoHandle, sizeof(materialState.aoHandle), "MCE_ASSET_TEXTURE", materialHandle);
            dirty |= DrawTextureSlotRow(context, panelState, "Emissive", materialState.emissiveHandle, sizeof(materialState.emissiveHandle), "MCE_ASSET_TEXTURE", materialHandle);

            ImGui::EndTable();
        }

        const bool hasMetalRough = materialState.metalRoughnessHandle[0] != 0;
        const bool hasMetallic = materialState.metallicHandle[0] != 0;
        const bool hasRoughness = materialState.roughnessHandle[0] != 0;
        if (hasMetalRough && (hasMetallic || hasRoughness)) {
            ImGui::TextColored(ImVec4(0.95f, 0.7f, 0.2f, 1.0f), "Warning: Metal/Roughness conflicts with Metallic/Roughness maps.");
        }
        return dirty;
    }

    InspectorMaterialCache &GetInspectorMaterialCache(InspectorState &state) {
        return state.materialCache;
    }

    MaterialEditorState *GetInspectorMaterialState(void *context, InspectorState &state, const char *materialHandle) {
        if (!materialHandle || materialHandle[0] == 0) { return nullptr; }
        InspectorMaterialCache &cache = GetInspectorMaterialCache(state);
        if (!cache.valid || strcmp(cache.handle, materialHandle) != 0) {
            memset(&cache.state, 0, sizeof(cache.state));
            if (!LoadMaterialState(context, materialHandle, cache.state)) {
                cache.valid = false;
                cache.handle[0] = 0;
                return nullptr;
            }
            strncpy(cache.handle, materialHandle, sizeof(cache.handle) - 1);
            cache.handle[sizeof(cache.handle) - 1] = 0;
            cache.valid = true;
        }
        return &cache.state;
    }

    bool DrawMaterialEditorContents(MaterialEditorState &state) {
        bool dirty = false;
        if (EditorUI::BeginPropertyTable("MaterialSurface")) {
            EditorUI::PropertyLabel("Version");
            ImGui::Text("%d", state.version);
            EditorUI::PropertyLabel("Material Name");
            dirty |= ImGui::InputText("##MaterialName", state.name, sizeof(state.name));
            const float baseDefault[3] = {1.0f, 1.0f, 1.0f};
            dirty |= EditorUI::PropertyColor3("Base Color", state.baseColor, baseDefault, true);
            dirty |= EditorUI::PropertyFloat("Metallic", &state.metallic, 0.01f, 0.0f, 1.0f, "%.3f", true, true, 1.0f);
            dirty |= EditorUI::PropertyFloat("Roughness", &state.roughness, 0.01f, EditorUIConstants::kRoughnessMin, EditorUIConstants::kRoughnessMax, "%.3f", true, true, 1.0f);
            dirty |= EditorUI::PropertyFloat("AO", &state.ao, 0.01f, 0.0f, 1.0f, "%.3f", true, true, 1.0f);
            EditorUI::EndPropertyTable();
        }

        if (EditorUI::BeginPropertyTable("MaterialEmissive")) {
            const float emissiveDefault[3] = {0.0f, 0.0f, 0.0f};
            dirty |= EditorUI::PropertyColor3("Emissive Color", state.emissive, emissiveDefault, true);
            dirty |= EditorUI::PropertyFloat("Emissive Intensity", &state.emissiveIntensity, 0.01f, 0.0f, 50.0f, "%.3f", true, true, 1.0f);
            const char* alphaModes[] = {"Opaque", "Masked", "Blended"};
            dirty |= EditorUI::PropertyCombo("Alpha Mode", &state.alphaMode, alphaModes, IM_ARRAYSIZE(alphaModes));
            dirty |= EditorUI::PropertyFloat("Alpha Cutoff", &state.alphaCutoff, 0.01f, 0.0f, 1.0f, "%.3f", true, true, 0.5f);
            dirty |= EditorUI::PropertyBool("Double Sided", &state.doubleSided);
            dirty |= EditorUI::PropertyBool("Unlit", &state.unlit);
            EditorUI::EndPropertyTable();
        }

        return dirty;
    }

    PendingSkyState &GetPendingSkyState(InspectorState &state) {
        return state.pendingSky;
    }
}

void ImGuiInspectorPanelDraw(void *context, bool *isOpen, const char *selectedEntityId) {
    if (!isOpen || !*isOpen) { return; }
    InspectorState &state = GetInspectorState(context);
    if (!EditorUI::BeginPanel("Inspector", isOpen)) {
        EditorUI::EndPanel();
        return;
    }
    ImGui::BeginChild("InspectorScroll", ImVec2(0, 0), false, ImGuiWindowFlags_AlwaysVerticalScrollbar);

    const bool hasEntityId = selectedEntityId && selectedEntityId[0] != 0;
    const bool hasValidEntity = hasEntityId && (MCEEditorEntityExists(context, selectedEntityId) != 0);
    char selectedMaterial[64] = {0};
    const bool hasSelectedMaterial = MCEEditorGetSelectedMaterial(context, selectedMaterial, sizeof(selectedMaterial)) != 0;

    if (!hasValidEntity) {
        if (!hasSelectedMaterial) {
            ImGui::TextUnformatted(hasEntityId ? "Selection no longer exists." : "No entity selected.");
            ImGui::EndChild();
            EditorUI::EndPanel();
            return;
        }
    }

    ImGui::PushStyleVar(ImGuiStyleVar_FramePadding, ImVec2(6, 4));

    char pendingMaterialHandle[64] = {0};
    if (MCEEditorConsumeOpenMaterialEditor(context, pendingMaterialHandle, sizeof(pendingMaterialHandle)) != 0) {
        OpenMaterialPopup(context, state, pendingMaterialHandle);
    }

    if (hasValidEntity) {
        char nameBuffer[256] = {0};
        if (MCEEditorGetEntityName(context, selectedEntityId, nameBuffer, sizeof(nameBuffer)) <= 0) {
            strncpy(nameBuffer, "Entity", sizeof(nameBuffer) - 1);
        }
        if (ImGui::InputText("Name", nameBuffer, sizeof(nameBuffer))) {
            MCEEditorSetEntityName(context, selectedEntityId, nameBuffer);
        }
        ImGui::Spacing();
    }

    if (hasValidEntity && MCEEditorEntityHasComponent(context, selectedEntityId, ComponentTransform) != 0) {
        bool transformOpen = EditorUI::BeginSection(context, "Transform", "Inspector.Transform", true);
        if (ImGui::BeginPopupContextItem("TransformContext")) {
            if (ImGui::MenuItem("Reset")) {
                MCEEditorSetTransform(context, selectedEntityId, 0, 0, 0, 0, 0, 0, 1, 1, 1);
            }
            if (ImGui::MenuItem("Remove")) {
                MCEEditorRemoveComponent(context, selectedEntityId, ComponentTransform);
            }
            ImGui::EndPopup();
        }
        if (transformOpen) {
            float px = 0, py = 0, pz = 0;
            float rx = 0, ry = 0, rz = 0;
            float sx = 1, sy = 1, sz = 1;
            if (MCEEditorGetTransform(context, selectedEntityId, &px, &py, &pz, &rx, &ry, &rz, &sx, &sy, &sz) != 0) {
                float position[3] = {px, py, pz};
                float rotation[3] = {rx * kRadToDeg, ry * kRadToDeg, rz * kRadToDeg};
                float scale[3] = {sx, sy, sz};
                bool dirty = false;
                if (EditorUI::BeginPropertyTable("TransformProps")) {
                    dirty |= EditorUI::PropertyVec3("Position",
                                                   position,
                                                   0.0f,
                                                   EditorUIConstants::kPositionStep,
                                                   0.0f,
                                                   0.0f,
                                                   "%.3f",
                                                   false,
                                                   true);
                    dirty |= EditorUI::PropertyVec3("Rotation (deg)",
                                                   rotation,
                                                   0.0f,
                                                   EditorUIConstants::kRotationStepDeg,
                                                   EditorUIConstants::kRotationMinDeg,
                                                   EditorUIConstants::kRotationMaxDeg,
                                                   "%.2f",
                                                   true,
                                                   true);
                    dirty |= EditorUI::PropertyVec3("Scale",
                                                   scale,
                                                   1.0f,
                                                   EditorUIConstants::kScaleStep,
                                                   0.0f,
                                                   0.0f,
                                                   "%.3f",
                                                   false,
                                                   true);
                    EditorUI::EndPropertyTable();
                }
                if (dirty) {
                    float rotationRad[3] = {rotation[0] * kDegToRad, rotation[1] * kDegToRad, rotation[2] * kDegToRad};
                    MCEEditorSetTransform(context, selectedEntityId,
                                          position[0], position[1], position[2],
                                          rotationRad[0], rotationRad[1], rotationRad[2],
                                          scale[0], scale[1], scale[2]);
                }
            }
        }
    }

    const bool hasCamera = hasValidEntity && MCEEditorEntityHasComponent(context, selectedEntityId, ComponentCamera) != 0;
    if (hasCamera) {
        bool cameraOpen = EditorUI::BeginSectionWithContext(context, 
            "Camera",
            "Inspector.Camera",
            "CameraContext",
            [&]() {
                if (ImGui::MenuItem("Remove")) {
                    MCEEditorRemoveComponent(context, selectedEntityId, ComponentCamera);
                }
            },
            true);
        if (cameraOpen) {
            int32_t projectionType = 0;
            float fovDegrees = 45.0f;
            float orthoSize = 10.0f;
            float nearPlane = 0.1f;
            float farPlane = 1000.0f;
            uint32_t isPrimary = 0;
            uint32_t isEditor = 0;
            if (MCEEditorGetCamera(context, selectedEntityId,
                                   &projectionType,
                                   &fovDegrees,
                                   &orthoSize,
                                   &nearPlane,
                                   &farPlane,
                                   &isPrimary,
                                   &isEditor) != 0) {
                const char *projectionItems[] = {"Perspective", "Orthographic"};
                int projectionIndex = projectionType;
                bool dirty = false;
                bool primaryDirty = false;
                if (EditorUI::BeginPropertyTable("CameraProps")) {
                    dirty |= EditorUI::PropertyCombo("Projection", &projectionIndex, projectionItems, 2);
                    if (projectionIndex == 0) {
                        dirty |= EditorUI::PropertyFloat("FOV (deg)", &fovDegrees, 0.1f, 1.0f, 179.0f, "%.1f", true);
                    } else {
                        dirty |= EditorUI::PropertyFloat("Ortho Size", &orthoSize, 0.05f, 0.01f, 10000.0f, "%.2f", true);
                    }
                    dirty |= EditorUI::PropertyFloat("Near", &nearPlane, 0.01f, 0.01f, 10000.0f, "%.3f", true);
                    dirty |= EditorUI::PropertyFloat("Far", &farPlane, 1.0f, 0.1f, 100000.0f, "%.1f", true);
                    bool primary = isPrimary != 0;
                    if (isEditor != 0) {
                        ImGui::BeginDisabled();
                    }
                    primaryDirty = EditorUI::PropertyBool("Primary", &primary);
                    if (isEditor != 0) {
                        ImGui::EndDisabled();
                    }
                    EditorUI::EndPropertyTable();

                    if (dirty || primaryDirty) {
                        const uint32_t primaryValue = (primary ? 1u : 0u);
                        MCEEditorSetCamera(context, selectedEntityId,
                                           projectionIndex,
                                           fovDegrees,
                                           orthoSize,
                                           nearPlane,
                                           farPlane,
                                           primaryValue);
                    }
                }
                if (isEditor != 0) {
                    ImGui::TextDisabled("Editor Camera");
                }
                if (isEditor != 0) {
                    ImGui::BeginDisabled();
                }
                if (ImGui::Button("Remove Camera")) {
                    MCEEditorRemoveComponent(context, selectedEntityId, ComponentCamera);
                }
                if (isEditor != 0) {
                    ImGui::EndDisabled();
                }
            }
        }
    }

    const bool hasMeshRenderer = hasValidEntity && MCEEditorEntityHasComponent(context, selectedEntityId, ComponentMeshRenderer) != 0;
    if (hasMeshRenderer) {
        bool meshOpen = EditorUI::BeginSectionWithContext(context, 
            "Mesh Renderer",
            "Inspector.MeshRenderer",
            "MeshRendererContext",
            [&]() {
                if (ImGui::MenuItem("Reset")) {
                    const char *empty = "";
                    MCEEditorSetMeshRenderer(context, selectedEntityId, empty, empty);
                    MCEEditorSetMaterialComponent(context, selectedEntityId, empty);
                }
                if (ImGui::MenuItem("Remove")) {
                    MCEEditorRemoveComponent(context, selectedEntityId, ComponentMeshRenderer);
                }
            },
            true);
        if (meshOpen) {
            char meshHandle[64] = {0};
            char materialHandle[64] = {0};
            MCEEditorGetMeshRenderer(context, selectedEntityId, meshHandle, sizeof(meshHandle), materialHandle, sizeof(materialHandle));

            if (EditorUI::BeginPropertyTable("MeshRendererProps")) {
                if (DrawMeshHandleRow(context, state, "Mesh", meshHandle, sizeof(meshHandle), "MCE_ASSET_MODEL", selectedEntityId, materialHandle)) {
                    MCEEditorSetMeshRenderer(context, selectedEntityId, meshHandle, materialHandle);
                }
                if (DrawMaterialHandleRow(context, state, "Material", materialHandle, sizeof(materialHandle), "MCE_ASSET_MATERIAL", selectedEntityId, meshHandle, true)) {
                    MCEEditorSetMeshRenderer(context, selectedEntityId, meshHandle, materialHandle);
                    MCEEditorSetMaterialComponent(context, selectedEntityId, materialHandle);
                }
                EditorUI::EndPropertyTable();
            }

            if (materialHandle[0] != 0) {
                if (MaterialEditorState *textureState = GetInspectorMaterialState(context, state, materialHandle)) {
                    bool texturesDirty = DrawMaterialTextureInspector(context, state, *textureState, materialHandle);
                    TexturePickerState &picker = GetTexturePickerState(state);
                    bool pickerDirty = picker.didPick && strcmp(picker.materialHandle, materialHandle) == 0;
                    if (pickerDirty) {
                        picker.didPick = false;
                    }
                    if (texturesDirty || pickerDirty) {
                        EnforceMetalRoughnessRule(*textureState);
                        MCEEditorSetMaterialAsset(
                            context,
                            materialHandle,
                            textureState->name,
                            textureState->version,
                            textureState->baseColor[0], textureState->baseColor[1], textureState->baseColor[2],
                            textureState->metallic, textureState->roughness, textureState->ao,
                            textureState->emissive[0], textureState->emissive[1], textureState->emissive[2],
                            textureState->emissiveIntensity,
                            textureState->alphaMode, textureState->alphaCutoff,
                            textureState->doubleSided ? 1 : 0, textureState->unlit ? 1 : 0,
                            textureState->baseColorHandle,
                            textureState->normalHandle,
                            textureState->metalRoughnessHandle,
                            textureState->metallicHandle,
                            textureState->roughnessHandle,
                            textureState->aoHandle,
                            textureState->emissiveHandle);
                    }
                }
            }

            if (materialHandle[0] == 0) {
                if (ImGui::Button("Create + Assign New Material")) {
                    char outHandle[64] = {0};
                    MCEEditorCreateMaterial(context, "Materials", "NewMaterial", outHandle, sizeof(outHandle));
                    if (outHandle[0] != 0) {
                        MCEEditorSetMeshRenderer(context, selectedEntityId, meshHandle, outHandle);
                        MCEEditorSetMaterialComponent(context, selectedEntityId, outHandle);
                        MCEEditorSetSelectedMaterial(context, outHandle);
                    }
                }
            } else {
                if (ImGui::Button("Select Material")) {
                    MCEEditorSetSelectedMaterial(context, materialHandle);
                }
            }

            if (ImGui::Button("Remove Mesh Renderer")) {
                MCEEditorRemoveComponent(context, selectedEntityId, ComponentMeshRenderer);
            }
        }
    }

    bool hasMaterialComponent = hasValidEntity && (MCEEditorEntityHasComponent(context, selectedEntityId, ComponentMaterial) != 0);
    const bool showMaterialSection = !hasMeshRenderer && (hasSelectedMaterial || hasMaterialComponent);
    if (showMaterialSection) {
        char materialHandle[64] = {0};
        if (hasMaterialComponent) {
            MCEEditorGetMaterialComponent(context, selectedEntityId, materialHandle, sizeof(materialHandle));
        } else if (hasValidEntity) {
            char meshHandle[64] = {0};
            MCEEditorGetMeshRenderer(context, selectedEntityId, meshHandle, sizeof(meshHandle), materialHandle, sizeof(materialHandle));
        } else if (hasSelectedMaterial) {
            strncpy(materialHandle, selectedMaterial, sizeof(materialHandle) - 1);
        }

        bool materialOpen = EditorUI::BeginSectionWithContext(context, 
            "Material",
            "Inspector.Material",
            "MaterialContext",
            [&]() {
                if (hasValidEntity && ImGui::MenuItem("Clear Material")) {
                    const char *empty = "";
                    MCEEditorSetMeshRenderer(context, selectedEntityId, empty, empty);
                    MCEEditorSetMaterialComponent(context, selectedEntityId, empty);
                }
                if (hasValidEntity && ImGui::MenuItem("Remove Component")) {
                    MCEEditorRemoveComponent(context, selectedEntityId, ComponentMaterial);
                }
            },
            true);
        if (materialOpen) {
            if (materialHandle[0] == 0) {
                ImGui::TextUnformatted("Assign a material asset.");
                if (hasValidEntity) {
                    if (EditorUI::BeginPropertyTable("MaterialSelection")) {
                        if (DrawMaterialHandleRow(context, state, "Material", materialHandle, sizeof(materialHandle), "MCE_ASSET_MATERIAL", selectedEntityId, nullptr, false)) {
                            MCEEditorAssignMaterialToEntity(context, selectedEntityId, materialHandle);
                        }
                        EditorUI::EndPropertyTable();
                    }
                }
            } else {
                if (EditorUI::BeginPropertyTable("MaterialSelection")) {
                    if (DrawMaterialHandleRow(context, state, "Material", materialHandle, sizeof(materialHandle), "MCE_ASSET_MATERIAL", selectedEntityId, nullptr, false)) {
                        MCEEditorAssignMaterialToEntity(context, selectedEntityId, materialHandle);
                    }
                    EditorUI::EndPropertyTable();
                }

                if (MaterialEditorState *textureState = GetInspectorMaterialState(context, state, materialHandle)) {
                    bool texturesDirty = DrawMaterialTextureInspector(context, state, *textureState, materialHandle);
                    TexturePickerState &picker = GetTexturePickerState(state);
                    bool pickerDirty = picker.didPick && strcmp(picker.materialHandle, materialHandle) == 0;
                    if (pickerDirty) {
                        picker.didPick = false;
                    }
                    if (texturesDirty || pickerDirty) {
                        EnforceMetalRoughnessRule(*textureState);
                        MCEEditorSetMaterialAsset(
                            context,
                            materialHandle,
                            textureState->name,
                            textureState->version,
                            textureState->baseColor[0], textureState->baseColor[1], textureState->baseColor[2],
                            textureState->metallic, textureState->roughness, textureState->ao,
                            textureState->emissive[0], textureState->emissive[1], textureState->emissive[2],
                            textureState->emissiveIntensity,
                            textureState->alphaMode, textureState->alphaCutoff,
                            textureState->doubleSided ? 1 : 0, textureState->unlit ? 1 : 0,
                            textureState->baseColorHandle,
                            textureState->normalHandle,
                            textureState->metalRoughnessHandle,
                            textureState->metallicHandle,
                            textureState->roughnessHandle,
                            textureState->aoHandle,
                            textureState->emissiveHandle);
                    }
                }
            }
        }
    }

    if (hasValidEntity && MCEEditorEntityHasComponent(context, selectedEntityId, ComponentLight) != 0) {
        bool lightOpen = EditorUI::BeginSectionWithContext(context, 
            "Light",
            "Inspector.Light",
            "LightContext",
            [&]() {
                if (ImGui::MenuItem("Reset")) {
                    MCEEditorSetLight(context, selectedEntityId, 0, 1.0f, 1.0f, 1.0f, 1.0f, 0.0f, 0.95f, 0.9f, 0.0f, -1.0f, 0.0f, 0);
                }
                if (ImGui::MenuItem("Remove")) {
                    MCEEditorRemoveComponent(context, selectedEntityId, ComponentLight);
                }
            },
            true);
        if (lightOpen) {
            int32_t type = 0;
            float colorX = 1, colorY = 1, colorZ = 1;
            float brightness = 1, range = 0, innerCos = 0.95f, outerCos = 0.9f;
            float dirX = 0, dirY = -1, dirZ = 0;
            uint32_t castsShadows = 0;
            if (MCEEditorGetLight(context, selectedEntityId, &type, &colorX, &colorY, &colorZ, &brightness, &range, &innerCos, &outerCos, &dirX, &dirY, &dirZ, &castsShadows) != 0) {
                const char* types[] = {"Point", "Spot", "Directional"};
                bool dirty = false;
                if (EditorUI::BeginPropertyTable("LightProps")) {
                    dirty |= EditorUI::PropertyCombo("Type", &type, types, IM_ARRAYSIZE(types));
                    float color[3] = {colorX, colorY, colorZ};
                    const float lightDefault[3] = {1.0f, 1.0f, 1.0f};
                    if (EditorUI::PropertyColor3("Color", color, lightDefault, true)) {
                        colorX = color[0];
                        colorY = color[1];
                        colorZ = color[2];
                        dirty = true;
                    }
                    dirty |= EditorUI::PropertyFloat("Brightness", &brightness, 0.1f, 0.0f, 100.0f, "%.2f", true, true, 1.0f);
                    dirty |= EditorUI::PropertyFloat("Range", &range, 0.1f, 0.0f, 100.0f, "%.2f", true, true, 0.0f);
                    dirty |= EditorUI::PropertyFloat("Inner Cone", &innerCos, 0.01f, 0.0f, 1.0f, "%.3f", true, true, 0.95f);
                    dirty |= EditorUI::PropertyFloat("Outer Cone", &outerCos, 0.01f, 0.0f, 1.0f, "%.3f", true, true, 0.9f);
                    if (type == 2) {
                        bool castsShadowsBool = castsShadows != 0;
                        if (EditorUI::PropertyBool("Casts Shadows", &castsShadowsBool)) {
                            castsShadows = castsShadowsBool ? 1 : 0;
                            dirty = true;
                        }
                    }
                    EditorUI::EndPropertyTable();
                }
                if (dirty) {
                    MCEEditorSetLight(context, selectedEntityId, type, colorX, colorY, colorZ, brightness, range, innerCos, outerCos, dirX, dirY, dirZ, castsShadows);
                }
            }
            if (ImGui::Button("Remove Light")) {
                MCEEditorRemoveComponent(context, selectedEntityId, ComponentLight);
            }
        }
    }

    if (hasValidEntity && MCEEditorEntityHasComponent(context, selectedEntityId, ComponentSkyLight) != 0) {
        bool skyOpen = EditorUI::BeginSectionWithContext(context, 
            "Sky",
            "Inspector.Sky",
            "SkyContext",
            [&]() {
                if (ImGui::MenuItem("Reset")) {
                    const char *empty = "";
                    MCEEditorSetSkyLight(context, selectedEntityId, 0, 1,
                                         1.0f, 1.0f, 1.0f, 1.0f,
                                         2.0f, 0.0f, 30.0f,
                                         EditorUIConstants::kDefaultSkySunSize,
                                         0.24f, 0.45f, 0.95f,
                                         0.95f, 0.75f, 0.55f,
                                         EditorUIConstants::kDefaultSkyGradientStrength,
                                         EditorUIConstants::kDefaultSkyHazeDensity,
                                         EditorUIConstants::kDefaultSkyHazeFalloff,
                                         EditorUIConstants::kDefaultSkyHazeHeight,
                                         EditorUIConstants::kDefaultSkyOzoneStrength,
                                         0.55f, 0.7f, 1.0f,
                                         EditorUIConstants::kDefaultSkySunHaloSize,
                                         EditorUIConstants::kDefaultSkySunHaloIntensity,
                                         EditorUIConstants::kDefaultSkySunHaloSoftness,
                                         0,
                                         EditorUIConstants::kDefaultCloudCoverage,
                                         EditorUIConstants::kDefaultCloudSoftness,
                                         EditorUIConstants::kDefaultCloudScale,
                                         EditorUIConstants::kDefaultCloudSpeed,
                                         EditorUIConstants::kDefaultCloudWindX,
                                         EditorUIConstants::kDefaultCloudWindY,
                                         EditorUIConstants::kDefaultCloudHeight,
                                         EditorUIConstants::kDefaultCloudThickness,
                                         EditorUIConstants::kDefaultCloudBrightness,
                                         EditorUIConstants::kDefaultCloudSunInfluence,
                                         1,
                                         empty);
                }
                if (ImGui::MenuItem("Remove")) {
                    MCEEditorRemoveComponent(context, selectedEntityId, ComponentSkyLight);
                }
            },
            true);
        if (skyOpen) {
            int32_t skyCount = MCEEditorSkyEntityCount(context);
            if (skyCount > 1) {
                ImGui::TextColored(ImVec4(1.0f, 0.75f, 0.2f, 1.0f), "Warning: multiple Sky entities exist. Only one is active.");
            }
            char activeSky[64] = {0};
            bool isActive = (MCEEditorGetActiveSkyId(context, activeSky, sizeof(activeSky)) > 0) && (strcmp(activeSky, selectedEntityId) == 0);
            ImGui::Text("Active: %s", isActive ? "Yes" : "No");
            if (!isActive) {
                if (ImGui::Button("Set as Active Sky")) {
                    MCEEditorSetActiveSky(context, selectedEntityId);
                }
            }

            int32_t mode = 0;
            uint32_t enabled = 1;
            float intensity = 1.0f;
            float tintX = 1.0f, tintY = 1.0f, tintZ = 1.0f;
            float turbidity = 2.0f;
            float azimuth = 0.0f;
            float elevation = 30.0f;
            char hdriHandle[64] = {0};
            float sunSize = 0.535f;
            float zenithTintX = 0.24f, zenithTintY = 0.45f, zenithTintZ = 0.95f;
            float horizonTintX = 0.95f, horizonTintY = 0.75f, horizonTintZ = 0.55f;
            float gradientStrength = 1.0f;
            float hazeDensity = 0.35f;
            float hazeFalloff = 2.2f;
            float hazeHeight = 0.0f;
            float ozoneStrength = 0.35f;
            float ozoneTintX = 0.55f, ozoneTintY = 0.7f, ozoneTintZ = 1.0f;
            float sunHaloSize = 2.5f;
            float sunHaloIntensity = 0.5f;
            float sunHaloSoftness = 1.2f;
            uint32_t cloudsEnabled = 0;
            float cloudsCoverage = 0.35f;
            float cloudsSoftness = 0.6f;
            float cloudsScale = 1.0f;
            float cloudsSpeed = 0.02f;
            float cloudsWindX = 1.0f;
            float cloudsWindY = 0.0f;
            float cloudsHeight = 0.25f;
            float cloudsThickness = 0.35f;
            float cloudsBrightness = 1.0f;
            float cloudsSunInfluence = 1.0f;
            uint32_t autoRebuild = 1;
            uint32_t needsRebuild = 0;
            if (MCEEditorGetSkyLight(context, selectedEntityId, &mode, &enabled, &intensity, &tintX, &tintY, &tintZ,
                                     &turbidity, &azimuth, &elevation, &sunSize,
                                     &zenithTintX, &zenithTintY, &zenithTintZ,
                                     &horizonTintX, &horizonTintY, &horizonTintZ,
                                     &gradientStrength,
                                     &hazeDensity, &hazeFalloff, &hazeHeight,
                                     &ozoneStrength, &ozoneTintX, &ozoneTintY, &ozoneTintZ,
                                     &sunHaloSize, &sunHaloIntensity, &sunHaloSoftness,
                                     &cloudsEnabled, &cloudsCoverage, &cloudsSoftness,
                                     &cloudsScale, &cloudsSpeed,
                                     &cloudsWindX, &cloudsWindY,
                                     &cloudsHeight, &cloudsThickness,
                                     &cloudsBrightness, &cloudsSunInfluence,
                                     &autoRebuild, &needsRebuild,
                                     hdriHandle, sizeof(hdriHandle)) != 0) {
                const char* modes[] = {"HDRI", "Procedural"};
                PendingSkyState &pending = GetPendingSkyState(state);
                if (strncmp(pending.entityId, selectedEntityId, sizeof(pending.entityId)) != 0) {
                    memset(&pending, 0, sizeof(pending));
                    strncpy(pending.entityId, selectedEntityId, sizeof(pending.entityId) - 1);
                }

                int32_t editMode = mode;
                uint32_t editEnabled = enabled;
                float editIntensity = intensity;
                float editTintX = tintX;
                float editTintY = tintY;
                float editTintZ = tintZ;
                float editTurbidity = turbidity;
                float editAzimuth = azimuth;
                float editElevation = elevation;
                float editSunSize = sunSize;
                float editZenithTintX = zenithTintX;
                float editZenithTintY = zenithTintY;
                float editZenithTintZ = zenithTintZ;
                float editHorizonTintX = horizonTintX;
                float editHorizonTintY = horizonTintY;
                float editHorizonTintZ = horizonTintZ;
                float editGradientStrength = gradientStrength;
                float editHazeDensity = hazeDensity;
                float editHazeFalloff = hazeFalloff;
                float editHazeHeight = hazeHeight;
                float editOzoneStrength = ozoneStrength;
                float editOzoneTintX = ozoneTintX;
                float editOzoneTintY = ozoneTintY;
                float editOzoneTintZ = ozoneTintZ;
                float editSunHaloSize = sunHaloSize;
                float editSunHaloIntensity = sunHaloIntensity;
                float editSunHaloSoftness = sunHaloSoftness;
                uint32_t editCloudsEnabled = cloudsEnabled;
                float editCloudsCoverage = cloudsCoverage;
                float editCloudsSoftness = cloudsSoftness;
                float editCloudsScale = cloudsScale;
                float editCloudsSpeed = cloudsSpeed;
                float editCloudsWindX = cloudsWindX;
                float editCloudsWindY = cloudsWindY;
                float editCloudsHeight = cloudsHeight;
                float editCloudsThickness = cloudsThickness;
                float editCloudsBrightness = cloudsBrightness;
                float editCloudsSunInfluence = cloudsSunInfluence;
                EnvironmentPickerState &envPicker = GetEnvironmentPickerState(state);
                const bool envPickerDirty = envPicker.didPick && (strcmp(envPicker.entityId, selectedEntityId) == 0);
                if (!envPickerDirty) {
                    strncpy(pending.hdriHandle, hdriHandle, sizeof(pending.hdriHandle) - 1);
                    pending.hdriHandle[sizeof(pending.hdriHandle) - 1] = 0;
                }
                char *editHdriHandle = pending.hdriHandle;

                bool dirty = false;
                int presetIndex = pending.presetIndex;
                if (presetIndex < 0 || presetIndex >= IM_ARRAYSIZE(kSkyPresetNames)) {
                    presetIndex = 0;
                    pending.presetIndex = 0;
                }

                if (editMode == 1) {
                    ImGui::TextDisabled("Mood Presets");
                    if (EditorUI::BeginPropertyTable("SkyPresetProps")) {
                        if (EditorUI::PropertyCombo("Preset", &presetIndex, kSkyPresetNames, IM_ARRAYSIZE(kSkyPresetNames))) {
                            pending.presetIndex = presetIndex;
                        }
                        EditorUI::EndPropertyTable();
                    }
                    if (ImGui::Button("Apply Preset")) {
                        const SkyPreset &preset = kSkyPresets[presetIndex];
                        editMode = preset.mode;
                        editEnabled = preset.enabled;
                        editIntensity = preset.intensity;
                        editTintX = preset.tintX;
                        editTintY = preset.tintY;
                        editTintZ = preset.tintZ;
                        editTurbidity = preset.turbidity;
                        editAzimuth = preset.azimuth;
                        editElevation = preset.elevation;
                        editSunSize = preset.sunSize;
                        editZenithTintX = preset.zenithTintX;
                        editZenithTintY = preset.zenithTintY;
                        editZenithTintZ = preset.zenithTintZ;
                        editHorizonTintX = preset.horizonTintX;
                        editHorizonTintY = preset.horizonTintY;
                        editHorizonTintZ = preset.horizonTintZ;
                        editGradientStrength = preset.gradientStrength;
                        editHazeDensity = preset.hazeDensity;
                        editHazeFalloff = preset.hazeFalloff;
                        editHazeHeight = preset.hazeHeight;
                        editOzoneStrength = preset.ozoneStrength;
                        editOzoneTintX = preset.ozoneTintX;
                        editOzoneTintY = preset.ozoneTintY;
                        editOzoneTintZ = preset.ozoneTintZ;
                        editSunHaloSize = preset.sunHaloSize;
                        editSunHaloIntensity = preset.sunHaloIntensity;
                        editSunHaloSoftness = preset.sunHaloSoftness;
                        editCloudsEnabled = preset.cloudsEnabled;
                        editCloudsCoverage = preset.cloudsCoverage;
                        editCloudsSoftness = preset.cloudsSoftness;
                        editCloudsScale = preset.cloudsScale;
                        editCloudsSpeed = preset.cloudsSpeed;
                        editCloudsWindX = preset.cloudsWindX;
                        editCloudsWindY = preset.cloudsWindY;
                        editCloudsHeight = preset.cloudsHeight;
                        editCloudsThickness = preset.cloudsThickness;
                        editCloudsBrightness = preset.cloudsBrightness;
                        editCloudsSunInfluence = preset.cloudsSunInfluence;
                        dirty = true;
                    }
                    ImGui::SameLine();
                    if (ImGui::Button("Randomize Slightly")) {
                        editIntensity = ClampFloat(editIntensity * (1.0f + RandomRange(-0.12f, 0.12f)),
                                                   EditorUIConstants::kSkyIntensityMin,
                                                   EditorUIConstants::kSkyIntensityMax);
                        editTurbidity = ClampFloat(editTurbidity + RandomRange(-0.5f, 0.5f),
                                                   EditorUIConstants::kSkyTurbidityMin,
                                                   EditorUIConstants::kSkyTurbidityMax);
                        editAzimuth = fmodf(editAzimuth + RandomRange(-12.0f, 12.0f) + 360.0f, 360.0f);
                        editElevation = ClampFloat(editElevation + RandomRange(-4.0f, 4.0f),
                                                   EditorUIConstants::kSkyElevationMin,
                                                   EditorUIConstants::kSkyElevationMax);
                        editSunSize = ClampFloat(editSunSize * (1.0f + RandomRange(-0.15f, 0.15f)),
                                                 EditorUIConstants::kSkySunSizeMin,
                                                 EditorUIConstants::kSkySunSizeMax);
                        editGradientStrength = ClampFloat(editGradientStrength + RandomRange(-0.15f, 0.15f),
                                                          EditorUIConstants::kSkyGradientStrengthMin,
                                                          EditorUIConstants::kSkyGradientStrengthMax);
                        editHazeDensity = ClampFloat(editHazeDensity + RandomRange(-0.08f, 0.08f),
                                                     EditorUIConstants::kSkyHazeDensityMin,
                                                     EditorUIConstants::kSkyHazeDensityMax);
                        editHazeFalloff = ClampFloat(editHazeFalloff + RandomRange(-0.4f, 0.4f),
                                                     EditorUIConstants::kSkyHazeFalloffMin,
                                                     EditorUIConstants::kSkyHazeFalloffMax);
                        editHazeHeight = ClampFloat(editHazeHeight + RandomRange(-0.04f, 0.04f),
                                                    EditorUIConstants::kSkyHazeHeightMin,
                                                    EditorUIConstants::kSkyHazeHeightMax);
                        editOzoneStrength = ClampFloat(editOzoneStrength + RandomRange(-0.15f, 0.15f),
                                                       EditorUIConstants::kSkyOzoneStrengthMin,
                                                       EditorUIConstants::kSkyOzoneStrengthMax);
                        editSunHaloSize = ClampFloat(editSunHaloSize + RandomRange(-0.3f, 0.3f),
                                                     EditorUIConstants::kSkySunHaloSizeMin,
                                                     EditorUIConstants::kSkySunHaloSizeMax);
                        editSunHaloIntensity = ClampFloat(editSunHaloIntensity + RandomRange(-0.2f, 0.2f),
                                                          EditorUIConstants::kSkySunHaloIntensityMin,
                                                          EditorUIConstants::kSkySunHaloIntensityMax);
                        editSunHaloSoftness = ClampFloat(editSunHaloSoftness + RandomRange(-0.2f, 0.2f),
                                                         EditorUIConstants::kSkySunHaloSoftnessMin,
                                                         EditorUIConstants::kSkySunHaloSoftnessMax);
                        editTintX = ClampFloat(editTintX + RandomRange(-0.05f, 0.05f), 0.0f, 1.0f);
                        editTintY = ClampFloat(editTintY + RandomRange(-0.05f, 0.05f), 0.0f, 1.0f);
                        editTintZ = ClampFloat(editTintZ + RandomRange(-0.05f, 0.05f), 0.0f, 1.0f);
                        editZenithTintX = ClampFloat(editZenithTintX + RandomRange(-0.06f, 0.06f), 0.0f, 1.2f);
                        editZenithTintY = ClampFloat(editZenithTintY + RandomRange(-0.06f, 0.06f), 0.0f, 1.2f);
                        editZenithTintZ = ClampFloat(editZenithTintZ + RandomRange(-0.06f, 0.06f), 0.0f, 1.2f);
                        editHorizonTintX = ClampFloat(editHorizonTintX + RandomRange(-0.06f, 0.06f), 0.0f, 1.2f);
                        editHorizonTintY = ClampFloat(editHorizonTintY + RandomRange(-0.06f, 0.06f), 0.0f, 1.2f);
                        editHorizonTintZ = ClampFloat(editHorizonTintZ + RandomRange(-0.06f, 0.06f), 0.0f, 1.2f);
                        editOzoneTintX = ClampFloat(editOzoneTintX + RandomRange(-0.06f, 0.06f), 0.0f, 1.2f);
                        editOzoneTintY = ClampFloat(editOzoneTintY + RandomRange(-0.06f, 0.06f), 0.0f, 1.2f);
                        editOzoneTintZ = ClampFloat(editOzoneTintZ + RandomRange(-0.06f, 0.06f), 0.0f, 1.2f);
                        if (editCloudsEnabled != 0) {
                            editCloudsCoverage = ClampFloat(editCloudsCoverage + RandomRange(-0.08f, 0.08f),
                                                            EditorUIConstants::kCloudCoverageMin,
                                                            EditorUIConstants::kCloudCoverageMax);
                            editCloudsSoftness = ClampFloat(editCloudsSoftness + RandomRange(-0.08f, 0.08f),
                                                            EditorUIConstants::kCloudSoftnessMin,
                                                            EditorUIConstants::kCloudSoftnessMax);
                            editCloudsScale = ClampFloat(editCloudsScale * (1.0f + RandomRange(-0.2f, 0.2f)),
                                                         EditorUIConstants::kCloudScaleMin,
                                                         EditorUIConstants::kCloudScaleMax);
                            editCloudsSpeed = ClampFloat(editCloudsSpeed + RandomRange(-0.03f, 0.03f),
                                                         EditorUIConstants::kCloudSpeedMin,
                                                         EditorUIConstants::kCloudSpeedMax);
                            float windX = editCloudsWindX + RandomRange(-0.2f, 0.2f);
                            float windY = editCloudsWindY + RandomRange(-0.2f, 0.2f);
                            float windLen = sqrtf(windX * windX + windY * windY);
                            if (windLen > 0.001f) {
                                windX /= windLen;
                                windY /= windLen;
                            }
                            editCloudsWindX = ClampFloat(windX, EditorUIConstants::kCloudWindMin, EditorUIConstants::kCloudWindMax);
                            editCloudsWindY = ClampFloat(windY, EditorUIConstants::kCloudWindMin, EditorUIConstants::kCloudWindMax);
                            editCloudsHeight = ClampFloat(editCloudsHeight + RandomRange(-0.05f, 0.05f),
                                                          EditorUIConstants::kCloudHeightMin,
                                                          EditorUIConstants::kCloudHeightMax);
                            editCloudsThickness = ClampFloat(editCloudsThickness + RandomRange(-0.06f, 0.06f),
                                                             EditorUIConstants::kCloudThicknessMin,
                                                             EditorUIConstants::kCloudThicknessMax);
                            editCloudsBrightness = ClampFloat(editCloudsBrightness + RandomRange(-0.15f, 0.15f),
                                                              EditorUIConstants::kCloudBrightnessMin,
                                                              EditorUIConstants::kCloudBrightnessMax);
                            editCloudsSunInfluence = ClampFloat(editCloudsSunInfluence + RandomRange(-0.2f, 0.2f),
                                                                EditorUIConstants::kCloudSunInfluenceMin,
                                                                EditorUIConstants::kCloudSunInfluenceMax);
                        }
                        dirty = true;
                    }
                }

                ImGui::Spacing();
                ImGui::TextDisabled("Art Direction (Live)");
                if (EditorUI::BeginPropertyTable("SkyArtProps")) {
                    bool enabledBool = editEnabled != 0;
                    if (EditorUI::PropertyBool("Enabled", &enabledBool)) {
                        editEnabled = enabledBool ? 1 : 0;
                        dirty = true;
                    }
                    dirty |= EditorUI::PropertyFloat("Intensity",
                                                     &editIntensity,
                                                     EditorUIConstants::kSkyIntensityStep,
                                                     EditorUIConstants::kSkyIntensityMin,
                                                     EditorUIConstants::kSkyIntensityMax,
                                                     "%.2f",
                                                     true,
                                                     true,
                                                     EditorUIConstants::kDefaultSkyIntensity);
                    float tint[3] = {editTintX, editTintY, editTintZ};
                    const float tintDefault[3] = {1.0f, 1.0f, 1.0f};
                    if (EditorUI::PropertyColor3("Tint", tint, tintDefault, true)) {
                        editTintX = tint[0];
                        editTintY = tint[1];
                        editTintZ = tint[2];
                        dirty = true;
                    }
                    if (editMode == 1) {
                        dirty |= EditorUI::PropertyFloat("Azimuth",
                                                         &editAzimuth,
                                                         EditorUIConstants::kSkyAzimuthStep,
                                                         EditorUIConstants::kSkyAzimuthMin,
                                                         EditorUIConstants::kSkyAzimuthMax,
                                                         "%.2f",
                                                         true,
                                                         true,
                                                         EditorUIConstants::kDefaultSkyAzimuth);
                        dirty |= EditorUI::PropertyFloat("Elevation",
                                                         &editElevation,
                                                         EditorUIConstants::kSkyElevationStep,
                                                         EditorUIConstants::kSkyElevationMin,
                                                         EditorUIConstants::kSkyElevationMax,
                                                         "%.2f",
                                                         true,
                                                         true,
                                                         EditorUIConstants::kDefaultSkyElevation);
                        dirty |= EditorUI::PropertyFloat("Turbidity",
                                                         &editTurbidity,
                                                         EditorUIConstants::kSkyTurbidityStep,
                                                         EditorUIConstants::kSkyTurbidityMin,
                                                         EditorUIConstants::kSkyTurbidityMax,
                                                         "%.2f",
                                                         true,
                                                         true,
                                                         EditorUIConstants::kDefaultSkyTurbidity);
                        dirty |= EditorUI::PropertyFloat("Sun Size (deg)",
                                                         &editSunSize,
                                                         EditorUIConstants::kSkySunSizeStep,
                                                         EditorUIConstants::kSkySunSizeMin,
                                                         EditorUIConstants::kSkySunSizeMax,
                                                         "%.2f",
                                                         true,
                                                         true,
                                                         EditorUIConstants::kDefaultSkySunSize);
                        float zenithTint[3] = {editZenithTintX, editZenithTintY, editZenithTintZ};
                        const float zenithDefault[3] = {0.24f, 0.45f, 0.95f};
                        if (EditorUI::PropertyColor3("Zenith Tint", zenithTint, zenithDefault, true)) {
                            editZenithTintX = zenithTint[0];
                            editZenithTintY = zenithTint[1];
                            editZenithTintZ = zenithTint[2];
                            dirty = true;
                        }
                        float horizonTint[3] = {editHorizonTintX, editHorizonTintY, editHorizonTintZ};
                        const float horizonDefault[3] = {0.95f, 0.75f, 0.55f};
                        if (EditorUI::PropertyColor3("Horizon Tint", horizonTint, horizonDefault, true)) {
                            editHorizonTintX = horizonTint[0];
                            editHorizonTintY = horizonTint[1];
                            editHorizonTintZ = horizonTint[2];
                            dirty = true;
                        }
                        dirty |= EditorUI::PropertyFloat("Gradient Strength",
                                                         &editGradientStrength,
                                                         EditorUIConstants::kSkyGradientStrengthStep,
                                                         EditorUIConstants::kSkyGradientStrengthMin,
                                                         EditorUIConstants::kSkyGradientStrengthMax,
                                                         "%.2f",
                                                         true,
                                                         true,
                                                         EditorUIConstants::kDefaultSkyGradientStrength);
                        dirty |= EditorUI::PropertyFloat("Haze Density",
                                                         &editHazeDensity,
                                                         EditorUIConstants::kSkyHazeDensityStep,
                                                         EditorUIConstants::kSkyHazeDensityMin,
                                                         EditorUIConstants::kSkyHazeDensityMax,
                                                         "%.2f",
                                                         true,
                                                         true,
                                                         EditorUIConstants::kDefaultSkyHazeDensity);
                        dirty |= EditorUI::PropertyFloat("Haze Falloff",
                                                         &editHazeFalloff,
                                                         EditorUIConstants::kSkyHazeFalloffStep,
                                                         EditorUIConstants::kSkyHazeFalloffMin,
                                                         EditorUIConstants::kSkyHazeFalloffMax,
                                                         "%.2f",
                                                         true,
                                                         true,
                                                         EditorUIConstants::kDefaultSkyHazeFalloff);
                        dirty |= EditorUI::PropertyFloat("Haze Height",
                                                         &editHazeHeight,
                                                         EditorUIConstants::kSkyHazeHeightStep,
                                                         EditorUIConstants::kSkyHazeHeightMin,
                                                         EditorUIConstants::kSkyHazeHeightMax,
                                                         "%.2f",
                                                         true,
                                                         true,
                                                         EditorUIConstants::kDefaultSkyHazeHeight);
                        dirty |= EditorUI::PropertyFloat("Ozone Strength",
                                                         &editOzoneStrength,
                                                         EditorUIConstants::kSkyOzoneStrengthStep,
                                                         EditorUIConstants::kSkyOzoneStrengthMin,
                                                         EditorUIConstants::kSkyOzoneStrengthMax,
                                                         "%.2f",
                                                         true,
                                                         true,
                                                         EditorUIConstants::kDefaultSkyOzoneStrength);
                        float ozoneTint[3] = {editOzoneTintX, editOzoneTintY, editOzoneTintZ};
                        const float ozoneDefault[3] = {0.55f, 0.7f, 1.0f};
                        if (EditorUI::PropertyColor3("Ozone Tint", ozoneTint, ozoneDefault, true)) {
                            editOzoneTintX = ozoneTint[0];
                            editOzoneTintY = ozoneTint[1];
                            editOzoneTintZ = ozoneTint[2];
                            dirty = true;
                        }
                        dirty |= EditorUI::PropertyFloat("Sun Halo Size",
                                                         &editSunHaloSize,
                                                         EditorUIConstants::kSkySunHaloSizeStep,
                                                         EditorUIConstants::kSkySunHaloSizeMin,
                                                         EditorUIConstants::kSkySunHaloSizeMax,
                                                         "%.2f",
                                                         true,
                                                         true,
                                                         EditorUIConstants::kDefaultSkySunHaloSize);
                        dirty |= EditorUI::PropertyFloat("Sun Halo Intensity",
                                                         &editSunHaloIntensity,
                                                         EditorUIConstants::kSkySunHaloIntensityStep,
                                                         EditorUIConstants::kSkySunHaloIntensityMin,
                                                         EditorUIConstants::kSkySunHaloIntensityMax,
                                                         "%.2f",
                                                         true,
                                                         true,
                                                         EditorUIConstants::kDefaultSkySunHaloIntensity);
                        dirty |= EditorUI::PropertyFloat("Sun Halo Softness",
                                                         &editSunHaloSoftness,
                                                         EditorUIConstants::kSkySunHaloSoftnessStep,
                                                         EditorUIConstants::kSkySunHaloSoftnessMin,
                                                         EditorUIConstants::kSkySunHaloSoftnessMax,
                                                         "%.2f",
                                                         true,
                                                         true,
                                                         EditorUIConstants::kDefaultSkySunHaloSoftness);
                    }
                    EditorUI::EndPropertyTable();
                }

                if (editMode == 1) {
                    ImGui::Spacing();
                    ImGui::TextDisabled("Clouds (Live)");
                    if (EditorUI::BeginPropertyTable("SkyCloudProps")) {
                        bool cloudsEnabledBool = editCloudsEnabled != 0;
                        if (EditorUI::PropertyBool("Enabled", &cloudsEnabledBool)) {
                            editCloudsEnabled = cloudsEnabledBool ? 1 : 0;
                            dirty = true;
                        }
                        if (editCloudsEnabled != 0) {
                            dirty |= EditorUI::PropertyFloat("Coverage",
                                                             &editCloudsCoverage,
                                                             EditorUIConstants::kCloudCoverageStep,
                                                             EditorUIConstants::kCloudCoverageMin,
                                                             EditorUIConstants::kCloudCoverageMax,
                                                             "%.2f",
                                                             true,
                                                             true,
                                                             EditorUIConstants::kDefaultCloudCoverage);
                            dirty |= EditorUI::PropertyFloat("Softness",
                                                             &editCloudsSoftness,
                                                             EditorUIConstants::kCloudSoftnessStep,
                                                             EditorUIConstants::kCloudSoftnessMin,
                                                             EditorUIConstants::kCloudSoftnessMax,
                                                             "%.2f",
                                                             true,
                                                             true,
                                                             EditorUIConstants::kDefaultCloudSoftness);
                            dirty |= EditorUI::PropertyFloat("Scale",
                                                             &editCloudsScale,
                                                             EditorUIConstants::kCloudScaleStep,
                                                             EditorUIConstants::kCloudScaleMin,
                                                             EditorUIConstants::kCloudScaleMax,
                                                             "%.2f",
                                                             true,
                                                             true,
                                                             EditorUIConstants::kDefaultCloudScale);
                            dirty |= EditorUI::PropertyFloat("Speed",
                                                             &editCloudsSpeed,
                                                             EditorUIConstants::kCloudSpeedStep,
                                                             EditorUIConstants::kCloudSpeedMin,
                                                             EditorUIConstants::kCloudSpeedMax,
                                                             "%.2f",
                                                             true,
                                                             true,
                                                             EditorUIConstants::kDefaultCloudSpeed);
                            dirty |= EditorUI::PropertyFloat("Wind X",
                                                             &editCloudsWindX,
                                                             EditorUIConstants::kCloudWindStep,
                                                             EditorUIConstants::kCloudWindMin,
                                                             EditorUIConstants::kCloudWindMax,
                                                             "%.2f",
                                                             true,
                                                             true,
                                                             EditorUIConstants::kDefaultCloudWindX);
                            dirty |= EditorUI::PropertyFloat("Wind Y",
                                                             &editCloudsWindY,
                                                             EditorUIConstants::kCloudWindStep,
                                                             EditorUIConstants::kCloudWindMin,
                                                             EditorUIConstants::kCloudWindMax,
                                                             "%.2f",
                                                             true,
                                                             true,
                                                             EditorUIConstants::kDefaultCloudWindY);
                            dirty |= EditorUI::PropertyFloat("Height",
                                                             &editCloudsHeight,
                                                             EditorUIConstants::kCloudHeightStep,
                                                             EditorUIConstants::kCloudHeightMin,
                                                             EditorUIConstants::kCloudHeightMax,
                                                             "%.2f",
                                                             true,
                                                             true,
                                                             EditorUIConstants::kDefaultCloudHeight);
                            dirty |= EditorUI::PropertyFloat("Thickness",
                                                             &editCloudsThickness,
                                                             EditorUIConstants::kCloudThicknessStep,
                                                             EditorUIConstants::kCloudThicknessMin,
                                                             EditorUIConstants::kCloudThicknessMax,
                                                             "%.2f",
                                                             true,
                                                             true,
                                                             EditorUIConstants::kDefaultCloudThickness);
                            dirty |= EditorUI::PropertyFloat("Brightness",
                                                             &editCloudsBrightness,
                                                             EditorUIConstants::kCloudBrightnessStep,
                                                             EditorUIConstants::kCloudBrightnessMin,
                                                             EditorUIConstants::kCloudBrightnessMax,
                                                             "%.2f",
                                                             true,
                                                             true,
                                                             EditorUIConstants::kDefaultCloudBrightness);
                            dirty |= EditorUI::PropertyFloat("Sun Influence",
                                                             &editCloudsSunInfluence,
                                                             EditorUIConstants::kCloudSunInfluenceStep,
                                                             EditorUIConstants::kCloudSunInfluenceMin,
                                                             EditorUIConstants::kCloudSunInfluenceMax,
                                                             "%.2f",
                                                             true,
                                                             true,
                                                             EditorUIConstants::kDefaultCloudSunInfluence);
                        }
                        EditorUI::EndPropertyTable();
                    }
                }

                ImGui::Spacing();
                ImGui::TextDisabled("Rebuild-required");
                if (EditorUI::BeginPropertyTable("SkyRebuildProps")) {
                    dirty |= EditorUI::PropertyCombo("Mode", &editMode, modes, IM_ARRAYSIZE(modes));
                    if (editMode == 0) {
                        dirty |= DrawEnvironmentHandleRow(context, state, "HDRI", editHdriHandle, sizeof(pending.hdriHandle), "MCE_ASSET_ENVIRONMENT", selectedEntityId);
                    }
                    EditorUI::EndPropertyTable();
                }

                if (envPickerDirty) {
                    envPicker.didPick = false;
                    dirty = true;
                }

                bool autoRebuildBool = autoRebuild != 0;
                if (ImGui::Checkbox("Auto Rebuild", &autoRebuildBool)) {
                    autoRebuild = autoRebuildBool ? 1 : 0;
                    dirty = true;
                }
                ImGui::SameLine();
                if (ImGui::Button("Rebuild IBL")) {
                    MCEEditorRequestSkyRebuild(context, selectedEntityId);
                }
                if (needsRebuild != 0) {
                    ImGui::TextColored(ImVec4(1.0f, 0.75f, 0.2f, 1.0f), "IBL rebuild required.");
                }

                if (dirty) {
                    MCEEditorSetSkyLight(context, selectedEntityId,
                                         editMode,
                                         editEnabled,
                                         editIntensity,
                                         editTintX,
                                         editTintY,
                                         editTintZ,
                                         editTurbidity,
                                         editAzimuth,
                                         editElevation,
                                         editSunSize,
                                         editZenithTintX,
                                         editZenithTintY,
                                         editZenithTintZ,
                                         editHorizonTintX,
                                         editHorizonTintY,
                                         editHorizonTintZ,
                                         editGradientStrength,
                                         editHazeDensity,
                                         editHazeFalloff,
                                         editHazeHeight,
                                         editOzoneStrength,
                                         editOzoneTintX,
                                         editOzoneTintY,
                                         editOzoneTintZ,
                                         editSunHaloSize,
                                         editSunHaloIntensity,
                                         editSunHaloSoftness,
                                         editCloudsEnabled,
                                         editCloudsCoverage,
                                         editCloudsSoftness,
                                         editCloudsScale,
                                         editCloudsSpeed,
                                         editCloudsWindX,
                                         editCloudsWindY,
                                         editCloudsHeight,
                                         editCloudsThickness,
                                         editCloudsBrightness,
                                         editCloudsSunInfluence,
                                         autoRebuild,
                                         editHdriHandle);
                }
            }
            if (ImGui::Button("Remove Sky")) {
                MCEEditorRemoveComponent(context, selectedEntityId, ComponentSkyLight);
            }
        }
    }

    if (hasValidEntity && ImGui::Button("Add Component")) {
        ImGui::OpenPopup("AddComponentPopup");
    }
    if (ImGui::BeginPopup("AddComponentPopup")) {
        if (MCEEditorEntityHasComponent(context, selectedEntityId, ComponentMeshRenderer) == 0) {
            if (ImGui::MenuItem("Mesh Renderer")) {
                MCEEditorAddComponent(context, selectedEntityId, ComponentMeshRenderer);
            }
        }
        if (MCEEditorEntityHasComponent(context, selectedEntityId, ComponentMaterial) == 0) {
            if (ImGui::MenuItem("Material")) {
                MCEEditorAddComponent(context, selectedEntityId, ComponentMaterial);
            }
        }
        if (MCEEditorEntityHasComponent(context, selectedEntityId, ComponentCamera) == 0) {
            if (ImGui::MenuItem("Camera")) {
                MCEEditorAddComponent(context, selectedEntityId, ComponentCamera);
            }
        }
        if (MCEEditorEntityHasComponent(context, selectedEntityId, ComponentLight) == 0) {
            if (ImGui::MenuItem("Light")) {
                MCEEditorAddComponent(context, selectedEntityId, ComponentLight);
            }
        }
        if (MCEEditorEntityHasComponent(context, selectedEntityId, ComponentSkyLight) == 0) {
            if (ImGui::MenuItem("Sky Light")) {
                MCEEditorAddComponent(context, selectedEntityId, ComponentSkyLight);
            }
        }
        ImGui::EndPopup();
    }

    MaterialPopupState &popup = GetMaterialPopupState(state);
    if (popup.open) {
        ImGui::SetNextWindowSize(ImVec2(520.0f, 520.0f), ImGuiCond_Once);
        if (ImGui::BeginPopupModal(popup.title.c_str(), &popup.open, ImGuiWindowFlags_AlwaysAutoResize)) {
            ImGui::BeginChild("MaterialEditorScroll", ImVec2(0, 360.0f), false, ImGuiWindowFlags_AlwaysVerticalScrollbar);
            const bool changed = DrawMaterialEditorContents(popup.state);
            ImGui::EndChild();
            if (changed) {
                popup.dirty = true;
            }

            ImGui::Spacing();
            if (popup.dirty) {
                ImGui::TextColored(ImVec4(0.95f, 0.7f, 0.2f, 1.0f), "* Unsaved changes");
            }

            if (ImGui::Button("Save")) {
                EnforceMetalRoughnessRule(popup.state);
                MCEEditorSetMaterialAsset(
                    context,
                    popup.handle,
                    popup.state.name,
                    popup.state.version,
                    popup.state.baseColor[0], popup.state.baseColor[1], popup.state.baseColor[2],
                    popup.state.metallic, popup.state.roughness, popup.state.ao,
                    popup.state.emissive[0], popup.state.emissive[1], popup.state.emissive[2],
                    popup.state.emissiveIntensity,
                    popup.state.alphaMode, popup.state.alphaCutoff,
                    popup.state.doubleSided ? 1 : 0, popup.state.unlit ? 1 : 0,
                    popup.state.baseColorHandle,
                    popup.state.normalHandle,
                    popup.state.metalRoughnessHandle,
                    popup.state.metallicHandle,
                    popup.state.roughnessHandle,
                    popup.state.aoHandle,
                    popup.state.emissiveHandle);
                popup.dirty = false;
            }
            ImGui::SameLine();
            if (ImGui::Button("Close")) {
                popup.open = false;
                ImGui::CloseCurrentPopup();
            }

            ImGui::EndPopup();
        }
    }

    ImGui::PopStyleVar();
    ImGui::EndChild();

    TexturePickerState &picker = GetTexturePickerState(state);
    if (picker.requestOpen) {
        ImGui::OpenPopup("TexturePicker");
        picker.requestOpen = false;
    }
    if (picker.open) {
        ImGui::SetNextWindowSize(ImVec2(420.0f, 320.0f), ImGuiCond_Once);
        if (ImGui::BeginPopupModal("TexturePicker", &picker.open, ImGuiWindowFlags_AlwaysAutoResize)) {
            ImGui::TextUnformatted(picker.title);
            ImGui::Separator();
            ImGui::InputTextWithHint("##TextureFilter", "Search textures...", picker.filter, sizeof(picker.filter));
            ImGui::Separator();

            std::vector<AssetOption> options;
            LoadTextureOptions(context, options);
            const std::string filterText = EditorUI::ToLower(std::string(picker.filter));
            for (const auto &option : options) {
                if (!filterText.empty() && EditorUI::ToLower(option.name).find(filterText) == std::string::npos) {
                    continue;
                }
                if (ImGui::Selectable(option.name.c_str())) {
                    if (picker.target) {
                        strncpy(picker.target, option.handle.c_str(), 63);
                        picker.target[63] = 0;
                    }
                    picker.didPick = true;
                    picker.open = false;
                    ImGui::CloseCurrentPopup();
                    break;
                }
            }

            if (options.empty()) {
                ImGui::TextDisabled("No textures found.");
            }

            ImGui::Spacing();
            if (ImGui::Button("Close")) {
                picker.open = false;
                ImGui::CloseCurrentPopup();
            }

            ImGui::EndPopup();
        }
    }

    EnvironmentPickerState &envPicker = GetEnvironmentPickerState(state);
    if (envPicker.requestOpen) {
        ImGui::OpenPopup("EnvironmentPicker");
        envPicker.requestOpen = false;
    }
    if (envPicker.open) {
        ImGui::SetNextWindowSize(ImVec2(420.0f, 320.0f), ImGuiCond_Once);
        if (ImGui::BeginPopupModal("EnvironmentPicker", &envPicker.open, ImGuiWindowFlags_AlwaysAutoResize)) {
            ImGui::TextUnformatted(envPicker.title);
            ImGui::Separator();
            ImGui::InputTextWithHint("##EnvironmentFilter", "Search environments...", envPicker.filter, sizeof(envPicker.filter));
            ImGui::Separator();

            std::vector<AssetOption> options;
            LoadEnvironmentOptions(context, options);
            const std::string filterText = EditorUI::ToLower(std::string(envPicker.filter));
            for (const auto &option : options) {
                if (!filterText.empty() && EditorUI::ToLower(option.name).find(filterText) == std::string::npos) {
                    continue;
                }
                if (ImGui::Selectable(option.name.c_str())) {
                    if (envPicker.target) {
                        strncpy(envPicker.target, option.handle.c_str(), 63);
                        envPicker.target[63] = 0;
                    }
                    envPicker.didPick = true;
                    envPicker.open = false;
                    ImGui::CloseCurrentPopup();
                    break;
                }
            }

            if (options.empty()) {
                ImGui::TextDisabled("No environment assets found.");
            }

            ImGui::Spacing();
            if (ImGui::Button("Close")) {
                envPicker.open = false;
                ImGui::CloseCurrentPopup();
            }

            ImGui::EndPopup();
        }
    }

    MeshPickerState &meshPicker = GetMeshPickerState(state);
    if (meshPicker.requestOpen) {
        ImGui::OpenPopup("MeshPicker");
        meshPicker.requestOpen = false;
    }
    if (meshPicker.open) {
        ImGui::SetNextWindowSize(ImVec2(420.0f, 320.0f), ImGuiCond_Once);
        if (ImGui::BeginPopupModal("MeshPicker", &meshPicker.open, ImGuiWindowFlags_AlwaysAutoResize)) {
            ImGui::TextUnformatted(meshPicker.title);
            ImGui::Separator();
            ImGui::InputTextWithHint("##MeshFilter", "Search meshes...", meshPicker.filter, sizeof(meshPicker.filter));
            ImGui::Separator();

            std::vector<AssetOption> options;
            LoadMeshOptions(context, options);
            const std::string filterText = EditorUI::ToLower(std::string(meshPicker.filter));
            for (const auto &option : options) {
                if (!filterText.empty() && EditorUI::ToLower(option.name).find(filterText) == std::string::npos) {
                    continue;
                }
                if (ImGui::Selectable(option.name.c_str())) {
                    if (meshPicker.entityId[0] != 0) {
                        MCEEditorSetMeshRenderer(context, meshPicker.entityId, option.handle.c_str(), meshPicker.materialHandle);
                    }
                    meshPicker.open = false;
                    ImGui::CloseCurrentPopup();
                    break;
                }
            }

            if (options.empty()) {
                ImGui::TextDisabled("No mesh assets found.");
            }

            ImGui::Spacing();
            if (ImGui::Button("Close")) {
                meshPicker.open = false;
                ImGui::CloseCurrentPopup();
            }

            ImGui::EndPopup();
        }
    }

    MaterialPickerState &materialPicker = GetMaterialPickerState(state);
    if (materialPicker.requestOpen) {
        ImGui::OpenPopup("MaterialPicker");
        materialPicker.requestOpen = false;
    }
    if (materialPicker.open) {
        ImGui::SetNextWindowSize(ImVec2(420.0f, 320.0f), ImGuiCond_Once);
        if (ImGui::BeginPopupModal("MaterialPicker", &materialPicker.open, ImGuiWindowFlags_AlwaysAutoResize)) {
            ImGui::TextUnformatted(materialPicker.title);
            ImGui::Separator();
            ImGui::InputTextWithHint("##MaterialFilter", "Search materials...", materialPicker.filter, sizeof(materialPicker.filter));
            ImGui::Separator();

            std::vector<AssetOption> options;
            LoadMaterialOptions(context, options);
            const std::string filterText = EditorUI::ToLower(std::string(materialPicker.filter));
            for (const auto &option : options) {
                if (!filterText.empty() && EditorUI::ToLower(option.name).find(filterText) == std::string::npos) {
                    continue;
                }
                if (ImGui::Selectable(option.name.c_str())) {
                    if (materialPicker.entityId[0] != 0) {
                        if (materialPicker.usesMeshRenderer) {
                            MCEEditorSetMeshRenderer(context, materialPicker.entityId, materialPicker.meshHandle, option.handle.c_str());
                            MCEEditorSetMaterialComponent(context, materialPicker.entityId, option.handle.c_str());
                        } else {
                            MCEEditorAssignMaterialToEntity(context, materialPicker.entityId, option.handle.c_str());
                        }
                    }
                    materialPicker.open = false;
                    ImGui::CloseCurrentPopup();
                    break;
                }
            }

            if (options.empty()) {
                ImGui::TextDisabled("No material assets found.");
            }

            ImGui::Spacing();
            if (ImGui::Button("Close")) {
                materialPicker.open = false;
                ImGui::CloseCurrentPopup();
            }

            ImGui::EndPopup();
        }
    }

    EditorUI::EndPanel();
}
