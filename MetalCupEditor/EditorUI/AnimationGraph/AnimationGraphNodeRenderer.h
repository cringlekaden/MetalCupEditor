#pragma once

#include "AnimationGraphInlineWidgets.h"
#include "AnimationGraphSchema.h"

#include "../../ImGui/imgui.h"
#include "../../ThirdParty/imgui-node-editor/imgui_node_editor.h"

#include <functional>
#include <string>
#include <vector>

namespace AnimationGraphNodeRenderer {

namespace ed = ax::NodeEditor;

struct RenderRequest {
    ed::NodeId editorNodeId;
    std::string nodeId;
    const AnimationGraphSchema::AnimGraphNodeSchema *schema = nullptr;
    std::string title;
    std::vector<std::string> summaryLines;
    std::function<ed::PinId(int32_t slot, bool isInput)> makePinId;
    std::function<void(const ed::PinId &pinId,
                       int32_t slot,
                       bool isInput,
                       const AnimationGraphSchema::AnimGraphPinSchema *pinSchema)> registerPin;
    std::function<void()> renderHeaderExtras;
    std::function<void()> renderInlineBody;
};

inline void RenderPin(const AnimationGraphSchema::AnimGraphPinSchema &pinSchema, bool isInput) {
    const ImVec4 pinColor = AnimationGraphSchema::PinColor(pinSchema.type);
    if (isInput) {
        ImGui::PushStyleColor(ImGuiCol_Text, pinColor);
        ImGui::TextUnformatted(AnimationGraphSchema::PinIcon(pinSchema.type));
        ImGui::PopStyleColor();
        ImGui::SameLine(0.0f, 6.0f);
        ImGui::TextUnformatted(pinSchema.label.c_str());
    } else {
        ImGui::TextUnformatted(pinSchema.label.c_str());
        ImGui::SameLine(0.0f, 6.0f);
        ImGui::PushStyleColor(ImGuiCol_Text, pinColor);
        ImGui::TextUnformatted(AnimationGraphSchema::PinIcon(pinSchema.type));
        ImGui::PopStyleColor();
    }
}

inline void RenderNodeHeader(const RenderRequest &request) {
    const ImVec4 tint = request.schema ? request.schema->style.headerTint : ImVec4(0.43f, 0.43f, 0.43f, 1.0f);
    ImGui::PushStyleColor(ImGuiCol_Text, tint);
    ImGui::TextUnformatted(request.title.c_str());
    ImGui::PopStyleColor();
    if (request.renderHeaderExtras) {
        request.renderHeaderExtras();
    }
}

inline void RenderNodeBody(const RenderRequest &request) {
    if (request.renderInlineBody) {
        request.renderInlineBody();
    } else {
        AnimationGraphInlineWidgets::DrawSummaryLines(request.summaryLines);
    }
}

inline void DrawNodeChrome(const RenderRequest &request) {
    if (request.schema == nullptr) {
        return;
    }
    const ImVec2 nodePos = ed::GetNodePosition(request.editorNodeId);
    const ImVec2 nodeSize = ed::GetNodeSize(request.editorNodeId);
    if (nodeSize.x <= 0.0f || nodeSize.y <= 0.0f) {
        return;
    }
    ImDrawList *nodeBg = ed::GetNodeBackgroundDrawList(request.editorNodeId);
    const ImVec4 tint = request.schema->style.headerTint;
    const bool highlightNode = request.schema->style.emphasizeBorder || request.schema->behavior.supportsWorkspaceEdit;
    const ImU32 headerColor = IM_COL32(static_cast<int>(tint.x * 255.0f),
                                       static_cast<int>(tint.y * 255.0f),
                                       static_cast<int>(tint.z * 255.0f),
                                       highlightNode ? 170 : 120);
    nodeBg->AddRectFilled(nodePos,
                          ImVec2(nodePos.x + nodeSize.x, nodePos.y + 26.0f),
                          headerColor,
                          7.0f,
                          ImDrawFlags_RoundCornersTop);
    if (highlightNode) {
        nodeBg->AddRect(nodePos,
                        ImVec2(nodePos.x + nodeSize.x, nodePos.y + nodeSize.y),
                        IM_COL32(static_cast<int>(tint.x * 255.0f),
                                 static_cast<int>(tint.y * 255.0f),
                                 static_cast<int>(tint.z * 255.0f),
                                 220),
                        7.0f,
                        0,
                        1.8f);
    }
}

inline void RenderNode(const RenderRequest &request) {
    if (request.schema == nullptr || !request.makePinId || !request.registerPin) {
        return;
    }

    ed::BeginNode(request.editorNodeId);
    ImGui::PushStyleVar(ImGuiStyleVar_ItemSpacing, ImVec2(6.0f, 5.0f));
    ImGui::PushStyleVar(ImGuiStyleVar_FramePadding, ImVec2(4.0f, 3.0f));

    RenderNodeHeader(request);
    ImGui::Dummy(ImVec2(0.0f, 4.0f));
    ImGui::Separator();
    ImGui::Dummy(ImVec2(0.0f, 2.0f));

    ImGui::BeginGroup();
    const int32_t inputCount = AnimationGraphSchema::PinCount(*request.schema, AnimationGraphSchema::PinDirection::Input);
    for (int32_t slot = 0; slot < inputCount; ++slot) {
        const auto *pinSchema = AnimationGraphSchema::PinAt(*request.schema, AnimationGraphSchema::PinDirection::Input, slot);
        if (pinSchema == nullptr) {
            continue;
        }
        const ed::PinId pinId = request.makePinId(slot, true);
        request.registerPin(pinId, slot, true, pinSchema);
        ed::BeginPin(pinId, ed::PinKind::Input);
        RenderPin(*pinSchema, true);
        ed::EndPin();
    }
    if (inputCount == 0) {
        ImGui::TextDisabled(" ");
    }
    ImGui::EndGroup();

    ImGui::SameLine(0.0f, 20.0f);
    ImGui::BeginGroup();
    RenderNodeBody(request);
    ImGui::EndGroup();

    ImGui::SameLine(0.0f, 20.0f);
    ImGui::BeginGroup();
    const int32_t outputCount = AnimationGraphSchema::PinCount(*request.schema, AnimationGraphSchema::PinDirection::Output);
    for (int32_t slot = 0; slot < outputCount; ++slot) {
        const auto *pinSchema = AnimationGraphSchema::PinAt(*request.schema, AnimationGraphSchema::PinDirection::Output, slot);
        if (pinSchema == nullptr) {
            continue;
        }
        const ed::PinId pinId = request.makePinId(slot, false);
        request.registerPin(pinId, slot, false, pinSchema);
        ed::BeginPin(pinId, ed::PinKind::Output);
        RenderPin(*pinSchema, false);
        ed::EndPin();
    }
    if (outputCount == 0) {
        ImGui::TextDisabled(" ");
    }
    ImGui::EndGroup();

    ImGui::PopStyleVar(2);
    ed::EndNode();
    DrawNodeChrome(request);
}

} // namespace AnimationGraphNodeRenderer
