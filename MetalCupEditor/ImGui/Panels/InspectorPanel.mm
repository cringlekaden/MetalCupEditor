#import "InspectorPanel.h"

#import "imgui.h"
#import "EditorUIHelpers.h"
#import "EditorUIConstants.h"
#include <string.h>
#include <stdint.h>
#include <string>

extern "C" uint32_t MCEEditorEntityHasComponent(const char *entityId, int32_t componentType);
extern "C" uint32_t MCEEditorAddComponent(const char *entityId, int32_t componentType);
extern "C" uint32_t MCEEditorRemoveComponent(const char *entityId, int32_t componentType);
extern "C" uint32_t MCEEditorEntityExists(const char *entityId);
extern "C" int32_t MCEEditorSkyEntityCount(void);
extern "C" int32_t MCEEditorGetActiveSkyId(char *buffer, int32_t bufferSize);
extern "C" uint32_t MCEEditorSetActiveSky(const char *entityId);

extern "C" int32_t MCEEditorGetEntityName(const char *entityId, char *buffer, int32_t bufferSize);
extern "C" void MCEEditorSetEntityName(const char *entityId, const char *name);

extern "C" uint32_t MCEEditorGetTransform(const char *entityId, float *px, float *py, float *pz,
                                          float *rx, float *ry, float *rz,
                                          float *sx, float *sy, float *sz);
extern "C" void MCEEditorSetTransform(const char *entityId, float px, float py, float pz,
                                      float rx, float ry, float rz,
                                      float sx, float sy, float sz);

extern "C" uint32_t MCEEditorGetMeshRenderer(const char *entityId, char *meshHandle, int32_t meshHandleSize,
                                             char *materialHandle, int32_t materialHandleSize);
extern "C" void MCEEditorSetMeshRenderer(const char *entityId, const char *meshHandle, const char *materialHandle);
extern "C" void MCEEditorAssignMaterialToEntity(const char *entityId, const char *materialHandle);
extern "C" uint32_t MCEEditorGetMaterialComponent(const char *entityId, char *materialHandle, int32_t materialHandleSize);
extern "C" void MCEEditorSetMaterialComponent(const char *entityId, const char *materialHandle);

extern "C" uint32_t MCEEditorGetLight(const char *entityId, int32_t *type, float *colorX, float *colorY, float *colorZ,
                                      float *brightness, float *range, float *innerCos, float *outerCos,
                                      float *dirX, float *dirY, float *dirZ);
extern "C" void MCEEditorSetLight(const char *entityId, int32_t type, float colorX, float colorY, float colorZ,
                                  float brightness, float range, float innerCos, float outerCos,
                                  float dirX, float dirY, float dirZ);

extern "C" uint32_t MCEEditorGetSkyLight(const char *entityId, int32_t *mode, uint32_t *enabled,
                                         float *intensity, float *tintX, float *tintY, float *tintZ,
                                         float *turbidity, float *azimuth, float *elevation,
                                         char *hdriHandle, int32_t hdriHandleSize);
extern "C" void MCEEditorSetSkyLight(const char *entityId, int32_t mode, uint32_t enabled,
                                     float intensity, float tintX, float tintY, float tintZ,
                                     float turbidity, float azimuth, float elevation,
                                     const char *hdriHandle);

