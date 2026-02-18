// SceneHierarchyPanel.mm
// Defines the ImGui SceneHierarchy panel rendering and interaction logic.
// Created by Kaden Cringle.

#import "SceneHierarchyPanel.h"

#import "../../ImGui/imgui.h"
#import "PanelState.h"
#import "../Widgets/UIWidgets.h"
#include <string.h>
#include <stdint.h>

extern "C" int32_t MCEEditorGetEntityCount(MCE_CTX);
extern "C" int32_t MCEEditorGetEntityIdAt(MCE_CTX,  int32_t index, char *buffer, int32_t bufferSize);
extern "C" int32_t MCEEditorGetEntityName(MCE_CTX,  const char *entityId, char *buffer, int32_t bufferSize);
extern "C" uint32_t MCEEditorEntityHasComponent(MCE_CTX,  const char *entityId, int32_t componentType);
extern "C" int32_t MCEEditorCreateEntity(MCE_CTX,  const char *name, char *outId, int32_t outIdSize);
extern "C" int32_t MCEEditorCreateMeshEntity(MCE_CTX,  int32_t meshType, char *outId, int32_t outIdSize);
extern "C" int32_t MCEEditorCreateLightEntity(MCE_CTX,  int32_t lightType, char *outId, int32_t outIdSize);
extern "C" int32_t MCEEditorCreateSkyEntity(MCE_CTX,  char *outId, int32_t outIdSize);
extern "C" int32_t MCEEditorCreateCameraEntity(MCE_CTX,  char *outId, int32_t outIdSize);
extern "C" uint32_t MCEEditorSetActiveSky(MCE_CTX,  const char *entityId);
extern "C" void MCEEditorDestroyEntity(MCE_CTX,  const char *entityId);
extern "C" void MCEEditorAssignMaterialToEntity(MCE_CTX,  const char *entityId, const char *materialHandle);
extern "C" int32_t MCEEditorCreateMeshEntityFromHandle(MCE_CTX,  const char *meshHandle, char *outId, int32_t outIdSize);
extern "C" int32_t MCEEditorInstantiatePrefabFromHandle(MCE_CTX,  const char *prefabHandle, char *outId, int32_t outIdSize);
extern "C" uint32_t MCEEditorCreatePrefabFromEntity(MCE_CTX,  const char *entityId, char *outPath, int32_t outPathSize);
extern "C" void MCEEditorSetLastSelectedEntityId(MCE_CTX,  const char *value);
extern "C" int32_t MCEEditorGetAssetCount(MCE_CTX);
extern "C" uint32_t MCEEditorGetAssetAt(MCE_CTX,  int32_t index,
                                        char *handleBuffer, int32_t handleBufferSize,
                                        int32_t *typeOut,
                                        char *pathBuffer, int32_t pathBufferSize,
                                        char *nameBuffer, int32_t nameBufferSize);
extern "C" void *MCEContextGetUIPanelState(MCE_CTX);

namespace {
    using MCEPanelState::SceneHierarchyState;

    SceneHierarchyState &GetSceneHierarchyState(void *context) {
        auto *state = static_cast<MCEPanelState::EditorUIPanelState *>(MCEContextGetUIPanelState(context));
        return state->sceneHierarchy;
    }
}

static void AssignSelection(char *selectedEntityId, size_t selectedEntityIdSize, const char *newId) {
    if (!selectedEntityId || selectedEntityIdSize == 0) { return; }
    if (!newId) {
        selectedEntityId[0] = 0;
        return;
    }
    size_t length = strnlen(newId, selectedEntityIdSize - 1);
    memcpy(selectedEntityId, newId, length);
    selectedEntityId[length] = 0;
}

