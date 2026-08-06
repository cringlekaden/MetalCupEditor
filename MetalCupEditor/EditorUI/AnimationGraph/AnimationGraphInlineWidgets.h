#pragma once

#include "AnimationGraphSchema.h"

#include "../../ImGui/imgui.h"

#include <algorithm>
#include <functional>
#include <cstring>
#include <string>
#include <vector>

namespace AnimationGraphInlineWidgets {

struct ClipOption {
    std::string handle;
    std::string label;
};

struct SchemaInlineFieldState {
    std::string title;
    std::string parameterName;
    std::string parameterXName;
    std::string parameterYName;
    std::string clipHandle;
    float floatValue = 0.0f;
    bool boolValue = false;
    bool synchronizeValue = false;
    bool hasFloatValue = false;
    bool hasBoolValue = false;
    bool hasSynchronizeValue = false;
};

struct SchemaInlineFieldContext {
    bool showSelectedOnly = false;
    const std::vector<ClipOption> *clipOptions = nullptr;
    std::function<std::string(const std::string &clipHandle)> clipDisplayName;
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

template <typename DisableBindingFn, typename VisibilityBindingFn>
inline bool DrawSchemaInlineFields(const AnimationGraphSchema::AnimGraphNodeSchema &schema,
                                   SchemaInlineFieldState &state,
                                   const SchemaInlineFieldContext &context,
                                   VisibilityBindingFn &&showBinding,
                                   DisableBindingFn &&disableBinding) {
    bool changed = false;
    for (const auto &field : schema.inlineFields) {
        if (field.visibility == AnimationGraphSchema::FieldVisibility::SelectedOnly && !context.showSelectedOnly) {
            continue;
        }
        if (!showBinding(field.binding)) {
            continue;
        }
        const std::string id = "##InlineField_" + field.id;
        switch (field.binding) {
            case AnimationGraphSchema::FieldBinding::Title:
                changed = DrawTextField(id.c_str(), field.label.empty() ? nullptr : field.label.c_str(), state.title) || changed;
                break;
            case AnimationGraphSchema::FieldBinding::ClipHandle: {
                const std::string popupId = "InlineFieldPopup_" + field.id;
                const std::string displayName = context.clipDisplayName ? context.clipDisplayName(state.clipHandle) : state.clipHandle;
                const std::vector<ClipOption> emptyOptions;
                const std::vector<ClipOption> &options = context.clipOptions ? *context.clipOptions : emptyOptions;
                changed = DrawClipField(id.c_str(),
                                        popupId.c_str(),
                                        state.clipHandle,
                                        displayName.empty() ? "<None>" : displayName,
                                        options) || changed;
                break;
            }
            case AnimationGraphSchema::FieldBinding::ParameterName:
                changed = DrawTextField(id.c_str(), field.label.empty() ? nullptr : field.label.c_str(), state.parameterName) || changed;
                break;
            case AnimationGraphSchema::FieldBinding::ParameterXName:
                changed = DrawTextField(id.c_str(), field.label.empty() ? nullptr : field.label.c_str(), state.parameterXName) || changed;
                break;
            case AnimationGraphSchema::FieldBinding::ParameterYName:
                changed = DrawTextField(id.c_str(), field.label.empty() ? nullptr : field.label.c_str(), state.parameterYName) || changed;
                break;
            case AnimationGraphSchema::FieldBinding::FloatValue:
            case AnimationGraphSchema::FieldBinding::Duration:
                changed = DrawFloatField(id.c_str(),
                                         field.label.empty() ? nullptr : field.label.c_str(),
                                         state.floatValue,
                                         0.01f,
                                         0.0f,
                                         20.0f,
                                         "%.3f",
                                         field.binding == AnimationGraphSchema::FieldBinding::Duration,
                                         disableBinding(field.binding)) || changed;
                state.hasFloatValue = true;
                break;
            case AnimationGraphSchema::FieldBinding::BoolValue:
                changed = DrawBoolField(id.c_str(),
                                        field.label.empty() ? nullptr : field.label.c_str(),
                                        state.boolValue,
                                        disableBinding(field.binding)) || changed;
                state.hasBoolValue = true;
                break;
            case AnimationGraphSchema::FieldBinding::SynchronizeValue:
                changed = DrawBoolField(id.c_str(),
                                        field.label.empty() ? nullptr : field.label.c_str(),
                                        state.synchronizeValue,
                                        disableBinding(field.binding)) || changed;
                state.hasSynchronizeValue = true;
                break;
            default:
                break;
        }
    }
    return changed;
}

} // namespace AnimationGraphInlineWidgets
