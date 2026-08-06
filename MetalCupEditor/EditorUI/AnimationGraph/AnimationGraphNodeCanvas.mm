#include "AnimationGraphNodeCanvas.h"

#include "AnimationGraphCanvasHost.h"
#include "AnimationGraphInteractionController.h"
#include "AnimationGraphInlineWidgets.h"
#include "AnimationGraphNodeEditorStore.h"
#include "AnimationGraphNodeRenderer.h"
#include "AnimationGraphSchema.h"
#include "AnimationGraphValidation.h"

#include "../../ImGui/imgui.h"
#include "../../ThirdParty/imgui-node-editor/imgui_node_editor.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

extern "C" uint32_t MCEEditorGetAssetsRootPath(void *context, char *buffer, int32_t bufferSize);
extern "C" int32_t MCEEditorGetAssetCount(void *context);
extern "C" uint32_t MCEEditorGetAssetAt(void *context, int32_t index,
                                        char *handleBuffer, int32_t handleBufferSize,
                                        int32_t *typeOut,
                                        char *pathBuffer, int32_t pathBufferSize,
                                        char *nameBuffer, int32_t nameBufferSize);
extern "C" uint32_t MCEEditorGetAssetDisplayName(void *context, const char *handle, char *buffer, int32_t bufferSize);
extern "C" uint32_t MCEEditorSetAnimationGraphBlend1DNode(void *context, const char *handle, const char *nodeId, const char *parameterName);
extern "C" uint32_t MCEEditorSetAnimationGraphBlend2DNode(void *context, const char *handle, const char *nodeId, const char *parameterXName, const char *parameterYName);
extern "C" uint32_t MCEEditorRemoveAnimationGraphLink(void *context, const char *handle, const char *linkId);
extern "C" uint32_t MCEEditorAddAnimationGraphLink(void *context, const char *handle, const char *fromNodeId, int32_t fromSlot, const char *toNodeId, int32_t toSlot, char *outLinkId, int32_t outLinkIdSize);
extern "C" uint32_t MCEEditorRemoveAnimationGraphNode(void *context, const char *handle, const char *nodeId);
extern "C" uint32_t MCEEditorAddAnimationGraphNode(void *context, const char *handle, int32_t type, const char *title, float posX, float posY, const char *clipHandle, char *outNodeId, int32_t outNodeIdSize);
extern "C" uint32_t MCEEditorSetAnimationGraphNodeParameterName(void *context, const char *handle, const char *nodeId, const char *parameterName);
extern "C" uint32_t MCEEditorSetAnimationGraphOutputNode(void *context, const char *handle, const char *nodeId);
extern "C" uint32_t MCEEditorUpdateAnimationGraphNode(void *context, const char *handle, const char *nodeId, const char *title, float posX, float posY, const char *clipHandle);

namespace {
    namespace ed = ax::NodeEditor;
    constexpr int32_t kAssetTypeAnimationClip = 9;

    struct AnimationClipOption {
        std::string handle;
        std::string label;
    };

    static std::vector<AnimationClipOption> CollectAnimationClipOptions(void *context) {
        std::vector<AnimationClipOption> options;
        const int32_t assetCount = MCEEditorGetAssetCount(context);
        if (assetCount <= 0) { return options; }
        options.reserve(static_cast<size_t>(assetCount));
        for (int32_t i = 0; i < assetCount; ++i) {
            char handle[64] = {0};
            char path[512] = {0};
            char name[128] = {0};
            int32_t type = -1;
            if (MCEEditorGetAssetAt(context,
                                    i,
                                    handle,
                                    sizeof(handle),
                                    &type,
                                    path,
                                    sizeof(path),
                                    name,
                                    sizeof(name)) == 0) {
                continue;
            }
            if (type != kAssetTypeAnimationClip || handle[0] == 0) { continue; }
            AnimationClipOption option;
            option.handle = handle;
            option.label = name[0] != 0 ? name : handle;
            options.push_back(option);
        }
        std::sort(options.begin(), options.end(), [](const AnimationClipOption &a, const AnimationClipOption &b) {
            return a.label < b.label;
        });
        return options;
    }

    static std::string ClipDisplayName(void *context, const std::string &clipHandle) {
        if (clipHandle.empty()) { return "<None>"; }
        char name[128] = {0};
        if (MCEEditorGetAssetDisplayName(context, clipHandle.c_str(), name, sizeof(name)) != 0 && name[0] != 0) {
            return name;
        }
        return clipHandle;
    }

    static bool IsWorkspaceRootNodeType(int32_t type) {
        return type == 2 || type == 3 || type == 4;
    }

    static std::vector<std::string> RootNodeSummaryLines(const AnimationGraphNodeRecord &node) {
        std::vector<std::string> lines;
        if (node.type == 1) {
            lines.push_back(node.clipHandle.empty() ? "Clip: <None>" : "Clip");
        } else if (node.type == 2) {
            lines.push_back("Open blend workspace");
            lines.push_back("Samples: " + std::to_string(node.blend1DSamples.size()));
            if (!node.blend1DParameterName.empty()) {
                lines.push_back("Input: " + node.blend1DParameterName);
            }
        } else if (node.type == 3) {
            lines.push_back("Open blend workspace");
            lines.push_back("Samples: " + std::to_string(node.blend2DSamples.size()));
            if (!node.blend2DParameterXName.empty() || !node.blend2DParameterYName.empty()) {
                const std::string xName = node.blend2DParameterXName.empty() ? "Unbound" : node.blend2DParameterXName;
                const std::string yName = node.blend2DParameterYName.empty() ? "Unbound" : node.blend2DParameterYName;
                lines.push_back("Inputs: " + xName + " / " + yName);
            }
        } else if (node.type == 4) {
            lines.push_back("Open state machine");
            lines.push_back("States: " + std::to_string(node.stateMachineStates.size()));
        } else if (node.type == 0) {
            lines.push_back("Final Output");
        }
        return lines;
    }

    struct AnimationGraphPinEndpoint {
        std::string nodeId;
        int32_t slot = 0;
        bool isInput = false;
        bool isSyntheticParameterNode = false;
        const AnimationGraphSchema::AnimGraphNodeSchema *nodeSchema = nullptr;
        const AnimationGraphSchema::AnimGraphPinSchema *pinSchema = nullptr;
    };

        static uintptr_t HashStableEditorId(const std::string &value) {
        uint64_t hash = 1469598103934665603ull;
        for (unsigned char c : value) {
            hash ^= static_cast<uint64_t>(c);
            hash *= 1099511628211ull;
        }
        hash &= 0x7fffffffffffffffull;
        if (hash == 0) { hash = 1; }
        return static_cast<uintptr_t>(hash);
    }

