// SceneHierarchyPanel.mm
// Defines the ImGui SceneHierarchy panel rendering and interaction logic.
// Created by Kaden Cringle.

#import "SceneHierarchyPanel.h"

#import "../../ImGui/imgui.h"
#import "PanelState.h"
#import "../Widgets/UIWidgets.h"
#include <algorithm>
#include <functional>
#include <stdint.h>
#include <string.h>
#include <string>
#include <vector>

extern "C" int32_t MCEEditorGetEntityName(MCE_CTX, const char *entityId, char *buffer, int32_t bufferSize);
extern "C" uint32_t MCEEditorEntityHasComponent(MCE_CTX, const char *entityId, int32_t componentType);
extern "C" int32_t MCEEditorCreateEntity(MCE_CTX, const char *name, char *outId, int32_t outIdSize);
extern "C" int32_t MCEEditorCreateMeshEntity(MCE_CTX, int32_t meshType, char *outId, int32_t outIdSize);
extern "C" int32_t MCEEditorCreateLightEntity(MCE_CTX, int32_t lightType, char *outId, int32_t outIdSize);
extern "C" int32_t MCEEditorCreateSkyEntity(MCE_CTX, char *outId, int32_t outIdSize);
extern "C" int32_t MCEEditorCreateCameraEntity(MCE_CTX, char *outId, int32_t outIdSize);
extern "C" uint32_t MCEEditorSetActiveSky(MCE_CTX, const char *entityId);
extern "C" void MCEEditorDestroyEntity(MCE_CTX, const char *entityId);
extern "C" void MCEEditorDestroySelectedEntities(MCE_CTX);
extern "C" int32_t MCEEditorDuplicateSelectedEntities(MCE_CTX, char *outPrimaryId, int32_t outPrimaryIdSize);
extern "C" void MCEEditorAssignMaterialToEntity(MCE_CTX, const char *entityId, const char *materialHandle);
extern "C" int32_t MCEEditorCreateMeshEntityFromHandle(MCE_CTX, const char *meshHandle, char *outId, int32_t outIdSize);
extern "C" int32_t MCEEditorInstantiatePrefabFromHandle(MCE_CTX, const char *prefabHandle, char *outId, int32_t outIdSize);
extern "C" uint32_t MCEEditorCreatePrefabFromEntity(MCE_CTX, const char *entityId, char *outPath, int32_t outPathSize);
extern "C" int32_t MCEEditorGetAssetCount(MCE_CTX);
extern "C" uint32_t MCEEditorGetAssetAt(MCE_CTX, int32_t index,
                                        char *handleBuffer, int32_t handleBufferSize,
                                        int32_t *typeOut,
                                        char *pathBuffer, int32_t pathBufferSize,
                                        char *nameBuffer, int32_t nameBufferSize);
extern "C" void *MCEContextGetUIPanelState(MCE_CTX);
extern "C" void MCEEditorSetLastSelectedEntityId(MCE_CTX, const char *value);
extern "C" int32_t MCEEditorGetSelectedEntityCount(MCE_CTX);
extern "C" int32_t MCEEditorGetSelectedEntityIdAt(MCE_CTX, int32_t index, char *buffer, int32_t bufferSize);
extern "C" void MCEEditorSetSelectedEntitiesCSV(MCE_CTX, const char *csv, const char *primaryId);
extern "C" int32_t MCEEditorGetRootEntityCount(MCE_CTX);
extern "C" int32_t MCEEditorGetRootEntityIdAt(MCE_CTX, int32_t index, char *buffer, int32_t bufferSize);
extern "C" int32_t MCEEditorGetChildEntityCount(MCE_CTX, const char *parentId);
extern "C" int32_t MCEEditorGetChildEntityIdAt(MCE_CTX, const char *parentId, int32_t index, char *buffer, int32_t bufferSize);
extern "C" int32_t MCEEditorGetParentEntityId(MCE_CTX, const char *childId, char *buffer, int32_t bufferSize);
extern "C" uint32_t MCEEditorSetParent(MCE_CTX, const char *childId, const char *parentId, uint32_t keepWorldTransform);
extern "C" uint32_t MCEEditorUnparent(MCE_CTX, const char *childId, uint32_t keepWorldTransform);
extern "C" uint32_t MCEEditorReorderEntity(MCE_CTX, const char *entityId, const char *parentId, int32_t newIndex);
extern "C" uint32_t MCESceneIsPlaying(MCE_CTX);
extern "C" uint32_t MCESceneIsSimulating(MCE_CTX);

