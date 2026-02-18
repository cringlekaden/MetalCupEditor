// RendererSettingsBridge.h
// Defines the renderer settings bridge for the editor UI.
// Created by Kaden Cringle.

#pragma once

#include <stdint.h>
#include "MCEBridgeMacros.h"

#ifdef __cplusplus
extern "C" {
#endif

uint32_t MCERendererGetBloomEnabled(MCE_CTX);
void MCERendererSetBloomEnabled(MCE_CTX, uint32_t value);

float MCERendererGetBloomThreshold(MCE_CTX);
void MCERendererSetBloomThreshold(MCE_CTX, float value);

float MCERendererGetBloomKnee(MCE_CTX);
void MCERendererSetBloomKnee(MCE_CTX, float value);

float MCERendererGetBloomIntensity(MCE_CTX);
void MCERendererSetBloomIntensity(MCE_CTX, float value);

float MCERendererGetBloomUpsampleScale(MCE_CTX);
void MCERendererSetBloomUpsampleScale(MCE_CTX, float value);

float MCERendererGetBloomDirtIntensity(MCE_CTX);
void MCERendererSetBloomDirtIntensity(MCE_CTX, float value);

uint32_t MCERendererGetBlurPasses(MCE_CTX);
void MCERendererSetBlurPasses(MCE_CTX, uint32_t value);

uint32_t MCERendererGetBloomMaxMips(MCE_CTX);
void MCERendererSetBloomMaxMips(MCE_CTX, uint32_t value);

uint32_t MCERendererGetTonemap(MCE_CTX);
void MCERendererSetTonemap(MCE_CTX, uint32_t value);

float MCERendererGetExposure(MCE_CTX);
void MCERendererSetExposure(MCE_CTX, float value);

float MCERendererGetGamma(MCE_CTX);
void MCERendererSetGamma(MCE_CTX, float value);

uint32_t MCERendererGetIBLEnabled(MCE_CTX);
void MCERendererSetIBLEnabled(MCE_CTX, uint32_t value);

float MCERendererGetIBLIntensity(MCE_CTX);
void MCERendererSetIBLIntensity(MCE_CTX, float value);

uint32_t MCERendererGetIBLQualityPreset(MCE_CTX);
void MCERendererSetIBLQualityPreset(MCE_CTX, uint32_t value);

uint32_t MCERendererGetHalfResBloom(MCE_CTX);
void MCERendererSetHalfResBloom(MCE_CTX, uint32_t value);

uint32_t MCERendererGetDisableSpecularAA(MCE_CTX);
void MCERendererSetDisableSpecularAA(MCE_CTX, uint32_t value);

uint32_t MCERendererGetDisableClearcoat(MCE_CTX);
void MCERendererSetDisableClearcoat(MCE_CTX, uint32_t value);

uint32_t MCERendererGetDisableSheen(MCE_CTX);
void MCERendererSetDisableSheen(MCE_CTX, uint32_t value);

uint32_t MCERendererGetSkipSpecIBLHighRoughness(MCE_CTX);
void MCERendererSetSkipSpecIBLHighRoughness(MCE_CTX, uint32_t value);

uint32_t MCERendererGetNormalFlipYGlobal(MCE_CTX);
void MCERendererSetNormalFlipYGlobal(MCE_CTX, uint32_t value);

uint32_t MCERendererGetShadingDebugMode(MCE_CTX);
void MCERendererSetShadingDebugMode(MCE_CTX, uint32_t value);

float MCERendererGetIBLSpecularLodExponent(MCE_CTX);
void MCERendererSetIBLSpecularLodExponent(MCE_CTX, float value);
float MCERendererGetIBLSpecularLodBias(MCE_CTX);
void MCERendererSetIBLSpecularLodBias(MCE_CTX, float value);
float MCERendererGetIBLSpecularGrazingLodBias(MCE_CTX);
void MCERendererSetIBLSpecularGrazingLodBias(MCE_CTX, float value);
float MCERendererGetIBLSpecularMinRoughness(MCE_CTX);
void MCERendererSetIBLSpecularMinRoughness(MCE_CTX, float value);
float MCERendererGetSpecularAAStrength(MCE_CTX);
void MCERendererSetSpecularAAStrength(MCE_CTX, float value);
float MCERendererGetNormalMapMipBias(MCE_CTX);
void MCERendererSetNormalMapMipBias(MCE_CTX, float value);
float MCERendererGetNormalMapMipBiasGrazing(MCE_CTX);
void MCERendererSetNormalMapMipBiasGrazing(MCE_CTX, float value);

uint32_t MCERendererGetOutlineEnabled(MCE_CTX);
void MCERendererSetOutlineEnabled(MCE_CTX, uint32_t value);
uint32_t MCERendererGetOutlineThickness(MCE_CTX);
void MCERendererSetOutlineThickness(MCE_CTX, uint32_t value);
float MCERendererGetOutlineOpacity(MCE_CTX);
void MCERendererSetOutlineOpacity(MCE_CTX, float value);
void MCERendererGetOutlineColor(MCE_CTX, float *r, float *g, float *b);
void MCERendererSetOutlineColor(MCE_CTX, float r, float g, float b);

uint32_t MCERendererGetGridEnabled(MCE_CTX);
void MCERendererSetGridEnabled(MCE_CTX, uint32_t value);
float MCERendererGetGridOpacity(MCE_CTX);
void MCERendererSetGridOpacity(MCE_CTX, float value);
float MCERendererGetGridFadeDistance(MCE_CTX);
void MCERendererSetGridFadeDistance(MCE_CTX, float value);
float MCERendererGetGridMajorLineEvery(MCE_CTX);
void MCERendererSetGridMajorLineEvery(MCE_CTX, float value);

uint32_t MCERendererGetIBLFireflyClampEnabled(MCE_CTX);
void MCERendererSetIBLFireflyClampEnabled(MCE_CTX, uint32_t value);
float MCERendererGetIBLFireflyClamp(MCE_CTX);
void MCERendererSetIBLFireflyClamp(MCE_CTX, float value);
float MCERendererGetIBLSampleMultiplier(MCE_CTX);
void MCERendererSetIBLSampleMultiplier(MCE_CTX, float value);

float MCERendererGetFrameMs(MCE_CTX);
float MCERendererGetUpdateMs(MCE_CTX);
float MCERendererGetSceneMs(MCE_CTX);
float MCERendererGetRenderMs(MCE_CTX);
float MCERendererGetBloomMs(MCE_CTX);
float MCERendererGetBloomExtractMs(MCE_CTX);
float MCERendererGetBloomDownsampleMs(MCE_CTX);
float MCERendererGetBloomBlurMs(MCE_CTX);
float MCERendererGetCompositeMs(MCE_CTX);
float MCERendererGetOverlaysMs(MCE_CTX);
float MCERendererGetPresentMs(MCE_CTX);
float MCERendererGetGpuMs(MCE_CTX);

#ifdef __cplusplus
} // extern "C"
#endif
