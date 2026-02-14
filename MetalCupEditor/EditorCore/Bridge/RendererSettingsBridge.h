// RendererSettingsBridge.h
// Defines the renderer settings bridge for the editor UI.
// Created by Kaden Cringle.

#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

uint32_t MCERendererGetBloomEnabled(void);
void MCERendererSetBloomEnabled(uint32_t value);

float MCERendererGetBloomThreshold(void);
void MCERendererSetBloomThreshold(float value);

float MCERendererGetBloomKnee(void);
void MCERendererSetBloomKnee(float value);

float MCERendererGetBloomIntensity(void);
void MCERendererSetBloomIntensity(float value);

float MCERendererGetBloomUpsampleScale(void);
void MCERendererSetBloomUpsampleScale(float value);

float MCERendererGetBloomDirtIntensity(void);
void MCERendererSetBloomDirtIntensity(float value);

uint32_t MCERendererGetBlurPasses(void);
void MCERendererSetBlurPasses(uint32_t value);

uint32_t MCERendererGetBloomMaxMips(void);
void MCERendererSetBloomMaxMips(uint32_t value);

uint32_t MCERendererGetTonemap(void);
void MCERendererSetTonemap(uint32_t value);

float MCERendererGetExposure(void);
void MCERendererSetExposure(float value);

float MCERendererGetGamma(void);
void MCERendererSetGamma(float value);

uint32_t MCERendererGetIBLEnabled(void);
void MCERendererSetIBLEnabled(uint32_t value);

float MCERendererGetIBLIntensity(void);
void MCERendererSetIBLIntensity(float value);

uint32_t MCERendererGetIBLQualityPreset(void);
void MCERendererSetIBLQualityPreset(uint32_t value);

uint32_t MCERendererGetHalfResBloom(void);
void MCERendererSetHalfResBloom(uint32_t value);

uint32_t MCERendererGetDisableSpecularAA(void);
void MCERendererSetDisableSpecularAA(uint32_t value);

uint32_t MCERendererGetDisableClearcoat(void);
void MCERendererSetDisableClearcoat(uint32_t value);

uint32_t MCERendererGetDisableSheen(void);
void MCERendererSetDisableSheen(uint32_t value);

uint32_t MCERendererGetSkipSpecIBLHighRoughness(void);
void MCERendererSetSkipSpecIBLHighRoughness(uint32_t value);

uint32_t MCERendererGetNormalFlipYGlobal(void);
void MCERendererSetNormalFlipYGlobal(uint32_t value);

uint32_t MCERendererGetShadingDebugMode(void);
void MCERendererSetShadingDebugMode(uint32_t value);

float MCERendererGetIBLSpecularLodExponent(void);
void MCERendererSetIBLSpecularLodExponent(float value);
float MCERendererGetIBLSpecularLodBias(void);
void MCERendererSetIBLSpecularLodBias(float value);
float MCERendererGetIBLSpecularGrazingLodBias(void);
void MCERendererSetIBLSpecularGrazingLodBias(float value);
float MCERendererGetIBLSpecularMinRoughness(void);
void MCERendererSetIBLSpecularMinRoughness(float value);
float MCERendererGetSpecularAAStrength(void);
void MCERendererSetSpecularAAStrength(float value);
float MCERendererGetNormalMapMipBias(void);
void MCERendererSetNormalMapMipBias(float value);
float MCERendererGetNormalMapMipBiasGrazing(void);
void MCERendererSetNormalMapMipBiasGrazing(float value);

uint32_t MCERendererGetOutlineEnabled(void);
void MCERendererSetOutlineEnabled(uint32_t value);
uint32_t MCERendererGetOutlineThickness(void);
void MCERendererSetOutlineThickness(uint32_t value);
float MCERendererGetOutlineOpacity(void);
void MCERendererSetOutlineOpacity(float value);
void MCERendererGetOutlineColor(float *r, float *g, float *b);
void MCERendererSetOutlineColor(float r, float g, float b);

uint32_t MCERendererGetGridEnabled(void);
void MCERendererSetGridEnabled(uint32_t value);
float MCERendererGetGridOpacity(void);
void MCERendererSetGridOpacity(float value);
float MCERendererGetGridFadeDistance(void);
void MCERendererSetGridFadeDistance(float value);
float MCERendererGetGridMajorLineEvery(void);
void MCERendererSetGridMajorLineEvery(float value);

uint32_t MCERendererGetIBLFireflyClampEnabled(void);
void MCERendererSetIBLFireflyClampEnabled(uint32_t value);
float MCERendererGetIBLFireflyClamp(void);
void MCERendererSetIBLFireflyClamp(float value);
float MCERendererGetIBLSampleMultiplier(void);
void MCERendererSetIBLSampleMultiplier(float value);

float MCERendererGetFrameMs(void);
float MCERendererGetUpdateMs(void);
float MCERendererGetSceneMs(void);
float MCERendererGetRenderMs(void);
float MCERendererGetBloomMs(void);
float MCERendererGetBloomExtractMs(void);
float MCERendererGetBloomDownsampleMs(void);
float MCERendererGetBloomBlurMs(void);
float MCERendererGetCompositeMs(void);
float MCERendererGetOverlaysMs(void);
float MCERendererGetPresentMs(void);
float MCERendererGetGpuMs(void);

uint32_t MCESkyHasSkyLight(void);
uint32_t MCESkyGetEnabled(void);
void MCESkySetEnabled(uint32_t value);
uint32_t MCESkyGetMode(void);
void MCESkySetMode(uint32_t value);
float MCESkyGetIntensity(void);
void MCESkySetIntensity(float value);
void MCESkyGetTint(float *r, float *g, float *b);
void MCESkySetTint(float r, float g, float b);
float MCESkyGetTurbidity(void);
void MCESkySetTurbidity(float value);
float MCESkyGetAzimuthDegrees(void);
void MCESkySetAzimuthDegrees(float value);
float MCESkyGetElevationDegrees(void);
void MCESkySetElevationDegrees(float value);
uint32_t MCESkyGetRealtimeUpdate(void);
void MCESkySetRealtimeUpdate(uint32_t value);
void MCESkyRegenerate(void);

#ifdef __cplusplus
} // extern "C"
#endif
