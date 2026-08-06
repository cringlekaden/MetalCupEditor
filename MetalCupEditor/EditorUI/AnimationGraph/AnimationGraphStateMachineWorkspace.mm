#include "AnimationGraphStateMachineWorkspace.h"

#include "AnimationGraphInlineWidgets.h"
#include "AnimationGraphStateMachineStateStore.h"

#include "../../ImGui/imgui.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

extern "C" uint32_t MCEEditorAddAnimationGraphStateMachineState(void *context, const char *handle, const char *nodeId,
                                                                 const char *name, const char *clipHandle, const char *nodeRefId,
                                                                 uint32_t isOneShot,
                                                                 uint32_t usesRootMotion,
                                                                 char *outStateId, int32_t outStateIdSize);
extern "C" uint32_t MCEEditorUpdateAnimationGraphStateMachineState(void *context, const char *handle, const char *nodeId, const char *stateId,
                                                                     const char *name, const char *clipHandle, const char *nodeRefId,
                                                                     uint32_t isOneShot, uint32_t usesRootMotion);
extern "C" uint32_t MCEEditorSetAnimationGraphStateMachineDefaultState(void *context, const char *handle, const char *nodeId, const char *stateId);
extern "C" uint32_t MCEEditorRemoveAnimationGraphStateMachineState(void *context, const char *handle, const char *nodeId, const char *stateId);
extern "C" uint32_t MCEEditorAddAnimationGraphStateMachineTransition(void *context, const char *handle, const char *nodeId,
                                                                      const char *fromStateId, const char *toStateId,
                                                                      float duration, uint32_t hasMinimumNormalizedTime, float minimumNormalizedTime,
                                                                      char *outTransitionId, int32_t outTransitionIdSize);
extern "C" uint32_t MCEEditorUpdateAnimationGraphStateMachineTransition(void *context, const char *handle, const char *nodeId,
                                                                         const char *transitionId,
                                                                         const char *fromStateId, const char *toStateId,
                                                                         float duration, uint32_t hasMinimumNormalizedTime, float minimumNormalizedTime);
extern "C" uint32_t MCEEditorRemoveAnimationGraphStateMachineTransition(void *context, const char *handle, const char *nodeId, const char *transitionId);
extern "C" uint32_t MCEEditorAddAnimationGraphNode(void *context, const char *handle, int32_t type, const char *title, float posX, float posY, const char *clipHandle, char *outNodeId, int32_t outNodeIdSize);

namespace {
void DrawWorkspaceSectionBanner(const char *title, const char *subtitle) {
    ImDrawList *draw = ImGui::GetWindowDrawList();
    const ImVec2 start = ImGui::GetCursorScreenPos();
    const float width = ImGui::GetContentRegionAvail().x;
    const ImVec2 size(width, 48.0f);
    draw->AddRectFilled(start, ImVec2(start.x + size.x, start.y + size.y), IM_COL32(24, 27, 32, 255), 8.0f);
    draw->AddRect(start, ImVec2(start.x + size.x, start.y + size.y), IM_COL32(56, 63, 74, 255), 8.0f, 0, 1.0f);
    draw->AddText(ImVec2(start.x + 14.0f, start.y + 8.0f), IM_COL32(226, 232, 240, 245), title);
    draw->AddText(ImVec2(start.x + 14.0f, start.y + 26.0f), IM_COL32(148, 158, 174, 230), subtitle);
    ImGui::Dummy(size);
}

struct StateRect {
    ImVec2 min;
    ImVec2 max;
    ImVec2 center;
};

struct TransitionVisual {
    const AnimationGraphNodeRecord::StateMachineTransitionRecord *transition = nullptr;
    bool selfLoop = false;
    ImVec2 start;
    ImVec2 control;
    ImVec2 end;
    ImVec2 loopCenter;
    float loopRadius = 0.0f;
    ImVec2 pickPoint;
};

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

ImVec2 ClampToCanvas(const ImVec2 &localCenter, const ImVec2 &halfSize, const ImVec2 &canvasSize) {
    const float minX = halfSize.x + 6.0f;
    const float maxX = std::max(minX, canvasSize.x - halfSize.x - 6.0f);
    const float minY = halfSize.y + 6.0f;
    const float maxY = std::max(minY, canvasSize.y - halfSize.y - 6.0f);
    return ImVec2(std::clamp(localCenter.x, minX, maxX), std::clamp(localCenter.y, minY, maxY));
}

ImVec2 AnchorOnRectEdge(const ImVec2 &center, const ImVec2 &halfSize, const ImVec2 &dirUnit) {
    const float absX = fabsf(dirUnit.x);
    const float absY = fabsf(dirUnit.y);
    if (absX < 1.0e-4f && absY < 1.0e-4f) { return center; }
    const float tx = absX < 1.0e-4f ? 1.0e6f : (halfSize.x / absX);
    const float ty = absY < 1.0e-4f ? 1.0e6f : (halfSize.y / absY);
    const float t = std::min(tx, ty);
    return ImVec2(center.x + dirUnit.x * t, center.y + dirUnit.y * t);
}

ImVec2 EvalQuadratic(const ImVec2 &a, const ImVec2 &b, const ImVec2 &c, float t) {
    const float s = 1.0f - t;
    return ImVec2(
        s * s * a.x + 2.0f * s * t * b.x + t * t * c.x,
        s * s * a.y + 2.0f * s * t * b.y + t * t * c.y
    );
}

float DistancePointToSegment(const ImVec2 &p, const ImVec2 &a, const ImVec2 &b) {
    const ImVec2 ab = ImVec2(b.x - a.x, b.y - a.y);
    const float abLenSq = ab.x * ab.x + ab.y * ab.y;
    if (abLenSq < 1.0e-6f) {
        const ImVec2 d = ImVec2(p.x - a.x, p.y - a.y);
        return sqrtf(d.x * d.x + d.y * d.y);
    }
    const ImVec2 ap = ImVec2(p.x - a.x, p.y - a.y);
    const float t = std::clamp((ap.x * ab.x + ap.y * ab.y) / abLenSq, 0.0f, 1.0f);
    const ImVec2 closest = ImVec2(a.x + ab.x * t, a.y + ab.y * t);
    const ImVec2 d = ImVec2(p.x - closest.x, p.y - closest.y);
    return sqrtf(d.x * d.x + d.y * d.y);
}

float DistanceToQuadraticCurve(const ImVec2 &p, const ImVec2 &a, const ImVec2 &b, const ImVec2 &c) {
    float best = 1.0e6f;
    ImVec2 prev = a;
    constexpr int kSegments = 20;
    for (int i = 1; i <= kSegments; ++i) {
        const float t = static_cast<float>(i) / static_cast<float>(kSegments);
        const ImVec2 curr = EvalQuadratic(a, b, c, t);
        best = std::min(best, DistancePointToSegment(p, prev, curr));
        prev = curr;
    }
    return best;
}

float DistanceToLoopArc(const ImVec2 &p, const ImVec2 &center, float radius) {
    const ImVec2 d = ImVec2(p.x - center.x, p.y - center.y);
    const float len = sqrtf(d.x * d.x + d.y * d.y);
    return fabsf(len - radius);
}

TransitionVisual BuildTransitionVisual(const AnimationGraphNodeRecord &machineNode,
                                       const AnimationGraphNodeRecord::StateMachineTransitionRecord &transition,
                                       const std::unordered_map<std::string, StateRect> &stateRects,
                                       const ImVec2 &stateHalfSize) {
    TransitionVisual visual;
    visual.transition = &transition;

    auto fromIt = stateRects.find(transition.fromStateId);
    auto toIt = stateRects.find(transition.toStateId);
    if (fromIt == stateRects.end() || toIt == stateRects.end()) {
        return visual;
    }

    int sameDirectionIndex = 0;
    for (const auto &candidate : machineNode.stateMachineTransitions) {
        if (candidate.id == transition.id) { break; }
        if (candidate.fromStateId == transition.fromStateId && candidate.toStateId == transition.toStateId) {
            sameDirectionIndex += 1;
        }
    }

    if (transition.fromStateId == transition.toStateId) {
        visual.selfLoop = true;
        visual.loopCenter = ImVec2(fromIt->second.center.x + stateHalfSize.x + 24.0f,
                                   fromIt->second.center.y - stateHalfSize.y - 16.0f);
        visual.loopRadius = 20.0f + static_cast<float>(sameDirectionIndex) * 7.0f;
        visual.pickPoint = ImVec2(visual.loopCenter.x, visual.loopCenter.y - visual.loopRadius);
        return visual;
    }

    const ImVec2 fromCenter = fromIt->second.center;
    const ImVec2 toCenter = toIt->second.center;
    const ImVec2 dir = ImVec2(toCenter.x - fromCenter.x, toCenter.y - fromCenter.y);
    const float len = sqrtf(dir.x * dir.x + dir.y * dir.y);
    if (len < 1.0e-4f) {
        return visual;
    }

    const ImVec2 unit = ImVec2(dir.x / len, dir.y / len);

    const bool canonicalForward = transition.fromStateId <= transition.toStateId;
    const ImVec2 canonicalUnit = canonicalForward ? unit : ImVec2(-unit.x, -unit.y);
    const ImVec2 canonicalPerp = ImVec2(-canonicalUnit.y, canonicalUnit.x);
    const float directionSign = canonicalForward ? 1.0f : -1.0f;
    const float lane = directionSign * (1.0f + static_cast<float>(sameDirectionIndex));
    const float laneOffset = 14.0f * lane;
    const ImVec2 fromShiftedCenter(fromCenter.x + canonicalPerp.x * laneOffset, fromCenter.y + canonicalPerp.y * laneOffset);
    const ImVec2 toShiftedCenter(toCenter.x + canonicalPerp.x * laneOffset, toCenter.y + canonicalPerp.y * laneOffset);
    const ImVec2 fromAnchor = AnchorOnRectEdge(fromShiftedCenter, stateHalfSize, unit);
    const ImVec2 toAnchor = AnchorOnRectEdge(toShiftedCenter, stateHalfSize, ImVec2(-unit.x, -unit.y));
    const ImVec2 mid = ImVec2((fromAnchor.x + toAnchor.x) * 0.5f, (fromAnchor.y + toAnchor.y) * 0.5f);
    const float controlOffset = laneOffset * 2.0f;

    visual.start = ImVec2(fromAnchor.x + unit.x * 1.0f, fromAnchor.y + unit.y * 1.0f);
    visual.end = ImVec2(toAnchor.x - unit.x * 1.0f, toAnchor.y - unit.y * 1.0f);
    visual.control = ImVec2(mid.x + canonicalPerp.x * controlOffset, mid.y + canonicalPerp.y * controlOffset);
    visual.pickPoint = EvalQuadratic(visual.start, visual.control, visual.end, 0.5f);
    return visual;
}
}