    static ed::NodeId MakeNodeEditorNodeId(const std::string &nodeId) {
        return ed::NodeId(HashStableEditorId(std::string("node|").append(nodeId)));
    }

    static ed::LinkId MakeNodeEditorLinkId(const std::string &linkId) {
        return ed::LinkId(HashStableEditorId(std::string("link|").append(linkId)));
    }

    static ed::PinId MakeNodeEditorPinId(const std::string &nodeId, int32_t slot, bool isInput) {
        std::string key = "pin|";
        key.append(nodeId);
        key.push_back('|');
        key.append(isInput ? "in|" : "out|");
        key.append(std::to_string(slot));
        return ed::PinId(HashStableEditorId(key));
    }

    static const AnimationGraphSchema::AnimGraphNodeSchema *NodeSchemaForType(int32_t type) {
        return AnimationGraphSchema::SchemaForRuntimeType(type);
    }

    static AnimationGraphInteractionController::PopupStateRefs PopupStateRefsForRoot(MCEPanelState::AnimationGraphPanelState &panelState) {
        return AnimationGraphInteractionController::PopupStateRefs {
            panelState.popupContext.openScreenPos,
            panelState.popupContext.openCanvasPos,
            panelState.popupContext.requestOpen,
            panelState.contextNodeId,
            panelState.contextLinkId,
            panelState.contextPinNodeId,
            panelState.contextPinSlot,
            panelState.contextPinIsInput,
            panelState.pendingCreateFromPin
        };
    }

    struct RootCanvasPopupIds {
        std::string background;
        std::string node;
        std::string pin;
        std::string link;
        std::string createNode;
        std::string search;
    };

    static RootCanvasPopupIds BuildRootCanvasPopupIds(const std::string &graphHandle) {
        const std::string scopeId = graphHandle.empty() ? "default" : graphHandle;
        return RootCanvasPopupIds {
            "RootCanvasBackgroundContext##" + scopeId,
            "RootCanvasNodeContext##" + scopeId,
            "RootCanvasPinContext##" + scopeId,
            "RootCanvasLinkContext##" + scopeId,
            "RootCanvasAddNode##" + scopeId,
            "##RootCanvasNodeSearch##" + scopeId
        };
    }

    static std::string AnimationGraphEditorSettingsPath(void *context, const std::string &graphHandle) {
        char assetsRoot[1024] = {0};
        if (MCEEditorGetAssetsRootPath(context, assetsRoot, sizeof(assetsRoot)) == 0 || assetsRoot[0] == 0) {
            return "";
        }
        std::string path = assetsRoot;
        if (!path.empty() && path.back() != '/') {
            path.push_back('/');
        }
        path.append(".node-editor-");
        path.append(graphHandle.empty() ? "default" : graphHandle);
        path.append(".json");
        return path;
    }