namespace {
using MCEPanelState::SceneHierarchyState;

SceneHierarchyState &GetSceneHierarchyState(void *context) {
    auto *state = static_cast<MCEPanelState::EditorUIPanelState *>(MCEContextGetUIPanelState(context));
    return state->sceneHierarchy;
}

bool HasId(const std::vector<std::string> &ids, const std::string &id) {
    return std::find(ids.begin(), ids.end(), id) != ids.end();
}

std::string JoinCSV(const std::vector<std::string> &ids) {
    std::string csv;
    for (size_t i = 0; i < ids.size(); ++i) {
        if (i > 0) { csv += ","; }
        csv += ids[i];
    }
    return csv;
}

std::vector<std::string> ReadSelection(void *context) {
    std::vector<std::string> ids;
    const int32_t count = MCEEditorGetSelectedEntityCount(context);
    ids.reserve(count > 0 ? static_cast<size_t>(count) : 0);
    for (int32_t i = 0; i < count; ++i) {
        char idBuffer[64] = {0};
        if (MCEEditorGetSelectedEntityIdAt(context, i, idBuffer, sizeof(idBuffer)) > 0) {
            ids.emplace_back(idBuffer);
        }
    }
    return ids;
}

void AssignPrimarySelection(char *selectedEntityId, size_t selectedEntityIdSize, const std::string &id) {
    if (!selectedEntityId || selectedEntityIdSize == 0) { return; }
    const size_t length = std::min(id.size(), selectedEntityIdSize - 1);
    if (length > 0) {
        memcpy(selectedEntityId, id.c_str(), length);
    }
    selectedEntityId[length] = 0;
}

void CommitSelection(void *context,
                     char *selectedEntityId,
                     size_t selectedEntityIdSize,
                     const std::vector<std::string> &ids,
                     const std::string &primaryId) {
    const std::string csv = JoinCSV(ids);
    const char *primary = primaryId.empty() ? nullptr : primaryId.c_str();
    MCEEditorSetSelectedEntitiesCSV(context, csv.c_str(), primary);
    AssignPrimarySelection(selectedEntityId, selectedEntityIdSize, primaryId);
    MCEEditorSetLastSelectedEntityId(context, primaryId.c_str());
}

std::string GetParentId(void *context, const std::string &childId) {
    char buffer[64] = {0};
    if (MCEEditorGetParentEntityId(context, childId.c_str(), buffer, sizeof(buffer)) > 0) {
        return std::string(buffer);
    }
    return "";
}

bool IsDescendantOf(void *context, const std::string &candidate, const std::string &ancestor) {
    std::string current = candidate;
    while (!current.empty()) {
        const std::string parent = GetParentId(context, current);
        if (parent.empty()) { return false; }
        if (parent == ancestor) { return true; }
        current = parent;
    }
    return false;
}

std::vector<std::string> TopLevelSelection(void *context, const std::vector<std::string> &selection) {
    std::vector<std::string> result;
    result.reserve(selection.size());
    for (const std::string &id : selection) {
        bool nested = false;
        std::string current = GetParentId(context, id);
        while (!current.empty()) {
            if (HasId(selection, current)) {
                nested = true;
                break;
            }
            current = GetParentId(context, current);
        }
        if (!nested) {
            result.push_back(id);
        }
    }
    return result;
}

std::vector<std::string> FetchChildren(void *context, const std::string &parentId) {
    std::vector<std::string> out;
    const int32_t count = MCEEditorGetChildEntityCount(context, parentId.c_str());
    out.reserve(count > 0 ? static_cast<size_t>(count) : 0);
    for (int32_t i = 0; i < count; ++i) {
        char idBuffer[64] = {0};
        if (MCEEditorGetChildEntityIdAt(context, parentId.c_str(), i, idBuffer, sizeof(idBuffer)) > 0) {
            out.emplace_back(idBuffer);
        }
    }
    return out;
}

void DuplicateSelection(void *context, char *selectedEntityId, size_t selectedEntityIdSize) {
    char newPrimary[64] = {0};
    if (MCEEditorDuplicateSelectedEntities(context, newPrimary, sizeof(newPrimary)) > 0) {
        AssignPrimarySelection(selectedEntityId, selectedEntityIdSize, std::string(newPrimary));
        MCEEditorSetLastSelectedEntityId(context, newPrimary);
    }
}

void CreateChildEntity(void *context, const char *parentId, char *selectedEntityId, size_t selectedEntityIdSize) {
    char createdId[64] = {0};
    if (MCEEditorCreateEntity(context, "Empty Entity", createdId, sizeof(createdId)) <= 0) { return; }
    MCEEditorSetParent(context, createdId, parentId, 1);
    std::vector<std::string> selection = {std::string(createdId)};
    CommitSelection(context, selectedEntityId, selectedEntityIdSize, selection, selection.front());
}

void DrawPrefabPicker(void *context, SceneHierarchyState &state, bool runtimeLocked, bool *open, char *selectedEntityId, size_t selectedEntityIdSize) {
    if (!open || !*open) { return; }
    ImGui::SetNextWindowSize(ImVec2(420.0f, 320.0f), ImGuiCond_Once);
    if (!ImGui::BeginPopupModal("PrefabPicker", open, ImGuiWindowFlags_AlwaysAutoResize)) {
        return;
    }

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
        if (type != 5 || handleBuffer[0] == 0) { continue; }
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
    const bool canCreate = !runtimeLocked && !state.selectedPrefabHandle.empty();
    if (!canCreate) { ImGui::BeginDisabled(); }
    if (ImGui::Button("Create")) {
        char createdId[64] = {0};
        if (MCEEditorInstantiatePrefabFromHandle(context, state.selectedPrefabHandle.c_str(), createdId, sizeof(createdId)) > 0) {
            std::vector<std::string> selection = {std::string(createdId)};
            CommitSelection(context, selectedEntityId, selectedEntityIdSize, selection, selection.front());
        }
        *open = false;
        ImGui::CloseCurrentPopup();
    }
    if (!canCreate) { ImGui::EndDisabled(); }
    ImGui::SameLine();
    if (ImGui::Button("Close")) {
        *open = false;
        ImGui::CloseCurrentPopup();
    }
    ImGui::EndPopup();
}
} // namespace

