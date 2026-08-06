#include "AnimationGraphStateMachineStateStore.h"
#include "AnimationGraphUIStateStore.h"

namespace AnimationGraphStateMachineStateStore {
AnimationGraphStateMachineWorkspaceState &StateForWorkspace(const std::string &graphHandle,
                                                            const AnimationGraphWorkspaceDescriptor &workspace) {
    return AnimationGraphUIStateStore::StateMachineStateForWorkspace(graphHandle, workspace);
}
}