static void DrawPrefabPicker(void *context, SceneHierarchyState &state, bool *open, char *selectedEntityId, size_t selectedEntityIdSize) {
    if (!open || !*open) { return; }
    ImGui::SetNextWindowSize(ImVec2(420.0f, 320.0f), ImGuiCond_Once);
    if (ImGui::BeginPopupModal("PrefabPicker", open, ImGuiWindowFlags_AlwaysAutoResize)) {
        ImGui::TextUnformatted("Select Prefab");
        ImGui::Separator();
        ImGui::InputTextWithHint("##PrefabFilter", "Search prefabs...", state.prefabFilter, sizeof(state.prefabFilter));
        ImGui::Separator();

        if (ImGui::IsWindowAppearing()) {
            state.selectedPrefabHandle.clear();
        }

        const int32_t count = MCEEditorGetAssetCount(context);
        std::string filterText = EditorUI::ToLower(std::string(state.prefabFilter));
        for (int32_t i = 0; i < count; ++i) {
            char handleBuffer[64] = {0};
            int32_t type = 0;
            char pathBuffer[512] = {0};
            char nameBuffer[128] = {0};
            if (MCEEditorGetAssetAt(context, i, handleBuffer, sizeof(handleBuffer), &type, pathBuffer, sizeof(pathBuffer), nameBuffer, sizeof(nameBuffer)) == 0) {
                continue;
            }
            if (type != 5) { continue; }
            if (handleBuffer[0] == 0) { continue; }
            const char *label = nameBuffer[0] != 0 ? nameBuffer : pathBuffer;
            if (!filterText.empty() && EditorUI::ToLower(label).find(filterText) == std::string::npos) {
                continue;
            }
            const bool isSelected = (state.selectedPrefabHandle == handleBuffer);
            if (ImGui::Selectable(label, isSelected, ImGuiSelectableFlags_DontClosePopups)) {
                state.selectedPrefabHandle = handleBuffer;
            }
        }

        if (count == 0) {
            ImGui::TextDisabled("No prefab assets found.");
        }

        ImGui::Spacing();
        const bool canCreate = !state.selectedPrefabHandle.empty();
        if (!canCreate) {
            ImGui::BeginDisabled();
        }
        if (ImGui::Button("Create")) {
            char createdId[64] = {0};
            if (MCEEditorInstantiatePrefabFromHandle(context, state.selectedPrefabHandle.c_str(), createdId, sizeof(createdId)) > 0) {
                AssignSelection(selectedEntityId, selectedEntityIdSize, createdId);
                MCEEditorSetLastSelectedEntityId(context, createdId);
            }
            *open = false;
            ImGui::CloseCurrentPopup();
        }
        if (!canCreate) {
            ImGui::EndDisabled();
        }
        ImGui::SameLine();
        if (ImGui::Button("Close")) {
            *open = false;
            ImGui::CloseCurrentPopup();
        }
        ImGui::EndPopup();
    }
}

