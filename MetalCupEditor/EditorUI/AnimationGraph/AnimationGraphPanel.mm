#include "AnimationGraphPanel.h"

#include "AnimationGraphBlendSpaceWorkspace.h"
#include "AnimationGraphModels.h"
#include "AnimationGraphNodeCanvas.h"
#include "AnimationGraphNodeEditorStore.h"
#include "AnimationGraphSidebar.h"
#include "AnimationGraphStateMachineWorkspace.h"
#include "AnimationGraphTransitionGraphHost.h"
#include "AnimationGraphUIStateStore.h"
#include "AnimationGraphWorkspaceRouter.h"

#include "../Widgets/UIWidgets.h"
#include "../../ImGui/imgui.h"

#include <algorithm>
#include <cctype>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace AnimationGraphBreadcrumbs {
void DrawWorkspaceBreadcrumbs(const std::string &graphHandle,
                              const AnimationGraphWorkspacePath &path,
                              const AnimationGraphSnapshot &snapshot);
}

namespace {
void DrawWorkspaceBanner(const char *title, const char *subtitle) {
    ImDrawList *draw = ImGui::GetWindowDrawList();
    const ImVec2 start = ImGui::GetCursorScreenPos();
    const float width = ImGui::GetContentRegionAvail().x;
    const ImVec2 size(width, 52.0f);
    draw->AddRectFilled(start, ImVec2(start.x + size.x, start.y + size.y), IM_COL32(24, 27, 32, 255), 8.0f);
    draw->AddRect(start, ImVec2(start.x + size.x, start.y + size.y), IM_COL32(56, 63, 74, 255), 8.0f, 0, 1.0f);
    draw->AddText(ImVec2(start.x + 14.0f, start.y + 10.0f), IM_COL32(226, 232, 240, 245), title);
    draw->AddText(ImVec2(start.x + 14.0f, start.y + 28.0f), IM_COL32(148, 158, 174, 230), subtitle);
    ImGui::Dummy(size);
}

const AnimationGraphNodeRecord *FindNodeById(const AnimationGraphSnapshot &snapshot, const std::string &nodeId) {
    for (const auto &node : snapshot.nodes) {
        if (node.id == nodeId) { return &node; }
    }
    return nullptr;
}

const AnimationGraphNodeRecord::StateMachineStateRecord *FindStateInMachine(const AnimationGraphNodeRecord &machineNode,
                                                                             const std::string &stateId) {
    for (const auto &state : machineNode.stateMachineStates) {
        if (state.id == stateId) { return &state; }
    }
    return nullptr;
}

const AnimationGraphNodeRecord::StateMachineTransitionRecord *FindTransitionInMachine(const AnimationGraphNodeRecord &machineNode,
                                                                                       const std::string &transitionId) {
    for (const auto &transition : machineNode.stateMachineTransitions) {
        if (transition.id == transitionId) { return &transition; }
    }
    return nullptr;
}

std::unordered_map<std::string, const AnimationGraphNodeRecord *> BuildNodeRecordLookup(const AnimationGraphSnapshot &snapshot) {
    std::unordered_map<std::string, const AnimationGraphNodeRecord *> byId;
    byId.reserve(snapshot.nodes.size());
    for (const auto &node : snapshot.nodes) {
        byId.emplace(node.id, &node);
    }
    return byId;
}

void CollectConnectedNodesFromSeed(const AnimationGraphSnapshot &snapshot,
                                   const std::unordered_map<std::string, const AnimationGraphNodeRecord *> &nodeById,
                                   const std::string &seedNodeId,
                                   std::unordered_set<std::string> &outNodeIds) {
    if (seedNodeId.empty() || nodeById.count(seedNodeId) == 0) {
        return;
    }
    std::vector<std::string> stack;
    stack.push_back(seedNodeId);
    while (!stack.empty()) {
        const std::string nodeId = stack.back();
        stack.pop_back();
        if (!outNodeIds.insert(nodeId).second) {
            continue;
        }
        for (const auto &link : snapshot.links) {
            if (link.fromNodeId == nodeId && outNodeIds.count(link.toNodeId) == 0) {
                stack.push_back(link.toNodeId);
            }
            if (link.toNodeId == nodeId && outNodeIds.count(link.fromNodeId) == 0) {
                stack.push_back(link.fromNodeId);
            }
        }
    }
}

std::unordered_set<std::string> CollectStateSubgraphNodeIds(const AnimationGraphSnapshot &snapshot,
                                                            const std::unordered_map<std::string, const AnimationGraphNodeRecord *> &nodeById) {
    std::unordered_set<std::string> subgraphNodeIds;
    for (const auto &node : snapshot.nodes) {
        if (node.type != 4) { continue; }
        for (const auto &state : node.stateMachineStates) {
            if (state.nodeRefId.empty()) { continue; }
            CollectConnectedNodesFromSeed(snapshot, nodeById, state.nodeRefId, subgraphNodeIds);
        }
    }
    // Keep root graph anchors available in root workspace even if links touch a subgraph component.
    for (const auto &node : snapshot.nodes) {
        if (node.type == 0 || node.type == 4) {
            subgraphNodeIds.erase(node.id);
        }
    }
    return subgraphNodeIds;
}

AnimationGraphNodeCanvasScope BuildRootWorkspaceScope(const AnimationGraphSnapshot &snapshot) {
    AnimationGraphNodeCanvasScope scope;
    scope.enabled = true;
    const auto nodeById = BuildNodeRecordLookup(snapshot);
    const auto subgraphNodeIds = CollectStateSubgraphNodeIds(snapshot, nodeById);
    for (const auto &node : snapshot.nodes) {
        if (subgraphNodeIds.count(node.id) == 0) {
            scope.visibleNodeIds.insert(node.id);
        }
    }
    if (scope.visibleNodeIds.empty()) {
        for (const auto &node : snapshot.nodes) {
            scope.visibleNodeIds.insert(node.id);
        }
    }
    return scope;
}

AnimationGraphNodeCanvasScope BuildStateSubgraphWorkspaceScope(const AnimationGraphSnapshot &snapshot,
                                                               const std::string &seedNodeId,
                                                               const std::string &selectedNodeId) {
    AnimationGraphNodeCanvasScope scope;
    scope.enabled = true;
    const auto nodeById = BuildNodeRecordLookup(snapshot);
    CollectConnectedNodesFromSeed(snapshot, nodeById, seedNodeId, scope.visibleNodeIds);
    if (!selectedNodeId.empty()) {
        CollectConnectedNodesFromSeed(snapshot, nodeById, selectedNodeId, scope.visibleNodeIds);
    }
    if (scope.visibleNodeIds.empty()) {
        scope.enabled = false;
    }
    return scope;
}
}

