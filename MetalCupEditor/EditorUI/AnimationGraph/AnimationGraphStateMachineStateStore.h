#pragma once

#include "AnimationGraphWorkspaceRouter.h"
#include "../../ImGui/imgui.h"
#include <string>
#include <unordered_map>

struct AnimationGraphStateMachineWorkspaceState {
    struct NodePopupState {
        ImVec2 openScreenPos = ImVec2(0.0f, 0.0f);
        ImVec2 openCanvasPos = ImVec2(0.0f, 0.0f);
        bool requestOpen = false;
    };

    std::string selectedStateId;
    std::string selectedTransitionId;
    std::string pendingTransitionSourceStateId;
    std::string contextStateId;
    std::string contextTransitionId;
    std::unordered_map<std::string, ImVec2> positionsByStateId;
    NodePopupState popupState;
};

namespace AnimationGraphStateMachineStateStore {
AnimationGraphStateMachineWorkspaceState &StateForWorkspace(const std::string &graphHandle,
                                                            const AnimationGraphWorkspaceDescriptor &workspace);
}
