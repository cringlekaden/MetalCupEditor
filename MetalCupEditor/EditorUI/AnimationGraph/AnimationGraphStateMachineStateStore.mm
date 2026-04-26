#include "AnimationGraphStateMachineStateStore.h"

#include <unordered_map>

namespace {
std::unordered_map<std::string, AnimationGraphStateMachineWorkspaceState> gStateByWorkspaceKey;

std::string WorkspaceKey(const std::string &graphHandle, const AnimationGraphWorkspaceDescriptor &workspace) {
    return graphHandle +
        "|" + std::to_string(static_cast<int>(workspace.kind)) +
        "|" + workspace.nodeId +
        "|" + workspace.stateId +
        "|" + workspace.transitionId;
}
}

namespace AnimationGraphStateMachineStateStore {
AnimationGraphStateMachineWorkspaceState &StateForWorkspace(const std::string &graphHandle,
                                                            const AnimationGraphWorkspaceDescriptor &workspace) {
    return gStateByWorkspaceKey[WorkspaceKey(graphHandle, workspace)];
}
}

