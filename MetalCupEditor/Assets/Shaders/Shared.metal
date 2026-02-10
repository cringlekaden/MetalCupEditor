//
//  Shared.metal
//  MetalCup
//
//  Created by Kaden Cringle on 1/21/26.
//

#ifndef SHARED_METAL
#define SHARED_METAL

#include <metal_stdlib>
using namespace metal;

struct SimpleVertex {
    float3 position [[ attribute(0) ]];
};

struct Vertex {
    float3 position [[ attribute(0) ]];
    float4 color [[ attribute(1) ]];
    float2 texCoord [[ attribute(2) ]];
    float3 normal [[ attribute(3) ]];
    float3 tangent [[ attribute(4) ]];
    float3 bitangent [[ attribute(5) ]];
};

struct CubemapRasterizerData {
    float4 position [[ position ]];
    float3 localPosition;
};

struct RasterizerData {
    float4 position [[ position ]];
    float4 color;
    float2 texCoord;
    float totalGameTime;
    float3 worldPosition;
    float3 surfaceNormal;
    float3 surfaceTangent;
    float3 surfaceBitangent;
    float3 toCamera;
    float4 cameraPositionAndIBL;
};

struct SimpleRasterizerData {
    float4 position [[ position ]];
    float2 texCoord;
};

struct ModelConstants {
    float4x4 modelMatrix;
};

struct SceneConstants {
    float totalGameTime;
    float4x4 viewMatrix;
    float4x4 skyViewMatrix;
    float4x4 projectionMatrix;
    float4 cameraPositionAndIBL;
};

struct RendererSettings {
    float bloomThreshold;
    float bloomKnee;
    float bloomIntensity;
    float bloomUpsampleScale;
    float bloomDirtIntensity;
    uint bloomEnabled;
    float2 bloomTexelSize;
    float bloomMipLevel;
    uint bloomMaxMips;
    uint blurPasses;
    uint tonemap;
    float exposure;
    float gamma;
    uint iblEnabled;
    float iblIntensity;
    uint iblResolutionOverride;
    uint perfFlags;
    uint normalFlipYGlobal;
    float padding;
    float padding2;
};

struct SkyParams {
    float3 sunDirection;
    float sunAngularRadius;
    float3 sunColor;
    float sunIntensity;
    float turbidity;
    float intensity;
    float3 skyTint;
    float padding;
};

enum TonemapType : uint {
    TonemapNone = 0,
    TonemapReinhard = 1,
    TonemapACES = 2,
    TonemapHazel = 3
};

struct MetalCupMaterial {
    float3 baseColor;
    float metallicScalar;
    float roughnessScalar;
    float aoScalar;
    float3 emissiveColor;
    float emissiveScalar;
    uint flags;
    float clearcoatFactor;
    float clearcoatRoughness;
    float sheenRoughness;
    float padding;
    float3 sheenColor;
    float padding2;
};

enum MetalCupMaterialFlags : uint {
    HasBaseColorMap =      1 << 0,
    HasNormalMap =         1 << 1,
    HasMetallicMap =       1 << 2,
    HasRoughnessMap =      1 << 3,
    HasMetalRoughnessMap = 1 << 4,
    HasAOMap =             1 << 5,
    HasEmissiveMap =       1 << 6,
    IsUnlit =              1 << 7,
    IsDoubleSided =        1 << 8,
    AlphaMasked =          1 << 9,
    AlphaBlended =         1 << 10,
    HasClearcoat =         1 << 11,
    HasSheen =             1 << 12,
    NormalFlipY =          1 << 13,
    HasClearcoatMap =      1 << 14,
    HasClearcoatRoughnessMap = 1 << 15,
    HasSheenColorMap =     1 << 16,
    HasSheenIntensityMap = 1 << 17,
    HasClearcoatGlossMap = 1 << 18
};
    
inline bool hasFlag(uint flags, uint bit) { return (flags & bit) != 0u; }

enum LightType : uint {
    LightTypePoint = 0,
    LightTypeSpot = 1,
    LightTypeDirectional = 2
};

enum RendererPerfFlags : uint {
    PerfHalfResBloom = 1 << 0,
    PerfUseAsyncIBLGen = 1 << 1,
    PerfDisableSpecularAA = 1 << 2,
    PerfDisableClearcoat = 1 << 3,
    PerfDisableSheen = 1 << 4,
    PerfSkipSpecIBLHighRoughness = 1 << 5
};

struct LightData {
    float3 position;
    uint type;
    float3 direction;
    float range;
    float3 color;
    float brightness;
    float ambientIntensity;
    float diffuseIntensity;
    float specularIntensity;
    float innerConeCos;
    float outerConeCos;
    float2 padding;
};

#endif
