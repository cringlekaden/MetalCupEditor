#import "EditorUIHelpers.h"

namespace EditorUI {
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
        ImGui::PushID(label);
        const float dragMin = clampValue ? minValue : 0.0f;
        const float dragMax = clampValue ? maxValue : 0.0f;
        bool changed = ImGui::DragFloat("##Value", value, speed, dragMin, dragMax, format);
        if (enableReset && ImGui::IsItemHovered() && ImGui::IsMouseDoubleClicked(0)) {
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
        ImGui::PushID(label);
        bool changed = ImGui::ColorEdit3("##Value", color, ImGuiColorEditFlags_Float);
        if (enableReset && resetColor && ImGui::IsItemHovered() && ImGui::IsMouseDoubleClicked(0)) {
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

    bool PropertyVec3(const char *label, float *values, float resetValue, float speed, float minValue, float maxValue, const char *format, bool clampValue, bool enableReset) {
        PropertyLabel(label);

        ImGui::PushID(label);
        ImGui::PushStyleVar(ImGuiStyleVar_ItemSpacing, ImVec2(4, 0));

        const ImVec4 axisColors[] = {
            ImVec4(0.8f, 0.2f, 0.2f, 1.0f),
            ImVec4(0.2f, 0.7f, 0.2f, 1.0f),
            ImVec4(0.2f, 0.4f, 0.9f, 1.0f)
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
            if (enableReset && ImGui::IsItemHovered() && ImGui::IsMouseDoubleClicked(0)) {
                values[i] = resetValue;
                changed = true;
            }
            if (i < 2) {
                ImGui::SameLine();
            }
        }

        ImGui::PopStyleVar();
        ImGui::PopID();
        return changed;
    }
}
