#pragma once

#include "AnimationGraphBlendSpaceStateStore.h"
#include "AnimationGraphEditorDrafts.h"
#include "AnimationGraphNodeEditorStore.h"
#include "AnimationGraphStateMachineStateStore.h"
#include "AnimationGraphWorkspaceRouter.h"

#include <string>
#include <unordered_map>
#include <unordered_set>

namespace AnimationGraphUIStateStore {
AnimationGraphWorkspacePath &WorkspacePathForGraph(const std::string &graphHandle);
AnimationGraphNodeEditorState &NodeEditorStateForGraph(const std::string &graphHandle);
std::unordered_set<std::string> &SelectedNodeSetForGraph(const std::string &graphHandle);
AnimationGraphStateMachineWorkspaceState &StateMachineStateForWorkspace(const std::string &graphHandle,
                                                                        const AnimationGraphWorkspaceDescriptor &workspace);
AnimationGraphBlendSpaceWorkspaceState &BlendSpaceStateForWorkspace(const std::string &graphHandle,
                                                                    const AnimationGraphWorkspaceDescriptor &workspace);
AnimationGraphEditorDrafts &EditorDrafts();

int32_t &SelectedInputIndexForGraph(const std::string &graphHandle);
int32_t &SelectedLocalIndexForGraph(const std::string &graphHandle);
bool &FocusInputRenameForGraph(const std::string &graphHandle);
bool &FocusLocalRenameForGraph(const std::string &graphHandle);

void ClearStateForGraph(const std::string &graphHandle);
void ClearAllAnimationGraphUIState();
void PruneStateToActiveGraph(const std::string &activeGraphHandle);
}

