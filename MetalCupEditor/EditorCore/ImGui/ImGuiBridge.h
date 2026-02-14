// ImGuiBridge.h
// Defines the ImGui bridge interface for editor rendering and input.
// Created by Kaden Cringle.

#import <Foundation/Foundation.h>
#import <MetalKit/MetalKit.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@interface ImGuiBridge : NSObject

/// Call once after MTKView is created.
+ (void)setupWithView:(MTKView *)view;

/// Call each frame before building any ImGui UI.
+ (void)newFrameWithView:(MTKView *)view deltaTime:(float)dt;

/// Build your ImGui panels here (call every frame after newFrame).
/// Pass the scene texture you want to show in the viewport (can be nil).
+ (void)buildUIWithSceneTexture:(id<MTLTexture> _Nullable)sceneTexture;

/// Render the ImGui draw data into the given render pass.
/// This call creates its own render command encoder.
+ (void)renderWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
            renderPassDescriptor:(MTLRenderPassDescriptor *)renderPassDescriptor;

+ (bool)wantsCaptureMouse;
+ (bool)wantsCaptureKeyboard;
+ (bool)viewportIsHovered;
+ (bool)viewportIsFocused;
+ (CGSize)viewportContentSize;
+ (CGPoint)viewportContentOrigin;
+ (CGPoint)viewportImageOrigin;
+ (CGSize)viewportImageSize;
+ (CGPoint)mousePosition;
+ (void)setSelectedEntityId:(NSString *)value;

@end

NS_ASSUME_NONNULL_END