void ImGuiSceneHierarchyPanelDraw(void *context, bool *isOpen, char *selectedEntityId, size_t selectedEntityIdSize) {
    if (!isOpen || !*isOpen) { return; }
    SceneHierarchyState &state = GetSceneHierarchyState(context);
    if (!EditorUI::BeginPanel("Scene Hierarchy", isOpen)) {
        EditorUI::EndPanel();
        return;
    }
    ImGui::PushStyleVar(ImGuiStyleVar_FramePadding, ImVec2(8.0f, 4.0f));
    ImGui::PushStyleVar(ImGuiStyleVar_ItemSpacing, ImVec2(6.0f, 2.0f));
    ImGui::BeginChild("SceneHierarchyScroll", ImVec2(0, 0), false, ImGuiWindowFlags_AlwaysVerticalScrollbar);

    const int32_t entityCount = MCEEditorGetEntityCount(context);
    const float rowHeight = ImGui::GetTextLineHeight() + 10.0f;
    const float rowWidth = ImGui::GetContentRegionAvail().x;
    ImGuiListClipper clipper;
    clipper.Begin(entityCount, rowHeight);
    while (clipper.Step()) {
        for (int32_t i = clipper.DisplayStart; i < clipper.DisplayEnd; ++i) {
            char idBuffer[64] = {0};
            if (MCEEditorGetEntityIdAt(context, i, idBuffer, sizeof(idBuffer)) <= 0) { continue; }
            char nameBuffer[128] = {0};
            if (MCEEditorGetEntityName(context, idBuffer, nameBuffer, sizeof(nameBuffer)) <= 0) {
                strncpy(nameBuffer, idBuffer, sizeof(nameBuffer) - 1);
            }
            bool isSelected = selectedEntityId && selectedEntityId[0] != 0 && strcmp(selectedEntityId, idBuffer) == 0;
            ImGui::PushID(idBuffer);
            ImGui::InvisibleButton("##EntityRow", ImVec2(rowWidth, rowHeight));
            const bool hovered = ImGui::IsItemHovered();
            if (ImGui::IsItemClicked(ImGuiMouseButton_Left)) {
                AssignSelection(selectedEntityId, selectedEntityIdSize, idBuffer);
                MCEEditorSetLastSelectedEntityId(context, idBuffer);
            }

            ImVec2 itemMin = ImGui::GetItemRectMin();
            ImVec2 itemMax = ImGui::GetItemRectMax();
            ImDrawList *drawList = ImGui::GetWindowDrawList();
            if (isSelected) {
                drawList->AddRectFilled(itemMin, itemMax, IM_COL32(120, 95, 150, 80), 4.0f);
                drawList->AddRect(itemMin, itemMax, IM_COL32(155, 120, 190, 160), 4.0f, 0, 1.0f);
            } else if (hovered) {
                drawList->AddRectFilled(itemMin, itemMax, IM_COL32(90, 90, 100, 70), 4.0f);
            }

            const float textPaddingX = 10.0f;
            const float textPaddingY = (rowHeight - ImGui::GetTextLineHeight()) * 0.5f;
            drawList->AddText(ImVec2(itemMin.x + textPaddingX, itemMin.y + textPaddingY),
                              ImGui::GetColorU32(ImGuiCol_Text),
                              nameBuffer);
            if (ImGui::BeginDragDropTarget()) {
                if (const ImGuiPayload* payload = ImGui::AcceptDragDropPayload("MCE_ASSET_MATERIAL")) {
                    const char *payloadText = static_cast<const char *>(payload->Data);
                    MCEEditorAssignMaterialToEntity(context, idBuffer, payloadText);
                }
                if (const ImGuiPayload* payload = ImGui::AcceptDragDropPayload("MCE_ASSET_MODEL")) {
                    const char *payloadText = static_cast<const char *>(payload->Data);
                    char createdId[64] = {0};
                    if (MCEEditorCreateMeshEntityFromHandle(context, payloadText, createdId, sizeof(createdId)) > 0) {
                        AssignSelection(selectedEntityId, selectedEntityIdSize, createdId);
                    }
                }
                if (const ImGuiPayload* payload = ImGui::AcceptDragDropPayload("MCE_ASSET_PREFAB")) {
                    const char *payloadText = static_cast<const char *>(payload->Data);
                    char createdId[64] = {0};
                    if (MCEEditorInstantiatePrefabFromHandle(context, payloadText, createdId, sizeof(createdId)) > 0) {
                        AssignSelection(selectedEntityId, selectedEntityIdSize, createdId);
                        MCEEditorSetLastSelectedEntityId(context, createdId);
                    }
                }
                ImGui::EndDragDropTarget();
            }
            if (ImGui::BeginPopupContextItem()) {
                if (MCEEditorEntityHasComponent(context, idBuffer, 4) != 0) {
                    if (ImGui::MenuItem("Set as Active Sky")) {
                        MCEEditorSetActiveSky(context, idBuffer);
                    }
                    ImGui::Separator();
                }
                if (isSelected) {
                    if (ImGui::MenuItem("Create Prefab from Selected")) {
                        char pathBuffer[512] = {0};
                        MCEEditorCreatePrefabFromEntity(context, idBuffer, pathBuffer, sizeof(pathBuffer));
                    }
                    ImGui::Separator();
                }
                if (ImGui::MenuItem("Delete")) {
                    MCEEditorDestroyEntity(context, idBuffer);
                    if (isSelected) {
                        AssignSelection(selectedEntityId, selectedEntityIdSize, nullptr);
                        MCEEditorSetLastSelectedEntityId(context, "");
                    }
                }
                ImGui::EndPopup();
            }
            ImGui::PopID();
        }
    }

    if (ImGui::BeginPopupContextWindow("SceneHierarchyContext", ImGuiPopupFlags_MouseButtonRight | ImGuiPopupFlags_NoOpenOverItems)) {
        if (ImGui::MenuItem("Create Empty Entity")) {
            char createdId[64] = {0};
            if (MCEEditorCreateEntity(context, "Empty Entity", createdId, sizeof(createdId)) > 0) {
                AssignSelection(selectedEntityId, selectedEntityIdSize, createdId);
                MCEEditorSetLastSelectedEntityId(context, createdId);
            }
        }
        if (ImGui::BeginMenu("Create 3D")) {
            if (ImGui::MenuItem("Cube")) {
                char createdId[64] = {0};
                if (MCEEditorCreateMeshEntity(context, 0, createdId, sizeof(createdId)) > 0) {
                    AssignSelection(selectedEntityId, selectedEntityIdSize, createdId);
                    MCEEditorSetLastSelectedEntityId(context, createdId);
                }
            }
            if (ImGui::MenuItem("Sphere")) {
                char createdId[64] = {0};
                if (MCEEditorCreateMeshEntity(context, 1, createdId, sizeof(createdId)) > 0) {
                    AssignSelection(selectedEntityId, selectedEntityIdSize, createdId);
                    MCEEditorSetLastSelectedEntityId(context, createdId);
                }
            }
            if (ImGui::MenuItem("Plane")) {
                char createdId[64] = {0};
                if (MCEEditorCreateMeshEntity(context, 2, createdId, sizeof(createdId)) > 0) {
                    AssignSelection(selectedEntityId, selectedEntityIdSize, createdId);
                    MCEEditorSetLastSelectedEntityId(context, createdId);
                }
            }
            ImGui::EndMenu();
        }
        if (ImGui::MenuItem("Create Camera")) {
            char createdId[64] = {0};
            if (MCEEditorCreateCameraEntity(context, createdId, sizeof(createdId)) > 0) {
                AssignSelection(selectedEntityId, selectedEntityIdSize, createdId);
                MCEEditorSetLastSelectedEntityId(context, createdId);
            }
        }
        if (ImGui::MenuItem("Create Prefab...")) {
            state.showPrefabPicker = true;
            state.requestPrefabPickerOpen = true;
        }
        if (ImGui::BeginMenu("Create Light")) {
            if (ImGui::MenuItem("Point Light")) {
                char createdId[64] = {0};
                if (MCEEditorCreateLightEntity(context, 0, createdId, sizeof(createdId)) > 0) {
                    AssignSelection(selectedEntityId, selectedEntityIdSize, createdId);
                    MCEEditorSetLastSelectedEntityId(context, createdId);
                }
            }
            if (ImGui::MenuItem("Spot Light")) {
                char createdId[64] = {0};
                if (MCEEditorCreateLightEntity(context, 1, createdId, sizeof(createdId)) > 0) {
                    AssignSelection(selectedEntityId, selectedEntityIdSize, createdId);
                    MCEEditorSetLastSelectedEntityId(context, createdId);
                }
            }
            if (ImGui::MenuItem("Directional Light")) {
                char createdId[64] = {0};
                if (MCEEditorCreateLightEntity(context, 2, createdId, sizeof(createdId)) > 0) {
                    AssignSelection(selectedEntityId, selectedEntityIdSize, createdId);
                    MCEEditorSetLastSelectedEntityId(context, createdId);
                }
            }
            ImGui::EndMenu();
        }
        if (ImGui::MenuItem("Create Sky")) {
            char createdId[64] = {0};
            if (MCEEditorCreateSkyEntity(context, createdId, sizeof(createdId)) > 0) {
                AssignSelection(selectedEntityId, selectedEntityIdSize, createdId);
                MCEEditorSetLastSelectedEntityId(context, createdId);
            }
        }
        if (selectedEntityId && selectedEntityId[0] != 0) {
            if (ImGui::MenuItem("Delete Selected")) {
                MCEEditorDestroyEntity(context, selectedEntityId);
                AssignSelection(selectedEntityId, selectedEntityIdSize, nullptr);
                MCEEditorSetLastSelectedEntityId(context, "");
            }
        }
        ImGui::EndPopup();
    }

    if (state.requestPrefabPickerOpen) {
        ImGui::OpenPopup("PrefabPicker");
        state.requestPrefabPickerOpen = false;
    }
    DrawPrefabPicker(context, state, &state.showPrefabPicker, selectedEntityId, selectedEntityIdSize);

    ImGui::EndChild();
    ImGui::PopStyleVar(2);
    EditorUI::EndPanel();
}
