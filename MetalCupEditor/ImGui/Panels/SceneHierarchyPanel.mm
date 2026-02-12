#import "SceneHierarchyPanel.h"

#import "imgui.h"
#include <string.h>
#include <stdint.h>

extern "C" int32_t MCEEditorGetEntityCount(void);
extern "C" int32_t MCEEditorGetEntityIdAt(int32_t index, char *buffer, int32_t bufferSize);
extern "C" int32_t MCEEditorGetEntityName(const char *entityId, char *buffer, int32_t bufferSize);
extern "C" uint32_t MCEEditorEntityHasComponent(const char *entityId, int32_t componentType);
extern "C" int32_t MCEEditorCreateEntity(const char *name, char *outId, int32_t outIdSize);
extern "C" int32_t MCEEditorCreateMeshEntity(int32_t meshType, char *outId, int32_t outIdSize);
extern "C" int32_t MCEEditorCreateLightEntity(int32_t lightType, char *outId, int32_t outIdSize);
extern "C" int32_t MCEEditorCreateSkyEntity(char *outId, int32_t outIdSize);
extern "C" uint32_t MCEEditorSetActiveSky(const char *entityId);
extern "C" void MCEEditorLogSelection(const char *entityId);
extern "C" void MCEEditorDestroyEntity(const char *entityId);
extern "C" void MCEEditorAssignMaterialToEntity(const char *entityId, const char *materialHandle);
extern "C" int32_t MCEEditorCreateMeshEntityFromHandle(const char *meshHandle, char *outId, int32_t outIdSize);

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

void ImGuiSceneHierarchyPanelDraw(bool *isOpen, char *selectedEntityId, size_t selectedEntityIdSize) {
    if (!isOpen || !*isOpen) { return; }
    ImGui::Begin("Scene Hierarchy", isOpen);
    ImGui::BeginChild("SceneHierarchyScroll", ImVec2(0, 0), false, ImGuiWindowFlags_AlwaysVerticalScrollbar);

    int32_t entityCount = MCEEditorGetEntityCount();
    for (int32_t i = 0; i < entityCount; ++i) {
        char idBuffer[64] = {0};
        if (MCEEditorGetEntityIdAt(i, idBuffer, sizeof(idBuffer)) <= 0) { continue; }
        char nameBuffer[128] = {0};
        if (MCEEditorGetEntityName(idBuffer, nameBuffer, sizeof(nameBuffer)) <= 0) {
            strncpy(nameBuffer, idBuffer, sizeof(nameBuffer) - 1);
        }
        bool isSelected = selectedEntityId && selectedEntityId[0] != 0 && strcmp(selectedEntityId, idBuffer) == 0;
        if (ImGui::Selectable(nameBuffer, isSelected)) {
            AssignSelection(selectedEntityId, selectedEntityIdSize, idBuffer);
            MCEEditorLogSelection(idBuffer);
        }
        if (ImGui::BeginDragDropTarget()) {
            if (const ImGuiPayload* payload = ImGui::AcceptDragDropPayload("MCE_ASSET_MATERIAL")) {
                const char *payloadText = static_cast<const char *>(payload->Data);
                MCEEditorAssignMaterialToEntity(idBuffer, payloadText);
            }
            if (const ImGuiPayload* payload = ImGui::AcceptDragDropPayload("MCE_ASSET_MODEL")) {
                const char *payloadText = static_cast<const char *>(payload->Data);
                char createdId[64] = {0};
                if (MCEEditorCreateMeshEntityFromHandle(payloadText, createdId, sizeof(createdId)) > 0) {
                    AssignSelection(selectedEntityId, selectedEntityIdSize, createdId);
                }
            }
            ImGui::EndDragDropTarget();
        }
        if (ImGui::BeginPopupContextItem()) {
            if (MCEEditorEntityHasComponent(idBuffer, 4) != 0) {
                if (ImGui::MenuItem("Set as Active Sky")) {
                    MCEEditorSetActiveSky(idBuffer);
                }
                ImGui::Separator();
            }
            if (ImGui::MenuItem("Delete")) {
                MCEEditorDestroyEntity(idBuffer);
                if (isSelected) {
                    AssignSelection(selectedEntityId, selectedEntityIdSize, nullptr);
                }
            }
            ImGui::EndPopup();
        }
    }

    if (ImGui::BeginPopupContextWindow("SceneHierarchyContext", ImGuiPopupFlags_MouseButtonRight)) {
        if (ImGui::MenuItem("Create Empty Entity")) {
            char createdId[64] = {0};
            if (MCEEditorCreateEntity("Empty Entity", createdId, sizeof(createdId)) > 0) {
                AssignSelection(selectedEntityId, selectedEntityIdSize, createdId);
            }
        }
        if (ImGui::BeginMenu("Create 3D")) {
            if (ImGui::MenuItem("Cube")) {
                char createdId[64] = {0};
                if (MCEEditorCreateMeshEntity(0, createdId, sizeof(createdId)) > 0) {
                    AssignSelection(selectedEntityId, selectedEntityIdSize, createdId);
                }
            }
            if (ImGui::MenuItem("Sphere")) {
                char createdId[64] = {0};
                if (MCEEditorCreateMeshEntity(1, createdId, sizeof(createdId)) > 0) {
                    AssignSelection(selectedEntityId, selectedEntityIdSize, createdId);
                }
            }
            if (ImGui::MenuItem("Plane")) {
                char createdId[64] = {0};
                if (MCEEditorCreateMeshEntity(2, createdId, sizeof(createdId)) > 0) {
                    AssignSelection(selectedEntityId, selectedEntityIdSize, createdId);
                }
            }
            ImGui::EndMenu();
        }
        if (ImGui::BeginMenu("Create Light")) {
            if (ImGui::MenuItem("Point Light")) {
                char createdId[64] = {0};
                if (MCEEditorCreateLightEntity(0, createdId, sizeof(createdId)) > 0) {
                    AssignSelection(selectedEntityId, selectedEntityIdSize, createdId);
                }
            }
            if (ImGui::MenuItem("Spot Light")) {
                char createdId[64] = {0};
                if (MCEEditorCreateLightEntity(1, createdId, sizeof(createdId)) > 0) {
                    AssignSelection(selectedEntityId, selectedEntityIdSize, createdId);
                }
            }
            if (ImGui::MenuItem("Directional Light")) {
                char createdId[64] = {0};
                if (MCEEditorCreateLightEntity(2, createdId, sizeof(createdId)) > 0) {
                    AssignSelection(selectedEntityId, selectedEntityIdSize, createdId);
                }
            }
            ImGui::EndMenu();
        }
        if (ImGui::MenuItem("Create Sky")) {
            char createdId[64] = {0};
            if (MCEEditorCreateSkyEntity(createdId, sizeof(createdId)) > 0) {
                AssignSelection(selectedEntityId, selectedEntityIdSize, createdId);
            }
        }
        if (selectedEntityId && selectedEntityId[0] != 0) {
            if (ImGui::MenuItem("Delete Selected")) {
                MCEEditorDestroyEntity(selectedEntityId);
                AssignSelection(selectedEntityId, selectedEntityIdSize, nullptr);
            }
        }
        ImGui::EndPopup();
    }

    ImGui::EndChild();
    ImGui::End();
}
