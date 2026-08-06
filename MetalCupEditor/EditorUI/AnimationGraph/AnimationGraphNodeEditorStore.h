#pragma once

#include "../../ThirdParty/imgui-node-editor/imgui_node_editor.h"
#include <string>
#include <unordered_map>
#include <unordered_set>

struct AnimationGraphNodeEditorState {
    ax::NodeEditor::EditorContext *context = nullptr;
    std::unordered_set<std::string> initializedNodePositions;
    std::unordered_map<std::string, ImVec2> parameterNodePositions;
    std::unordered_set<std::string> initializedParameterNodePositions;
    bool didAutoFrame = false;
    std::string settingsFilePath;
};

namespace AnimationGraphNodeEditorStore {
AnimationGraphNodeEditorState &EditorStateForGraph(const std::string &graphHandle);
std::unordered_set<std::string> &SelectedNodeSetForGraph(const std::string &graphHandle);
}
