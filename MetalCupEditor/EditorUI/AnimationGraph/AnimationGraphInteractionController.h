#pragma once

#include "AnimationGraphSchema.h"
#include "AnimationGraphValidation.h"

#include "../../ImGui/imgui.h"
#include "../../ThirdParty/imgui-node-editor/imgui_node_editor.h"

#include <algorithm>
#include <cctype>
#include <functional>
#include <string>
#include <vector>

namespace AnimationGraphInteractionController {

namespace ed = ax::NodeEditor;

struct PopupStateRefs {
    ImVec2 &openScreenPos;
    ImVec2 &openCanvasPos;
    bool &requestOpen;
    std::string &contextNodeId;
    std::string &contextLinkId;
    std::string &contextPinNodeId;
    int32_t &contextPinSlot;
    bool &contextPinIsInput;
    bool &pendingCreateFromPin;
};

inline void CapturePopupOpenPosition(PopupStateRefs refs,
                                     const ImVec2 &screenPos,
                                     const ImVec2 &canvasPos) {
    refs.openScreenPos = screenPos;
    refs.openCanvasPos = canvasPos;
    refs.requestOpen = true;
}

inline void PositionPopupAtCapturedCursor(PopupStateRefs refs) {
    if (!refs.requestOpen) {
        return;
    }
    ImGui::SetNextWindowPos(refs.openScreenPos, ImGuiCond_Always);
}

template <typename PinMap>
inline bool AcceptCreateFromPinRequest(const PinMap &pinByEditorId,
                                       PopupStateRefs refs,
                                       bool &hasInteractedWithCanvas) {
    ed::PinId createFromPinId;
    if (!ed::QueryNewNode(&createFromPinId)) {
        return false;
    }
    const auto pinIt = pinByEditorId.find(createFromPinId.Get());
    if (pinIt == pinByEditorId.end()) {
        ed::RejectNewItem(ImVec4(0.95f, 0.45f, 0.45f, 1.0f), 2.5f);
        return false;
    }
    if (!ed::AcceptNewItem(ImVec4(0.62f, 0.90f, 0.66f, 1.0f), 3.0f)) {
        return false;
    }
    const ImVec2 screenPos = ImGui::GetMousePos();
    const ImVec2 graphPos = ed::ScreenToCanvas(screenPos);
    CapturePopupOpenPosition(refs, screenPos, graphPos);
    refs.contextPinNodeId = pinIt->second.nodeId;
    refs.contextPinSlot = pinIt->second.slot;
    refs.contextPinIsInput = pinIt->second.isInput;
    refs.pendingCreateFromPin = true;
    hasInteractedWithCanvas = true;
    return true;
}

template <typename NodeMap, typename PinMap, typename LinkMap, typename NodeSelectionFn, typename LinkSelectionFn>
inline void CaptureContextMenuRequests(PopupStateRefs refs,
                                       const NodeMap &nodeIdByEditorId,
                                       const PinMap &pinByEditorId,
                                       const LinkMap &linkIdByEditorId,
                                       bool &hasInteractedWithCanvas,
                                       const char *backgroundPopupName,
                                       const char *nodePopupName,
                                       const char *pinPopupName,
                                       const char *linkPopupName,
                                       NodeSelectionFn onNodeSelected,
                                       LinkSelectionFn onLinkSelected) {
    if (ed::ShowBackgroundContextMenu()) {
        hasInteractedWithCanvas = true;
        const ImVec2 screenPos = ImGui::GetMousePos();
        CapturePopupOpenPosition(refs, screenPos, ed::ScreenToCanvas(screenPos));
        refs.pendingCreateFromPin = false;
        ImGui::OpenPopup(backgroundPopupName);
    }

    ed::NodeId contextNodeId;
    if (ed::ShowNodeContextMenu(&contextNodeId)) {
        const ImVec2 screenPos = ImGui::GetMousePos();
        CapturePopupOpenPosition(refs, screenPos, ed::ScreenToCanvas(screenPos));
        const auto it = nodeIdByEditorId.find(contextNodeId.Get());
        refs.contextNodeId = (it != nodeIdByEditorId.end()) ? it->second : "";
        hasInteractedWithCanvas = true;
        onNodeSelected(refs.contextNodeId);
        ImGui::OpenPopup(nodePopupName);
    }

    ed::PinId contextPinId;
    if (ed::ShowPinContextMenu(&contextPinId)) {
        const ImVec2 screenPos = ImGui::GetMousePos();
        CapturePopupOpenPosition(refs, screenPos, ed::ScreenToCanvas(screenPos));
        const auto it = pinByEditorId.find(contextPinId.Get());
        if (it != pinByEditorId.end()) {
            refs.contextPinNodeId = it->second.nodeId;
            refs.contextPinSlot = it->second.slot;
            refs.contextPinIsInput = it->second.isInput;
        } else {
            refs.contextPinNodeId.clear();
            refs.contextPinSlot = 0;
            refs.contextPinIsInput = false;
        }
        ImGui::OpenPopup(pinPopupName);
    }

    ed::LinkId contextLinkId;
    if (ed::ShowLinkContextMenu(&contextLinkId)) {
        const ImVec2 screenPos = ImGui::GetMousePos();
        CapturePopupOpenPosition(refs, screenPos, ed::ScreenToCanvas(screenPos));
        const auto it = linkIdByEditorId.find(contextLinkId.Get());
        refs.contextLinkId = (it != linkIdByEditorId.end()) ? it->second : "";
        hasInteractedWithCanvas = true;
        onLinkSelected(refs.contextLinkId);
        ImGui::OpenPopup(linkPopupName);
    }
}

inline bool DrawBackgroundContextMenu(PopupStateRefs refs,
                                      const char *popupName,
                                      const char *createPopupName) {
    PositionPopupAtCapturedCursor(refs);
    bool openedCreate = false;
    if (ImGui::BeginPopup(popupName)) {
        if (ImGui::MenuItem("Add Node...")) {
            refs.pendingCreateFromPin = false;
            refs.requestOpen = true;
            ImGui::OpenPopup(createPopupName);
            openedCreate = true;
        }
        if (ImGui::MenuItem("Frame All")) {
            ed::NavigateToContent(0.0f);
        }
        ImGui::EndPopup();
    }
    return openedCreate;
}

template <typename CanCreateFn>
inline bool DrawPinContextMenu(PopupStateRefs refs,
                               const char *popupName,
                               const char *createPopupName,
                               CanCreateFn canCreateFromPin) {
    PositionPopupAtCapturedCursor(refs);
    bool openedCreate = false;
    if (ImGui::BeginPopup(popupName)) {
        const bool hasPin = !refs.contextPinNodeId.empty();
        if (hasPin && canCreateFromPin()) {
            if (ImGui::MenuItem("Create Node...")) {
                refs.pendingCreateFromPin = true;
                refs.requestOpen = true;
                ImGui::OpenPopup(createPopupName);
                ImGui::CloseCurrentPopup();
                openedCreate = true;
            }
        }
        ImGui::EndPopup();
    }
    return openedCreate;
}

template <typename LinkInfoFn, typename DeleteLinkFn>
inline void DrawLinkContextMenu(PopupStateRefs refs,
                                const char *popupName,
                                LinkInfoFn drawLinkInfo,
                                DeleteLinkFn deleteLink) {
    PositionPopupAtCapturedCursor(refs);
    if (ImGui::BeginPopup(popupName)) {
        drawLinkInfo();
        if (!refs.contextLinkId.empty() && ImGui::MenuItem("Delete Link")) {
            deleteLink(refs.contextLinkId);
            refs.contextLinkId.clear();
            ImGui::CloseCurrentPopup();
        }
        ImGui::EndPopup();
    }
    if (!ImGui::IsPopupOpen(popupName)) {
        refs.contextLinkId.clear();
    }
}

template <typename NodeExtrasFn, typename DeleteNodeFn>
inline void DrawNodeContextMenu(PopupStateRefs refs,
                                const char *popupName,
                                NodeExtrasFn drawNodeExtras,
                                DeleteNodeFn deleteNode) {
    PositionPopupAtCapturedCursor(refs);
    if (ImGui::BeginPopup(popupName)) {
        drawNodeExtras();
        if (!refs.contextNodeId.empty() && ImGui::MenuItem("Delete Node")) {
            deleteNode(refs.contextNodeId);
            refs.contextNodeId.clear();
            ImGui::CloseCurrentPopup();
        }
        ImGui::EndPopup();
    }
    if (!ImGui::IsPopupOpen(popupName)) {
        refs.contextNodeId.clear();
    }
}

template <typename FilterFn, typename ActivateFn>
inline bool DrawSchemaCreateMenu(AnimationGraphSchema::GraphDomain domain,
                                 PopupStateRefs refs,
                                 const char *popupName,
                                 const char *searchId,
                                 char *searchBuffer,
                                 size_t searchBufferSize,
                                 const char *headerLabel,
                                 FilterFn canCreateSchema,
                                 ActivateFn activateSchema) {
    bool created = false;
    PositionPopupAtCapturedCursor(refs);
    if (ImGui::BeginPopup(popupName)) {
        if (searchBuffer != nullptr && searchBufferSize > 0) {
            ImGui::SetNextItemWidth(260.0f);
            ImGui::InputTextWithHint(searchId, "Search nodes...", searchBuffer, searchBufferSize);
            ImGui::Separator();
        }
        if (headerLabel != nullptr && headerLabel[0] != 0) {
            ImGui::TextDisabled("%s", headerLabel);
            ImGui::Separator();
        }

        std::string filter = (searchBuffer != nullptr) ? std::string(searchBuffer) : std::string();
        std::transform(filter.begin(), filter.end(), filter.begin(), [](unsigned char c) {
            return static_cast<char>(std::tolower(c));
        });

        const std::vector<const AnimationGraphSchema::AnimGraphNodeSchema *> creatableSchemas =
            AnimationGraphSchema::CreatableSchemasForDomain(domain);
        std::string currentCategory;
        bool menuOpen = false;
        for (const auto *schema : creatableSchemas) {
            if (schema == nullptr || !canCreateSchema(*schema)) {
                continue;
            }
            std::string labelLower = schema->createMenu.label;
            std::transform(labelLower.begin(), labelLower.end(), labelLower.begin(), [](unsigned char c) {
                return static_cast<char>(std::tolower(c));
            });
            if (!filter.empty() && labelLower.find(filter) == std::string::npos) {
                continue;
            }
            if (searchBuffer != nullptr) {
                if (schema->createMenu.category != currentCategory) {
                    if (menuOpen) {
                        ImGui::EndMenu();
                    }
                    currentCategory = schema->createMenu.category;
                    menuOpen = ImGui::BeginMenu(currentCategory.c_str());
                }
                if (menuOpen && ImGui::MenuItem(schema->createMenu.label.c_str())) {
                    created = activateSchema(*schema);
                }
            } else if (ImGui::MenuItem(schema->createMenu.label.c_str())) {
                created = activateSchema(*schema);
            }
            if (created) {
                refs.pendingCreateFromPin = false;
                refs.requestOpen = false;
                ImGui::CloseCurrentPopup();
                break;
            }
        }
        if (menuOpen) {
            ImGui::EndMenu();
        }
        ImGui::EndPopup();
    }
    if (!ImGui::IsPopupOpen(popupName)) {
        refs.pendingCreateFromPin = false;
        refs.requestOpen = false;
    }
    return created;
}

inline bool AnyPopupOpen(const std::initializer_list<const char *> &popupNames) {
    for (const char *popupName : popupNames) {
        if (popupName != nullptr && ImGui::IsPopupOpen(popupName)) {
            return true;
        }
    }
    return false;
}

} // namespace AnimationGraphInteractionController
