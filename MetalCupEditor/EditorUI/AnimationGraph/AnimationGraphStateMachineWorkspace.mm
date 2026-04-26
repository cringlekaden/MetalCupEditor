#include "AnimationGraphStateMachineWorkspace.h"

#include "AnimationGraphStateMachineStateStore.h"

#include "../../ImGui/imgui.h"

#include <algorithm>
#include <cmath>
#include <string>
#include <unordered_map>
#include <unordered_set>

extern "C" uint32_t MCEEditorAddAnimationGraphStateMachineState(void *context, const char *handle, const char *nodeId,
                                                                 const char *name, const char *clipHandle, const char *nodeRefId,
                                                                 uint32_t isOneShot,
                                                                 uint32_t usesRootMotion,
                                                                 char *outStateId, int32_t outStateIdSize);
extern "C" uint32_t MCEEditorSetAnimationGraphStateMachineDefaultState(void *context, const char *handle, const char *nodeId, const char *stateId);
extern "C" uint32_t MCEEditorRemoveAnimationGraphStateMachineState(void *context, const char *handle, const char *nodeId, const char *stateId);
extern "C" uint32_t MCEEditorAddAnimationGraphStateMachineTransition(void *context, const char *handle, const char *nodeId,
                                                                      const char *fromStateId, const char *toStateId,
                                                                      float duration, uint32_t hasMinimumNormalizedTime, float minimumNormalizedTime,
                                                                      char *outTransitionId, int32_t outTransitionIdSize);
extern "C" uint32_t MCEEditorRemoveAnimationGraphStateMachineTransition(void *context, const char *handle, const char *nodeId, const char *transitionId);

