#pragma once

#include "AnimationGraphCanvasHost.h"
#include "AnimationGraphInlineWidgets.h"
#include "AnimationGraphInteractionController.h"
#include "AnimationGraphModels.h"
#include "AnimationGraphNodeRenderer.h"
#include "AnimationGraphSchema.h"
#include "AnimationGraphValidation.h"

#include "../Panels/PanelState.h"
#include "../../ImGui/imgui.h"
#include "../../ThirdParty/imgui-node-editor/imgui_node_editor.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>

extern "C" uint32_t MCEEditorGetAssetsRootPath(void *context, char *buffer, int32_t bufferSize);
extern "C" uint32_t MCEEditorAddAnimationGraphStateMachineTransitionGraphNode(void *context, const char *handle, const char *nodeId, const char *transitionId,
                                                                               const char *type, const char *title, float posX, float posY,
                                                                               const char *parameterName, float floatValue, uint32_t hasFloatValue,
                                                                               uint32_t boolValue, uint32_t hasBoolValue,
                                                                               uint32_t synchronizeValue, uint32_t hasSynchronizeValue,
                                                                               uint32_t isOutputNode,
                                                                               char *outNodeId, int32_t outNodeIdSize);
extern "C" uint32_t MCEEditorUpdateAnimationGraphStateMachineTransitionGraphNode(void *context, const char *handle, const char *nodeId, const char *transitionId,
                                                                                  const char *transitionNodeId, const char *title, float posX, float posY,
                                                                                  const char *parameterName, float floatValue, uint32_t hasFloatValue,
                                                                                  uint32_t boolValue, uint32_t hasBoolValue,
                                                                                  uint32_t synchronizeValue, uint32_t hasSynchronizeValue,
                                                                                  uint32_t isOutputNode);
extern "C" uint32_t MCEEditorRemoveAnimationGraphStateMachineTransitionGraphNode(void *context, const char *handle, const char *nodeId, const char *transitionId,
                                                                                  const char *transitionNodeId);
extern "C" uint32_t MCEEditorAddAnimationGraphStateMachineTransitionGraphLink(void *context, const char *handle, const char *nodeId, const char *transitionId,
                                                                               const char *fromNodeId, int32_t fromSlot,
                                                                               const char *toNodeId, int32_t toSlot,
                                                                               char *outLinkId, int32_t outLinkIdSize);
extern "C" uint32_t MCEEditorRemoveAnimationGraphStateMachineTransitionGraphLink(void *context, const char *handle, const char *nodeId, const char *transitionId,
                                                                                  const char *linkId);
extern "C" uint32_t MCEEditorSetAnimationGraphStateMachineTransitionGraphOutputNode(void *context, const char *handle, const char *nodeId, const char *transitionId,
                                                                                     const char *outputNodeId);

struct AnimationGraphTransitionGraphHostContext {
    void *context = nullptr;
    std::string graphHandle;
    std::string stateMachineNodeId;
    MCEPanelState::AnimationGraphPanelState *panelState = nullptr;
};

namespace AnimationGraphTransitionGraphHost {

namespace ed = ax::NodeEditor;

struct TransitionGraphPinEndpoint {
    std::string nodeId;
    int32_t slot = 0;
    bool isInput = false;
    const AnimationGraphSchema::AnimGraphNodeSchema *nodeSchema = nullptr;
    const AnimationGraphSchema::AnimGraphPinSchema *pinSchema = nullptr;
};

struct TransitionGraphEditorState {
    struct NodePopupState {
        ImVec2 openScreenPos = ImVec2(0.0f, 0.0f);
        ImVec2 openCanvasPos = ImVec2(0.0f, 0.0f);
        bool requestOpen = false;
    };

