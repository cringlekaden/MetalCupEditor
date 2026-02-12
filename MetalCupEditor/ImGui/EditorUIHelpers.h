#pragma once

#include "imgui.h"

namespace EditorUI {
    bool BeginPropertyTable(const char *id, float labelWidth = 140.0f);
    void EndPropertyTable();
    void PropertyLabel(const char *label);
    bool PropertyFloat(const char *label, float *value, float speed = 0.1f, float minValue = 0.0f, float maxValue = 0.0f, const char *format = "%.3f", bool clampValue = false, bool enableReset = false, float resetValue = 0.0f);
    bool PropertyBool(const char *label, bool *value);
    bool PropertyColor3(const char *label, float color[3], const float resetColor[3] = nullptr, bool enableReset = false);
    bool PropertyCombo(const char *label, int *current, const char *const items[], int count);
    bool PropertyVec3(const char *label, float *values, float resetValue = 0.0f, float speed = 0.1f, float minValue = 0.0f, float maxValue = 0.0f, const char *format = "%.3f", bool clampValue = false, bool enableReset = false);
}
