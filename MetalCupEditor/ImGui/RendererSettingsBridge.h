//
//  RendererSettingsBridge.h
//  MetalCupEditor
//
//  Created by Codex on 2/6/26.
//

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

uint32_t MCERendererGetBlurPasses(void);
void MCERendererSetBlurPasses(uint32_t value);

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

uint32_t MCERendererGetHalfResBloom(void);
void MCERendererSetHalfResBloom(uint32_t value);

uint32_t MCERendererGetShowAlbedo(void);
void MCERendererSetShowAlbedo(uint32_t value);

uint32_t MCERendererGetShowNormals(void);
void MCERendererSetShowNormals(uint32_t value);

uint32_t MCERendererGetShowRoughness(void);
void MCERendererSetShowRoughness(uint32_t value);

uint32_t MCERendererGetShowMetallic(void);
void MCERendererSetShowMetallic(uint32_t value);

uint32_t MCERendererGetShowEmissive(void);
void MCERendererSetShowEmissive(uint32_t value);

uint32_t MCERendererGetShowBloom(void);
void MCERendererSetShowBloom(uint32_t value);

float MCERendererGetFrameMs(void);
float MCERendererGetUpdateMs(void);
float MCERendererGetRenderMs(void);
float MCERendererGetBloomMs(void);
float MCERendererGetPresentMs(void);
float MCERendererGetGpuMs(void);

#ifdef __cplusplus
} // extern "C"
#endif
