// UIConstants.h
// Defines shared constants for ImGui-based editor UI.
// Created by Kaden Cringle.

#pragma once

namespace EditorUIConstants {
    constexpr float kPositionStep = 0.1f;
    constexpr float kRotationStepDeg = 0.1f;
    constexpr float kRotationMinDeg = -720.0f;
    constexpr float kRotationMaxDeg = 720.0f;
    constexpr float kScaleStep = 0.01f;

    constexpr float kSkyIntensityMin = 0.0f;
    constexpr float kSkyIntensityMax = 10.0f;
    constexpr float kSkyIntensityStep = 0.05f;
    constexpr float kSkyTurbidityMin = 1.0f;
    constexpr float kSkyTurbidityMax = 10.0f;
    constexpr float kSkyTurbidityStep = 0.05f;
    constexpr float kSkyAzimuthMin = 0.0f;
    constexpr float kSkyAzimuthMax = 360.0f;
    constexpr float kSkyAzimuthStep = 0.5f;
    constexpr float kSkyElevationMin = 0.0f;
    constexpr float kSkyElevationMax = 90.0f;
    constexpr float kSkyElevationStep = 0.5f;
    constexpr float kDefaultSkyIntensity = 1.0f;
    constexpr float kDefaultSkyTurbidity = 2.0f;
    constexpr float kDefaultSkyAzimuth = 0.0f;
    constexpr float kDefaultSkyElevation = 30.0f;

    constexpr float kRoughnessMin = 0.02f;
    constexpr float kRoughnessMax = 1.0f;

    constexpr float kExposureMin = 0.01f;
    constexpr float kExposureMax = 10.0f;
    constexpr float kExposureStep = 0.05f;
    constexpr float kGammaMin = 1.0f;
    constexpr float kGammaMax = 3.0f;
    constexpr float kGammaStep = 0.01f;

    constexpr float kBloomThresholdMin = 0.0f;
    constexpr float kBloomThresholdMax = 10.0f;
    constexpr float kBloomThresholdStep = 0.05f;
    constexpr float kDefaultBloomThreshold = 1.2f;
    constexpr float kBloomKneeMin = 0.0f;
    constexpr float kBloomKneeMax = 1.0f;
    constexpr float kBloomKneeStep = 0.02f;
    constexpr float kDefaultBloomKnee = 0.2f;
    constexpr float kBloomIntensityMin = 0.0f;
    constexpr float kBloomIntensityMax = 5.0f;
    constexpr float kBloomIntensityStep = 0.05f;
    constexpr float kDefaultBloomIntensity = 0.15f;
    constexpr float kBloomUpsampleMin = 0.5f;
    constexpr float kBloomUpsampleMax = 2.0f;
    constexpr float kBloomUpsampleStep = 0.02f;
    constexpr float kDefaultBloomUpsample = 1.0f;
    constexpr float kBloomDirtMin = 0.0f;
    constexpr float kBloomDirtMax = 5.0f;
    constexpr float kBloomDirtStep = 0.05f;
    constexpr float kDefaultBloomDirt = 0.0f;

    constexpr float kIBLIntensityMin = 0.0f;
    constexpr float kIBLIntensityMax = 5.0f;
    constexpr float kIBLIntensityStep = 0.05f;
    constexpr float kDefaultIBLIntensity = 1.0f;

    constexpr float kDefaultExposure = 1.0f;
    constexpr float kDefaultGamma = 2.2f;
}
