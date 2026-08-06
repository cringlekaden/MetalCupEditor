/// InspectorPanel.mm
/// Defines the ImGui Inspector panel rendering and interaction logic.
/// Created by Kaden Cringle.

#import "InspectorPanel.h"

#import "../../ImGui/imgui.h"
#import "PanelState.h"
#import "../Widgets/UIWidgets.h"
#import "../Widgets/UIConstants.h"
#import "../EditorIcons.h"
#include <string.h>
#include <stdint.h>
#include <string>
#include <vector>
#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <cmath>
#include <cfloat>
#include <climits>

extern "C" uint32_t MCEEditorEntityHasComponent(MCE_CTX,  const char *entityId, int32_t componentType);
extern "C" uint32_t MCEEditorAddComponent(MCE_CTX,  const char *entityId, int32_t componentType);
extern "C" uint32_t MCEEditorRemoveComponent(MCE_CTX,  const char *entityId, int32_t componentType);
extern "C" uint32_t MCEEditorEntityExists(MCE_CTX,  const char *entityId);
extern "C" uint32_t MCEEditorEntityIsAutoDrivenSkySun(MCE_CTX, const char *entityId);
extern "C" int32_t MCEEditorSkyEntityCount(MCE_CTX);
extern "C" int32_t MCEEditorGetActiveSkyId(MCE_CTX,  char *buffer, int32_t bufferSize);
extern "C" uint32_t MCEEditorSetActiveSky(MCE_CTX,  const char *entityId);

extern "C" int32_t MCEEditorGetEntityName(MCE_CTX,  const char *entityId, char *buffer, int32_t bufferSize);
extern "C" void MCEEditorSetEntityName(MCE_CTX,  const char *entityId, const char *name);

extern "C" uint32_t MCEEditorGetTransform(MCE_CTX,  const char *entityId, float *px, float *py, float *pz,
                                          float *rx, float *ry, float *rz,
                                          float *sx, float *sy, float *sz);
extern "C" void MCEEditorSetTransform(MCE_CTX,  const char *entityId, float px, float py, float pz,
                                      float rx, float ry, float rz,
                                      float sx, float sy, float sz);
extern "C" uint32_t MCEEditorGetCamera(MCE_CTX,  const char *entityId,
                                       int32_t *projectionType,
                                       float *fovDegrees,
                                       float *orthoSize,
                                       float *nearPlane,
                                       float *farPlane,
                                       uint32_t *isPrimary,
                                       uint32_t *isEditor);
extern "C" void MCEEditorSetCamera(MCE_CTX,  const char *entityId,
                                   int32_t projectionType,
                                   float fovDegrees,
                                   float orthoSize,
                                   float nearPlane,
                                   float farPlane,
                                   uint32_t isPrimary);
extern "C" uint32_t MCEEditorGetReflectionProbe(MCE_CTX,  const char *entityId,
                                                uint32_t *enabled,
                                                float *boxExtentsX,
                                                float *boxExtentsY,
                                                float *boxExtentsZ,
                                                float *blendDistance,
                                                int32_t *priority,
                                                float *intensity,
                                                int32_t *captureResolution,
                                                int32_t *rebuildMode,
                                                uint32_t *includeSky);
extern "C" void MCEEditorSetReflectionProbe(MCE_CTX,  const char *entityId,
                                            uint32_t enabled,
                                            float boxExtentsX,
                                            float boxExtentsY,
                                            float boxExtentsZ,
                                            float blendDistance,
                                            int32_t priority,
                                            float intensity,
                                            int32_t captureResolution,
                                            int32_t rebuildMode,
                                            uint32_t includeSky);
extern "C" uint32_t MCEEditorGetReflectionProbeRuntimeStatus(MCE_CTX,  const char *entityId, int32_t *statusOut);
extern "C" uint32_t MCEEditorRequestReflectionProbeRebuild(MCE_CTX,  const char *entityId);
extern "C" uint32_t MCEEditorRequestAllReflectionProbeRebuilds(MCE_CTX);
extern "C" uint32_t MCEEditorGetCameraExposure(MCE_CTX, const char *entityId,
                                               uint32_t *autoExposureEnabled,
                                               float *exposureEV,
                                               float *exposureCompensation,
                                               float *autoExposureMin,
                                               float *autoExposureMax,
                                               float *adaptationSpeed);
extern "C" void MCEEditorSetCameraExposure(MCE_CTX, const char *entityId,
                                           uint32_t autoExposureEnabled,
                                           float exposureEV,
                                           float exposureCompensation,
                                           float autoExposureMin,
                                           float autoExposureMax,
                                           float adaptationSpeed);

extern "C" uint32_t MCEEditorGetMeshRenderer(MCE_CTX,  const char *entityId, char *meshHandle, int32_t meshHandleSize,
                                             char *materialHandle, int32_t materialHandleSize);
extern "C" void MCEEditorSetMeshRenderer(MCE_CTX,  const char *entityId, const char *meshHandle, const char *materialHandle);
extern "C" uint32_t MCEEditorGetSkinnedMesh(MCE_CTX, const char *entityId,
                                             char *skeletonHandle, int32_t skeletonHandleSize,
                                             int32_t *jointCount, uint32_t *isValid);
extern "C" void MCEEditorSetSkinnedMesh(MCE_CTX, const char *entityId, const char *skeletonHandle);
extern "C" uint32_t MCEEditorGetAnimator(MCE_CTX, const char *entityId,
                                         char *clipHandle, int32_t clipHandleSize,
                                         float *playbackTime, float *playbackSpeed,
                                         uint32_t *isPlaying, uint32_t *isLooping);
extern "C" void MCEEditorSetAnimator(MCE_CTX, const char *entityId, const char *clipHandle,
                                     float playbackTime, float playbackSpeed,
                                     uint32_t isPlaying, uint32_t isLooping);
extern "C" uint32_t MCEEditorGetAnimatorMode(MCE_CTX, const char *entityId,
                                             int32_t *modeOut,
                                             char *graphHandle, int32_t graphHandleSize);
extern "C" void MCEEditorSetAnimatorGraph(MCE_CTX, const char *entityId, const char *graphHandle,
                                          float playbackTime, float playbackSpeed,
                                          uint32_t isPlaying, uint32_t isLooping);
extern "C" int32_t MCEEditorGetAnimatorGraphParameterCount(MCE_CTX, const char *entityId);
extern "C" uint32_t MCEEditorGetAnimatorGraphParameterAt(MCE_CTX, const char *entityId, int32_t index,
                                                         char *nameBuffer, int32_t nameBufferSize,
                                                         int32_t *typeOut,
                                                         float *defaultFloatOut,
                                                         uint32_t *defaultBoolOut,
                                                         int32_t *defaultIntOut,
                                                         float *floatValueOut,
                                                         uint32_t *boolValueOut,
                                                         int32_t *intValueOut,
                                                         uint32_t *triggerValueOut);
extern "C" uint32_t MCEEditorSetAnimatorGraphParameterFloat(MCE_CTX, const char *entityId, int32_t index, float value);
extern "C" uint32_t MCEEditorSetAnimatorGraphParameterBool(MCE_CTX, const char *entityId, int32_t index, uint32_t value);
extern "C" uint32_t MCEEditorSetAnimatorGraphParameterInt(MCE_CTX, const char *entityId, int32_t index, int32_t value);
extern "C" uint32_t MCEEditorSetAnimatorGraphParameterTrigger(MCE_CTX, const char *entityId, int32_t index);
extern "C" uint32_t MCEEditorGetAnimatorRootMotionEnabled(MCE_CTX, const char *entityId, uint32_t *enabledOut);
extern "C" uint32_t MCEEditorSetAnimatorRootMotionEnabled(MCE_CTX, const char *entityId, uint32_t enabled);
extern "C" uint32_t MCEEditorGetAnimatorGraphRuntimeDebug(MCE_CTX, const char *entityId,
                                                          char *currentStateBuffer, int32_t currentStateBufferSize,
                                                          char *nextStateBuffer, int32_t nextStateBufferSize,
                                                          char *rootMotionBoneBuffer, int32_t rootMotionBoneBufferSize,
                                                          char *rootMotionTranslationBoneBuffer, int32_t rootMotionTranslationBoneBufferSize,
                                                          char *rootMotionRotationBoneBuffer, int32_t rootMotionRotationBoneBufferSize,
                                                          char *rootMotionConsumeBoneBuffer, int32_t rootMotionConsumeBoneBufferSize,
                                                          float *speedOut,
                                                          uint32_t *groundedOut,
                                                          float *moveXOut,
                                                          float *moveYOut,
                                                          uint32_t *jumpTriggerOut,
                                                          uint32_t *rootMotionEnabledOut,
                                                          uint32_t *usesRootMotionOut,
                                                          float *rootMotionDeltaMagnitudeOut,
                                                          int32_t *rootMotionJointIndexOut,
                                                          int32_t *rootMotionTranslationJointIndexOut,
                                                          int32_t *rootMotionRotationJointIndexOut,
                                                          int32_t *rootMotionConsumeJointIndexOut,
                                                          uint32_t *rootMotionTrackConsumedOut);
extern "C" void MCEEditorAssignMaterialToEntity(MCE_CTX,  const char *entityId, const char *materialHandle);
extern "C" uint32_t MCEEditorGetMaterialComponent(MCE_CTX,  const char *entityId, char *materialHandle, int32_t materialHandleSize);
extern "C" void MCEEditorSetMaterialComponent(MCE_CTX,  const char *entityId, const char *materialHandle);

extern "C" uint32_t MCEEditorGetLight(MCE_CTX,  const char *entityId, int32_t *type, float *colorX, float *colorY, float *colorZ,
                                      float *brightness, float *range, float *innerCos, float *outerCos,
                                      float *dirX, float *dirY, float *dirZ, uint32_t *castsShadows);
extern "C" void MCEEditorSetLight(MCE_CTX,  const char *entityId, int32_t type, float colorX, float colorY, float colorZ,
                                  float brightness, float range, float innerCos, float outerCos,
                                  float dirX, float dirY, float dirZ, uint32_t castsShadows);

extern "C" uint32_t MCEEditorGetSkyLight(MCE_CTX,  const char *entityId, int32_t *mode, uint32_t *enabled,
                                         float *timeOfDay, int32_t *weatherType, int32_t *secondaryWeatherType, float *weatherBlend, float *weatherAmount,
                                         float *atmosphereAmount, float *cloudCoverage, int32_t *cloudStyle,
                                         float *temperature, float *mood,
                                         float *intensity, float *tintX, float *tintY, float *tintZ,
                                         float *turbidity, float *azimuth, float *elevation, float *sunSize,
                                         float *zenithTintX, float *zenithTintY, float *zenithTintZ,
                                         float *horizonTintX, float *horizonTintY, float *horizonTintZ,
                                         float *gradientStrength,
                                         float *hazeDensity, float *hazeFalloff, float *hazeHeight,
                                         float *ozoneStrength, float *ozoneTintX, float *ozoneTintY, float *ozoneTintZ,
                                         float *sunHaloSize, float *sunHaloIntensity, float *sunHaloSoftness,
                                         uint32_t *cloudsEnabled, float *cloudsCoverage, float *cloudsSoftness,
                                         float *cloudsScale, float *cloudsSpeed,
                                         float *cloudsWindX, float *cloudsWindY,
                                         float *cloudsHeight, float *cloudsThickness,
                                         float *cloudsBrightness, float *cloudsSunInfluence,
                                         float *fogAmount, float *fogHeight, float *fogDistance,
                                         uint32_t *autoRebuild, uint32_t *needsRebuild,
                                         char *hdriHandle, int32_t hdriHandleSize);
extern "C" void MCEEditorSetSkyLight(MCE_CTX,  const char *entityId, int32_t mode, uint32_t enabled,
                                     float timeOfDay, int32_t weatherType, int32_t secondaryWeatherType, float weatherBlend, float weatherAmount,
                                     float atmosphereAmount, float cloudCoverage, int32_t cloudStyle,
                                     float temperature, float mood,
                                     float intensity, float tintX, float tintY, float tintZ,
                                     float turbidity, float azimuth, float elevation, float sunSize,
                                     float zenithTintX, float zenithTintY, float zenithTintZ,
                                     float horizonTintX, float horizonTintY, float horizonTintZ,
                                     float gradientStrength,
                                     float hazeDensity, float hazeFalloff, float hazeHeight,
                                     float ozoneStrength, float ozoneTintX, float ozoneTintY, float ozoneTintZ,
                                     float sunHaloSize, float sunHaloIntensity, float sunHaloSoftness,
                                     uint32_t cloudsEnabled, float cloudsCoverage, float cloudsSoftness,
                                     float cloudsScale, float cloudsSpeed,
                                     float cloudsWindX, float cloudsWindY,
                                     float cloudsHeight, float cloudsThickness,
                                     float cloudsBrightness, float cloudsSunInfluence,
                                     float fogAmount, float fogHeight, float fogDistance,
                                     uint32_t autoRebuild,
                                     const char *hdriHandle);
extern "C" void MCEEditorRequestSkyRebuild(MCE_CTX,  const char *entityId);

struct MCEEnvironmentLookBridge {
    int32_t preset;
    float mood;
    float warmth;
    float cinematicAmount;
};

struct MCEEnvironmentSourceBridge {
    uint32_t enabled;
    int32_t mode;
    uint32_t hasHdriHandle;
    uint64_t hdriHandleHigh;
    uint64_t hdriHandleLow;
};

struct MCEEnvironmentTimeBridge {
    float defaultTimeOfDay;
    float previewTimeOfDay;
    int32_t timeControlMode;
    float dayLengthSeconds;
    float timeScale;
};

struct MCEEnvironmentAtmosphereBridge {
    float amount;
    float haze;
    float density;
    float temperature;
    float mood;
};

struct MCEEnvironmentCelestialBridge {
    float moonIntensity;
    float moonSizeDegrees;
    float starIntensity;
    float starRichness;
    float milkyWayIntensity;
    float milkyWayChroma;
    float milkyWayRotation;
    float nightBrightness;
};

struct MCEEnvironmentWeatherCloudBridge {
    int32_t weatherPrimary;
    int32_t weatherSecondary;
    float weatherBlend;
    float weatherAmount;
    float cloudCoverage;
    int32_t cloudStyle;
    int32_t cloudRenderMode;
};

struct MCEEnvironmentFogBridge {
    float amount;
    float height;
    float distance;
};

struct MCEEnvironmentIBLBridge {
    uint32_t realtimeUpdate;
    uint32_t autoRebuildOnChange;
    uint32_t needsRebuild;
    uint32_t dirty;
    uint32_t isRebuilding;
    int32_t currentRebuildQuality;
    int32_t lastBuiltQuality;
    uint32_t hasFailure;
};

extern "C" uint32_t MCEEditorGetEnvironmentLookBridge(MCE_CTX, const char *entityId,
                                                       MCEEnvironmentLookBridge *outValue);
extern "C" void MCEEditorSetEnvironmentLookBridge(MCE_CTX, const char *entityId,
                                                   const MCEEnvironmentLookBridge *value);
extern "C" uint32_t MCEEditorGetEnvironmentSourceBridge(MCE_CTX, const char *entityId,
                                                         MCEEnvironmentSourceBridge *outValue);
extern "C" void MCEEditorSetEnvironmentSourceBridge(MCE_CTX, const char *entityId,
                                                     const MCEEnvironmentSourceBridge *value);
extern "C" uint32_t MCEEditorGetEnvironmentTimeBridge(MCE_CTX, const char *entityId,
                                                       MCEEnvironmentTimeBridge *outValue);
extern "C" void MCEEditorSetEnvironmentTimeBridge(MCE_CTX, const char *entityId,
                                                   const MCEEnvironmentTimeBridge *value);
extern "C" uint32_t MCEEditorGetEnvironmentAtmosphereBridge(MCE_CTX, const char *entityId,
                                                             MCEEnvironmentAtmosphereBridge *outValue);
extern "C" void MCEEditorSetEnvironmentAtmosphereBridge(MCE_CTX, const char *entityId,
                                                         const MCEEnvironmentAtmosphereBridge *value);
extern "C" uint32_t MCEEditorGetEnvironmentCelestialBridge(MCE_CTX, const char *entityId,
                                                            MCEEnvironmentCelestialBridge *outValue);
extern "C" void MCEEditorSetEnvironmentCelestialBridge(MCE_CTX, const char *entityId,
                                                        const MCEEnvironmentCelestialBridge *value);
extern "C" uint32_t MCEEditorGetEnvironmentWeatherCloudBridge(MCE_CTX, const char *entityId,
                                                               MCEEnvironmentWeatherCloudBridge *outValue);
extern "C" void MCEEditorSetEnvironmentWeatherCloudBridge(MCE_CTX, const char *entityId,
                                                           const MCEEnvironmentWeatherCloudBridge *value);
extern "C" uint32_t MCEEditorGetEnvironmentFogBridge(MCE_CTX, const char *entityId,
                                                      MCEEnvironmentFogBridge *outValue);
extern "C" void MCEEditorSetEnvironmentFogBridge(MCE_CTX, const char *entityId,
                                                  const MCEEnvironmentFogBridge *value);
extern "C" uint32_t MCEEditorGetEnvironmentIBLStatusBridge(MCE_CTX, const char *entityId,
                                                            MCEEnvironmentIBLBridge *outValue);
extern "C" void MCEEditorSetEnvironmentIBLConfigBridge(MCE_CTX, const char *entityId,
                                                        const MCEEnvironmentIBLBridge *value);
extern "C" uint32_t MCEEditorGetEnvironmentLook(MCE_CTX, const char *entityId,
                                                 int32_t *preset,
                                                 float *mood,
                                                 float *warmth,
                                                 float *cinematicAmount);
extern "C" void MCEEditorApplyEnvironmentPreset(MCE_CTX, const char *entityId,
                                                 int32_t preset);
extern "C" uint32_t MCEEditorGetEnvironmentSource(MCE_CTX, const char *entityId,
                                                   uint32_t *enabled,
                                                   int32_t *mode,
                                                   char *hdriHandle,
                                                   int32_t hdriHandleSize);
extern "C" void MCEEditorSetEnvironmentSource(MCE_CTX, const char *entityId,
                                               uint32_t enabled,
                                               int32_t mode,
                                               const char *hdriHandle);
extern "C" uint32_t MCEEditorGetEnvironmentCelestial(MCE_CTX, const char *entityId,
                                                      float *defaultTimeOfDay,
                                                      float *previewTimeOfDay,
                                                      float *moonIntensity,
                                                      float *moonSizeDegrees,
                                                      float *starIntensity);
extern "C" void MCEEditorSetEnvironmentCelestial(MCE_CTX, const char *entityId,
                                                  float defaultTimeOfDay,
                                                  float moonIntensity,
                                                  float moonSizeDegrees,
                                                  float starIntensity);
extern "C" void MCEEditorSetEnvironmentPreviewTime(MCE_CTX, const char *entityId,
                                                    float previewTimeOfDay);
extern "C" uint32_t MCEEditorGetEnvironmentWeather(MCE_CTX, const char *entityId,
                                                    int32_t *primaryType,
                                                    int32_t *secondaryType,
                                                    float *blend,
                                                    float *amount);
extern "C" void MCEEditorSetEnvironmentWeather(MCE_CTX, const char *entityId,
                                                int32_t primaryType,
                                                int32_t secondaryType,
                                                float blend,
                                                float amount);
extern "C" uint32_t MCEEditorGetEnvironmentAtmosphere(MCE_CTX, const char *entityId,
                                                       float *amount,
                                                       float *haze,
                                                       float *density,
                                                       float *temperature,
                                                       float *mood);
extern "C" void MCEEditorSetEnvironmentAtmosphere(MCE_CTX, const char *entityId,
                                                   float amount,
                                                   float haze,
                                                   float density,
                                                   float temperature,
                                                   float mood);
extern "C" uint32_t MCEEditorGetEnvironmentClouds(MCE_CTX, const char *entityId,
                                                   float *coverage,
                                                   int32_t *style);
extern "C" void MCEEditorSetEnvironmentClouds(MCE_CTX, const char *entityId,
                                               float coverage,
                                               int32_t style);
extern "C" uint32_t MCEEditorGetEnvironmentFog(MCE_CTX, const char *entityId,
                                                float *amount,
                                                float *height,
                                                float *distance);
extern "C" void MCEEditorSetEnvironmentFog(MCE_CTX, const char *entityId,
                                            float amount,
                                            float height,
                                            float distance);
extern "C" uint32_t MCEEditorGetEnvironmentIBL(MCE_CTX, const char *entityId,
                                                uint32_t *realtimeUpdate,
                                                uint32_t *autoRebuildOnChange,
                                                uint32_t *needsRebuild,
                                                uint32_t *dirty,
                                                uint32_t *isRebuilding,
                                                int32_t *currentRebuildQuality,
                                                int32_t *lastBuiltQuality,
                                                char *lastFailureMessage,
                                                int32_t lastFailureMessageSize);
extern "C" void MCEEditorSetEnvironmentIBL(MCE_CTX, const char *entityId,
                                            uint32_t realtimeUpdate,
                                            uint32_t autoRebuildOnChange);
extern "C" void MCEEditorRequestEnvironmentIBLRebuild(MCE_CTX, const char *entityId);
extern "C" uint32_t MCEEditorGetRigidbody(MCE_CTX,  const char *entityId,
                                          uint32_t *enabled,
                                          int32_t *motionType,
                                          float *mass,
                                          float *friction,
                                          float *restitution,
                                          float *linearDamping,
                                          float *angularDamping,
                                          float *gravityFactor,
                                          uint32_t *allowSleeping,
                                          uint32_t *ccdEnabled,
                                          int32_t *collisionLayer);
extern "C" void MCEEditorSetRigidbody(MCE_CTX,  const char *entityId,
                                      uint32_t enabled,
                                      int32_t motionType,
                                      float mass,
                                      float friction,
                                      float restitution,
                                      float linearDamping,
                                      float angularDamping,
                                      float gravityFactor,
                                      uint32_t allowSleeping,
                                      uint32_t ccdEnabled,
                                      int32_t collisionLayer);
extern "C" uint32_t MCEEditorGetCollider(MCE_CTX,  const char *entityId,
                                         uint32_t *enabled,
                                         int32_t *shapeType,
                                         float *boxX, float *boxY, float *boxZ,
                                         float *sphereRadius,
                                         float *capsuleHalfHeight,
                                         float *capsuleRadius,
                                         float *offsetX, float *offsetY, float *offsetZ,
                                         float *rotX, float *rotY, float *rotZ,
                                         uint32_t *isTrigger);
extern "C" void MCEEditorSetCollider(MCE_CTX,  const char *entityId,
                                     uint32_t enabled,
                                     int32_t shapeType,
                                     float boxX, float boxY, float boxZ,
                                     float sphereRadius,
                                     float capsuleHalfHeight,
                                     float capsuleRadius,
                                     float offsetX, float offsetY, float offsetZ,
                                     float rotX, float rotY, float rotZ,
                                     uint32_t isTrigger);
extern "C" int32_t MCEEditorGetColliderShapeCount(MCE_CTX, const char *entityId);
extern "C" void MCEEditorAddColliderShape(MCE_CTX, const char *entityId);
extern "C" void MCEEditorRemoveColliderShape(MCE_CTX, const char *entityId, int32_t shapeIndex);
extern "C" uint32_t MCEEditorGetColliderShape(MCE_CTX, const char *entityId,
                                              int32_t shapeIndex,
                                              uint32_t *enabled,
                                              int32_t *shapeType,
                                              float *boxX, float *boxY, float *boxZ,
                                              float *sphereRadius,
                                              float *capsuleHalfHeight,
                                              float *capsuleRadius,
                                              float *offsetX, float *offsetY, float *offsetZ,
                                              float *rotX, float *rotY, float *rotZ,
                                              uint32_t *isTrigger,
                                              uint32_t *hasLayerOverride,
                                              int32_t *layerOverride);
extern "C" void MCEEditorSetColliderShape(MCE_CTX, const char *entityId,
                                          int32_t shapeIndex,
                                          uint32_t enabled,
                                          int32_t shapeType,
                                          float boxX, float boxY, float boxZ,
                                          float sphereRadius,
                                          float capsuleHalfHeight,
                                          float capsuleRadius,
                                          float offsetX, float offsetY, float offsetZ,
                                          float rotX, float rotY, float rotZ,
                                          uint32_t isTrigger,
                                          uint32_t hasLayerOverride,
                                          int32_t layerOverride);
extern "C" uint32_t MCEEditorRebuildPhysicsBody(MCE_CTX,  const char *entityId);
extern "C" uint32_t MCEEditorGetScript(MCE_CTX,  const char *entityId,
                                       uint32_t *enabled,
                                       char *scriptHandleBuffer, int32_t scriptHandleBufferSize,
                                       char *typeNameBuffer, int32_t typeNameBufferSize,
                                       uint32_t *fieldDataSize,
                                       uint32_t *fieldDataVersion);
extern "C" uint32_t MCEEditorSetScript(MCE_CTX,  const char *entityId,
                                       uint32_t enabled,
                                       const char *scriptHandle,
                                       const char *typeName,
                                       uint32_t keepFieldData);
extern "C" uint32_t MCEEditorClearScriptFieldData(MCE_CTX,  const char *entityId);
extern "C" uint32_t MCEEditorResetScriptFieldsToDefaults(MCE_CTX, const char *entityId);
extern "C" uint32_t MCEEditorGetScriptRuntimeStatus(MCE_CTX,  const char *entityId,
                                                    int32_t *runtimeStateOut,
                                                    uint32_t *hasInstanceOut,
                                                    char *errorBuffer, int32_t errorBufferSize);
extern "C" uint32_t MCEEditorReloadScriptInstance(MCE_CTX,  const char *entityId);
extern "C" int32_t MCEEditorGetScriptFieldCount(MCE_CTX, const char *entityId);
extern "C" uint32_t MCEEditorGetScriptFieldAt(MCE_CTX, const char *entityId, int32_t index,
                                              char *fieldName, int32_t fieldNameSize,
                                              int32_t *fieldType,
                                              int32_t *intValue,
                                              float *numberValue,
                                              uint32_t *boolValue,
                                              char *stringValue, int32_t stringValueSize,
                                              float *vecX, float *vecY, float *vecZ,
                                              char *entityValue, int32_t entityValueSize,
                                              char *prefabValue, int32_t prefabValueSize,
                                              uint32_t *hasMin, float *minValue,
                                              uint32_t *hasMax, float *maxValue,
                                              uint32_t *hasStep, float *stepValue,
                                              char *tooltip, int32_t tooltipSize,
                                              uint32_t *isMissingReference);
extern "C" uint32_t MCEEditorSetScriptField(MCE_CTX, const char *entityId, const char *fieldName,
                                            int32_t fieldType,
                                            int32_t intValue,
                                            float numberValue,
                                            uint32_t boolValue,
                                            const char *stringValue,
                                            float vecX, float vecY, float vecZ,
                                            const char *entityValue,
                                            const char *prefabValue);
extern "C" int32_t MCEEditorGetEntityCount(MCE_CTX);
extern "C" int32_t MCEEditorGetEntityIdAt(MCE_CTX, int32_t index, char *buffer, int32_t bufferSize);
extern "C" int32_t MCEEditorGetChildEntityCount(MCE_CTX, const char *parentId);
extern "C" int32_t MCEEditorGetChildEntityIdAt(MCE_CTX, const char *parentId, int32_t index, char *buffer, int32_t bufferSize);
extern "C" int32_t MCEEditorGetParentEntityId(MCE_CTX, const char *childId, char *buffer, int32_t bufferSize);
extern "C" int32_t MCEEditorCreateEntity(MCE_CTX, const char *name, char *outId, int32_t outIdSize);
extern "C" uint32_t MCEEditorSetParent(MCE_CTX, const char *childId, const char *parentId, uint32_t keepWorldTransform);
extern "C" uint32_t MCEEditorGetCharacterController(MCE_CTX, const char *entityId,
                                                     uint32_t *enabled,
                                                     float *height,
                                                     float *radius,
                                                     float *stepOffset,
                                                     float *moveSpeed,
                                                     float *sprintMultiplier,
                                                     float *jumpSpeed,
                                                     uint32_t *useGravityOverride,
                                                     float *gravity,
                                                     float *maxSlope,
                                                     float *pushStrength,
                                                     float *airControl,
                                                     float *lookSensitivity,
                                                     float *minPitchDegrees,
                                                     float *maxPitchDegrees,
                                                     uint32_t *debugDraw,
                                                     uint32_t *grounded,
                                                     float *speed,
                                                     float *velocityY,
                                                     uint64_t *groundBodyId,
                                                     float *fixedDeltaTime,
                                                     float *interpolationAlpha);
extern "C" void MCEEditorSetCharacterController(MCE_CTX, const char *entityId,
                                                uint32_t enabled,
                                                float height,
                                                float radius,
                                                float stepOffset,
                                                float moveSpeed,
                                                float sprintMultiplier,
                                                float jumpSpeed,
                                                uint32_t useGravityOverride,
                                                float gravity,
                                                float maxSlope,
                                                float pushStrength,
                                                float airControl,
                                                float lookSensitivity,
                                                float minPitchDegrees,
                                                float maxPitchDegrees,
                                                uint32_t debugDraw);
extern "C" uint32_t MCEEditorGetCharacterControllerEntityRefs(MCE_CTX, const char *entityId,
                                                               char *visualEntityIdOut, int32_t visualEntityIdSize,
                                                               char *cameraPivotEntityIdOut, int32_t cameraPivotEntityIdSize);
extern "C" uint32_t MCEEditorSetCharacterControllerEntityRefs(MCE_CTX, const char *entityId,
                                                               const char *visualEntityId,
                                                               const char *cameraPivotEntityId);
extern "C" uint32_t MCEEditorCharacterControllerRemoveRigidbody(MCE_CTX, const char *entityId);
extern "C" uint32_t MCEEditorCharacterControllerCreateRecommendedHierarchy(MCE_CTX, const char *entityId, uint32_t createCamera);
extern "C" uint32_t MCESceneIsPlaying(MCE_CTX);
extern "C" uint32_t MCESceneIsSimulating(MCE_CTX);
extern "C" uint32_t MCEEditorGetMaterialAsset(MCE_CTX, 
    const char *handle,
    char *nameBuffer, int32_t nameBufferSize,
    int32_t *version,
    float *baseColorX, float *baseColorY, float *baseColorZ,
    float *metallic, float *roughness, float *ao,
    float *emissiveX, float *emissiveY, float *emissiveZ,
    float *emissiveIntensity,
    float *uvTilingX, float *uvTilingY,
    float *uvOffsetX, float *uvOffsetY,
    int32_t *alphaMode, float *alphaCutoff,
    uint32_t *doubleSided, uint32_t *unlit,
    char *baseColorHandle, int32_t baseColorHandleSize,
    char *normalHandle, int32_t normalHandleSize,
    char *metalRoughnessHandle, int32_t metalRoughnessHandleSize,
    char *metallicHandle, int32_t metallicHandleSize,
    char *roughnessHandle, int32_t roughnessHandleSize,
    char *aoHandle, int32_t aoHandleSize,
    char *emissiveHandle, int32_t emissiveHandleSize);
extern "C" uint32_t MCEEditorSetMaterialAsset(MCE_CTX, 
    const char *handle,
    const char *name,
    int32_t version,
    float baseColorX, float baseColorY, float baseColorZ,
    float metallic, float roughness, float ao,
    float emissiveX, float emissiveY, float emissiveZ,
    float emissiveIntensity,
    float uvTilingX, float uvTilingY,
    float uvOffsetX, float uvOffsetY,
    int32_t alphaMode, float alphaCutoff,
    uint32_t doubleSided, uint32_t unlit,
    const char *baseColorHandle,
    const char *normalHandle,
    const char *metalRoughnessHandle,
    const char *metallicHandle,
    const char *roughnessHandle,
    const char *aoHandle,
    const char *emissiveHandle);
extern "C" uint32_t MCEEditorGetAssetDisplayName(MCE_CTX,  const char *handle, char *buffer, int32_t bufferSize);
extern "C" uint32_t MCEEditorGetImportedSkeletonHandleForMesh(MCE_CTX, const char *meshHandle, char *outHandle, int32_t outHandleSize);
extern "C" int32_t MCEEditorGetImportedClipCountForMesh(MCE_CTX, const char *meshHandle);
extern "C" uint32_t MCEEditorGetImportedClipHandleForMeshAt(MCE_CTX, const char *meshHandle, int32_t index, char *outHandle, int32_t outHandleSize);
extern "C" uint32_t MCEEditorGetImportedDefaultClipHandleForMesh(MCE_CTX, const char *meshHandle, char *outHandle, int32_t outHandleSize);
extern "C" uint32_t MCEEditorGetAnimationClipDuration(MCE_CTX, const char *clipHandle, float *durationOut);
extern "C" uint32_t MCEEditorGetSkeletonJointCount(MCE_CTX, const char *skeletonHandle, int32_t *countOut);
extern "C" int32_t MCEEditorGetAssociatedClipCountForSkeleton(MCE_CTX, const char *skeletonHandle);
extern "C" uint32_t MCEEditorGetAssociatedClipHandleForSkeletonAt(MCE_CTX, const char *skeletonHandle, int32_t index, char *outHandle, int32_t outHandleSize);
extern "C" uint32_t MCEEditorGetAnimatorRuntimeStats(MCE_CTX, const char *entityId, int32_t *evaluatedJointCount, uint32_t *hasPoseState);
extern "C" uint32_t MCEEditorGetAssetImportSetting(MCE_CTX, const char *handle, const char *key, char *valueOut, int32_t valueOutSize);
extern "C" uint32_t MCEEditorGetSelectedMaterial(MCE_CTX,  char *buffer, int32_t bufferSize);
extern "C" int32_t MCEEditorGetSelectedEntityCount(MCE_CTX);
extern "C" int32_t MCEEditorGetSelectedEntityIdAt(MCE_CTX, int32_t index, char *buffer, int32_t bufferSize);
extern "C" uint32_t MCEEditorCreateMaterial(MCE_CTX,  const char *relativePath, const char *name, char *outHandle, int32_t outHandleSize);
extern "C" void MCEEditorSetSelectedMaterial(MCE_CTX,  const char *handle);
extern "C" void MCEEditorOpenMaterialEditor(MCE_CTX,  const char *handle);
extern "C" uint32_t MCEEditorConsumeOpenMaterialEditor(MCE_CTX,  char *buffer, int32_t bufferSize);
extern "C" int32_t MCEEditorGetAssetCount(MCE_CTX);
extern "C" uint32_t MCEEditorGetAssetAt(MCE_CTX,  int32_t index,
                                        char *handleBuffer, int32_t handleBufferSize,
                                        int32_t *typeOut,
                                        char *pathBuffer, int32_t pathBufferSize,
                                        char *nameBuffer, int32_t nameBufferSize);