    static void DrawAnimationGraphNodeCanvasImpl(void *context,
                                             AnimationGraphSnapshot &snapshot,
                                             std::unordered_set<std::string> &selectedNodeIds,
                                             MCEPanelState::AnimationGraphPanelState &panelState,
                                             const AnimationGraphNodeCanvasScope *scope) {
        AnimationGraphNodeEditorState &editorState =
            AnimationGraphNodeEditorStore::EditorStateForGraph(panelState.activeGraphHandle);
        const RootCanvasPopupIds popupIds = BuildRootCanvasPopupIds(panelState.activeGraphHandle);
        if (editorState.context == nullptr) {
            editorState.settingsFilePath = AnimationGraphEditorSettingsPath(context, panelState.activeGraphHandle);
            ed::Config config {};
            config.SettingsFile = editorState.settingsFilePath.empty() ? nullptr : editorState.settingsFilePath.c_str();
            config.DragButtonIndex = 0;
            config.SelectButtonIndex = 0;
            config.NavigateButtonIndex = 1;
            config.ContextMenuButtonIndex = 1;
            config.EnableSmoothZoom = true;
            editorState.context = ed::CreateEditor(&config);
        }
        if (editorState.context == nullptr) { return; }

        auto isNodeVisible = [&](const std::string &nodeId) -> bool {
            if (scope == nullptr || !scope->enabled) { return true; }
            return scope->visibleNodeIds.count(nodeId) != 0;
        };

        std::unordered_map<std::string, AnimationGraphNodeRecord *> nodeById;
        nodeById.reserve(snapshot.nodes.size());
        for (auto &node : snapshot.nodes) {
            if (!isNodeVisible(node.id)) { continue; }
            nodeById[node.id] = &node;
        }
        std::unordered_map<std::string, AnimationGraphParameterRecord *> parameterByName;
        parameterByName.reserve(snapshot.parameters.size());
        for (auto &parameter : snapshot.parameters) {
            parameterByName[parameter.name] = &parameter;
        }
        auto parameterNodeIdForName = [](const std::string &name) -> std::string {
            return std::string("__param__|") + name;
        };
        auto parameterNameFromNodeId = [](const std::string &nodeId) -> std::string {
            static const std::string prefix = "__param__|";
            if (nodeId.rfind(prefix, 0) != 0) { return ""; }
            return nodeId.substr(prefix.size());
        };
        auto isParameterNodeId = [&](const std::string &nodeId) -> bool {
            return !parameterNameFromNodeId(nodeId).empty();
        };
        std::unordered_set<std::string> visibleParameterNames;
        std::unordered_set<std::string> visibleParameterNodeIds;
        if (scope != nullptr && scope->enabled) {
            for (const auto &node : snapshot.nodes) {
                if (!isNodeVisible(node.id)) { continue; }
                if (node.type == 2 && !node.blend1DParameterName.empty()) {
                    visibleParameterNames.insert(node.blend1DParameterName);
                } else if (node.type == 3) {
                    if (!node.blend2DParameterXName.empty()) {
                        visibleParameterNames.insert(node.blend2DParameterXName);
                    }
                    if (!node.blend2DParameterYName.empty()) {
                        visibleParameterNames.insert(node.blend2DParameterYName);
                    }
                }
            }
        }

        std::unordered_map<uintptr_t, std::string> nodeIdByEditorId;
        std::unordered_map<uintptr_t, std::string> linkIdByEditorId;
        std::unordered_map<uintptr_t, AnimationGraphPinEndpoint> pinByEditorId;

        AnimationGraphCanvasHost::DrawCanvas({editorState.context,
                                              "AnimationGraphNodeEditor",
                                              &editorState.didAutoFrame,
                                              &panelState.hasInteractedWithCanvas},
                                             [&]() {

        int parameterIndex = 0;
        for (const auto &parameter : snapshot.parameters) {
            if (scope != nullptr && scope->enabled && visibleParameterNames.count(parameter.name) == 0) {
                continue;
            }
            const std::string parameterNodeId = parameterNodeIdForName(parameter.name);
            visibleParameterNodeIds.insert(parameterNodeId);
            const ed::NodeId parameterEditorNodeId = MakeNodeEditorNodeId(parameterNodeId);
            nodeIdByEditorId[parameterEditorNodeId.Get()] = parameterNodeId;
            if (editorState.initializedParameterNodePositions.count(parameterNodeId) == 0) {
                const ImVec2 defaultPos = ImVec2(-480.0f, -160.0f + 56.0f * static_cast<float>(parameterIndex));
                const auto existingPosIt = editorState.parameterNodePositions.find(parameterNodeId);
                ed::SetNodePosition(parameterEditorNodeId, existingPosIt != editorState.parameterNodePositions.end() ? existingPosIt->second : defaultPos);
                editorState.initializedParameterNodePositions.insert(parameterNodeId);
            }
            ++parameterIndex;

            ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(0.73f, 0.83f, 0.96f, 1.0f));
            ImGui::PopStyleColor();
            const AnimationGraphSchema::AnimGraphNodeSchema *parameterSchema =
                AnimationGraphSchema::SchemaForParameterProxy(parameter.type);
            AnimationGraphNodeRenderer::RenderNode({
                parameterEditorNodeId,
                parameterNodeId,
                parameterNodeId,
                parameterSchema,
                parameter.name,
                false,
                { AnimationGraphSchema::ParameterTypeLabel(parameter.type) },
                [&](int32_t slot, bool isInput) {
                    return MakeNodeEditorPinId(parameterNodeId, slot, isInput);
                },
                [&](const ed::PinId &pinId, int32_t slot, bool isInput, const AnimationGraphSchema::AnimGraphPinSchema *pinSchema) {
                    pinByEditorId[pinId.Get()] = AnimationGraphPinEndpoint {
                        parameterNodeId,
                        slot,
                        isInput,
                        true,
                        parameterSchema,
                        pinSchema
                    };
                },
                {},
                {},
                {},
                {},
                {}
            });

            const ImVec2 paramNodePos = ed::GetNodePosition(parameterEditorNodeId);
            editorState.parameterNodePositions[parameterNodeId] = paramNodePos;
        }

        std::unordered_set<std::string> occupiedInputSlots;
        occupiedInputSlots.reserve(snapshot.links.size() * 2);
        auto inputSlotKey = [](const std::string &nodeId, int slot) {
            return nodeId + "|" + std::to_string(slot);
        };
        for (const auto &link : snapshot.links) {
            occupiedInputSlots.insert(inputSlotKey(link.toNodeId, link.toSlot));
        }
        for (const auto &node : snapshot.nodes) {
            if (node.type == 2 && !node.blend1DParameterName.empty()) {
                occupiedInputSlots.insert(inputSlotKey(node.id, 0));
            } else if (node.type == 3) {
                if (!node.blend2DParameterXName.empty()) {
                    occupiedInputSlots.insert(inputSlotKey(node.id, 0));
                }
                if (!node.blend2DParameterYName.empty()) {
                    occupiedInputSlots.insert(inputSlotKey(node.id, 1));
                }
            }
        }
        auto isInputSlotDriven = [&](const std::string &nodeId, int slot) {
            return occupiedInputSlots.count(inputSlotKey(nodeId, slot)) != 0;
        };
        auto updateNodeMetadata = [&](const AnimationGraphNodeRecord &nodeRecord) {
            MCEEditorUpdateAnimationGraphNode(context,
                                              panelState.activeGraphHandle.c_str(),
                                              nodeRecord.id.c_str(),
                                              nodeRecord.title.c_str(),
                                              nodeRecord.position.x,
                                              nodeRecord.position.y,
                                              nodeRecord.clipHandle.empty() ? nullptr : nodeRecord.clipHandle.c_str());
        };
        auto requestWorkspaceNavigationForNode = [&](const AnimationGraphNodeRecord *nodeRecord) {
            if (!nodeRecord) { return; }
            if (nodeRecord->type == 4) {
                panelState.pendingWorkspaceNavigationKind = MCEPanelState::AnimationGraphPanelState::WorkspaceNavigationStateMachine;
                panelState.pendingWorkspaceNodeId = nodeRecord->id;
                panelState.pendingWorkspaceStateId.clear();
                panelState.pendingWorkspaceTransitionId.clear();
            } else if (nodeRecord->type == 2 || nodeRecord->type == 3) {
                panelState.pendingWorkspaceNavigationKind = MCEPanelState::AnimationGraphPanelState::WorkspaceNavigationBlendSpace;
                panelState.pendingWorkspaceNodeId = nodeRecord->id;
                panelState.pendingWorkspaceStateId.clear();
                panelState.pendingWorkspaceTransitionId.clear();
            }
        };

        const std::vector<AnimationClipOption> clipOptions = CollectAnimationClipOptions(context);
        std::vector<AnimationGraphInlineWidgets::ClipOption> sharedClipOptions;
        sharedClipOptions.reserve(clipOptions.size());
        for (const auto &clip : clipOptions) {
            sharedClipOptions.push_back({clip.handle, clip.label});
        }
        for (auto &node : snapshot.nodes) {
            if (!isNodeVisible(node.id)) { continue; }
            const AnimationGraphSchema::AnimGraphNodeSchema *nodeSchema = NodeSchemaForType(node.type);
            const ed::NodeId nodeEditorId = MakeNodeEditorNodeId(node.id);
            nodeIdByEditorId[nodeEditorId.Get()] = node.id;

            if (editorState.initializedNodePositions.count(node.id) == 0) {
                ed::SetNodePosition(nodeEditorId, node.position);
                editorState.initializedNodePositions.insert(node.id);
            }

            const bool isWorkspaceRootNode = IsWorkspaceRootNodeType(node.type);
            std::vector<std::string> centerLines = RootNodeSummaryLines(node);

            AnimationGraphNodeRenderer::RenderNode({
                nodeEditorId,
                node.id,
                node.id,
                nodeSchema,
                node.title.empty() && nodeSchema ? nodeSchema->title : node.title,
                selectedNodeIds.count(node.id) != 0,
                centerLines,
                [&](int32_t slot, bool isInput) {
                    return MakeNodeEditorPinId(node.id, slot, isInput);
                },
                [&](const ed::PinId &pinId, int32_t slot, bool isInput, const AnimationGraphSchema::AnimGraphPinSchema *pinSchema) {
                    pinByEditorId[pinId.Get()] = AnimationGraphPinEndpoint {
                        node.id,
                        slot,
                        isInput,
                        false,
                        nodeSchema,
                        pinSchema
                    };
                },
                [&]() {
                    if (!isWorkspaceRootNode) {
                        return;
                    }
                    const std::string buttonLabel = std::string("Open##WorkspaceNodeOpen|").append(node.id);
                    if (ImGui::SmallButton(buttonLabel.c_str())) {
                        requestWorkspaceNavigationForNode(&node);
                    }
                },
                {
                    node.title,
                    node.blend1DParameterName,
                    node.blend2DParameterXName,
                    node.blend2DParameterYName,
                    node.clipHandle
                },
                {
                    false,
                    &sharedClipOptions,
                    [&](const std::string &clipHandle) {
                        return ClipDisplayName(context, clipHandle);
                    }
                },
                [&](AnimationGraphSchema::FieldBinding binding) {
                    switch (binding) {
                        case AnimationGraphSchema::FieldBinding::Title:
                            return true;
                        case AnimationGraphSchema::FieldBinding::ClipHandle:
                            return node.type == 1;
                        case AnimationGraphSchema::FieldBinding::ParameterName:
                            return false;
                        case AnimationGraphSchema::FieldBinding::ParameterXName:
                        case AnimationGraphSchema::FieldBinding::ParameterYName:
                            return false;
                        default:
                            return false;
                    }
                },
                [&](AnimationGraphSchema::FieldBinding binding) {
                    if (node.type == 2 && binding == AnimationGraphSchema::FieldBinding::ParameterName) {
                        return isInputSlotDriven(node.id, 0);
                    }
                    if (node.type == 3 && binding == AnimationGraphSchema::FieldBinding::ParameterXName) {
                        return isInputSlotDriven(node.id, 0);
                    }
                    if (node.type == 3 && binding == AnimationGraphSchema::FieldBinding::ParameterYName) {
                        return isInputSlotDriven(node.id, 1);
                    }
                    return false;
                },
                [&](const AnimationGraphInlineWidgets::SchemaInlineFieldState &fieldState) {
                    bool didUpdate = false;
                    if (node.title != fieldState.title) {
                        node.title = fieldState.title;
                        didUpdate = true;
                    }
                    if (node.clipHandle != fieldState.clipHandle) {
                        node.clipHandle = fieldState.clipHandle;
                        didUpdate = true;
                    }
                    if (node.type == 2 && node.blend1DParameterName != fieldState.parameterName) {
                        node.blend1DParameterName = fieldState.parameterName;
                        MCEEditorSetAnimationGraphBlend1DNode(context,
                                                              panelState.activeGraphHandle.c_str(),
                                                              node.id.c_str(),
                                                              node.blend1DParameterName.c_str());
                    }
                    if (node.type == 3 &&
                        (node.blend2DParameterXName != fieldState.parameterXName ||
                         node.blend2DParameterYName != fieldState.parameterYName)) {
                        node.blend2DParameterXName = fieldState.parameterXName;
                        node.blend2DParameterYName = fieldState.parameterYName;
                        MCEEditorSetAnimationGraphBlend2DNode(context,
                                                              panelState.activeGraphHandle.c_str(),
                                                              node.id.c_str(),
                                                              node.blend2DParameterXName.c_str(),
                                                              node.blend2DParameterYName.c_str());
                    }
                    if (didUpdate) {
                        updateNodeMetadata(node);
                    }
                }
            });
        }

        for (const auto &link : snapshot.links) {
            if (!isNodeVisible(link.fromNodeId) || !isNodeVisible(link.toNodeId)) {
                continue;
            }
            const ed::LinkId linkEditorId = MakeNodeEditorLinkId(link.id);
            const ed::PinId outputPinId = MakeNodeEditorPinId(link.fromNodeId, link.fromSlot, false);
            const ed::PinId inputPinId = MakeNodeEditorPinId(link.toNodeId, link.toSlot, true);
            linkIdByEditorId[linkEditorId.Get()] = link.id;
            int32_t sourceType = 0;
            auto sourceNodeIt = nodeById.find(link.fromNodeId);
            if (sourceNodeIt != nodeById.end() && sourceNodeIt->second != nullptr) {
                sourceType = sourceNodeIt->second->type;
            }
            const AnimationGraphSchema::AnimGraphNodeSchema *sourceSchema = NodeSchemaForType(sourceType);
            ed::Link(linkEditorId,
                     outputPinId,
                     inputPinId,
                     sourceSchema ? sourceSchema->style.linkTint : ImVec4(0.65f, 0.70f, 0.78f, 0.95f),
                     2.4f);
        }

        for (const auto &node : snapshot.nodes) {
            if (!isNodeVisible(node.id)) { continue; }
            if (node.type == 2 && !node.blend1DParameterName.empty()) {
                const std::string parameterNodeId = parameterNodeIdForName(node.blend1DParameterName);
                if (parameterByName.count(node.blend1DParameterName) != 0 &&
                    (scope == nullptr || !scope->enabled || visibleParameterNodeIds.count(parameterNodeId) != 0)) {
                    const std::string syntheticLinkId = std::string("paramlink|").append(node.blend1DParameterName).append("|").append(node.id).append("|0");
                    const ed::LinkId linkEditorId = MakeNodeEditorLinkId(syntheticLinkId);
                    const ed::PinId outputPinId = MakeNodeEditorPinId(parameterNodeId, 0, false);
                    const ed::PinId inputPinId = MakeNodeEditorPinId(node.id, 0, true);
                    linkIdByEditorId[linkEditorId.Get()] = syntheticLinkId;
                    ed::Link(linkEditorId, outputPinId, inputPinId, ImVec4(0.90f, 0.72f, 0.38f, 0.88f), 1.8f);
                }
            } else if (node.type == 3) {
                if (!node.blend2DParameterXName.empty() && parameterByName.count(node.blend2DParameterXName) != 0) {
                    const std::string parameterNodeId = parameterNodeIdForName(node.blend2DParameterXName);
                    if (scope == nullptr || !scope->enabled || visibleParameterNodeIds.count(parameterNodeId) != 0) {
                        const std::string syntheticLinkId = std::string("paramlink|").append(node.blend2DParameterXName).append("|").append(node.id).append("|0");
                        const ed::LinkId linkEditorId = MakeNodeEditorLinkId(syntheticLinkId);
                        const ed::PinId outputPinId = MakeNodeEditorPinId(parameterNodeId, 0, false);
                        const ed::PinId inputPinId = MakeNodeEditorPinId(node.id, 0, true);
                        linkIdByEditorId[linkEditorId.Get()] = syntheticLinkId;
                        ed::Link(linkEditorId, outputPinId, inputPinId, ImVec4(0.90f, 0.72f, 0.38f, 0.88f), 1.8f);
                    }
                }
                if (!node.blend2DParameterYName.empty() && parameterByName.count(node.blend2DParameterYName) != 0) {
                    const std::string parameterNodeId = parameterNodeIdForName(node.blend2DParameterYName);
                    if (scope == nullptr || !scope->enabled || visibleParameterNodeIds.count(parameterNodeId) != 0) {
                        const std::string syntheticLinkId = std::string("paramlink|").append(node.blend2DParameterYName).append("|").append(node.id).append("|1");
                        const ed::LinkId linkEditorId = MakeNodeEditorLinkId(syntheticLinkId);
                        const ed::PinId outputPinId = MakeNodeEditorPinId(parameterNodeId, 0, false);
                        const ed::PinId inputPinId = MakeNodeEditorPinId(node.id, 1, true);
                        linkIdByEditorId[linkEditorId.Get()] = syntheticLinkId;
                        ed::Link(linkEditorId, outputPinId, inputPinId, ImVec4(0.90f, 0.72f, 0.38f, 0.88f), 1.8f);
                    }
                }
            }
        }

        const ed::LinkId hoveredLink = ed::GetHoveredLink();
        if (hoveredLink) {
            ed::Flow(hoveredLink, ed::FlowDirection::Forward);
        }

        auto popupRefs = PopupStateRefsForRoot(panelState);
        if (ed::BeginCreate(ImVec4(0.72f, 0.82f, 0.95f, 1.0f), 2.2f)) {
            ed::PinId startPinId;
            ed::PinId endPinId;
            if (ed::QueryNewLink(&startPinId, &endPinId)) {
                AnimationGraphValidation::PinEndpoint outputEndpoint {};
                AnimationGraphValidation::PinEndpoint inputEndpoint {};
                AnimationGraphValidation::LinkValidationResult validation {};

                const auto startIt = pinByEditorId.find(startPinId.Get());
                const auto endIt = pinByEditorId.find(endPinId.Get());
                if (startIt != pinByEditorId.end() && endIt != pinByEditorId.end() && startIt->second.isInput != endIt->second.isInput) {
                    const AnimationGraphPinEndpoint &a = startIt->second;
                    const AnimationGraphPinEndpoint &b = endIt->second;
                    const AnimationGraphPinEndpoint &outputPin = a.isInput ? b : a;
                    const AnimationGraphPinEndpoint &inputPin = a.isInput ? a : b;
                    outputEndpoint = { outputPin.nodeId, outputPin.slot, false, outputPin.isSyntheticParameterNode, outputPin.nodeSchema, outputPin.pinSchema };
                    inputEndpoint = { inputPin.nodeId, inputPin.slot, true, inputPin.isSyntheticParameterNode, inputPin.nodeSchema, inputPin.pinSchema };
                    validation = AnimationGraphValidation::ValidateRootLink(outputEndpoint, inputEndpoint);
                } else {
                    validation.reason = "Root graph links must connect one output pin to one input pin.";
                }

                if (validation.valid) {
                    if (ed::AcceptNewItem(ImVec4(0.62f, 0.90f, 0.66f, 1.0f), 3.0f)) {
                        panelState.hasInteractedWithCanvas = true;
                        if (validation.parameterAssignment) {
                            auto targetNodeIt = nodeById.find(inputEndpoint.nodeId);
                            if (targetNodeIt != nodeById.end() && targetNodeIt->second != nullptr) {
                                AnimationGraphNodeRecord *targetNode = targetNodeIt->second;
                                const std::string parameterName = parameterNameFromNodeId(outputEndpoint.nodeId);
                                if (targetNode->type == 2) {
                                    targetNode->blend1DParameterName = parameterName;
                                    MCEEditorSetAnimationGraphBlend1DNode(context,
                                                                          panelState.activeGraphHandle.c_str(),
                                                                          targetNode->id.c_str(),
                                                                          targetNode->blend1DParameterName.c_str());
                                } else if (targetNode->type == 3) {
                                    if (inputEndpoint.slot == 0) {
                                        targetNode->blend2DParameterXName = parameterName;
                                    } else {
                                        targetNode->blend2DParameterYName = parameterName;
                                    }
                                    MCEEditorSetAnimationGraphBlend2DNode(context,
                                                                          panelState.activeGraphHandle.c_str(),
                                                                          targetNode->id.c_str(),
                                                                          targetNode->blend2DParameterXName.c_str(),
                                                                          targetNode->blend2DParameterYName.c_str());
                                }
                            }
                        } else {
                            for (const auto &existingLink : snapshot.links) {
                                if (existingLink.toNodeId == inputEndpoint.nodeId && existingLink.toSlot == inputEndpoint.slot) {
                                    MCEEditorRemoveAnimationGraphLink(context,
                                                                      panelState.activeGraphHandle.c_str(),
                                                                      existingLink.id.c_str());
                                    break;
                                }
                            }

                            char outLinkId[64] = {0};
                            if (MCEEditorAddAnimationGraphLink(context,
                                                               panelState.activeGraphHandle.c_str(),
                                                               outputEndpoint.nodeId.c_str(),
                                                               outputEndpoint.slot,
                                                               inputEndpoint.nodeId.c_str(),
                                                               inputEndpoint.slot,
                                                               outLinkId,
                                                               sizeof(outLinkId)) != 0) {
                                AnimationGraphLinkRecord newLink;
                                newLink.id = outLinkId;
                                newLink.fromNodeId = outputEndpoint.nodeId;
                                newLink.fromSlot = outputEndpoint.slot;
                                newLink.toNodeId = inputEndpoint.nodeId;
                                newLink.toSlot = inputEndpoint.slot;
                                snapshot.links.push_back(newLink);
                            }
                        }
                    }
                } else {
                    ed::RejectNewItem(ImVec4(0.95f, 0.45f, 0.45f, 1.0f), 2.5f);
                }
            }

            if (AnimationGraphInteractionController::AcceptCreateFromPinRequest(pinByEditorId,
                                                                                popupRefs,
                                                                                panelState.hasInteractedWithCanvas)) {
                panelState.requestNodeCreatePopup = true;
            }
        }
        ed::EndCreate();

        if (ed::BeginDelete()) {
            ed::LinkId deletedLink;
            while (ed::QueryDeletedLink(&deletedLink)) {
                auto linkIdIt = linkIdByEditorId.find(deletedLink.Get());
                if (linkIdIt == linkIdByEditorId.end()) {
                    ed::RejectDeletedItem();
                    continue;
                }
                if (ed::AcceptDeletedItem()) {
                    panelState.hasInteractedWithCanvas = true;
                    const bool isSyntheticParameterLink = linkIdIt->second.rfind("paramlink|", 0) == 0;
                    if (!isSyntheticParameterLink) {
                        MCEEditorRemoveAnimationGraphLink(context,
                                                          panelState.activeGraphHandle.c_str(),
                                                          linkIdIt->second.c_str());
                        snapshot.links.erase(std::remove_if(snapshot.links.begin(),
                                                            snapshot.links.end(),
                                                            [&](const AnimationGraphLinkRecord &link) { return link.id == linkIdIt->second; }),
                                             snapshot.links.end());
                    }
                }
            }

            ed::NodeId deletedNode;
            while (ed::QueryDeletedNode(&deletedNode)) {
                auto nodeIdIt = nodeIdByEditorId.find(deletedNode.Get());
                if (nodeIdIt == nodeIdByEditorId.end()) {
                    ed::RejectDeletedItem();
                    continue;
                }
                if (ed::AcceptDeletedItem()) {
                    panelState.hasInteractedWithCanvas = true;
                    if (!isParameterNodeId(nodeIdIt->second)) {
                        MCEEditorRemoveAnimationGraphNode(context,
                                                          panelState.activeGraphHandle.c_str(),
                                                          nodeIdIt->second.c_str());
                        selectedNodeIds.erase(nodeIdIt->second);
                        if (panelState.selectedNodeId == nodeIdIt->second) {
                            panelState.selectedNodeId.clear();
                        }
                    }
                }
            }
        }
        ed::EndDelete();

        if (!editorState.didAutoFrame) {
            ed::NavigateToContent(0.0f);
            editorState.didAutoFrame = true;
        }

        AnimationGraphInteractionController::CaptureContextMenuRequests(
            popupRefs,
            nodeIdByEditorId,
            pinByEditorId,
            linkIdByEditorId,
            panelState.hasInteractedWithCanvas,
            popupIds.background.c_str(),
            popupIds.node.c_str(),
            popupIds.pin.c_str(),
            popupIds.link.c_str(),
            [&](const std::string &nodeId) {
                if (!nodeId.empty() && !isParameterNodeId(nodeId)) {
                    panelState.selectedNodeId = nodeId;
                }
            },
            [&](const std::string &linkId) {
                if (!linkId.empty()) {
                    panelState.selectedLinkId = linkId;
                }
            });

        ed::Suspend();
        if (ImGui::BeginDragDropTarget()) {
            auto spawnBoundNodeFromPayload = [&](const char *payloadText, bool isLocal) {
                if (!payloadText || payloadText[0] == 0) { return; }
                std::string value = payloadText;
                const size_t sep = value.find('|');
                if (sep == std::string::npos) { return; }
                const int32_t scalarType = static_cast<int32_t>(std::atoi(value.substr(0, sep).c_str()));
                const std::string name = value.substr(sep + 1);
                if (name.empty()) { return; }
                const ImVec2 graphPos = ed::ScreenToCanvas(ImGui::GetMousePos());
                int32_t nodeType = -1;
                if (!isLocal) {
                    switch (scalarType) {
                        case 0: nodeType = 8; break;  // parameterFloat
                        case 1: nodeType = 9; break;  // parameterBool
                        case 2: nodeType = 20; break; // parameterInt
                        case 3: nodeType = 10; break; // parameterTrigger
                        default: break;
                    }
                } else {
                    switch (scalarType) {
                        case 0: nodeType = 21; break; // localFloat
                        case 1: nodeType = 22; break; // localBool
                        case 2: nodeType = 23; break; // localInt
                        default: break;
                    }
                }
                if (nodeType < 0) { return; }
                char outNodeId[64] = {0};
                if (MCEEditorAddAnimationGraphNode(context,
                                                   panelState.activeGraphHandle.c_str(),
                                                   nodeType,
                                                   nullptr,
                                                   graphPos.x,
                                                   graphPos.y,
                                                   nullptr,
                                                   outNodeId,
                                                   sizeof(outNodeId)) != 0) {
                    MCEEditorSetAnimationGraphNodeParameterName(context,
                                                                panelState.activeGraphHandle.c_str(),
                                                                outNodeId,
                                                                name.c_str());
                    panelState.selectedNodeId = outNodeId;
                    panelState.hasInteractedWithCanvas = true;
                }
            };
            auto spawnClipNodeFromPayload = [&](const char *clipHandle) {
                if (!clipHandle || clipHandle[0] == 0) { return; }
                const ImVec2 graphPos = ed::ScreenToCanvas(ImGui::GetMousePos());
                char outNodeId[64] = {0};
                if (MCEEditorAddAnimationGraphNode(context,
                                                   panelState.activeGraphHandle.c_str(),
                                                   1,
                                                   nullptr,
                                                   graphPos.x,
                                                   graphPos.y,
                                                   clipHandle,
                                                   outNodeId,
                                                   sizeof(outNodeId)) != 0) {
                    panelState.selectedNodeId = outNodeId;
                    panelState.hasInteractedWithCanvas = true;
                }
            };
            if (const ImGuiPayload *payload = ImGui::AcceptDragDropPayload("MCE_ANIM_GRAPH_INPUT_DEF")) {
                const char *payloadText = static_cast<const char *>(payload->Data);
                spawnBoundNodeFromPayload(payloadText, false);
            }
            if (const ImGuiPayload *payload = ImGui::AcceptDragDropPayload("MCE_ANIM_GRAPH_LOCAL_DEF")) {
                const char *payloadText = static_cast<const char *>(payload->Data);
                spawnBoundNodeFromPayload(payloadText, true);
            }
            if (const ImGuiPayload *payload = ImGui::AcceptDragDropPayload("MCE_ASSET_ANIMATION_CLIP")) {
                const char *clipHandle = static_cast<const char *>(payload->Data);
                spawnClipNodeFromPayload(clipHandle);
            }
            ImGui::EndDragDropTarget();
        }
        auto rootContextEndpoint = [&]() -> AnimationGraphValidation::PinEndpoint {
            AnimationGraphValidation::PinEndpoint endpoint {};
            if (panelState.contextPinNodeId.empty()) {
                return endpoint;
            }
            endpoint.nodeId = panelState.contextPinNodeId;
            endpoint.slot = panelState.contextPinSlot;
            endpoint.isInput = panelState.contextPinIsInput;
            endpoint.isSyntheticParameterNode = isParameterNodeId(panelState.contextPinNodeId);
            if (endpoint.isSyntheticParameterNode) {
                const std::string parameterName = parameterNameFromNodeId(panelState.contextPinNodeId);
                auto parameterIt = parameterByName.find(parameterName);
                if (parameterIt != parameterByName.end() && parameterIt->second != nullptr) {
                    endpoint.nodeSchema = AnimationGraphSchema::SchemaForParameterProxy(parameterIt->second->type);
                }
            } else {
                auto nodeIt = nodeById.find(panelState.contextPinNodeId);
                if (nodeIt != nodeById.end() && nodeIt->second != nullptr) {
                    endpoint.nodeSchema = NodeSchemaForType(nodeIt->second->type);
                }
            }
            if (endpoint.nodeSchema != nullptr) {
                endpoint.pinSchema = AnimationGraphSchema::PinAt(*endpoint.nodeSchema,
                                                                endpoint.isInput ? AnimationGraphSchema::PinDirection::Input
                                                                                 : AnimationGraphSchema::PinDirection::Output,
                                                                endpoint.slot);
            }
            return endpoint;
        };
        const AnimationGraphValidation::PinEndpoint contextEndpoint = rootContextEndpoint();

        AnimationGraphInteractionController::DrawNodeContextMenu(
            popupRefs,
            popupIds.node.c_str(),
            [&]() {
                if (panelState.contextNodeId.empty()) {
                    return;
                }
                if (isParameterNodeId(panelState.contextNodeId)) {
                    const std::string parameterName = parameterNameFromNodeId(panelState.contextNodeId);
                    if (!parameterName.empty()) {
                        ImGui::TextDisabled("Input: %s", parameterName.c_str());
                    }
                    return;
                }
                const auto selectedNodeIt = nodeById.find(panelState.contextNodeId);
                const AnimationGraphNodeRecord *selectedNodeRecord = (selectedNodeIt != nodeById.end()) ? selectedNodeIt->second : nullptr;
                const bool supportsWorkspaceEdit = (selectedNodeRecord != nullptr) &&
                    (selectedNodeRecord->type == 2 || selectedNodeRecord->type == 3 || selectedNodeRecord->type == 4);
                if (supportsWorkspaceEdit && ImGui::MenuItem("Edit Workspace")) {
                    requestWorkspaceNavigationForNode(selectedNodeRecord);
                }
                if (ImGui::MenuItem("Set As Output")) {
                    MCEEditorSetAnimationGraphOutputNode(context,
                                                         panelState.activeGraphHandle.c_str(),
                                                         panelState.contextNodeId.c_str());
                }
            },
            [&](const std::string &nodeId) {
                if (isParameterNodeId(nodeId)) {
                    return;
                }
                MCEEditorRemoveAnimationGraphNode(context,
                                                  panelState.activeGraphHandle.c_str(),
                                                  nodeId.c_str());
                selectedNodeIds.erase(nodeId);
                if (panelState.selectedNodeId == nodeId) {
                    panelState.selectedNodeId.clear();
                }
            });

        AnimationGraphInteractionController::DrawPinContextMenu(
            popupRefs,
            popupIds.pin.c_str(),
            popupIds.createNode.c_str(),
            [&]() {
                const auto creatableSchemas =
                    AnimationGraphSchema::CreatableSchemasForDomain(AnimationGraphSchema::GraphDomain::Root);
                return std::any_of(creatableSchemas.begin(),
                                   creatableSchemas.end(),
                                   [&](const AnimationGraphSchema::AnimGraphNodeSchema *schema) {
                                       return schema != nullptr &&
                                           AnimationGraphValidation::CanCreateRootNodeFromPin(contextEndpoint, *schema);
                                   });
            });

        AnimationGraphInteractionController::DrawLinkContextMenu(
            popupRefs,
            popupIds.link.c_str(),
            [&]() {
                if (!panelState.contextLinkId.empty() && panelState.contextLinkId.rfind("paramlink|", 0) == 0) {
                    ImGui::TextDisabled("Synthetic parameter binding");
                    ImGui::Separator();
                }
            },
            [&](const std::string &linkId) {
                const bool isSyntheticParameterLink = linkId.rfind("paramlink|", 0) == 0;
                if (!isSyntheticParameterLink) {
                    MCEEditorRemoveAnimationGraphLink(context,
                                                      panelState.activeGraphHandle.c_str(),
                                                      linkId.c_str());
                    snapshot.links.erase(std::remove_if(snapshot.links.begin(),
                                                        snapshot.links.end(),
                                                        [&](const AnimationGraphLinkRecord &link) { return link.id == linkId; }),
                                         snapshot.links.end());
                }
                panelState.selectedLinkId.clear();
            });

        AnimationGraphInteractionController::DrawBackgroundContextMenu(popupRefs,
                                                                       popupIds.background.c_str(),
                                                                       popupIds.createNode.c_str());

        if (panelState.requestNodeCreatePopup) {
            ImGui::OpenPopup(popupIds.createNode.c_str());
            panelState.requestNodeCreatePopup = false;
            panelState.nodeSearchFilter[0] = 0;
        }
        AnimationGraphInteractionController::DrawSchemaCreateMenu(
            AnimationGraphSchema::GraphDomain::Root,
            popupRefs,
            popupIds.createNode.c_str(),
            popupIds.search.c_str(),
            panelState.nodeSearchFilter,
            sizeof(panelState.nodeSearchFilter),
            nullptr,
            [&](const AnimationGraphSchema::AnimGraphNodeSchema &schema) {
                return !panelState.pendingCreateFromPin ||
                    AnimationGraphValidation::CanCreateRootNodeFromPin(contextEndpoint, schema);
            },
            [&](const AnimationGraphSchema::AnimGraphNodeSchema &schema) {
                char newNodeId[64] = {0};
                const ImVec2 popupCanvasPos = panelState.popupContext.openCanvasPos;
                if (MCEEditorAddAnimationGraphNode(context,
                                                   panelState.activeGraphHandle.c_str(),
                                                   schema.runtimeType,
                                                   nullptr,
                                                   popupCanvasPos.x,
                                                   popupCanvasPos.y,
                                                   nullptr,
                                                   newNodeId,
                                                   sizeof(newNodeId)) == 0) {
                    return false;
                }
                panelState.selectedNodeId = newNodeId;
                selectedNodeIds.clear();
                selectedNodeIds.insert(panelState.selectedNodeId);

                if (panelState.pendingCreateFromPin && !panelState.contextPinNodeId.empty()) {
                    char outLinkId[64] = {0};
                    if (contextEndpoint.isSyntheticParameterNode && !contextEndpoint.isInput) {
                        const std::string parameterName = parameterNameFromNodeId(panelState.contextPinNodeId);
                        if (schema.runtimeType == 2) {
                            MCEEditorSetAnimationGraphBlend1DNode(context,
                                                                  panelState.activeGraphHandle.c_str(),
                                                                  newNodeId,
                                                                  parameterName.c_str());
                        } else if (schema.runtimeType == 3) {
                            MCEEditorSetAnimationGraphBlend2DNode(context,
                                                                  panelState.activeGraphHandle.c_str(),
                                                                  newNodeId,
                                                                  parameterName.c_str(),
                                                                  parameterName.c_str());
                        }
                    } else if (panelState.contextPinIsInput) {
                        MCEEditorAddAnimationGraphLink(context,
                                                       panelState.activeGraphHandle.c_str(),
                                                       newNodeId,
                                                       0,
                                                       panelState.contextPinNodeId.c_str(),
                                                       panelState.contextPinSlot,
                                                       outLinkId,
                                                       sizeof(outLinkId));
                    } else {
                        MCEEditorAddAnimationGraphLink(context,
                                                       panelState.activeGraphHandle.c_str(),
                                                       panelState.contextPinNodeId.c_str(),
                                                       panelState.contextPinSlot,
                                                       newNodeId,
                                                       0,
                                                       outLinkId,
                                                       sizeof(outLinkId));
                    }
                }
                return true;
            });
        const bool isAnyEditorPopupOpen =
            AnimationGraphInteractionController::AnyPopupOpen({
                popupIds.createNode.c_str(),
                popupIds.node.c_str(),
                popupIds.pin.c_str(),
                popupIds.link.c_str(),
                popupIds.background.c_str()
            });
        ed::Resume();

        // Keep node editor interactions from stealing input while context/create popups are active.
        if (isAnyEditorPopupOpen) {
            for (auto &node : snapshot.nodes) {
                if (!isNodeVisible(node.id)) { continue; }
                const ed::NodeId nodeEditorId = MakeNodeEditorNodeId(node.id);
                const ImVec2 editorPos = ed::GetNodePosition(nodeEditorId);
                if (fabsf(editorPos.x - node.position.x) > 0.001f || fabsf(editorPos.y - node.position.y) > 0.001f) {
                    panelState.hasInteractedWithCanvas = true;
                    node.position = editorPos;
                    MCEEditorUpdateAnimationGraphNode(context,
                                                      panelState.activeGraphHandle.c_str(),
                                                      node.id.c_str(),
                                                      node.title.c_str(),
                                                      node.position.x,
                                                      node.position.y,
                                                      node.clipHandle.empty() ? nullptr : node.clipHandle.c_str());
                }
            }
            return;
        }

        const ed::NodeId doubleClickedNode = ed::GetDoubleClickedNode();
        if (doubleClickedNode) {
            panelState.hasInteractedWithCanvas = true;
            auto nodeIdIt = nodeIdByEditorId.find(doubleClickedNode.Get());
            if (nodeIdIt != nodeIdByEditorId.end() && !isParameterNodeId(nodeIdIt->second)) {
                panelState.selectedNodeId = nodeIdIt->second;
                const auto selectedNodeIt = nodeById.find(nodeIdIt->second);
                const AnimationGraphNodeRecord *selectedNodeRecord = (selectedNodeIt != nodeById.end()) ? selectedNodeIt->second : nullptr;
                if (selectedNodeRecord != nullptr && (selectedNodeRecord->type == 2 || selectedNodeRecord->type == 3 || selectedNodeRecord->type == 4)) {
                    requestWorkspaceNavigationForNode(selectedNodeRecord);
                }
            }
        }

        std::vector<ed::NodeId> selectedEditorNodes(snapshot.nodes.size());
        const int selectedCount = selectedEditorNodes.empty() ? 0 : ed::GetSelectedNodes(selectedEditorNodes.data(), static_cast<int>(selectedEditorNodes.size()));
        selectedNodeIds.clear();
        for (int i = 0; i < selectedCount; ++i) {
            auto it = nodeIdByEditorId.find(selectedEditorNodes[static_cast<size_t>(i)].Get());
            if (it != nodeIdByEditorId.end() && !isParameterNodeId(it->second)) {
                selectedNodeIds.insert(it->second);
            }
        }
        if (!selectedNodeIds.empty()) {
            panelState.selectedNodeId = *selectedNodeIds.begin();
            panelState.hasInteractedWithCanvas = true;
        } else {
            panelState.selectedNodeId.clear();
        }

        for (auto &node : snapshot.nodes) {
            if (!isNodeVisible(node.id)) { continue; }
            const ed::NodeId nodeEditorId = MakeNodeEditorNodeId(node.id);
            const ImVec2 editorPos = ed::GetNodePosition(nodeEditorId);
            if (fabsf(editorPos.x - node.position.x) > 0.001f || fabsf(editorPos.y - node.position.y) > 0.001f) {
                panelState.hasInteractedWithCanvas = true;
                node.position = editorPos;
                MCEEditorUpdateAnimationGraphNode(context,
                                                  panelState.activeGraphHandle.c_str(),
                                                  node.id.c_str(),
                                                  node.title.c_str(),
                                                  node.position.x,
                                                  node.position.y,
                                                  node.clipHandle.empty() ? nullptr : node.clipHandle.c_str());
            }
        }
        });
}
}

void DrawAnimationGraphNodeCanvas(void *context,
                                  AnimationGraphSnapshot &snapshot,
                                  std::unordered_set<std::string> &selectedNodeIds,
                                  MCEPanelState::AnimationGraphPanelState &panelState,
                                  const AnimationGraphNodeCanvasScope *scope) {
    DrawAnimationGraphNodeCanvasImpl(context, snapshot, selectedNodeIds, panelState, scope);
}

void DrawAnimationGraphNodeCreatePopup(void *context,
                                       AnimationGraphSnapshot &snapshot,
                                       std::unordered_set<std::string> &selectedNodeIds,
                                       MCEPanelState::AnimationGraphPanelState &panelState,
                                       const AnimationGraphNodeCanvasScope *scope) {
    (void)context;
    (void)snapshot;
    (void)selectedNodeIds;
    (void)panelState;
    (void)scope;
}
