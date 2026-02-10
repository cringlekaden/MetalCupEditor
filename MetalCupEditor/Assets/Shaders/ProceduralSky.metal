//
//  ProceduralSky.metal
//  MetalCup
//
//  Created by Codex on 2/10/26.
//

#include <metal_stdlib>
#include "Shared.metal"
using namespace metal;

static inline float3 perez(float cosTheta, float gamma, float cosGamma, float3 A, float3 B, float3 C, float3 D, float3 E) {
    float3 term1 = 1.0 + A * exp(B / max(cosTheta, 0.01));
    float3 term2 = 1.0 + C * exp(D * gamma) + E * cosGamma * cosGamma;
    return term1 * term2;
}

static inline float3 hosek_wilkie_sky(float3 dir, float3 sunDir, float turbidity, float3 sunTint) {
    float cosTheta = clamp(dir.y, 0.0, 1.0);
    float cosGamma = clamp(dot(dir, sunDir), -1.0, 1.0);
    float gamma = acos(cosGamma);

    // Hosek–Wilkie style fit using extended Perez distribution (RGB-tinted).
    float t = clamp(turbidity, 1.0, 10.0);
    float3 A = (float3(0.1787) * t - 1.4630) * sunTint;
    float3 B = (float3(-0.3554) * t + 0.4275);
    float3 C = (float3(-0.0227) * t + 5.3251);
    float3 D = (float3(0.1206) * t - 2.5771);
    float3 E = (float3(-0.0670) * t + 0.3703);

    float3 zenith = float3(1.0, 1.0, 1.0);
    float3 sky = perez(cosTheta, gamma, cosGamma, A, B, C, D, E) * zenith;
    return max(sky, float3(0.0));
}

fragment float4 fragment_procedural_sky(CubemapRasterizerData rd [[ stage_in ]],
                                        constant SkyParams &params [[ buffer(0) ]]) {
    float3 dir = normalize(rd.localPosition);
    float3 sunDir = normalize(params.sunDirection);

    float3 sunTint = params.sunColor;
    float3 sky = hosek_wilkie_sky(dir, sunDir, params.turbidity, clamp(sunTint, float3(0.0), float3(1.0)));
    sky *= max(params.skyTint, float3(0.0));

    float sunCos = clamp(dot(dir, sunDir), -1.0, 1.0);
    float sunAngle = acos(sunCos);
    float sunDisk = 1.0 - smoothstep(params.sunAngularRadius * 0.5, params.sunAngularRadius, sunAngle);
    float3 sun = sunTint * params.sunIntensity * sunDisk;

    float3 radiance = (sky + sun) * max(params.intensity, 0.0);
    return float4(radiance, 1.0);
}
