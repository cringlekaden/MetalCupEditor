//
//  ImGuiBridge.h
//  MetalCupEditor
//
//  Created by Kaden Cringle on 2/4/26.
//

#import <Foundation/Foundation.h>
#import <MetalKit/MetalKit.h>

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

@end

NS_ASSUME_NONNULL_END
