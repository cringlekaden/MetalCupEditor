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

static inline float3 tonemap_uncharted2(float3 x) {
    const float A = 0.15;
    const float B = 0.50;
    const float C = 0.10;
    const float D = 0.20;
    const float E = 0.02;
    const float F = 0.30;
    return ((x * (A * x + C * B) + D * E) / (x * (A * x + B) + D * F)) - E / F;
}

static inline float3 tonemap_hazel(float3 x) {
    const float exposureBias = 2.0;
    float3 color = tonemap_uncharted2(x * exposureBias);
    float3 whiteScale = 1.0 / tonemap_uncharted2(float3(11.2));
    return color * whiteScale;
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
    float k = max(t * knee, 1e-6);

    // Soft knee curve:
    // https://catlikecoding.com/unity/tutorials/advanced-rendering/bloom/
    float soft = clamp((l - t + k) / (2.0 * k), 0.0, 1.0);
    float contrib = max(l - t, 0.0) + soft * soft * k;

    // Scale color by how much exceeded threshold, normalized by luminance
    // (avoids hue shift)
    return (l > 1e-6) ? (color * (contrib / l)) : float3(0.0);
}

static inline float3 gaussianBlur9(texture2d<float> tex, sampler s, float2 uv, float2 texel, float2 dir, float mipLevel) {
    const float w0 = 0.2270270270;
    const float w1 = 0.1945945946;
    const float w2 = 0.1216216216;
    const float w3 = 0.0540540541;
    const float w4 = 0.0162162162;
    float3 c = tex.sample(s, uv, level(mipLevel)).rgb * w0;
    c += tex.sample(s, uv + dir * texel * 1.0, level(mipLevel)).rgb * w1;
    c += tex.sample(s, uv - dir * texel * 1.0, level(mipLevel)).rgb * w1;
    c += tex.sample(s, uv + dir * texel * 2.0, level(mipLevel)).rgb * w2;
    c += tex.sample(s, uv - dir * texel * 2.0, level(mipLevel)).rgb * w2;
    c += tex.sample(s, uv + dir * texel * 3.0, level(mipLevel)).rgb * w3;
    c += tex.sample(s, uv - dir * texel * 3.0, level(mipLevel)).rgb * w3;
    c += tex.sample(s, uv + dir * texel * 4.0, level(mipLevel)).rgb * w4;
    c += tex.sample(s, uv - dir * texel * 4.0, level(mipLevel)).rgb * w4;
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

fragment float4 fragment_bloom_downsample(const SimpleRasterizerData rd [[ stage_in ]],
                                         constant RendererSettings &settings [[ buffer(0) ]],
                                         texture2d<float> renderTexture [[ texture(0) ]],
                                         sampler s [[ sampler(0) ]]) {
    float2 uv = rd.texCoord;
    uv.y = 1.0 - uv.y;
    float2 texel = settings.bloomTexelSize;
    float mip = settings.bloomMipLevel;
    float3 c0 = renderTexture.sample(s, uv, level(mip)).rgb;
    float3 c1 = renderTexture.sample(s, uv + texel * float2(1.0, 0.0), level(mip)).rgb;
    float3 c2 = renderTexture.sample(s, uv + texel * float2(0.0, 1.0), level(mip)).rgb;
    float3 c3 = renderTexture.sample(s, uv + texel * float2(1.0, 1.0), level(mip)).rgb;
    float3 result = (c0 + c1 + c2 + c3) * 0.25;
    return float4(result, 1.0);
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
    float3 blurred = gaussianBlur9(renderTexture, s, uv, settings.bloomTexelSize, float2(1.0, 0.0), settings.bloomMipLevel) * mask;
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
    float3 blurred = gaussianBlur9(renderTexture, s, uv, settings.bloomTexelSize, float2(0.0, 1.0), settings.bloomMipLevel) * mask;
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
    float3 bloom = float3(0.0);
    if (settings.bloomEnabled != 0) {
        float up = max(settings.bloomUpsampleScale, 0.0);
        float weights[5] = {
            1.0,
            0.8 * up,
            0.6 * up * up,
            0.4 * up * up * up,
            0.2 * up * up * up * up
        };
        int maxMips = clamp((int)settings.bloomMaxMips, 1, 5);
        float weightSum = 0.0;
        for (int i = 0; i < maxMips; i++) {
            bloom += bloomTexture.sample(s, uv, level((float)i)).rgb * weights[i];
            weightSum += weights[i];
        }
        if (weightSum > 1e-6) {
            bloom /= weightSum;
        }
        bloom *= (1.0 + settings.bloomDirtIntensity);
    }
    float bloomIntensity = (settings.bloomEnabled != 0) ? settings.bloomIntensity : 0.0;
    float3 color = scene + bloom * bloomIntensity;
    color *= settings.exposure;

    if (settings.tonemap == TonemapType::TonemapReinhard) {
        color = tonemap_reinhard(color);
    } else if (settings.tonemap == TonemapType::TonemapACES) {
        float3 x = max(color, 0.0);
        color = (x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14);
    } else if (settings.tonemap == TonemapType::TonemapHazel) {
        color = tonemap_hazel(max(color, 0.0));
    }

    color = pow(color, 1.0 / max(settings.gamma, 1e-4));
    return float4(color, 1.0);
}