extern "C" uint32_t MCEEditorGetMaterialAsset(
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
extern "C" uint32_t MCEEditorSetMaterialAsset(
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
extern "C" uint32_t MCEEditorGetAssetDisplayName(const char *handle, char *buffer, int32_t bufferSize);
extern "C" uint32_t MCEEditorGetSelectedMaterial(char *buffer, int32_t bufferSize);
extern "C" uint32_t MCEEditorCreateMaterial(const char *relativePath, const char *name, char *outHandle, int32_t outHandleSize);
extern "C" void MCEEditorSetSelectedMaterial(const char *handle);
extern "C" void MCEEditorOpenMaterialEditor(const char *handle);
extern "C" uint32_t MCEEditorConsumeOpenMaterialEditor(char *buffer, int32_t bufferSize);

enum ComponentType : int32_t {
    ComponentName = 0,
    ComponentTransform = 1,
    ComponentMeshRenderer = 2,
    ComponentLight = 3,
    ComponentSkyLight = 4,
    ComponentMaterial = 5
};

namespace {
    constexpr float kDegToRad = 0.0174532925f;
    constexpr float kRadToDeg = 57.2957795f;

    struct MaterialEditorState {
        char name[128] = {0};
        int32_t version = 1;
        float baseColor[3] = {1.0f, 1.0f, 1.0f};
        float metallic = 1.0f;
        float roughness = 1.0f;
        float ao = 1.0f;
        float emissive[3] = {0.0f, 0.0f, 0.0f};
        float emissiveIntensity = 1.0f;
        int32_t alphaMode = 0;
        float alphaCutoff = 0.5f;
        bool doubleSided = false;
        bool unlit = false;
        char baseColorHandle[64] = {0};
        char normalHandle[64] = {0};
        char metalRoughnessHandle[64] = {0};
        char metallicHandle[64] = {0};
        char roughnessHandle[64] = {0};
        char aoHandle[64] = {0};
        char emissiveHandle[64] = {0};
    };

    bool LoadMaterialState(const char *materialHandle, MaterialEditorState &state) {
        if (!materialHandle || materialHandle[0] == 0) { return false; }
        uint32_t doubleSided = 0;
        uint32_t unlit = 0;
        return MCEEditorGetMaterialAsset(
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
            state.emissiveHandle, sizeof(state.emissiveHandle)) != 0
            ? (state.doubleSided = (doubleSided != 0), state.unlit = (unlit != 0), true)
            : false;
    }

    void GetAssetName(const char *handle, char *buffer, size_t bufferSize) {
        if (!handle || handle[0] == 0) {
            strncpy(buffer, "None", bufferSize - 1);
            buffer[bufferSize - 1] = 0;
            return;
        }
        if (MCEEditorGetAssetDisplayName(handle, buffer, static_cast<int32_t>(bufferSize)) == 0) {
            strncpy(buffer, handle, bufferSize - 1);
            buffer[bufferSize - 1] = 0;
        }
    }

    bool DrawTextureSlotRow(const char *label, char *handleBuffer, size_t handleBufferSize, const char *payloadType,
                            char **assignTarget, bool &assignPopupOpen) {
        bool changed = false;
        ImGui::TableNextRow();
        ImGui::TableSetColumnIndex(0);
        ImGui::TextUnformatted(label);
        ImGui::TableSetColumnIndex(1);

        ImGui::PushID(label);
        char displayName[128] = {0};
        GetAssetName(handleBuffer, displayName, sizeof(displayName));
        ImGui::Selectable(displayName, false);
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
        if (ImGui::Button((std::string("Assign##") + label).c_str())) {
            *assignTarget = handleBuffer;
            assignPopupOpen = true;
        }
        ImGui::TableSetColumnIndex(3);
        if (ImGui::Button((std::string("Clear##") + label).c_str())) {
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

    struct MaterialPopupState {
        char handle[64] = {0};
        MaterialEditorState state;
        bool open = false;
        bool dirty = false;
        std::string title;
    };

    MaterialPopupState &GetMaterialPopupState() {
        static MaterialPopupState state;
        return state;
    }

    void OpenMaterialPopup(const char *materialHandle) {
        if (!materialHandle || materialHandle[0] == 0) { return; }
        auto &popup = GetMaterialPopupState();
        memset(&popup.state, 0, sizeof(popup.state));
        if (!LoadMaterialState(materialHandle, popup.state)) { return; }
        strncpy(popup.handle, materialHandle, sizeof(popup.handle) - 1);
        popup.handle[sizeof(popup.handle) - 1] = 0;
        popup.dirty = false;
        popup.open = true;
        popup.title = std::string("Material: ") + (popup.state.name[0] != 0 ? popup.state.name : "Material");
        ImGui::OpenPopup(popup.title.c_str());
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

        ImGui::TextUnformatted("Textures");
        ImGui::Separator();
        static char assignBuffer[64] = {0};
        static char *assignTarget = nullptr;
        static bool assignPopupOpen = false;

        if (ImGui::BeginTable("MaterialTextures", 4, ImGuiTableFlags_BordersInnerH | ImGuiTableFlags_RowBg)) {
            ImGui::TableSetupColumn("Slot", ImGuiTableColumnFlags_WidthFixed, 120.0f);
            ImGui::TableSetupColumn("Texture", ImGuiTableColumnFlags_WidthStretch);
            ImGui::TableSetupColumn("Assign", ImGuiTableColumnFlags_WidthFixed, 70.0f);
            ImGui::TableSetupColumn("Clear", ImGuiTableColumnFlags_WidthFixed, 60.0f);
            ImGui::TableHeadersRow();

            dirty |= DrawTextureSlotRow("Base Color", state.baseColorHandle, sizeof(state.baseColorHandle), "MCE_ASSET_TEXTURE", &assignTarget, assignPopupOpen);
            dirty |= DrawTextureSlotRow("Normal", state.normalHandle, sizeof(state.normalHandle), "MCE_ASSET_TEXTURE", &assignTarget, assignPopupOpen);
            dirty |= DrawTextureSlotRow("Metal/Rough", state.metalRoughnessHandle, sizeof(state.metalRoughnessHandle), "MCE_ASSET_TEXTURE", &assignTarget, assignPopupOpen);
            dirty |= DrawTextureSlotRow("Metallic", state.metallicHandle, sizeof(state.metallicHandle), "MCE_ASSET_TEXTURE", &assignTarget, assignPopupOpen);
            dirty |= DrawTextureSlotRow("Roughness", state.roughnessHandle, sizeof(state.roughnessHandle), "MCE_ASSET_TEXTURE", &assignTarget, assignPopupOpen);
            dirty |= DrawTextureSlotRow("AO", state.aoHandle, sizeof(state.aoHandle), "MCE_ASSET_TEXTURE", &assignTarget, assignPopupOpen);
            dirty |= DrawTextureSlotRow("Emissive", state.emissiveHandle, sizeof(state.emissiveHandle), "MCE_ASSET_TEXTURE", &assignTarget, assignPopupOpen);

            ImGui::EndTable();
        }

        if (assignPopupOpen) {
            if (assignTarget) {
                strncpy(assignBuffer, assignTarget, sizeof(assignBuffer) - 1);
            }
            ImGui::OpenPopup("Assign Texture");
            assignPopupOpen = false;
        }
        if (ImGui::BeginPopupModal("Assign Texture", nullptr, ImGuiWindowFlags_AlwaysAutoResize)) {
            ImGui::InputText("Handle", assignBuffer, sizeof(assignBuffer));
            if (ImGui::Button("Apply")) {
                if (assignTarget) {
                    strncpy(assignTarget, assignBuffer, 63);
                    assignTarget[63] = 0;
                    dirty = true;
                }
                ImGui::CloseCurrentPopup();
            }
            ImGui::SameLine();
            if (ImGui::Button("Cancel")) {
                ImGui::CloseCurrentPopup();
            }
            ImGui::EndPopup();
        }

        const bool hasMetalRough = state.metalRoughnessHandle[0] != 0;
        const bool hasMetallic = state.metallicHandle[0] != 0;
        const bool hasRoughness = state.roughnessHandle[0] != 0;
        if (hasMetalRough && (hasMetallic || hasRoughness)) {
            ImGui::TextColored(ImVec4(0.95f, 0.7f, 0.2f, 1.0f), "Warning: Metal/Roughness conflicts with Metallic/Roughness maps.");
        }

        ImGui::TextUnformatted("Derived Flags");
        ImGui::Separator();
        ImGui::TextDisabled("Has BaseColor Map: %s", state.baseColorHandle[0] != 0 ? "Yes" : "No");
        ImGui::TextDisabled("Has Normal Map: %s", state.normalHandle[0] != 0 ? "Yes" : "No");
        ImGui::TextDisabled("Has Metal/Roughness: %s", state.metalRoughnessHandle[0] != 0 ? "Yes" : "No");
        ImGui::TextDisabled("Has Metallic Map: %s", state.metallicHandle[0] != 0 ? "Yes" : "No");
        ImGui::TextDisabled("Has Roughness Map: %s", state.roughnessHandle[0] != 0 ? "Yes" : "No");
        ImGui::TextDisabled("Has AO Map: %s", state.aoHandle[0] != 0 ? "Yes" : "No");
        ImGui::TextDisabled("Has Emissive Map: %s", state.emissiveHandle[0] != 0 ? "Yes" : "No");

        return dirty;
    }

    struct PendingSkyState {
        char entityId[64] = {0};
        bool hasPending = false;
        bool autoApply = false;
        int32_t mode = 0;
        uint32_t enabled = 1;
        float intensity = 1.0f;
        float tintX = 1.0f;
        float tintY = 1.0f;
        float tintZ = 1.0f;
        float turbidity = 2.0f;
        float azimuth = 0.0f;
        float elevation = 30.0f;
        char hdriHandle[64] = {0};
    };

    PendingSkyState &GetPendingSkyState() {
        static PendingSkyState state;
        return state;
    }
}

void ImGuiInspectorPanelDraw(bool *isOpen, const char *selectedEntityId) {
    if (!isOpen || !*isOpen) { return; }
    ImGui::Begin("Inspector", isOpen);
    ImGui::BeginChild("InspectorScroll", ImVec2(0, 0), false, ImGuiWindowFlags_AlwaysVerticalScrollbar);

    const bool hasEntityId = selectedEntityId && selectedEntityId[0] != 0;
    const bool hasValidEntity = hasEntityId && (MCEEditorEntityExists(selectedEntityId) != 0);
    char selectedMaterial[64] = {0};
    const bool hasSelectedMaterial = MCEEditorGetSelectedMaterial(selectedMaterial, sizeof(selectedMaterial)) != 0;

    if (!hasValidEntity) {
        if (!hasSelectedMaterial) {
            ImGui::TextUnformatted(hasEntityId ? "Selection no longer exists." : "No entity selected.");
            ImGui::EndChild();
            ImGui::End();
            return;
        }
    }

    ImGui::PushStyleVar(ImGuiStyleVar_FramePadding, ImVec2(6, 4));

    char pendingMaterialHandle[64] = {0};
    if (MCEEditorConsumeOpenMaterialEditor(pendingMaterialHandle, sizeof(pendingMaterialHandle)) != 0) {
        OpenMaterialPopup(pendingMaterialHandle);
    }

    if (hasValidEntity) {
        char nameBuffer[256] = {0};
        if (MCEEditorGetEntityName(selectedEntityId, nameBuffer, sizeof(nameBuffer)) <= 0) {
            strncpy(nameBuffer, "Entity", sizeof(nameBuffer) - 1);
        }
        if (ImGui::InputText("Name", nameBuffer, sizeof(nameBuffer))) {
            MCEEditorSetEntityName(selectedEntityId, nameBuffer);
        }
        ImGui::Spacing();
    }

    if (hasValidEntity && MCEEditorEntityHasComponent(selectedEntityId, ComponentTransform) != 0) {
        bool transformOpen = ImGui::CollapsingHeader("Transform", ImGuiTreeNodeFlags_DefaultOpen);
        if (ImGui::BeginPopupContextItem("TransformContext")) {
            if (ImGui::MenuItem("Reset")) {
                MCEEditorSetTransform(selectedEntityId, 0, 0, 0, 0, 0, 0, 1, 1, 1);
            }
            if (ImGui::MenuItem("Remove")) {
                MCEEditorRemoveComponent(selectedEntityId, ComponentTransform);
            }
            ImGui::EndPopup();
        }
        if (transformOpen) {
            float px = 0, py = 0, pz = 0;
            float rx = 0, ry = 0, rz = 0;
            float sx = 1, sy = 1, sz = 1;
            if (MCEEditorGetTransform(selectedEntityId, &px, &py, &pz, &rx, &ry, &rz, &sx, &sy, &sz) != 0) {
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
                    MCEEditorSetTransform(selectedEntityId,
                                          position[0], position[1], position[2],
                                          rotationRad[0], rotationRad[1], rotationRad[2],
                                          scale[0], scale[1], scale[2]);
                }
            }
        }
    }

    const bool hasMeshRenderer = hasValidEntity && MCEEditorEntityHasComponent(selectedEntityId, ComponentMeshRenderer) != 0;
    if (hasMeshRenderer) {
        bool meshOpen = ImGui::CollapsingHeader("Mesh Renderer", ImGuiTreeNodeFlags_DefaultOpen);
        if (ImGui::BeginPopupContextItem("MeshRendererContext")) {
            if (ImGui::MenuItem("Reset")) {
                const char *empty = "";
                MCEEditorSetMeshRenderer(selectedEntityId, empty, empty);
                MCEEditorSetMaterialComponent(selectedEntityId, empty);
            }
            if (ImGui::MenuItem("Remove")) {
                MCEEditorRemoveComponent(selectedEntityId, ComponentMeshRenderer);
            }
            ImGui::EndPopup();
        }
        if (meshOpen) {
            char meshHandle[64] = {0};
            char materialHandle[64] = {0};
            MCEEditorGetMeshRenderer(selectedEntityId, meshHandle, sizeof(meshHandle), materialHandle, sizeof(materialHandle));

            char meshName[128] = {0};
            GetAssetName(meshHandle, meshName, sizeof(meshName));
            char materialName[128] = {0};
            GetAssetName(materialHandle, materialName, sizeof(materialName));
            if (EditorUI::BeginPropertyTable("MeshRendererProps")) {
                EditorUI::PropertyLabel("Mesh");
                ImGui::TextUnformatted(meshName);
                EditorUI::PropertyLabel("Material");
                ImGui::TextUnformatted(materialName);
                EditorUI::EndPropertyTable();
            }

            if (materialHandle[0] != 0) {
                if (ImGui::Button("Edit Material")) {
                    MCEEditorOpenMaterialEditor(materialHandle);
                }
                ImGui::SameLine();
                if (ImGui::Button("Clear Material")) {
                    materialHandle[0] = 0;
                    MCEEditorSetMeshRenderer(selectedEntityId, meshHandle, materialHandle);
                    MCEEditorSetMaterialComponent(selectedEntityId, materialHandle);
                }
            }

            if (ImGui::BeginDragDropTarget()) {
                if (const ImGuiPayload* payload = ImGui::AcceptDragDropPayload("MCE_ASSET_MATERIAL")) {
                    const char *payloadText = static_cast<const char *>(payload->Data);
                    strncpy(materialHandle, payloadText, sizeof(materialHandle) - 1);
                    MCEEditorSetMeshRenderer(selectedEntityId, meshHandle, materialHandle);
                    MCEEditorSetMaterialComponent(selectedEntityId, materialHandle);
                }
                ImGui::EndDragDropTarget();
            }

            if (materialHandle[0] == 0) {
                if (ImGui::Button("Create + Assign New Material")) {
                    char outHandle[64] = {0};
                    MCEEditorCreateMaterial("Materials", "NewMaterial", outHandle, sizeof(outHandle));
                    if (outHandle[0] != 0) {
                        MCEEditorSetMeshRenderer(selectedEntityId, meshHandle, outHandle);
                        MCEEditorSetMaterialComponent(selectedEntityId, outHandle);
                        MCEEditorSetSelectedMaterial(outHandle);
                    }
                }
            } else {
                if (ImGui::Button("Select Material")) {
                    MCEEditorSetSelectedMaterial(materialHandle);
                }
            }

            if (ImGui::Button("Remove Mesh Renderer")) {
                MCEEditorRemoveComponent(selectedEntityId, ComponentMeshRenderer);
            }
        }
    }

    bool hasMaterialComponent = hasValidEntity && (MCEEditorEntityHasComponent(selectedEntityId, ComponentMaterial) != 0);
    const bool showMaterialSection = !hasMeshRenderer && (hasSelectedMaterial || hasMaterialComponent);
    if (showMaterialSection) {
        char materialHandle[64] = {0};
        if (hasMaterialComponent) {
            MCEEditorGetMaterialComponent(selectedEntityId, materialHandle, sizeof(materialHandle));
        } else if (hasValidEntity) {
            char meshHandle[64] = {0};
            MCEEditorGetMeshRenderer(selectedEntityId, meshHandle, sizeof(meshHandle), materialHandle, sizeof(materialHandle));
        } else if (hasSelectedMaterial) {
            strncpy(materialHandle, selectedMaterial, sizeof(materialHandle) - 1);
        }

        bool materialOpen = ImGui::CollapsingHeader("Material", ImGuiTreeNodeFlags_DefaultOpen);
        if (ImGui::BeginPopupContextItem("MaterialContext")) {
            if (hasValidEntity && ImGui::MenuItem("Clear Material")) {
                const char *empty = "";
                MCEEditorSetMeshRenderer(selectedEntityId, empty, empty);
                MCEEditorSetMaterialComponent(selectedEntityId, empty);
            }
            if (hasValidEntity && ImGui::MenuItem("Remove Component")) {
                MCEEditorRemoveComponent(selectedEntityId, ComponentMaterial);
            }
            ImGui::EndPopup();
        }
        if (materialOpen) {
            if (materialHandle[0] == 0) {
                ImGui::TextUnformatted("Assign a material asset.");
                if (hasValidEntity && ImGui::BeginDragDropTarget()) {
                    if (const ImGuiPayload* payload = ImGui::AcceptDragDropPayload("MCE_ASSET_MATERIAL")) {
                        const char *payloadText = static_cast<const char *>(payload->Data);
                        strncpy(materialHandle, payloadText, sizeof(materialHandle) - 1);
                        MCEEditorAssignMaterialToEntity(selectedEntityId, materialHandle);
                    }
                    ImGui::EndDragDropTarget();
                }
            } else {
                char materialName[128] = {0};
                GetAssetName(materialHandle, materialName, sizeof(materialName));
                if (EditorUI::BeginPropertyTable("MaterialSelection")) {
                    EditorUI::PropertyLabel("Material");
                    ImGui::TextUnformatted(materialName);
                    EditorUI::EndPropertyTable();
                }
                if (ImGui::Button("Edit Material")) {
                    MCEEditorOpenMaterialEditor(materialHandle);
                }
            }
        }
    }

    if (hasValidEntity && MCEEditorEntityHasComponent(selectedEntityId, ComponentLight) != 0) {
        bool lightOpen = ImGui::CollapsingHeader("Light", ImGuiTreeNodeFlags_DefaultOpen);
        if (ImGui::BeginPopupContextItem("LightContext")) {
            if (ImGui::MenuItem("Reset")) {
                MCEEditorSetLight(selectedEntityId, 0, 1.0f, 1.0f, 1.0f, 1.0f, 0.0f, 0.95f, 0.9f, 0.0f, -1.0f, 0.0f);
            }
            if (ImGui::MenuItem("Remove")) {
                MCEEditorRemoveComponent(selectedEntityId, ComponentLight);
            }
            ImGui::EndPopup();
        }
        if (lightOpen) {
            int32_t type = 0;
            float colorX = 1, colorY = 1, colorZ = 1;
            float brightness = 1, range = 0, innerCos = 0.95f, outerCos = 0.9f;
            float dirX = 0, dirY = -1, dirZ = 0;
            if (MCEEditorGetLight(selectedEntityId, &type, &colorX, &colorY, &colorZ, &brightness, &range, &innerCos, &outerCos, &dirX, &dirY, &dirZ) != 0) {
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
                    EditorUI::EndPropertyTable();
                }
                if (dirty) {
                    MCEEditorSetLight(selectedEntityId, type, colorX, colorY, colorZ, brightness, range, innerCos, outerCos, dirX, dirY, dirZ);
                }
            }
            if (ImGui::Button("Remove Light")) {
                MCEEditorRemoveComponent(selectedEntityId, ComponentLight);
            }
        }
    }

    if (hasValidEntity && MCEEditorEntityHasComponent(selectedEntityId, ComponentSkyLight) != 0) {
        bool skyOpen = ImGui::CollapsingHeader("Sky", ImGuiTreeNodeFlags_DefaultOpen);
        if (ImGui::BeginPopupContextItem("SkyContext")) {
            if (ImGui::MenuItem("Reset")) {
                const char *empty = "";
                MCEEditorSetSkyLight(selectedEntityId, 0, 1, 1.0f, 1.0f, 1.0f, 1.0f, 2.0f, 0.0f, 30.0f, empty);
            }
            if (ImGui::MenuItem("Remove")) {
                MCEEditorRemoveComponent(selectedEntityId, ComponentSkyLight);
            }
            ImGui::EndPopup();
        }
        if (skyOpen) {
            int32_t skyCount = MCEEditorSkyEntityCount();
            if (skyCount > 1) {
                ImGui::TextColored(ImVec4(1.0f, 0.75f, 0.2f, 1.0f), "Warning: multiple Sky entities exist. Only one is active.");
            }
            char activeSky[64] = {0};
            bool isActive = (MCEEditorGetActiveSkyId(activeSky, sizeof(activeSky)) > 0) && (strcmp(activeSky, selectedEntityId) == 0);
            ImGui::Text("Active: %s", isActive ? "Yes" : "No");
            if (!isActive) {
                if (ImGui::Button("Set as Active Sky")) {
                    MCEEditorSetActiveSky(selectedEntityId);
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
            if (MCEEditorGetSkyLight(selectedEntityId, &mode, &enabled, &intensity, &tintX, &tintY, &tintZ, &turbidity, &azimuth, &elevation, hdriHandle, sizeof(hdriHandle)) != 0) {
                const char* modes[] = {"HDRI", "Procedural"};
                bool enabledBool = enabled != 0;
                PendingSkyState &pending = GetPendingSkyState();
                if (strncmp(pending.entityId, selectedEntityId, sizeof(pending.entityId)) != 0) {
                    memset(&pending, 0, sizeof(pending));
                    strncpy(pending.entityId, selectedEntityId, sizeof(pending.entityId) - 1);
                    pending.autoApply = false;
                }

                int32_t editMode = pending.hasPending ? pending.mode : mode;
                uint32_t editEnabled = pending.hasPending ? pending.enabled : enabled;
                float editIntensity = pending.hasPending ? pending.intensity : intensity;
                float editTintX = pending.hasPending ? pending.tintX : tintX;
                float editTintY = pending.hasPending ? pending.tintY : tintY;
                float editTintZ = pending.hasPending ? pending.tintZ : tintZ;
                float editTurbidity = pending.hasPending ? pending.turbidity : turbidity;
                float editAzimuth = pending.hasPending ? pending.azimuth : azimuth;
                float editElevation = pending.hasPending ? pending.elevation : elevation;
                char editHdriHandle[64] = {0};
                if (pending.hasPending) {
                    strncpy(editHdriHandle, pending.hdriHandle, sizeof(editHdriHandle) - 1);
                } else {
                    strncpy(editHdriHandle, hdriHandle, sizeof(editHdriHandle) - 1);
                }

                bool dirty = false;
                if (EditorUI::BeginPropertyTable("SkyProps")) {
                    if (EditorUI::PropertyBool("Enabled", &enabledBool)) {
                        editEnabled = enabledBool ? 1 : 0;
                        dirty = true;
                    }
                    dirty |= EditorUI::PropertyCombo("Mode", &editMode, modes, IM_ARRAYSIZE(modes));
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
                        dirty |= EditorUI::PropertyFloat("Turbidity",
                                                         &editTurbidity,
                                                         EditorUIConstants::kSkyTurbidityStep,
                                                         EditorUIConstants::kSkyTurbidityMin,
                                                         EditorUIConstants::kSkyTurbidityMax,
                                                         "%.2f",
                                                         true,
                                                         true,
                                                         EditorUIConstants::kDefaultSkyTurbidity);
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
                    } else {
                        EditorUI::PropertyLabel("HDRI Handle");
                        dirty |= ImGui::InputText("##HDRIHandle", editHdriHandle, sizeof(editHdriHandle));
                    }
                    EditorUI::EndPropertyTable();
                }
                if (dirty) {
                    if (editMode == 1 && !pending.autoApply) {
                        pending.hasPending = true;
                        pending.mode = editMode;
                        pending.enabled = editEnabled;
                        pending.intensity = editIntensity;
                        pending.tintX = editTintX;
                        pending.tintY = editTintY;
                        pending.tintZ = editTintZ;
                        pending.turbidity = editTurbidity;
                        pending.azimuth = editAzimuth;
                        pending.elevation = editElevation;
                        strncpy(pending.hdriHandle, editHdriHandle, sizeof(pending.hdriHandle) - 1);
                    } else {
                        pending.hasPending = false;
                        MCEEditorSetSkyLight(selectedEntityId,
                                             editMode,
                                             editEnabled,
                                             editIntensity,
                                             editTintX,
                                             editTintY,
                                             editTintZ,
                                             editTurbidity,
                                             editAzimuth,
                                             editElevation,
                                             editHdriHandle);
                    }
                }

                if (editMode == 1) {
                    bool autoApply = pending.autoApply;
                    if (ImGui::Checkbox("Auto-Apply", &autoApply)) {
                        pending.autoApply = autoApply;
                        if (pending.autoApply && pending.hasPending) {
                            MCEEditorSetSkyLight(selectedEntityId,
                                                 pending.mode,
                                                 pending.enabled,
                                                 pending.intensity,
                                                 pending.tintX,
                                                 pending.tintY,
                                                 pending.tintZ,
                                                 pending.turbidity,
                                                 pending.azimuth,
                                                 pending.elevation,
                                                 pending.hdriHandle);
                            pending.hasPending = false;
                        }
                    }
                    if (pending.hasPending) {
                        ImGui::SameLine();
                        if (ImGui::Button("Apply Sky Changes (Rebuild IBL)")) {
                            MCEEditorSetSkyLight(selectedEntityId,
                                                 pending.mode,
                                                 pending.enabled,
                                                 pending.intensity,
                                                 pending.tintX,
                                                 pending.tintY,
                                                 pending.tintZ,
                                                 pending.turbidity,
                                                 pending.azimuth,
                                                 pending.elevation,
                                                 pending.hdriHandle);
                            pending.hasPending = false;
                        }
                    }
                }
            }
            if (ImGui::Button("Remove Sky")) {
                MCEEditorRemoveComponent(selectedEntityId, ComponentSkyLight);
            }
        }
    }

    if (hasValidEntity && ImGui::Button("Add Component")) {
        ImGui::OpenPopup("AddComponentPopup");
    }
    if (ImGui::BeginPopup("AddComponentPopup")) {
        if (MCEEditorEntityHasComponent(selectedEntityId, ComponentMeshRenderer) == 0) {
            if (ImGui::MenuItem("Mesh Renderer")) {
                MCEEditorAddComponent(selectedEntityId, ComponentMeshRenderer);
            }
        }
        if (MCEEditorEntityHasComponent(selectedEntityId, ComponentMaterial) == 0) {
            if (ImGui::MenuItem("Material")) {
                MCEEditorAddComponent(selectedEntityId, ComponentMaterial);
            }
        }
        if (MCEEditorEntityHasComponent(selectedEntityId, ComponentLight) == 0) {
            if (ImGui::MenuItem("Light")) {
                MCEEditorAddComponent(selectedEntityId, ComponentLight);
            }
        }
        if (MCEEditorEntityHasComponent(selectedEntityId, ComponentSkyLight) == 0) {
            if (ImGui::MenuItem("Sky Light")) {
                MCEEditorAddComponent(selectedEntityId, ComponentSkyLight);
            }
        }
        ImGui::EndPopup();
    }

    MaterialPopupState &popup = GetMaterialPopupState();
    if (popup.open) {
        if (ImGui::BeginPopupModal(popup.title.c_str(), &popup.open, ImGuiWindowFlags_AlwaysAutoResize)) {
            const bool changed = DrawMaterialEditorContents(popup.state);
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
    ImGui::End();
}
