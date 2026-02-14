// ViewportPanel.h
// Defines the ImGui Viewport panel rendering and interaction logic.
// Created by Kaden Cringle.

#pragma once

#import <CoreGraphics/CoreGraphics.h>
#import <Metal/Metal.h>

#ifdef __cplusplus
extern "C" {
#endif

void ImGuiViewportPanelDraw(id<MTLTexture> _Nullable sceneTexture,
                            bool *hovered,
                            bool *focused,
                            CGSize *contentSize,
                            CGPoint *contentOrigin,
                            CGPoint *imageOrigin,
                            CGSize *imageSize);

#ifdef __cplusplus
}
#endif
