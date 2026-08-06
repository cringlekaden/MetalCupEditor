#pragma once

#include "../Panels/PanelState.h"
#include <cstdint>
#include <string>
#include <vector>

enum class AnimationGraphWorkspaceKind : int32_t {
    RootGraph = 0,
    StateMachine = 1,
    StateSubgraph = 2,
    BlendSpace = 3
};

struct AnimationGraphWorkspaceDescriptor {
    AnimationGraphWorkspaceKind kind = AnimationGraphWorkspaceKind::RootGraph;
    std::string nodeId;
    std::string stateId;
    std::string transitionId;
};

struct AnimationGraphWorkspacePath {
    std::vector<AnimationGraphWorkspaceDescriptor> items;
};

namespace AnimationGraphWorkspaceRouter {
AnimationGraphWorkspacePath &GetWorkspacePath(const std::string &graphHandle);
const AnimationGraphWorkspaceDescriptor &GetCurrentWorkspace(const std::string &graphHandle);
void PushWorkspace(const std::string &graphHandle, const AnimationGraphWorkspaceDescriptor &descriptor);
void PopWorkspace(const std::string &graphHandle);
void TruncateWorkspacePath(const std::string &graphHandle, size_t count);
void ResetWorkspacePathForHandle(const std::string &graphHandle);
void ApplyPendingNavigation(const std::string &graphHandle, MCEPanelState::AnimationGraphPanelState &panelState);
}