void DrawAnimationGraphStateMachineWorkspace(void *context,
                                             const AnimationGraphSnapshot &snapshot,
                                             const AnimationGraphWorkspaceDescriptor &workspace,
                                             MCEPanelState::AnimationGraphPanelState &panelState,
                                             const AnimationGraphRuntimeDebugSnapshot *runtimeDebug,
                                             AnimationGraphTransitionCanvasRenderer transitionCanvasRenderer) {
    (void)transitionCanvasRenderer;
    const auto *node = FindNodeById(snapshot, workspace.nodeId);
    if (!node || node->type != 4) {
        ImGui::TextDisabled("State machine workspace target is missing.");
        return;
    }

    AnimationGraphStateMachineWorkspaceState &workspaceState =
        AnimationGraphStateMachineStateStore::StateForWorkspace(panelState.activeGraphHandle, workspace);
    std::string &selectedStateId = workspaceState.selectedStateId;
    std::string &selectedTransitionId = workspaceState.selectedTransitionId;
    std::string &pendingTransitionSourceStateId = workspaceState.pendingTransitionSourceStateId;
    std::string &contextStateId = workspaceState.contextStateId;
    std::string &contextTransitionId = workspaceState.contextTransitionId;
    AnimationGraphStateMachineWorkspaceState::NodePopupState &popupState = workspaceState.popupState;

    if (!selectedStateId.empty()) {
        const bool stillExists = std::any_of(node->stateMachineStates.begin(), node->stateMachineStates.end(), [&](const auto &state) {
            return state.id == selectedStateId;
        });
        if (!stillExists) {
            selectedStateId.clear();
        }
    }
    if (!selectedTransitionId.empty()) {
        const bool stillExists = std::any_of(node->stateMachineTransitions.begin(), node->stateMachineTransitions.end(), [&](const auto &transition) {
            return transition.id == selectedTransitionId;
        });
        if (!stillExists) {
            selectedTransitionId.clear();
        }
    }
    if (!pendingTransitionSourceStateId.empty()) {
        const bool stillExists = std::any_of(node->stateMachineStates.begin(), node->stateMachineStates.end(), [&](const auto &state) {
            return state.id == pendingTransitionSourceStateId;
        });
        if (!stillExists) {
            pendingTransitionSourceStateId.clear();
        }
    }
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

    DrawWorkspaceSectionBanner(node->title.empty() ? "State Machine" : node->title.c_str(),
                               "Select states above. Author the selected transition below.");
    bool openBackgroundContextMenu = false;
    const ImVec2 stateHalf(112.0f, 56.0f);
    const std::string popupScopeId = panelState.activeGraphHandle + "|" + node->id;
    const std::string backgroundPopupId = "StateMachineBackgroundContextMenu##" + popupScopeId;
    const std::string statePopupId = "StateMachineStateContextMenu##" + popupScopeId;
    const std::string transitionPopupId = "StateMachineTransitionContextMenu##" + popupScopeId;

    auto openOrCreateSubgraphForState = [&](const AnimationGraphNodeRecord::StateMachineStateRecord &state) {
        if (!state.nodeRefId.empty()) {
            panelState.pendingWorkspaceNavigationKind = MCEPanelState::AnimationGraphPanelState::WorkspaceNavigationStateSubgraph;
            panelState.pendingWorkspaceNodeId = node->id;
            panelState.pendingWorkspaceStateId = state.id;
            panelState.pendingWorkspaceTransitionId.clear();
            return;
        }

        char outNodeId[64] = {0};
        const float spawnX = node->position.x + 260.0f;
        const float spawnY = node->position.y + 60.0f;
        if (MCEEditorAddAnimationGraphNode(context,
                                           panelState.activeGraphHandle.c_str(),
                                           1,
                                           nullptr,
                                           spawnX,
                                           spawnY,
                                           state.clipHandle.empty() ? nullptr : state.clipHandle.c_str(),
                                           outNodeId,
                                           sizeof(outNodeId)) != 0 && outNodeId[0] != 0) {
            MCEEditorUpdateAnimationGraphStateMachineState(context,
                                                           panelState.activeGraphHandle.c_str(),
                                                           node->id.c_str(),
                                                           state.id.c_str(),
                                                           state.name.c_str(),
                                                           nullptr,
                                                           outNodeId,
                                                           state.isOneShot ? 1u : 0u,
                                                           state.usesRootMotion ? 1u : 0u);
            panelState.pendingWorkspaceNavigationKind = MCEPanelState::AnimationGraphPanelState::WorkspaceNavigationStateSubgraph;
            panelState.pendingWorkspaceNodeId = node->id;
            panelState.pendingWorkspaceStateId = state.id;
            panelState.pendingWorkspaceTransitionId.clear();
        }
    };
    auto addStateAt = [&](const ImVec2 &localPos) {
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
        if (MCEEditorAddAnimationGraphStateMachineState(context,
                                                         panelState.activeGraphHandle.c_str(),
                                                         node->id.c_str(),
                                                         name.c_str(),
                                                         nullptr,
                                                         nullptr,
                                                         0,
                                                         0,
                                                         outStateId,
                                                         sizeof(outStateId)) != 0 && outStateId[0] != 0) {
            const ImVec2 currentWorkspaceAvail = ImGui::GetContentRegionAvail();
            workspaceState.positionsByStateId[outStateId] = ClampToCanvas(localPos, stateHalf, currentWorkspaceAvail);
            selectedStateId = outStateId;
            selectedTransitionId.clear();
        }
    };

    auto *selectedState = const_cast<AnimationGraphNodeRecord::StateMachineStateRecord *>(
        selectedStateId.empty() ? nullptr : FindStateInMachine(*node, selectedStateId));
    auto *selectedTransition = const_cast<AnimationGraphNodeRecord::StateMachineTransitionRecord *>([&]() -> const AnimationGraphNodeRecord::StateMachineTransitionRecord * {
        if (selectedTransitionId.empty()) { return nullptr; }
        for (const auto &transition : node->stateMachineTransitions) {
            if (transition.id == selectedTransitionId) {
                return &transition;
            }
        }
        return nullptr;
    }());

    if (ImGui::Button("Add State")) {
        const ImVec2 workspaceAvail = ImGui::GetContentRegionAvail();
        addStateAt(ImVec2(workspaceAvail.x * 0.5f, workspaceAvail.y * 0.32f));
    }
    ImGui::SameLine();
    ImGui::BeginDisabled(selectedState == nullptr);
    if (ImGui::Button("Open State Graph")) {
        openOrCreateSubgraphForState(*selectedState);
    }
    ImGui::EndDisabled();
    ImGui::SameLine();
    ImGui::BeginDisabled(selectedState == nullptr);
    if (ImGui::Button("Create Transition")) {
        pendingTransitionSourceStateId = selectedStateId;
        selectedTransitionId.clear();
    }
    ImGui::EndDisabled();
    if (!pendingTransitionSourceStateId.empty()) {
        ImGui::SameLine();
        if (ImGui::Button("Cancel Transition")) {
            pendingTransitionSourceStateId.clear();
        }
    }
    ImGui::SameLine();
    ImGui::TextDisabled(selectedTransitionId.empty()
        ? "Edges open in the lower pane."
        : "Editing selected transition below.");

    const ImVec2 workspaceAvail = ImGui::GetContentRegionAvail();
    const float topHeight = std::clamp(workspaceAvail.y * 0.58f, 220.0f, std::max(220.0f, workspaceAvail.y - 170.0f));

    ImGui::BeginChild("StateMachineTopPane", ImVec2(0.0f, topHeight), true);
    ImDrawList *draw = ImGui::GetWindowDrawList();
    const ImVec2 origin = ImGui::GetCursorScreenPos();
    const ImVec2 avail = ImGui::GetContentRegionAvail();
    draw->AddRectFilled(origin, ImVec2(origin.x + avail.x, origin.y + avail.y), IM_COL32(22, 25, 30, 255), 8.0f);
    draw->AddRect(origin, ImVec2(origin.x + avail.x, origin.y + avail.y), IM_COL32(60, 68, 80, 255), 8.0f);

    for (auto it = workspaceState.positionsByStateId.begin(); it != workspaceState.positionsByStateId.end();) {
        const bool exists = std::any_of(node->stateMachineStates.begin(), node->stateMachineStates.end(), [&](const auto &state) {
            return state.id == it->first;
        });
        if (!exists) {
            it = workspaceState.positionsByStateId.erase(it);
        } else {
            ++it;
        }
    }

    const int stateCount = static_cast<int>(node->stateMachineStates.size());
    for (int i = 0; i < stateCount; ++i) {
        const auto &state = node->stateMachineStates[static_cast<size_t>(i)];
        if (workspaceState.positionsByStateId.count(state.id) != 0) {
            continue;
        }
        const float angle = stateCount > 0
            ? (6.283185307f * static_cast<float>(i)) / static_cast<float>(stateCount)
            : 0.0f;
        ImVec2 localCenter(avail.x * 0.5f + cosf(angle) * avail.x * 0.28f,
                           avail.y * 0.5f + sinf(angle) * avail.y * 0.30f);
        localCenter = ClampToCanvas(localCenter, stateHalf, avail);
        workspaceState.positionsByStateId[state.id] = localCenter;
    }

    std::unordered_map<std::string, StateRect> stateRects;
    stateRects.reserve(node->stateMachineStates.size());

    bool hoveredAnyState = false;
    bool hoveredAnyTransition = false;
    for (int32_t stateIndex = 0; stateIndex < static_cast<int32_t>(node->stateMachineStates.size()); ++stateIndex) {
        const auto &state = node->stateMachineStates[static_cast<size_t>(stateIndex)];
        ImVec2 &localCenter = workspaceState.positionsByStateId[state.id];
        localCenter = ClampToCanvas(localCenter, stateHalf, avail);
        const ImVec2 center(origin.x + localCenter.x, origin.y + localCenter.y);
        const ImVec2 min(center.x - stateHalf.x, center.y - stateHalf.y);
        const ImVec2 max(center.x + stateHalf.x, center.y + stateHalf.y);
        stateRects[state.id] = StateRect{min, max, center};

        const bool selected = (selectedStateId == state.id);
        const bool isDefault = (!node->stateMachineDefaultStateId.empty() && node->stateMachineDefaultStateId == state.id);
        const bool isOneShot = state.isOneShot;
        const bool isSubgraphState = !state.nodeRefId.empty();
        const bool inTransitionCreateMode = (pendingTransitionSourceStateId == state.id);
        const bool isRuntimeActive = (!activeStateID.empty() && activeStateID == state.id);

        const ImU32 fill = selected ? IM_COL32(76, 90, 116, 242) : IM_COL32(44, 49, 57, 242);
        ImU32 border = IM_COL32(112, 122, 140, 255);
        if (isOneShot) {
            border = IM_COL32(236, 173, 86, 255);
        } else if (isSubgraphState) {
            border = IM_COL32(118, 188, 248, 255);
        }
        if (isDefault) {
            border = IM_COL32(190, 220, 140, 255);
        }
        if (inTransitionCreateMode) {
            border = IM_COL32(248, 200, 120, 255);
        }
        if (isRuntimeActive) {
            draw->AddRectFilled(ImVec2(min.x - 4.0f, min.y - 4.0f),
                                ImVec2(max.x + 4.0f, max.y + 4.0f),
                                IM_COL32(56, 146, 78, 42),
                                10.0f);
            draw->AddRect(ImVec2(min.x - 3.0f, min.y - 3.0f),
                          ImVec2(max.x + 3.0f, max.y + 3.0f),
                          IM_COL32(110, 252, 132, 120),
                          7.0f,
                          0,
                          2.4f);
        }

        draw->AddRectFilled(min, max, fill, 8.0f);
        draw->AddRect(min, max, border, 8.0f, 0, selected ? 2.0f : 1.5f);

        const char *stateBadge = isOneShot ? "ONE SHOT" : (isSubgraphState ? "SUBGRAPH" : "STATE");
        const std::string stateTitle = TruncatedLabel(state.name.empty() ? std::string("State") : state.name, 28);
        const ImVec2 titleSize = ImGui::CalcTextSize(stateTitle.c_str());
        draw->AddText(ImVec2(center.x - titleSize.x * 0.5f, center.y - titleSize.y * 0.5f - 8.0f),
                      IM_COL32(222, 228, 236, 245),
                      stateTitle.c_str());
        draw->AddText(ImVec2(min.x + 10.0f, max.y - 18.0f), IM_COL32(168, 179, 196, 225), stateBadge);
        if (isDefault) {
            const ImVec2 badgeMin(min.x + 10.0f, min.y + 10.0f);
            const ImVec2 badgeMax(min.x + 62.0f, min.y + 28.0f);
            draw->AddRectFilled(badgeMin, badgeMax, IM_COL32(146, 182, 92, 225), 6.0f);
            draw->AddText(ImVec2(badgeMin.x + 9.0f, badgeMin.y + 3.0f), IM_COL32(26, 30, 18, 255), "ENTRY");
        }
        if (isRuntimeActive) {
            const ImVec2 activeBadgeMin(max.x - 64.0f, min.y + 10.0f);
            const ImVec2 activeBadgeMax(max.x - 10.0f, min.y + 28.0f);
            draw->AddRectFilled(activeBadgeMin, activeBadgeMax, IM_COL32(72, 178, 94, 220), 6.0f);
            draw->AddText(ImVec2(activeBadgeMin.x + 8.0f, activeBadgeMin.y + 3.0f), IM_COL32(16, 28, 18, 255), "ACTIVE");
        }
        if (panelState.showSortIndices) {
            const std::string indexLabel = "#" + std::to_string(stateIndex);
            draw->AddText(ImVec2(max.x - 24.0f, min.y + 7.0f), IM_COL32(180, 190, 206, 225), indexLabel.c_str());
        }
        if (panelState.showIDs) {
            const std::string idLabel = TruncatedLabel(state.id, 10);
            draw->AddText(ImVec2(min.x + 8.0f, max.y + 4.0f), IM_COL32(160, 170, 186, 220), idLabel.c_str());
        }
        if (isRuntimeActive) {
            const ImVec2 ledPos(max.x - 12.0f, min.y + 10.0f);
            draw->AddCircleFilled(ledPos, 4.0f, IM_COL32(110, 252, 132, 255));
            draw->AddCircle(ledPos, 8.0f, IM_COL32(110, 252, 132, 160), 24, 2.0f);
            draw->AddCircle(ledPos, 12.0f, IM_COL32(110, 252, 132, 80), 24, 1.0f);
        }

        ImGui::SetCursorScreenPos(min);
        ImGui::PushID(state.id.c_str());
        ImGui::InvisibleButton("StateBody", ImVec2(max.x - min.x, max.y - min.y));
        const bool hovered = ImGui::IsMouseHoveringRect(min, max, true);
        hoveredAnyState = hoveredAnyState || hovered;

        if (ImGui::IsItemActivated() && ImGui::IsMouseDoubleClicked(ImGuiMouseButton_Left)) {
            openOrCreateSubgraphForState(state);
        } else if (ImGui::IsItemActivated() && ImGui::IsMouseClicked(ImGuiMouseButton_Left)) {
            if (!pendingTransitionSourceStateId.empty() && pendingTransitionSourceStateId != state.id) {
                char outTransitionId[64] = {0};
                if (MCEEditorAddAnimationGraphStateMachineTransition(context,
                                                                     panelState.activeGraphHandle.c_str(),
                                                                     node->id.c_str(),
                                                                     pendingTransitionSourceStateId.c_str(),
                                                                     state.id.c_str(),
                                                                     0.1f,
                                                                     0,
                                                                     0.0f,
                                                                     outTransitionId,
                                                                     sizeof(outTransitionId)) != 0 && outTransitionId[0] != 0) {
                    selectedTransitionId = outTransitionId;
                }
                pendingTransitionSourceStateId.clear();
            } else {
                selectedStateId = state.id;
                selectedTransitionId.clear();
            }
        }

        if (ImGui::IsItemActive() && ImGui::IsMouseDragging(ImGuiMouseButton_Left)) {
            localCenter.x += ImGui::GetIO().MouseDelta.x;
            localCenter.y += ImGui::GetIO().MouseDelta.y;
            localCenter = ClampToCanvas(localCenter, stateHalf, avail);
            stateRects[state.id] = StateRect{
                ImVec2(origin.x + localCenter.x - stateHalf.x, origin.y + localCenter.y - stateHalf.y),
                ImVec2(origin.x + localCenter.x + stateHalf.x, origin.y + localCenter.y + stateHalf.y),
                ImVec2(origin.x + localCenter.x, origin.y + localCenter.y)
            };
        }

        if (hovered && ImGui::IsMouseClicked(ImGuiMouseButton_Right)) {
            selectedStateId = state.id;
            selectedTransitionId.clear();
            contextStateId = state.id;
            contextTransitionId.clear();
            popupState.openScreenPos = ImGui::GetMousePos();
            popupState.openCanvasPos = ImVec2(popupState.openScreenPos.x - origin.x, popupState.openScreenPos.y - origin.y);
            popupState.requestOpen = true;
            ImGui::OpenPopup(statePopupId.c_str());
        }

        if (ImGui::BeginDragDropTarget()) {
            if (const ImGuiPayload *payload = ImGui::AcceptDragDropPayload("MCE_ASSET_ANIMATION_CLIP")) {
                const char *clipHandle = static_cast<const char *>(payload->Data);
                if (clipHandle && clipHandle[0] != 0) {
                    MCEEditorUpdateAnimationGraphStateMachineState(context,
                                                           panelState.activeGraphHandle.c_str(),
                                                           node->id.c_str(),
                                                           state.id.c_str(),
                                                           state.name.c_str(),
                                                           clipHandle,
                                                           state.nodeRefId.empty() ? nullptr : state.nodeRefId.c_str(),
                                                           state.isOneShot ? 1u : 0u,
                                                           state.usesRootMotion ? 1u : 0u);
                }
            }
            ImGui::EndDragDropTarget();
        }

        if (hovered || selected || inTransitionCreateMode) {
            const ImVec2 handleCenter(max.x + 10.0f, center.y);
            const ImU32 handleFill = inTransitionCreateMode
                ? IM_COL32(248, 200, 120, 255)
                : (hovered ? IM_COL32(164, 196, 242, 245) : IM_COL32(132, 170, 220, 220));
            draw->AddCircleFilled(handleCenter, 9.0f, handleFill);
            draw->AddCircle(handleCenter, 12.5f, IM_COL32(24, 28, 34, 235), 24, 2.0f);
            draw->AddText(ImVec2(handleCenter.x - 5.0f, handleCenter.y - 7.0f),
                          IM_COL32(24, 28, 34, 255),
                          "+");
            ImGui::SetCursorScreenPos(ImVec2(handleCenter.x - 14.0f, handleCenter.y - 14.0f));
            ImGui::InvisibleButton("TransitionHandle", ImVec2(28.0f, 28.0f));
            if (ImGui::IsItemHovered()) {
                ImGui::SetTooltip("Create transition from this state");
            }
            if (ImGui::IsItemClicked(ImGuiMouseButton_Left)) {
                pendingTransitionSourceStateId = state.id;
                selectedStateId = state.id;
                selectedTransitionId.clear();
            }
        }

        ImGui::PopID();
    }

    std::vector<TransitionVisual> transitionVisuals;
    transitionVisuals.reserve(node->stateMachineTransitions.size());
    for (const auto &transition : node->stateMachineTransitions) {
        TransitionVisual visual = BuildTransitionVisual(*node, transition, stateRects, stateHalf);
        if (visual.transition) {
            transitionVisuals.push_back(visual);
        }
    }

    int hoveredTransitionIndex = -1;
    int selectedTransitionIndex = -1;
    if (ImGui::IsWindowHovered(ImGuiHoveredFlags_AllowWhenBlockedByPopup)) {
        const ImVec2 mousePos = ImGui::GetMousePos();
        float bestDistance = 1.0e6f;
        for (int i = 0; i < static_cast<int>(transitionVisuals.size()); ++i) {
            const TransitionVisual &visual = transitionVisuals[static_cast<size_t>(i)];
            const float distance = visual.selfLoop
                ? DistanceToLoopArc(mousePos, visual.loopCenter, visual.loopRadius)
                : DistanceToQuadraticCurve(mousePos, visual.start, visual.control, visual.end);
            const float tolerance = visual.selfLoop ? 8.5f : 7.5f;
            if (distance <= tolerance && distance < bestDistance) {
                bestDistance = distance;
                hoveredTransitionIndex = i;
            }
        }
    }
    for (int i = 0; i < static_cast<int>(transitionVisuals.size()); ++i) {
        const auto &transition = *transitionVisuals[static_cast<size_t>(i)].transition;
        if (selectedTransitionId == transition.id) {
            selectedTransitionIndex = i;
            break;
        }
    }
    hoveredAnyTransition = hoveredTransitionIndex >= 0;

    if (hoveredTransitionIndex >= 0) {
        const auto &hoveredTransition = *transitionVisuals[static_cast<size_t>(hoveredTransitionIndex)].transition;
        if (ImGui::IsMouseClicked(ImGuiMouseButton_Left)) {
            selectedTransitionId = hoveredTransition.id;
            selectedStateId.clear();
        }
        if (ImGui::IsMouseClicked(ImGuiMouseButton_Right)) {
            selectedTransitionId = hoveredTransition.id;
            selectedStateId.clear();
            contextTransitionId = hoveredTransition.id;
            contextStateId.clear();
            popupState.openScreenPos = ImGui::GetMousePos();
            popupState.openCanvasPos = ImVec2(popupState.openScreenPos.x - origin.x, popupState.openScreenPos.y - origin.y);
            popupState.requestOpen = true;
            ImGui::OpenPopup(transitionPopupId.c_str());
        }
    }

    const auto renderTransition = [&](const TransitionVisual &visual, bool hovered) {
        const auto &transition = *visual.transition;
        const bool transitionActive = !activeStateID.empty() &&
            !activeNextStateID.empty() &&
            transition.fromStateId == activeStateID &&
            transition.toStateId == activeNextStateID &&
            activeTransitionDuration > 1.0e-5f;
        const bool transitionSelected = (selectedTransitionId == transition.id);
        const float transitionAlpha = transitionActive
            ? std::clamp(activeTransitionElapsed / std::max(activeTransitionDuration, 1.0e-5f), 0.0f, 1.0f)
            : 0.0f;
        const ImU32 transitionColor = transitionSelected
            ? IM_COL32(248, 200, 120, 255)
            : (hovered ? IM_COL32(164, 196, 242, 245) : (transitionActive ? IM_COL32(106, 240, 144, 240) : IM_COL32(132, 170, 220, 225)));
        const float transitionThickness = transitionSelected ? 3.5f : (hovered ? 2.8f : (transitionActive ? 3.0f : 2.0f));
        const ImU32 transitionHaloColor = transitionSelected
            ? IM_COL32(248, 200, 120, 90)
            : (hovered ? IM_COL32(164, 196, 242, 70) : IM_COL32(0, 0, 0, 0));

        if (visual.selfLoop) {
            if (transitionSelected) {
                draw->AddCircle(visual.loopCenter, visual.loopRadius + 3.0f, transitionHaloColor, 32, 7.0f);
            }
            constexpr int kLoopSegments = 28;
            const float startAngle = 2.5f;
            const float endAngle = -0.3f;
            ImVec2 prev(visual.loopCenter.x + cosf(startAngle) * visual.loopRadius,
                        visual.loopCenter.y + sinf(startAngle) * visual.loopRadius);
            for (int i = 1; i <= kLoopSegments; ++i) {
                const float t = static_cast<float>(i) / static_cast<float>(kLoopSegments);
                const float a = startAngle + (endAngle - startAngle) * t;
                const ImVec2 curr(visual.loopCenter.x + cosf(a) * visual.loopRadius,
                                  visual.loopCenter.y + sinf(a) * visual.loopRadius);
                draw->AddLine(prev, curr, transitionColor, transitionThickness);
                prev = curr;
            }
            const ImVec2 tip(visual.loopCenter.x + cosf(endAngle) * visual.loopRadius,
                             visual.loopCenter.y + sinf(endAngle) * visual.loopRadius);
            const ImVec2 tangent(-sinf(endAngle), cosf(endAngle));
            const ImVec2 normal(-tangent.y, tangent.x);
            const ImVec2 base(tip.x - tangent.x * 11.0f, tip.y - tangent.y * 11.0f);
            const ImVec2 left(base.x + normal.x * 5.0f, base.y + normal.y * 5.0f);
            const ImVec2 right(base.x - normal.x * 5.0f, base.y - normal.y * 5.0f);
            draw->AddTriangleFilled(tip, left, right, transitionColor);
        } else {
            if (transitionSelected) {
                constexpr int kHaloSegments = 24;
                ImVec2 prevHalo = visual.start;
                for (int i = 1; i <= kHaloSegments; ++i) {
                    const float t = static_cast<float>(i) / static_cast<float>(kHaloSegments);
                    const ImVec2 currHalo = EvalQuadratic(visual.start, visual.control, visual.end, t);
                    draw->AddLine(prevHalo, currHalo, transitionHaloColor, 8.0f);
                    prevHalo = currHalo;
                }
            }
            constexpr int kSegments = 20;
            constexpr float kArrowLength = 11.0f;
            const ImVec2 tip = visual.end;
            const ImVec2 beforeTip = EvalQuadratic(visual.start, visual.control, visual.end, 0.92f);
            const ImVec2 arrowDir = ImVec2(tip.x - beforeTip.x, tip.y - beforeTip.y);
            const float arrowLen = sqrtf(arrowDir.x * arrowDir.x + arrowDir.y * arrowDir.y);
            if (arrowLen > 1.0e-3f) {
                const ImVec2 unit = ImVec2(arrowDir.x / arrowLen, arrowDir.y / arrowLen);
                const ImVec2 lineEnd = ImVec2(tip.x - unit.x * kArrowLength, tip.y - unit.y * kArrowLength);
                ImVec2 prev = visual.start;
                for (int i = 1; i <= kSegments; ++i) {
                    const float t = static_cast<float>(i) / static_cast<float>(kSegments);
                    const ImVec2 curr = EvalQuadratic(visual.start, visual.control, lineEnd, t);
                    draw->AddLine(prev, curr, transitionColor, transitionThickness);
                    prev = curr;
                }
                const ImVec2 normal = ImVec2(-unit.y, unit.x);
                const ImVec2 base = lineEnd;
                const ImVec2 left = ImVec2(base.x + normal.x * 5.0f, base.y + normal.y * 5.0f);
                const ImVec2 right = ImVec2(base.x - normal.x * 5.0f, base.y - normal.y * 5.0f);
                draw->AddTriangleFilled(tip, left, right, transitionColor);
            } else {
                ImVec2 prev = visual.start;
                for (int i = 1; i <= kSegments; ++i) {
                    const float t = static_cast<float>(i) / static_cast<float>(kSegments);
                    const ImVec2 curr = EvalQuadratic(visual.start, visual.control, visual.end, t);
                    draw->AddLine(prev, curr, transitionColor, transitionThickness);
                    prev = curr;
                }
            }
        }

        if (transitionSelected || hovered) {
            draw->AddCircleFilled(visual.pickPoint, transitionSelected ? 7.0f : 5.5f, IM_COL32(248, 200, 120, 255));
            if (transitionSelected) {
                draw->AddCircle(visual.pickPoint, 11.5f, IM_COL32(248, 200, 120, 110), 24, 2.0f);
                const auto *fromState = FindStateInMachine(*node, transition.fromStateId);
                const auto *toState = FindStateInMachine(*node, transition.toStateId);
                const std::string edgeLabel = (fromState ? fromState->name : transition.fromStateId) +
                    std::string(" -> ") +
                    (toState ? toState->name : transition.toStateId);
                const ImVec2 labelSize = ImGui::CalcTextSize(edgeLabel.c_str());
                const ImVec2 pillMin(visual.pickPoint.x - labelSize.x * 0.5f - 8.0f, visual.pickPoint.y - 24.0f - labelSize.y);
                const ImVec2 pillMax(visual.pickPoint.x + labelSize.x * 0.5f + 8.0f, visual.pickPoint.y - 10.0f);
                draw->AddRectFilled(pillMin, pillMax, IM_COL32(34, 38, 46, 240), 5.0f);
                draw->AddRect(pillMin, pillMax, IM_COL32(248, 200, 120, 180), 5.0f, 0, 1.3f);
                draw->AddText(ImVec2(pillMin.x + 8.0f, pillMin.y + 2.0f), IM_COL32(236, 224, 196, 245), edgeLabel.c_str());
            }
        } else if (transitionActive) {
            const float glow = 4.0f + 2.0f * transitionAlpha;
            draw->AddCircleFilled(visual.pickPoint, glow, IM_COL32(106, 240, 144, 210));
        }
    };

    for (int i = 0; i < static_cast<int>(transitionVisuals.size()); ++i) {
        if (i == selectedTransitionIndex) { continue; }
        const bool hovered = (i == hoveredTransitionIndex);
        renderTransition(transitionVisuals[static_cast<size_t>(i)], hovered);
    }
    if (selectedTransitionIndex >= 0 && selectedTransitionIndex < static_cast<int>(transitionVisuals.size())) {
        const bool hovered = (selectedTransitionIndex == hoveredTransitionIndex);
        renderTransition(transitionVisuals[static_cast<size_t>(selectedTransitionIndex)], hovered);
    }

    if (selectedState != nullptr) {
        const auto selectedRectIt = stateRects.find(selectedState->id);
        if (selectedRectIt != stateRects.end()) {
            const StateRect &selectedRect = selectedRectIt->second;
            const float overlayWidth = 260.0f;
            const float overlayHeight = 156.0f;
            ImVec2 overlayMin(selectedRect.max.x + 18.0f, selectedRect.min.y - 4.0f);
            overlayMin.x = std::clamp(overlayMin.x, origin.x + 10.0f, origin.x + avail.x - overlayWidth - 10.0f);
            overlayMin.y = std::clamp(overlayMin.y, origin.y + 10.0f, origin.y + avail.y - overlayHeight - 10.0f);
            const ImVec2 overlayMax(overlayMin.x + overlayWidth, overlayMin.y + overlayHeight);
            draw->AddRectFilled(overlayMin, overlayMax, IM_COL32(28, 32, 38, 244), 8.0f);
            draw->AddRect(overlayMin, overlayMax, IM_COL32(100, 110, 126, 220), 8.0f, 0, 1.1f);
            draw->AddText(ImVec2(overlayMin.x + 10.0f, overlayMin.y + 8.0f),
                          IM_COL32(224, 232, 242, 245),
                          "State");
            draw->AddText(ImVec2(overlayMin.x + 10.0f, overlayMin.y + 22.0f),
                          IM_COL32(148, 158, 174, 230),
                          "Edit this state in place.");

            ImGui::SetCursorScreenPos(ImVec2(overlayMin.x + 10.0f, overlayMin.y + 42.0f));
            ImGui::PushID(selectedState->id.c_str());

            std::string stateName = selectedState->name;
            if (AnimationGraphInlineWidgets::DrawTextField("##StateCardName", nullptr, stateName, overlayWidth - 20.0f)) {
                MCEEditorUpdateAnimationGraphStateMachineState(context,
                                                               panelState.activeGraphHandle.c_str(),
                                                               node->id.c_str(),
                                                               selectedState->id.c_str(),
                                                               stateName.c_str(),
                                                               selectedState->clipHandle.empty() ? nullptr : selectedState->clipHandle.c_str(),
                                                               selectedState->nodeRefId.empty() ? nullptr : selectedState->nodeRefId.c_str(),
                                                               selectedState->isOneShot ? 1u : 0u,
                                                               selectedState->usesRootMotion ? 1u : 0u);
            }

            ImGui::SetCursorScreenPos(ImVec2(overlayMin.x + 10.0f, overlayMin.y + 72.0f));
            bool isOneShot = selectedState->isOneShot;
            if (AnimationGraphInlineWidgets::DrawBoolField("##StateCardOneShot", "One Shot", isOneShot)) {
                MCEEditorUpdateAnimationGraphStateMachineState(context,
                                                               panelState.activeGraphHandle.c_str(),
                                                               node->id.c_str(),
                                                               selectedState->id.c_str(),
                                                               selectedState->name.c_str(),
                                                               selectedState->clipHandle.empty() ? nullptr : selectedState->clipHandle.c_str(),
                                                               selectedState->nodeRefId.empty() ? nullptr : selectedState->nodeRefId.c_str(),
                                                               isOneShot ? 1u : 0u,
                                                               selectedState->usesRootMotion ? 1u : 0u);
            }
            ImGui::SameLine();
            bool usesRootMotion = selectedState->usesRootMotion;
            if (AnimationGraphInlineWidgets::DrawBoolField("##StateCardRootMotion", "Root Motion", usesRootMotion)) {
                MCEEditorUpdateAnimationGraphStateMachineState(context,
                                                               panelState.activeGraphHandle.c_str(),
                                                               node->id.c_str(),
                                                               selectedState->id.c_str(),
                                                               selectedState->name.c_str(),
                                                               selectedState->clipHandle.empty() ? nullptr : selectedState->clipHandle.c_str(),
                                                               selectedState->nodeRefId.empty() ? nullptr : selectedState->nodeRefId.c_str(),
                                                               selectedState->isOneShot ? 1u : 0u,
                                                               usesRootMotion ? 1u : 0u);
            }

            ImGui::SetCursorScreenPos(ImVec2(overlayMin.x + 10.0f, overlayMin.y + 104.0f));
            const bool isEntryState = (!node->stateMachineDefaultStateId.empty() && node->stateMachineDefaultStateId == selectedState->id);
            if (isEntryState) {
                ImGui::TextDisabled("Entry State");
            } else if (ImGui::Button("Set Entry", ImVec2(88.0f, 0.0f))) {
                MCEEditorSetAnimationGraphStateMachineDefaultState(context,
                                                                   panelState.activeGraphHandle.c_str(),
                                                                   node->id.c_str(),
                                                                   selectedState->id.c_str());
            }
            ImGui::SameLine();
            if (ImGui::Button(selectedState->nodeRefId.empty() ? "Create Graph" : "Open Graph", ImVec2(96.0f, 0.0f))) {
                openOrCreateSubgraphForState(*selectedState);
            }

            const std::string clipLabel = std::string("Clip: ") +
                (selectedState->clipHandle.empty() ? std::string("<None>") : selectedState->clipHandle);
            draw->AddText(ImVec2(overlayMin.x + 10.0f, overlayMin.y + 136.0f),
                          IM_COL32(168, 179, 196, 235),
                          clipLabel.c_str());
            ImGui::PopID();
        }
    }

    if (!pendingTransitionSourceStateId.empty()) {
        const char *instruction = "Select target state for transition (Esc to cancel)";
        draw->AddText(ImVec2(origin.x + 12.0f, origin.y + 10.0f), IM_COL32(248, 200, 120, 255), instruction);
        auto sourceRectIt = stateRects.find(pendingTransitionSourceStateId);
        if (sourceRectIt != stateRects.end()) {
            const ImVec2 previewStart(sourceRectIt->second.max.x + 10.0f, sourceRectIt->second.center.y);
            const ImVec2 mousePos = ImGui::GetMousePos();
            draw->AddLine(previewStart, mousePos, IM_COL32(248, 200, 120, 200), 2.4f);
            draw->AddCircleFilled(previewStart, 5.0f, IM_COL32(248, 200, 120, 255));
        }
    }

    if (ImGui::IsWindowFocused() && ImGui::IsKeyPressed(ImGuiKey_Escape) && !pendingTransitionSourceStateId.empty()) {
        pendingTransitionSourceStateId.clear();
    }
    if (ImGui::IsWindowFocused() && ImGui::IsKeyPressed(ImGuiKey_Delete)) {
        if (!selectedTransitionId.empty()) {
            MCEEditorRemoveAnimationGraphStateMachineTransition(context,
                                                                panelState.activeGraphHandle.c_str(),
                                                                node->id.c_str(),
                                                                selectedTransitionId.c_str());
            selectedTransitionId.clear();
        } else if (!selectedStateId.empty()) {
            MCEEditorRemoveAnimationGraphStateMachineState(context,
                                                           panelState.activeGraphHandle.c_str(),
                                                           node->id.c_str(),
                                                           selectedStateId.c_str());
            workspaceState.positionsByStateId.erase(selectedStateId);
            selectedStateId.clear();
            pendingTransitionSourceStateId.clear();
        }
    }

    if (ImGui::IsWindowHovered() && ImGui::IsMouseClicked(ImGuiMouseButton_Left) && !hoveredAnyState && !hoveredAnyTransition) {
        selectedTransitionId.clear();
        selectedStateId.clear();
        pendingTransitionSourceStateId.clear();
    }

    if (ImGui::IsWindowHovered() && ImGui::IsMouseClicked(ImGuiMouseButton_Right) && !hoveredAnyState && !hoveredAnyTransition) {
        popupState.openScreenPos = ImGui::GetMousePos();
        popupState.openCanvasPos = ImVec2(popupState.openScreenPos.x - origin.x, popupState.openScreenPos.y - origin.y);
        popupState.requestOpen = true;
        openBackgroundContextMenu = true;
    }
    if (openBackgroundContextMenu) {
        ImGui::OpenPopup(backgroundPopupId.c_str());
    }

    if (popupState.requestOpen) {
        ImGui::SetNextWindowPos(popupState.openScreenPos, ImGuiCond_Always);
    }
    if (ImGui::BeginPopup(backgroundPopupId.c_str())) {
        if (ImGui::MenuItem("Add State")) {
            addStateAt(popupState.openCanvasPos);
        }
        ImGui::EndPopup();
    }

    if (popupState.requestOpen) {
        ImGui::SetNextWindowPos(popupState.openScreenPos, ImGuiCond_Always);
    }
    if (ImGui::BeginPopup(statePopupId.c_str())) {
        if (!contextStateId.empty()) {
            if (ImGui::MenuItem("Set as Entry")) {
                MCEEditorSetAnimationGraphStateMachineDefaultState(context,
                                                                   panelState.activeGraphHandle.c_str(),
                                                                   node->id.c_str(),
                                                                   contextStateId.c_str());
                contextStateId.clear();
                ImGui::CloseCurrentPopup();
            }
            if (ImGui::MenuItem("Start Transition From Here")) {
                pendingTransitionSourceStateId = contextStateId;
                contextStateId.clear();
                ImGui::CloseCurrentPopup();
            }
            if (ImGui::MenuItem("Delete State")) {
                MCEEditorRemoveAnimationGraphStateMachineState(context,
                                                               panelState.activeGraphHandle.c_str(),
                                                               node->id.c_str(),
                                                               contextStateId.c_str());
                if (selectedStateId == contextStateId) {
                    selectedStateId.clear();
                }
                workspaceState.positionsByStateId.erase(contextStateId);
                if (pendingTransitionSourceStateId == contextStateId) {
                    pendingTransitionSourceStateId.clear();
                }
                contextStateId.clear();
                ImGui::CloseCurrentPopup();
            }
        }
        ImGui::EndPopup();
    }
    if (!ImGui::IsPopupOpen(statePopupId.c_str())) {
        contextStateId.clear();
    }

    if (popupState.requestOpen) {
        ImGui::SetNextWindowPos(popupState.openScreenPos, ImGuiCond_Always);
    }
    if (ImGui::BeginPopup(transitionPopupId.c_str())) {
        if (!contextTransitionId.empty()) {
            if (ImGui::MenuItem("Delete Transition")) {
                MCEEditorRemoveAnimationGraphStateMachineTransition(context,
                                                                    panelState.activeGraphHandle.c_str(),
                                                                    node->id.c_str(),
                                                                    contextTransitionId.c_str());
                if (selectedTransitionId == contextTransitionId) {
                    selectedTransitionId.clear();
                }
                contextTransitionId.clear();
                ImGui::CloseCurrentPopup();
            }
        }
        ImGui::EndPopup();
    }
    if (!ImGui::IsPopupOpen(transitionPopupId.c_str())) {
        contextTransitionId.clear();
    }
    if (!ImGui::IsPopupOpen(backgroundPopupId.c_str()) &&
        !ImGui::IsPopupOpen(statePopupId.c_str()) &&
        !ImGui::IsPopupOpen(transitionPopupId.c_str())) {
        popupState.requestOpen = false;
    }

    ImGui::EndChild();
    selectedTransition = nullptr;
    if (!selectedTransitionId.empty()) {
        for (const auto &transition : node->stateMachineTransitions) {
            if (transition.id == selectedTransitionId) {
                selectedTransition = const_cast<AnimationGraphNodeRecord::StateMachineTransitionRecord *>(&transition);
                break;
            }
        }
    }

    ImGui::BeginChild("StateMachineTransitionPane", ImVec2(0.0f, 0.0f), true);
    if (selectedTransition == nullptr) {
        DrawWorkspaceSectionBanner("Transition", "Select an edge above to author its rules and graph here.");
    } else {
        const auto *fromState = FindStateInMachine(*node, selectedTransition->fromStateId);
        const auto *toState = FindStateInMachine(*node, selectedTransition->toStateId);
        const std::string fromName = fromState ? fromState->name : selectedTransition->fromStateId;
        const std::string toName = toState ? toState->name : selectedTransition->toStateId;
        const std::string transitionTitle = "Transition: " + fromName + " -> " + toName;
        DrawWorkspaceSectionBanner(transitionTitle.c_str(), "This lower pane is the only transition authoring surface.");
        bool hasMinTime = selectedTransition->hasMinimumNormalizedTime;
        if (AnimationGraphInlineWidgets::DrawBoolField("##TransitionPaneHasMinTime", "Use Minimum Normalized Time", hasMinTime)) {
            MCEEditorUpdateAnimationGraphStateMachineTransition(context,
                                                                panelState.activeGraphHandle.c_str(),
                                                                node->id.c_str(),
                                                                selectedTransition->id.c_str(),
                                                                selectedTransition->fromStateId.c_str(),
                                                                selectedTransition->toStateId.c_str(),
                                                                selectedTransition->duration,
                                                                hasMinTime ? 1u : 0u,
                                                                hasMinTime ? selectedTransition->minimumNormalizedTime : 0.0f);
        }
        if (hasMinTime) {
            float minimumNormalizedTime = selectedTransition->minimumNormalizedTime;
            if (AnimationGraphInlineWidgets::DrawFloatField("##TransitionPaneMinTime",
                                                            "Min Normalized Time",
                                                            minimumNormalizedTime,
                                                            0.01f,
                                                            0.0f,
                                                            1.0f,
                                                            "%.3f",
                                                            true)) {
                MCEEditorUpdateAnimationGraphStateMachineTransition(context,
                                                                    panelState.activeGraphHandle.c_str(),
                                                                    node->id.c_str(),
                                                                    selectedTransition->id.c_str(),
                                                                    selectedTransition->fromStateId.c_str(),
                                                                    selectedTransition->toStateId.c_str(),
                                                                    selectedTransition->duration,
                                                                    1u,
                                                                    minimumNormalizedTime);
            }
        }
        ImGui::TextDisabled("Conditions and graph logic live in this pane.");
        if (transitionCanvasRenderer != nullptr) {
            transitionCanvasRenderer(*selectedTransition, "SplitTransitionGraphCanvas");
        } else {
            ImGui::TextDisabled("Transition graph renderer is unavailable.");
        }
    }
    ImGui::EndChild();
}