namespace {
std::string TruncatedLabel(const std::string &value, size_t maxChars) {
    if (value.size() <= maxChars) { return value; }
    if (maxChars < 4) { return value.substr(0, maxChars); }
    return value.substr(0, maxChars - 3) + "...";
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
}

void DrawAnimationGraphStateMachineWorkspace(void *context,
                                             const AnimationGraphSnapshot &snapshot,
                                             const AnimationGraphWorkspaceDescriptor &workspace,
                                             MCEPanelState::AnimationGraphPanelState &panelState,
                                             const AnimationGraphRuntimeDebugSnapshot *runtimeDebug,
                                             AnimationGraphTransitionCanvasRenderer transitionCanvasRenderer) {
    const auto *node = FindNodeById(snapshot, workspace.nodeId);
    if (!node || node->type != 4) {
        ImGui::TextDisabled("State machine workspace target is missing.");
        return;
    }

    AnimationGraphStateMachineWorkspaceState &workspaceState =
        AnimationGraphStateMachineStateStore::StateForWorkspace(panelState.activeGraphHandle, workspace);
    std::string &selectedStateId = workspaceState.selectedStateId;
    std::string &selectedTransitionId = workspaceState.selectedTransitionId;
    if (selectedStateId.empty() && !node->stateMachineStates.empty()) {
        selectedStateId = node->stateMachineStates.front().id;
    }

    std::string activeStateID;
    std::string activeNextStateID;
    float activeTransitionElapsed = 0.0f;
    float activeTransitionDuration = 0.0f;
    if (runtimeDebug && runtimeDebug->available) {
        auto runtimeIt = runtimeDebug->stateMachineRuntimeByNodeID.find(node->id);
        if (runtimeIt != runtimeDebug->stateMachineRuntimeByNodeID.end()) {
            activeStateID = runtimeIt->second.currentStateID;
            activeNextStateID = runtimeIt->second.nextStateID;
            activeTransitionElapsed = runtimeIt->second.transitionElapsed;
            activeTransitionDuration = runtimeIt->second.transitionDuration;
        }
    }

    ImGui::SeparatorText(node->title.empty() ? "State Machine" : node->title.c_str());
    const float totalHeight = ImGui::GetContentRegionAvail().y;
    const float topHeight = std::max(180.0f, totalHeight * 0.56f);
    std::string contextStateId;
    std::string contextTransitionId;
    bool openBackgroundContextMenu = false;

    ImGui::BeginChild("StateMachineTopPane", ImVec2(0.0f, topHeight), true);
    ImDrawList *draw = ImGui::GetWindowDrawList();
    const ImVec2 origin = ImGui::GetCursorScreenPos();
    const ImVec2 avail = ImGui::GetContentRegionAvail();
    draw->AddRectFilled(origin, ImVec2(origin.x + avail.x, origin.y + avail.y), IM_COL32(22, 24, 28, 255), 4.0f);
    draw->AddRect(origin, ImVec2(origin.x + avail.x, origin.y + avail.y), IM_COL32(64, 70, 78, 255), 4.0f);
    const int stateCount = static_cast<int>(node->stateMachineStates.size());
    std::unordered_map<std::string, ImVec2> centersByStateId;
    centersByStateId.reserve(node->stateMachineStates.size());
    for (int i = 0; i < stateCount; ++i) {
        const auto &state = node->stateMachineStates[static_cast<size_t>(i)];
        const float angle = (6.283185307f * static_cast<float>(i)) / static_cast<float>(stateCount);
        const ImVec2 center(origin.x + avail.x * 0.5f + cosf(angle) * avail.x * 0.28f,
                            origin.y + avail.y * 0.5f + sinf(angle) * avail.y * 0.30f);
        centersByStateId[state.id] = center;
    }
    for (const auto &transition : node->stateMachineTransitions) {
        const auto fromIt = centersByStateId.find(transition.fromStateId);
        const auto toIt = centersByStateId.find(transition.toStateId);
        if (fromIt == centersByStateId.end() || toIt == centersByStateId.end()) { continue; }
        const ImVec2 a = fromIt->second;
        const ImVec2 b = toIt->second;
        const bool transitionActive = !activeStateID.empty() &&
            !activeNextStateID.empty() &&
            transition.fromStateId == activeStateID &&
            transition.toStateId == activeNextStateID &&
            activeTransitionDuration > 1.0e-5f;
        const float transitionAlpha = transitionActive
            ? std::clamp(activeTransitionElapsed / std::max(activeTransitionDuration, 1.0e-5f), 0.0f, 1.0f)
            : 0.0f;
        const ImU32 transitionColor = transitionActive
            ? IM_COL32(106, 240, 144, 240)
            : IM_COL32(132, 170, 220, 225);
        draw->AddLine(a, b, transitionColor, transitionActive ? 3.0f : 2.0f);
        const ImVec2 mid((a.x + b.x) * 0.5f, (a.y + b.y) * 0.5f);
        ImGui::SetCursorScreenPos(ImVec2(mid.x - 8.0f, mid.y - 8.0f));
        ImGui::PushID(transition.id.c_str());
        ImGui::InvisibleButton("TransitionPick", ImVec2(16.0f, 16.0f));
        const bool hovered = ImGui::IsItemHovered();
        if (hovered && ImGui::IsMouseClicked(ImGuiMouseButton_Left)) {
            selectedTransitionId = transition.id;
        }
        if (hovered && ImGui::IsMouseClicked(ImGuiMouseButton_Right)) {
            selectedTransitionId = transition.id;
            contextTransitionId = transition.id;
            ImGui::OpenPopup("StateMachineTransitionContextMenu");
        }
        if (hovered && ImGui::IsMouseDoubleClicked(ImGuiMouseButton_Left)) {
            panelState.pendingWorkspaceNavigationKind = MCEPanelState::AnimationGraphPanelState::WorkspaceNavigationTransitionGraph;
            panelState.pendingWorkspaceNodeId = node->id;
            panelState.pendingWorkspaceTransitionId = transition.id;
            panelState.pendingWorkspaceStateId.clear();
        }
        ImGui::PopID();
        if (selectedTransitionId == transition.id || hovered) {
            draw->AddCircleFilled(mid, 5.0f, IM_COL32(248, 200, 120, 255));
        } else if (transitionActive) {
            const float glow = 4.0f + 2.0f * transitionAlpha;
            draw->AddCircleFilled(mid, glow, IM_COL32(106, 240, 144, 210));
        }
    }

    for (int32_t stateIndex = 0; stateIndex < static_cast<int32_t>(node->stateMachineStates.size()); ++stateIndex) {
        const auto &state = node->stateMachineStates[static_cast<size_t>(stateIndex)];
        const ImVec2 center = centersByStateId[state.id];
        const ImVec2 half(64.0f, 22.0f);
        const ImVec2 min(center.x - half.x, center.y - half.y);
        const ImVec2 max(center.x + half.x, center.y + half.y);
        const bool selected = (selectedStateId == state.id);
        const bool isDefault = (!node->stateMachineDefaultStateId.empty() && node->stateMachineDefaultStateId == state.id);
        const bool isOneShot = state.isOneShot;
        const bool isSubgraphState = !state.nodeRefId.empty();
        const ImU32 fill = selected ? IM_COL32(92, 108, 138, 235) : IM_COL32(52, 58, 66, 235);
        ImU32 border = IM_COL32(136, 144, 160, 255);
        if (isOneShot) {
            border = IM_COL32(236, 173, 86, 255);
        } else if (isSubgraphState) {
            border = IM_COL32(118, 188, 248, 255);
        }
        if (isDefault) {
            border = IM_COL32(190, 220, 140, 255);
        }
        draw->AddRectFilled(min, max, fill, 5.0f);
        draw->AddRect(min, max, border, 5.0f, 0, 1.6f);
        draw->AddText(ImVec2(min.x + 8.0f, min.y + 7.0f), IM_COL32(235, 240, 248, 255), state.name.c_str());
        const char *stateBadge = isOneShot ? "ONE SHOT" : (isSubgraphState ? "SUBGRAPH" : "CLIP");
        draw->AddText(ImVec2(min.x + 8.0f, max.y - 14.0f), IM_COL32(168, 179, 196, 235), stateBadge);
        if (panelState.showSortIndices) {
            const std::string indexLabel = "#" + std::to_string(stateIndex);
            draw->AddText(ImVec2(max.x - 24.0f, min.y + 7.0f), IM_COL32(180, 190, 206, 225), indexLabel.c_str());
        }
        if (panelState.showIDs) {
            const std::string idLabel = TruncatedLabel(state.id, 10);
            draw->AddText(ImVec2(min.x + 8.0f, max.y + 4.0f), IM_COL32(160, 170, 186, 220), idLabel.c_str());
        }
        if (isDefault) {
            draw->AddText(ImVec2(max.x + 6.0f, min.y + 7.0f), IM_COL32(190, 220, 140, 255), "(ENTRY)");
        }
        if (!activeStateID.empty() && activeStateID == state.id) {
            const ImVec2 ledPos(max.x - 12.0f, min.y + 10.0f);
            draw->AddCircleFilled(ledPos, 4.0f, IM_COL32(110, 252, 132, 255));
            draw->AddCircle(ledPos, 8.0f, IM_COL32(110, 252, 132, 160), 24, 2.0f);
            draw->AddCircle(ledPos, 12.0f, IM_COL32(110, 252, 132, 80), 24, 1.0f);
        }
        ImGui::SetCursorScreenPos(min);
        ImGui::PushID(state.id.c_str());
        ImGui::InvisibleButton("StatePick", ImVec2(max.x - min.x, max.y - min.y));
        const bool hovered = ImGui::IsItemHovered();
        if (hovered && ImGui::IsMouseClicked(ImGuiMouseButton_Left)) {
            selectedStateId = state.id;
        }
        if (hovered && ImGui::IsMouseClicked(ImGuiMouseButton_Right)) {
            selectedStateId = state.id;
            contextStateId = state.id;
            ImGui::OpenPopup("StateMachineStateContextMenu");
        }
        if (hovered && ImGui::IsMouseDoubleClicked(ImGuiMouseButton_Left) && !state.nodeRefId.empty()) {
            panelState.pendingWorkspaceNavigationKind = MCEPanelState::AnimationGraphPanelState::WorkspaceNavigationStateSubgraph;
            panelState.pendingWorkspaceNodeId = node->id;
            panelState.pendingWorkspaceStateId = state.id;
            panelState.pendingWorkspaceTransitionId.clear();
        }
        ImGui::PopID();
    }

    if (ImGui::IsWindowHovered() && ImGui::IsMouseClicked(ImGuiMouseButton_Right)) {
        openBackgroundContextMenu = true;
    }
    if (openBackgroundContextMenu) {
        ImGui::OpenPopup("StateMachineBackgroundContextMenu");
    }

    if (ImGui::BeginPopup("StateMachineBackgroundContextMenu")) {
        if (ImGui::MenuItem("Add State")) {
            std::string name = "State";
            int suffix = static_cast<int>(node->stateMachineStates.size()) + 1;
            std::unordered_set<std::string> existingNames;
            for (const auto &state : node->stateMachineStates) {
                existingNames.insert(state.name);
            }
            while (existingNames.count(name) != 0) {
                name = "State " + std::to_string(suffix++);
            }
            char outStateId[64] = {0};
            MCEEditorAddAnimationGraphStateMachineState(context,
                                                        panelState.activeGraphHandle.c_str(),
                                                        node->id.c_str(),
                                                        name.c_str(),
                                                        nullptr,
                                                        nullptr,
                                                        0,
                                                        0,
                                                        outStateId,
                                                        sizeof(outStateId));
        }
        ImGui::Separator();
        ImGui::Checkbox("Show IDs", &panelState.showIDs);
        ImGui::Checkbox("Show Sort Indices", &panelState.showSortIndices);
        ImGui::EndPopup();
    }
    if (ImGui::BeginPopup("StateMachineStateContextMenu")) {
        if (!contextStateId.empty()) {
            if (ImGui::MenuItem("Set as Entry")) {
                MCEEditorSetAnimationGraphStateMachineDefaultState(context,
                                                                   panelState.activeGraphHandle.c_str(),
                                                                   node->id.c_str(),
                                                                   contextStateId.c_str());
            }
            if (ImGui::MenuItem("Delete State")) {
                MCEEditorRemoveAnimationGraphStateMachineState(context,
                                                               panelState.activeGraphHandle.c_str(),
                                                               node->id.c_str(),
                                                               contextStateId.c_str());
                if (selectedStateId == contextStateId) {
                    selectedStateId.clear();
                }
            }
            if (ImGui::MenuItem("Add Transition From Here")) {
                std::string targetStateId = selectedStateId;
                if (targetStateId.empty() || targetStateId == contextStateId) {
                    for (const auto &candidateState : node->stateMachineStates) {
                        if (candidateState.id != contextStateId) {
                            targetStateId = candidateState.id;
                            break;
                        }
                    }
                }
                if (!targetStateId.empty() && targetStateId != contextStateId) {
                    char outTransitionId[64] = {0};
                    MCEEditorAddAnimationGraphStateMachineTransition(context,
                                                                     panelState.activeGraphHandle.c_str(),
                                                                     node->id.c_str(),
                                                                     contextStateId.c_str(),
                                                                     targetStateId.c_str(),
                                                                     0.1f,
                                                                     0,
                                                                     0.0f,
                                                                     outTransitionId,
                                                                     sizeof(outTransitionId));
                }
            }
        }
        ImGui::EndPopup();
    }
    if (ImGui::BeginPopup("StateMachineTransitionContextMenu")) {
        if (!contextTransitionId.empty()) {
            if (ImGui::MenuItem("Delete Transition")) {
                MCEEditorRemoveAnimationGraphStateMachineTransition(context,
                                                                    panelState.activeGraphHandle.c_str(),
                                                                    node->id.c_str(),
                                                                    contextTransitionId.c_str());
                if (selectedTransitionId == contextTransitionId) {
                    selectedTransitionId.clear();
                }
            }
        }
        ImGui::EndPopup();
    }
    ImGui::EndChild();

    ImGui::BeginChild("StateMachineBottomPane", ImVec2(0.0f, 0.0f), true);
    const auto *selectedTransition = FindTransitionInMachine(*node, selectedTransitionId);
    if (!selectedTransition) {
        ImGui::TextDisabled("No transition selected.");
        ImGui::TextWrapped("Click a transition arrow in the top pane to inspect/edit its transition graph here.");
    } else {
        std::string fromName = selectedTransition->fromStateId;
        std::string toName = selectedTransition->toStateId;
        if (const auto *from = FindStateInMachine(*node, selectedTransition->fromStateId)) { fromName = from->name; }
        if (const auto *to = FindStateInMachine(*node, selectedTransition->toStateId)) { toName = to->name; }
        std::string paneTitle = "Transition: " + fromName + " \u2192 " + toName;
        ImGui::SeparatorText(paneTitle.c_str());
        if (transitionCanvasRenderer) {
            transitionCanvasRenderer(*selectedTransition, "StateMachineTransitionGraphCanvas");
        }
    }
    ImGui::EndChild();
}

