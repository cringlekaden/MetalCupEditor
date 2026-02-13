// UIWidgets.h
// Defines reusable ImGui widgets and layout helpers for the editor.
// Created by Kaden Cringle.

#pragma once

#include "../../ImGui/imgui.h"
#include <string>

namespace EditorUI {
    bool BeginPanel(const char *title, bool *isOpen = nullptr, ImGuiWindowFlags flags = 0);
    void EndPanel();
    bool ToolbarButton(const char *label, bool enabled = true);
    bool AssetField(const char *label,
                    const char *displayName,
                    char *handleBuffer,
                    int handleBufferSize,
                    const char *dragDropPayload,
                    bool allowClear,
                    bool *outRequestPicker);
    bool BeginPropertyTable(const char *id, float labelWidth = 140.0f);
    void EndPropertyTable();
    void PropertyLabel(const char *label);
    bool PropertyFloat(const char *label, float *value, float speed = 0.1f, float minValue = 0.0f, float maxValue = 0.0f, const char *format = "%.3f", bool clampValue = false, bool enableReset = false, float resetValue = 0.0f);
    bool PropertyBool(const char *label, bool *value);
    bool PropertyColor3(const char *label, float color[3], const float resetColor[3] = nullptr, bool enableReset = false);
    bool PropertyCombo(const char *label, int *current, const char *const items[], int count);
    bool PropertyInt(const char *label, int *value, int minValue, int maxValue);
    bool PropertyVec3(const char *label, float *values, float resetValue = 0.0f, float speed = 0.1f, float minValue = 0.0f, float maxValue = 0.0f, const char *format = "%.3f", bool clampValue = false, bool enableReset = false);

    bool BeginSection(const char *label, const char *stateId, bool defaultOpen = true);
    std::string ToLower(const std::string &value);
    void PushMenuBarStyle();
    void PopMenuBarStyle();
    void PushMenuPopupStyle();
    void PopMenuPopupStyle();
}
