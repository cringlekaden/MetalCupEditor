#pragma once

#include "AnimationGraphWorkspaceRouter.h"
#include <string>

struct AnimationGraphBlendSpaceWorkspaceState {
    int selectedSampleIndex = -1;
    std::string xLabel = "X";
    std::string yLabel = "Y";
    float xMin = -1.0f;
    float xMax = 1.0f;
    float yMin = -1.0f;
    float yMax = 1.0f;
    bool initializedFromNode = false;
};

namespace AnimationGraphBlendSpaceStateStore {
AnimationGraphBlendSpaceWorkspaceState &StateForWorkspace(const std::string &graphHandle,
                                                          const AnimationGraphWorkspaceDescriptor &workspace);
}

