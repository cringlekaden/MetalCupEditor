//
//  FinalShaders.metal
//  MetalCup
//
//  Created by Kaden Cringle on 1/21/26.
//

#include <metal_stdlib>
#include "Shared.metal"
using namespace metal;


static inline float3 tonemap_reinhard(float3 x) {
    return x / (x + 1.0);
}

static inline float luminance(float3 c) {
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

// Soft threshold (filmic-ish) to avoid harsh cutoff.
// threshold: point where bloom starts
// knee: softness range (0..threshold)
static inline float3 soft_threshold(float3 color, float threshold, float knee) {
    float l = luminance(color);
    float t = threshold;
    float k = max(knee, 1e-6);

    // Soft knee curve:
    // https://catlikecoding.com/unity/tutorials/advanced-rendering/bloom/
    float soft = clamp((l - t + k) / (2.0 * k), 0.0, 1.0);
    float contrib = max(l - t, 0.0) + soft * soft * k;

    // Scale color by how much exceeded threshold, normalized by luminance
    // (avoids hue shift)
    return (l > 1e-6) ? (color * (contrib / l)) : float3(0.0);
}

static inline float3 gaussianBlur9(texture2d<float> tex, sampler s, float2 uv, float2 texel, float2 dir) {
    const float w0 = 0.2270270270;
    const float w1 = 0.1945945946;
    const float w2 = 0.1216216216;
    const float w3 = 0.0540540541;
    const float w4 = 0.0162162162;
    float3 c = tex.sample(s, uv).rgb * w0;
    c += tex.sample(s, uv + dir * texel * 1.0).rgb * w1;
    c += tex.sample(s, uv - dir * texel * 1.0).rgb * w1;
    c += tex.sample(s, uv + dir * texel * 2.0).rgb * w2;
    c += tex.sample(s, uv - dir * texel * 2.0).rgb * w2;
    c += tex.sample(s, uv + dir * texel * 3.0).rgb * w3;
    c += tex.sample(s, uv - dir * texel * 3.0).rgb * w3;
    c += tex.sample(s, uv + dir * texel * 4.0).rgb * w4;
    c += tex.sample(s, uv - dir * texel * 4.0).rgb * w4;
    return c;
}

vertex SimpleRasterizerData vertex_final(const SimpleVertex vert [[ stage_in ]]) {
    SimpleRasterizerData rd;
    rd.position = float4(vert.position, 1.0);
    rd.texCoord = vert.position.xy * 0.5 + 0.5;
    return rd;
}

fragment float4 fragment_bloom_extract(const SimpleRasterizerData rd [[ stage_in ]],
                                       constant RendererSettings &settings [[ buffer(0) ]],
                                       texture2d<float> renderTexture [[ texture(0) ]],
                                       sampler s [[ sampler(0) ]]) {
    float2 uv = rd.texCoord;
    uv.y = 1.0 - uv.y;
    float3 scene = renderTexture.sample(s, uv).rgb;
    float threshold = settings.bloomThreshold;
    float knee = settings.bloomKnee;
    float3 bloom = soft_threshold(scene, threshold, knee);
    return float4(bloom, 1.0);
}

fragment float4 fragment_blur_h(const SimpleRasterizerData rd [[ stage_in ]],
                                constant RendererSettings &settings [[ buffer(0) ]],
                                texture2d<float> renderTexture [[ texture(0) ]],
                                sampler s [[ sampler(0) ]]) {
    float2 uv = rd.texCoord;
    uv.y = 1.0 - uv.y;
    float2 border = settings.bloomTexelSize * 4.0;
    float mask = step(border.x, uv.x) * step(border.y, uv.y) *
                 step(uv.x, 1.0 - border.x) * step(uv.y, 1.0 - border.y);
    float3 blurred = gaussianBlur9(renderTexture, s, uv, settings.bloomTexelSize, float2(1.0, 0.0)) * mask;
    return float4(blurred, 1.0);
}

fragment float4 fragment_blur_v(const SimpleRasterizerData rd [[ stage_in ]],
                                constant RendererSettings &settings [[ buffer(0) ]],
                                texture2d<float> renderTexture [[ texture(0) ]],
                                sampler s [[ sampler(0) ]]) {
    float2 uv = rd.texCoord;
    uv.y = 1.0 - uv.y;
    float2 border = settings.bloomTexelSize * 4.0;
    float mask = step(border.x, uv.x) * step(border.y, uv.y) *
                 step(uv.x, 1.0 - border.x) * step(uv.y, 1.0 - border.y);
    float3 blurred = gaussianBlur9(renderTexture, s, uv, settings.bloomTexelSize, float2(0.0, 1.0)) * mask;
    return float4(blurred, 1.0);
}

fragment float4 fragment_final(const SimpleRasterizerData rd [[ stage_in ]],
                               constant RendererSettings &settings [[ buffer(0) ]],
                               texture2d<float> sceneTexture [[ texture(0) ]],
                               texture2d<float> bloomTexture [[ texture(1) ]],
                               sampler s [[ sampler(0) ]]) {
    float2 uv = rd.texCoord;
    uv.y = 1.0 - uv.y;
    float3 scene = sceneTexture.sample(s, uv).rgb;
    float3 bloom = bloomTexture.sample(s, uv).rgb;
    if (settings.debugFlags & RendererDebugFlags::ShowBloom) {
        return float4(bloom, 1.0);
    }

    float bloomIntensity = (settings.bloomEnabled != 0) ? settings.bloomIntensity : 0.0;
    float3 color = scene + bloom * bloomIntensity;
    color *= settings.exposure;

    if (settings.tonemap == TonemapType::TonemapReinhard) {
        color = tonemap_reinhard(color);
    } else if (settings.tonemap == TonemapType::TonemapACES) {
        float3 x = max(color, 0.0);
        color = (x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14);
    }

    color = pow(color, 1.0 / max(settings.gamma, 1e-4));
    return float4(color, 1.0);
}