extern "C" uint32_t MCEEditorGetPrefabInstanceInfo(MCE_CTX,
                                                   const char *entityId,
                                                   char *prefabHandleOut, int32_t prefabHandleOutSize,
                                                   char *prefabPathOut, int32_t prefabPathOutSize);
extern "C" uint32_t MCEEditorApplyPrefabInstanceToAsset(MCE_CTX, const char *entityId);
extern "C" uint32_t MCEEditorRevertPrefabInstance(MCE_CTX, const char *entityId);
extern "C" void *MCEContextGetUIPanelState(MCE_CTX);

enum ComponentType : int32_t {
    ComponentName = 0,
    ComponentTransform = 1,
    ComponentMeshRenderer = 2,
    ComponentLight = 3,
    ComponentSkyLight = 4,
    ComponentMaterial = 5,
    ComponentCamera = 6,
    ComponentRigidbody = 7,
    ComponentCollider = 8,
    ComponentScript = 9,
    ComponentCharacterController = 10,
    ComponentSkinnedMesh = 11,
    ComponentAnimator = 12,
    ComponentReflectionProbe = 13,
    ComponentEnvironment = 14
};

namespace {
    constexpr float kDegToRad = 0.0174532925f;
    constexpr float kRadToDeg = 57.2957795f;

    using MCEPanelState::EnvironmentPickerState;
    using MCEPanelState::InspectorMaterialCache;
    using MCEPanelState::InspectorState;
    using MCEPanelState::MaterialEditorState;
    using MCEPanelState::MaterialPickerState;
    using MCEPanelState::MaterialPopupState;
    using MCEPanelState::MeshPickerState;
    using MCEPanelState::PendingSkyState;
    using MCEPanelState::ScriptPickerState;
    using MCEPanelState::TexturePickerState;

    InspectorState &GetInspectorState(void *context) {
        auto *state = static_cast<MCEPanelState::EditorUIPanelState *>(MCEContextGetUIPanelState(context));
        return state->inspector;
    }

    enum AtmosphereWeatherTypeUI : int32_t {
        AtmosphereWeatherClear = 0,
        AtmosphereWeatherPartlyCloudy = 1,
        AtmosphereWeatherOvercast = 2,
        AtmosphereWeatherStorm = 3,
        AtmosphereWeatherFoggy = 4,
        AtmosphereWeatherCustom = 5
    };

    enum AtmosphereCloudStyleUI : int32_t {
        AtmosphereCloudClear = 0,
        AtmosphereCloudWispy = 1,
        AtmosphereCloudPuffy = 2,
        AtmosphereCloudLayered = 3,
        AtmosphereCloudOvercast = 4,
        AtmosphereCloudStorm = 5,
        AtmosphereCloudCustom = 6
    };

    struct AtmospherePreset {
        const char *name;
        int32_t mode;
        uint32_t enabled;
        float timeOfDay;
        int32_t primaryWeatherType;
        int32_t secondaryWeatherType;
        float weatherBlend;
        float weatherAmount;
        float atmosphereAmount;
        float cloudCoverage;
        int32_t cloudStyle;
        float temperature;
        float mood;
        float fogAmount;
        float fogHeight;
        float fogDistance;
    };

    static const AtmospherePreset kSkyPresets[] = {
        {"Clear Day", 1, 1, 14.0f, AtmosphereWeatherClear, AtmosphereWeatherPartlyCloudy, 0.05f, 0.10f, 0.22f, 0.10f, AtmosphereCloudWispy, 0.05f, 0.25f, 0.02f, 0.0f, 8.0f},
        {"Golden Hour", 1, 1, 18.0f, AtmosphereWeatherPartlyCloudy, AtmosphereWeatherClear, 0.20f, 0.35f, 0.45f, 0.35f, AtmosphereCloudPuffy, 0.45f, 0.15f, 0.05f, 0.0f, 18.0f},
        {"Blue Hour", 1, 1, 19.5f, AtmosphereWeatherClear, AtmosphereWeatherFoggy, 0.10f, 0.15f, 0.30f, 0.05f, AtmosphereCloudClear, -0.20f, -0.20f, 0.01f, 0.0f, 22.0f},
        {"Overcast", 1, 1, 13.0f, AtmosphereWeatherOvercast, AtmosphereWeatherFoggy, 0.25f, 0.85f, 0.62f, 0.85f, AtmosphereCloudOvercast, -0.05f, -0.10f, 0.08f, 0.0f, 12.0f},
        {"Stormy", 1, 1, 16.0f, AtmosphereWeatherStorm, AtmosphereWeatherOvercast, 0.30f, 0.95f, 0.82f, 0.92f, AtmosphereCloudStorm, -0.08f, -0.55f, 0.14f, 0.0f, 10.0f},
        {"Desert Haze", 1, 1, 15.0f, AtmosphereWeatherClear, AtmosphereWeatherFoggy, 0.55f, 0.35f, 0.72f, 0.05f, AtmosphereCloudClear, 0.55f, 0.18f, 0.02f, 0.0f, 18.0f},
        {"Winter Cold", 1, 1, 11.5f, AtmosphereWeatherPartlyCloudy, AtmosphereWeatherOvercast, 0.18f, 0.30f, 0.28f, 0.35f, AtmosphereCloudLayered, -0.65f, 0.05f, 0.04f, 0.0f, 14.0f},
        {"Stylized", 1, 1, 17.0f, AtmosphereWeatherCustom, AtmosphereWeatherPartlyCloudy, 0.35f, 0.45f, 0.18f, 0.25f, AtmosphereCloudPuffy, 0.75f, 0.55f, 0.03f, 0.0f, 18.0f},
        {"Alien", 1, 1, 9.0f, AtmosphereWeatherCustom, AtmosphereWeatherFoggy, 0.40f, 0.50f, 0.30f, 0.45f, AtmosphereCloudLayered, -0.40f, 0.75f, 0.04f, 0.0f, 20.0f},
        {"Night Atmosphere", 1, 1, 22.0f, AtmosphereWeatherClear, AtmosphereWeatherFoggy, 0.20f, 0.15f, 0.12f, 0.0f, AtmosphereCloudClear, -0.35f, -0.35f, 0.01f, 0.0f, 30.0f}
    };

    static const char *kSkyPresetNames[] = {
        "Clear Day",
        "Golden Hour",
        "Blue Hour",
        "Overcast",
        "Stormy",
        "Desert Haze",
        "Winter Cold",
        "Stylized",
        "Alien",
        "Night Atmosphere"
    };

    static float RandomRange(float minValue, float maxValue) {
        const float t = static_cast<float>(rand()) / static_cast<float>(RAND_MAX);
        return minValue + (maxValue - minValue) * t;
    }

    static float ClampFloat(float value, float minValue, float maxValue) {
        return std::max(minValue, std::min(value, maxValue));
    }

    bool LoadMaterialState(void *context, const char *materialHandle, MaterialEditorState &state) {
        if (!materialHandle || materialHandle[0] == 0) { return false; }
        uint32_t doubleSided = 0;
        uint32_t unlit = 0;
        const bool loaded = MCEEditorGetMaterialAsset(
            context,
            materialHandle,
            state.name, sizeof(state.name),
            &state.version,
            &state.baseColor[0], &state.baseColor[1], &state.baseColor[2],
            &state.metallic, &state.roughness, &state.ao,
            &state.emissive[0], &state.emissive[1], &state.emissive[2],
            &state.emissiveIntensity,
            &state.uvTiling[0], &state.uvTiling[1],
            &state.uvOffset[0], &state.uvOffset[1],
            &state.alphaMode, &state.alphaCutoff,
            &doubleSided, &unlit,
            state.baseColorHandle, sizeof(state.baseColorHandle),
            state.normalHandle, sizeof(state.normalHandle),
            state.metalRoughnessHandle, sizeof(state.metalRoughnessHandle),
            state.metallicHandle, sizeof(state.metallicHandle),
            state.roughnessHandle, sizeof(state.roughnessHandle),
            state.aoHandle, sizeof(state.aoHandle),
            state.emissiveHandle, sizeof(state.emissiveHandle)) != 0;
        if (!loaded) {
            return false;
        }
        state.doubleSided = (doubleSided != 0);
        state.unlit = (unlit != 0);
        return true;
    }

    void GetAssetName(void *context, const char *handle, char *buffer, size_t bufferSize) {
        if (!handle || handle[0] == 0) {
            strncpy(buffer, "None", bufferSize - 1);
            buffer[bufferSize - 1] = 0;
            return;
        }
        if (strcmp(handle, "00000000-0000-0000-0000-000000000002") == 0) {
            strncpy(buffer, "Cube", bufferSize - 1);
            buffer[bufferSize - 1] = 0;
            return;
        }
        if (strcmp(handle, "00000000-0000-0000-0000-000000000006") == 0) {
            strncpy(buffer, "Plane", bufferSize - 1);
            buffer[bufferSize - 1] = 0;
            return;
        }
        if (strcmp(handle, "00000000-0000-0000-0000-000000000003") == 0) {
            strncpy(buffer, "Cubemap", bufferSize - 1);
            buffer[bufferSize - 1] = 0;
            return;
        }
        if (strcmp(handle, "00000000-0000-0000-0000-000000000004") == 0) {
            strncpy(buffer, "Skybox", bufferSize - 1);
            buffer[bufferSize - 1] = 0;
            return;
        }
        if (strcmp(handle, "00000000-0000-0000-0000-000000000005") == 0) {
            strncpy(buffer, "Fullscreen Quad", bufferSize - 1);
            buffer[bufferSize - 1] = 0;
            return;
        }
        if (MCEEditorGetAssetDisplayName(context, handle, buffer, static_cast<int32_t>(bufferSize)) == 0) {
            strncpy(buffer, handle, bufferSize - 1);
            buffer[bufferSize - 1] = 0;
        }
    }

    struct AssetOption {
        std::string handle;
        std::string name;
        std::string path;
    };

    std::string ClipOptionLabel(const AssetOption &option, const std::vector<AssetOption> &allOptions) {
        int duplicateNameCount = 0;
        for (const auto &candidate : allOptions) {
            if (candidate.name == option.name) {
                duplicateNameCount += 1;
            }
        }
        std::string label = option.name.empty() ? option.handle : option.name;
        if (duplicateNameCount > 1) {
            if (!option.path.empty()) {
                label += " | " + option.path;
            } else {
                label += " | " + option.handle.substr(0, std::min<size_t>(8, option.handle.size()));
            }
        }
        return label;
    }

    TexturePickerState &GetTexturePickerState(InspectorState &state) {
        return state.texturePicker;
    }

    EnvironmentPickerState &GetEnvironmentPickerState(InspectorState &state) {
        return state.environmentPicker;
    }

    MeshPickerState &GetMeshPickerState(InspectorState &state) {
        return state.meshPicker;
    }

    MaterialPickerState &GetMaterialPickerState(InspectorState &state) {
        return state.materialPicker;
    }

    ScriptPickerState &GetScriptPickerState(InspectorState &state) {
        return state.scriptPicker;
    }

    void LoadTextureOptions(void *context, std::vector<AssetOption> &options) {
        options.clear();
        const int32_t count = MCEEditorGetAssetCount(context);
        options.reserve(count);
        for (int32_t i = 0; i < count; ++i) {
            char handleBuffer[64] = {0};
            int32_t type = 0;
            char pathBuffer[512] = {0};
            char nameBuffer[128] = {0};
            if (MCEEditorGetAssetAt(context, i,
                                    handleBuffer, sizeof(handleBuffer),
                                    &type,
                                    pathBuffer, sizeof(pathBuffer),
                                    nameBuffer, sizeof(nameBuffer)) == 0) {
                continue;
            }
            if (type != 0) { continue; }
            if (handleBuffer[0] == 0) { continue; }
            AssetOption option;
            option.handle = handleBuffer;
            option.name = nameBuffer[0] != 0 ? nameBuffer : pathBuffer;
            option.path = pathBuffer;
            options.push_back(option);
        }
        std::sort(options.begin(), options.end(), [](const AssetOption &a, const AssetOption &b) {
            return a.name < b.name;
        });
    }

    void LoadEnvironmentOptions(void *context, std::vector<AssetOption> &options) {
        options.clear();
        const int32_t count = MCEEditorGetAssetCount(context);
        options.reserve(count);
        for (int32_t i = 0; i < count; ++i) {
            char handleBuffer[64] = {0};
            int32_t type = 0;
            char pathBuffer[512] = {0};
            char nameBuffer[128] = {0};
            if (MCEEditorGetAssetAt(context, i,
                                    handleBuffer, sizeof(handleBuffer),
                                    &type,
                                    pathBuffer, sizeof(pathBuffer),
                                    nameBuffer, sizeof(nameBuffer)) == 0) {
                continue;
            }
            if (type != 3) { continue; }
            if (handleBuffer[0] == 0) { continue; }
            AssetOption option;
            option.handle = handleBuffer;
            option.name = nameBuffer[0] != 0 ? nameBuffer : pathBuffer;
            option.path = pathBuffer;
            options.push_back(option);
        }
        std::sort(options.begin(), options.end(), [](const AssetOption &a, const AssetOption &b) {
            return a.name < b.name;
        });
    }

    void LoadMeshOptions(void *context, std::vector<AssetOption> &options) {
        options.clear();
        const int32_t count = MCEEditorGetAssetCount(context);
        options.reserve(count);
        for (int32_t i = 0; i < count; ++i) {
            char handleBuffer[64] = {0};
            int32_t type = 0;
            char pathBuffer[512] = {0};
            char nameBuffer[128] = {0};
            if (MCEEditorGetAssetAt(context, i,
                                    handleBuffer, sizeof(handleBuffer),
                                    &type,
                                    pathBuffer, sizeof(pathBuffer),
                                    nameBuffer, sizeof(nameBuffer)) == 0) {
                continue;
            }
            if (type != 1) { continue; }
            if (handleBuffer[0] == 0) { continue; }
            AssetOption option;
            option.handle = handleBuffer;
            option.name = nameBuffer[0] != 0 ? nameBuffer : pathBuffer;
            option.path = pathBuffer;
            options.push_back(option);
        }
        options.push_back({"00000000-0000-0000-0000-000000000002", "Cube"});
        options.push_back({"00000000-0000-0000-0000-000000000006", "Plane"});
        options.push_back({"00000000-0000-0000-0000-000000000003", "Cubemap"});
        options.push_back({"00000000-0000-0000-0000-000000000004", "Skybox"});
        options.push_back({"00000000-0000-0000-0000-000000000005", "Fullscreen Quad"});
        std::sort(options.begin(), options.end(), [](const AssetOption &a, const AssetOption &b) {
            return a.name < b.name;
        });
    }

    void LoadMaterialOptions(void *context, std::vector<AssetOption> &options) {
        options.clear();
        const int32_t count = MCEEditorGetAssetCount(context);
        options.reserve(count);
        for (int32_t i = 0; i < count; ++i) {
            char handleBuffer[64] = {0};
            int32_t type = 0;
            char pathBuffer[512] = {0};
            char nameBuffer[128] = {0};
            if (MCEEditorGetAssetAt(context, i,
                                    handleBuffer, sizeof(handleBuffer),
                                    &type,
                                    pathBuffer, sizeof(pathBuffer),
                                    nameBuffer, sizeof(nameBuffer)) == 0) {
                continue;
            }
            if (type != 2) { continue; }
            if (handleBuffer[0] == 0) { continue; }
            AssetOption option;
            option.handle = handleBuffer;
            option.name = nameBuffer[0] != 0 ? nameBuffer : pathBuffer;
            option.path = pathBuffer;
            options.push_back(option);
        }
        std::sort(options.begin(), options.end(), [](const AssetOption &a, const AssetOption &b) {
            return a.name < b.name;
        });
    }

    void LoadScriptOptions(void *context, std::vector<AssetOption> &options) {
        options.clear();
        const int32_t count = MCEEditorGetAssetCount(context);
        options.reserve(count);
        for (int32_t i = 0; i < count; ++i) {
            char handleBuffer[64] = {0};
            int32_t type = 0;
            char pathBuffer[512] = {0};
            char nameBuffer[128] = {0};
            if (MCEEditorGetAssetAt(context, i,
                                    handleBuffer, sizeof(handleBuffer),
                                    &type,
                                    pathBuffer, sizeof(pathBuffer),
                                    nameBuffer, sizeof(nameBuffer)) == 0) {
                continue;
            }
            if (type != 6) { continue; }
            if (handleBuffer[0] == 0) { continue; }
            AssetOption option;
            option.handle = handleBuffer;
            option.name = nameBuffer[0] != 0 ? nameBuffer : pathBuffer;
            option.path = pathBuffer;
            options.push_back(option);
        }
        std::sort(options.begin(), options.end(), [](const AssetOption &a, const AssetOption &b) {
            return a.name < b.name;
        });
    }

    void LoadSkeletonOptions(void *context, std::vector<AssetOption> &options) {
        options.clear();
        const int32_t count = MCEEditorGetAssetCount(context);
        options.reserve(count);
        for (int32_t i = 0; i < count; ++i) {
            char handleBuffer[64] = {0};
            int32_t type = 0;
            char pathBuffer[512] = {0};
            char nameBuffer[128] = {0};
            if (MCEEditorGetAssetAt(context, i,
                                    handleBuffer, sizeof(handleBuffer),
                                    &type,
                                    pathBuffer, sizeof(pathBuffer),
                                    nameBuffer, sizeof(nameBuffer)) == 0) {
                continue;
            }
            if (type != 8) { continue; }
            if (handleBuffer[0] == 0) { continue; }
            AssetOption option;
            option.handle = handleBuffer;
            option.name = nameBuffer[0] != 0 ? nameBuffer : pathBuffer;
            option.path = pathBuffer;
            options.push_back(option);
        }
        std::sort(options.begin(), options.end(), [](const AssetOption &a, const AssetOption &b) {
            return a.name < b.name;
        });
    }

    void LoadAnimationClipOptions(void *context, std::vector<AssetOption> &options) {
        options.clear();
        const int32_t count = MCEEditorGetAssetCount(context);
        options.reserve(count);
        for (int32_t i = 0; i < count; ++i) {
            char handleBuffer[64] = {0};
            int32_t type = 0;
            char pathBuffer[512] = {0};
            char nameBuffer[128] = {0};
            if (MCEEditorGetAssetAt(context, i,
                                    handleBuffer, sizeof(handleBuffer),
                                    &type,
                                    pathBuffer, sizeof(pathBuffer),
                                    nameBuffer, sizeof(nameBuffer)) == 0) {
                continue;
            }
            if (type != 9) { continue; }
            if (handleBuffer[0] == 0) { continue; }
            AssetOption option;
            option.handle = handleBuffer;
            option.name = nameBuffer[0] != 0 ? nameBuffer : pathBuffer;
            option.path = pathBuffer;
            options.push_back(option);
        }
        std::sort(options.begin(), options.end(), [](const AssetOption &a, const AssetOption &b) {
            return a.name < b.name;
        });
    }

    void LoadAnimationGraphOptions(void *context, std::vector<AssetOption> &options) {
        options.clear();
        const int32_t count = MCEEditorGetAssetCount(context);
        options.reserve(count);
        for (int32_t i = 0; i < count; ++i) {
            char handleBuffer[64] = {0};
            int32_t type = 0;
            char pathBuffer[512] = {0};
            char nameBuffer[128] = {0};
            if (MCEEditorGetAssetAt(context, i,
                                    handleBuffer, sizeof(handleBuffer),
                                    &type,
                                    pathBuffer, sizeof(pathBuffer),
                                    nameBuffer, sizeof(nameBuffer)) == 0) {
                continue;
            }
            if (type != 11) { continue; }
            if (handleBuffer[0] == 0) { continue; }
            AssetOption option;
            option.handle = handleBuffer;
            option.name = nameBuffer[0] != 0 ? nameBuffer : pathBuffer;
            option.path = pathBuffer;
            options.push_back(option);
        }
        std::sort(options.begin(), options.end(), [](const AssetOption &a, const AssetOption &b) {
            return a.name < b.name;
        });
    }

    void LoadPrefabOptions(void *context, std::vector<AssetOption> &options) {
        options.clear();
        const int32_t count = MCEEditorGetAssetCount(context);
        options.reserve(count);
        for (int32_t i = 0; i < count; ++i) {
            char handleBuffer[64] = {0};
            int32_t type = 0;
            char pathBuffer[512] = {0};
            char nameBuffer[128] = {0};
            if (MCEEditorGetAssetAt(context, i,
                                    handleBuffer, sizeof(handleBuffer),
                                    &type,
                                    pathBuffer, sizeof(pathBuffer),
                                    nameBuffer, sizeof(nameBuffer)) == 0) {
                continue;
            }
            if (type != 5) { continue; }
            if (handleBuffer[0] == 0) { continue; }
            AssetOption option;
            option.handle = handleBuffer;
            option.name = nameBuffer[0] != 0 ? nameBuffer : pathBuffer;
            option.path = pathBuffer;
            options.push_back(option);
        }
        std::sort(options.begin(), options.end(), [](const AssetOption &a, const AssetOption &b) {
            return a.name < b.name;
        });
    }

    void OpenTexturePicker(InspectorState &state, const char *label, char *target, const char *materialHandle) {
        auto &picker = GetTexturePickerState(state);
        picker.open = true;
        picker.requestOpen = true;
        picker.target = target;
        snprintf(picker.title, sizeof(picker.title), "Select Texture: %s", label);
        picker.filter[0] = 0;
        if (materialHandle) {
            strncpy(picker.materialHandle, materialHandle, sizeof(picker.materialHandle) - 1);
            picker.materialHandle[sizeof(picker.materialHandle) - 1] = 0;
        } else {
            picker.materialHandle[0] = 0;
        }
    }

    void OpenEnvironmentPicker(InspectorState &state, const char *label, char *target, const char *entityId) {
        auto &picker = GetEnvironmentPickerState(state);
        picker.open = true;
        picker.requestOpen = true;
        picker.target = target;
        snprintf(picker.title, sizeof(picker.title), "Select Environment: %s", label);
        picker.filter[0] = 0;
        if (entityId) {
            strncpy(picker.entityId, entityId, sizeof(picker.entityId) - 1);
            picker.entityId[sizeof(picker.entityId) - 1] = 0;
        } else {
            picker.entityId[0] = 0;
        }
    }

    void OpenMeshPicker(InspectorState &state, const char *label, const char *entityId, const char *materialHandle) {
        auto &picker = GetMeshPickerState(state);
        picker.open = true;
        picker.requestOpen = true;
        snprintf(picker.title, sizeof(picker.title), "Select Mesh: %s", label);
        picker.filter[0] = 0;
        if (entityId) {
            strncpy(picker.entityId, entityId, sizeof(picker.entityId) - 1);
            picker.entityId[sizeof(picker.entityId) - 1] = 0;
        } else {
            picker.entityId[0] = 0;
        }
        if (materialHandle) {
            strncpy(picker.materialHandle, materialHandle, sizeof(picker.materialHandle) - 1);
            picker.materialHandle[sizeof(picker.materialHandle) - 1] = 0;
        } else {
            picker.materialHandle[0] = 0;
        }
    }

    void OpenMaterialPicker(InspectorState &state, const char *label, const char *entityId, const char *meshHandle, bool usesMeshRenderer) {
        auto &picker = GetMaterialPickerState(state);
        picker.open = true;
        picker.requestOpen = true;
        snprintf(picker.title, sizeof(picker.title), "Select Material: %s", label);
        picker.filter[0] = 0;
        picker.usesMeshRenderer = usesMeshRenderer;
        if (entityId) {
            strncpy(picker.entityId, entityId, sizeof(picker.entityId) - 1);
            picker.entityId[sizeof(picker.entityId) - 1] = 0;
        } else {
            picker.entityId[0] = 0;
        }
        if (meshHandle) {
            strncpy(picker.meshHandle, meshHandle, sizeof(picker.meshHandle) - 1);
            picker.meshHandle[sizeof(picker.meshHandle) - 1] = 0;
        } else {
            picker.meshHandle[0] = 0;
        }
    }

    void OpenScriptPicker(InspectorState &state, const char *label, const char *entityId) {
        auto &picker = GetScriptPickerState(state);
        picker.open = true;
        picker.requestOpen = true;
        snprintf(picker.title, sizeof(picker.title), "Select Script: %s", label);
        picker.filter[0] = 0;
        if (entityId) {
            strncpy(picker.entityId, entityId, sizeof(picker.entityId) - 1);
            picker.entityId[sizeof(picker.entityId) - 1] = 0;
        } else {
            picker.entityId[0] = 0;
        }
    }

    bool DrawTextureSlotRow(void *context,
                            InspectorState &state,
                            const char *label,
                            char *handleBuffer,
                            size_t handleBufferSize,
                            const char *payloadType,
                            const char *materialHandle) {
        bool changed = false;
        ImGui::TableNextRow();
        ImGui::TableSetColumnIndex(0);
        ImGui::TextUnformatted(label);
        ImGui::TableSetColumnIndex(1);

        ImGui::PushID(label);
        char displayName[128] = {0};
        GetAssetName(context, handleBuffer, displayName, sizeof(displayName));
        const float wrapPos = ImGui::GetCursorPosX() + ImGui::GetContentRegionAvail().x - 6.0f;
        ImGui::PushTextWrapPos(wrapPos);
        ImGui::TextUnformatted(displayName);
        ImGui::PopTextWrapPos();
        if (ImGui::BeginDragDropTarget()) {
            if (const ImGuiPayload* payload = ImGui::AcceptDragDropPayload(payloadType)) {
                const char *payloadText = static_cast<const char *>(payload->Data);
                strncpy(handleBuffer, payloadText, handleBufferSize - 1);
                handleBuffer[handleBufferSize - 1] = 0;
                changed = true;
            }
            ImGui::EndDragDropTarget();
        }

        ImGui::TableSetColumnIndex(2);
        if (ImGui::Button((std::string("...##") + label).c_str())) {
            OpenTexturePicker(state, label, handleBuffer, materialHandle);
        }
        ImGui::TableSetColumnIndex(3);
        if (ImGui::Button((std::string("X##") + label).c_str())) {
            handleBuffer[0] = 0;
            changed = true;
        }
        ImGui::PopID();
        return changed;
    }

    bool DrawEnvironmentHandleRow(void *context,
                                  InspectorState &state,
                                  const char *label,
                                  char *handleBuffer,
                                  size_t handleBufferSize,
                                  const char *payloadType,
                                  const char *entityId) {
        bool changed = false;
        EditorUI::PropertyLabel(label);
        ImGui::PushID(label);
        char displayName[128] = {0};
        GetAssetName(context, handleBuffer, displayName, sizeof(displayName));
        const float wrapPos = ImGui::GetCursorPosX() + ImGui::GetContentRegionAvail().x - 120.0f;
        ImGui::PushTextWrapPos(wrapPos);
        ImGui::TextUnformatted(displayName);
        ImGui::PopTextWrapPos();
        if (ImGui::BeginDragDropTarget()) {
            if (const ImGuiPayload* payload = ImGui::AcceptDragDropPayload(payloadType)) {
                const char *payloadText = static_cast<const char *>(payload->Data);
                strncpy(handleBuffer, payloadText, handleBufferSize - 1);
                handleBuffer[handleBufferSize - 1] = 0;
                changed = true;
            }
            ImGui::EndDragDropTarget();
        }
        ImGui::SameLine();
        if (ImGui::Button("Select...")) {
            OpenEnvironmentPicker(state, label, handleBuffer, entityId);
        }
        ImGui::SameLine();
        if (ImGui::Button("Clear")) {
            handleBuffer[0] = 0;
            changed = true;
        }
        ImGui::PopID();
        return changed;
    }

    bool DrawMeshHandleRow(void *context,
                           InspectorState &state,
                           const char *label,
                           char *handleBuffer,
                           size_t handleBufferSize,
                           const char *payloadType,
                           const char *entityId,
                           const char *materialHandle) {
        bool changed = false;
        EditorUI::PropertyLabel(label);
        ImGui::PushID(label);
        char displayName[128] = {0};
        GetAssetName(context, handleBuffer, displayName, sizeof(displayName));
        const float wrapPos = ImGui::GetCursorPosX() + ImGui::GetContentRegionAvail().x - 120.0f;
        ImGui::PushTextWrapPos(wrapPos);
        ImGui::TextUnformatted(displayName);
        ImGui::PopTextWrapPos();
        if (ImGui::BeginDragDropTarget()) {
            if (const ImGuiPayload* payload = ImGui::AcceptDragDropPayload(payloadType)) {
                const char *payloadText = static_cast<const char *>(payload->Data);
                strncpy(handleBuffer, payloadText, handleBufferSize - 1);
                handleBuffer[handleBufferSize - 1] = 0;
                changed = true;
            }
            ImGui::EndDragDropTarget();
        }
        ImGui::SameLine();
        if (ImGui::Button("Select...")) {
            OpenMeshPicker(state, label, entityId, materialHandle);
        }
        ImGui::SameLine();
        if (ImGui::Button("Clear")) {
            handleBuffer[0] = 0;
            changed = true;
        }
        ImGui::PopID();
        return changed;
    }

    bool DrawMaterialHandleRow(void *context,
                               InspectorState &state,
                               const char *label,
                               char *handleBuffer,
                               size_t handleBufferSize,
                               const char *payloadType,
                               const char *entityId,
                               const char *meshHandle,
                               bool usesMeshRenderer) {
        bool changed = false;
        EditorUI::PropertyLabel(label);
        ImGui::PushID(label);
        char displayName[128] = {0};
        GetAssetName(context, handleBuffer, displayName, sizeof(displayName));
        const float wrapPos = ImGui::GetCursorPosX() + ImGui::GetContentRegionAvail().x - 120.0f;
        ImGui::PushTextWrapPos(wrapPos);
        ImGui::TextUnformatted(displayName);
        ImGui::PopTextWrapPos();
        if (ImGui::BeginDragDropTarget()) {
            if (const ImGuiPayload* payload = ImGui::AcceptDragDropPayload(payloadType)) {
                const char *payloadText = static_cast<const char *>(payload->Data);
                strncpy(handleBuffer, payloadText, handleBufferSize - 1);
                handleBuffer[handleBufferSize - 1] = 0;
                changed = true;
            }
            ImGui::EndDragDropTarget();
        }
        ImGui::SameLine();
        if (ImGui::Button("Select...")) {
            OpenMaterialPicker(state, label, entityId, meshHandle, usesMeshRenderer);
        }
        ImGui::SameLine();
        if (handleBuffer[0] != 0) {
            if (ImGui::Button("Edit")) {
                MCEEditorOpenMaterialEditor(context, handleBuffer);
            }
            ImGui::SameLine();
        }
        if (ImGui::Button("Clear")) {
            handleBuffer[0] = 0;
            changed = true;
        }
        ImGui::PopID();
        return changed;
    }

    bool DrawScriptHandleRow(void *context,
                             InspectorState &state,
                             const char *label,
                             char *handleBuffer,
                             size_t handleBufferSize,
                             const char *payloadType,
                             const char *entityId) {
        bool changed = false;
        EditorUI::PropertyLabel(label);
        ImGui::PushID(label);
        char displayName[128] = {0};
        GetAssetName(context, handleBuffer, displayName, sizeof(displayName));
        const float wrapPos = ImGui::GetCursorPosX() + ImGui::GetContentRegionAvail().x - 120.0f;
        ImGui::PushTextWrapPos(wrapPos);
        ImGui::TextUnformatted(displayName);
        ImGui::PopTextWrapPos();
        if (ImGui::BeginDragDropTarget()) {
            if (const ImGuiPayload* payload = ImGui::AcceptDragDropPayload(payloadType)) {
                const char *payloadText = static_cast<const char *>(payload->Data);
                strncpy(handleBuffer, payloadText, handleBufferSize - 1);
                handleBuffer[handleBufferSize - 1] = 0;
                changed = true;
            }
            ImGui::EndDragDropTarget();
        }
        ImGui::SameLine();
        if (ImGui::Button("Select...")) {
            OpenScriptPicker(state, label, entityId);
        }
        ImGui::SameLine();
        if (ImGui::Button("Clear")) {
            handleBuffer[0] = 0;
            changed = true;
        }
        ImGui::PopID();
        return changed;
    }

