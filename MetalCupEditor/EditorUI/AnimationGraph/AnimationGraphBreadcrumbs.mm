#include "AnimationGraphWorkspaceRouter.h"
#include "AnimationGraphModels.h"

#include "../../ImGui/imgui.h"

namespace {
const AnimationGraphNodeRecord *FindNodeByIdForBreadcrumbs(const AnimationGraphSnapshot &snapshot, const std::string &nodeId) {
    for (const auto &node : snapshot.nodes) {
        if (node.id == nodeId) { return &node; }
    }
    return nullptr;
}

const AnimationGraphNodeRecord::StateMachineStateRecord *FindStateInMachineForBreadcrumbs(
    const AnimationGraphNodeRecord &machineNode,
    const std::string &stateId) {
    for (const auto &state : machineNode.stateMachineStates) {
        if (state.id == stateId) { return &state; }
    }
    return nullptr;
}

std::string WorkspaceBreadcrumbLabel(const AnimationGraphWorkspaceDescriptor &descriptor,
                                     const AnimationGraphSnapshot &snapshot) {
    switch (descriptor.kind) {
        case AnimationGraphWorkspaceKind::RootGraph:
            return snapshot.name.empty() ? std::string("Graph") : snapshot.name;
        case AnimationGraphWorkspaceKind::StateMachine: {
            const auto *node = FindNodeByIdForBreadcrumbs(snapshot, descriptor.nodeId);
            if (!node) { return "State Machine"; }
            return node->title.empty() ? std::string("State Machine") : node->title;
        }
        case AnimationGraphWorkspaceKind::StateSubgraph: {
            const auto *machineNode = FindNodeByIdForBreadcrumbs(snapshot, descriptor.nodeId);
            if (!machineNode) { return "State"; }
            const auto *state = FindStateInMachineForBreadcrumbs(*machineNode, descriptor.stateId);
            return state ? (state->name.empty() ? std::string("State") : state->name) : std::string("State");
        }
        case AnimationGraphWorkspaceKind::BlendSpace: {
            const auto *node = FindNodeByIdForBreadcrumbs(snapshot, descriptor.nodeId);
            if (!node) { return "Blend Space"; }
            return node->title.empty() ? std::string("Blend Space") : node->title;
        }
    }
    return "Workspace";
}
}

namespace AnimationGraphBreadcrumbs {
void DrawWorkspaceBreadcrumbs(const std::string &graphHandle,
                              const AnimationGraphWorkspacePath &path,
                              const AnimationGraphSnapshot &snapshot) {
    ImDrawList *draw = ImGui::GetWindowDrawList();
    const ImVec2 start = ImGui::GetCursorScreenPos();
    const float width = ImGui::GetContentRegionAvail().x;
    const ImVec2 size(width, 42.0f);
    draw->AddRectFilled(start, ImVec2(start.x + size.x, start.y + size.y), IM_COL32(24, 27, 32, 255), 8.0f);
    draw->AddRect(start, ImVec2(start.x + size.x, start.y + size.y), IM_COL32(56, 63, 74, 255), 8.0f, 0, 1.0f);
    draw->AddText(ImVec2(start.x + 12.0f, start.y + 5.0f), IM_COL32(140, 150, 168, 230), "Workspace");
    ImGui::SetCursorScreenPos(ImVec2(start.x + 12.0f, start.y + 20.0f));
    int clickedIndex = -1;
    for (int i = 0; i < static_cast<int>(path.items.size()); ++i) {
        const std::string label = WorkspaceBreadcrumbLabel(path.items[static_cast<size_t>(i)], snapshot);
        ImGui::PushID(i);
        const bool current = (i == static_cast<int>(path.items.size()) - 1);
        if (current) {
            ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(224, 232, 240, 245));
            ImGui::TextUnformatted(label.c_str());
            ImGui::PopStyleColor();
        } else if (ImGui::SmallButton(label.c_str())) {
            clickedIndex = i;
        }
        ImGui::PopID();
        if (i + 1 < static_cast<int>(path.items.size())) {
            ImGui::SameLine(0.0f, 8.0f);
            ImGui::TextDisabled(">");
            ImGui::SameLine(0.0f, 8.0f);
        }
    }
    if (clickedIndex >= 0 && clickedIndex < static_cast<int>(path.items.size())) {
        AnimationGraphWorkspaceRouter::TruncateWorkspacePath(graphHandle, static_cast<size_t>(clickedIndex + 1));
    }
    ImGui::SetCursorScreenPos(ImVec2(start.x, start.y + size.y));
    ImGui::Dummy(size);
    ImGui::Spacing();
}
}
