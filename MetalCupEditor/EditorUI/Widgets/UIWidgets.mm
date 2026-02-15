// UIWidgets.mm
// Defines reusable ImGui widgets and layout helpers for the editor.
// Created by Kaden Cringle.

#import "UIWidgets.h"
#include <algorithm>
#include <cctype>
#include <cstring>

extern "C" uint32_t MCEEditorGetHeaderOpen(const char *headerId, uint32_t defaultValue);
extern "C" void MCEEditorSetHeaderOpen(const char *headerId, uint32_t open);

namespace EditorUI {
    bool BeginPanel(const char *title, bool *isOpen, ImGuiWindowFlags flags) {
        ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImGui::GetStyle().WindowPadding);
        return ImGui::Begin(title, isOpen, flags);
    }

    void EndPanel() {
        ImGui::End();
        ImGui::PopStyleVar();
    }

    bool ToolbarButton(const char *label, bool enabled) {
        if (!enabled) {
            ImGui::BeginDisabled();
        }
        bool pressed = ImGui::Button(label);
        if (!enabled) {
            ImGui::EndDisabled();
        }
        return enabled && pressed;
    }

    bool AssetField(const char *label,
                    const char *displayName,
                    char *handleBuffer,
                    int handleBufferSize,
                    const char *dragDropPayload,
                    bool allowClear,
                    bool *outRequestPicker) {
        PropertyLabel(label);
        ImGui::PushID(label);
        bool changed = false;

        const char *buttonLabel = (displayName && displayName[0] != 0) ? displayName : "None";
        if (ImGui::Button(buttonLabel, ImVec2(-1.0f, 0.0f))) {
            if (outRequestPicker) {
                *outRequestPicker = true;
            }
        }

        if (dragDropPayload && ImGui::BeginDragDropTarget()) {
            if (const ImGuiPayload *payload = ImGui::AcceptDragDropPayload(dragDropPayload)) {
                const char *payloadText = static_cast<const char *>(payload->Data);
                if (payloadText && handleBuffer && handleBufferSize > 0) {
                    strncpy(handleBuffer, payloadText, static_cast<size_t>(handleBufferSize - 1));
                    handleBuffer[handleBufferSize - 1] = 0;
                    changed = true;
                }
            }
            ImGui::EndDragDropTarget();
        }

        if (allowClear) {
            ImGui::SameLine();
            if (ImGui::Button("X")) {
                if (handleBuffer && handleBufferSize > 0) {
                    handleBuffer[0] = 0;
                    changed = true;
                }
            }
        }

        ImGui::PopID();
        return changed;
    }
    bool BeginPropertyTable(const char *id, float labelWidth) {
        ImGuiTableFlags flags = ImGuiTableFlags_SizingStretchProp | ImGuiTableFlags_BordersInnerV;
        if (!ImGui::BeginTable(id, 2, flags)) {
            return false;
        }
        ImGui::TableSetupColumn("Label", ImGuiTableColumnFlags_WidthFixed, labelWidth);
        ImGui::TableSetupColumn("Value", ImGuiTableColumnFlags_WidthStretch);
        return true;
    }

    void EndPropertyTable() {
        ImGui::EndTable();
    }

    void PropertyLabel(const char *label) {
        ImGui::TableNextRow();
        ImGui::TableSetColumnIndex(0);
        ImGui::AlignTextToFramePadding();
        ImGui::TextUnformatted(label);
        ImGui::TableSetColumnIndex(1);
        ImGui::SetNextItemWidth(-1.0f);
    }

    bool PropertyFloat(const char *label, float *value, float speed, float minValue, float maxValue, const char *format, bool clampValue, bool enableReset, float resetValue) {
        PropertyLabel(label);
        const bool labelClicked = enableReset && ImGui::IsItemClicked();
        ImGui::PushID(label);
        const float dragMin = clampValue ? minValue : 0.0f;
        const float dragMax = clampValue ? maxValue : 0.0f;
        bool changed = ImGui::DragFloat("##Value", value, speed, dragMin, dragMax, format);
        if (labelClicked) {
            *value = resetValue;
            changed = true;
        }
        ImGui::PopID();
        return changed;
    }

    bool PropertyBool(const char *label, bool *value) {
        PropertyLabel(label);
        ImGui::PushID(label);
        bool changed = ImGui::Checkbox("##Value", value);
        ImGui::PopID();
        return changed;
    }

    bool PropertyColor3(const char *label, float color[3], const float resetColor[3], bool enableReset) {
        PropertyLabel(label);
        const bool labelClicked = enableReset && resetColor && ImGui::IsItemClicked();
        ImGui::PushID(label);
        bool changed = ImGui::ColorEdit3("##Value", color, ImGuiColorEditFlags_Float);
        if (labelClicked) {
            color[0] = resetColor[0];
            color[1] = resetColor[1];
            color[2] = resetColor[2];
            changed = true;
        }
        ImGui::PopID();
        return changed;
    }

    bool PropertyCombo(const char *label, int *current, const char *const items[], int count) {
        PropertyLabel(label);
        ImGui::PushID(label);
        bool changed = ImGui::Combo("##Value", current, items, count);
        ImGui::PopID();
        return changed;
    }

    bool PropertyInt(const char *label, int *value, int minValue, int maxValue) {
        PropertyLabel(label);
        ImGui::PushID(label);
        bool changed = ImGui::SliderInt("##Value", value, minValue, maxValue);
        ImGui::PopID();
        return changed;
    }

    bool PropertyVec3(const char *label, float *values, float resetValue, float speed, float minValue, float maxValue, const char *format, bool clampValue, bool enableReset) {
        PropertyLabel(label);
        const bool labelClicked = enableReset && ImGui::IsItemClicked();

        ImGui::PushID(label);
        ImGui::PushStyleVar(ImGuiStyleVar_ItemSpacing, ImVec2(4, 0));

        const ImVec4 axisColors[] = {
            ImVec4(0.8f, 0.2f, 0.2f, 1.0f),
            ImVec4(0.2f, 0.7f, 0.2f, 1.0f),
            ImVec4(0.55f, 0.4f, 0.75f, 1.0f)
        };
        const char *axisLabels[] = { "X", "Y", "Z" };
        const char *axisDragIds[] = { "##X", "##Y", "##Z" };
        bool changed = false;

        const float totalWidth = ImGui::CalcItemWidth();
        const float buttonSize = ImGui::GetFrameHeight();
        const float spacing = ImGui::GetStyle().ItemSpacing.x;
        float dragWidth = (totalWidth - (buttonSize * 3.0f) - (spacing * 6.0f)) / 3.0f;
        if (dragWidth < 40.0f) {
            dragWidth = 40.0f;
        }

        for (int i = 0; i < 3; ++i) {
            ImGui::PushStyleColor(ImGuiCol_Button, axisColors[i]);
            ImGui::PushStyleColor(ImGuiCol_ButtonHovered, axisColors[i]);
            ImGui::PushStyleColor(ImGuiCol_ButtonActive, axisColors[i]);
            if (ImGui::Button(axisLabels[i], ImVec2(buttonSize, buttonSize))) {
                values[i] = resetValue;
                changed = true;
            }
            ImGui::PopStyleColor(3);
            ImGui::SameLine();
            ImGui::SetNextItemWidth(dragWidth);
            const float dragMin = clampValue ? minValue : 0.0f;
            const float dragMax = clampValue ? maxValue : 0.0f;
            changed |= ImGui::DragFloat(axisDragIds[i], &values[i], speed, dragMin, dragMax, format);
            if (i < 2) {
                ImGui::SameLine();
            }
        }

        if (labelClicked) {
            values[0] = resetValue;
            values[1] = resetValue;
            values[2] = resetValue;
            changed = true;
        }

        ImGui::PopStyleVar();
        ImGui::PopID();
        return changed;
    }

    bool BeginSection(const char *label, const char *stateId, bool defaultOpen) {
        const uint32_t openState = MCEEditorGetHeaderOpen(stateId, defaultOpen ? 1 : 0);
        ImGui::SetNextItemOpen(openState != 0, ImGuiCond_Once);
        const ImGuiTreeNodeFlags flags = defaultOpen ? ImGuiTreeNodeFlags_DefaultOpen : 0;
        const bool open = ImGui::CollapsingHeader(label, flags);
        if (ImGui::IsItemToggledOpen()) {
            MCEEditorSetHeaderOpen(stateId, open ? 1 : 0);
        }
        return open;
    }

    bool BeginSectionWithContext(const char *label,
                                 const char *stateId,
                                 const char *contextId,
                                 const std::function<void()> &contextBody,
                                 bool defaultOpen) {
        const bool open = BeginSection(label, stateId, defaultOpen);
        if (ImGui::BeginPopupContextItem(contextId)) {
            contextBody();
            ImGui::EndPopup();
        }
        return open;
    }

    bool BeginModal(const char *title, bool *requestOpen, bool *open, ImGuiWindowFlags flags) {
        if (requestOpen && *requestOpen) {
            ImGui::OpenPopup(title);
            *requestOpen = false;
        }
        return ImGui::BeginPopupModal(title, open, flags);
    }

    bool ConfirmModal(const char *title,
                      bool *requestOpen,
                      const char *message,
                      const char *confirmLabel,
                      const char *cancelLabel,
                      const std::function<void()> &onConfirm) {
        if (!BeginModal(title, requestOpen, nullptr, ImGuiWindowFlags_AlwaysAutoResize)) {
            return false;
        }
        if (message && message[0] != 0) {
            ImGui::TextWrapped("%s", message);
        }
        bool confirmed = false;
        if (ImGui::Button(confirmLabel)) {
            onConfirm();
            ImGui::CloseCurrentPopup();
            confirmed = true;
        }
        ImGui::SameLine();
        if (ImGui::Button(cancelLabel)) {
            ImGui::CloseCurrentPopup();
        }
        ImGui::EndPopup();
        return confirmed;
    }

    std::string ToLower(const std::string &value) {
        std::string output = value;
        std::transform(output.begin(), output.end(), output.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
        return output;
    }

    void PushMenuBarStyle() {
        ImGui::PushStyleVar(ImGuiStyleVar_FramePadding, ImVec2(12.0f, 6.0f));
        ImGui::PushStyleVar(ImGuiStyleVar_ItemSpacing, ImVec2(12.0f, 6.0f));
        ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(10.0f, 6.0f));
        ImGui::PushStyleVar(ImGuiStyleVar_FrameRounding, 6.0f);
    }

    void PopMenuBarStyle() {
        ImGui::PopStyleVar(4);
    }

    void PushMenuPopupStyle() {
        ImGui::PushStyleVar(ImGuiStyleVar_FramePadding, ImVec2(12.0f, 6.0f));
        ImGui::PushStyleVar(ImGuiStyleVar_ItemSpacing, ImVec2(8.0f, 6.0f));
        ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(10.0f, 6.0f));
        ImGui::PushStyleVar(ImGuiStyleVar_FrameRounding, 6.0f);
    }

    void PopMenuPopupStyle() {
        ImGui::PopStyleVar(4);
    }
}
