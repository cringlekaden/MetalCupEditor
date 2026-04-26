#pragma once

#include "AnimationGraphWorkspaceRouter.h"
#include <string>

struct AnimationGraphStateMachineWorkspaceState {
    std::string selectedStateId;
    std::string selectedTransitionId;
};

namespace AnimationGraphStateMachineStateStore {
AnimationGraphStateMachineWorkspaceState &StateForWorkspace(const std::string &graphHandle,
                                                            const AnimationGraphWorkspaceDescriptor &workspace);
}

