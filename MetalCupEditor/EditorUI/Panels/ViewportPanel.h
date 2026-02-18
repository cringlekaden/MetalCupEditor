// ViewportPanel.h
// Defines the ImGui Viewport panel rendering and interaction logic.
// Created by Kaden Cringle.

#pragma once

#import <CoreGraphics/CoreGraphics.h>
#import <Metal/Metal.h>

#ifdef __cplusplus
extern "C" {
#endif

void ImGuiViewportPanelDraw(void *context,
                            id<MTLTexture> _Nullable sceneTexture,
                            id<MTLTexture> _Nullable previewTexture,
                            const char * _Nullable selectedEntityId,
                            bool * _Nullable hovered,
                            bool * _Nullable focused,
                            bool * _Nullable uiHovered,
                            CGSize * _Nullable contentSize,
                            CGPoint * _Nullable contentOrigin,
                            CGPoint * _Nullable imageOrigin,
                            CGSize * _Nullable imageSize);

#ifdef __cplusplus
}
#endif
