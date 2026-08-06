#include "AnimationGraphBlendSpaceStateStore.h"
#include "AnimationGraphUIStateStore.h"

namespace AnimationGraphBlendSpaceStateStore {
AnimationGraphBlendSpaceWorkspaceState &StateForWorkspace(const std::string &graphHandle,
                                                          const AnimationGraphWorkspaceDescriptor &workspace) {
    return AnimationGraphUIStateStore::BlendSpaceStateForWorkspace(graphHandle, workspace);
}
}
