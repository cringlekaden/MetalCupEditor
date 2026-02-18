// SceneHierarchyPanel.h
// Defines the ImGui SceneHierarchy panel rendering and interaction logic.
// Created by Kaden Cringle.

#pragma once
#include <stddef.h>

void ImGuiSceneHierarchyPanelDraw(void *context, bool *isOpen, char *selectedEntityId, size_t selectedEntityIdSize);