    void EnforceMetalRoughnessRule(MaterialEditorState &state) {
        const bool hasMetalRoughness = state.metalRoughnessHandle[0] != 0;
        const bool hasMetallic = state.metallicHandle[0] != 0;
        const bool hasRoughness = state.roughnessHandle[0] != 0;
        if (hasMetalRoughness) {
            state.metallicHandle[0] = 0;
            state.roughnessHandle[0] = 0;
        } else if (hasMetallic || hasRoughness) {
            state.metalRoughnessHandle[0] = 0;
        }
    }

    MaterialPopupState &GetMaterialPopupState(InspectorState &state) {
        return state.materialPopup;
    }

    void OpenMaterialPopup(void *context, InspectorState &state, const char *materialHandle) {
        if (!materialHandle || materialHandle[0] == 0) { return; }
        auto &popup = GetMaterialPopupState(state);
        memset(&popup.state, 0, sizeof(popup.state));
        if (!LoadMaterialState(context, materialHandle, popup.state)) { return; }
        strncpy(popup.handle, materialHandle, sizeof(popup.handle) - 1);
        popup.handle[sizeof(popup.handle) - 1] = 0;
        popup.dirty = false;
        popup.open = true;
        popup.title = std::string("Material: ") + (popup.state.name[0] != 0 ? popup.state.name : "Material");
        ImGui::OpenPopup(popup.title.c_str());
    }

    bool DrawMaterialTextureInspector(void *context, InspectorState &panelState, MaterialEditorState &materialState, const char *materialHandle) {
        bool dirty = false;
        EditorUI::SectionHeader("Textures");

        if (ImGui::BeginTable("InspectorMaterialTextures", 4, ImGuiTableFlags_BordersInnerH | ImGuiTableFlags_RowBg)) {
            ImGui::TableSetupColumn("Slot", ImGuiTableColumnFlags_WidthFixed, 120.0f);
            ImGui::TableSetupColumn("Texture", ImGuiTableColumnFlags_WidthStretch);
            ImGui::TableSetupColumn("Assign", ImGuiTableColumnFlags_WidthFixed, 70.0f);
            ImGui::TableSetupColumn("Clear", ImGuiTableColumnFlags_WidthFixed, 60.0f);
            ImGui::TableHeadersRow();

            dirty |= DrawTextureSlotRow(context, panelState, "Base Color", materialState.baseColorHandle, sizeof(materialState.baseColorHandle), "MCE_ASSET_TEXTURE", materialHandle);
            dirty |= DrawTextureSlotRow(context, panelState, "Normal", materialState.normalHandle, sizeof(materialState.normalHandle), "MCE_ASSET_TEXTURE", materialHandle);
            dirty |= DrawTextureSlotRow(context, panelState, "Metal/Rough", materialState.metalRoughnessHandle, sizeof(materialState.metalRoughnessHandle), "MCE_ASSET_TEXTURE", materialHandle);
            dirty |= DrawTextureSlotRow(context, panelState, "Metallic", materialState.metallicHandle, sizeof(materialState.metallicHandle), "MCE_ASSET_TEXTURE", materialHandle);
            dirty |= DrawTextureSlotRow(context, panelState, "Roughness", materialState.roughnessHandle, sizeof(materialState.roughnessHandle), "MCE_ASSET_TEXTURE", materialHandle);
            dirty |= DrawTextureSlotRow(context, panelState, "AO", materialState.aoHandle, sizeof(materialState.aoHandle), "MCE_ASSET_TEXTURE", materialHandle);
            dirty |= DrawTextureSlotRow(context, panelState, "Emissive", materialState.emissiveHandle, sizeof(materialState.emissiveHandle), "MCE_ASSET_TEXTURE", materialHandle);

            ImGui::EndTable();
        }

        const bool hasMetalRough = materialState.metalRoughnessHandle[0] != 0;
        const bool hasMetallic = materialState.metallicHandle[0] != 0;
        const bool hasRoughness = materialState.roughnessHandle[0] != 0;
        if (hasMetalRough && (hasMetallic || hasRoughness)) {
            ImGui::TextColored(ImVec4(0.95f, 0.7f, 0.2f, 1.0f), "Warning: Metal/Roughness conflicts with Metallic/Roughness maps.");
        }
        return dirty;
    }

    InspectorMaterialCache &GetInspectorMaterialCache(InspectorState &state) {
        return state.materialCache;
    }

    MaterialEditorState *GetInspectorMaterialState(void *context, InspectorState &state, const char *materialHandle) {
        if (!materialHandle || materialHandle[0] == 0) { return nullptr; }
        InspectorMaterialCache &cache = GetInspectorMaterialCache(state);
        if (!cache.valid || strcmp(cache.handle, materialHandle) != 0) {
            memset(&cache.state, 0, sizeof(cache.state));
            if (!LoadMaterialState(context, materialHandle, cache.state)) {
                cache.valid = false;
                cache.handle[0] = 0;
                return nullptr;
            }
            strncpy(cache.handle, materialHandle, sizeof(cache.handle) - 1);
            cache.handle[sizeof(cache.handle) - 1] = 0;
            cache.valid = true;
        }
        return &cache.state;
    }

    bool DrawMaterialEditorContents(MaterialEditorState &state) {
        bool dirty = false;
        EditorUI::SectionHeader("Surface");
        if (EditorUI::BeginPropertyTable("MaterialSurface")) {
            EditorUI::PropertyLabel("Version");
            ImGui::Text("%d", state.version);
            EditorUI::PropertyLabel("Material Name");
            dirty |= ImGui::InputText("##MaterialName", state.name, sizeof(state.name));
            const float baseDefault[3] = {1.0f, 1.0f, 1.0f};
            dirty |= EditorUI::PropertyColor3("Base Color", state.baseColor, baseDefault, true);
            dirty |= EditorUI::PropertyFloat("Metallic", &state.metallic, 0.01f, 0.0f, 1.0f, "%.3f", true, true, 1.0f);
            dirty |= EditorUI::PropertyFloat("Roughness", &state.roughness, 0.01f, EditorUIConstants::kRoughnessMin, EditorUIConstants::kRoughnessMax, "%.3f", true, true, 1.0f);
            dirty |= EditorUI::PropertyFloat("AO", &state.ao, 0.01f, 0.0f, 1.0f, "%.3f", true, true, 1.0f);
            EditorUI::EndPropertyTable();
        }

        EditorUI::StandardSpacing();
        EditorUI::SectionHeader("Emissive");
        if (EditorUI::BeginPropertyTable("MaterialEmissive")) {
            const float emissiveDefault[3] = {0.0f, 0.0f, 0.0f};
            dirty |= EditorUI::PropertyColor3("Emissive Color", state.emissive, emissiveDefault, true);
            dirty |= EditorUI::PropertyFloat("Emissive Intensity", &state.emissiveIntensity, 0.01f, 0.0f, 50.0f, "%.3f", true, true, 1.0f);
            const char* alphaModes[] = {"Opaque", "Alpha Clip", "Transparent", "Additive"};
            dirty |= EditorUI::PropertyCombo("Alpha Mode", &state.alphaMode, alphaModes, IM_ARRAYSIZE(alphaModes));
            dirty |= EditorUI::PropertyFloat("Alpha Cutoff", &state.alphaCutoff, 0.01f, 0.0f, 1.0f, "%.3f", true, true, 0.5f);
            dirty |= EditorUI::PropertyBool("Double Sided", &state.doubleSided);
            dirty |= EditorUI::PropertyBool("Unlit", &state.unlit);
            EditorUI::EndPropertyTable();
        }

        EditorUI::StandardSpacing();
        EditorUI::SectionHeader("UV");
        if (EditorUI::BeginPropertyTable("MaterialUV")) {
            dirty |= EditorUI::PropertyVec2("Tiling", state.uvTiling, 1.0f, 0.01f, 0.0f, 0.0f, "%.3f", false, true);
            dirty |= EditorUI::PropertyVec2("Offset", state.uvOffset, 0.0f, 0.01f, 0.0f, 0.0f, "%.3f", false, true);
            EditorUI::EndPropertyTable();
        }

        return dirty;
    }

    PendingSkyState &GetPendingSkyState(InspectorState &state) {
        return state.pendingSky;
    }
}

