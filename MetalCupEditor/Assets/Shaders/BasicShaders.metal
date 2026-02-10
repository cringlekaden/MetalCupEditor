//
//  BasicShaders.metal
//  MetalCup
//
//  Created by Kaden Cringle on 1/21/26.
//

#include <metal_stdlib>
#include "PBR.metal"
#include "Shared.metal"
using namespace metal;

vertex RasterizerData vertex_basic(const Vertex vert [[ stage_in ]],
                                   constant SceneConstants &sceneConstants [[ buffer(1) ]],
                                   constant ModelConstants &modelConstants [[ buffer(2) ]]) {
    RasterizerData rd;
    float4 worldPosition = modelConstants.modelMatrix * float4(vert.position, 1.0);
    rd.position = sceneConstants.projectionMatrix * sceneConstants.viewMatrix * worldPosition;
    rd.color = vert.color;
    rd.texCoord = vert.texCoord;
    rd.totalGameTime = sceneConstants.totalGameTime;
    rd.worldPosition = worldPosition.xyz;
    float3x3 model3x3 = float3x3(
        modelConstants.modelMatrix[0].xyz,
        modelConstants.modelMatrix[1].xyz,
        modelConstants.modelMatrix[2].xyz
    );
    float3x3 normalMatrix = model3x3;
    rd.surfaceNormal = normalize(normalMatrix * vert.normal);
    rd.surfaceTangent = normalize(normalMatrix * vert.tangent);
    rd.surfaceBitangent = normalize(normalMatrix * vert.bitangent);
    rd.toCamera = sceneConstants.cameraPositionAndIBL.xyz - worldPosition.xyz;
    rd.cameraPositionAndIBL = sceneConstants.cameraPositionAndIBL;
    return rd;
}