void ImGuiSceneHierarchyPanelDraw(void *context, bool *isOpen, char *selectedEntityId, size_t selectedEntityIdSize) {
    if (!isOpen || !*isOpen) { return; }
    SceneHierarchyState &state = GetSceneHierarchyState(context);
    if (!EditorUI::BeginPanel("Scene Hierarchy", isOpen)) {
        EditorUI::EndPanel();
        return;
    }

    auto selection = ReadSelection(context);
    std::string primary = selection.empty() ? "" : selection.back();
    const bool runtimeLocked = MCESceneIsPlaying(context) != 0 || MCESceneIsSimulating(context) != 0;

    if (!runtimeLocked
        && ImGui::IsWindowFocused(ImGuiFocusedFlags_RootAndChildWindows)
        && !ImGui::GetIO().WantTextInput
        && ImGui::IsKeyPressed(ImGuiKey_D)
        && (ImGui::GetIO().KeySuper || ImGui::GetIO().KeyCtrl)) {
        DuplicateSelection(context, selectedEntityId, selectedEntityIdSize);
        selection = ReadSelection(context);
        primary = selection.empty() ? "" : selection.back();
    }

    ImGui::PushStyleVar(ImGuiStyleVar_FramePadding, ImVec2(8.0f, 4.0f));
    ImGui::PushStyleVar(ImGuiStyleVar_ItemSpacing, ImVec2(6.0f, 2.0f));
    ImGui::BeginChild("SceneHierarchyScroll", ImVec2(0, 0), false, ImGuiWindowFlags_AlwaysVerticalScrollbar);
    if (runtimeLocked) {
        ImGui::TextColored(ImVec4(0.95f, 0.7f, 0.2f, 1.0f), "Runtime Locked (Stop to Edit)");
        ImGui::Separator();
    }

    state.visibleEntityIds.clear();
    std::function<void(const std::string &)> collectVisibleIds = [&](const std::string &id) {
        state.visibleEntityIds.push_back(id);
        auto expandedIt = state.expandedByEntityId.find(id);
        bool expanded = expandedIt == state.expandedByEntityId.end() ? true : expandedIt->second;
        if (expandedIt == state.expandedByEntityId.end()) {
            state.expandedByEntityId[id] = true;
        }
        if (!expanded) { return; }
        auto children = FetchChildren(context, id);
        for (const std::string &child : children) {
            collectVisibleIds(child);
        }
    };
    {
        const int32_t rootCount = MCEEditorGetRootEntityCount(context);
        for (int32_t i = 0; i < rootCount; ++i) {
            char idBuffer[64] = {0};
            if (MCEEditorGetRootEntityIdAt(context, i, idBuffer, sizeof(idBuffer)) > 0) {
                collectVisibleIds(std::string(idBuffer));
            }
        }
    }

    const float rowHeight = ImGui::GetTextLineHeight() + 10.0f;
    const float rowWidth = ImGui::GetContentRegionAvail().x;
    std::string pendingReorderTarget;
    std::string pendingParentTarget;
    bool pendingInsertAfter = false;

    std::function<void(const std::string &, int)> drawNode = [&](const std::string &id, int depth) {
        char nameBuffer[128] = {0};
        if (MCEEditorGetEntityName(context, id.c_str(), nameBuffer, sizeof(nameBuffer)) <= 0) {
            strncpy(nameBuffer, id.c_str(), sizeof(nameBuffer) - 1);
        }

        auto children = FetchChildren(context, id);
        const bool hasChildren = !children.empty();
        auto expandedIt = state.expandedByEntityId.find(id);
        bool expanded = expandedIt == state.expandedByEntityId.end() ? true : expandedIt->second;
        if (expandedIt == state.expandedByEntityId.end()) {
            state.expandedByEntityId[id] = true;
        }
        const bool isSelected = HasId(selection, id);

        ImGui::PushID(id.c_str());
        ImGui::InvisibleButton("##EntityRow", ImVec2(rowWidth, rowHeight));
        const bool hovered = ImGui::IsItemHovered();
        ImVec2 itemMin = ImGui::GetItemRectMin();
        ImVec2 itemMax = ImGui::GetItemRectMax();
        ImDrawList *drawList = ImGui::GetWindowDrawList();

        if (isSelected) {
            drawList->AddRectFilled(itemMin, itemMax, IM_COL32(120, 95, 150, 80), 4.0f);
            drawList->AddRect(itemMin, itemMax, IM_COL32(155, 120, 190, 160), 4.0f, 0, 1.0f);
        } else if (hovered) {
            drawList->AddRectFilled(itemMin, itemMax, IM_COL32(90, 90, 100, 70), 4.0f);
        }

        const float indent = 12.0f + depth * 16.0f;
        ImVec2 triangleMin(itemMin.x + indent, itemMin.y + (rowHeight - 10.0f) * 0.5f);
        ImVec2 textPos(itemMin.x + indent + (hasChildren ? 14.0f : 8.0f), itemMin.y + (rowHeight - ImGui::GetTextLineHeight()) * 0.5f);
        if (hasChildren) {
            drawList->AddText(triangleMin, IM_COL32(220, 220, 220, 220), expanded ? "v" : ">");
        }
        drawList->AddText(textPos, ImGui::GetColorU32(ImGuiCol_Text), nameBuffer);

        const bool clicked = ImGui::IsItemClicked(ImGuiMouseButton_Left);
        if (clicked) {
            auto clickedIt = std::find(state.visibleEntityIds.begin(), state.visibleEntityIds.end(), id);
            const int clickedVisibleIndex = clickedIt == state.visibleEntityIds.end()
                ? -1
                : static_cast<int>(clickedIt - state.visibleEntityIds.begin());
            const bool shift = ImGui::GetIO().KeyShift;
            const bool toggle = ImGui::GetIO().KeyCtrl || ImGui::GetIO().KeySuper;
            const std::string anchorId = !state.rangeAnchorEntityId.empty()
                ? state.rangeAnchorEntityId
                : primary;
            if (shift && clickedVisibleIndex >= 0 && !anchorId.empty()) {
                auto anchorIt = std::find(state.visibleEntityIds.begin(), state.visibleEntityIds.end(), anchorId);
                const int anchorIndex = anchorIt == state.visibleEntityIds.end()
                    ? clickedVisibleIndex
                    : static_cast<int>(anchorIt - state.visibleEntityIds.begin());
                const int minIndex = std::min(anchorIndex, clickedVisibleIndex);
                const int maxIndex = std::max(anchorIndex, clickedVisibleIndex);
                std::vector<std::string> range;
                range.reserve(static_cast<size_t>(maxIndex - minIndex + 1));
                for (int i = minIndex; i <= maxIndex; ++i) {
                    range.push_back(state.visibleEntityIds[static_cast<size_t>(i)]);
                }
                CommitSelection(context, selectedEntityId, selectedEntityIdSize, range, id);
                selection = range;
                primary = id;
                if (state.rangeAnchorEntityId.empty()) {
                    state.rangeAnchorEntityId = anchorId;
                }
            } else if (toggle) {
                std::vector<std::string> toggled = selection;
                auto it = std::find(toggled.begin(), toggled.end(), id);
                if (it == toggled.end()) {
                    toggled.push_back(id);
                    primary = id;
                } else {
                    toggled.erase(it);
                    primary = toggled.empty() ? "" : toggled.back();
                }
                CommitSelection(context, selectedEntityId, selectedEntityIdSize, toggled, primary);
                selection = toggled;
                state.rangeAnchorEntityId = id;
            } else {
                std::vector<std::string> single = {id};
                CommitSelection(context, selectedEntityId, selectedEntityIdSize, single, id);
                selection = single;
                primary = id;
                state.rangeAnchorEntityId = id;
            }
        }

        if (hasChildren && hovered && ImGui::IsMouseDoubleClicked(ImGuiMouseButton_Left)) {
            expanded = !expanded;
            state.expandedByEntityId[id] = expanded;
        }
        if (hasChildren && hovered && ImGui::IsMouseClicked(ImGuiMouseButton_Left)) {
            const float triangleMaxX = triangleMin.x + 10.0f;
            if (ImGui::GetIO().MousePos.x >= triangleMin.x && ImGui::GetIO().MousePos.x <= triangleMaxX) {
                expanded = !expanded;
                state.expandedByEntityId[id] = expanded;
            }
        }

        if (ImGui::BeginDragDropSource()) {
            auto payloadSelection = HasId(selection, id) ? TopLevelSelection(context, selection) : std::vector<std::string>{id};
            const std::string csv = JoinCSV(payloadSelection);
            ImGui::SetDragDropPayload("MCE_SCENE_ENTITY_IDS", csv.c_str(), csv.size() + 1);
            ImGui::TextUnformatted(nameBuffer);
            ImGui::EndDragDropSource();
        }

        if (ImGui::BeginDragDropTarget()) {
            if (const ImGuiPayload *payload = ImGui::AcceptDragDropPayload("MCE_ASSET_MATERIAL")) {
                const char *payloadText = static_cast<const char *>(payload->Data);
                MCEEditorAssignMaterialToEntity(context, id.c_str(), payloadText);
            }
            if (!runtimeLocked) {
                if (const ImGuiPayload *payload = ImGui::AcceptDragDropPayload("MCE_ASSET_MODEL")) {
                    const char *payloadText = static_cast<const char *>(payload->Data);
                    char createdId[64] = {0};
                    if (MCEEditorCreateMeshEntityFromHandle(context, payloadText, createdId, sizeof(createdId)) > 0) {
                        MCEEditorSetParent(context, createdId, id.c_str(), 1);
                        std::vector<std::string> newSelection = {std::string(createdId)};
                        CommitSelection(context, selectedEntityId, selectedEntityIdSize, newSelection, newSelection.front());
                        selection = newSelection;
                        primary = newSelection.front();
                    }
                }
                if (const ImGuiPayload *payload = ImGui::AcceptDragDropPayload("MCE_ASSET_PREFAB")) {
                    const char *payloadText = static_cast<const char *>(payload->Data);
                    char createdId[64] = {0};
                    if (MCEEditorInstantiatePrefabFromHandle(context, payloadText, createdId, sizeof(createdId)) > 0) {
                        MCEEditorSetParent(context, createdId, id.c_str(), 1);
                        std::vector<std::string> newSelection = {std::string(createdId)};
                        CommitSelection(context, selectedEntityId, selectedEntityIdSize, newSelection, newSelection.front());
                        selection = newSelection;
                        primary = newSelection.front();
                    }
                }
                if (const ImGuiPayload *payload = ImGui::AcceptDragDropPayload("MCE_SCENE_ENTITY_IDS")) {
                    const float y = ImGui::GetIO().MousePos.y;
                    const float zone = rowHeight * 0.25f;
                    const bool insertBefore = y < itemMin.y + zone;
                    const bool insertAfter = y > itemMax.y - zone;
                    if (insertBefore || insertAfter) {
                        pendingReorderTarget = id;
                        pendingInsertAfter = insertAfter;
                    } else {
                        pendingParentTarget = id;
                    }
                    (void)payload;
                }
            } else {
                ImGui::AcceptDragDropPayload("MCE_ASSET_MODEL");
                ImGui::AcceptDragDropPayload("MCE_ASSET_PREFAB");
                ImGui::AcceptDragDropPayload("MCE_SCENE_ENTITY_IDS");
            }
            ImGui::EndDragDropTarget();
        }

        if (ImGui::BeginPopupContextItem()) {
            if (runtimeLocked) {
                ImGui::BeginDisabled();
            }
            if (MCEEditorEntityHasComponent(context, id.c_str(), 4) != 0) {
                if (ImGui::MenuItem("Set as Active Sky")) {
                    MCEEditorSetActiveSky(context, id.c_str());
                }
                ImGui::Separator();
            }
            if (ImGui::MenuItem("Duplicate", "Cmd/Ctrl+D")) {
                if (!HasId(selection, id)) {
                    std::vector<std::string> single = {id};
                    CommitSelection(context, selectedEntityId, selectedEntityIdSize, single, id);
                    selection = single;
                }
                DuplicateSelection(context, selectedEntityId, selectedEntityIdSize);
                selection = ReadSelection(context);
                primary = selection.empty() ? "" : selection.back();
            }
            if (ImGui::MenuItem("Create Child Empty")) {
                CreateChildEntity(context, id.c_str(), selectedEntityId, selectedEntityIdSize);
            }
            if (ImGui::MenuItem("Create Prefab from Selected")) {
                MCEEditorCreatePrefabFromEntity(context, id.c_str(), nullptr, 0);
            }
            if (ImGui::MenuItem("Delete")) {
                if (HasId(selection, id)) {
                    MCEEditorDestroySelectedEntities(context);
                } else {
                    MCEEditorDestroyEntity(context, id.c_str());
                }
                selection = ReadSelection(context);
                primary = selection.empty() ? "" : selection.back();
                AssignPrimarySelection(selectedEntityId, selectedEntityIdSize, primary);
                MCEEditorSetLastSelectedEntityId(context, primary.c_str());
            }
            if (runtimeLocked) {
                ImGui::EndDisabled();
            }
            ImGui::EndPopup();
        }

        ImGui::PopID();

        if (expanded) {
            for (const std::string &child : children) {
                drawNode(child, depth + 1);
            }
        }
    };

    const int32_t rootCount = MCEEditorGetRootEntityCount(context);
    for (int32_t i = 0; i < rootCount; ++i) {
        char idBuffer[64] = {0};
        if (MCEEditorGetRootEntityIdAt(context, i, idBuffer, sizeof(idBuffer)) > 0) {
            drawNode(std::string(idBuffer), 0);
        }
    }

    if (!runtimeLocked && (!pendingParentTarget.empty() || !pendingReorderTarget.empty())) {
        auto dragged = TopLevelSelection(context, selection);
        if (!dragged.empty()) {
            if (!pendingParentTarget.empty()) {
                bool valid = true;
                for (const std::string &id : dragged) {
                    if (id == pendingParentTarget || IsDescendantOf(context, pendingParentTarget, id)) {
                        valid = false;
                        break;
                    }
                }
                if (valid) {
                    for (const std::string &id : dragged) {
                        MCEEditorSetParent(context, id.c_str(), pendingParentTarget.c_str(), 1);
                    }
                }
            } else if (!pendingReorderTarget.empty()) {
                const std::string parent = GetParentId(context, pendingReorderTarget);
                char parentBuffer[64] = {0};
                const char *parentId = nullptr;
                if (!parent.empty()) {
                    strncpy(parentBuffer, parent.c_str(), sizeof(parentBuffer) - 1);
                    parentId = parentBuffer;
                }

                std::vector<std::string> siblings;
                if (parent.empty()) {
                    const int32_t roots = MCEEditorGetRootEntityCount(context);
                    siblings.reserve(roots);
                    for (int32_t i = 0; i < roots; ++i) {
                        char siblingId[64] = {0};
                        if (MCEEditorGetRootEntityIdAt(context, i, siblingId, sizeof(siblingId)) > 0) {
                            siblings.emplace_back(siblingId);
                        }
                    }
                } else {
                    siblings = FetchChildren(context, parent);
                }

                int targetIndex = 0;
                auto targetIt = std::find(siblings.begin(), siblings.end(), pendingReorderTarget);
                if (targetIt != siblings.end()) {
                    targetIndex = static_cast<int>(targetIt - siblings.begin());
                }
                int insertIndex = targetIndex + (pendingInsertAfter ? 1 : 0);
                for (const std::string &id : dragged) {
                    if (!parent.empty()) {
                        MCEEditorSetParent(context, id.c_str(), parent.c_str(), 1);
                    } else {
                        MCEEditorUnparent(context, id.c_str(), 1);
                    }
                    MCEEditorReorderEntity(context, id.c_str(), parentId, insertIndex);
                    insertIndex += 1;
                }
            }
        }
    }

    if (ImGui::BeginPopupContextWindow("SceneHierarchyContext", ImGuiPopupFlags_MouseButtonRight | ImGuiPopupFlags_NoOpenOverItems)) {
        if (runtimeLocked) {
            ImGui::BeginDisabled();
        }
        if (ImGui::MenuItem("Create Empty")) {
            char createdId[64] = {0};
            if (MCEEditorCreateEntity(context, "Empty Entity", createdId, sizeof(createdId)) > 0) {
                std::vector<std::string> single = {std::string(createdId)};
                CommitSelection(context, selectedEntityId, selectedEntityIdSize, single, single.front());
            }
        }
        if (ImGui::BeginMenu("Create 3D")) {
            if (ImGui::MenuItem("Cube")) {
                char createdId[64] = {0};
                if (MCEEditorCreateMeshEntity(context, 0, createdId, sizeof(createdId)) > 0) {
                    std::vector<std::string> single = {std::string(createdId)};
                    CommitSelection(context, selectedEntityId, selectedEntityIdSize, single, single.front());
                }
            }
            if (ImGui::MenuItem("Sphere")) {
                char createdId[64] = {0};
                if (MCEEditorCreateMeshEntity(context, 1, createdId, sizeof(createdId)) > 0) {
                    std::vector<std::string> single = {std::string(createdId)};
                    CommitSelection(context, selectedEntityId, selectedEntityIdSize, single, single.front());
                }
            }
            if (ImGui::MenuItem("Plane")) {
                char createdId[64] = {0};
                if (MCEEditorCreateMeshEntity(context, 2, createdId, sizeof(createdId)) > 0) {
                    std::vector<std::string> single = {std::string(createdId)};
                    CommitSelection(context, selectedEntityId, selectedEntityIdSize, single, single.front());
                }
            }
            ImGui::EndMenu();
        }
        if (ImGui::MenuItem("Create Camera")) {
            char createdId[64] = {0};
            if (MCEEditorCreateCameraEntity(context, createdId, sizeof(createdId)) > 0) {
                std::vector<std::string> single = {std::string(createdId)};
                CommitSelection(context, selectedEntityId, selectedEntityIdSize, single, single.front());
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
                    std::vector<std::string> single = {std::string(createdId)};
                    CommitSelection(context, selectedEntityId, selectedEntityIdSize, single, single.front());
                }
            }
            if (ImGui::MenuItem("Spot Light")) {
                char createdId[64] = {0};
                if (MCEEditorCreateLightEntity(context, 1, createdId, sizeof(createdId)) > 0) {
                    std::vector<std::string> single = {std::string(createdId)};
                    CommitSelection(context, selectedEntityId, selectedEntityIdSize, single, single.front());
                }
            }
            if (ImGui::MenuItem("Directional Light")) {
                char createdId[64] = {0};
                if (MCEEditorCreateLightEntity(context, 2, createdId, sizeof(createdId)) > 0) {
                    std::vector<std::string> single = {std::string(createdId)};
                    CommitSelection(context, selectedEntityId, selectedEntityIdSize, single, single.front());
                }
            }
            ImGui::EndMenu();
        }
        if (ImGui::MenuItem("Create Sky")) {
            char createdId[64] = {0};
            if (MCEEditorCreateSkyEntity(context, createdId, sizeof(createdId)) > 0) {
                std::vector<std::string> single = {std::string(createdId)};
                CommitSelection(context, selectedEntityId, selectedEntityIdSize, single, single.front());
            }
        }
        if (!selection.empty()) {
            if (ImGui::MenuItem("Duplicate", "Cmd/Ctrl+D")) {
                DuplicateSelection(context, selectedEntityId, selectedEntityIdSize);
            }
            if (ImGui::MenuItem("Delete")) {
                MCEEditorDestroySelectedEntities(context);
                std::vector<std::string> empty;
                CommitSelection(context, selectedEntityId, selectedEntityIdSize, empty, "");
            }
        }
        if (runtimeLocked) {
            ImGui::EndDisabled();
        }
        ImGui::EndPopup();
    }

    if (state.requestPrefabPickerOpen) {
        ImGui::OpenPopup("PrefabPicker");
        state.requestPrefabPickerOpen = false;
    }
    DrawPrefabPicker(context, state, runtimeLocked, &state.showPrefabPicker, selectedEntityId, selectedEntityIdSize);

    ImGui::EndChild();
    ImGui::PopStyleVar(2);
    EditorUI::EndPanel();
}
