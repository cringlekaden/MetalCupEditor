// RendererPanel.h
// Defines the ImGui Renderer panel rendering and interaction logic.
// Created by Kaden Cringle.

#pragma once

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

void ImGuiRendererPanelDraw(void *context, bool *isOpen);
void ImGuiRendererSettingsDraw(void *context);
void ImGuiRendererSettingsCoreDraw(void *context);
void ImGuiRendererSettingsLightingDraw(void *context);
void ImGuiRendererSettingsShadowsDraw(void *context);

#ifdef __cplusplus
}
#endif
