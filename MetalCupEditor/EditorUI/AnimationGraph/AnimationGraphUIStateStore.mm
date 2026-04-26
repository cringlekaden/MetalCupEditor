#include "AnimationGraphUIStateStore.h"

#include "../../ThirdParty/imgui-node-editor/imgui_node_editor.h"

namespace {
std::unordered_map<std::string, AnimationGraphWorkspacePath> gWorkspacePathsByGraph;
std::unordered_map<std::string, AnimationGraphNodeEditorState> gNodeEditorStatesByGraph;
std::unordered_map<std::string, std::unordered_set<std::string>> gSelectedNodeSetsByGraph;
std::unordered_map<std::string, AnimationGraphStateMachineWorkspaceState> gStateMachineStateByWorkspace;
std::unordered_map<std::string, AnimationGraphBlendSpaceWorkspaceState> gBlendSpaceStateByWorkspace;
AnimationGraphEditorDrafts gEditorDrafts;
std::unordered_map<std::string, int32_t> gSelectedInputIndexByGraph;
std::unordered_map<std::string, int32_t> gSelectedLocalIndexByGraph;
std::unordered_map<std::string, bool> gFocusInputRenameByGraph;
std::unordered_map<std::string, bool> gFocusLocalRenameByGraph;

std::string WorkspaceKey(const std::string &graphHandle, const AnimationGraphWorkspaceDescriptor &workspace) {
    return graphHandle +
        "|" + std::to_string(static_cast<int>(workspace.kind)) +
        "|" + workspace.nodeId +
        "|" + workspace.stateId +
        "|" + workspace.transitionId;
}
}

namespace AnimationGraphUIStateStore {
AnimationGraphWorkspacePath &WorkspacePathForGraph(const std::string &graphHandle) {
    AnimationGraphWorkspacePath &path = gWorkspacePathsByGraph[graphHandle];
    if (path.items.empty()) {
        path.items.push_back(AnimationGraphWorkspaceDescriptor());
    }
    return path;
}

AnimationGraphNodeEditorState &NodeEditorStateForGraph(const std::string &graphHandle) {
    return gNodeEditorStatesByGraph[graphHandle];
}

std::unordered_set<std::string> &SelectedNodeSetForGraph(const std::string &graphHandle) {
    return gSelectedNodeSetsByGraph[graphHandle];
}

AnimationGraphStateMachineWorkspaceState &StateMachineStateForWorkspace(const std::string &graphHandle,
                                                                        const AnimationGraphWorkspaceDescriptor &workspace) {
    return gStateMachineStateByWorkspace[WorkspaceKey(graphHandle, workspace)];
}

AnimationGraphBlendSpaceWorkspaceState &BlendSpaceStateForWorkspace(const std::string &graphHandle,
                                                                    const AnimationGraphWorkspaceDescriptor &workspace) {
    return gBlendSpaceStateByWorkspace[WorkspaceKey(graphHandle, workspace)];
}

AnimationGraphEditorDrafts &EditorDrafts() {
    return gEditorDrafts;
}

int32_t &SelectedInputIndexForGraph(const std::string &graphHandle) {
    return gSelectedInputIndexByGraph[graphHandle];
}

int32_t &SelectedLocalIndexForGraph(const std::string &graphHandle) {
    return gSelectedLocalIndexByGraph[graphHandle];
}

bool &FocusInputRenameForGraph(const std::string &graphHandle) {
    return gFocusInputRenameByGraph[graphHandle];
}

bool &FocusLocalRenameForGraph(const std::string &graphHandle) {
    return gFocusLocalRenameByGraph[graphHandle];
}

void ClearStateForGraph(const std::string &graphHandle) {
    auto editorStateIt = gNodeEditorStatesByGraph.find(graphHandle);
    if (editorStateIt != gNodeEditorStatesByGraph.end()) {
        if (editorStateIt->second.context != nullptr) {
            ax::NodeEditor::DestroyEditor(editorStateIt->second.context);
            editorStateIt->second.context = nullptr;
        }
        gNodeEditorStatesByGraph.erase(editorStateIt);
    }

    gWorkspacePathsByGraph.erase(graphHandle);
    gSelectedNodeSetsByGraph.erase(graphHandle);
    gSelectedInputIndexByGraph.erase(graphHandle);
    gSelectedLocalIndexByGraph.erase(graphHandle);
    gFocusInputRenameByGraph.erase(graphHandle);
    gFocusLocalRenameByGraph.erase(graphHandle);

    for (auto it = gStateMachineStateByWorkspace.begin(); it != gStateMachineStateByWorkspace.end();) {
        if (it->first.rfind(graphHandle + "|", 0) == 0) {
            it = gStateMachineStateByWorkspace.erase(it);
        } else {
            ++it;
        }
    }
    for (auto it = gBlendSpaceStateByWorkspace.begin(); it != gBlendSpaceStateByWorkspace.end();) {
        if (it->first.rfind(graphHandle + "|", 0) == 0) {
            it = gBlendSpaceStateByWorkspace.erase(it);
        } else {
            ++it;
        }
    }
}

void ClearAllAnimationGraphUIState() {
    for (auto &entry : gNodeEditorStatesByGraph) {
        if (entry.second.context != nullptr) {
            ax::NodeEditor::DestroyEditor(entry.second.context);
            entry.second.context = nullptr;
        }
    }
    gWorkspacePathsByGraph.clear();
    gNodeEditorStatesByGraph.clear();
    gSelectedNodeSetsByGraph.clear();
    gStateMachineStateByWorkspace.clear();
    gBlendSpaceStateByWorkspace.clear();
    gEditorDrafts = AnimationGraphEditorDrafts();
    gSelectedInputIndexByGraph.clear();
    gSelectedLocalIndexByGraph.clear();
    gFocusInputRenameByGraph.clear();
    gFocusLocalRenameByGraph.clear();
}

void PruneStateToActiveGraph(const std::string &activeGraphHandle) {
    if (activeGraphHandle.empty()) {
        ClearAllAnimationGraphUIState();
        return;
    }

    for (auto it = gWorkspacePathsByGraph.begin(); it != gWorkspacePathsByGraph.end();) {
        if (it->first != activeGraphHandle) {
            ClearStateForGraph(it->first);
            it = gWorkspacePathsByGraph.begin();
        } else {
            ++it;
        }
    }
}
}

