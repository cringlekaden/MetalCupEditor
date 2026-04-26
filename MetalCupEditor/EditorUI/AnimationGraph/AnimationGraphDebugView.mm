#include "AnimationGraphDebugView.h"

#include "../../ImGui/imgui.h"

void DrawAnimationGraphDebugView(const AnimationGraphSnapshot &snapshot,
                                 const AnimationGraphRuntimeDebugSnapshot &runtimeDebug,
                                 MCEPanelState::AnimationGraphPanelState &panelState) {
    (void)snapshot;
    if (runtimeDebug.isPlaying) {
        ImGui::SeparatorText("Runtime Debug");
        ImGui::Checkbox("Show Runtime Debug", &panelState.showRuntimeDebug);
        if (panelState.showRuntimeDebug) {
            if (ImGui::CollapsingHeader("Graph Trace", ImGuiTreeNodeFlags_DefaultOpen)) {
                ImGui::TextDisabled("Entries: %zu", runtimeDebug.traceEntries.size());
                ImGui::BeginChild("RuntimeTraceList", ImVec2(0.0f, 160.0f), true);
                for (const auto &entry : runtimeDebug.traceEntries) {
                    const std::string nodeLabel = entry.nodeTitle.empty() ? entry.nodeID : entry.nodeTitle;
                    ImGui::Text("%s [%s]", nodeLabel.c_str(), entry.nodeType.c_str());
                    ImGui::TextDisabled("%s", entry.outputSummary.c_str());
                    if (panelState.showIDs && !entry.nodeID.empty()) {
                        ImGui::TextDisabled("id: %s", entry.nodeID.c_str());
                    }
                    ImGui::Separator();
                }
                ImGui::EndChild();
            }
        }
    }
    if (!runtimeDebug.isPlaying &&
        !(panelState.selectedInputIndex < 0 && panelState.selectedLocalVariableIndex < 0)) {
        ImGui::SeparatorText("Runtime Debug");
        ImGui::Checkbox("Show Runtime Debug", &panelState.showRuntimeDebug);
    }
}

