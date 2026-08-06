#pragma once

#include "AnimationGraphWorkspaceRouter.h"
#include <string>

struct AnimationGraphBlendSpaceWorkspaceState {
    int selectedSampleIndex = -1;
};

namespace AnimationGraphBlendSpaceStateStore {
AnimationGraphBlendSpaceWorkspaceState &StateForWorkspace(const std::string &graphHandle,
                                                          const AnimationGraphWorkspaceDescriptor &workspace);
}