fragment float4 fragment_basic(RasterizerData rd [[ stage_in ]],
                              constant MetalCupMaterial &material [[ buffer(1) ]],
                              constant RendererSettings &settings [[ buffer(2) ]],
                              constant int &lightCount [[ buffer(3) ]],
                              constant LightData *lightDatas [[ buffer(4) ]],
                              sampler sam [[ sampler(0) ]],
                              texture2d<float> albedoMap [[ texture(0) ]],
                              texture2d<float> normalMap [[ texture(1) ]],
                              texture2d<float> metallicMap [[ texture(2) ]],
                              texture2d<float> roughnessMap [[ texture(3) ]],
                              texture2d<float> metalRoughness [[ texture(4) ]],
                              texture2d<float> aoMap [[ texture(5) ]],
                              texture2d<float> emissiveMap [[ texture(6) ]],
                              texture2d<float> clearcoatMap [[ texture(10) ]],
                              texture2d<float> clearcoatRoughnessMap [[ texture(11) ]],
                              texture2d<float> sheenColorMap [[ texture(12) ]],
                              texture2d<float> sheenIntensityMap [[ texture(13) ]],
                              texturecube<float> irradianceMap [[ texture(7) ]],
                              texturecube<float> prefilteredMap [[ texture(8) ]],
                              texture2d<float> brdf_lut [[ texture(9) ]])  {
    // ------------------------------------------------------------
    // Fallback scalars (material factors)
    // ------------------------------------------------------------
    float3 albedo = material.baseColor;
    float metallic = material.metallicScalar;
    float roughness = material.roughnessScalar;
    float ao = material.aoScalar;
    float emissiveScalar = material.emissiveScalar;
    
    // ------------------------------------------------------------
    // Texture overrides
    // ------------------------------------------------------------
    bool disableSpecularAA = hasFlag(settings.perfFlags, RendererPerfFlags::PerfDisableSpecularAA);
    bool disableClearcoat = hasFlag(settings.perfFlags, RendererPerfFlags::PerfDisableClearcoat);
    bool disableSheen = hasFlag(settings.perfFlags, RendererPerfFlags::PerfDisableSheen);

    if (hasFlag(material.flags, MetalCupMaterialFlags::HasBaseColorMap)) {
        albedo = albedoMap.sample(sam, rd.texCoord).rgb;
    }
    if (hasFlag(material.flags, MetalCupMaterialFlags::HasMetalRoughnessMap)) {
        float3 mr = metalRoughness.sample(sam, rd.texCoord).rgb;
        roughness = mr.g;
        metallic  = mr.b;
    } else {
        if (hasFlag(material.flags, MetalCupMaterialFlags::HasMetallicMap)) {
            metallic = metallicMap.sample(sam, rd.texCoord).r;
        }
        if (hasFlag(material.flags, MetalCupMaterialFlags::HasRoughnessMap)) {
            roughness = roughnessMap.sample(sam, rd.texCoord).r;
        }
    }
    if (hasFlag(material.flags, MetalCupMaterialFlags::HasAOMap)) {
        ao = aoMap.sample(sam, rd.texCoord).r;
    }
    float clearcoat = disableClearcoat ? 0.0 : clamp(material.clearcoatFactor, 0.0, 1.0);
    float clearcoatRoughness = clamp(material.clearcoatRoughness, 0.0, 1.0);
    if (!disableClearcoat) {
        if (hasFlag(material.flags, MetalCupMaterialFlags::HasClearcoatMap)) {
            clearcoat *= clearcoatMap.sample(sam, rd.texCoord).r;
        }
        if (hasFlag(material.flags, MetalCupMaterialFlags::HasClearcoatGlossMap)) {
            clearcoatRoughness = 1.0 - clearcoatRoughnessMap.sample(sam, rd.texCoord).r;
        } else if (hasFlag(material.flags, MetalCupMaterialFlags::HasClearcoatRoughnessMap)) {
            clearcoatRoughness = clearcoatRoughnessMap.sample(sam, rd.texCoord).r;
        }
    }
    float3 sheenColor = disableSheen ? float3(0.0) : clamp(material.sheenColor, float3(0.0), float3(1.0));
    if (!disableSheen) {
        if (hasFlag(material.flags, MetalCupMaterialFlags::HasSheenColorMap)) {
            float3 sheenTex = sheenColorMap.sample(sam, rd.texCoord).rgb;
            sheenColor = any(sheenColor > 0.0) ? sheenColor * sheenTex : sheenTex;
        }
        if (hasFlag(material.flags, MetalCupMaterialFlags::HasSheenIntensityMap)) {
            float sheenIntensity = sheenIntensityMap.sample(sam, rd.texCoord).r;
            sheenColor *= sheenIntensity;
        }
    }
    // Clamp for stability (prevents NaNs / LUT edge artifacts / fireflies)
    metallic = clamp(metallic, 0.0, 1.0);
    const float minRoughness = 0.08;
    roughness = clamp(roughness, minRoughness, 1.0); // 0.0 can cause sparkle/instability
    albedo = max(albedo, float3(0.0));
    
    // ------------------------------------------------------------
    // Normal mapping
    // ------------------------------------------------------------
    float3 N = normalize(rd.surfaceNormal);
    if (hasFlag(material.flags, MetalCupMaterialFlags::HasNormalMap)) {
        // Derive TBN from position/UV derivatives (stable across assets).
        float3 dp1 = dfdx(rd.worldPosition);
        float3 dp2 = dfdy(rd.worldPosition);
        float2 duv1 = dfdx(rd.texCoord);
        float2 duv2 = dfdy(rd.texCoord);
        float3 t = dp1 * duv2.y - dp2 * duv1.y;
        float3 b = -dp1 * duv2.x + dp2 * duv1.x;
        float3 T = normalize(t - N * dot(N, t));
        float3 B = normalize(b - N * dot(N, b));
        // Orthonormalize T to N (helps robustness)
        T = normalize(T - N * dot(N, T));
        float3 Bn = normalize(cross(N, T));
        float handedness = (dot(Bn, B) < 0.0) ? -1.0 : 1.0;
        Bn *= handedness;
        float3x3 TBN = float3x3(T, Bn, N);
        float3 tangentNormal = normalMap.sample(sam, rd.texCoord).xyz * 2.0 - 1.0;
        if (settings.normalFlipYGlobal != 0 || hasFlag(material.flags, MetalCupMaterialFlags::NormalFlipY)) {
            tangentNormal.y = -tangentNormal.y;
        }
        if (!disableSpecularAA) {
            // Specular AA (Toksvig-style) using normal map variance in tangent space.
            float3 dndx = dfdx(tangentNormal);
            float3 dndy = dfdy(tangentNormal);
            float variance = max(dot(dndx, dndx), dot(dndy, dndy));
            const float specularAAStrength = 0.5;
            roughness = clamp(sqrt(roughness * roughness + variance * specularAAStrength), minRoughness, 1.0);
        }

        N = normalize(TBN * tangentNormal);
    }

    // ------------------------------------------------------------
    // View vector
    // ------------------------------------------------------------
    float3 V = normalize(rd.toCamera);
    float NdotV = max(dot(N, V), 0.001);

    float iblIntensity = rd.cameraPositionAndIBL.w * ((settings.iblEnabled != 0) ? settings.iblIntensity : 0.0f);

    // ------------------------------------------------------------
    // Unlit shortcut
    // ------------------------------------------------------------
    if (hasFlag(material.flags, MetalCupMaterialFlags::IsUnlit)) {
        float3 emissive = material.emissiveColor;
        if (hasFlag(material.flags, MetalCupMaterialFlags::HasEmissiveMap)) {
            float3 e = emissiveMap.sample(sam, rd.texCoord).rgb;
            float luminance = dot(e, float3(0.2126, 0.7152, 0.0722));
            float mask = step(0.04, luminance);
            emissive = e * mask;
        }
        emissive *= material.emissiveScalar;
        return float4(albedo + emissive, 1.0);
    }

    // ------------------------------------------------------------
    // Base reflectivity
    // ------------------------------------------------------------
    float3 F0 = mix(float3(0.04), albedo, metallic);
    clearcoat = clamp(clearcoat, 0.0, 1.0);
    clearcoatRoughness = clamp(clearcoatRoughness, minRoughness, 1.0);
    sheenColor = clamp(sheenColor, float3(0.0), float3(1.0));
    float sheenRoughness = clamp(material.sheenRoughness, minRoughness, 1.0);

    // ------------------------------------------------------------
    // Direct lighting (Cook-Torrance BRDF)
    // ------------------------------------------------------------
    float3 Lo = float3(0.0);
    for (int i = 0; i < lightCount; i++) {
        LightData light = lightDatas[i];
        float3 L = float3(0.0);
        float attenuation = 1.0;

        if (light.type == LightTypeDirectional) {
            L = normalize(-light.direction);
        } else {
            float3 toLight = light.position - rd.worldPosition;
            float distance = length(toLight);
            L = toLight / max(distance, 1e-4);
            attenuation = 1.0 / max(distance * distance, 1e-4);
            if (light.range > 0.0) {
                float rangeAtt = clamp(1.0 - (distance / light.range), 0.0, 1.0);
                attenuation *= rangeAtt * rangeAtt;
            }
            if (light.type == LightTypeSpot) {
                float3 lightDir = normalize(light.direction);
                float spotCos = dot(normalize(-toLight), lightDir);
                float spotAtt = smoothstep(light.outerConeCos, light.innerConeCos, spotCos);
                // Softer edge falloff for spots.
                spotAtt = pow(spotAtt, 2.0);
                attenuation *= spotAtt;
            }
        }

        float3 H = normalize(V + L);
        float NdotL = max(dot(N, L), 0.0);
        float NdotH = max(dot(N, H), 0.0);
        float HdotV = max(dot(H, V), 0.0);
        float LdotH = max(dot(L, H), 0.0);

        float3 radiance = light.color * light.brightness * attenuation;

        // Cook-Torrance specular
        float D = PBR::DistributionGGX(N, H, roughness);
        float G = PBR::GeometrySmith(N, V, L, roughness);
        float3 F = PBR::FresnelSchlick(HdotV, F0);
        float3 specular = (D * G * F) / max(4.0 * NdotV * NdotL, 1e-4);

        // Diffuse term (Disney Burley)
        float3 kS = F;
        float3 kD = (1.0 - kS) * (1.0 - metallic);
        float fd90 = 0.5 + 2.0 * roughness * LdotH * LdotH;
        float lightScatter = 1.0 + (fd90 - 1.0) * pow(1.0 - NdotL, 5.0);
        float viewScatter = 1.0 + (fd90 - 1.0) * pow(1.0 - NdotV, 5.0);
        float3 diffuse = (albedo / PBR::PI) * kD * lightScatter * viewScatter;

        float3 direct = diffuse * light.diffuseIntensity + specular * light.specularIntensity;

        if (clearcoat > 0.0) {
            float Dcc = PBR::DistributionGGX(N, H, clearcoatRoughness);
            float Gcc = PBR::GeometrySmith(N, V, L, clearcoatRoughness);
            float3 Fcc = PBR::FresnelSchlick(HdotV, float3(0.04));
            float3 clearcoatSpec = (Dcc * Gcc * Fcc) / max(4.0 * NdotV * NdotL, 1e-4);
            // Energy conservation: clearcoat steals from base layer.
            float3 clearcoatEnergy = Fcc * clearcoat;
            direct *= (1.0 - clearcoatEnergy);
            direct += clearcoatSpec * clearcoat * light.specularIntensity;
        }

        if (any(sheenColor > 0.0)) {
            float Dsheen = PBR::DistributionGGX(N, H, sheenRoughness);
            float3 sheenSpec = Dsheen * sheenColor * (1.0 - metallic);
            direct += sheenSpec * 0.5;
        }

        Lo += direct * radiance * NdotL;
    }

    // ------------------------------------------------------------
    // Diffuse IBL
    // ------------------------------------------------------------
    float3 irradiance = irradianceMap.sample(sam, N).rgb;
    float3 diffuseIBL = irradiance * (albedo / PBR::PI) * iblIntensity;

    // Energy conservation split
    float3 F_ibl = PBR::FresnelSchlick(NdotV, F0);
    float3 kS = F_ibl;
    float3 kD = (1.0 - kS) * (1.0 - metallic);

    // Apply AO to ambient only
    float3 ambient = kD * diffuseIBL * ao;

    // ------------------------------------------------------------
    // Specular IBL (prefilter + BRDF LUT)
    // ------------------------------------------------------------
    float3 R = normalize(reflect(-V, N));
    float maxMip = float(prefilteredMap.get_num_mip_levels()) - 1.0;
    float mipLevel = roughness * maxMip;
    float3 prefilteredColor = prefilteredMap.sample(sam, R, level(mipLevel)).rgb;
    float2 brdfUV = float2(NdotV, roughness);
    brdfUV = clamp(brdfUV, 0.001, 0.999);
    float2 brdfSample = brdf_lut.sample(sam, brdfUV).rg;
    float3 specularIBL = prefilteredColor * (F_ibl * brdfSample.x + brdfSample.y) * iblIntensity;
    if (hasFlag(settings.perfFlags, RendererPerfFlags::PerfSkipSpecIBLHighRoughness) && roughness > 0.9) {
        specularIBL = float3(0.0);
    }

    // Optional: Apply AO to specular too (specular occlusion)
    // specularIBL *= ao;

    // ------------------------------------------------------------
    // Emissive (additive, unlit)
    // ------------------------------------------------------------
    float3 emissiveColor = material.emissiveColor;
    if (hasFlag(material.flags, MetalCupMaterialFlags::HasEmissiveMap)) {
        float3 e = emissiveMap.sample(sam, rd.texCoord).rgb;
        float luminance = dot(e, float3(0.2126, 0.7152, 0.0722));
        float mask = step(0.04, luminance);
        emissiveColor = e * mask;
    }
    emissiveColor *= emissiveScalar;

    // ------------------------------------------------------------
    // Debug Views
    // ------------------------------------------------------------
    // ------------------------------------------------------------
    // Combine
    // ------------------------------------------------------------
    float3 color = Lo + ambient + specularIBL + emissiveColor;
    return float4(color, 1.0);
}