    ed::EditorContext *context = nullptr;
    std::unordered_set<std::string> initializedNodePositions;
    bool didAutoFrame = false;
    std::string settingsFilePath;
    NodePopupState popupContext;
    std::string contextNodeId;
    std::string contextLinkId;
    std::string contextPinNodeId;
    int32_t contextPinSlot = 0;
    bool contextPinIsInput = false;
    bool pendingCreateFromPin = false;
};

struct TransitionGraphPopupIds {
    std::string background;
    std::string node;
    std::string pin;
    std::string link;
    std::string createNode;
};

inline std::unordered_map<std::string, TransitionGraphEditorState> &EditorStatesByWorkspace() {
    static std::unordered_map<std::string, TransitionGraphEditorState> states;
    return states;
}

inline uintptr_t HashStableId(const std::string &value) {
    uint64_t hash = 1469598103934665603ull;
    for (unsigned char c : value) {
        hash ^= static_cast<uint64_t>(c);
        hash *= 1099511628211ull;
    }
    hash &= 0x7fffffffffffffffull;
    if (hash == 0) { hash = 1; }
    return static_cast<uintptr_t>(hash);
}

inline bool DrawTransitionGraphCanvas(const AnimationGraphTransitionGraphHostContext &hostContext,
                                      const AnimationGraphNodeRecord::StateMachineTransitionRecord &transitionRecord,
                                      const char *canvasId) {
    auto makeNodeEditorNodeId = [&](const std::string &nodeId) {
        return ed::NodeId(HashStableId(std::string("transition-node|").append(nodeId)));
    };
    auto makeNodeEditorLinkId = [&](const std::string &linkId) {
        return ed::LinkId(HashStableId(std::string("transition-link|").append(linkId)));
    };
    auto makeNodeEditorPinId = [&](const std::string &nodeId, int32_t slot, bool isInput) {
        std::string key = "transition-pin|";
        key.append(nodeId);
        key.push_back('|');
        key.append(isInput ? "in|" : "out|");
        key.append(std::to_string(slot));
        return ed::PinId(HashStableId(key));
    };
    auto schemaForType = [&](std::string_view type) -> const AnimationGraphSchema::AnimGraphNodeSchema * {
        return AnimationGraphSchema::SchemaForTransitionType(type);
    };
    auto isOutputNode = [&](const AnimationGraphNodeRecord::StateMachineTransitionRecord::TransitionGraphNodeRecord &node) -> bool {
        return (!transitionRecord.transitionGraphOutputNodeId.empty() && node.id == transitionRecord.transitionGraphOutputNodeId) ||
            AnimationGraphSchema::NormalizeTypeId(node.type) == AnimationGraphSchema::NormalizeTypeId("transitionOutput");
    };
    const std::string workspaceKey = hostContext.graphHandle + "|" + hostContext.stateMachineNodeId + "|" + transitionRecord.id;
    const TransitionGraphPopupIds popupIds {
        "TransitionGraphBackgroundContext##" + workspaceKey,
        "TransitionGraphNodeContext##" + workspaceKey,
        "TransitionGraphPinContext##" + workspaceKey,
        "TransitionGraphLinkContext##" + workspaceKey,
        "TransitionGraphAddNode##" + workspaceKey
    };
    auto settingsPath = [&]() -> std::string {
        char assetsRoot[1024] = {0};
        if (hostContext.context == nullptr ||
            MCEEditorGetAssetsRootPath(hostContext.context, assetsRoot, sizeof(assetsRoot)) == 0 ||
            assetsRoot[0] == 0) {
            return {};
        }
        std::string path = assetsRoot;
        if (!path.empty() && path.back() != '/') {
            path.push_back('/');
        }
        path.append(".transition-node-editor-");
        path.append(workspaceKey);
        path.append(".json");
        return path;
    };
    auto addNode = [&](const char *type, const char *title, const ImVec2 &graphPos, const char *parameterName,
                       float floatValue, bool hasFloatValue,
                       bool boolValue, bool hasBoolValue,
                       bool synchronizeValue, bool hasSynchronizeValue,
                       bool isOutput) -> std::string {
        if (hostContext.context == nullptr || hostContext.graphHandle.empty() || hostContext.stateMachineNodeId.empty()) {
            return {};
        }
        char outNodeId[64] = {0};
        if (MCEEditorAddAnimationGraphStateMachineTransitionGraphNode(
                hostContext.context,
                hostContext.graphHandle.c_str(),
                hostContext.stateMachineNodeId.c_str(),
                transitionRecord.id.c_str(),
                type,
                title,
                graphPos.x,
                graphPos.y,
                parameterName,
                floatValue,
                hasFloatValue ? 1u : 0u,
                boolValue ? 1u : 0u,
                hasBoolValue ? 1u : 0u,
                synchronizeValue ? 1u : 0u,
                hasSynchronizeValue ? 1u : 0u,
                isOutput ? 1u : 0u,
                outNodeId,
                sizeof(outNodeId)) == 0) {
            return {};
        }
        return outNodeId;
    };
    auto updateNode = [&](const AnimationGraphNodeRecord::StateMachineTransitionRecord::TransitionGraphNodeRecord &node,
                          const char *title, const ImVec2 &graphPos, const char *parameterName,
                          float floatValue, bool hasFloatValue,
                          bool boolValue, bool hasBoolValue,
                          bool synchronizeValue, bool hasSynchronizeValue,
                          bool isOutput) {
        if (hostContext.context == nullptr || hostContext.graphHandle.empty() || hostContext.stateMachineNodeId.empty()) {
            return false;
        }
        return MCEEditorUpdateAnimationGraphStateMachineTransitionGraphNode(
                   hostContext.context,
                   hostContext.graphHandle.c_str(),
                   hostContext.stateMachineNodeId.c_str(),
                   transitionRecord.id.c_str(),
                   node.id.c_str(),
                   title,
                   graphPos.x,
                   graphPos.y,
                   parameterName,
                   floatValue,
                   hasFloatValue ? 1u : 0u,
                   boolValue ? 1u : 0u,
                   hasBoolValue ? 1u : 0u,
                   synchronizeValue ? 1u : 0u,
                   hasSynchronizeValue ? 1u : 0u,
                   isOutput ? 1u : 0u) != 0;
    };

    ImGui::BeginChild(canvasId, ImVec2(0.0f, 0.0f), true);
    if (hostContext.context == nullptr || hostContext.graphHandle.empty() || hostContext.stateMachineNodeId.empty()) {
        ImGui::TextDisabled("Transition graph editor context is unavailable.");
        ImGui::EndChild();
        return false;
    }

    if (!transitionRecord.hasInlineTransitionGraph) {
        ImGui::TextDisabled("Transition graph is empty. Right-click to add nodes.");
        ImGui::SameLine();
        if (ImGui::SmallButton("Create Output Node")) {
            addNode("transitionOutput",
                    "Transition Output",
                    ImVec2(0.0f, 0.0f),
                    nullptr,
                    transitionRecord.duration,
                    true,
                    false,
                    true,
                    false,
                    true,
                    true);
        }
    }

    TransitionGraphEditorState &editorState = EditorStatesByWorkspace()[workspaceKey];
    if (editorState.context == nullptr) {
        editorState.settingsFilePath = settingsPath();
        ed::Config config {};
        config.SettingsFile = editorState.settingsFilePath.empty() ? nullptr : editorState.settingsFilePath.c_str();
        config.DragButtonIndex = 0;
        config.SelectButtonIndex = 0;
        config.NavigateButtonIndex = 1;
        config.ContextMenuButtonIndex = 1;
        config.EnableSmoothZoom = true;
        editorState.context = ed::CreateEditor(&config);
    }
    if (editorState.context == nullptr) {
        ImGui::TextDisabled("Failed to initialize transition node editor context.");
        ImGui::EndChild();
        return false;
    }

    auto popupRefs = [&]() {
        return AnimationGraphInteractionController::PopupStateRefs {
            editorState.popupContext.openScreenPos,
            editorState.popupContext.openCanvasPos,
            editorState.popupContext.requestOpen,
            editorState.contextNodeId,
            editorState.contextLinkId,
            editorState.contextPinNodeId,
            editorState.contextPinSlot,
            editorState.contextPinIsInput,
            editorState.pendingCreateFromPin
        };
    };

    std::unordered_map<uintptr_t, std::string> nodeIdByEditorId;
    std::unordered_map<uintptr_t, std::string> linkIdByEditorId;
    std::unordered_map<uintptr_t, TransitionGraphPinEndpoint> pinByEditorId;

    AnimationGraphCanvasHost::DrawCanvas({editorState.context,
                                          "TransitionGraphNodeEditor",
                                          &editorState.didAutoFrame,
                                          hostContext.panelState ? &hostContext.panelState->hasInteractedWithCanvas : nullptr},
                                         [&]() {
        std::unordered_set<std::string> connectedInputSlots;
        connectedInputSlots.reserve(transitionRecord.transitionGraphLinks.size());
        auto inputSlotKey = [](const std::string &nodeId, int32_t slot) {
            return nodeId + "|" + std::to_string(slot);
        };
        for (const auto &link : transitionRecord.transitionGraphLinks) {
            connectedInputSlots.insert(inputSlotKey(link.toNodeId, link.toSlot));
        }
        auto isInputDriven = [&](const std::string &nodeId, int32_t slot) {
            return connectedInputSlots.count(inputSlotKey(nodeId, slot)) != 0;
        };

        for (const auto &node : transitionRecord.transitionGraphNodes) {
            const AnimationGraphSchema::AnimGraphNodeSchema *nodeSchema = schemaForType(node.type);
            const ed::NodeId editorNodeId = makeNodeEditorNodeId(node.id);
            nodeIdByEditorId[editorNodeId.Get()] = node.id;
            if (editorState.initializedNodePositions.count(node.id) == 0) {
                ed::SetNodePosition(editorNodeId, node.position);
                editorState.initializedNodePositions.insert(node.id);
            }
            const std::string normalizedType = AnimationGraphSchema::NormalizeTypeId(node.type);
            const std::string defaultTitle = node.title.empty() && nodeSchema ? nodeSchema->title : node.title;
            AnimationGraphNodeRenderer::RenderNode({
                editorNodeId,
                node.id,
                node.id,
                nodeSchema,
                defaultTitle,
                false,
                {},
                [&](int32_t slot, bool isInput) {
                    return makeNodeEditorPinId(node.id, slot, isInput);
                },
                [&](const ed::PinId &pinId, int32_t slot, bool isInput, const AnimationGraphSchema::AnimGraphPinSchema *pinSchema) {
                    pinByEditorId[pinId.Get()] = TransitionGraphPinEndpoint { node.id, slot, isInput, nodeSchema, pinSchema };
                },
                {},
                {
                    defaultTitle,
                    node.parameterName,
                    {},
                    {},
                    {},
                    node.floatValue,
                    node.boolValue,
                    node.synchronizeValue,
                    node.hasFloatValue,
                    node.hasBoolValue,
                    node.hasSynchronizeValue
                },
                {},
                {},
                [&](AnimationGraphSchema::FieldBinding binding) {
                    if (normalizedType != "transitionoutput") {
                        return false;
                    }
                    if (binding == AnimationGraphSchema::FieldBinding::BoolValue) {
                        return isInputDriven(node.id, 0);
                    }
                    if (binding == AnimationGraphSchema::FieldBinding::SynchronizeValue) {
                        return isInputDriven(node.id, 1);
                    }
                    if (binding == AnimationGraphSchema::FieldBinding::Duration) {
                        return isInputDriven(node.id, 2);
                    }
                    return false;
                },
                [&](const AnimationGraphInlineWidgets::SchemaInlineFieldState &fieldState) {
                    const ImVec2 graphPos = ed::GetNodePosition(editorNodeId);
                    updateNode(node,
                               fieldState.title.c_str(),
                               graphPos,
                               fieldState.parameterName.empty() ? nullptr : fieldState.parameterName.c_str(),
                               fieldState.floatValue,
                               fieldState.hasFloatValue,
                               fieldState.boolValue,
                               fieldState.hasBoolValue,
                               fieldState.synchronizeValue,
                               fieldState.hasSynchronizeValue,
                               isOutputNode(node));
                }
            });
        }

        for (const auto &link : transitionRecord.transitionGraphLinks) {
            const ed::LinkId editorLinkId = makeNodeEditorLinkId(link.id);
            linkIdByEditorId[editorLinkId.Get()] = link.id;
            ed::Link(editorLinkId,
                     makeNodeEditorPinId(link.fromNodeId, link.fromSlot, false),
                     makeNodeEditorPinId(link.toNodeId, link.toSlot, true),
                     ImVec4(0.50f, 0.70f, 0.93f, 0.95f),
                     2.0f);
        }

        if (ed::BeginCreate(ImVec4(0.72f, 0.82f, 0.95f, 1.0f), 2.0f)) {
            ed::PinId fromPin;
            ed::PinId toPin;
            if (ed::QueryNewLink(&fromPin, &toPin)) {
                AnimationGraphValidation::LinkValidationResult validation {};
                TransitionGraphPinEndpoint output {};
                TransitionGraphPinEndpoint input {};
                const auto fromIt = pinByEditorId.find(fromPin.Get());
                const auto toIt = pinByEditorId.find(toPin.Get());
                if (fromIt != pinByEditorId.end() && toIt != pinByEditorId.end() && fromIt->second.isInput != toIt->second.isInput) {
                    output = fromIt->second.isInput ? toIt->second : fromIt->second;
                    input = fromIt->second.isInput ? fromIt->second : toIt->second;
                    validation = AnimationGraphValidation::ValidateTransitionLink(
                        { output.nodeId, output.slot, false, false, output.nodeSchema, output.pinSchema },
                        { input.nodeId, input.slot, true, false, input.nodeSchema, input.pinSchema });
                } else {
                    validation.reason = "Transition graph links must connect one output pin to one input pin.";
                }
                if (validation.valid) {
                    if (ed::AcceptNewItem()) {
                        char outLinkId[64] = {0};
                        MCEEditorAddAnimationGraphStateMachineTransitionGraphLink(
                            hostContext.context,
                            hostContext.graphHandle.c_str(),
                            hostContext.stateMachineNodeId.c_str(),
                            transitionRecord.id.c_str(),
                            output.nodeId.c_str(),
                            output.slot,
                            input.nodeId.c_str(),
                            input.slot,
                            outLinkId,
                            sizeof(outLinkId));
                    }
                } else {
                    ed::RejectNewItem();
                }
            }
            bool transitionCanvasInteracted = false;
            AnimationGraphInteractionController::AcceptCreateFromPinRequest(pinByEditorId,
                                                                            popupRefs(),
                                                                            transitionCanvasInteracted);
            if (transitionCanvasInteracted && hostContext.panelState != nullptr) {
                hostContext.panelState->hasInteractedWithCanvas = true;
            }
        }
        ed::EndCreate();

        if (ed::BeginDelete()) {
            ed::LinkId deletedLink;
            while (ed::QueryDeletedLink(&deletedLink)) {
                const auto linkIt = linkIdByEditorId.find(deletedLink.Get());
                if (linkIt == linkIdByEditorId.end()) {
                    ed::RejectDeletedItem();
                    continue;
                }
                if (ed::AcceptDeletedItem()) {
                    MCEEditorRemoveAnimationGraphStateMachineTransitionGraphLink(
                        hostContext.context,
                        hostContext.graphHandle.c_str(),
                        hostContext.stateMachineNodeId.c_str(),
                        transitionRecord.id.c_str(),
                        linkIt->second.c_str());
                }
            }

            ed::NodeId deletedNode;
            while (ed::QueryDeletedNode(&deletedNode)) {
                const auto nodeIt = nodeIdByEditorId.find(deletedNode.Get());
                if (nodeIt == nodeIdByEditorId.end()) {
                    ed::RejectDeletedItem();
                    continue;
                }
                if (ed::AcceptDeletedItem()) {
                    MCEEditorRemoveAnimationGraphStateMachineTransitionGraphNode(
                        hostContext.context,
                        hostContext.graphHandle.c_str(),
                        hostContext.stateMachineNodeId.c_str(),
                        transitionRecord.id.c_str(),
                        nodeIt->second.c_str());
                }
            }
        }
        ed::EndDelete();

        bool transitionCanvasInteracted = false;
        AnimationGraphInteractionController::CaptureContextMenuRequests(
            popupRefs(),
            nodeIdByEditorId,
            pinByEditorId,
            linkIdByEditorId,
            transitionCanvasInteracted,
            popupIds.background.c_str(),
            popupIds.node.c_str(),
            popupIds.pin.c_str(),
            popupIds.link.c_str(),
            [&](const std::string &) {},
            [&](const std::string &linkId) {
                if (hostContext.panelState != nullptr) {
                    hostContext.panelState->selectedLinkId = linkId;
                }
            });
        if (transitionCanvasInteracted && hostContext.panelState != nullptr) {
            hostContext.panelState->hasInteractedWithCanvas = true;
        }

        ed::Suspend();
        if (ImGui::BeginDragDropTarget()) {
            auto addFromPayload = [&](const char *payloadText, bool isLocal) {
                if (!payloadText || payloadText[0] == 0) { return; }
                std::string value = payloadText;
                const size_t sep = value.find('|');
                if (sep == std::string::npos) { return; }
                const int32_t scalarType = static_cast<int32_t>(std::atoi(value.substr(0, sep).c_str()));
                const std::string name = value.substr(sep + 1);
                if (name.empty()) { return; }
                const ImVec2 graphPos = ed::ScreenToCanvas(ImGui::GetMousePos());
                const char *type = nullptr;
                const char *title = nullptr;
                if (!isLocal) {
                    switch (scalarType) {
                        case 0: type = "parameterFloat"; title = "Float Parameter"; break;
                        case 1: type = "parameterBool"; title = "Bool Parameter"; break;
                        case 2: type = "parameterInt"; title = "Int Parameter"; break;
                        case 3: type = "parameterTrigger"; title = "Trigger Parameter"; break;
                        default: break;
                    }
                } else {
                    switch (scalarType) {
                        case 0: type = "localFloat"; title = "Float Local"; break;
                        case 1: type = "localBool"; title = "Bool Local"; break;
                        case 2: type = "localInt"; title = "Int Local"; break;
                        default: break;
                    }
                }
                if (!type || !title) { return; }
                (void)addNode(type, title, graphPos, name.c_str(), 0.0f, false, false, false, false, false, false);
            };
            if (const ImGuiPayload *payload = ImGui::AcceptDragDropPayload("MCE_ANIM_GRAPH_INPUT_DEF")) {
                addFromPayload(static_cast<const char *>(payload->Data), false);
            }
            if (const ImGuiPayload *payload = ImGui::AcceptDragDropPayload("MCE_ANIM_GRAPH_LOCAL_DEF")) {
                addFromPayload(static_cast<const char *>(payload->Data), true);
            }
            ImGui::EndDragDropTarget();
        }

        auto transitionContextEndpoint = [&]() -> AnimationGraphValidation::PinEndpoint {
            AnimationGraphValidation::PinEndpoint endpoint {};
            if (editorState.contextPinNodeId.empty()) {
                return endpoint;
            }
            const auto pinIt = std::find_if(pinByEditorId.begin(),
                                            pinByEditorId.end(),
                                            [&](const auto &entry) {
                                                return entry.second.nodeId == editorState.contextPinNodeId &&
                                                    entry.second.slot == editorState.contextPinSlot &&
                                                    entry.second.isInput == editorState.contextPinIsInput;
                                            });
            if (pinIt == pinByEditorId.end()) {
                return endpoint;
            }
            endpoint.nodeId = pinIt->second.nodeId;
            endpoint.slot = pinIt->second.slot;
            endpoint.isInput = pinIt->second.isInput;
            endpoint.nodeSchema = pinIt->second.nodeSchema;
            endpoint.pinSchema = pinIt->second.pinSchema;
            return endpoint;
        };
        const AnimationGraphValidation::PinEndpoint contextEndpoint = transitionContextEndpoint();

        AnimationGraphInteractionController::DrawBackgroundContextMenu(popupRefs(),
                                                                       popupIds.background.c_str(),
                                                                       popupIds.createNode.c_str());
        AnimationGraphInteractionController::DrawNodeContextMenu(
            popupRefs(),
            popupIds.node.c_str(),
            [&]() {
                if (!editorState.contextNodeId.empty() && ImGui::MenuItem("Set As Output Node")) {
                    MCEEditorSetAnimationGraphStateMachineTransitionGraphOutputNode(
                        hostContext.context,
                        hostContext.graphHandle.c_str(),
                        hostContext.stateMachineNodeId.c_str(),
                        transitionRecord.id.c_str(),
                        editorState.contextNodeId.c_str());
                }
            },
            [&](const std::string &nodeId) {
                MCEEditorRemoveAnimationGraphStateMachineTransitionGraphNode(
                    hostContext.context,
                    hostContext.graphHandle.c_str(),
                    hostContext.stateMachineNodeId.c_str(),
                    transitionRecord.id.c_str(),
                    nodeId.c_str());
            });
        AnimationGraphInteractionController::DrawPinContextMenu(
            popupRefs(),
            popupIds.pin.c_str(),
            popupIds.createNode.c_str(),
            [&]() {
                const auto creatableSchemas =
                    AnimationGraphSchema::CreatableSchemasForDomain(AnimationGraphSchema::GraphDomain::Transition);
                return std::any_of(creatableSchemas.begin(),
                                   creatableSchemas.end(),
                                   [&](const AnimationGraphSchema::AnimGraphNodeSchema *schema) {
                                       return schema != nullptr &&
                                           AnimationGraphValidation::CanCreateTransitionNodeFromPin(contextEndpoint, *schema);
                                   });
            });
        AnimationGraphInteractionController::DrawLinkContextMenu(
            popupRefs(),
            popupIds.link.c_str(),
            []() {},
            [&](const std::string &linkId) {
                MCEEditorRemoveAnimationGraphStateMachineTransitionGraphLink(
                    hostContext.context,
                    hostContext.graphHandle.c_str(),
                    hostContext.stateMachineNodeId.c_str(),
                    transitionRecord.id.c_str(),
                    linkId.c_str());
            });

        AnimationGraphInteractionController::DrawSchemaCreateMenu(
            AnimationGraphSchema::GraphDomain::Transition,
            popupRefs(),
            popupIds.createNode.c_str(),
            nullptr,
            nullptr,
            0,
            "Add Transition Node",
            [&](const AnimationGraphSchema::AnimGraphNodeSchema &schema) {
                return !editorState.pendingCreateFromPin ||
                    AnimationGraphValidation::CanCreateTransitionNodeFromPin(contextEndpoint, schema);
            },
            [&](const AnimationGraphSchema::AnimGraphNodeSchema &schema) {
                const bool isOutput = AnimationGraphSchema::NormalizeTypeId(schema.typeId) ==
                    AnimationGraphSchema::NormalizeTypeId("transitionOutput");
                float floatValue = 0.0f;
                bool hasFloatValue = false;
                bool boolValue = false;
                bool hasBoolValue = false;
                bool synchronizeValue = false;
                bool hasSynchronizeValue = false;
                if (isOutput) {
                    floatValue = transitionRecord.duration;
                    hasFloatValue = true;
                    hasBoolValue = true;
                    hasSynchronizeValue = true;
                } else if (AnimationGraphSchema::NormalizeTypeId(schema.typeId) == AnimationGraphSchema::NormalizeTypeId("floatConstant")) {
                    hasFloatValue = true;
                } else if (AnimationGraphSchema::NormalizeTypeId(schema.typeId) == AnimationGraphSchema::NormalizeTypeId("boolConstant")) {
                    hasBoolValue = true;
                }

                const std::string createdNodeId = addNode(schema.typeId.c_str(),
                                                          schema.title.c_str(),
                                                          editorState.popupContext.openCanvasPos,
                                                          nullptr,
                                                          floatValue,
                                                          hasFloatValue,
                                                          boolValue,
                                                          hasBoolValue,
                                                          synchronizeValue,
                                                          hasSynchronizeValue,
                                                          isOutput);
                if (!editorState.pendingCreateFromPin || createdNodeId.empty()) {
                    return !createdNodeId.empty();
                }
                const int32_t compatibleSlot = AnimationGraphValidation::FirstCompatibleSlot(schema, contextEndpoint);
                if (compatibleSlot < 0) {
                    return !createdNodeId.empty();
                }
                char outLinkId[64] = {0};
                if (editorState.contextPinIsInput) {
                    MCEEditorAddAnimationGraphStateMachineTransitionGraphLink(
                        hostContext.context,
                        hostContext.graphHandle.c_str(),
                        hostContext.stateMachineNodeId.c_str(),
                        transitionRecord.id.c_str(),
                        createdNodeId.c_str(),
                        compatibleSlot,
                        editorState.contextPinNodeId.c_str(),
                        editorState.contextPinSlot,
                        outLinkId,
                        sizeof(outLinkId));
                } else {
                    MCEEditorAddAnimationGraphStateMachineTransitionGraphLink(
                        hostContext.context,
                        hostContext.graphHandle.c_str(),
                        hostContext.stateMachineNodeId.c_str(),
                        transitionRecord.id.c_str(),
                        editorState.contextPinNodeId.c_str(),
                        editorState.contextPinSlot,
                        createdNodeId.c_str(),
                        compatibleSlot,
                        outLinkId,
                        sizeof(outLinkId));
                }
                return true;
            });
        ed::Resume();

        for (const auto &node : transitionRecord.transitionGraphNodes) {
            const ed::NodeId nodeEditorId = makeNodeEditorNodeId(node.id);
            const ImVec2 editorPos = ed::GetNodePosition(nodeEditorId);
            if (fabsf(editorPos.x - node.position.x) > 0.001f || fabsf(editorPos.y - node.position.y) > 0.001f) {
                updateNode(node,
                           node.title.c_str(),
                           editorPos,
                           node.parameterName.empty() ? nullptr : node.parameterName.c_str(),
                           node.floatValue,
                           node.hasFloatValue,
                           node.boolValue,
                           node.hasBoolValue,
                           node.synchronizeValue,
                           node.hasSynchronizeValue,
                           isOutputNode(node));
            }
        }
    });

    ImGui::EndChild();
    return true;
}

} // namespace AnimationGraphTransitionGraphHost
