/// RendererPanel.h
/// Defines the ImGui Renderer panel rendering and interaction logic.
/// Created by Kaden Cringle.

#pragma once

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum ImGuiRendererSettingsCategory : unsigned int {
    ImGuiRendererSettingsCategoryCore = 0,
    ImGuiRendererSettingsCategoryLighting = 1,
    ImGuiRendererSettingsCategoryShadows = 2
} ImGuiRendererSettingsCategory;

void ImGuiRendererSettingsCategoryDraw(void *context, ImGuiRendererSettingsCategory category);

// Deprecated legacy entrypoints; intentionally disabled to prevent UI drift.
void ImGuiRendererPanelDraw(void *context, bool *isOpen);
void ImGuiRendererSettingsDraw(void *context);

#ifdef __cplusplus
}
#endif
