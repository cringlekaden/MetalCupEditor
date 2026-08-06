#pragma once

#include "../../ImGui/imgui.h"
#include "../../ThirdParty/imgui-node-editor/imgui_node_editor.h"

#include <cmath>

namespace AnimationGraphCanvasHost {

namespace ed = ax::NodeEditor;

struct Config {
    ed::EditorContext *editorContext = nullptr;
    const char *canvasName = nullptr;
    bool *didAutoFrame = nullptr;
    bool *hasInteractedWithCanvas = nullptr;
};

inline void PushSharedStyle() {
    ed::PushStyleVar(ed::StyleVar_NodePadding, ImVec4(8.0f, 6.0f, 8.0f, 8.0f));
    ed::PushStyleVar(ed::StyleVar_NodeRounding, 7.0f);
    ed::PushStyleVar(ed::StyleVar_NodeBorderWidth, 1.0f);
    ed::PushStyleVar(ed::StyleVar_HoveredNodeBorderWidth, 1.8f);
    ed::PushStyleVar(ed::StyleVar_SelectedNodeBorderWidth, 2.1f);
    ed::PushStyleVar(ed::StyleVar_PinRadius, 4.0f);
    ed::PushStyleVar(ed::StyleVar_PinArrowSize, 0.0f);
    ed::PushStyleVar(ed::StyleVar_LinkStrength, 88.0f);
    ed::PushStyleColor(ed::StyleColor_Bg, ImVec4(0.10f, 0.11f, 0.12f, 1.0f));
    ed::PushStyleColor(ed::StyleColor_Grid, ImVec4(1.0f, 1.0f, 1.0f, 0.05f));
    ed::PushStyleColor(ed::StyleColor_NodeBg, ImVec4(0.14f, 0.15f, 0.16f, 0.98f));
    ed::PushStyleColor(ed::StyleColor_NodeBorder, ImVec4(0.30f, 0.32f, 0.35f, 0.85f));
    ed::PushStyleColor(ed::StyleColor_HovNodeBorder, ImVec4(0.60f, 0.66f, 0.74f, 1.0f));
    ed::PushStyleColor(ed::StyleColor_SelNodeBorder, ImVec4(0.79f, 0.63f, 0.35f, 1.0f));
    ed::PushStyleColor(ed::StyleColor_PinRect, ImVec4(0.45f, 0.50f, 0.56f, 0.10f));
    ed::PushStyleColor(ed::StyleColor_PinRectBorder, ImVec4(0.58f, 0.64f, 0.72f, 0.45f));
}

inline void PopSharedStyle() {
    ed::PopStyleColor(8);
    ed::PopStyleVar(8);
}

template <typename BodyFn>
inline void DrawCanvas(const Config &config, BodyFn &&body) {
    if (config.editorContext == nullptr || config.canvasName == nullptr) {
        return;
    }
    // Canvas lifetime ownership is centralized here: callers only render into the
    // active editor context and must not manually end the editor or pop shared style.
    ed::SetCurrentEditor(config.editorContext);
    PushSharedStyle();
    ed::Begin(config.canvasName);

    if (config.hasInteractedWithCanvas != nullptr &&
        ImGui::IsWindowHovered(ImGuiHoveredFlags_AllowWhenBlockedByActiveItem)) {
        const ImGuiIO &io = ImGui::GetIO();
        if (std::fabs(io.MouseWheel) > 0.001f ||
            ImGui::IsMouseDragging(ImGuiMouseButton_Left, 0.0f) ||
            ImGui::IsMouseDragging(ImGuiMouseButton_Right, 0.0f)) {
            *config.hasInteractedWithCanvas = true;
        }
    }

    body();

    if (config.didAutoFrame != nullptr && !*config.didAutoFrame) {
        ed::NavigateToContent(0.0f);
        *config.didAutoFrame = true;
    }

    ed::End();
    PopSharedStyle();
    ed::SetCurrentEditor(nullptr);
}

} // namespace AnimationGraphCanvasHost
