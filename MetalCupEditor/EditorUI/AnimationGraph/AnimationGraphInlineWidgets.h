#pragma once

#include "../../ImGui/imgui.h"

#include <algorithm>
#include <cstring>
#include <string>
#include <vector>

namespace AnimationGraphInlineWidgets {

struct ClipOption {
    std::string handle;
    std::string label;
};

inline bool DrawTextField(const char *id, const char *label, std::string &value, float width = 180.0f) {
    char buffer[128] = {0};
    std::strncpy(buffer, value.c_str(), sizeof(buffer) - 1);
    if (label != nullptr && label[0] != 0) {
        ImGui::TextDisabled("%s", label);
    }
    ImGui::SetNextItemWidth(width);
    if (!ImGui::InputText(id, buffer, sizeof(buffer))) {
        return false;
    }
    value = buffer;
    return true;
}

inline bool DrawFloatField(const char *id,
                           const char *label,
                           float &value,
                           float speed = 0.02f,
                           float minValue = 0.0f,
                           float maxValue = 0.0f,
                           const char *format = "%.3f",
                           bool constrained = false,
                           bool disabled = false,
                           float width = 110.0f) {
    if (label != nullptr && label[0] != 0) {
        ImGui::TextDisabled("%s", label);
        ImGui::SameLine();
    }
    if (disabled) {
        ImGui::BeginDisabled();
    }
    ImGui::SetNextItemWidth(width);
    const bool changed = constrained
        ? ImGui::DragFloat(id, &value, speed, minValue, maxValue, format)
        : ImGui::DragFloat(id, &value, speed, 0.0f, 0.0f, format);
    if (disabled) {
        ImGui::EndDisabled();
    }
    return changed;
}

inline bool DrawBoolField(const char *id, const char *label, bool &value, bool disabled = false) {
    if (disabled) {
        ImGui::BeginDisabled();
    }
    const bool changed = ImGui::Checkbox(label != nullptr ? label : id, &value);
    if (disabled) {
        ImGui::EndDisabled();
    }
    return changed;
}

inline bool DrawClipField(const char *buttonLabelId,
                          const char *popupId,
                          std::string &clipHandle,
                          const std::string &displayName,
                          const std::vector<ClipOption> &options) {
    bool changed = false;
    const std::string buttonLabel = std::string("Clip: ").append(displayName);
    if (ImGui::Button(buttonLabelId != nullptr ? buttonLabelId : buttonLabel.c_str(), ImVec2(180.0f, 0.0f))) {
        ImGui::OpenPopup(popupId);
    }
    if (ImGui::BeginPopup(popupId)) {
        if (ImGui::Selectable("<None>", clipHandle.empty())) {
            clipHandle.clear();
            changed = true;
        }
        ImGui::Separator();
        for (const auto &clip : options) {
            if (ImGui::Selectable(clip.label.c_str(), clipHandle == clip.handle)) {
                clipHandle = clip.handle;
                changed = true;
                ImGui::CloseCurrentPopup();
            }
        }
        ImGui::EndPopup();
    }
    if (ImGui::BeginDragDropTarget()) {
        if (const ImGuiPayload *payload = ImGui::AcceptDragDropPayload("MCE_ASSET_ANIMATION_CLIP")) {
            const char *droppedHandle = static_cast<const char *>(payload->Data);
            if (droppedHandle != nullptr && droppedHandle[0] != 0) {
                clipHandle = droppedHandle;
                changed = true;
            }
        }
        ImGui::EndDragDropTarget();
    }
    return changed;
}

inline void DrawSummaryLines(const std::vector<std::string> &lines) {
    if (lines.empty()) {
        ImGui::TextDisabled("-");
        return;
    }
    for (const auto &line : lines) {
        ImGui::TextDisabled("%s", line.c_str());
    }
}

} // namespace AnimationGraphInlineWidgets
