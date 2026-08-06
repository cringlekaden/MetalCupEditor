#include "AnimationGraphNodeEditorStore.h"
#include "AnimationGraphUIStateStore.h"

namespace AnimationGraphNodeEditorStore {
AnimationGraphNodeEditorState &EditorStateForGraph(const std::string &graphHandle) {
    return AnimationGraphUIStateStore::NodeEditorStateForGraph(graphHandle);
}

std::unordered_set<std::string> &SelectedNodeSetForGraph(const std::string &graphHandle) {
    return AnimationGraphUIStateStore::SelectedNodeSetForGraph(graphHandle);
}
}
