#include "AnimationGraphInspector.h"

#include "AnimationGraphDebugView.h"

#include "../../ImGui/imgui.h"

void DrawAnimationGraphInspector(void *context,
                                 AnimationGraphSnapshot &snapshot,
                                 MCEPanelState::AnimationGraphPanelState &state,
                                 bool hasRuntimeDebugSnapshot,
                                 const AnimationGraphRuntimeDebugSnapshot &runtimeDebugSnapshot) {
    (void)context;
    (void)snapshot;
    (void)hasRuntimeDebugSnapshot;

    ImGui::BeginChild("AnimationGraphDetailsBottom", ImVec2(0.0f, 0.0f), true);
    ImGui::SeparatorText("Details");
    ImGui::Checkbox("Show IDs", &state.showIDs);
    ImGui::Checkbox("Show Sort Indices", &state.showSortIndices);
    ImGui::Checkbox("Show Runtime Debug", &state.showRuntimeDebug);
    ImGui::TextDisabled("Input and local variable authoring now lives entirely in the left panel.");

    DrawAnimationGraphDebugView(snapshot, runtimeDebugSnapshot, state);
    ImGui::EndChild();
}