void DrawAnimationGraphPanel(void *context,
                             MCEPanelState::AnimationGraphPanelState &state,
                             const char *selectedEntityId,
                             bool *isOpen) {
    if (!isOpen || !*isOpen) { return; }

    static std::string previousGraphHandle;
    if (previousGraphHandle != state.activeGraphHandle) {
        if (state.activeGraphHandle.empty()) {
            AnimationGraphUIStateStore::PruneStateToActiveGraph("");
        }
        previousGraphHandle = state.activeGraphHandle;
    }

    if (!EditorUI::BeginPanel("Animation Graph", isOpen)) {
        EditorUI::EndPanel();
        return;
    }

    if (state.activeGraphHandle.empty()) {
        DrawWorkspaceBanner("Animation Graph", "Open a graph asset from the content browser to edit it here.");
        EditorUI::EndPanel();
        return;
    }

    AnimationGraphSnapshot snapshot;
    if (!LoadAnimationGraphSnapshot(context, state.activeGraphHandle, snapshot)) {
        DrawWorkspaceBanner("Animation Graph", "The selected graph could not be loaded.");
        EditorUI::EndPanel();
        return;
    }
    AnimationGraphRuntimeDebugSnapshot runtimeDebugSnapshot;
    const bool hasRuntimeDebugSnapshot = LoadAnimationGraphRuntimeDebugSnapshot(context,
                                                                                 selectedEntityId,
                                                                                 snapshot,
                                                                                 state.activeGraphHandle,
                                                                                 state.showRuntimeDebug,
                                                                                 runtimeDebugSnapshot);
    auto transitionGraphRendererForNode = [&](const std::string &stateMachineNodeId) -> AnimationGraphTransitionCanvasRenderer {
        AnimationGraphTransitionGraphHostContext hostContext {
            context,
            state.activeGraphHandle,
            stateMachineNodeId,
            &state
        };
        return [hostContext](const AnimationGraphNodeRecord::StateMachineTransitionRecord &transitionRecord, const char *canvasId) {
            return AnimationGraphTransitionGraphHost::DrawTransitionGraphCanvas(hostContext, transitionRecord, canvasId);
        };
    };

    std::unordered_set<std::string> &selectedNodeIds = AnimationGraphNodeEditorStore::SelectedNodeSetForGraph(state.activeGraphHandle);
    AnimationGraphWorkspacePath &workspacePath = AnimationGraphWorkspaceRouter::GetWorkspacePath(state.activeGraphHandle);
    AnimationGraphBreadcrumbs::DrawWorkspaceBreadcrumbs(state.activeGraphHandle, workspacePath, snapshot);

    const AnimationGraphWorkspaceDescriptor &workspace = AnimationGraphWorkspaceRouter::GetCurrentWorkspace(state.activeGraphHandle);
    if (workspace.kind != AnimationGraphWorkspaceKind::RootGraph) {
        switch (workspace.kind) {
            case AnimationGraphWorkspaceKind::StateMachine:
                DrawAnimationGraphStateMachineWorkspace(context,
                                                        snapshot,
                                                        workspace,
                                                        state,
                                                        (hasRuntimeDebugSnapshot && state.showRuntimeDebug) ? &runtimeDebugSnapshot : nullptr,
                                                        transitionGraphRendererForNode(workspace.nodeId));
                break;
            case AnimationGraphWorkspaceKind::StateSubgraph: {
                const auto *machineNode = FindNodeById(snapshot, workspace.nodeId);
                const auto *stateRecord = machineNode ? FindStateInMachine(*machineNode, workspace.stateId) : nullptr;
                ImGui::SeparatorText("State Subgraph");
                if (!machineNode || !stateRecord) {
                    ImGui::TextDisabled("State reference is missing.");
                    break;
                }
                ImGui::Text("State: %s", stateRecord->name.c_str());
                if (state.showIDs) {
                    ImGui::TextDisabled("Node Ref: %s", stateRecord->nodeRefId.empty() ? "<None>" : stateRecord->nodeRefId.c_str());
                }
                if (stateRecord->nodeRefId.empty()) {
                    ImGui::TextDisabled("This state does not reference a subgraph node.");
                    break;
                }
                const AnimationGraphNodeCanvasScope subgraphScope =
                    BuildStateSubgraphWorkspaceScope(snapshot, stateRecord->nodeRefId, state.selectedNodeId);
                ImGui::BeginChild("StateSubgraphCanvasHost", ImVec2(0.0f, 0.0f), false, ImGuiWindowFlags_NoScrollbar | ImGuiWindowFlags_NoScrollWithMouse);
                DrawAnimationGraphNodeCanvas(context, snapshot, selectedNodeIds, state, &subgraphScope);
                ImGui::EndChild();
                break;
            }
            case AnimationGraphWorkspaceKind::BlendSpace:
                DrawAnimationGraphBlendSpaceWorkspace(context,
                                                      snapshot,
                                                      workspace,
                                                      state,
                                                      (hasRuntimeDebugSnapshot && state.showRuntimeDebug) ? &runtimeDebugSnapshot : nullptr);
                break;
            default:
                break;
        }
        AnimationGraphWorkspaceRouter::ApplyPendingNavigation(state.activeGraphHandle, state);
        EditorUI::EndPanel();
        return;
    }

    if (ImGui::BeginTable("AnimGraphLayout", 2, ImGuiTableFlags_SizingStretchProp | ImGuiTableFlags_NoSavedSettings)) {
        ImGui::TableSetupColumn("Sidebar", ImGuiTableColumnFlags_WidthFixed, 280.0f);
        ImGui::TableSetupColumn("Workspace", ImGuiTableColumnFlags_WidthStretch, 1.0f);

        ImGui::TableNextColumn();
        DrawAnimationGraphSidebar(context,
                                  selectedEntityId,
                                  snapshot,
                                  state,
                                  hasRuntimeDebugSnapshot,
                                  runtimeDebugSnapshot);
        ImGui::TableNextColumn();
        ImGui::BeginChild("AnimationGraphWorkspaceHost", ImVec2(0.0f, 0.0f), false, ImGuiWindowFlags_NoScrollbar | ImGuiWindowFlags_NoScrollWithMouse);
        DrawWorkspaceBanner(snapshot.name.empty() ? "Root Graph" : snapshot.name.c_str(),
                            "Compose the graph here. Open blend spaces and state machines from their nodes.");
        if (!state.hasInteractedWithCanvas) {
            ImGui::TextDisabled("Right-click to add nodes. Drag links to connect or create.");
            ImGui::Spacing();
        }
        if (snapshot.nodes.size() == 1 && snapshot.nodes.front().type == 0) {
            ImGui::TextDisabled("Start by adding a State Machine node.");
            ImGui::Spacing();
        }

        const AnimationGraphNodeCanvasScope rootScope = BuildRootWorkspaceScope(snapshot);
        DrawAnimationGraphNodeCanvas(context, snapshot, selectedNodeIds, state, &rootScope);
        AnimationGraphWorkspaceRouter::ApplyPendingNavigation(state.activeGraphHandle, state);
        ImGui::EndChild();

        ImGui::EndTable();
    }
    EditorUI::EndPanel();
}