void ImGuiInspectorPanelDraw(void *context, bool *isOpen, const char *selectedEntityId) {
    if (!isOpen || !*isOpen) { return; }
    InspectorState &state = GetInspectorState(context);
    if (!EditorUI::BeginPanel("Properties", isOpen)) {
        EditorUI::EndPanel();
        return;
    }
    ImGui::BeginChild("InspectorScroll", ImVec2(0, 0), false, ImGuiWindowFlags_AlwaysVerticalScrollbar);

    std::vector<std::string> selectedIds;
    const int32_t selectedCount = MCEEditorGetSelectedEntityCount(context);
    selectedIds.reserve(selectedCount > 0 ? static_cast<size_t>(selectedCount) : 0);
    for (int32_t i = 0; i < selectedCount; ++i) {
        char idBuffer[64] = {0};
        if (MCEEditorGetSelectedEntityIdAt(context, i, idBuffer, sizeof(idBuffer)) > 0) {
            selectedIds.emplace_back(idBuffer);
        }
    }

    const bool hasEntityId = !selectedIds.empty() || (selectedEntityId && selectedEntityId[0] != 0);
    const bool hasValidEntity = hasEntityId && (MCEEditorEntityExists(context, selectedEntityId) != 0);
    const bool isPlaying = MCESceneIsPlaying(context) != 0;
    const bool isSimulating = MCESceneIsSimulating(context) != 0;
    const bool runtimeLocked = isPlaying || isSimulating;
    char selectedMaterial[64] = {0};
    const bool hasSelectedMaterial = MCEEditorGetSelectedMaterial(context, selectedMaterial, sizeof(selectedMaterial)) != 0;

    if (!hasValidEntity) {
        if (!hasSelectedMaterial) {
            ImGui::TextUnformatted(hasEntityId ? "Selection no longer exists." : "No entity selected.");
            ImGui::EndChild();
            EditorUI::EndPanel();
            return;
        }
    }

    ImGui::PushStyleVar(ImGuiStyleVar_FramePadding, ImVec2(6, 4));

    char pendingMaterialHandle[64] = {0};
    if (MCEEditorConsumeOpenMaterialEditor(context, pendingMaterialHandle, sizeof(pendingMaterialHandle)) != 0) {
        OpenMaterialPopup(context, state, pendingMaterialHandle);
    }

    if (hasValidEntity) {
        char nameBuffer[256] = {0};
        if (MCEEditorGetEntityName(context, selectedEntityId, nameBuffer, sizeof(nameBuffer)) <= 0) {
            strncpy(nameBuffer, "Entity", sizeof(nameBuffer) - 1);
        }
        const float addButtonWidth = ImGui::CalcTextSize(EditorIcons::Glyph(EditorIcons::Id::Plus)).x + ImGui::GetStyle().FramePadding.x * 2.0f;
        ImGui::SetNextItemWidth(std::max(120.0f, ImGui::GetContentRegionAvail().x - addButtonWidth - ImGui::GetStyle().ItemSpacing.x));
        if (runtimeLocked) {
            ImGui::BeginDisabled(true);
        }
        if (ImGui::InputText("##EntityName", nameBuffer, sizeof(nameBuffer))) {
            MCEEditorSetEntityName(context, selectedEntityId, nameBuffer);
        }
        if (runtimeLocked) {
            ImGui::EndDisabled();
            if (ImGui::IsItemHovered()) {
                ImGui::SetTooltip("Locked during Simulate/Play");
            }
        }
        ImGui::SameLine();
        if (runtimeLocked) {
            ImGui::BeginDisabled(true);
        }
        if (EditorUI::IconButton("inspector_add_component",
                                 EditorIcons::Glyph(EditorIcons::Id::Plus),
                                 "Add Component",
                                 false,
                                 false)) {
            ImGui::OpenPopup("AddComponentPopup");
        }
        if (runtimeLocked) {
            ImGui::EndDisabled();
            if (ImGui::IsItemHovered()) {
                ImGui::SetTooltip("Locked during Simulate/Play");
            }
        }
        ImGui::Spacing();
    }

    if (runtimeLocked) {
        ImGui::TextColored(ImVec4(0.95f, 0.7f, 0.2f, 1.0f), "Runtime Locked (Script Component remains editable in Play)");
        ImGui::Separator();
    }

    if (hasValidEntity && MCEEditorEntityHasComponent(context, selectedEntityId, ComponentReflectionProbe) != 0) {
        if (ImGui::CollapsingHeader("Reflection Probe Runtime", ImGuiTreeNodeFlags_DefaultOpen)) {
            int32_t runtimeStatus = -1;
            const bool hasRuntimeStatus = MCEEditorGetReflectionProbeRuntimeStatus(context, selectedEntityId, &runtimeStatus) != 0;
            const char *statusLabel = "Not built (enter Play to capture)";
            switch (runtimeStatus) {
            case 0: statusLabel = "Idle"; break;
            case 1: statusLabel = "Queued"; break;
            case 2: statusLabel = "Capturing"; break;
            case 3: statusLabel = "Filtering"; break;
            case 4: statusLabel = "Ready"; break;
            case 5: statusLabel = "Failed"; break;
            default: break;
            }
            if (hasRuntimeStatus) {
                ImGui::Text("Status: %s", statusLabel);
            } else {
                ImGui::TextDisabled("%s", statusLabel);
            }

            const bool canRebuildRuntime = isPlaying;
            if (!canRebuildRuntime) {
                ImGui::BeginDisabled(true);
            }
            if (ImGui::Button("Rebuild Probe")) {
                MCEEditorRequestReflectionProbeRebuild(context, selectedEntityId);
            }
            ImGui::SameLine();
            if (ImGui::Button("Rebuild All Probes")) {
                MCEEditorRequestAllReflectionProbeRebuilds(context);
            }
            if (!canRebuildRuntime) {
                ImGui::EndDisabled();
                if (ImGui::IsItemHovered()) {
                    ImGui::SetTooltip("Reflection probe rebuilds are queued on the runtime scene while Play is active.");
                }
            }
            ImGui::Separator();
        }
    }

    ImGui::BeginDisabled(runtimeLocked);

    if (selectedIds.size() > 1) {
        ImGui::Text("Multiple selection (%d)", static_cast<int>(selectedIds.size()));
        ImGui::Separator();

        bool allHaveTransform = true;
        for (const std::string &id : selectedIds) {
            if (MCEEditorEntityHasComponent(context, id.c_str(), ComponentTransform) == 0) {
                allHaveTransform = false;
                break;
            }
        }
        if (!allHaveTransform) {
            ImGui::TextUnformatted("Batch editing currently supports Transform only.");
            ImGui::EndDisabled();
            ImGui::PopStyleVar();
            ImGui::EndChild();
            EditorUI::EndPanel();
            return;
        }

        float px = 0, py = 0, pz = 0;
        float rx = 0, ry = 0, rz = 0;
        float sx = 1, sy = 1, sz = 1;
        if (MCEEditorGetTransform(context, selectedIds.front().c_str(), &px, &py, &pz, &rx, &ry, &rz, &sx, &sy, &sz) != 0) {
            float position[3] = {px, py, pz};
            float rotation[3] = {rx * kRadToDeg, ry * kRadToDeg, rz * kRadToDeg};
            float scale[3] = {sx, sy, sz};
            bool dirty = false;
            if (EditorUI::BeginPropertyTable("TransformPropsMulti")) {
                dirty |= EditorUI::PropertyVec3("Position",
                                               position,
                                               0.0f,
                                               EditorUIConstants::kPositionStep,
                                               0.0f,
                                               0.0f,
                                               "%.3f",
                                               false,
                                               true);
                dirty |= EditorUI::PropertyVec3("Rotation (deg)",
                                               rotation,
                                               0.0f,
                                               EditorUIConstants::kRotationStepDeg,
                                               EditorUIConstants::kRotationMinDeg,
                                               EditorUIConstants::kRotationMaxDeg,
                                               "%.2f",
                                               true,
                                               true);
                dirty |= EditorUI::PropertyVec3("Scale",
                                               scale,
                                               1.0f,
                                               EditorUIConstants::kScaleStep,
                                               0.0f,
                                               0.0f,
                                               "%.3f",
                                               false,
                                               true);
                EditorUI::EndPropertyTable();
            }
            if (dirty) {
                float rotationRad[3] = {rotation[0] * kDegToRad, rotation[1] * kDegToRad, rotation[2] * kDegToRad};
                for (const std::string &id : selectedIds) {
                    MCEEditorSetTransform(context, id.c_str(),
                                          position[0], position[1], position[2],
                                          rotationRad[0], rotationRad[1], rotationRad[2],
                                          scale[0], scale[1], scale[2]);
                }
            }
        }

        ImGui::EndDisabled();
        ImGui::PopStyleVar();
        ImGui::EndChild();
        EditorUI::EndPanel();
        return;
    }

    if (hasValidEntity) {
        char prefabHandle[64] = {0};
        char prefabPath[512] = {0};
        if (MCEEditorGetPrefabInstanceInfo(context,
                                           selectedEntityId,
                                           prefabHandle,
                                           sizeof(prefabHandle),
                                           prefabPath,
                                           sizeof(prefabPath)) != 0) {
            EditorUI::SectionHeader("Prefab");
            ImGui::TextWrapped("%s", prefabPath[0] != 0 ? prefabPath : prefabHandle);
            const char *applyTooltip = "Apply All: writes this instance's current component values into the prefab asset and refreshes all loaded instances.";
            const char *revertTooltip = "Revert All: discards this instance's overrides and rebuilds it from the prefab asset.";

            if (ImGui::Button("Apply to Prefab")) {
                MCEEditorApplyPrefabInstanceToAsset(context, selectedEntityId);
            }
            if (ImGui::IsItemHovered(ImGuiHoveredFlags_AllowWhenDisabled)) {
                ImGui::SetTooltip("%s", applyTooltip);
            }
            ImGui::SameLine();
            if (ImGui::Button("Revert")) {
                MCEEditorRevertPrefabInstance(context, selectedEntityId);
            }
            if (ImGui::IsItemHovered(ImGuiHoveredFlags_AllowWhenDisabled)) {
                ImGui::SetTooltip("%s", revertTooltip);
            }
            ImGui::Spacing();
        }
    }

    if (hasValidEntity && MCEEditorEntityHasComponent(context, selectedEntityId, ComponentTransform) != 0) {
        bool transformOpen = EditorUI::BeginSection(context, "Transform", "Inspector.Transform", true);
        if (ImGui::BeginPopupContextItem("TransformContext")) {
            if (ImGui::MenuItem("Reset")) {
                MCEEditorSetTransform(context, selectedEntityId, 0, 0, 0, 0, 0, 0, 1, 1, 1);
            }
            if (ImGui::MenuItem("Remove")) {
                MCEEditorRemoveComponent(context, selectedEntityId, ComponentTransform);
            }
            ImGui::EndPopup();
        }
        if (transformOpen) {
            float px = 0, py = 0, pz = 0;
            float rx = 0, ry = 0, rz = 0;
            float sx = 1, sy = 1, sz = 1;
            if (MCEEditorGetTransform(context, selectedEntityId, &px, &py, &pz, &rx, &ry, &rz, &sx, &sy, &sz) != 0) {
                float position[3] = {px, py, pz};
                float rotation[3] = {rx * kRadToDeg, ry * kRadToDeg, rz * kRadToDeg};
                float scale[3] = {sx, sy, sz};
                bool dirty = false;
                if (EditorUI::BeginPropertyTable("TransformProps")) {
                    EditorUI::SetNextPropertyInfoTooltip("Entity position in world space.\nUnits: meters.\nPerformance: none.\nPersistence: Scene.");
                    dirty |= EditorUI::PropertyVec3("Position",
                                                   position,
                                                   0.0f,
                                                   EditorUIConstants::kPositionStep,
                                                   0.0f,
                                                   0.0f,
                                                   "%.3f",
                                                   false,
                                                   true);
                    EditorUI::SetNextPropertyInfoTooltip("Entity Euler rotation.\nUnits: degrees.\nPerformance: none.\nPersistence: Scene.");
                    dirty |= EditorUI::PropertyVec3("Rotation (deg)",
                                                   rotation,
                                                   0.0f,
                                                   EditorUIConstants::kRotationStepDeg,
                                                   EditorUIConstants::kRotationMinDeg,
                                                   EditorUIConstants::kRotationMaxDeg,
                                                   "%.2f",
                                                   true,
                                                   true);
                    EditorUI::SetNextPropertyInfoTooltip("Entity local scale.\nUnits: scalar.\nPerformance: none.\nPersistence: Scene.");
                    dirty |= EditorUI::PropertyVec3("Scale",
                                                   scale,
                                                   1.0f,
                                                   EditorUIConstants::kScaleStep,
                                                   0.0f,
                                                   0.0f,
                                                   "%.3f",
                                                   false,
                                                   true);
                    EditorUI::EndPropertyTable();
                }
                if (dirty) {
                    float rotationRad[3] = {rotation[0] * kDegToRad, rotation[1] * kDegToRad, rotation[2] * kDegToRad};
                    MCEEditorSetTransform(context, selectedEntityId,
                                          position[0], position[1], position[2],
                                          rotationRad[0], rotationRad[1], rotationRad[2],
                                          scale[0], scale[1], scale[2]);
                }
            }
        }
    }

    const bool hasRigidbody = hasValidEntity && MCEEditorEntityHasComponent(context, selectedEntityId, ComponentRigidbody) != 0;
    const bool hasCollider = hasValidEntity && MCEEditorEntityHasComponent(context, selectedEntityId, ComponentCollider) != 0;

    if (hasRigidbody) {
        bool rigidbodyOpen = EditorUI::BeginSectionWithContext(context,
            "Rigidbody",
            "Inspector.Rigidbody",
            "RigidbodyContext",
            [&]() {
                if (ImGui::MenuItem("Remove")) {
                    MCEEditorRemoveComponent(context, selectedEntityId, ComponentRigidbody);
                }
            },
            true);
        if (rigidbodyOpen) {
            if (!hasCollider) {
                ImGui::TextColored(ImVec4(0.95f, 0.7f, 0.2f, 1.0f), "Requires a Collider component.");
            }
            if (isPlaying) {
                ImGui::TextColored(ImVec4(0.75f, 0.82f, 0.9f, 1.0f), "Changes apply next time you press Play.");
            }
            ImGui::BeginDisabled(!isPlaying || !hasCollider);
            if (ImGui::Button("Rebuild Body")) {
                if (isPlaying) {
                    MCEEditorRebuildPhysicsBody(context, selectedEntityId);
                }
            }
            ImGui::SameLine();
            EditorUI::InfoIconTooltip(isPlaying
                                      ? "Rebuilds the runtime physics body from current component values.\nUnits: N/A.\nPerformance: moderate one-shot rebuild.\nPersistence: runtime-only."
                                      : "Play mode required to rebuild runtime body.\nUnits: N/A.\nPersistence: N/A.");
            ImGui::EndDisabled();
            ImGui::Spacing();
            uint32_t enabled = 1;
            int32_t motionType = 1;
            float mass = 1.0f;
            float friction = 0.6f;
            float restitution = 0.0f;
            float linearDamping = 0.02f;
            float angularDamping = 0.2f;
            float gravityFactor = 1.0f;
            uint32_t allowSleeping = 1;
            uint32_t ccdEnabled = 0;
            int32_t collisionLayer = 0;
            uint32_t colliderEnabled = 1;
            int32_t colliderShape = 0;
            float boxX = 0.5f, boxY = 0.5f, boxZ = 0.5f;
            float sphereRadius = 0.5f;
            float capsuleHalfHeight = 0.5f;
            float capsuleRadius = 0.5f;
            float offsetX = 0.0f, offsetY = 0.0f, offsetZ = 0.0f;
            float rotX = 0.0f, rotY = 0.0f, rotZ = 0.0f;
            uint32_t isTrigger = 0;
            const bool hasColliderData = hasCollider && MCEEditorGetCollider(context, selectedEntityId,
                                     &colliderEnabled,
                                     &colliderShape,
                                     &boxX, &boxY, &boxZ,
                                     &sphereRadius,
                                     &capsuleHalfHeight,
                                     &capsuleRadius,
                                     &offsetX, &offsetY, &offsetZ,
                                     &rotX, &rotY, &rotZ,
                                     &isTrigger) != 0;
            if (MCEEditorGetRigidbody(context, selectedEntityId,
                                      &enabled,
                                      &motionType,
                                      &mass,
                                      &friction,
                                      &restitution,
                                      &linearDamping,
                                      &angularDamping,
                                      &gravityFactor,
                                      &allowSleeping,
                                      &ccdEnabled,
                                      &collisionLayer) != 0) {
                bool dirty = false;
                bool colliderDirty = false;
                bool allowSleepBool = allowSleeping != 0;
                bool ccdBool = ccdEnabled != 0;
                if (EditorUI::BeginPropertyTable("RigidbodyProps")) {
                    const char* typeItems[] = { "Static", "Dynamic", "Kinematic" };
                    int typeIndex = motionType;
                    EditorUI::SetNextPropertyInfoTooltip("Rigid body simulation mode.\nUnits: enum.\nPerformance: dynamic is highest cost.\nPersistence: Scene.");
                    if (EditorUI::PropertyCombo("Motion Type", &typeIndex, typeItems, IM_ARRAYSIZE(typeItems))) {
                        motionType = typeIndex;
                        dirty = true;
                    }
                    if (motionType == 1) {
                        EditorUI::SetNextPropertyInfoTooltip("Body mass.\nUnits: kilograms.\nPerformance: none.\nPersistence: Scene.");
                        if (EditorUI::PropertyFloat("Mass", &mass, 0.05f, 0.0f, 0.0f, "%.3f", false, true, 1.0f)) {
                            dirty = true;
                        }
                        EditorUI::SetNextPropertyInfoTooltip("Linear velocity damping.\nUnits: unitless.\nPerformance: low.\nPersistence: Scene.");
                        if (EditorUI::PropertyFloat("Linear Damping", &linearDamping, 0.01f, 0.0f, 1.0f, "%.3f", true, true, 0.02f)) {
                            dirty = true;
                        }
                        EditorUI::SetNextPropertyInfoTooltip("Angular velocity damping.\nUnits: unitless.\nPerformance: low.\nPersistence: Scene.");
                        if (EditorUI::PropertyFloat("Angular Damping", &angularDamping, 0.01f, 0.0f, 1.0f, "%.3f", true, true, 0.2f)) {
                            dirty = true;
                        }
                        if (EditorUI::PropertyFloat("Friction", &friction, 0.05f, 0.0f, 1.0f, "%.2f", true, true, 0.6f)) {
                            dirty = true;
                        }
                        if (EditorUI::PropertyFloat("Restitution", &restitution, 0.05f, 0.0f, 1.0f, "%.2f", true, true, 0.0f)) {
                            dirty = true;
                        }
                        if (EditorUI::PropertyBool("Allow Sleeping", &allowSleepBool)) {
                            allowSleeping = allowSleepBool ? 1 : 0;
                            dirty = true;
                        }
                        if (EditorUI::PropertyBool("Enable CCD", &ccdBool)) {
                            ccdEnabled = ccdBool ? 1 : 0;
                            dirty = true;
                        }
                    } else if (motionType == 0 && hasColliderData) {
                        bool triggerBool = isTrigger != 0;
                        if (EditorUI::PropertyBool("Is Trigger", &triggerBool)) {
                            isTrigger = triggerBool ? 1 : 0;
                            colliderDirty = true;
                        }
                    }
                    EditorUI::EndPropertyTable();
                }
                if (ImGui::CollapsingHeader("Advanced##Rigidbody")) {
                    bool enabledBool = enabled != 0;
                    if (EditorUI::BeginPropertyTable("RigidbodyAdvanced")) {
                        if (EditorUI::PropertyBool("Enabled", &enabledBool)) {
                            enabled = enabledBool ? 1 : 0;
                            dirty = true;
                        }
                        if (EditorUI::PropertyFloat("Gravity Factor", &gravityFactor, 0.05f, 0.0f, 5.0f, "%.2f", true, true, 1.0f)) {
                            dirty = true;
                        }
                        if (EditorUI::PropertyInt("Collision Layer", &collisionLayer, 0, 15)) {
                            dirty = true;
                        }
                        EditorUI::EndPropertyTable();
                    }
                }
                if (dirty) {
                    MCEEditorSetRigidbody(context, selectedEntityId,
                                          enabled,
                                          motionType,
                                          mass,
                                          friction,
                                          restitution,
                                          linearDamping,
                                          angularDamping,
                                          gravityFactor,
                                          allowSleeping,
                                          ccdEnabled,
                                          collisionLayer);
                }
                if (colliderDirty && hasColliderData) {
                    MCEEditorSetCollider(context, selectedEntityId,
                                         colliderEnabled,
                                         colliderShape,
                                         boxX, boxY, boxZ,
                                         sphereRadius,
                                         capsuleHalfHeight,
                                         capsuleRadius,
                                         offsetX, offsetY, offsetZ,
                                         rotX, rotY, rotZ,
                                         isTrigger);
                }
            }
        }
    }

    if (hasCollider) {
        bool colliderOpen = EditorUI::BeginSectionWithContext(context,
            "Colliders",
            "Inspector.Colliders",
            "ColliderContext",
            [&]() {
                if (ImGui::MenuItem("Remove Collider Component")) {
                    MCEEditorRemoveComponent(context, selectedEntityId, ComponentCollider);
                }
            },
            true);
        if (colliderOpen) {
            if (!hasRigidbody) {
                ImGui::TextColored(ImVec4(0.95f, 0.7f, 0.2f, 1.0f), "Requires a Rigidbody to simulate.");
            }
            const int32_t shapeCount = MCEEditorGetColliderShapeCount(context, selectedEntityId);
            if (ImGui::Button("+ Add Collider")) {
                MCEEditorAddColliderShape(context, selectedEntityId);
            }
            ImGui::Separator();
            const char* shapeItems[] = { "Box", "Sphere", "Capsule" };
            for (int32_t shapeIndex = 0; shapeIndex < shapeCount; ++shapeIndex) {
                ImGui::PushID(shapeIndex);
                uint32_t enabled = 1;
                int32_t shapeType = 0;
                float boxX = 0.5f, boxY = 0.5f, boxZ = 0.5f;
                float sphereRadius = 0.5f;
                float capsuleHalfHeight = 0.5f;
                float capsuleRadius = 0.5f;
                float offsetX = 0.0f, offsetY = 0.0f, offsetZ = 0.0f;
                float rotX = 0.0f, rotY = 0.0f, rotZ = 0.0f;
                uint32_t isTrigger = 0;
                uint32_t hasLayerOverride = 0;
                int32_t layerOverride = 0;
                if (MCEEditorGetColliderShape(context, selectedEntityId, shapeIndex,
                                              &enabled, &shapeType,
                                              &boxX, &boxY, &boxZ,
                                              &sphereRadius,
                                              &capsuleHalfHeight,
                                              &capsuleRadius,
                                              &offsetX, &offsetY, &offsetZ,
                                              &rotX, &rotY, &rotZ,
                                              &isTrigger,
                                              &hasLayerOverride,
                                              &layerOverride) == 0) {
                    ImGui::PopID();
                    continue;
                }

                bool open = ImGui::CollapsingHeader((std::string("Collider ") + std::to_string(shapeIndex)).c_str(), ImGuiTreeNodeFlags_DefaultOpen);
                if (open) {
                    if (ImGui::Button("Remove Collider")) {
                        MCEEditorRemoveColliderShape(context, selectedEntityId, shapeIndex);
                        ImGui::PopID();
                        continue;
                    }
                    bool dirty = false;
                    int shapeTypeIndex = shapeType;
                    float offset[3] = { offsetX, offsetY, offsetZ };
                    float rotationDeg[3] = { rotX * kRadToDeg, rotY * kRadToDeg, rotZ * kRadToDeg };
                    bool triggerBool = isTrigger != 0;
                    bool enabledBool = enabled != 0;
                    bool overrideBool = hasLayerOverride != 0;

                    if (EditorUI::BeginPropertyTable("ColliderShapeProps")) {
                        if (EditorUI::PropertyBool("Enabled", &enabledBool)) {
                            enabled = enabledBool ? 1 : 0;
                            dirty = true;
                        }
                        if (EditorUI::PropertyCombo("Shape", &shapeTypeIndex, shapeItems, IM_ARRAYSIZE(shapeItems))) {
                            shapeType = shapeTypeIndex;
                            dirty = true;
                        }
                        if (shapeType == 0) {
                            float extents[3] = { boxX, boxY, boxZ };
                            if (EditorUI::PropertyVec3("Half Extents", extents, 0.5f, 0.05f, 0.0f, 0.0f, "%.3f", false, true)) {
                                boxX = extents[0];
                                boxY = extents[1];
                                boxZ = extents[2];
                                dirty = true;
                            }
                        } else if (shapeType == 1) {
                            if (EditorUI::PropertyFloat("Radius", &sphereRadius, 0.05f, 0.0f, 0.0f, "%.3f", false, true, 0.5f)) {
                                dirty = true;
                            }
                        } else {
                            if (EditorUI::PropertyFloat("Radius", &capsuleRadius, 0.05f, 0.0f, 0.0f, "%.3f", false, true, 0.5f)) {
                                dirty = true;
                            }
                            if (EditorUI::PropertyFloat("Half Height", &capsuleHalfHeight, 0.05f, 0.0f, 0.0f, "%.3f", false, true, 0.5f)) {
                                dirty = true;
                            }
                        }
                        if (EditorUI::PropertyVec3("Offset Position", offset, 0.0f, 0.05f, 0.0f, 0.0f, "%.3f", false, true)) {
                            offsetX = offset[0];
                            offsetY = offset[1];
                            offsetZ = offset[2];
                            dirty = true;
                        }
                        if (EditorUI::PropertyVec3("Offset Rotation (deg)", rotationDeg, 0.0f, EditorUIConstants::kRotationStepDeg,
                                                   EditorUIConstants::kRotationMinDeg, EditorUIConstants::kRotationMaxDeg, "%.2f", true, true)) {
                            rotX = rotationDeg[0] * kDegToRad;
                            rotY = rotationDeg[1] * kDegToRad;
                            rotZ = rotationDeg[2] * kDegToRad;
                            dirty = true;
                        }
                        if (EditorUI::PropertyBool("Is Trigger", &triggerBool)) {
                            isTrigger = triggerBool ? 1 : 0;
                            dirty = true;
                        }
                        if (EditorUI::PropertyBool("Override Layer", &overrideBool)) {
                            hasLayerOverride = overrideBool ? 1 : 0;
                            dirty = true;
                        }
                        if (overrideBool && EditorUI::PropertyInt("Layer", &layerOverride, 0, 15)) {
                            dirty = true;
                        }
                        EditorUI::EndPropertyTable();
                    }
                    if (dirty) {
                        MCEEditorSetColliderShape(context, selectedEntityId, shapeIndex,
                                                  enabled, shapeType,
                                                  boxX, boxY, boxZ,
                                                  sphereRadius,
                                                  capsuleHalfHeight,
                                                  capsuleRadius,
                                                  offsetX, offsetY, offsetZ,
                                                  rotX, rotY, rotZ,
                                                  isTrigger,
                                                  hasLayerOverride,
                                                  layerOverride);
                    }
                }
                ImGui::PopID();
            }
        }
    }

    const bool hasCamera = hasValidEntity && MCEEditorEntityHasComponent(context, selectedEntityId, ComponentCamera) != 0;
    if (hasCamera) {
        bool cameraOpen = EditorUI::BeginSectionWithContext(context, 
            "Camera",
            "Inspector.Camera",
            "CameraContext",
            [&]() {
                if (ImGui::MenuItem("Remove")) {
                    MCEEditorRemoveComponent(context, selectedEntityId, ComponentCamera);
                }
            },
            true);
        if (cameraOpen) {
            int32_t projectionType = 0;
            float fovDegrees = 45.0f;
            float orthoSize = 10.0f;
            float nearPlane = 0.1f;
            float farPlane = 1000.0f;
            uint32_t isPrimary = 0;
            uint32_t isEditor = 0;
            if (MCEEditorGetCamera(context, selectedEntityId,
                                   &projectionType,
                                   &fovDegrees,
                                   &orthoSize,
                                   &nearPlane,
                                   &farPlane,
                                   &isPrimary,
                                   &isEditor) != 0) {
                const char *projectionItems[] = {"Perspective", "Orthographic"};
                int projectionIndex = projectionType;
                bool dirty = false;
                bool primaryDirty = false;
                uint32_t autoExposureEnabled = 0;
                float exposureEV = 0.0f;
                float exposureCompensation = 0.0f;
                float autoExposureMin = 0.03f;
                float autoExposureMax = 8.0f;
                float adaptationSpeed = 2.0f;
                bool hasExposureSettings = MCEEditorGetCameraExposure(context,
                                                                      selectedEntityId,
                                                                      &autoExposureEnabled,
                                                                      &exposureEV,
                                                                      &exposureCompensation,
                                                                      &autoExposureMin,
                                                                      &autoExposureMax,
                                                                      &adaptationSpeed) != 0;
                if (EditorUI::BeginPropertyTable("CameraProps")) {
                    EditorUI::SetNextPropertyInfoTooltip("Camera projection model.\nUnits: enum.\nPerformance: similar.\nPersistence: Scene.");
                    dirty |= EditorUI::PropertyCombo("Projection", &projectionIndex, projectionItems, 2);
                    if (projectionIndex == 0) {
                        EditorUI::SetNextPropertyInfoTooltip("Perspective field of view.\nUnits: degrees.\nPerformance: none.\nPersistence: Scene.");
                        dirty |= EditorUI::PropertyFloat("FOV (deg)", &fovDegrees, 0.1f, 1.0f, 179.0f, "%.1f", true);
                    } else {
                        EditorUI::SetNextPropertyInfoTooltip("Orthographic vertical size.\nUnits: world units.\nPerformance: none.\nPersistence: Scene.");
                        dirty |= EditorUI::PropertyFloat("Ortho Size", &orthoSize, 0.05f, 0.01f, 10000.0f, "%.2f", true);
                    }
                    EditorUI::SetNextPropertyInfoTooltip("Near clipping plane.\nUnits: meters.\nPerformance: precision-sensitive.\nPersistence: Scene.");
                    dirty |= EditorUI::PropertyFloat("Near", &nearPlane, 0.01f, 0.01f, 10000.0f, "%.3f", true);
                    EditorUI::SetNextPropertyInfoTooltip("Far clipping plane.\nUnits: meters.\nPerformance: precision-sensitive.\nPersistence: Scene.");
                    dirty |= EditorUI::PropertyFloat("Far", &farPlane, 1.0f, 0.1f, 100000.0f, "%.1f", true);
                    bool primary = isPrimary != 0;
                    if (isEditor != 0) {
                        ImGui::BeginDisabled();
                    }
                    primaryDirty = EditorUI::PropertyBool("Primary", &primary);
                    if (isEditor != 0) {
                        ImGui::EndDisabled();
                    }
                    if (hasExposureSettings) {
                        const bool editorCamera = isEditor != 0;
                        const char *exposureModeItems[] = {"Manual (Phase 1)"};
                        int exposureMode = 0;
                        bool exposureDirty = false;

                        EditorUI::SetNextPropertyInfoTooltip("Auto exposure is unavailable pending histogram and temporal-adaptation reconstruction. Phase 1 rendering is deterministic and manual-only.");
                        ImGui::BeginDisabled(true);
                        EditorUI::PropertyCombo("Exposure Mode", &exposureMode, exposureModeItems, 1);
                        ImGui::EndDisabled();

                        EditorUI::SetNextPropertyInfoTooltip(editorCamera
                            ? "Stable editor viewport exposure in stops. EV 0 is unity; +1 doubles and -1 halves final-stage exposure.\nPersistence: Scene."
                            : "Manual final-stage exposure in stops. EV 0 is unity; +1 doubles and -1 halves exposure.\nPersistence: Scene.");
                        exposureDirty |= EditorUI::PropertyFloat("Exposure (EV)", &exposureEV, 0.1f, -16.0f, 16.0f, "%+.2f EV", true);

                        if (exposureDirty) {
                            autoExposureEnabled = 0;
                            MCEEditorSetCameraExposure(context,
                                                       selectedEntityId,
                                                       autoExposureEnabled,
                                                       exposureEV,
                                                       exposureCompensation,
                                                       autoExposureMin,
                                                       autoExposureMax,
                                                       adaptationSpeed);
                        }
                    }
                    EditorUI::EndPropertyTable();

                    if (dirty || primaryDirty) {
                        const uint32_t primaryValue = (primary ? 1u : 0u);
                        MCEEditorSetCamera(context, selectedEntityId,
                                           projectionIndex,
                                           fovDegrees,
                                           orthoSize,
                                           nearPlane,
                                           farPlane,
                                           primaryValue);
                    }
                }
                if (isEditor != 0) {
                    ImGui::TextDisabled("Editor Camera");
                    ImGui::TextDisabled("Editor camera exposure settings persist with the scene.");
                }
            }
        }
    }

    if (runtimeLocked) {
        ImGui::EndDisabled();
    }

    const bool hasScript = hasValidEntity && MCEEditorEntityHasComponent(context, selectedEntityId, ComponentScript) != 0;
    if (hasScript) {
        bool scriptOpen = EditorUI::BeginSectionWithContext(context,
            "Script",
            "Inspector.Script",
            "ScriptContext",
            [&]() {
                if (ImGui::MenuItem("Remove")) {
                    MCEEditorRemoveComponent(context, selectedEntityId, ComponentScript);
                }
            },
            true);
        if (scriptOpen) {
            uint32_t enabled = 1;
            char scriptHandle[64] = {0};
            char typeName[256] = {0};
            uint32_t fieldDataVersion = 1;
            if (MCEEditorGetScript(context,
                                   selectedEntityId,
                                   &enabled,
                                   scriptHandle, sizeof(scriptHandle),
                                   typeName, sizeof(typeName),
                                   nullptr,
                                   &fieldDataVersion) != 0) {
                bool dirty = false;
                bool enabledBool = enabled != 0;
                if (EditorUI::BeginPropertyTable("ScriptProps")) {
                    dirty |= EditorUI::PropertyBool("Enabled", &enabledBool);
                    if (DrawScriptHandleRow(context, state, "Script Asset", scriptHandle, sizeof(scriptHandle), "MCE_ASSET_SCRIPT", selectedEntityId)) {
                        dirty = true;
                    }
                    int32_t runtimeState = 0;
                    uint32_t hasInstance = 0;
                    char runtimeError[2048] = {0};
                    MCEEditorGetScriptRuntimeStatus(context,
                                                    selectedEntityId,
                                                    &runtimeState,
                                                    &hasInstance,
                                                    runtimeError, sizeof(runtimeError));
                    const char *statusLabel = "Disabled";
                    if (enabledBool) {
                        if (runtimeState == 1) {
                            statusLabel = "Loaded";
                        } else if (runtimeState == 2) {
                            statusLabel = "Error";
                        } else {
                            statusLabel = "Disabled";
                        }
                    }
                    EditorUI::PropertyLabel("Status");
                    ImGui::Text("%s%s", statusLabel, hasInstance != 0 ? " (Instance Active)" : "");
                    EditorUI::EndPropertyTable();
                    if (ImGui::CollapsingHeader("Advanced##Script")) {
                        if (EditorUI::BeginPropertyTable("ScriptAdvancedProps")) {
                            EditorUI::PropertyLabel("Type Name");
                            ImGui::InputText("##ScriptTypeName", typeName, sizeof(typeName), ImGuiInputTextFlags_ReadOnly);
                            EditorUI::PropertyLabel("Field Data Version");
                            ImGui::Text("v%u", fieldDataVersion);
                            EditorUI::EndPropertyTable();
                        }
                    }
                    if (runtimeError[0] != 0) {
                        ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(0.95f, 0.45f, 0.45f, 1.0f));
                        ImGui::PushTextWrapPos(0.0f);
                        ImGui::TextUnformatted(runtimeError);
                        ImGui::PopTextWrapPos();
                        ImGui::PopStyleColor();
                    }
                }
                const int32_t scriptFieldCount = MCEEditorGetScriptFieldCount(context, selectedEntityId);
                if (scriptFieldCount > 0) {
                    ImGui::Separator();
                    ImGui::TextDisabled("Exposed Fields");
                    if (EditorUI::BeginPropertyTable("ScriptFieldProps")) {
                        static char entityPickerField[128] = {0};
                        static char entityPickerFilter[128] = {0};
                        static bool openEntityPicker = false;
                        static char prefabPickerField[128] = {0};
                        static char prefabPickerFilter[128] = {0};
                        static bool openPrefabPicker = false;

                        for (int32_t fieldIndex = 0; fieldIndex < scriptFieldCount; ++fieldIndex) {
                            char fieldName[128] = {0};
                            int32_t fieldType = 0;
                            int32_t intValue = 0;
                            float numberValue = 0.0f;
                            uint32_t boolValue = 0;
                            char stringValue[512] = {0};
                            float vecX = 0.0f, vecY = 0.0f, vecZ = 0.0f;
                            char entityValue[64] = {0};
                            char prefabValue[64] = {0};
                            uint32_t hasMin = 0, hasMax = 0, hasStep = 0, isMissingReference = 0;
                            float minValue = 0.0f, maxValue = 0.0f, stepValue = 0.1f;
                            char tooltip[512] = {0};
                            if (MCEEditorGetScriptFieldAt(context,
                                                          selectedEntityId,
                                                          fieldIndex,
                                                          fieldName, sizeof(fieldName),
                                                          &fieldType,
                                                          &intValue,
                                                          &numberValue,
                                                          &boolValue,
                                                          stringValue, sizeof(stringValue),
                                                          &vecX, &vecY, &vecZ,
                                                          entityValue, sizeof(entityValue),
                                                          prefabValue, sizeof(prefabValue),
                                                          &hasMin, &minValue,
                                                          &hasMax, &maxValue,
                                                          &hasStep, &stepValue,
                                                          tooltip, sizeof(tooltip),
                                                          &isMissingReference) == 0) {
                                continue;
                            }

                            bool fieldDirty = false;
                            if (tooltip[0] != 0) {
                                EditorUI::SetNextPropertyInfoTooltip(tooltip);
                            }
                            EditorUI::PropertyLabel(fieldName);
                            ImGui::PushID(fieldName);
                            switch (fieldType) {
                                case 0: {
                                    bool check = boolValue != 0;
                                    fieldDirty = ImGui::Checkbox("##ScriptFieldBool", &check);
                                    boolValue = check ? 1u : 0u;
                                    break;
                                }
                                case 1:
                                    fieldDirty = ImGui::DragInt("##ScriptFieldInt", &intValue, hasStep ? stepValue : 1.0f,
                                                                hasMin ? static_cast<int>(minValue) : INT32_MIN,
                                                                hasMax ? static_cast<int>(maxValue) : INT32_MAX);
                                    break;
                                case 2:
                                    fieldDirty = ImGui::DragFloat("##ScriptFieldFloat", &numberValue, hasStep ? stepValue : 0.1f,
                                                                  hasMin ? minValue : -FLT_MAX,
                                                                  hasMax ? maxValue : FLT_MAX);
                                    break;
                                case 3: {
                                    float vec[2] = {vecX, vecY};
                                    fieldDirty = ImGui::DragFloat2("##ScriptFieldVec2", vec, hasStep ? stepValue : 0.05f);
                                    vecX = vec[0];
                                    vecY = vec[1];
                                    break;
                                }
                                case 4: {
                                    float vec[3] = {vecX, vecY, vecZ};
                                    fieldDirty = ImGui::DragFloat3("##ScriptFieldVec3", vec, hasStep ? stepValue : 0.05f);
                                    vecX = vec[0];
                                    vecY = vec[1];
                                    vecZ = vec[2];
                                    break;
                                }
                                case 5: {
                                    float color[3] = {vecX, vecY, vecZ};
                                    fieldDirty = ImGui::ColorEdit3("##ScriptFieldColor3", color, ImGuiColorEditFlags_NoInputs);
                                    vecX = color[0];
                                    vecY = color[1];
                                    vecZ = color[2];
                                    break;
                                }
                                case 6:
                                    fieldDirty = ImGui::InputText("##ScriptFieldString", stringValue, sizeof(stringValue));
                                    break;
                                case 7: {
                                    char entityName[128] = {0};
                                    const bool hasEntity = entityValue[0] != 0;
                                    const bool entityExists = hasEntity && MCEEditorEntityExists(context, entityValue) != 0;
                                    if (hasEntity && entityExists) {
                                        if (MCEEditorGetEntityName(context, entityValue, entityName, sizeof(entityName)) <= 0) {
                                            strncpy(entityName, entityValue, sizeof(entityName) - 1);
                                        }
                                    } else if (hasEntity) {
                                        strncpy(entityName, "Missing Entity", sizeof(entityName) - 1);
                                    } else {
                                        strncpy(entityName, "None", sizeof(entityName) - 1);
                                    }
                                    ImGui::Button(entityName, ImVec2(ImGui::GetContentRegionAvail().x - 110.0f, 0));
                                    if (ImGui::BeginDragDropTarget()) {
                                        if (const ImGuiPayload* payload = ImGui::AcceptDragDropPayload("MCE_SCENE_ENTITY_IDS")) {
                                            const char *csv = static_cast<const char *>(payload->Data);
                                            char local[64] = {0};
                                            size_t i = 0;
                                            while (csv[i] != 0 && csv[i] != ',' && i < sizeof(local) - 1) {
                                                local[i] = csv[i];
                                                ++i;
                                            }
                                            local[i] = 0;
                                            strncpy(entityValue, local, sizeof(entityValue) - 1);
                                            fieldDirty = true;
                                        }
                                        ImGui::EndDragDropTarget();
                                    }
                                    ImGui::SameLine();
                                    if (ImGui::Button("Pick")) {
                                        strncpy(entityPickerField, fieldName, sizeof(entityPickerField) - 1);
                                        entityPickerFilter[0] = 0;
                                        openEntityPicker = true;
                                    }
                                    ImGui::SameLine();
                                    if (ImGui::Button("X")) {
                                        entityValue[0] = 0;
                                        fieldDirty = true;
                                    }
                                    if (isMissingReference != 0) {
                                        ImGui::TextDisabled("Missing");
                                    }
                                    break;
                                }
                                case 8: {
                                    char prefabName[128] = {0};
                                    if (prefabValue[0] != 0) {
                                        GetAssetName(context, prefabValue, prefabName, sizeof(prefabName));
                                    } else {
                                        strncpy(prefabName, "None", sizeof(prefabName) - 1);
                                    }
                                    ImGui::Button(prefabName, ImVec2(ImGui::GetContentRegionAvail().x - 110.0f, 0));
                                    if (ImGui::BeginDragDropTarget()) {
                                        if (const ImGuiPayload* payload = ImGui::AcceptDragDropPayload("MCE_ASSET_PREFAB")) {
                                            const char *payloadText = static_cast<const char *>(payload->Data);
                                            strncpy(prefabValue, payloadText, sizeof(prefabValue) - 1);
                                            fieldDirty = true;
                                        }
                                        ImGui::EndDragDropTarget();
                                    }
                                    ImGui::SameLine();
                                    if (ImGui::Button("Pick")) {
                                        strncpy(prefabPickerField, fieldName, sizeof(prefabPickerField) - 1);
                                        prefabPickerFilter[0] = 0;
                                        openPrefabPicker = true;
                                    }
                                    ImGui::SameLine();
                                    if (ImGui::Button("X")) {
                                        prefabValue[0] = 0;
                                        fieldDirty = true;
                                    }
                                    if (isMissingReference != 0) {
                                        ImGui::TextDisabled("Missing");
                                    }
                                    break;
                                }
                                default:
                                    ImGui::TextDisabled("Unsupported");
                                    break;
                            }
                            ImGui::PopID();
                            if (fieldDirty) {
                                MCEEditorSetScriptField(context,
                                                        selectedEntityId,
                                                        fieldName,
                                                        fieldType,
                                                        intValue,
                                                        numberValue,
                                                        boolValue,
                                                        stringValue,
                                                        vecX, vecY, vecZ,
                                                        entityValue,
                                                        prefabValue);
                            }
                        }
                        EditorUI::EndPropertyTable();

                        if (openEntityPicker) {
                            ImGui::OpenPopup("ScriptEntityPicker");
                            openEntityPicker = false;
                        }
                        if (ImGui::BeginPopupModal("ScriptEntityPicker", nullptr, ImGuiWindowFlags_AlwaysAutoResize)) {
                            ImGui::InputTextWithHint("##ScriptEntityFieldFilter", "Search entities...", entityPickerFilter, sizeof(entityPickerFilter));
                            ImGui::Separator();
                            const std::string filterText = EditorUI::ToLower(std::string(entityPickerFilter));
                            const int32_t entityCount = MCEEditorGetEntityCount(context);
                            for (int32_t i = 0; i < entityCount; ++i) {
                                char idBuffer[64] = {0};
                                char nameBuffer[256] = {0};
                                if (MCEEditorGetEntityIdAt(context, i, idBuffer, sizeof(idBuffer)) <= 0) { continue; }
                                MCEEditorGetEntityName(context, idBuffer, nameBuffer, sizeof(nameBuffer));
                                std::string display = nameBuffer[0] != 0 ? nameBuffer : idBuffer;
                                if (!filterText.empty() && EditorUI::ToLower(display).find(filterText) == std::string::npos) {
                                    continue;
                                }
                                std::string selectableLabel = display + "##" + std::string(idBuffer);
                                if (ImGui::Selectable(selectableLabel.c_str())) {
                                    MCEEditorSetScriptField(context,
                                                            selectedEntityId,
                                                            entityPickerField,
                                                            7,
                                                            0,
                                                            0,
                                                            0,
                                                            "",
                                                            0, 0, 0,
                                                            idBuffer,
                                                            "");
                                    ImGui::CloseCurrentPopup();
                                }
                            }
                            if (ImGui::Button("Close")) {
                                ImGui::CloseCurrentPopup();
                            }
                            ImGui::EndPopup();
                        }

                        if (openPrefabPicker) {
                            ImGui::OpenPopup("ScriptPrefabPicker");
                            openPrefabPicker = false;
                        }
                        if (ImGui::BeginPopupModal("ScriptPrefabPicker", nullptr, ImGuiWindowFlags_AlwaysAutoResize)) {
                            ImGui::InputTextWithHint("##ScriptPrefabFieldFilter", "Search prefabs...", prefabPickerFilter, sizeof(prefabPickerFilter));
                            ImGui::Separator();
                            std::vector<AssetOption> options;
                            LoadPrefabOptions(context, options);
                            const std::string filterText = EditorUI::ToLower(std::string(prefabPickerFilter));
                            for (const auto &option : options) {
                                if (!filterText.empty() && EditorUI::ToLower(option.name).find(filterText) == std::string::npos) {
                                    continue;
                                }
                                if (ImGui::Selectable(option.name.c_str())) {
                                    MCEEditorSetScriptField(context,
                                                            selectedEntityId,
                                                            prefabPickerField,
                                                            8,
                                                            0,
                                                            0,
                                                            0,
                                                            "",
                                                            0, 0, 0,
                                                            "",
                                                            option.handle.c_str());
                                    ImGui::CloseCurrentPopup();
                                }
                            }
                            if (ImGui::Button("Close")) {
                                ImGui::CloseCurrentPopup();
                            }
                            ImGui::EndPopup();
                        }
                    }
                } else {
                    ImGui::TextDisabled("This script has no exposed fields. Add <Type>.Fields = {...} to expose parameters.");
                }
                if (ImGui::Button("Clear Field Blob")) {
                    MCEEditorClearScriptFieldData(context, selectedEntityId);
                }
                ImGui::SameLine();
                if (ImGui::Button("Reset to Defaults")) {
                    MCEEditorResetScriptFieldsToDefaults(context, selectedEntityId);
                }
                ImGui::SameLine();
                ImGui::TextDisabled("Fields");
                if (isPlaying) {
                    ImGui::SameLine();
                    if (ImGui::Button("Reload Script")) {
                        MCEEditorReloadScriptInstance(context, selectedEntityId);
                    }
                }
                if (isPlaying) {
                    ImGui::TextDisabled("Changing script asset in Play reinstantiates immediately.");
                }
                if (dirty) {
                    MCEEditorSetScript(context,
                                       selectedEntityId,
                                       enabledBool ? 1u : 0u,
                                       scriptHandle,
                                       typeName,
                                       1);
                }
            }
        }
    }

    const bool hasCharacterController = hasValidEntity && MCEEditorEntityHasComponent(context, selectedEntityId, ComponentCharacterController) != 0;
    if (hasCharacterController) {
        bool controllerOpen = EditorUI::BeginSectionWithContext(context,
            "Character Controller",
            "Inspector.CharacterController",
            "CharacterControllerContext",
            [&]() {
                if (ImGui::MenuItem("Remove")) {
                    MCEEditorRemoveComponent(context, selectedEntityId, ComponentCharacterController);
                }
            },
            true);
        if (controllerOpen) {
            uint32_t enabled = 1;
            float height = 1.8f;
            float radius = 0.35f;
            float stepOffset = 0.25f;
            float moveSpeed = 4.0f;
            float sprintMultiplier = 1.5f;
            float jumpSpeed = 5.5f;
            uint32_t useGravityOverride = 0;
            float gravity = -9.81f;
            float maxSlope = 45.0f;
            float pushStrength = 100.0f;
            float airControl = 0.35f;
            float lookSensitivity = 0.01f;
            float minPitchDegrees = -80.0f;
            float maxPitchDegrees = 80.0f;
            uint32_t grounded = 0;
            char visualEntityId[64] = {0};
            char cameraPivotEntityId[64] = {0};

            if (MCEEditorGetCharacterController(context,
                                                selectedEntityId,
                                                &enabled,
                                                &height,
                                                &radius,
                                                &stepOffset,
                                                &moveSpeed,
                                                &sprintMultiplier,
                                                &jumpSpeed,
                                                &useGravityOverride,
                                                &gravity,
                                                &maxSlope,
                                                &pushStrength,
                                                &airControl,
                                                &lookSensitivity,
                                                &minPitchDegrees,
                                                &maxPitchDegrees,
                                                nullptr,
                                                &grounded,
                                                nullptr,
                                                nullptr,
                                                nullptr,
                                                nullptr,
                                                nullptr) != 0) {
                MCEEditorGetCharacterControllerEntityRefs(context,
                                                          selectedEntityId,
                                                          visualEntityId,
                                                          static_cast<int32_t>(sizeof(visualEntityId)),
                                                          cameraPivotEntityId,
                                                          static_cast<int32_t>(sizeof(cameraPivotEntityId)));
                ImGui::TextDisabled("Uses Jolt CharacterVirtual.");
                ImGui::TextDisabled("Mode: Play only");
                if (hasRigidbody) {
                    ImGui::TextColored(ImVec4(0.95f, 0.55f, 0.2f, 1.0f), "Rigidbody is optional; CharacterVirtual owns movement.");
                    if (!isPlaying && ImGui::Button("Remove Rigidbody")) {
                        MCEEditorCharacterControllerRemoveRigidbody(context, selectedEntityId);
                    }
                }

                if (!isPlaying) {
                    if (ImGui::Button("Create Recommended Hierarchy")) {
                        MCEEditorCharacterControllerCreateRecommendedHierarchy(context, selectedEntityId, 1);
                    }
                    ImGui::SameLine();
                    ImGui::TextDisabled("(?)");
                    if (ImGui::IsItemHovered(ImGuiHoveredFlags_DelayShort)) {
                        ImGui::SetTooltip("Creates/binds children: Visual, CameraPivot, and Camera. Edit mode only.");
                    }
                }

                auto parentMatches = [&](const char *childId, const char *expectedParentId) -> bool {
                    if (childId == nullptr || childId[0] == 0 || expectedParentId == nullptr || expectedParentId[0] == 0) {
                        return false;
                    }
                    char parentBuffer[64] = {0};
                    if (MCEEditorGetParentEntityId(context, childId, parentBuffer, static_cast<int32_t>(sizeof(parentBuffer))) <= 0) {
                        return false;
                    }
                    return strcmp(parentBuffer, expectedParentId) == 0;
                };

                auto pivotHasCameraChild = [&]() -> bool {
                    if (cameraPivotEntityId[0] == 0 || MCEEditorEntityExists(context, cameraPivotEntityId) == 0) {
                        return false;
                    }
                    const int32_t childCount = MCEEditorGetChildEntityCount(context, cameraPivotEntityId);
                    for (int32_t childIndex = 0; childIndex < childCount; ++childIndex) {
                        char childId[64] = {0};
                        if (MCEEditorGetChildEntityIdAt(context,
                                                        cameraPivotEntityId,
                                                        childIndex,
                                                        childId,
                                                        static_cast<int32_t>(sizeof(childId))) <= 0) {
                            continue;
                        }
                        if (MCEEditorEntityHasComponent(context, childId, ComponentCamera) != 0) {
                            return true;
                        }
                    }
                    return false;
                };

                const bool visualAssigned = visualEntityId[0] != 0 && MCEEditorEntityExists(context, visualEntityId) != 0;
                const bool pivotAssigned = cameraPivotEntityId[0] != 0 && MCEEditorEntityExists(context, cameraPivotEntityId) != 0;
                const bool visualIsChildOfRoot = parentMatches(visualEntityId, selectedEntityId);
                const bool pivotIsChildOfRoot = parentMatches(cameraPivotEntityId, selectedEntityId);
                const bool cameraUnderPivot = pivotHasCameraChild();
                const bool characterActive = isPlaying && enabled != 0;

                ImGui::Spacing();
                ImGui::BeginChild("CharacterControllerSetupChecklist", ImVec2(0.0f, 138.0f), true);
                ImGui::Text("Setup Checklist");
                ImGui::Separator();
                ImGui::BulletText("Required: Character Controller component on root entity");
                ImGui::BulletText("Required: Camera Pivot reference if scripts drive look");
                ImGui::BulletText("Optional: Visual child reference for model subtree interpolation");
                ImGui::BulletText("Optional: Rigidbody (collision layer source only)");
                ImGui::Separator();
                ImGui::Text("CharacterVirtual: %s", characterActive ? "Active (Play)" : "Inactive");
                ImGui::Text("Grounded: %s", isPlaying ? (grounded != 0 ? "true" : "false") : "Play only");
                ImGui::Text("Camera Pivot: %s", pivotAssigned ? "Assigned" : "Missing");
                ImGui::Text("Visual Child: %s", visualAssigned ? "Assigned" : "Not set");
                ImGui::Text("Camera child under pivot: %s", cameraUnderPivot ? "Yes" : "No");
                ImGui::EndChild();

                if (!visualAssigned) {
                    ImGui::TextColored(ImVec4(0.95f, 0.55f, 0.2f, 1.0f), "Warning: Visual entity reference is not set (optional).");
                }
                if (!pivotAssigned) {
                    ImGui::TextColored(ImVec4(0.95f, 0.55f, 0.2f, 1.0f), "Warning: CameraPivot reference is not set (optional).");
                }
                if (visualAssigned && !visualIsChildOfRoot) {
                    ImGui::TextColored(ImVec4(0.95f, 0.55f, 0.2f, 1.0f), "Warning: Visual entity should be a direct child of this root.");
                }
                if (pivotAssigned && !pivotIsChildOfRoot) {
                    ImGui::TextColored(ImVec4(0.95f, 0.55f, 0.2f, 1.0f), "Warning: CameraPivot should be a direct child of this root.");
                }
                if (pivotAssigned && !cameraUnderPivot) {
                    ImGui::TextColored(ImVec4(0.95f, 0.55f, 0.2f, 1.0f), "Warning: CameraPivot has no camera child.");
                }

                bool dirty = false;
                bool refsDirty = false;
                bool enabledBool = enabled != 0;
                bool gravityOverrideEnabled = useGravityOverride != 0;
                static char ccVisualFilter[128] = {0};
                static char ccCameraFilter[128] = {0};
                static bool openVisualPicker = false;
                static bool openCameraPicker = false;

                auto drawEntityRefRow = [&](const char *label, char *valueBuffer, bool isVisualPicker) {
                    EditorUI::PropertyLabel(label);
                    char displayName[128] = {0};
                    if (valueBuffer[0] != 0 && MCEEditorEntityExists(context, valueBuffer) != 0) {
                        if (MCEEditorGetEntityName(context, valueBuffer, displayName, sizeof(displayName)) == 0) {
                            strncpy(displayName, valueBuffer, sizeof(displayName) - 1);
                        }
                    } else if (valueBuffer[0] != 0) {
                        strncpy(displayName, "Missing Entity", sizeof(displayName) - 1);
                    } else {
                        strncpy(displayName, "None", sizeof(displayName) - 1);
                    }
                    ImGui::PushID(label);
                    ImGui::Button(displayName, ImVec2(ImGui::GetContentRegionAvail().x - 120.0f, 0));
                    if (ImGui::BeginDragDropTarget()) {
                        if (const ImGuiPayload* payload = ImGui::AcceptDragDropPayload("MCE_SCENE_ENTITY_IDS")) {
                            const char *csv = static_cast<const char *>(payload->Data);
                            char local[64] = {0};
                            size_t i = 0;
                            while (csv[i] != 0 && csv[i] != ',' && i < sizeof(local) - 1) {
                                local[i] = csv[i];
                                ++i;
                            }
                            local[i] = 0;
                            strncpy(valueBuffer, local, 63);
                            refsDirty = true;
                        }
                        ImGui::EndDragDropTarget();
                    }
                    ImGui::SameLine();
                    if (ImGui::Button("Pick")) {
                        if (isVisualPicker) {
                            openVisualPicker = true;
                            ccVisualFilter[0] = 0;
                        } else {
                            openCameraPicker = true;
                            ccCameraFilter[0] = 0;
                        }
                    }
                    ImGui::SameLine();
                    if (ImGui::Button("X")) {
                        valueBuffer[0] = 0;
                        refsDirty = true;
                    }
                    ImGui::PopID();
                };

                if (EditorUI::BeginPropertyTable("CharacterControllerGeneral")) {
                    EditorUI::SetNextPropertyInfoTooltip("Enable/disable controller runtime.\nUnits: bool.\nPersistence: Scene.");
                    dirty |= EditorUI::PropertyBool("Enabled", &enabledBool);
                    EditorUI::EndPropertyTable();
                }

                ImGui::Spacing();
                ImGui::TextDisabled("Capsule");
                if (EditorUI::BeginPropertyTable("CharacterControllerShapeProps")) {
                    dirty |= EditorUI::PropertyFloat("Radius", &radius, 0.01f, 0.05f, 5.0f, "%.2f", true);
                    dirty |= EditorUI::PropertyFloat("Height", &height, 0.01f, 0.2f, 10.0f, "%.2f", true);
                    EditorUI::EndPropertyTable();
                }

                ImGui::Spacing();
                ImGui::TextDisabled("Movement");
                if (EditorUI::BeginPropertyTable("CharacterControllerMovementProps")) {
                    dirty |= EditorUI::PropertyFloat("Move Speed", &moveSpeed, 0.05f, 0.0f, 100.0f, "%.2f", true);
                    dirty |= EditorUI::PropertyFloat("Sprint Multiplier", &sprintMultiplier, 0.05f, 1.0f, 8.0f, "%.2f", true);
                    dirty |= EditorUI::PropertyFloat("Air Control", &airControl, 0.01f, 0.0f, 1.0f, "%.2f", true);
                    dirty |= EditorUI::PropertyFloat("Push Strength", &pushStrength, 1.0f, 0.0f, 2000.0f, "%.1f", true);
                    EditorUI::EndPropertyTable();
                }

                ImGui::Spacing();
                ImGui::TextDisabled("Jump & Gravity");
                if (EditorUI::BeginPropertyTable("CharacterControllerJumpGravityProps")) {
                    dirty |= EditorUI::PropertyFloat("Jump Speed", &jumpSpeed, 0.05f, 0.0f, 100.0f, "%.2f", true);
                    dirty |= EditorUI::PropertyBool("Override Gravity", &gravityOverrideEnabled);
                    if (gravityOverrideEnabled) {
                        dirty |= EditorUI::PropertyFloat("Gravity", &gravity, 0.05f, -100.0f, 0.0f, "%.2f", true);
                    }
                    EditorUI::EndPropertyTable();
                }

                ImGui::Spacing();
                ImGui::TextDisabled("Grounding");
                if (EditorUI::BeginPropertyTable("CharacterControllerGroundingProps")) {
                    dirty |= EditorUI::PropertyFloat("Max Slope", &maxSlope, 1.0f, 1.0f, 89.0f, "%.1f", true);
                    dirty |= EditorUI::PropertyFloat("Step Offset", &stepOffset, 0.01f, 0.0f, 2.0f, "%.2f", true);
                    EditorUI::EndPropertyTable();
                }

                ImGui::Spacing();
                ImGui::TextDisabled("Look");
                if (EditorUI::BeginPropertyTable("CharacterControllerLookProps")) {
                    dirty |= EditorUI::PropertyFloat("Look Sensitivity", &lookSensitivity, 0.0001f, 0.0f, 1.0f, "%.4f", true);
                    dirty |= EditorUI::PropertyFloat("Pitch Min", &minPitchDegrees, 0.5f, -89.0f, 0.0f, "%.1f", true);
                    dirty |= EditorUI::PropertyFloat("Pitch Max", &maxPitchDegrees, 0.5f, 0.0f, 89.0f, "%.1f", true);
                    EditorUI::EndPropertyTable();
                }

                ImGui::Spacing();
                ImGui::TextDisabled("References");
                if (EditorUI::BeginPropertyTable("CharacterControllerReferencesProps")) {
                    drawEntityRefRow("Visual Entity", visualEntityId, true);
                    drawEntityRefRow("Camera Pivot", cameraPivotEntityId, false);
                    EditorUI::EndPropertyTable();
                }

                if (openVisualPicker) {
                    ImGui::OpenPopup("CCVisualEntityPicker");
                    openVisualPicker = false;
                }
                if (ImGui::BeginPopupModal("CCVisualEntityPicker", nullptr, ImGuiWindowFlags_AlwaysAutoResize)) {
                    ImGui::InputTextWithHint("##CCVisualFilter", "Search mesh entities...", ccVisualFilter, sizeof(ccVisualFilter));
                    ImGui::Separator();
                    const std::string filterText = EditorUI::ToLower(std::string(ccVisualFilter));
                    const int32_t entityCount = MCEEditorGetEntityCount(context);
                    for (int32_t i = 0; i < entityCount; ++i) {
                        char idBuffer[64] = {0};
                        char nameBuffer[256] = {0};
                        if (MCEEditorGetEntityIdAt(context, i, idBuffer, sizeof(idBuffer)) <= 0) { continue; }
                        if (MCEEditorEntityHasComponent(context, idBuffer, ComponentMeshRenderer) == 0) { continue; }
                        MCEEditorGetEntityName(context, idBuffer, nameBuffer, sizeof(nameBuffer));
                        std::string display = nameBuffer[0] != 0 ? nameBuffer : idBuffer;
                        if (!filterText.empty() && EditorUI::ToLower(display).find(filterText) == std::string::npos) {
                            continue;
                        }
                        std::string selectableLabel = display + "##cc_visual_" + std::string(idBuffer);
                        if (ImGui::Selectable(selectableLabel.c_str())) {
                            strncpy(visualEntityId, idBuffer, sizeof(visualEntityId) - 1);
                            refsDirty = true;
                            ImGui::CloseCurrentPopup();
                        }
                    }
                    if (ImGui::Button("Clear")) {
                        visualEntityId[0] = 0;
                        refsDirty = true;
                        ImGui::CloseCurrentPopup();
                    }
                    ImGui::SameLine();
                    if (ImGui::Button("Close")) {
                        ImGui::CloseCurrentPopup();
                    }
                    ImGui::EndPopup();
                }

                if (openCameraPicker) {
                    ImGui::OpenPopup("CCCameraPivotPicker");
                    openCameraPicker = false;
                }
                if (ImGui::BeginPopupModal("CCCameraPivotPicker", nullptr, ImGuiWindowFlags_AlwaysAutoResize)) {
                    ImGui::InputTextWithHint("##CCCameraFilter", "Search pivot entities...", ccCameraFilter, sizeof(ccCameraFilter));
                    ImGui::Separator();
                    const std::string filterText = EditorUI::ToLower(std::string(ccCameraFilter));
                    const int32_t entityCount = MCEEditorGetEntityCount(context);
                    for (int32_t i = 0; i < entityCount; ++i) {
                        char idBuffer[64] = {0};
                        char nameBuffer[256] = {0};
                        if (MCEEditorGetEntityIdAt(context, i, idBuffer, sizeof(idBuffer)) <= 0) { continue; }
                        MCEEditorGetEntityName(context, idBuffer, nameBuffer, sizeof(nameBuffer));
                        std::string display = nameBuffer[0] != 0 ? nameBuffer : idBuffer;
                        if (!filterText.empty() && EditorUI::ToLower(display).find(filterText) == std::string::npos) {
                            continue;
                        }
                        std::string selectableLabel = display + "##cc_camera_" + std::string(idBuffer);
                        if (ImGui::Selectable(selectableLabel.c_str())) {
                            strncpy(cameraPivotEntityId, idBuffer, sizeof(cameraPivotEntityId) - 1);
                            refsDirty = true;
                            ImGui::CloseCurrentPopup();
                        }
                    }
                    if (ImGui::Button("Clear")) {
                        cameraPivotEntityId[0] = 0;
                        refsDirty = true;
                        ImGui::CloseCurrentPopup();
                    }
                    ImGui::SameLine();
                    if (ImGui::Button("Close")) {
                        ImGui::CloseCurrentPopup();
                    }
                    ImGui::EndPopup();
                }
                if (dirty) {
                    MCEEditorSetCharacterController(context,
                                                    selectedEntityId,
                                                    enabledBool ? 1u : 0u,
                                                    height,
                                                    radius,
                                                    stepOffset,
                                                    moveSpeed,
                                                    sprintMultiplier,
                                                    jumpSpeed,
                                                    gravityOverrideEnabled ? 1u : 0u,
                                                    gravity,
                                                    maxSlope,
                                                    pushStrength,
                                                    airControl,
                                                    lookSensitivity,
                                                    minPitchDegrees,
                                                    maxPitchDegrees,
                                                    0);
                }
                if (refsDirty) {
                    MCEEditorSetCharacterControllerEntityRefs(context,
                                                              selectedEntityId,
                                                              visualEntityId[0] != 0 ? visualEntityId : nullptr,
                                                              cameraPivotEntityId[0] != 0 ? cameraPivotEntityId : nullptr);
                }
            }
        }
    }

    if (runtimeLocked) {
        ImGui::BeginDisabled(true);
    }

    const bool hasMeshRenderer = hasValidEntity && MCEEditorEntityHasComponent(context, selectedEntityId, ComponentMeshRenderer) != 0;
    if (hasMeshRenderer) {
        bool meshOpen = EditorUI::BeginSectionWithContext(context, 
            "Mesh Renderer",
            "Inspector.MeshRenderer",
            "MeshRendererContext",
            [&]() {
                if (ImGui::MenuItem("Reset")) {
                    const char *empty = "";
                    MCEEditorSetMeshRenderer(context, selectedEntityId, empty, empty);
                    MCEEditorSetMaterialComponent(context, selectedEntityId, empty);
                }
                if (ImGui::MenuItem("Remove")) {
                    MCEEditorRemoveComponent(context, selectedEntityId, ComponentMeshRenderer);
                }
            },
            true);
        if (meshOpen) {
            char meshHandle[64] = {0};
            char materialHandle[64] = {0};
            MCEEditorGetMeshRenderer(context, selectedEntityId, meshHandle, sizeof(meshHandle), materialHandle, sizeof(materialHandle));

            if (EditorUI::BeginPropertyTable("MeshRendererProps")) {
                EditorUI::SetNextPropertyInfoTooltip("Mesh asset reference for rendering.\nUnits: asset handle.\nPerformance: mesh complexity dependent.\nPersistence: Scene.");
                if (DrawMeshHandleRow(context, state, "Mesh", meshHandle, sizeof(meshHandle), "MCE_ASSET_MODEL", selectedEntityId, materialHandle)) {
                    MCEEditorSetMeshRenderer(context, selectedEntityId, meshHandle, materialHandle);
                }
                EditorUI::SetNextPropertyInfoTooltip("Material asset used for shading.\nUnits: asset handle.\nPerformance: shader/material dependent.\nPersistence: Scene.");
                if (DrawMaterialHandleRow(context, state, "Material", materialHandle, sizeof(materialHandle), "MCE_ASSET_MATERIAL", selectedEntityId, meshHandle, true)) {
                    MCEEditorSetMeshRenderer(context, selectedEntityId, meshHandle, materialHandle);
                    MCEEditorSetMaterialComponent(context, selectedEntityId, materialHandle);
                }
                EditorUI::EndPropertyTable();
            }

            if (materialHandle[0] != 0) {
                if (MaterialEditorState *textureState = GetInspectorMaterialState(context, state, materialHandle)) {
                    bool texturesDirty = DrawMaterialTextureInspector(context, state, *textureState, materialHandle);
                    TexturePickerState &picker = GetTexturePickerState(state);
                    bool pickerDirty = picker.didPick && strcmp(picker.materialHandle, materialHandle) == 0;
                    if (pickerDirty) {
                        picker.didPick = false;
                    }
                    if (texturesDirty || pickerDirty) {
                        EnforceMetalRoughnessRule(*textureState);
                        MCEEditorSetMaterialAsset(
                            context,
                            materialHandle,
                            textureState->name,
                            textureState->version,
                            textureState->baseColor[0], textureState->baseColor[1], textureState->baseColor[2],
                            textureState->metallic, textureState->roughness, textureState->ao,
                            textureState->emissive[0], textureState->emissive[1], textureState->emissive[2],
                            textureState->emissiveIntensity,
                            textureState->uvTiling[0], textureState->uvTiling[1],
                            textureState->uvOffset[0], textureState->uvOffset[1],
                            textureState->alphaMode, textureState->alphaCutoff,
                            textureState->doubleSided ? 1 : 0, textureState->unlit ? 1 : 0,
                            textureState->baseColorHandle,
                            textureState->normalHandle,
                            textureState->metalRoughnessHandle,
                            textureState->metallicHandle,
                            textureState->roughnessHandle,
                            textureState->aoHandle,
                            textureState->emissiveHandle);
                    }
                }
            }

            if (materialHandle[0] == 0) {
                if (ImGui::Button("Create + Assign New Material")) {
                    char outHandle[64] = {0};
                    MCEEditorCreateMaterial(context, "Materials", "NewMaterial", outHandle, sizeof(outHandle));
                    if (outHandle[0] != 0) {
                        MCEEditorSetMeshRenderer(context, selectedEntityId, meshHandle, outHandle);
                        MCEEditorSetMaterialComponent(context, selectedEntityId, outHandle);
                        MCEEditorSetSelectedMaterial(context, outHandle);
                    }
                }
            }
        }
    }

    const bool hasSkinnedMesh = hasValidEntity && MCEEditorEntityHasComponent(context, selectedEntityId, ComponentSkinnedMesh) != 0;
    if (hasSkinnedMesh) {
        bool skinnedOpen = EditorUI::BeginSectionWithContext(context,
            "Skinned Mesh",
            "Inspector.SkinnedMesh",
            "SkinnedMeshContext",
            [&]() {
                if (ImGui::MenuItem("Clear Skeleton")) {
                    const char *empty = "";
                    MCEEditorSetSkinnedMesh(context, selectedEntityId, empty);
                }
                if (ImGui::MenuItem("Remove")) {
                    MCEEditorRemoveComponent(context, selectedEntityId, ComponentSkinnedMesh);
                }
            },
            true);
        if (skinnedOpen) {
            char skeletonHandle[64] = {0};
            int32_t jointCount = 0;
            uint32_t isValidSkeleton = 0;
            MCEEditorGetSkinnedMesh(context, selectedEntityId, skeletonHandle, sizeof(skeletonHandle), &jointCount, &isValidSkeleton);

            char meshHandle[64] = {0};
            char materialHandle[64] = {0};
            MCEEditorGetMeshRenderer(context, selectedEntityId, meshHandle, sizeof(meshHandle), materialHandle, sizeof(materialHandle));

            if (EditorUI::BeginPropertyTable("SkinnedMeshProps")) {
                EditorUI::PropertyLabel("Skeleton");
                ImGui::PushID("SkinnedSkeleton");
                char displayName[128] = {0};
                GetAssetName(context, skeletonHandle, displayName, sizeof(displayName));
                ImGui::TextUnformatted(displayName);
                if (ImGui::BeginDragDropTarget()) {
                    if (const ImGuiPayload* payload = ImGui::AcceptDragDropPayload("MCE_ASSET_SKELETON")) {
                        const char *payloadText = static_cast<const char *>(payload->Data);
                        strncpy(skeletonHandle, payloadText, sizeof(skeletonHandle) - 1);
                        skeletonHandle[sizeof(skeletonHandle) - 1] = 0;
                        MCEEditorSetSkinnedMesh(context, selectedEntityId, skeletonHandle);
                    }
                    ImGui::EndDragDropTarget();
                }
                ImGui::SameLine();
                if (ImGui::Button("Clear")) {
                    skeletonHandle[0] = 0;
                    MCEEditorSetSkinnedMesh(context, selectedEntityId, skeletonHandle);
                }
                ImGui::PopID();

                EditorUI::PropertyLabel("Status");
                if (skeletonHandle[0] == 0) {
                    ImGui::TextColored(ImVec4(0.95f, 0.7f, 0.2f, 1.0f), "No skeleton assigned");
                } else if (isValidSkeleton == 0) {
                    ImGui::TextColored(ImVec4(0.95f, 0.45f, 0.45f, 1.0f), "Invalid skeleton asset");
                } else {
                    ImGui::TextColored(ImVec4(0.45f, 0.9f, 0.55f, 1.0f), "Valid");
                }

                EditorUI::PropertyLabel("Joint Count");
                ImGui::Text("%d", static_cast<int>(jointCount));
                EditorUI::EndPropertyTable();
            }

            std::vector<AssetOption> skeletonOptions;
            LoadSkeletonOptions(context, skeletonOptions);
            const char *currentSkeleton = "None";
            int selectedSkeletonIndex = 0;
            for (size_t i = 0; i < skeletonOptions.size(); ++i) {
                if (skeletonOptions[i].handle == skeletonHandle) {
                    selectedSkeletonIndex = static_cast<int>(i) + 1;
                    currentSkeleton = skeletonOptions[i].name.c_str();
                    break;
                }
            }
            if (ImGui::BeginCombo("Skeleton Picker", currentSkeleton)) {
                if (ImGui::Selectable("None", selectedSkeletonIndex == 0)) {
                    skeletonHandle[0] = 0;
                    MCEEditorSetSkinnedMesh(context, selectedEntityId, skeletonHandle);
                }
                for (const auto &option : skeletonOptions) {
                    const bool selected = option.handle == skeletonHandle;
                    if (ImGui::Selectable(option.name.c_str(), selected)) {
                        MCEEditorSetSkinnedMesh(context, selectedEntityId, option.handle.c_str());
                    }
                }
                ImGui::EndCombo();
            }
            if (meshHandle[0] != 0) {
                char importedSkeleton[64] = {0};
                if (MCEEditorGetImportedSkeletonHandleForMesh(context, meshHandle, importedSkeleton, sizeof(importedSkeleton)) != 0) {
                    if (ImGui::Button("Use Imported Skeleton")) {
                        MCEEditorSetSkinnedMesh(context, selectedEntityId, importedSkeleton);
                    }
                }
            }
        }
    }

    const bool hasAnimator = hasValidEntity && MCEEditorEntityHasComponent(context, selectedEntityId, ComponentAnimator) != 0;
    if (hasAnimator) {
        bool animatorOpen = EditorUI::BeginSectionWithContext(context,
            "Animator",
            "Inspector.Animator",
            "AnimatorContext",
            [&]() {
                if (ImGui::MenuItem("Reset")) {
                    MCEEditorSetAnimator(context, selectedEntityId, nullptr, 0.0f, 1.0f, 1u, 1u);
                }
                if (ImGui::MenuItem("Remove")) {
                    MCEEditorRemoveComponent(context, selectedEntityId, ComponentAnimator);
                }
            },
            true);
        if (animatorOpen) {
            char clipHandle[64] = {0};
            float playbackTime = 0.0f;
            float playbackSpeed = 1.0f;
            uint32_t isPlaying = 1;
            uint32_t isLooping = 1;
            MCEEditorGetAnimator(context, selectedEntityId, clipHandle, sizeof(clipHandle), &playbackTime, &playbackSpeed, &isPlaying, &isLooping);
            int32_t animatorMode = 0;
            char graphHandle[64] = {0};
            MCEEditorGetAnimatorMode(context, selectedEntityId, &animatorMode, graphHandle, sizeof(graphHandle));

            char meshHandle[64] = {0};
            char materialHandle[64] = {0};
            MCEEditorGetMeshRenderer(context, selectedEntityId, meshHandle, sizeof(meshHandle), materialHandle, sizeof(materialHandle));

            const char *animatorModes[] = {"Clip", "Graph"};
            int modeIndex = animatorMode == 1 ? 1 : 0;
            ImGui::SetNextItemWidth(180.0f);
            if (ImGui::Combo("Mode", &modeIndex, animatorModes, IM_ARRAYSIZE(animatorModes))) {
                if (modeIndex == 0) {
                    MCEEditorSetAnimator(context, selectedEntityId, clipHandle, playbackTime, playbackSpeed, isPlaying, isLooping);
                } else {
                    MCEEditorSetAnimatorGraph(context, selectedEntityId, graphHandle[0] != 0 ? graphHandle : nullptr, playbackTime, playbackSpeed, isPlaying, isLooping);
                }
                animatorMode = modeIndex == 1 ? 1 : 0;
            }

            if (animatorMode == 0) {

            float duration = 0.0f;
            if (clipHandle[0] != 0) {
                MCEEditorGetAnimationClipDuration(context, clipHandle, &duration);
            }
            const float sliderMax = duration > 0.0f ? duration : std::max(5.0f, playbackTime + 1.0f);
            int32_t evaluatedJointCount = 0;
            uint32_t hasPoseState = 0;
            MCEEditorGetAnimatorRuntimeStats(context, selectedEntityId, &evaluatedJointCount, &hasPoseState);

            char assignedSkeletonHandle[64] = {0};
            int32_t skinnedJointCount = 0;
            uint32_t skinnedValid = 0;
            if (hasSkinnedMesh) {
                MCEEditorGetSkinnedMesh(context, selectedEntityId, assignedSkeletonHandle, sizeof(assignedSkeletonHandle), &skinnedJointCount, &skinnedValid);
            }

            if (EditorUI::BeginPropertyTable("AnimatorProps")) {
                EditorUI::PropertyLabel("Clip");
                ImGui::PushID("AnimatorClip");
                char clipDisplayName[128] = {0};
                GetAssetName(context, clipHandle, clipDisplayName, sizeof(clipDisplayName));
                ImGui::TextUnformatted(clipDisplayName);
                if (ImGui::BeginDragDropTarget()) {
                    if (const ImGuiPayload* payload = ImGui::AcceptDragDropPayload("MCE_ASSET_ANIMATION_CLIP")) {
                        const char *payloadText = static_cast<const char *>(payload->Data);
                        strncpy(clipHandle, payloadText, sizeof(clipHandle) - 1);
                        clipHandle[sizeof(clipHandle) - 1] = 0;
                        MCEEditorSetAnimator(context, selectedEntityId, clipHandle, playbackTime, playbackSpeed, isPlaying, isLooping);
                    }
                    ImGui::EndDragDropTarget();
                }
                ImGui::SameLine();
                if (ImGui::Button("Clear")) {
                    clipHandle[0] = 0;
                    playbackTime = 0.0f;
                    MCEEditorSetAnimator(context, selectedEntityId, clipHandle, playbackTime, playbackSpeed, isPlaying, isLooping);
                }
                ImGui::PopID();

                bool play = isPlaying != 0;
                if (EditorUI::PropertyBool("Playing", &play)) {
                    isPlaying = play ? 1u : 0u;
                    MCEEditorSetAnimator(context, selectedEntityId, clipHandle, playbackTime, playbackSpeed, isPlaying, isLooping);
                }

                bool loop = isLooping != 0;
                if (EditorUI::PropertyBool("Looping", &loop)) {
                    isLooping = loop ? 1u : 0u;
                    MCEEditorSetAnimator(context, selectedEntityId, clipHandle, playbackTime, playbackSpeed, isPlaying, isLooping);
                }

                if (EditorUI::PropertyFloat("Playback Time", &playbackTime, 0.01f, 0.0f, sliderMax, "%.3f", true, false, 0.0f)) {
                    MCEEditorSetAnimator(context, selectedEntityId, clipHandle, playbackTime, playbackSpeed, isPlaying, isLooping);
                }
                if (EditorUI::PropertyFloat("Playback Speed", &playbackSpeed, 0.01f, 0.0f, 4.0f, "%.2f", true, true, 1.0f)) {
                    MCEEditorSetAnimator(context, selectedEntityId, clipHandle, playbackTime, playbackSpeed, isPlaying, isLooping);
                }
                EditorUI::PropertyLabel("Clip Duration");
                ImGui::Text("%.3fs", duration);
                EditorUI::PropertyLabel("Current Time");
                ImGui::Text("%.3fs", playbackTime);

                EditorUI::PropertyLabel("State");
                ImGui::Text("isPlaying=%s | isLooping=%s", isPlaying ? "true" : "false", isLooping ? "true" : "false");
                EditorUI::EndPropertyTable();
            }

            if (ImGui::Button(isPlaying != 0 ? "Pause" : "Play")) {
                isPlaying = isPlaying != 0 ? 0u : 1u;
                MCEEditorSetAnimator(context, selectedEntityId, clipHandle, playbackTime, playbackSpeed, isPlaying, isLooping);
            }
            ImGui::SameLine();
            bool loopToggle = isLooping != 0;
            if (ImGui::Checkbox("Loop", &loopToggle)) {
                isLooping = loopToggle ? 1u : 0u;
                MCEEditorSetAnimator(context, selectedEntityId, clipHandle, playbackTime, playbackSpeed, isPlaying, isLooping);
            }

            ImGui::SetNextItemWidth(-1.0f);
            if (ImGui::SliderFloat("Time Scrub", &playbackTime, 0.0f, sliderMax, "%.3f")) {
                MCEEditorSetAnimator(context, selectedEntityId, clipHandle, playbackTime, playbackSpeed, isPlaying, isLooping);
            }

            if (clipHandle[0] == 0) {
                ImGui::TextColored(ImVec4(0.95f, 0.7f, 0.2f, 1.0f), "No animation clip assigned.");
            }
            if (!hasSkinnedMesh) {
                ImGui::TextColored(ImVec4(0.95f, 0.7f, 0.2f, 1.0f), "Animator is active without Skinned Mesh component.");
            }

            std::vector<AssetOption> importedClips;
            if (meshHandle[0] != 0) {
                const int32_t importedCount = MCEEditorGetImportedClipCountForMesh(context, meshHandle);
                importedClips.reserve(std::max(0, importedCount));
                for (int32_t i = 0; i < importedCount; ++i) {
                    char importedHandle[64] = {0};
                    if (MCEEditorGetImportedClipHandleForMeshAt(context, meshHandle, i, importedHandle, sizeof(importedHandle)) == 0) {
                        continue;
                    }
                    char importedName[128] = {0};
                    GetAssetName(context, importedHandle, importedName, sizeof(importedName));
                    AssetOption option;
                    option.handle = importedHandle;
                    option.name = importedName;
                    option.path = "";
                    importedClips.push_back(option);
                }
            }

            std::vector<AssetOption> skeletonAssociatedClips;
            if (assignedSkeletonHandle[0] != 0) {
                const int32_t associatedCount = MCEEditorGetAssociatedClipCountForSkeleton(context, assignedSkeletonHandle);
                skeletonAssociatedClips.reserve(std::max(0, associatedCount));
                for (int32_t i = 0; i < associatedCount; ++i) {
                    char associatedHandle[64] = {0};
                    if (MCEEditorGetAssociatedClipHandleForSkeletonAt(context, assignedSkeletonHandle, i, associatedHandle, sizeof(associatedHandle)) == 0) {
                        continue;
                    }
                    char associatedName[128] = {0};
                    GetAssetName(context, associatedHandle, associatedName, sizeof(associatedName));
                    AssetOption option;
                    option.handle = associatedHandle;
                    option.name = associatedName;
                    option.path = "";
                    skeletonAssociatedClips.push_back(option);
                }
            }

            if (!skeletonAssociatedClips.empty()) {
                const char *currentAssociatedName = "Select Skeleton Clip";
                for (const auto &clip : skeletonAssociatedClips) {
                    if (clip.handle == clipHandle) {
                        currentAssociatedName = clip.name.c_str();
                        break;
                    }
                }
                if (ImGui::BeginCombo("Skeleton Clips", currentAssociatedName)) {
                    for (const auto &clip : skeletonAssociatedClips) {
                        float clipDuration = 0.0f;
                        MCEEditorGetAnimationClipDuration(context, clip.handle.c_str(), &clipDuration);
                        std::string label = ClipOptionLabel(clip, skeletonAssociatedClips) + " (" + std::to_string(clipDuration) + "s)";
                        const bool selected = clip.handle == clipHandle;
                        std::string selectableLabel = label + "##" + clip.handle;
                        if (ImGui::Selectable(selectableLabel.c_str(), selected)) {
                            MCEEditorSetAnimator(context, selectedEntityId, clip.handle.c_str(), 0.0f, playbackSpeed, isPlaying, isLooping);
                        }
                    }
                    ImGui::EndCombo();
                }
            }

            if (!importedClips.empty()) {
                char defaultImportedClip[64] = {0};
                MCEEditorGetImportedDefaultClipHandleForMesh(context, meshHandle, defaultImportedClip, sizeof(defaultImportedClip));
                const char *currentImportedName = "Select Imported Clip";
                for (const auto &clip : importedClips) {
                    if (clip.handle == clipHandle) {
                        currentImportedName = clip.name.c_str();
                        break;
                    }
                }
                if (ImGui::BeginCombo("Imported Clips", currentImportedName)) {
                    for (const auto &clip : importedClips) {
                        float clipDuration = 0.0f;
                        MCEEditorGetAnimationClipDuration(context, clip.handle.c_str(), &clipDuration);
                        std::string label = ClipOptionLabel(clip, importedClips) + " (" + std::to_string(clipDuration) + "s)";
                        if (defaultImportedClip[0] != 0 && clip.handle == defaultImportedClip) {
                            label += " [Default]";
                        }
                        const bool selected = clip.handle == clipHandle;
                        std::string selectableLabel = label + "##" + clip.handle;
                        if (ImGui::Selectable(selectableLabel.c_str(), selected)) {
                            MCEEditorSetAnimator(context, selectedEntityId, clip.handle.c_str(), 0.0f, playbackSpeed, isPlaying, isLooping);
                        }
                    }
                    ImGui::EndCombo();
                }
            }

            std::vector<AssetOption> clipOptions;
            LoadAnimationClipOptions(context, clipOptions);
            const char *currentClipName = "Select Clip";
            for (const auto &option : clipOptions) {
                if (option.handle == clipHandle) {
                    currentClipName = option.name.c_str();
                    break;
                }
            }
            if (ImGui::BeginCombo("All Clips", currentClipName)) {
                for (const auto &option : clipOptions) {
                    const bool selected = option.handle == clipHandle;
                    std::string displayLabel = ClipOptionLabel(option, clipOptions);
                    std::string selectableLabel = displayLabel + "##" + option.handle;
                    if (ImGui::Selectable(selectableLabel.c_str(), selected)) {
                        MCEEditorSetAnimator(context, selectedEntityId, option.handle.c_str(), 0.0f, playbackSpeed, isPlaying, isLooping);
                    }
                }
                ImGui::EndCombo();
            }

            ImGui::Separator();
            ImGui::TextUnformatted("Animation Debug");
            char activeClipName[128] = {0};
            GetAssetName(context, clipHandle, activeClipName, sizeof(activeClipName));
            char skeletonName[128] = {0};
            GetAssetName(context, assignedSkeletonHandle, skeletonName, sizeof(skeletonName));
            ImGui::Text("Skeleton: %s", assignedSkeletonHandle[0] != 0 ? assignedSkeletonHandle : "<none>");
            ImGui::Text("Skeleton Asset: %s", skeletonName);
            ImGui::Text("Clip: %s", clipHandle[0] != 0 ? clipHandle : "<none>");
            ImGui::Text("Clip Asset: %s", activeClipName);
            ImGui::Text("Imported Clip Count: %d", static_cast<int>(importedClips.size()));
            ImGui::Text("Evaluated Joint Count: %d", static_cast<int>(evaluatedJointCount));
            const bool skinningActive = (hasSkinnedMesh && skinnedValid != 0 && clipHandle[0] != 0 && evaluatedJointCount > 0 && hasPoseState != 0);
            ImGui::Text("Skinning Active: %s", skinningActive ? "true" : "false");
            if (assignedSkeletonHandle[0] == 0) {
                ImGui::TextColored(ImVec4(0.95f, 0.7f, 0.2f, 1.0f), "Warning: SkinnedMesh has no skeleton handle.");
            } else if (skinnedValid == 0) {
                ImGui::TextColored(ImVec4(0.95f, 0.45f, 0.45f, 1.0f), "Warning: Skeleton asset is missing or invalid.");
            }
            if (clipHandle[0] == 0) {
                ImGui::TextColored(ImVec4(0.95f, 0.7f, 0.2f, 1.0f), "Warning: Animator has no clip selected.");
            } else if (duration <= 0.0f) {
                ImGui::TextColored(ImVec4(0.95f, 0.45f, 0.45f, 1.0f), "Warning: Active clip duration is zero.");
            }
            if (hasPoseState == 0 && clipHandle[0] != 0 && assignedSkeletonHandle[0] != 0) {
                ImGui::TextColored(ImVec4(0.95f, 0.45f, 0.45f, 1.0f), "Warning: No evaluated pose runtime state.");
            }

            if (meshHandle[0] != 0) {
                char importScaleNormalization[64] = {0};
                char importScaleApplied[64] = {0};
                const bool hasScaleMode = MCEEditorGetAssetImportSetting(context, meshHandle, "importScaleNormalization", importScaleNormalization, sizeof(importScaleNormalization)) != 0;
                const bool hasScaleApplied = MCEEditorGetAssetImportSetting(context, meshHandle, "importScaleApplied", importScaleApplied, sizeof(importScaleApplied)) != 0;
                if (hasScaleMode || hasScaleApplied) {
                    ImGui::Text("Import Scale Normalization: %s", hasScaleMode ? importScaleNormalization : "<unknown>");
                    ImGui::Text("Import Scale Applied: %s", hasScaleApplied ? importScaleApplied : "<unknown>");
                }
            }
            } else {
                const float sliderMax = std::max(5.0f, playbackTime + 1.0f);
                uint32_t rootMotionEnabledRaw = 1;
                MCEEditorGetAnimatorRootMotionEnabled(context, selectedEntityId, &rootMotionEnabledRaw);
                if (EditorUI::BeginPropertyTable("AnimatorGraphProps")) {
                    EditorUI::PropertyLabel("Graph");
                    ImGui::PushID("AnimatorGraph");
                    char graphDisplayName[128] = {0};
                    GetAssetName(context, graphHandle, graphDisplayName, sizeof(graphDisplayName));
                    ImGui::TextUnformatted(graphDisplayName);
                    if (ImGui::BeginDragDropTarget()) {
                        if (const ImGuiPayload* payload = ImGui::AcceptDragDropPayload("MCE_ASSET_ANIMATION_GRAPH")) {
                            const char *payloadText = static_cast<const char *>(payload->Data);
                            strncpy(graphHandle, payloadText, sizeof(graphHandle) - 1);
                            graphHandle[sizeof(graphHandle) - 1] = 0;
                            MCEEditorSetAnimatorGraph(context, selectedEntityId, graphHandle, playbackTime, playbackSpeed, isPlaying, isLooping);
                        }
                        ImGui::EndDragDropTarget();
                    }
                    ImGui::SameLine();
                    if (ImGui::Button("Clear")) {
                        graphHandle[0] = 0;
                        MCEEditorSetAnimatorGraph(context, selectedEntityId, nullptr, playbackTime, playbackSpeed, isPlaying, isLooping);
                    }
                    ImGui::PopID();

                    bool play = isPlaying != 0;
                    if (EditorUI::PropertyBool("Playing", &play)) {
                        isPlaying = play ? 1u : 0u;
                        MCEEditorSetAnimatorGraph(context, selectedEntityId, graphHandle[0] != 0 ? graphHandle : nullptr, playbackTime, playbackSpeed, isPlaying, isLooping);
                    }
                    bool loop = isLooping != 0;
                    if (EditorUI::PropertyBool("Looping", &loop)) {
                        isLooping = loop ? 1u : 0u;
                        MCEEditorSetAnimatorGraph(context, selectedEntityId, graphHandle[0] != 0 ? graphHandle : nullptr, playbackTime, playbackSpeed, isPlaying, isLooping);
                    }
                    bool enableRootMotion = rootMotionEnabledRaw != 0;
                    if (EditorUI::PropertyBool("Enable Root Motion", &enableRootMotion)) {
                        rootMotionEnabledRaw = enableRootMotion ? 1u : 0u;
                        MCEEditorSetAnimatorRootMotionEnabled(context, selectedEntityId, rootMotionEnabledRaw);
                    }
                    if (EditorUI::PropertyFloat("Playback Time", &playbackTime, 0.01f, 0.0f, sliderMax, "%.3f", true, false, 0.0f)) {
                        MCEEditorSetAnimatorGraph(context, selectedEntityId, graphHandle[0] != 0 ? graphHandle : nullptr, playbackTime, playbackSpeed, isPlaying, isLooping);
                    }
                    if (EditorUI::PropertyFloat("Playback Speed", &playbackSpeed, 0.01f, 0.0f, 4.0f, "%.2f", true, true, 1.0f)) {
                        MCEEditorSetAnimatorGraph(context, selectedEntityId, graphHandle[0] != 0 ? graphHandle : nullptr, playbackTime, playbackSpeed, isPlaying, isLooping);
                    }
                    EditorUI::EndPropertyTable();
                }

                ImGui::Separator();
                ImGui::TextUnformatted("Graph Parameters");
                const int32_t parameterCount = MCEEditorGetAnimatorGraphParameterCount(context, selectedEntityId);
                if (parameterCount <= 0) {
                    ImGui::TextDisabled("No parameters.");
                } else {
                    for (int32_t i = 0; i < parameterCount; ++i) {
                        char parameterName[128] = {0};
                        int32_t parameterType = 0;
                        float defaultFloat = 0.0f;
                        uint32_t defaultBool = 0;
                        int32_t defaultInt = 0;
                        float floatValue = 0.0f;
                        uint32_t boolValue = 0;
                        int32_t intValue = 0;
                        uint32_t triggerValue = 0;
                        if (MCEEditorGetAnimatorGraphParameterAt(context,
                                                                 selectedEntityId,
                                                                 i,
                                                                 parameterName, sizeof(parameterName),
                                                                 &parameterType,
                                                                 &defaultFloat,
                                                                 &defaultBool,
                                                                 &defaultInt,
                                                                 &floatValue,
                                                                 &boolValue,
                                                                 &intValue,
                                                                 &triggerValue) == 0) {
                            continue;
                        }

                        ImGui::PushID(i);
                        if (parameterType == 0) {
                            if (ImGui::DragFloat(parameterName, &floatValue, 0.01f)) {
                                MCEEditorSetAnimatorGraphParameterFloat(context, selectedEntityId, i, floatValue);
                            }
                            ImGui::TextDisabled("default %.3f", defaultFloat);
                        } else if (parameterType == 1) {
                            bool value = boolValue != 0;
                            if (ImGui::Checkbox(parameterName, &value)) {
                                MCEEditorSetAnimatorGraphParameterBool(context, selectedEntityId, i, value ? 1u : 0u);
                            }
                            ImGui::TextDisabled("default %s", defaultBool != 0 ? "true" : "false");
                        } else if (parameterType == 2) {
                            if (ImGui::DragInt(parameterName, &intValue, 1.0f)) {
                                MCEEditorSetAnimatorGraphParameterInt(context, selectedEntityId, i, intValue);
                            }
                            ImGui::TextDisabled("default %d", defaultInt);
                        } else {
                            std::string fireLabel = std::string("Fire##") + parameterName;
                            if (ImGui::Button(fireLabel.c_str())) {
                                MCEEditorSetAnimatorGraphParameterTrigger(context, selectedEntityId, i);
                            }
                            ImGui::SameLine();
                            ImGui::Text("%s = %s", parameterName, triggerValue != 0 ? "true" : "false");
                        }
                        ImGui::PopID();
                    }
                }

                if (isPlaying) {
                    char currentState[128] = {0};
                    char nextState[128] = {0};
                    char rootMotionBoneName[192] = {0};
                    char rootMotionTranslationBoneName[192] = {0};
                    char rootMotionRotationBoneName[192] = {0};
                    char rootMotionConsumeBoneName[192] = {0};
                    float runtimeSpeed = 0.0f;
                    float runtimeMoveX = 0.0f;
                    float runtimeMoveY = 0.0f;
                    uint32_t runtimeGrounded = 0;
                    uint32_t runtimeJumpTrigger = 0;
                    uint32_t runtimeRootMotionEnabled = 0;
                    uint32_t runtimeUsesRootMotion = 0;
                    float runtimeRootMotionDeltaMagnitude = 0.0f;
                    int32_t runtimeRootMotionJointIndex = -1;
                    int32_t runtimeRootMotionTranslationJointIndex = -1;
                    int32_t runtimeRootMotionRotationJointIndex = -1;
                    int32_t runtimeRootMotionConsumeJointIndex = -1;
                    uint32_t runtimeRootTrackConsumed = 0;
                    if (MCEEditorGetAnimatorGraphRuntimeDebug(context,
                                                              selectedEntityId,
                                                              currentState, sizeof(currentState),
                                                              nextState, sizeof(nextState),
                                                              rootMotionBoneName, sizeof(rootMotionBoneName),
                                                              rootMotionTranslationBoneName, sizeof(rootMotionTranslationBoneName),
                                                              rootMotionRotationBoneName, sizeof(rootMotionRotationBoneName),
                                                              rootMotionConsumeBoneName, sizeof(rootMotionConsumeBoneName),
                                                              &runtimeSpeed,
                                                              &runtimeGrounded,
                                                              &runtimeMoveX,
                                                              &runtimeMoveY,
                                                              &runtimeJumpTrigger,
                                                              &runtimeRootMotionEnabled,
                                                              &runtimeUsesRootMotion,
                                                              &runtimeRootMotionDeltaMagnitude,
                                                              &runtimeRootMotionJointIndex,
                                                              &runtimeRootMotionTranslationJointIndex,
                                                              &runtimeRootMotionRotationJointIndex,
                                                              &runtimeRootMotionConsumeJointIndex,
                                                              &runtimeRootTrackConsumed) != 0) {
                        ImGui::Separator();
                        ImGui::TextUnformatted("Runtime");
                        ImGui::Text("State: %s", currentState[0] != 0 ? currentState : "<none>");
                        ImGui::Text("Next: %s", nextState[0] != 0 ? nextState : "-");
                        ImGui::Text("speed %.2f | grounded %s | moveX %.2f | moveY %.2f | jump %s",
                                    runtimeSpeed,
                                    runtimeGrounded != 0 ? "true" : "false",
                                    runtimeMoveX,
                                    runtimeMoveY,
                                    runtimeJumpTrigger != 0 ? "latched" : "false");
                        ImGui::Text("rootMotion enabled %s | active %s | |delta| %.3f",
                                    runtimeRootMotionEnabled != 0 ? "true" : "false",
                                    runtimeUsesRootMotion != 0 ? "true" : "false",
                                    runtimeRootMotionDeltaMagnitude);
                        ImGui::Text("rootBone %s | rootJoint %d | consumed %s",
                                    rootMotionBoneName[0] != 0 ? rootMotionBoneName : "<none>",
                                    runtimeRootMotionJointIndex,
                                    runtimeRootTrackConsumed != 0 ? "true" : "false");
                        ImGui::Text("rm srcT %s[%d] | srcR %s[%d] | consume %s[%d]",
                                    rootMotionTranslationBoneName[0] != 0 ? rootMotionTranslationBoneName : "<none>",
                                    runtimeRootMotionTranslationJointIndex,
                                    rootMotionRotationBoneName[0] != 0 ? rootMotionRotationBoneName : "<none>",
                                    runtimeRootMotionRotationJointIndex,
                                    rootMotionConsumeBoneName[0] != 0 ? rootMotionConsumeBoneName : "<none>",
                                    runtimeRootMotionConsumeJointIndex);
                    }
                }

                if (graphHandle[0] == 0) {
                    ImGui::TextColored(ImVec4(0.95f, 0.7f, 0.2f, 1.0f), "No animation graph assigned.");
                }
                if (!hasSkinnedMesh) {
                    ImGui::TextColored(ImVec4(0.95f, 0.7f, 0.2f, 1.0f), "Animator is active without Skinned Mesh component.");
                }
            }
        }
    }

    bool hasMaterialComponent = hasValidEntity && (MCEEditorEntityHasComponent(context, selectedEntityId, ComponentMaterial) != 0);
    const bool showMaterialSection = !hasMeshRenderer && (hasSelectedMaterial || hasMaterialComponent);
    if (showMaterialSection) {
        char materialHandle[64] = {0};
        if (hasMaterialComponent) {
            MCEEditorGetMaterialComponent(context, selectedEntityId, materialHandle, sizeof(materialHandle));
        } else if (hasValidEntity) {
            char meshHandle[64] = {0};
            MCEEditorGetMeshRenderer(context, selectedEntityId, meshHandle, sizeof(meshHandle), materialHandle, sizeof(materialHandle));
        } else if (hasSelectedMaterial) {
            strncpy(materialHandle, selectedMaterial, sizeof(materialHandle) - 1);
        }

        bool materialOpen = EditorUI::BeginSectionWithContext(context, 
            "Material",
            "Inspector.Material",
            "MaterialContext",
            [&]() {
                if (hasValidEntity && ImGui::MenuItem("Clear Material")) {
                    const char *empty = "";
                    MCEEditorSetMeshRenderer(context, selectedEntityId, empty, empty);
                    MCEEditorSetMaterialComponent(context, selectedEntityId, empty);
                }
                if (hasValidEntity && ImGui::MenuItem("Remove Component")) {
                    MCEEditorRemoveComponent(context, selectedEntityId, ComponentMaterial);
                }
            },
            true);
        if (materialOpen) {
            if (materialHandle[0] == 0) {
                ImGui::TextUnformatted("Assign a material asset.");
                if (hasValidEntity) {
                    if (EditorUI::BeginPropertyTable("MaterialSelection")) {
                        if (DrawMaterialHandleRow(context, state, "Material", materialHandle, sizeof(materialHandle), "MCE_ASSET_MATERIAL", selectedEntityId, nullptr, false)) {
                            MCEEditorAssignMaterialToEntity(context, selectedEntityId, materialHandle);
                        }
                        EditorUI::EndPropertyTable();
                    }
                }
            } else {
                if (EditorUI::BeginPropertyTable("MaterialSelection")) {
                    if (DrawMaterialHandleRow(context, state, "Material", materialHandle, sizeof(materialHandle), "MCE_ASSET_MATERIAL", selectedEntityId, nullptr, false)) {
                        MCEEditorAssignMaterialToEntity(context, selectedEntityId, materialHandle);
                    }
                    EditorUI::EndPropertyTable();
                }

                if (MaterialEditorState *textureState = GetInspectorMaterialState(context, state, materialHandle)) {
                    bool texturesDirty = DrawMaterialTextureInspector(context, state, *textureState, materialHandle);
                    TexturePickerState &picker = GetTexturePickerState(state);
                    bool pickerDirty = picker.didPick && strcmp(picker.materialHandle, materialHandle) == 0;
                    if (pickerDirty) {
                        picker.didPick = false;
                    }
                    if (texturesDirty || pickerDirty) {
                        EnforceMetalRoughnessRule(*textureState);
                        MCEEditorSetMaterialAsset(
                            context,
                            materialHandle,
                            textureState->name,
                            textureState->version,
                            textureState->baseColor[0], textureState->baseColor[1], textureState->baseColor[2],
                            textureState->metallic, textureState->roughness, textureState->ao,
                            textureState->emissive[0], textureState->emissive[1], textureState->emissive[2],
                            textureState->emissiveIntensity,
                            textureState->uvTiling[0], textureState->uvTiling[1],
                            textureState->uvOffset[0], textureState->uvOffset[1],
                            textureState->alphaMode, textureState->alphaCutoff,
                            textureState->doubleSided ? 1 : 0, textureState->unlit ? 1 : 0,
                            textureState->baseColorHandle,
                            textureState->normalHandle,
                            textureState->metalRoughnessHandle,
                            textureState->metallicHandle,
                            textureState->roughnessHandle,
                            textureState->aoHandle,
                            textureState->emissiveHandle);
                    }
                }
            }
        }
    }

    const bool isAutoDrivenSkySun = hasValidEntity && MCEEditorEntityIsAutoDrivenSkySun(context, selectedEntityId) != 0;

    if (isAutoDrivenSkySun) {
        ImGui::PushStyleColor(ImGuiCol_Text, IM_COL32(235, 190, 110, 255));
        ImGui::TextWrapped("Auto Sun is driven by the active Sky entity. It is hidden from normal authoring workflow and direct light edits are locked.");
        ImGui::PopStyleColor();
        ImGui::Spacing();
    }

    if (hasValidEntity && !isAutoDrivenSkySun && MCEEditorEntityHasComponent(context, selectedEntityId, ComponentLight) != 0) {
        bool lightOpen = EditorUI::BeginSectionWithContext(context, 
            "Light",
            "Inspector.Light",
            "LightContext",
            [&]() {
                if (ImGui::MenuItem("Reset")) {
                    MCEEditorSetLight(context, selectedEntityId, 0, 1.0f, 1.0f, 1.0f, 1.0f, 0.0f, 0.95f, 0.9f, 0.0f, -1.0f, 0.0f, 0);
                }
                if (ImGui::MenuItem("Remove")) {
                    MCEEditorRemoveComponent(context, selectedEntityId, ComponentLight);
                }
            },
            true);
        if (lightOpen) {
            int32_t type = 0;
            float colorX = 1, colorY = 1, colorZ = 1;
            float brightness = 1, range = 0, innerCos = 0.95f, outerCos = 0.9f;
            float dirX = 0, dirY = -1, dirZ = 0;
            uint32_t castsShadows = 0;
            if (MCEEditorGetLight(context, selectedEntityId, &type, &colorX, &colorY, &colorZ, &brightness, &range, &innerCos, &outerCos, &dirX, &dirY, &dirZ, &castsShadows) != 0) {
                const char* types[] = {"Point", "Spot", "Directional"};
                bool dirty = false;
                if (EditorUI::BeginPropertyTable("LightProps")) {
                    EditorUI::SetNextPropertyInfoTooltip("Light type.\nUnits: enum.\nPerformance: shadows + spot/directional often costlier.\nPersistence: Scene.");
                    dirty |= EditorUI::PropertyCombo("Type", &type, types, IM_ARRAYSIZE(types));
                    float color[3] = {colorX, colorY, colorZ};
                    const float lightDefault[3] = {1.0f, 1.0f, 1.0f};
                    EditorUI::SetNextPropertyInfoTooltip("Light color.\nUnits: linear RGB.\nPerformance: none.\nPersistence: Scene.");
                    if (EditorUI::PropertyColor3("Color", color, lightDefault, true)) {
                        colorX = color[0];
                        colorY = color[1];
                        colorZ = color[2];
                        dirty = true;
                    }
                    if (type == 2) {
                        EditorUI::SetNextPropertyInfoTooltip("Scene-relative incident illuminance. A value of pi produces radiance 1 from a white Lambertian at normal incidence before dielectric Fresnel redistribution. Not calibrated lux.\nPersistence: Scene.");
                        dirty |= EditorUI::PropertyFloat("Illuminance", &brightness, 0.1f, 0.0f, 100.0f, "%.2f", true, true, 1.0f);
                    } else {
                        EditorUI::SetNextPropertyInfoTooltip("Scene-relative numerator of inverse-square irradiance. Not calibrated candela.\nPersistence: Scene.");
                        dirty |= EditorUI::PropertyFloat("Intensity", &brightness, 0.1f, 0.0f, 100.0f, "%.2f", true, true, 1.0f);
                    }
                    EditorUI::SetNextPropertyInfoTooltip("Finite-support distance. Inverse-square response is unchanged through 80% of range, then fades smoothly to zero. Zero means no finite cutoff.\nUnits: scene distance.\nPerformance: larger ranges can affect more pixels.\nPersistence: Scene.");
                    dirty |= EditorUI::PropertyFloat("Range", &range, 0.1f, 0.0f, 100.0f, "%.2f", true, true, 0.0f);
                    if (type == 1) {
                        EditorUI::SetNextPropertyInfoTooltip("Spot inner cone cosine.\nUnits: cosine value.\nPerformance: low.\nPersistence: Scene.");
                        dirty |= EditorUI::PropertyFloat("Inner Cone", &innerCos, 0.01f, 0.0f, 1.0f, "%.3f", true, true, 0.95f);
                        EditorUI::SetNextPropertyInfoTooltip("Spot outer cone cosine.\nUnits: cosine value.\nPerformance: low.\nPersistence: Scene.");
                        dirty |= EditorUI::PropertyFloat("Outer Cone", &outerCos, 0.01f, 0.0f, 1.0f, "%.3f", true, true, 0.9f);
                    }
                    if (type == 2) {
                        float direction[3] = {dirX, dirY, dirZ};
                        ImGui::BeginDisabled(true);
                        EditorUI::SetNextPropertyInfoTooltip("Read-only transform-derived light direction.\nUnits: normalized vector.\nPersistence: Scene transform.");
                        EditorUI::PropertyVec3("Direction (from transform)",
                                               direction,
                                               0.0f,
                                               EditorUIConstants::kPositionStep,
                                               0.0f,
                                               0.0f,
                                               "%.3f",
                                               false,
                                               true);
                        ImGui::EndDisabled();
                        bool castsShadowsBool = castsShadows != 0;
                        EditorUI::SetNextPropertyInfoTooltip("Enables shadow casting for this directional light.\nUnits: boolean.\nPerformance: medium-to-high GPU cost.\nPersistence: Scene.");
                        if (EditorUI::PropertyBool("Casts Shadows", &castsShadowsBool)) {
                            castsShadows = castsShadowsBool ? 1 : 0;
                            dirty = true;
                        }
                    } else {
                        ImGui::BeginDisabled(true);
                        bool unsupportedShadows = false;
                        EditorUI::SetNextPropertyInfoTooltip("Point and spot shadows are unsupported in Phase 2. This control is informational only.");
                        EditorUI::PropertyBool("Shadows (unsupported)", &unsupportedShadows);
                        ImGui::EndDisabled();
                    }
                    EditorUI::EndPropertyTable();
                }
                if (dirty) {
                    MCEEditorSetLight(context, selectedEntityId, type, colorX, colorY, colorZ, brightness, range, innerCos, outerCos, dirX, dirY, dirZ, castsShadows);
                }
            }
        }
    }

    if (hasValidEntity && MCEEditorEntityHasComponent(context, selectedEntityId, ComponentReflectionProbe) != 0) {
        bool probeOpen = EditorUI::BeginSectionWithContext(context,
            "Reflection Probe",
            "Inspector.ReflectionProbe",
            "ReflectionProbeContext",
            [&]() {
                if (ImGui::MenuItem("Reset")) {
                    MCEEditorSetReflectionProbe(context, selectedEntityId, 1, 5.0f, 5.0f, 5.0f, 1.0f, 0, 1.0f, 128, 1, 1);
                }
                if (ImGui::MenuItem("Remove")) {
                    MCEEditorRemoveComponent(context, selectedEntityId, ComponentReflectionProbe);
                }
            },
            true);
        if (probeOpen) {
            uint32_t enabled = 1;
            float boxExtentsX = 5.0f, boxExtentsY = 5.0f, boxExtentsZ = 5.0f;
            float blendDistance = 1.0f;
            int32_t priority = 0;
            float intensity = 1.0f;
            int32_t captureResolution = 128;
            int32_t rebuildMode = 1;
            uint32_t includeSky = 1;
            if (MCEEditorGetReflectionProbe(context, selectedEntityId, &enabled, &boxExtentsX, &boxExtentsY, &boxExtentsZ, &blendDistance, &priority, &intensity, &captureResolution, &rebuildMode, &includeSky) != 0) {
                bool dirty = false;
                bool enabledBool = enabled != 0;
                bool includeSkyBool = includeSky != 0;
                float boxExtents[3] = {boxExtentsX, boxExtentsY, boxExtentsZ};
                int priorityValue = static_cast<int>(priority);
                constexpr int kReflectionProbePriorityMin = -1024;
                constexpr int kReflectionProbePriorityMax = 1024;
                const char *rebuildModes[] = {"Manual", "On Play"};
                int rebuildModeIndex = rebuildMode <= 0 ? 0 : 1;
                const int captureResolutionOptions[] = {64, 128, 256, 512};
                const char *captureResolutionLabels[] = {"64", "128", "256", "512"};
                int captureResolutionIndex = 1;
                for (int optionIndex = 0; optionIndex < IM_ARRAYSIZE(captureResolutionOptions); ++optionIndex) {
                    if (captureResolution == captureResolutionOptions[optionIndex]) {
                        captureResolutionIndex = optionIndex;
                        break;
                    }
                }

                if (EditorUI::BeginPropertyTable("ReflectionProbeProps")) {
                    dirty |= EditorUI::PropertyBool("Enabled", &enabledBool);
                    dirty |= EditorUI::PropertyVec3("Box Extents",
                                                    boxExtents,
                                                    5.0f,
                                                    EditorUIConstants::kPositionStep,
                                                    0.0f,
                                                    0.0f,
                                                    "%.3f",
                                                    false,
                                                    true);
                    dirty |= EditorUI::PropertyFloat("Blend Distance", &blendDistance, 0.1f, 0.0f, 100.0f, "%.2f", true, true, 1.0f);
                    if (EditorUI::PropertyInt("Priority",
                                              &priorityValue,
                                              kReflectionProbePriorityMin,
                                              kReflectionProbePriorityMax)) {
                        priority = static_cast<int32_t>(priorityValue);
                        dirty = true;
                    }
                    if (EditorUI::PropertyCombo("Capture Resolution", &captureResolutionIndex, captureResolutionLabels, IM_ARRAYSIZE(captureResolutionLabels))) {
                        captureResolution = captureResolutionOptions[captureResolutionIndex];
                        dirty = true;
                    }
                    dirty |= EditorUI::PropertyBool("Include Sky", &includeSkyBool);
                    if (EditorUI::PropertyCombo("Rebuild Mode", &rebuildModeIndex, rebuildModes, IM_ARRAYSIZE(rebuildModes))) {
                        rebuildMode = rebuildModeIndex == 0 ? 0 : 1;
                        dirty = true;
                    }
                    EditorUI::EndPropertyTable();
                }

                if (ImGui::TreeNodeEx("ReflectionProbeAdvanced", ImGuiTreeNodeFlags_None, "Advanced")) {
                    ImGui::TextWrapped("Reflection probe intensity remains serialized for compatibility, but normal workflow derives probe brightness from the captured scene and sky.");
                    if (EditorUI::BeginPropertyTable("ReflectionProbeAdvancedProps")) {
                        dirty |= EditorUI::PropertyFloat("Legacy Intensity", &intensity, 0.1f, 0.0f, 100.0f, "%.2f", true, true, 1.0f);
                        EditorUI::EndPropertyTable();
                    }
                    ImGui::TreePop();
                }

                if (dirty) {
                    MCEEditorSetReflectionProbe(context,
                                                selectedEntityId,
                                                enabledBool ? 1u : 0u,
                                                boxExtents[0],
                                                boxExtents[1],
                                                boxExtents[2],
                                                blendDistance,
                                                priority,
                                                intensity,
                                                captureResolution,
                                                rebuildMode,
                                                includeSkyBool ? 1u : 0u);
                }
            }
        }
    }

    if (hasValidEntity && MCEEditorEntityHasComponent(context, selectedEntityId, ComponentEnvironment) != 0) {
        bool environmentOpen = EditorUI::BeginSectionWithContext(context,
            "Environment",
            "Inspector.Environment",
            "EnvironmentContext",
            [&]() {
                if (ImGui::MenuItem("Remove")) {
                    MCEEditorRemoveComponent(context, selectedEntityId, ComponentEnvironment);
                }
            },
            true);
        if (environmentOpen) {
            int32_t lookPreset = 0;
            float lookMood = 0.0f;
            float lookWarmth = 0.0f;
            float lookCinematicAmount = 0.0f;
            uint32_t enabled = 1;
            int32_t sourceMode = 1;
            char hdriHandle[64] = {0};
            float defaultTimeOfDay = 14.0f;
            float previewTimeOfDay = 14.0f;
            float moonIntensity = 0.18f;
            float moonSizeDegrees = 0.54f;
            float starIntensity = 0.75f;
            float starRichness = 1.0f;
            float milkyWayIntensity = 1.0f;
            float milkyWayChroma = 1.0f;
            float milkyWayRotation = 0.0f;
            float nightBrightness = 1.0f;
            int32_t weatherPrimary = AtmosphereWeatherClear;
            int32_t weatherSecondary = AtmosphereWeatherClear;
            float weatherBlend = 0.0f;
            float weatherAmount = 0.0f;
            float atmosphereAmount = 0.28f;
            float atmosphereHaze = 0.28f;
            float atmosphereDensity = 1.0f;
            float atmosphereTemperature = 0.0f;
            float atmosphereMood = 0.0f;
            float cloudCoverage = 0.30f;
            int32_t cloudStyle = AtmosphereCloudPuffy;
            int32_t cloudRenderMode = 0;
            float fogAmount = 0.03f;
            float fogHeight = 0.0f;
            float fogDistance = 3.0f;
            uint32_t realtimeUpdate = 0;
            uint32_t autoRebuildOnChange = 0;
            uint32_t needsRebuild = 0;
            uint32_t iblDirtyState = 0;
            uint32_t iblRebuildingState = 0;
            int32_t iblCurrentQuality = -1;
            int32_t iblLastBuiltQuality = -1;
            char iblFailureMessage[256] = {0};
            MCEEnvironmentLookBridge lookBridge = {};
            MCEEnvironmentSourceBridge sourceBridge = {};
            MCEEnvironmentTimeBridge timeBridge = {};
            MCEEnvironmentAtmosphereBridge atmosphereBridge = {};
            MCEEnvironmentCelestialBridge celestialBridge = {};
            MCEEnvironmentWeatherCloudBridge weatherCloudBridge = {};
            MCEEnvironmentFogBridge fogBridge = {};
            MCEEnvironmentIBLBridge iblBridge = {};

            if (MCEEditorGetEnvironmentLookBridge(context, selectedEntityId, &lookBridge) != 0 &&
                MCEEditorGetEnvironmentSourceBridge(context, selectedEntityId, &sourceBridge) != 0 &&
                MCEEditorGetEnvironmentTimeBridge(context, selectedEntityId, &timeBridge) != 0 &&
                MCEEditorGetEnvironmentAtmosphereBridge(context, selectedEntityId, &atmosphereBridge) != 0 &&
                MCEEditorGetEnvironmentCelestialBridge(context, selectedEntityId, &celestialBridge) != 0 &&
                MCEEditorGetEnvironmentWeatherCloudBridge(context, selectedEntityId, &weatherCloudBridge) != 0 &&
                MCEEditorGetEnvironmentFogBridge(context, selectedEntityId, &fogBridge) != 0 &&
                MCEEditorGetEnvironmentIBLStatusBridge(context, selectedEntityId, &iblBridge) != 0 &&
                MCEEditorGetEnvironmentSource(context, selectedEntityId, &enabled, &sourceMode, hdriHandle, sizeof(hdriHandle)) != 0 &&
                MCEEditorGetEnvironmentCelestial(context, selectedEntityId, &defaultTimeOfDay, &previewTimeOfDay, &moonIntensity, &moonSizeDegrees, &starIntensity) != 0 &&
                MCEEditorGetEnvironmentWeather(context, selectedEntityId, &weatherPrimary, &weatherSecondary, &weatherBlend, &weatherAmount) != 0 &&
                MCEEditorGetEnvironmentAtmosphere(context, selectedEntityId, &atmosphereAmount, &atmosphereHaze, &atmosphereDensity, &atmosphereTemperature, &atmosphereMood) != 0 &&
                MCEEditorGetEnvironmentClouds(context, selectedEntityId, &cloudCoverage, &cloudStyle) != 0 &&
                MCEEditorGetEnvironmentFog(context, selectedEntityId, &fogAmount, &fogHeight, &fogDistance) != 0 &&
                MCEEditorGetEnvironmentIBL(context, selectedEntityId,
                                           &realtimeUpdate,
                                           &autoRebuildOnChange,
                                           &needsRebuild,
                                           &iblDirtyState,
                                           &iblRebuildingState,
                                           &iblCurrentQuality,
                                           &iblLastBuiltQuality,
                                           iblFailureMessage,
                                           sizeof(iblFailureMessage)) != 0) {
                lookPreset = lookBridge.preset;
                lookMood = lookBridge.mood;
                lookWarmth = lookBridge.warmth;
                lookCinematicAmount = lookBridge.cinematicAmount;
                enabled = sourceBridge.enabled;
                sourceMode = sourceBridge.mode;
                defaultTimeOfDay = timeBridge.defaultTimeOfDay;
                previewTimeOfDay = timeBridge.previewTimeOfDay;
                moonIntensity = celestialBridge.moonIntensity;
                moonSizeDegrees = celestialBridge.moonSizeDegrees;
                starIntensity = celestialBridge.starIntensity;
                starRichness = celestialBridge.starRichness;
                milkyWayIntensity = celestialBridge.milkyWayIntensity;
                milkyWayChroma = celestialBridge.milkyWayChroma;
                milkyWayRotation = celestialBridge.milkyWayRotation;
                nightBrightness = celestialBridge.nightBrightness;
                weatherPrimary = weatherCloudBridge.weatherPrimary;
                weatherSecondary = weatherCloudBridge.weatherSecondary;
                weatherBlend = weatherCloudBridge.weatherBlend;
                weatherAmount = weatherCloudBridge.weatherAmount;
                atmosphereAmount = atmosphereBridge.amount;
                atmosphereHaze = atmosphereBridge.haze;
                atmosphereDensity = atmosphereBridge.density;
                atmosphereTemperature = atmosphereBridge.temperature;
                atmosphereMood = atmosphereBridge.mood;
                cloudCoverage = weatherCloudBridge.cloudCoverage;
                cloudStyle = weatherCloudBridge.cloudStyle;
                cloudRenderMode = weatherCloudBridge.cloudRenderMode;
                fogAmount = fogBridge.amount;
                fogHeight = fogBridge.height;
                fogDistance = fogBridge.distance;
                realtimeUpdate = iblBridge.realtimeUpdate;
                autoRebuildOnChange = iblBridge.autoRebuildOnChange;
                needsRebuild = iblBridge.needsRebuild;
                iblDirtyState = iblBridge.dirty;
                iblRebuildingState = iblBridge.isRebuilding;
                iblCurrentQuality = iblBridge.currentRebuildQuality;
                iblLastBuiltQuality = iblBridge.lastBuiltQuality;

                PendingSkyState &pending = GetPendingSkyState(state);
                if (strncmp(pending.entityId, selectedEntityId, sizeof(pending.entityId)) != 0) {
                    memset(&pending, 0, sizeof(pending));
                    strncpy(pending.entityId, selectedEntityId, sizeof(pending.entityId) - 1);
                }
                EnvironmentPickerState &envPicker = GetEnvironmentPickerState(state);
                const bool envPickerDirty = envPicker.didPick && (strcmp(envPicker.entityId, selectedEntityId) == 0);
                if (!envPickerDirty) {
                    strncpy(pending.hdriHandle, hdriHandle, sizeof(pending.hdriHandle) - 1);
                    pending.hdriHandle[sizeof(pending.hdriHandle) - 1] = 0;
                }
                char *editHdriHandle = pending.hdriHandle;

                int32_t editSourceMode = sourceMode;
                uint32_t editEnabled = enabled;
                float editDefaultTimeOfDay = defaultTimeOfDay;
                float editPreviewTimeOfDay = previewTimeOfDay;
                float editMoonIntensity = moonIntensity;
                float editMoonSizeDegrees = moonSizeDegrees;
                float editStarIntensity = starIntensity;
                float editStarRichness = starRichness;
                float editMilkyWayIntensity = milkyWayIntensity;
                float editMilkyWayChroma = milkyWayChroma;
                float editMilkyWayRotation = milkyWayRotation;
                float editNightBrightness = nightBrightness;
                int32_t editWeatherPrimary = weatherPrimary;
                int32_t editWeatherSecondary = weatherSecondary;
                float editWeatherBlend = weatherBlend;
                float editWeatherAmount = weatherAmount;
                float editAtmosphereAmount = atmosphereAmount;
                float editAtmosphereHaze = atmosphereHaze;
                float editAtmosphereDensity = atmosphereDensity;
                float editAtmosphereTemperature = atmosphereTemperature;
                float editAtmosphereMood = atmosphereMood;
                float editCloudCoverage = cloudCoverage;
                int32_t editCloudStyle = cloudStyle;
                int32_t editCloudRenderMode = cloudRenderMode;
                float editFogAmount = fogAmount;
                float editFogHeight = fogHeight;
                float editFogDistance = fogDistance;
                uint32_t editRealtimeUpdate = realtimeUpdate;
                uint32_t editAutoRebuildOnChange = autoRebuildOnChange;
                int32_t editLookPreset = lookPreset;

                const char *lookPresetNames[] = {"Custom", "Clear Noon", "Golden Hour", "Blue Hour", "Moonlit Night", "Starry Night", "Milky Way Night", "Foggy Morning", "Overcast", "Stormy"};
                const char *lookPresetDescriptions[] = {
                    "Custom authored environment.",
                    "Bright clear daytime environment.",
                    "Warm low-sun cinematic look.",
                    "Cool twilight transition.",
                    "Moon-dominant night sky.",
                    "Dark clear stars.",
                    "Deep night with galaxy focus.",
                    "Low sun and aerial fog.",
                    "Soft cloudy sky.",
                    "Dark dramatic clouds."
                };
                const char *sourceModeNames[] = {"HDRI", "Procedural"};
                const char *weatherTypeNames[] = {"Clear", "Partly Cloudy", "Overcast", "Storm", "Foggy", "Custom"};
                const char *cloudStyleNames[] = {"Clear", "Wispy", "Puffy", "Layered", "Overcast", "Storm", "Custom"};
                const char *cloudRenderModeNames[] = {"Both", "Procedural", "Cards"};
                const int lookPresetCount = IM_ARRAYSIZE(lookPresetNames);
                int lookPresetIndex = editLookPreset;
                if (lookPresetIndex < 0 || lookPresetIndex >= lookPresetCount) {
                    lookPresetIndex = 0;
                }
                const int sourceModeIndex = editSourceMode == 0 ? 0 : 1;
                const char *iblStatusLabel = "Ready";
                ImVec4 iblStatusColor = ImGui::GetStyleColorVec4(ImGuiCol_TextDisabled);
                if (iblRebuildingState != 0) {
                    iblStatusLabel = "Rebuilding";
                    iblStatusColor = ImVec4(0.4f, 0.7f, 1.0f, 1.0f);
                } else if (iblFailureMessage[0] != 0 || iblBridge.hasFailure != 0) {
                    iblStatusLabel = "Error";
                    iblStatusColor = ImVec4(1.0f, 0.35f, 0.3f, 1.0f);
                } else if (needsRebuild != 0 || iblDirtyState != 0) {
                    iblStatusLabel = "Dirty";
                    iblStatusColor = ImVec4(1.0f, 0.75f, 0.2f, 1.0f);
                }

                bool sourceDirty = false;
                bool celestialDirty = false;
                bool previewTimeDirty = false;
                bool weatherDirty = false;
                bool atmosphereDirty = false;
                bool cloudsDirty = false;
                bool fogDirty = false;
                bool iblDirty = false;

                ImGui::Spacing();
                ImGui::Text("Mode: %s", sourceModeNames[sourceModeIndex]);
                ImGui::SameLine();
                ImGui::TextDisabled("  Look: %s", lookPresetNames[lookPresetIndex]);
                ImGui::SameLine();
                ImGui::TextDisabled("  Time: %.2f", editPreviewTimeOfDay);
                ImGui::SameLine();
                ImGui::TextColored(iblStatusColor, "  IBL: %s", iblStatusLabel);
                if (iblFailureMessage[0] != 0 && ImGui::IsItemHovered()) {
                    ImGui::SetTooltip("%s", iblFailureMessage);
                }
                if (ImGui::Button("Rebuild IBL##EnvironmentSummary")) {
                    MCEEditorRequestEnvironmentIBLRebuild(context, selectedEntityId);
                }
                ImGui::SameLine();
                if (ImGui::Button("Reset Preview Time")) {
                    MCEEditorSetEnvironmentPreviewTime(context, selectedEntityId, editDefaultTimeOfDay);
                }

                ImGui::Spacing();
                ImGui::TextDisabled("Look");
                if (EditorUI::BeginPropertyTable("EnvironmentLookProps")) {
                    if (EditorUI::PropertyCombo("Preset", &editLookPreset, lookPresetNames, IM_ARRAYSIZE(lookPresetNames))) {
                        MCEEditorApplyEnvironmentPreset(context, selectedEntityId, editLookPreset);
                    }
                    bool lookDirty = false;
                    lookDirty |= EditorUI::PropertyFloat("Mood",
                                                         &lookMood,
                                                         0.02f,
                                                         -1.0f,
                                                         1.0f,
                                                         "%.2f",
                                                         true,
                                                         true,
                                                         0.0f);
                    lookDirty |= EditorUI::PropertyFloat("Warmth",
                                                         &lookWarmth,
                                                         0.02f,
                                                         -1.0f,
                                                         1.0f,
                                                         "%.2f",
                                                         true,
                                                         true,
                                                         0.0f);
                    lookDirty |= EditorUI::PropertyFloat("Cinematic",
                                                         &lookCinematicAmount,
                                                         0.02f,
                                                         0.0f,
                                                         1.0f,
                                                         "%.2f",
                                                         true,
                                                         true,
                                                         0.0f);
                    if (lookDirty) {
                        MCEEnvironmentLookBridge editLook = lookBridge;
                        editLook.preset = 0;
                        editLook.mood = lookMood;
                        editLook.warmth = lookWarmth;
                        editLook.cinematicAmount = lookCinematicAmount;
                        MCEEditorSetEnvironmentLookBridge(context, selectedEntityId, &editLook);
                    }
                    EditorUI::EndPropertyTable();
                }
                ImGui::TextWrapped("%s", lookPresetDescriptions[lookPresetIndex]);

                ImGui::Spacing();
                ImGui::TextDisabled("Lighting Source");
                if (EditorUI::BeginPropertyTable("EnvironmentSourceProps")) {
                    bool enabledBool = editEnabled != 0;
                    if (EditorUI::PropertyBool("Enabled", &enabledBool)) {
                        editEnabled = enabledBool ? 1 : 0;
                        sourceDirty = true;
                    }
                    sourceDirty |= EditorUI::PropertyCombo("Mode", &editSourceMode, sourceModeNames, IM_ARRAYSIZE(sourceModeNames));
                    if (editSourceMode == 0) {
                        sourceDirty |= DrawEnvironmentHandleRow(context, state, "HDRI", editHdriHandle, sizeof(pending.hdriHandle), "MCE_ASSET_ENVIRONMENT", selectedEntityId);
                    }
                    EditorUI::EndPropertyTable();
                }
                if (envPickerDirty) {
                    envPicker.didPick = false;
                    sourceDirty = true;
                }

                ImGui::Spacing();
                ImGui::TextDisabled("Time & Sun");
                if (EditorUI::BeginPropertyTable("EnvironmentCelestialProps")) {
                    celestialDirty |= EditorUI::PropertyFloat("Default Time",
                                                              &editDefaultTimeOfDay,
                                                              0.1f,
                                                              0.0f,
                                                              24.0f,
                                                              "%.2f",
                                                              true,
                                                              true,
                                                              14.0f);
                    previewTimeDirty |= EditorUI::PropertyFloat("Preview Time",
                                                                &editPreviewTimeOfDay,
                                                                0.1f,
                                                                0.0f,
                                                                24.0f,
                                                                "%.2f",
                                                                true,
                                                                true,
                                                                editDefaultTimeOfDay);
                    EditorUI::EndPropertyTable();
                }

                ImGui::Spacing();
                ImGui::TextDisabled("Celestial / Night");
                if (EditorUI::BeginPropertyTable("EnvironmentNightProps")) {
                    celestialDirty |= EditorUI::PropertyFloat("Moon Intensity",
                                                              &editMoonIntensity,
                                                              0.01f,
                                                              0.0f,
                                                              10.0f,
                                                              "%.2f",
                                                              true,
                                                              true,
                                                              0.18f);
                    celestialDirty |= EditorUI::PropertyFloat("Moon Size",
                                                              &editMoonSizeDegrees,
                                                              0.01f,
                                                              0.01f,
                                                              5.0f,
                                                              "%.2f",
                                                              true,
                                                              true,
                                                              0.54f);
                    celestialDirty |= EditorUI::PropertyFloat("Star Visibility",
                                                              &editStarIntensity,
                                                              0.01f,
                                                              0.0f,
                                                              10.0f,
                                                              "%.2f",
                                                              true,
                                                              true,
                                                              0.75f);
                    celestialDirty |= EditorUI::PropertyFloat("Star Richness",
                                                              &editStarRichness,
                                                              0.02f,
                                                              0.0f,
                                                              3.0f,
                                                              "%.2f",
                                                              true,
                                                              true,
                                                              1.0f);
                    celestialDirty |= EditorUI::PropertyFloat("Milky Way Intensity",
                                                              &editMilkyWayIntensity,
                                                              0.02f,
                                                              0.0f,
                                                              3.0f,
                                                              "%.2f",
                                                              true,
                                                              true,
                                                              1.0f);
                    celestialDirty |= EditorUI::PropertyFloat("Milky Way Chroma",
                                                              &editMilkyWayChroma,
                                                              0.02f,
                                                              0.0f,
                                                              3.0f,
                                                              "%.2f",
                                                              true,
                                                              true,
                                                              1.0f);
                    celestialDirty |= EditorUI::PropertyFloat("Milky Way Rotation",
                                                              &editMilkyWayRotation,
                                                              0.01f,
                                                              -1.0f,
                                                              1.0f,
                                                              "%.2f",
                                                              true,
                                                              true,
                                                              0.0f);
                    celestialDirty |= EditorUI::PropertyFloat("Night Brightness",
                                                              &editNightBrightness,
                                                              0.02f,
                                                              0.0f,
                                                              3.0f,
                                                              "%.2f",
                                                              true,
                                                              true,
                                                              1.0f);
                    EditorUI::EndPropertyTable();
                }
                ImGui::TextDisabled("Moon texture and Milky Way texture use built-in runtime assets.");

                ImGui::Spacing();
                ImGui::TextDisabled("Weather / Clouds");
                if (EditorUI::BeginPropertyTable("EnvironmentWeatherProps")) {
                    weatherDirty |= EditorUI::PropertyCombo("Weather", &editWeatherPrimary, weatherTypeNames, IM_ARRAYSIZE(weatherTypeNames));
                    weatherDirty |= EditorUI::PropertyCombo("Blend To", &editWeatherSecondary, weatherTypeNames, IM_ARRAYSIZE(weatherTypeNames));
                    weatherDirty |= EditorUI::PropertyFloat("Blend",
                                                            &editWeatherBlend,
                                                            0.02f,
                                                            0.0f,
                                                            1.0f,
                                                            "%.2f",
                                                            true,
                                                            true,
                                                            0.0f);
                    weatherDirty |= EditorUI::PropertyFloat("Amount",
                                                            &editWeatherAmount,
                                                            0.02f,
                                                            0.0f,
                                                            1.0f,
                                                            "%.2f",
                                                            true,
                                                            true,
                                                            0.0f);
                    cloudsDirty |= EditorUI::PropertyFloat("Coverage",
                                                           &editCloudCoverage,
                                                           0.02f,
                                                           0.0f,
                                                           1.0f,
                                                           "%.2f",
                                                           true,
                                                           true,
                                                           0.30f);
                    cloudsDirty |= EditorUI::PropertyCombo("Render Mode", &editCloudRenderMode, cloudRenderModeNames, IM_ARRAYSIZE(cloudRenderModeNames));
                    cloudsDirty |= EditorUI::PropertyCombo("Style", &editCloudStyle, cloudStyleNames, IM_ARRAYSIZE(cloudStyleNames));
                    EditorUI::EndPropertyTable();
                }

                ImGui::Spacing();
                ImGui::TextDisabled("Atmosphere");
                if (EditorUI::BeginPropertyTable("EnvironmentAtmosphereProps")) {
                    atmosphereDirty |= EditorUI::PropertyFloat("Atmosphere",
                                                               &editAtmosphereAmount,
                                                               0.02f,
                                                               0.0f,
                                                               1.0f,
                                                               "%.2f",
                                                               true,
                                                               true,
                                                               0.28f);
                    atmosphereDirty |= EditorUI::PropertyFloat("Haze",
                                                               &editAtmosphereHaze,
                                                               0.02f,
                                                               0.0f,
                                                               1.0f,
                                                               "%.2f",
                                                               true,
                                                               true,
                                                               0.28f);
                    atmosphereDirty |= EditorUI::PropertyFloat("Horizon Depth",
                                                               &editAtmosphereDensity,
                                                               0.02f,
                                                               0.0f,
                                                               10.0f,
                                                               "%.2f",
                                                               true,
                                                               true,
                                                               1.0f);
                    atmosphereDirty |= EditorUI::PropertyFloat("Temperature",
                                                               &editAtmosphereTemperature,
                                                               0.02f,
                                                               -1.0f,
                                                               1.0f,
                                                               "%.2f",
                                                               true,
                                                               true,
                                                               0.0f);
                    atmosphereDirty |= EditorUI::PropertyFloat("Mood Bias",
                                                               &editAtmosphereMood,
                                                               0.02f,
                                                               -1.0f,
                                                               1.0f,
                                                               "%.2f",
                                                               true,
                                                               true,
                                                               0.0f);
                    EditorUI::EndPropertyTable();
                }

                ImGui::Spacing();
                ImGui::TextDisabled("Fog / Aerial Perspective");
                if (EditorUI::BeginPropertyTable("EnvironmentFogProps")) {
                    fogDirty |= EditorUI::PropertyFloat("Fog Amount",
                                                        &editFogAmount,
                                                        0.005f,
                                                        0.0f,
                                                        1.0f,
                                                        "%.3f",
                                                        true,
                                                        true,
                                                        0.03f);
                    fogDirty |= EditorUI::PropertyFloat("Height",
                                                        &editFogHeight,
                                                        0.1f,
                                                        -1000.0f,
                                                        1000.0f,
                                                        "%.2f",
                                                        true,
                                                        true,
                                                        0.0f);
                    fogDirty |= EditorUI::PropertyFloat("Distance",
                                                        &editFogDistance,
                                                        0.1f,
                                                        0.0f,
                                                        1000.0f,
                                                        "%.2f",
                                                        true,
                                                        true,
                                                        3.0f);
                    EditorUI::EndPropertyTable();
                }

                ImGui::Spacing();
                ImGui::TextDisabled("Lighting / IBL");
                bool realtimeBool = editRealtimeUpdate != 0;
                if (ImGui::Checkbox("Realtime Update", &realtimeBool)) {
                    editRealtimeUpdate = realtimeBool ? 1 : 0;
                    iblDirty = true;
                }
                ImGui::SameLine();
                bool autoRebuildBool = editAutoRebuildOnChange != 0;
                if (ImGui::Checkbox("Auto Rebuild", &autoRebuildBool)) {
                    editAutoRebuildOnChange = autoRebuildBool ? 1 : 0;
                    iblDirty = true;
                }
                if (ImGui::Button("Rebuild IBL##EnvironmentLighting")) {
                    MCEEditorRequestEnvironmentIBLRebuild(context, selectedEntityId);
                }
                if (iblRebuildingState != 0) {
                    ImGui::SameLine();
                    const char *qualityLabel = iblCurrentQuality == 0 ? "interactive" : (iblCurrentQuality == 1 ? "final" : "unknown");
                    ImGui::TextColored(ImVec4(0.4f, 0.7f, 1.0f, 1.0f), "IBL rebuilding (%s).", qualityLabel);
                } else if (iblFailureMessage[0] != 0) {
                    ImGui::SameLine();
                    ImGui::TextColored(ImVec4(1.0f, 0.35f, 0.3f, 1.0f), "IBL error.");
                    if (ImGui::IsItemHovered()) {
                        ImGui::SetTooltip("%s", iblFailureMessage);
                    }
                } else if (needsRebuild != 0 || iblDirtyState != 0) {
                    ImGui::SameLine();
                    ImGui::TextColored(ImVec4(1.0f, 0.75f, 0.2f, 1.0f), "IBL rebuild required.");
                } else {
                    ImGui::SameLine();
                    if (iblLastBuiltQuality == 0) {
                        ImGui::TextDisabled("IBL ready (interactive).");
                    } else if (iblLastBuiltQuality == 1) {
                        ImGui::TextDisabled("IBL ready (final).");
                    } else {
                        ImGui::TextDisabled("IBL ready.");
                    }
                }

                if (ImGui::TreeNodeEx("EnvironmentAdvanced", ImGuiTreeNodeFlags_None, "Advanced / Debug")) {
                    ImGui::TextWrapped("Runtime preview state and IBL rebuild state are transient. Raw timing controls are shown here for diagnostics.");
                    MCEEnvironmentTimeBridge editTime = timeBridge;
                    bool timeRuntimeDirty = false;
                    if (EditorUI::BeginPropertyTable("EnvironmentAdvancedProps")) {
                        int timeMode = editTime.timeControlMode;
                        timeRuntimeDirty |= EditorUI::PropertyInt("Time Mode", &timeMode, 0, 2);
                        editTime.timeControlMode = timeMode;
                        timeRuntimeDirty |= EditorUI::PropertyFloat("Day Length",
                                                                    &editTime.dayLengthSeconds,
                                                                    1.0f,
                                                                    1.0f,
                                                                    86400.0f,
                                                                    "%.1f",
                                                                    true,
                                                                    true,
                                                                    300.0f);
                        timeRuntimeDirty |= EditorUI::PropertyFloat("Time Scale",
                                                                    &editTime.timeScale,
                                                                    0.1f,
                                                                    -100.0f,
                                                                    100.0f,
                                                                    "%.2f",
                                                                    true,
                                                                    true,
                                                                    1.0f);
                        EditorUI::EndPropertyTable();
                    }
                    if (timeRuntimeDirty) {
                        MCEEditorSetEnvironmentTimeBridge(context, selectedEntityId, &editTime);
                    }
                    ImGui::TreePop();
                }

                if (sourceDirty) {
                    MCEEditorSetEnvironmentSource(context, selectedEntityId, editEnabled, editSourceMode, editHdriHandle);
                }
                if (celestialDirty) {
                    MCEEnvironmentTimeBridge editTime = timeBridge;
                    editTime.defaultTimeOfDay = editDefaultTimeOfDay;
                    editTime.previewTimeOfDay = editPreviewTimeOfDay;
                    MCEEditorSetEnvironmentTimeBridge(context, selectedEntityId, &editTime);
                    MCEEnvironmentCelestialBridge editCelestial = celestialBridge;
                    editCelestial.moonIntensity = editMoonIntensity;
                    editCelestial.moonSizeDegrees = editMoonSizeDegrees;
                    editCelestial.starIntensity = editStarIntensity;
                    editCelestial.starRichness = editStarRichness;
                    editCelestial.milkyWayIntensity = editMilkyWayIntensity;
                    editCelestial.milkyWayChroma = editMilkyWayChroma;
                    editCelestial.milkyWayRotation = editMilkyWayRotation;
                    editCelestial.nightBrightness = editNightBrightness;
                    MCEEditorSetEnvironmentCelestialBridge(context, selectedEntityId, &editCelestial);
                }
                if (previewTimeDirty) {
                    MCEEditorSetEnvironmentPreviewTime(context, selectedEntityId, editPreviewTimeOfDay);
                }
                if (weatherDirty || cloudsDirty) {
                    MCEEnvironmentWeatherCloudBridge editWeatherCloud = weatherCloudBridge;
                    editWeatherCloud.weatherPrimary = editWeatherPrimary;
                    editWeatherCloud.weatherSecondary = editWeatherSecondary;
                    editWeatherCloud.weatherBlend = editWeatherBlend;
                    editWeatherCloud.weatherAmount = editWeatherAmount;
                    editWeatherCloud.cloudCoverage = editCloudCoverage;
                    editWeatherCloud.cloudStyle = editCloudStyle;
                    editWeatherCloud.cloudRenderMode = editCloudRenderMode;
                    MCEEditorSetEnvironmentWeatherCloudBridge(context, selectedEntityId, &editWeatherCloud);
                }
                if (atmosphereDirty) {
                    MCEEnvironmentAtmosphereBridge editAtmosphere = atmosphereBridge;
                    editAtmosphere.amount = editAtmosphereAmount;
                    editAtmosphere.haze = editAtmosphereHaze;
                    editAtmosphere.density = editAtmosphereDensity;
                    editAtmosphere.temperature = editAtmosphereTemperature;
                    editAtmosphere.mood = editAtmosphereMood;
                    MCEEditorSetEnvironmentAtmosphereBridge(context, selectedEntityId, &editAtmosphere);
                }
                if (fogDirty) {
                    MCEEnvironmentFogBridge editFog = fogBridge;
                    editFog.amount = editFogAmount;
                    editFog.height = editFogHeight;
                    editFog.distance = editFogDistance;
                    MCEEditorSetEnvironmentFogBridge(context, selectedEntityId, &editFog);
                }
                if (iblDirty) {
                    MCEEnvironmentIBLBridge editIBL = iblBridge;
                    editIBL.realtimeUpdate = editRealtimeUpdate;
                    editIBL.autoRebuildOnChange = editAutoRebuildOnChange;
                    MCEEditorSetEnvironmentIBLConfigBridge(context, selectedEntityId, &editIBL);
                }
            }
        }
    }

    if (hasValidEntity && MCEEditorEntityHasComponent(context, selectedEntityId, ComponentSkyLight) != 0) {
        bool skyOpen = EditorUI::BeginSectionWithContext(context, 
            "Sky",
            "Inspector.Sky",
            "SkyContext",
            [&]() {
                if (ImGui::MenuItem("Reset")) {
                    const char *empty = "";
                    MCEEditorSetSkyLight(context, selectedEntityId, 0, 1,
                                         14.0f,
                                         AtmosphereWeatherClear,
                                         AtmosphereWeatherClear,
                                         0.0f,
                                         0.0f,
                                         0.28f,
                                         0.30f,
                                         AtmosphereCloudPuffy,
                                         0.0f,
                                         0.0f,
                                         1.0f, 1.0f, 1.0f, 1.0f,
                                         2.0f, 0.0f, 30.0f,
                                         EditorUIConstants::kDefaultSkySunSize,
                                         0.24f, 0.45f, 0.95f,
                                         0.95f, 0.75f, 0.55f,
                                         EditorUIConstants::kDefaultSkyGradientStrength,
                                         EditorUIConstants::kDefaultSkyHazeDensity,
                                         EditorUIConstants::kDefaultSkyHazeFalloff,
                                         EditorUIConstants::kDefaultSkyHazeHeight,
                                         EditorUIConstants::kDefaultSkyOzoneStrength,
                                         0.55f, 0.7f, 1.0f,
                                         EditorUIConstants::kDefaultSkySunHaloSize,
                                         EditorUIConstants::kDefaultSkySunHaloIntensity,
                                         EditorUIConstants::kDefaultSkySunHaloSoftness,
                                         0,
                                         EditorUIConstants::kDefaultCloudCoverage,
                                         EditorUIConstants::kDefaultCloudSoftness,
                                         EditorUIConstants::kDefaultCloudScale,
                                         EditorUIConstants::kDefaultCloudSpeed,
                                         EditorUIConstants::kDefaultCloudWindX,
                                         EditorUIConstants::kDefaultCloudWindY,
                                         EditorUIConstants::kDefaultCloudHeight,
                                         EditorUIConstants::kDefaultCloudThickness,
                                         EditorUIConstants::kDefaultCloudBrightness,
                                         EditorUIConstants::kDefaultCloudSunInfluence,
                                         0.03f,
                                         0.0f,
                                         3.0f,
                                         1,
                                         empty);
                }
                if (ImGui::MenuItem("Remove")) {
                    MCEEditorRemoveComponent(context, selectedEntityId, ComponentSkyLight);
                }
            },
            true);
        if (skyOpen) {
            int32_t skyCount = MCEEditorSkyEntityCount(context);
            if (skyCount > 1) {
                ImGui::TextColored(ImVec4(1.0f, 0.75f, 0.2f, 1.0f), "Warning: multiple Sky entities exist. Only one is active.");
            }
            char activeSky[64] = {0};
            bool isActive = (MCEEditorGetActiveSkyId(context, activeSky, sizeof(activeSky)) > 0) && (strcmp(activeSky, selectedEntityId) == 0);
            ImGui::Text("Active: %s", isActive ? "Yes" : "No");
            if (!isActive) {
                if (ImGui::Button("Set as Active Sky")) {
                    MCEEditorSetActiveSky(context, selectedEntityId);
                }
            }

            int32_t mode = 0;
            uint32_t enabled = 1;
            float timeOfDay = 14.0f;
            int32_t weatherType = AtmosphereWeatherClear;
            int32_t secondaryWeatherType = AtmosphereWeatherClear;
            float weatherBlend = 0.0f;
            float weatherAmount = 0.0f;
            float atmosphereAmount = 0.28f;
            float cloudCoverage = 0.30f;
            int32_t cloudStyle = AtmosphereCloudPuffy;
            float temperature = 0.0f;
            float mood = 0.0f;
            float intensity = 1.0f;
            float tintX = 1.0f, tintY = 1.0f, tintZ = 1.0f;
            float turbidity = 2.0f;
            float azimuth = 0.0f;
            float elevation = 30.0f;
            char hdriHandle[64] = {0};
            float sunSize = 0.535f;
            float zenithTintX = 0.24f, zenithTintY = 0.45f, zenithTintZ = 0.95f;
            float horizonTintX = 0.95f, horizonTintY = 0.75f, horizonTintZ = 0.55f;
            float gradientStrength = 1.0f;
            float hazeDensity = 0.35f;
            float hazeFalloff = 2.2f;
            float hazeHeight = 0.0f;
            float ozoneStrength = 0.35f;
            float ozoneTintX = 0.55f, ozoneTintY = 0.7f, ozoneTintZ = 1.0f;
            float sunHaloSize = 2.5f;
            float sunHaloIntensity = 0.5f;
            float sunHaloSoftness = 1.2f;
            uint32_t cloudsEnabled = 0;
            float cloudsCoverage = 0.35f;
            float cloudsSoftness = 0.6f;
            float cloudsScale = 1.0f;
            float cloudsSpeed = 0.02f;
            float cloudsWindX = 1.0f;
            float cloudsWindY = 0.0f;
            float cloudsHeight = 0.25f;
            float cloudsThickness = 0.35f;
            float cloudsBrightness = 1.0f;
            float cloudsSunInfluence = 1.0f;
            float fogAmount = 0.03f;
            float fogHeight = 0.0f;
            float fogDistance = 3.0f;
            uint32_t autoRebuild = 1;
            uint32_t needsRebuild = 0;
            if (MCEEditorGetSkyLight(context, selectedEntityId, &mode, &enabled,
                                     &timeOfDay, &weatherType, &secondaryWeatherType, &weatherBlend, &weatherAmount,
                                     &atmosphereAmount, &cloudCoverage, &cloudStyle,
                                     &temperature, &mood,
                                     &intensity, &tintX, &tintY, &tintZ,
                                     &turbidity, &azimuth, &elevation, &sunSize,
                                     &zenithTintX, &zenithTintY, &zenithTintZ,
                                     &horizonTintX, &horizonTintY, &horizonTintZ,
                                     &gradientStrength,
                                     &hazeDensity, &hazeFalloff, &hazeHeight,
                                     &ozoneStrength, &ozoneTintX, &ozoneTintY, &ozoneTintZ,
                                     &sunHaloSize, &sunHaloIntensity, &sunHaloSoftness,
                                     &cloudsEnabled, &cloudsCoverage, &cloudsSoftness,
                                     &cloudsScale, &cloudsSpeed,
                                     &cloudsWindX, &cloudsWindY,
                                     &cloudsHeight, &cloudsThickness,
                                     &cloudsBrightness, &cloudsSunInfluence,
                                     &fogAmount, &fogHeight, &fogDistance,
                                     &autoRebuild, &needsRebuild,
                                     hdriHandle, sizeof(hdriHandle)) != 0) {
                const char* modes[] = {"HDRI", "Procedural"};
                PendingSkyState &pending = GetPendingSkyState(state);
                if (strncmp(pending.entityId, selectedEntityId, sizeof(pending.entityId)) != 0) {
                    memset(&pending, 0, sizeof(pending));
                    strncpy(pending.entityId, selectedEntityId, sizeof(pending.entityId) - 1);
                }

                int32_t editMode = mode;
                uint32_t editEnabled = enabled;
                float editTimeOfDay = timeOfDay;
                int32_t editWeatherType = weatherType;
                int32_t editSecondaryWeatherType = secondaryWeatherType;
                float editWeatherBlend = weatherBlend;
                float editWeatherAmount = weatherAmount;
                float editAtmosphereAmount = atmosphereAmount;
                float editCloudCoverage = cloudCoverage;
                int32_t editCloudStyle = cloudStyle;
                float editTemperature = temperature;
                float editMood = mood;
                float editIntensity = intensity;
                float editTintX = tintX;
                float editTintY = tintY;
                float editTintZ = tintZ;
                float editTurbidity = turbidity;
                float editAzimuth = azimuth;
                float editElevation = elevation;
                float editSunSize = sunSize;
                float editZenithTintX = zenithTintX;
                float editZenithTintY = zenithTintY;
                float editZenithTintZ = zenithTintZ;
                float editHorizonTintX = horizonTintX;
                float editHorizonTintY = horizonTintY;
                float editHorizonTintZ = horizonTintZ;
                float editGradientStrength = gradientStrength;
                float editHazeDensity = hazeDensity;
                float editHazeFalloff = hazeFalloff;
                float editHazeHeight = hazeHeight;
                float editOzoneStrength = ozoneStrength;
                float editOzoneTintX = ozoneTintX;
                float editOzoneTintY = ozoneTintY;
                float editOzoneTintZ = ozoneTintZ;
                float editSunHaloSize = sunHaloSize;
                float editSunHaloIntensity = sunHaloIntensity;
                float editSunHaloSoftness = sunHaloSoftness;
                uint32_t editCloudsEnabled = cloudsEnabled;
                float editCloudsCoverage = cloudsCoverage;
                float editCloudsSoftness = cloudsSoftness;
                float editCloudsScale = cloudsScale;
                float editCloudsSpeed = cloudsSpeed;
                float editCloudsWindX = cloudsWindX;
                float editCloudsWindY = cloudsWindY;
                float editCloudsHeight = cloudsHeight;
                float editCloudsThickness = cloudsThickness;
                float editCloudsBrightness = cloudsBrightness;
                float editCloudsSunInfluence = cloudsSunInfluence;
                float editFogAmount = fogAmount;
                float editFogHeight = fogHeight;
                float editFogDistance = fogDistance;
                EnvironmentPickerState &envPicker = GetEnvironmentPickerState(state);
                const bool envPickerDirty = envPicker.didPick && (strcmp(envPicker.entityId, selectedEntityId) == 0);
                if (!envPickerDirty) {
                    strncpy(pending.hdriHandle, hdriHandle, sizeof(pending.hdriHandle) - 1);
                    pending.hdriHandle[sizeof(pending.hdriHandle) - 1] = 0;
                }
                char *editHdriHandle = pending.hdriHandle;

                bool dirty = false;
                int presetIndex = pending.presetIndex;
                if (presetIndex < 0 || presetIndex >= IM_ARRAYSIZE(kSkyPresetNames)) {
                    presetIndex = 0;
                    pending.presetIndex = 0;
                }

                auto applyPresetToEdits = [&](const AtmospherePreset &preset) {
                    editMode = preset.mode;
                    editEnabled = preset.enabled;
                    editTimeOfDay = preset.timeOfDay;
                    editWeatherType = preset.primaryWeatherType;
                    editSecondaryWeatherType = preset.secondaryWeatherType;
                    editWeatherBlend = preset.weatherBlend;
                    editWeatherAmount = preset.weatherAmount;
                    editAtmosphereAmount = preset.atmosphereAmount;
                    editCloudCoverage = preset.cloudCoverage;
                    editCloudStyle = preset.cloudStyle;
                    editTemperature = preset.temperature;
                    editMood = preset.mood;
                    editFogAmount = preset.fogAmount;
                    editFogHeight = preset.fogHeight;
                    editFogDistance = preset.fogDistance;
                };

                const char *weatherTypeNames[] = {"Clear", "Partly Cloudy", "Overcast", "Storm", "Foggy", "Custom"};
                const char *cloudStyleNames[] = {"Clear", "Wispy", "Puffy", "Layered", "Overcast", "Storm", "Custom"};

                ImGui::Spacing();
                ImGui::TextDisabled("Sky Source");
                if (EditorUI::BeginPropertyTable("SkySourceProps")) {
                    bool enabledBool = editEnabled != 0;
                    if (EditorUI::PropertyBool("Enabled", &enabledBool)) {
                        editEnabled = enabledBool ? 1 : 0;
                        dirty = true;
                    }
                    dirty |= EditorUI::PropertyCombo("Mode", &editMode, modes, IM_ARRAYSIZE(modes));
                    if (editMode == 0) {
                        dirty |= DrawEnvironmentHandleRow(context, state, "HDRI", editHdriHandle, sizeof(pending.hdriHandle), "MCE_ASSET_ENVIRONMENT", selectedEntityId);
                    }
                    EditorUI::EndPropertyTable();
                }

                if (editMode == 1) {
                    ImGui::Spacing();
                    ImGui::TextDisabled("Atmosphere State");
                    if (EditorUI::BeginPropertyTable("SkyPresetProps")) {
                        if (EditorUI::PropertyCombo("Preset", &presetIndex, kSkyPresetNames, IM_ARRAYSIZE(kSkyPresetNames))) {
                            pending.presetIndex = presetIndex;
                        }
                        EditorUI::EndPropertyTable();
                    }
                    if (ImGui::Button("Apply Preset")) {
                        applyPresetToEdits(kSkyPresets[presetIndex]);
                        dirty = true;
                    }
                    ImGui::SameLine();
                    if (ImGui::Button("Randomize Slightly")) {
                        editTimeOfDay = ClampFloat(editTimeOfDay + RandomRange(-1.0f, 1.0f), 0.0f, 24.0f);
                        editWeatherBlend = ClampFloat(editWeatherBlend + RandomRange(-0.12f, 0.12f), 0.0f, 1.0f);
                        editWeatherAmount = ClampFloat(editWeatherAmount + RandomRange(-0.15f, 0.15f), 0.0f, 1.0f);
                        editAtmosphereAmount = ClampFloat(editAtmosphereAmount + RandomRange(-0.1f, 0.1f), 0.0f, 1.0f);
                        editCloudCoverage = ClampFloat(editCloudCoverage + RandomRange(-0.12f, 0.12f), 0.0f, 1.0f);
                        editTemperature = ClampFloat(editTemperature + RandomRange(-0.15f, 0.15f), -1.0f, 1.0f);
                        editMood = ClampFloat(editMood + RandomRange(-0.15f, 0.15f), -1.0f, 1.0f);
                        editFogAmount = ClampFloat(editFogAmount + RandomRange(-0.015f, 0.015f), 0.0f, 1.0f);
                        dirty = true;
                    }
                    ImGui::TextWrapped("Author the atmosphere here. The editor now writes authored sky state and synchronized runtime preview state; live simulation owns time, weather progression, and cloud motion once play starts.");

                    ImGui::Spacing();
                    ImGui::TextDisabled("Atmosphere");
                    if (EditorUI::BeginPropertyTable("SkyPublicProps")) {
                        dirty |= EditorUI::PropertyFloat("Time of Day",
                                                         &editTimeOfDay,
                                                         0.1f,
                                                         0.0f,
                                                         24.0f,
                                                         "%.2f",
                                                         true,
                                                         true,
                                                         14.0f);
                        dirty |= EditorUI::PropertyCombo("Weather Type", &editWeatherType, weatherTypeNames, IM_ARRAYSIZE(weatherTypeNames));
                        dirty |= EditorUI::PropertyCombo("Blend To", &editSecondaryWeatherType, weatherTypeNames, IM_ARRAYSIZE(weatherTypeNames));
                        dirty |= EditorUI::PropertyFloat("Weather Blend",
                                                         &editWeatherBlend,
                                                         0.02f,
                                                         0.0f,
                                                         1.0f,
                                                         "%.2f",
                                                         true,
                                                         true,
                                                         0.0f);
                        dirty |= EditorUI::PropertyFloat("Weather Amount",
                                                         &editWeatherAmount,
                                                         0.02f,
                                                         0.0f,
                                                         1.0f,
                                                         "%.2f",
                                                         true,
                                                         true,
                                                         0.0f);
                        dirty |= EditorUI::PropertyFloat("Temperature",
                                                         &editTemperature,
                                                         0.02f,
                                                         -1.0f,
                                                         1.0f,
                                                         "%.2f",
                                                         true,
                                                         true,
                                                         0.0f);
                        dirty |= EditorUI::PropertyFloat("Mood",
                                                         &editMood,
                                                         0.02f,
                                                         -1.0f,
                                                         1.0f,
                                                         "%.2f",
                                                         true,
                                                         true,
                                                         0.0f);
                        dirty |= EditorUI::PropertyFloat("Atmosphere / Haze",
                                                         &editAtmosphereAmount,
                                                         0.02f,
                                                         0.0f,
                                                         1.0f,
                                                         "%.2f",
                                                         true,
                                                         true,
                                                         0.28f);
                        EditorUI::EndPropertyTable();
                    }

                    ImGui::Spacing();
                    ImGui::TextDisabled("Clouds");
                    if (EditorUI::BeginPropertyTable("SkyCloudProps")) {
                        dirty |= EditorUI::PropertyFloat("Cloud Coverage",
                                                         &editCloudCoverage,
                                                         0.02f,
                                                         0.0f,
                                                         1.0f,
                                                         "%.2f",
                                                         true,
                                                         true,
                                                         0.30f);
                        dirty |= EditorUI::PropertyCombo("Cloud Style", &editCloudStyle, cloudStyleNames, IM_ARRAYSIZE(cloudStyleNames));
                        EditorUI::EndPropertyTable();
                    }

                    ImGui::Spacing();
                    ImGui::TextDisabled("Fog");
                    if (EditorUI::BeginPropertyTable("SkyFogProps")) {
                        dirty |= EditorUI::PropertyFloat("Fog Amount",
                                                         &editFogAmount,
                                                         0.005f,
                                                         0.0f,
                                                         1.0f,
                                                         "%.3f",
                                                         true,
                                                         true,
                                                         0.03f);
                        dirty |= EditorUI::PropertyFloat("Fog Height",
                                                         &editFogHeight,
                                                         0.1f,
                                                         -1000.0f,
                                                         1000.0f,
                                                         "%.2f",
                                                         true,
                                                         true,
                                                         0.0f);
                        dirty |= EditorUI::PropertyFloat("Fog Distance",
                                                         &editFogDistance,
                                                         0.1f,
                                                         0.0f,
                                                         1000.0f,
                                                         "%.2f",
                                                         true,
                                                         true,
                                                         3.0f);
                        EditorUI::EndPropertyTable();
                    }

                    if (ImGui::TreeNodeEx("SkyAdvancedControls", ImGuiTreeNodeFlags_None, "Legacy Procedural Controls (Debug)")) {
                        ImGui::TextWrapped("These controls are compatibility/debug overrides for the older procedural sky path. They are not the normal authored environment workflow in Wave 1. Use Custom weather/cloud settings only when you intentionally want manual legacy overrides.");
                        if (EditorUI::BeginPropertyTable("SkyAdvancedProps")) {
                            dirty |= EditorUI::PropertyFloat("Legacy Sky Brightness",
                                                             &editIntensity,
                                                             EditorUIConstants::kSkyIntensityStep,
                                                             EditorUIConstants::kSkyIntensityMin,
                                                             EditorUIConstants::kSkyIntensityMax,
                                                             "%.2f",
                                                             true,
                                                             true,
                                                             EditorUIConstants::kDefaultSkyIntensity);
                            float tint[3] = {editTintX, editTintY, editTintZ};
                            const float tintDefault[3] = {1.0f, 1.0f, 1.0f};
                            if (EditorUI::PropertyColor3("Tint", tint, tintDefault, true)) {
                                editTintX = tint[0];
                                editTintY = tint[1];
                                editTintZ = tint[2];
                                dirty = true;
                            }
                            dirty |= EditorUI::PropertyFloat("Turbidity",
                                                             &editTurbidity,
                                                             EditorUIConstants::kSkyTurbidityStep,
                                                             EditorUIConstants::kSkyTurbidityMin,
                                                             EditorUIConstants::kSkyTurbidityMax,
                                                             "%.2f",
                                                             true,
                                                             true,
                                                             EditorUIConstants::kDefaultSkyTurbidity);
                            dirty |= EditorUI::PropertyFloat("Sun Size (deg)",
                                                             &editSunSize,
                                                             EditorUIConstants::kSkySunSizeStep,
                                                             EditorUIConstants::kSkySunSizeMin,
                                                             EditorUIConstants::kSkySunSizeMax,
                                                             "%.2f",
                                                             true,
                                                             true,
                                                             EditorUIConstants::kDefaultSkySunSize);
                            float zenithTint[3] = {editZenithTintX, editZenithTintY, editZenithTintZ};
                            const float zenithDefault[3] = {0.24f, 0.45f, 0.95f};
                            if (EditorUI::PropertyColor3("Zenith Tint", zenithTint, zenithDefault, true)) {
                                editZenithTintX = zenithTint[0];
                                editZenithTintY = zenithTint[1];
                                editZenithTintZ = zenithTint[2];
                                dirty = true;
                            }
                            float horizonTint[3] = {editHorizonTintX, editHorizonTintY, editHorizonTintZ};
                            const float horizonDefault[3] = {0.95f, 0.75f, 0.55f};
                            if (EditorUI::PropertyColor3("Horizon Tint", horizonTint, horizonDefault, true)) {
                                editHorizonTintX = horizonTint[0];
                                editHorizonTintY = horizonTint[1];
                                editHorizonTintZ = horizonTint[2];
                                dirty = true;
                            }
                            dirty |= EditorUI::PropertyFloat("Gradient Strength",
                                                             &editGradientStrength,
                                                             EditorUIConstants::kSkyGradientStrengthStep,
                                                             EditorUIConstants::kSkyGradientStrengthMin,
                                                             EditorUIConstants::kSkyGradientStrengthMax,
                                                             "%.2f",
                                                             true,
                                                             true,
                                                             EditorUIConstants::kDefaultSkyGradientStrength);
                            dirty |= EditorUI::PropertyFloat("Haze Falloff",
                                                             &editHazeFalloff,
                                                             EditorUIConstants::kSkyHazeFalloffStep,
                                                             EditorUIConstants::kSkyHazeFalloffMin,
                                                             EditorUIConstants::kSkyHazeFalloffMax,
                                                             "%.2f",
                                                             true,
                                                             true,
                                                             EditorUIConstants::kDefaultSkyHazeFalloff);
                            dirty |= EditorUI::PropertyFloat("Haze Height",
                                                             &editHazeHeight,
                                                             EditorUIConstants::kSkyHazeHeightStep,
                                                             EditorUIConstants::kSkyHazeHeightMin,
                                                             EditorUIConstants::kSkyHazeHeightMax,
                                                             "%.2f",
                                                             true,
                                                             true,
                                                             EditorUIConstants::kDefaultSkyHazeHeight);
                            dirty |= EditorUI::PropertyFloat("Ozone Strength",
                                                             &editOzoneStrength,
                                                             EditorUIConstants::kSkyOzoneStrengthStep,
                                                             EditorUIConstants::kSkyOzoneStrengthMin,
                                                             EditorUIConstants::kSkyOzoneStrengthMax,
                                                             "%.2f",
                                                             true,
                                                             true,
                                                             EditorUIConstants::kDefaultSkyOzoneStrength);
                            float ozoneTint[3] = {editOzoneTintX, editOzoneTintY, editOzoneTintZ};
                            const float ozoneDefault[3] = {0.55f, 0.7f, 1.0f};
                            if (EditorUI::PropertyColor3("Ozone Tint", ozoneTint, ozoneDefault, true)) {
                                editOzoneTintX = ozoneTint[0];
                                editOzoneTintY = ozoneTint[1];
                                editOzoneTintZ = ozoneTint[2];
                                dirty = true;
                            }
                            dirty |= EditorUI::PropertyFloat("Sun Halo Size",
                                                             &editSunHaloSize,
                                                             EditorUIConstants::kSkySunHaloSizeStep,
                                                             EditorUIConstants::kSkySunHaloSizeMin,
                                                             EditorUIConstants::kSkySunHaloSizeMax,
                                                             "%.2f",
                                                             true,
                                                             true,
                                                             EditorUIConstants::kDefaultSkySunHaloSize);
                            dirty |= EditorUI::PropertyFloat("Sun Halo Intensity",
                                                             &editSunHaloIntensity,
                                                             EditorUIConstants::kSkySunHaloIntensityStep,
                                                             EditorUIConstants::kSkySunHaloIntensityMin,
                                                             EditorUIConstants::kSkySunHaloIntensityMax,
                                                             "%.2f",
                                                             true,
                                                             true,
                                                             EditorUIConstants::kDefaultSkySunHaloIntensity);
                            dirty |= EditorUI::PropertyFloat("Sun Halo Softness",
                                                             &editSunHaloSoftness,
                                                             EditorUIConstants::kSkySunHaloSoftnessStep,
                                                             EditorUIConstants::kSkySunHaloSoftnessMin,
                                                             EditorUIConstants::kSkySunHaloSoftnessMax,
                                                             "%.2f",
                                                             true,
                                                             true,
                                                             EditorUIConstants::kDefaultSkySunHaloSoftness);
                            dirty |= EditorUI::PropertyFloat("Cloud Scale",
                                                             &editCloudsScale,
                                                             EditorUIConstants::kCloudScaleStep,
                                                             EditorUIConstants::kCloudScaleMin,
                                                             EditorUIConstants::kCloudScaleMax,
                                                             "%.2f",
                                                             true,
                                                             true,
                                                             EditorUIConstants::kDefaultCloudScale);
                            dirty |= EditorUI::PropertyFloat("Cloud Wind X",
                                                             &editCloudsWindX,
                                                             EditorUIConstants::kCloudWindStep,
                                                             EditorUIConstants::kCloudWindMin,
                                                             EditorUIConstants::kCloudWindMax,
                                                             "%.2f",
                                                             true,
                                                             true,
                                                             EditorUIConstants::kDefaultCloudWindX);
                            dirty |= EditorUI::PropertyFloat("Cloud Wind Y",
                                                             &editCloudsWindY,
                                                             EditorUIConstants::kCloudWindStep,
                                                             EditorUIConstants::kCloudWindMin,
                                                             EditorUIConstants::kCloudWindMax,
                                                             "%.2f",
                                                             true,
                                                             true,
                                                             EditorUIConstants::kDefaultCloudWindY);
                            dirty |= EditorUI::PropertyFloat("Cloud Height",
                                                             &editCloudsHeight,
                                                             EditorUIConstants::kCloudHeightStep,
                                                             EditorUIConstants::kCloudHeightMin,
                                                             EditorUIConstants::kCloudHeightMax,
                                                             "%.2f",
                                                             true,
                                                             true,
                                                             EditorUIConstants::kDefaultCloudHeight);
                            dirty |= EditorUI::PropertyFloat("Cloud Thickness",
                                                             &editCloudsThickness,
                                                             EditorUIConstants::kCloudThicknessStep,
                                                             EditorUIConstants::kCloudThicknessMin,
                                                             EditorUIConstants::kCloudThicknessMax,
                                                             "%.2f",
                                                             true,
                                                             true,
                                                             EditorUIConstants::kDefaultCloudThickness);
                            dirty |= EditorUI::PropertyFloat("Cloud Brightness",
                                                             &editCloudsBrightness,
                                                             EditorUIConstants::kCloudBrightnessStep,
                                                             EditorUIConstants::kCloudBrightnessMin,
                                                             EditorUIConstants::kCloudBrightnessMax,
                                                             "%.2f",
                                                             true,
                                                             true,
                                                             EditorUIConstants::kDefaultCloudBrightness);
                            dirty |= EditorUI::PropertyFloat("Cloud Sun Influence",
                                                             &editCloudsSunInfluence,
                                                             EditorUIConstants::kCloudSunInfluenceStep,
                                                             EditorUIConstants::kCloudSunInfluenceMin,
                                                             EditorUIConstants::kCloudSunInfluenceMax,
                                                             "%.2f",
                                                             true,
                                                             true,
                                                             EditorUIConstants::kDefaultCloudSunInfluence);
                            EditorUI::EndPropertyTable();
                        }
                        ImGui::TreePop();
                    }
                }

                ImGui::Spacing();
                ImGui::TextDisabled("IBL Update");

                if (envPickerDirty) {
                    envPicker.didPick = false;
                    dirty = true;
                }

                bool autoRebuildBool = autoRebuild != 0;
                if (ImGui::Checkbox("Auto Rebuild", &autoRebuildBool)) {
                    autoRebuild = autoRebuildBool ? 1 : 0;
                    dirty = true;
                }
                ImGui::SameLine();
                if (ImGui::Button("Rebuild IBL")) {
                    MCEEditorRequestSkyRebuild(context, selectedEntityId);
                }
                if (needsRebuild != 0) {
                    ImGui::TextColored(ImVec4(1.0f, 0.75f, 0.2f, 1.0f), "IBL rebuild required.");
                }

                if (dirty) {
                    MCEEditorSetSkyLight(context, selectedEntityId,
                                         editMode,
                                         editEnabled,
                                         editTimeOfDay,
                                         editWeatherType,
                                         editSecondaryWeatherType,
                                         editWeatherBlend,
                                         editWeatherAmount,
                                         editAtmosphereAmount,
                                         editCloudCoverage,
                                         editCloudStyle,
                                         editTemperature,
                                         editMood,
                                         editIntensity,
                                         editTintX,
                                         editTintY,
                                         editTintZ,
                                         editTurbidity,
                                         editAzimuth,
                                         editElevation,
                                         editSunSize,
                                         editZenithTintX,
                                         editZenithTintY,
                                         editZenithTintZ,
                                         editHorizonTintX,
                                         editHorizonTintY,
                                         editHorizonTintZ,
                                         editGradientStrength,
                                         editHazeDensity,
                                         editHazeFalloff,
                                         editHazeHeight,
                                         editOzoneStrength,
                                         editOzoneTintX,
                                         editOzoneTintY,
                                         editOzoneTintZ,
                                         editSunHaloSize,
                                         editSunHaloIntensity,
                                         editSunHaloSoftness,
                                         editCloudsEnabled,
                                         editCloudsCoverage,
                                         editCloudsSoftness,
                                         editCloudsScale,
                                         editCloudsSpeed,
                                         editCloudsWindX,
                                         editCloudsWindY,
                                         editCloudsHeight,
                                         editCloudsThickness,
                                         editCloudsBrightness,
                                         editCloudsSunInfluence,
                                         editFogAmount,
                                         editFogHeight,
                                         editFogDistance,
                                         autoRebuild,
                                         editHdriHandle);
                }
            }
        }
    }

    if (ImGui::BeginPopup("AddComponentPopup")) {
        if (MCEEditorEntityHasComponent(context, selectedEntityId, ComponentMeshRenderer) == 0) {
            if (ImGui::MenuItem("Mesh Renderer")) {
                MCEEditorAddComponent(context, selectedEntityId, ComponentMeshRenderer);
            }
        }
        if (MCEEditorEntityHasComponent(context, selectedEntityId, ComponentMaterial) == 0) {
            if (ImGui::MenuItem("Material")) {
                MCEEditorAddComponent(context, selectedEntityId, ComponentMaterial);
            }
        }
        if (MCEEditorEntityHasComponent(context, selectedEntityId, ComponentCamera) == 0) {
            if (ImGui::MenuItem("Camera")) {
                MCEEditorAddComponent(context, selectedEntityId, ComponentCamera);
            }
        }
        if (MCEEditorEntityHasComponent(context, selectedEntityId, ComponentRigidbody) == 0) {
            if (ImGui::MenuItem("Rigidbody")) {
                MCEEditorAddComponent(context, selectedEntityId, ComponentRigidbody);
            }
        }
        if (MCEEditorEntityHasComponent(context, selectedEntityId, ComponentCollider) == 0) {
            if (ImGui::MenuItem("Collider")) {
                MCEEditorAddComponent(context, selectedEntityId, ComponentCollider);
            }
        }
        if (MCEEditorEntityHasComponent(context, selectedEntityId, ComponentScript) == 0) {
            if (ImGui::MenuItem("Script")) {
                MCEEditorAddComponent(context, selectedEntityId, ComponentScript);
            }
        }
        if (MCEEditorEntityHasComponent(context, selectedEntityId, ComponentCharacterController) == 0) {
            if (ImGui::MenuItem("Character Controller")) {
                MCEEditorAddComponent(context, selectedEntityId, ComponentCharacterController);
            }
        }
        if (MCEEditorEntityHasComponent(context, selectedEntityId, ComponentSkinnedMesh) == 0) {
            if (ImGui::MenuItem("Skinned Mesh")) {
                MCEEditorAddComponent(context, selectedEntityId, ComponentSkinnedMesh);
            }
        }
        if (MCEEditorEntityHasComponent(context, selectedEntityId, ComponentAnimator) == 0) {
            if (ImGui::MenuItem("Animator")) {
                MCEEditorAddComponent(context, selectedEntityId, ComponentAnimator);
            }
        }
        if (MCEEditorEntityHasComponent(context, selectedEntityId, ComponentLight) == 0) {
            if (ImGui::MenuItem("Light")) {
                MCEEditorAddComponent(context, selectedEntityId, ComponentLight);
            }
        }
        if (MCEEditorEntityHasComponent(context, selectedEntityId, ComponentEnvironment) == 0) {
            if (ImGui::MenuItem("Environment")) {
                MCEEditorAddComponent(context, selectedEntityId, ComponentEnvironment);
            }
        }
        if (MCEEditorEntityHasComponent(context, selectedEntityId, ComponentReflectionProbe) == 0) {
            if (ImGui::MenuItem("Reflection Probe")) {
                MCEEditorAddComponent(context, selectedEntityId, ComponentReflectionProbe);
            }
        }
        ImGui::EndPopup();
    }

    MaterialPopupState &popup = GetMaterialPopupState(state);
    if (popup.open) {
        ImGui::SetNextWindowSize(ImVec2(520.0f, 520.0f), ImGuiCond_Once);
        if (ImGui::BeginPopupModal(popup.title.c_str(), &popup.open, ImGuiWindowFlags_AlwaysAutoResize)) {
            ImGui::BeginChild("MaterialEditorScroll", ImVec2(0, 360.0f), false, ImGuiWindowFlags_AlwaysVerticalScrollbar);
            const bool changed = DrawMaterialEditorContents(popup.state);
            ImGui::EndChild();
            if (changed) {
                popup.dirty = true;
            }

            ImGui::Spacing();
            if (popup.dirty) {
                ImGui::TextColored(ImVec4(0.95f, 0.7f, 0.2f, 1.0f), "* Unsaved changes");
            }

            if (ImGui::Button("Save")) {
                EnforceMetalRoughnessRule(popup.state);
                MCEEditorSetMaterialAsset(
                    context,
                    popup.handle,
                    popup.state.name,
                    popup.state.version,
                    popup.state.baseColor[0], popup.state.baseColor[1], popup.state.baseColor[2],
                    popup.state.metallic, popup.state.roughness, popup.state.ao,
                    popup.state.emissive[0], popup.state.emissive[1], popup.state.emissive[2],
                    popup.state.emissiveIntensity,
                    popup.state.uvTiling[0], popup.state.uvTiling[1],
                    popup.state.uvOffset[0], popup.state.uvOffset[1],
                    popup.state.alphaMode, popup.state.alphaCutoff,
                    popup.state.doubleSided ? 1 : 0, popup.state.unlit ? 1 : 0,
                    popup.state.baseColorHandle,
                    popup.state.normalHandle,
                    popup.state.metalRoughnessHandle,
                    popup.state.metallicHandle,
                    popup.state.roughnessHandle,
                    popup.state.aoHandle,
                    popup.state.emissiveHandle);
                popup.dirty = false;
            }
            ImGui::SameLine();
            if (ImGui::Button("Close")) {
                popup.open = false;
                ImGui::CloseCurrentPopup();
            }

            ImGui::EndPopup();
        }
    }

    ImGui::EndDisabled();
    ImGui::PopStyleVar();
    ImGui::EndChild();

    TexturePickerState &picker = GetTexturePickerState(state);
    if (picker.requestOpen) {
        ImGui::OpenPopup("TexturePicker");
        picker.requestOpen = false;
    }
    if (picker.open) {
        ImGui::SetNextWindowSize(ImVec2(420.0f, 320.0f), ImGuiCond_Once);
        if (ImGui::BeginPopupModal("TexturePicker", &picker.open, ImGuiWindowFlags_AlwaysAutoResize)) {
            ImGui::TextUnformatted(picker.title);
            ImGui::Separator();
            ImGui::InputTextWithHint("##TextureFilter", "Search textures...", picker.filter, sizeof(picker.filter));
            ImGui::Separator();

            std::vector<AssetOption> options;
            LoadTextureOptions(context, options);
            const std::string filterText = EditorUI::ToLower(std::string(picker.filter));
            for (const auto &option : options) {
                if (!filterText.empty() && EditorUI::ToLower(option.name).find(filterText) == std::string::npos) {
                    continue;
                }
                if (ImGui::Selectable(option.name.c_str())) {
                    if (picker.target) {
                        strncpy(picker.target, option.handle.c_str(), 63);
                        picker.target[63] = 0;
                    }
                    picker.didPick = true;
                    picker.open = false;
                    ImGui::CloseCurrentPopup();
                    break;
                }
            }

            if (options.empty()) {
                ImGui::TextDisabled("No textures found.");
            }

            ImGui::Spacing();
            if (ImGui::Button("Close")) {
                picker.open = false;
                ImGui::CloseCurrentPopup();
            }

            ImGui::EndPopup();
        }
    }

    EnvironmentPickerState &envPicker = GetEnvironmentPickerState(state);
    if (envPicker.requestOpen) {
        ImGui::OpenPopup("EnvironmentPicker");
        envPicker.requestOpen = false;
    }
    if (envPicker.open) {
        ImGui::SetNextWindowSize(ImVec2(420.0f, 320.0f), ImGuiCond_Once);
        if (ImGui::BeginPopupModal("EnvironmentPicker", &envPicker.open, ImGuiWindowFlags_AlwaysAutoResize)) {
            ImGui::TextUnformatted(envPicker.title);
            ImGui::Separator();
            ImGui::InputTextWithHint("##EnvironmentFilter", "Search environments...", envPicker.filter, sizeof(envPicker.filter));
            ImGui::Separator();

            std::vector<AssetOption> options;
            LoadEnvironmentOptions(context, options);
            const std::string filterText = EditorUI::ToLower(std::string(envPicker.filter));
            for (const auto &option : options) {
                if (!filterText.empty() && EditorUI::ToLower(option.name).find(filterText) == std::string::npos) {
                    continue;
                }
                if (ImGui::Selectable(option.name.c_str())) {
                    if (envPicker.target) {
                        strncpy(envPicker.target, option.handle.c_str(), 63);
                        envPicker.target[63] = 0;
                    }
                    envPicker.didPick = true;
                    envPicker.open = false;
                    ImGui::CloseCurrentPopup();
                    break;
                }
            }

            if (options.empty()) {
                ImGui::TextDisabled("No environment assets found.");
            }

            ImGui::Spacing();
            if (ImGui::Button("Close")) {
                envPicker.open = false;
                ImGui::CloseCurrentPopup();
            }

            ImGui::EndPopup();
        }
    }

    MeshPickerState &meshPicker = GetMeshPickerState(state);
    if (meshPicker.requestOpen) {
        ImGui::OpenPopup("MeshPicker");
        meshPicker.requestOpen = false;
    }
    if (meshPicker.open) {
        ImGui::SetNextWindowSize(ImVec2(420.0f, 320.0f), ImGuiCond_Once);
        if (ImGui::BeginPopupModal("MeshPicker", &meshPicker.open, ImGuiWindowFlags_AlwaysAutoResize)) {
            ImGui::TextUnformatted(meshPicker.title);
            ImGui::Separator();
            ImGui::InputTextWithHint("##MeshFilter", "Search meshes...", meshPicker.filter, sizeof(meshPicker.filter));
            ImGui::Separator();

            std::vector<AssetOption> options;
            LoadMeshOptions(context, options);
            const std::string filterText = EditorUI::ToLower(std::string(meshPicker.filter));
            for (const auto &option : options) {
                if (!filterText.empty() && EditorUI::ToLower(option.name).find(filterText) == std::string::npos) {
                    continue;
                }
                if (ImGui::Selectable(option.name.c_str())) {
                    if (meshPicker.entityId[0] != 0) {
                        MCEEditorSetMeshRenderer(context, meshPicker.entityId, option.handle.c_str(), meshPicker.materialHandle);
                    }
                    meshPicker.open = false;
                    ImGui::CloseCurrentPopup();
                    break;
                }
            }

            if (options.empty()) {
                ImGui::TextDisabled("No mesh assets found.");
            }

            ImGui::Spacing();
            if (ImGui::Button("Close")) {
                meshPicker.open = false;
                ImGui::CloseCurrentPopup();
            }

            ImGui::EndPopup();
        }
    }

    MaterialPickerState &materialPicker = GetMaterialPickerState(state);
    if (materialPicker.requestOpen) {
        ImGui::OpenPopup("MaterialPicker");
        materialPicker.requestOpen = false;
    }
    if (materialPicker.open) {
        ImGui::SetNextWindowSize(ImVec2(420.0f, 320.0f), ImGuiCond_Once);
        if (ImGui::BeginPopupModal("MaterialPicker", &materialPicker.open, ImGuiWindowFlags_AlwaysAutoResize)) {
            ImGui::TextUnformatted(materialPicker.title);
            ImGui::Separator();
            ImGui::InputTextWithHint("##MaterialFilter", "Search materials...", materialPicker.filter, sizeof(materialPicker.filter));
            ImGui::Separator();

            std::vector<AssetOption> options;
            LoadMaterialOptions(context, options);
            const std::string filterText = EditorUI::ToLower(std::string(materialPicker.filter));
            for (const auto &option : options) {
                if (!filterText.empty() && EditorUI::ToLower(option.name).find(filterText) == std::string::npos) {
                    continue;
                }
                if (ImGui::Selectable(option.name.c_str())) {
                    if (materialPicker.entityId[0] != 0) {
                        if (materialPicker.usesMeshRenderer) {
                            MCEEditorSetMeshRenderer(context, materialPicker.entityId, materialPicker.meshHandle, option.handle.c_str());
                            MCEEditorSetMaterialComponent(context, materialPicker.entityId, option.handle.c_str());
                        } else {
                            MCEEditorAssignMaterialToEntity(context, materialPicker.entityId, option.handle.c_str());
                        }
                    }
                    materialPicker.open = false;
                    ImGui::CloseCurrentPopup();
                    break;
                }
            }

            if (options.empty()) {
                ImGui::TextDisabled("No material assets found.");
            }

            ImGui::Spacing();
            if (ImGui::Button("Close")) {
                materialPicker.open = false;
                ImGui::CloseCurrentPopup();
            }

            ImGui::EndPopup();
        }
    }

    ScriptPickerState &scriptPicker = GetScriptPickerState(state);
    if (scriptPicker.requestOpen) {
        ImGui::OpenPopup("ScriptPicker");
        scriptPicker.requestOpen = false;
    }
    if (scriptPicker.open) {
        ImGui::SetNextWindowSize(ImVec2(420.0f, 320.0f), ImGuiCond_Once);
        if (ImGui::BeginPopupModal("ScriptPicker", &scriptPicker.open, ImGuiWindowFlags_AlwaysAutoResize)) {
            ImGui::TextUnformatted(scriptPicker.title);
            ImGui::Separator();
            ImGui::InputTextWithHint("##ScriptFilter", "Search scripts...", scriptPicker.filter, sizeof(scriptPicker.filter));
            ImGui::Separator();

            std::vector<AssetOption> options;
            LoadScriptOptions(context, options);
            const std::string filterText = EditorUI::ToLower(std::string(scriptPicker.filter));
            for (const auto &option : options) {
                if (!filterText.empty() && EditorUI::ToLower(option.name).find(filterText) == std::string::npos) {
                    continue;
                }
                if (ImGui::Selectable(option.name.c_str())) {
                    if (scriptPicker.entityId[0] != 0) {
                        uint32_t enabled = 1;
                        char scriptHandle[64] = {0};
                        char typeName[256] = {0};
                        uint32_t fieldDataSize = 0;
                        uint32_t fieldDataVersion = 1;
                        if (MCEEditorGetScript(context,
                                               scriptPicker.entityId,
                                               &enabled,
                                               scriptHandle, sizeof(scriptHandle),
                                               typeName, sizeof(typeName),
                                               &fieldDataSize,
                                               &fieldDataVersion) != 0) {
                            MCEEditorSetScript(context,
                                               scriptPicker.entityId,
                                               enabled,
                                               option.handle.c_str(),
                                               typeName,
                                               1);
                        }
                    }
                    scriptPicker.open = false;
                    ImGui::CloseCurrentPopup();
                    break;
                }
            }

            if (options.empty()) {
                ImGui::TextDisabled("No script assets found.");
            }

            ImGui::Spacing();
            if (ImGui::Button("Close")) {
                scriptPicker.open = false;
                ImGui::CloseCurrentPopup();
            }

            ImGui::EndPopup();
        }
    }

    EditorUI::EndPanel();
}
