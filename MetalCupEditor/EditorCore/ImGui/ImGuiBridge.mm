/// ImGuiBridge.mm
/// Defines the ImGui bridge interface for editor rendering and input.
/// Created by Kaden Cringle.

#import "ImGuiBridge.h"

// ImGui
#ifndef IMGUI_DEFINE_MATH_OPERATORS
#define IMGUI_DEFINE_MATH_OPERATORS
#endif
#import "../../ImGui/imgui.h"
#import "../../ImGui/backends/imgui_impl_osx.h"
#import "../../ImGui/backends/imgui_impl_metal.h"

#import "../../EditorUI/Panels/RendererPanel.h"
#import "../../EditorUI/Panels/ViewportPanel.h"
#import "../../EditorUI/Panels/SceneHierarchyPanel.h"
#import "../../EditorUI/Panels/InspectorPanel.h"
#import "../../EditorUI/Panels/ContentBrowserPanel.h"
#import "../../EditorUI/Panels/PanelState.h"
#import "../../EditorUI/AnimationGraph/AnimationGraphModels.h"
#import "../../EditorUI/AnimationGraph/AnimationGraphBlendSpaceWorkspace.h"
#import "../../EditorUI/AnimationGraph/AnimationGraphPanel.h"
#import "../../EditorUI/AnimationGraph/AnimationGraphSidebar.h"
#import "../../EditorUI/AnimationGraph/AnimationGraphUIStateStore.h"
#import "../../EditorUI/AnimationGraph/AnimationGraphNodeCanvas.h"
#import "../../EditorUI/AnimationGraph/AnimationGraphNodeEditorStore.h"
#import "../../EditorUI/AnimationGraph/AnimationGraphStateMachineWorkspace.h"
#import "../../EditorUI/AnimationGraph/AnimationGraphWorkspaceRouter.h"
#import "../../EditorUI/EditorIcons.h"
#import "../Bridge/RendererSettingsBridge.h"
#import "../Bridge/PhysicsSettingsBridge.h"
#import "../../EditorUI/Widgets/UIWidgets.h"
#import <Cocoa/Cocoa.h>
#include <algorithm>
#include <array>
#include <cstring>
#include <ctime>
#include <cmath>
#include <fstream>
#include <regex>
#include <string>
#include <vector>
#include <unordered_set>
#include <unordered_map>
#include <sys/stat.h>

namespace AnimationGraphBreadcrumbs {
void DrawWorkspaceBreadcrumbs(const std::string &graphHandle,
                              const AnimationGraphWorkspacePath &path,
                              const AnimationGraphSnapshot &snapshot);
}

extern "C" uint32_t MCEEditorGetViewportDebugCategoryEnabled(MCE_CTX, int32_t categoryRawValue);
extern "C" void MCEEditorSetViewportDebugCategoryEnabled(MCE_CTX, int32_t categoryRawValue, uint32_t value);
extern "C" void MCEEditorGetViewportDebugCategoryColor(MCE_CTX, int32_t categoryRawValue, float *rOut, float *gOut, float *bOut);
extern "C" void MCEEditorSetViewportDebugCategoryColor(MCE_CTX, int32_t categoryRawValue, float r, float g, float b);
extern "C" float MCEEditorGetViewportDebugCategoryOpacity(MCE_CTX, int32_t categoryRawValue);
extern "C" void MCEEditorSetViewportDebugCategoryOpacity(MCE_CTX, int32_t categoryRawValue, float value);
extern "C" float MCEEditorGetViewportDebugCategoryThickness(MCE_CTX, int32_t categoryRawValue);
extern "C" void MCEEditorSetViewportDebugCategoryThickness(MCE_CTX, int32_t categoryRawValue, float value);
extern "C" float MCEEditorGetViewportWorldIconsOpacity(MCE_CTX);
extern "C" void MCEEditorSetViewportWorldIconsOpacity(MCE_CTX, float value);
extern "C" uint32_t MCEEditorGetViewportProbeShellShowInnerBox(MCE_CTX);
extern "C" void MCEEditorSetViewportProbeShellShowInnerBox(MCE_CTX, uint32_t value);
extern "C" uint32_t MCEEditorGetViewportProbeShellShowOuterBox(MCE_CTX);
extern "C" void MCEEditorSetViewportProbeShellShowOuterBox(MCE_CTX, uint32_t value);
extern "C" uint32_t MCEEditorGetViewportProbeShellShowConnectorLines(MCE_CTX);
extern "C" void MCEEditorSetViewportProbeShellShowConnectorLines(MCE_CTX, uint32_t value);

namespace ViewportDebugCategory {
static constexpr int32_t WorldIcons = 0;
static constexpr int32_t CameraFrustums = 1;
static constexpr int32_t ReflectionProbeInfluence = 2;
static constexpr int32_t ReflectionProbeBlendShell = 3;
static constexpr int32_t ReflectionProbeLinks = 4;
static constexpr int32_t Physics = 5;
static constexpr int32_t GenericLines = 6;
static constexpr int32_t GenericShapes = 7;
}

static void DrawViewportDebugStyleControls(void *context,
                                           const char *tableId,
                                           int32_t category,
                                           const char *enabledLabel,
                                           const char *colorLabel,
                                           const char *thicknessLabel,
                                           const char *opacityLabel,
                                           const char *enabledTooltip,
                                           const char *colorTooltip,
                                           const char *thicknessTooltip,
                                           const char *opacityTooltip) {
    if (!EditorUI::BeginPropertyTable(tableId)) {
        return;
    }

    bool enabled = MCEEditorGetViewportDebugCategoryEnabled(context, category) != 0;
    EditorUI::SetNextPropertyInfoTooltip(enabledTooltip);
    if (EditorUI::PropertyBool(enabledLabel, &enabled)) {
        MCEEditorSetViewportDebugCategoryEnabled(context, category, enabled ? 1 : 0);
    }

    float color[3] = { 1.0f, 1.0f, 1.0f };
    MCEEditorGetViewportDebugCategoryColor(context, category, &color[0], &color[1], &color[2]);
    EditorUI::SetNextPropertyInfoTooltip(colorTooltip);
    if (EditorUI::PropertyColor3(colorLabel, color)) {
        MCEEditorSetViewportDebugCategoryColor(context, category, color[0], color[1], color[2]);
    }

    float thickness = MCEEditorGetViewportDebugCategoryThickness(context, category);
    EditorUI::SetNextPropertyInfoTooltip(thicknessTooltip);
    if (EditorUI::PropertyFloat(thicknessLabel, &thickness, 0.005f, 0.0f, 0.25f, "%.3f", true, false)) {
        MCEEditorSetViewportDebugCategoryThickness(context, category, thickness);
    }

    float opacity = MCEEditorGetViewportDebugCategoryOpacity(context, category);
    EditorUI::SetNextPropertyInfoTooltip(opacityTooltip);
    if (EditorUI::PropertyFloat(opacityLabel, &opacity, 0.025f, 0.0f, 1.0f, "%.2f", true, false)) {
        MCEEditorSetViewportDebugCategoryOpacity(context, category, opacity);
    }

    EditorUI::EndPropertyTable();
}


static std::string ResolveEditorIconFontPath(const char *fileName) {
    if (!fileName || fileName[0] == 0) {
        return {};
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *fileNameString = [NSString stringWithUTF8String:fileName];
    NSString *basename = [fileNameString stringByDeletingPathExtension];
    NSString *extension = [fileNameString pathExtension];
    NSString *candidate = [[NSBundle mainBundle] pathForResource:basename
                                                         ofType:extension
                                                    inDirectory:@"Icons"];
    if (candidate.length == 0) {
        return {};
    }

    BOOL isDirectory = NO;
    if ([fileManager fileExistsAtPath:candidate isDirectory:&isDirectory] && !isDirectory) {
        return std::string(candidate.UTF8String);
    }
    return {};
}

extern "C" void *MCEUIPanelStateCreate(void) {
    return new MCEPanelState::EditorUIPanelState();
}

extern "C" void MCEUIPanelStateDestroy(void *state) {
    delete static_cast<MCEPanelState::EditorUIPanelState *>(state);
}

extern "C" void MCEProjectNew(MCE_CTX);
extern "C" void MCEProjectOpen(MCE_CTX);
extern "C" void MCEProjectSave(MCE_CTX);
extern "C" void MCEProjectSaveAs(MCE_CTX);
extern "C" void MCEProjectSaveAll(MCE_CTX);
extern "C" uint32_t MCEProjectHasOpen(MCE_CTX);
extern "C" uint32_t MCEProjectNeedsModal(MCE_CTX);
extern "C" void MCEProjectDismissModal(MCE_CTX);
extern "C" int32_t MCEProjectRecentCount(MCE_CTX);
extern "C" int32_t MCEProjectRecentPathAt(MCE_CTX,  int32_t index, char *buffer, int32_t bufferSize);
extern "C" uint32_t MCEProjectOpenRecent(MCE_CTX,  const char *path);
extern "C" int32_t MCEProjectListCount(MCE_CTX);
extern "C" uint32_t MCEProjectListAt(MCE_CTX,  int32_t index,
                                     char *nameBuffer, int32_t nameBufferSize,
                                     char *pathBuffer, int32_t pathBufferSize,
                                     double *modifiedOut);
extern "C" uint32_t MCEProjectOpenAtPath(MCE_CTX,  const char *path);
extern "C" uint32_t MCEProjectDeleteAtPath(MCE_CTX,  const char *path);
extern "C" void MCESceneSave(MCE_CTX);
extern "C" void MCESceneSaveAs(MCE_CTX);
extern "C" void MCESceneLoad(MCE_CTX);
extern "C" void MCEScenePlay(MCE_CTX);
extern "C" void MCESceneStop(MCE_CTX);
extern "C" void MCEScenePause(MCE_CTX);
extern "C" void MCESceneResume(MCE_CTX);
extern "C" uint32_t MCESceneIsPlaying(MCE_CTX);
extern "C" uint32_t MCESceneIsPaused(MCE_CTX);
extern "C" uint32_t MCESceneIsDirty(MCE_CTX);
extern "C" void MCESceneNotifyMutation(MCE_CTX);
extern "C" uint32_t MCEEditorDebugPhysicsRaycastFromCamera(MCE_CTX, float maxDistance);
extern "C" int32_t MCEEditorCreateMeshEntityFromHandle(MCE_CTX,  const char *meshHandle, char *outId, int32_t outIdSize);
extern "C" int32_t MCEEditorCreateMeshEntityFromHandleWithMaterials(MCE_CTX,  const char *meshHandle, char *outId, int32_t outIdSize);
extern "C" int32_t MCEEditorCreateImportedMeshEntity(MCE_CTX, const char *meshHandle, const char *skeletonHandle, const char *defaultClipHandle, const char *submeshMaterialHandles, const char *meshPath, char *outId, int32_t outIdSize);
extern "C" uint32_t MCEEditorPopNextAlert(MCE_CTX,  char *buffer, int32_t bufferSize);
extern "C" uint32_t MCEEditorGetImGuiIniPath(MCE_CTX, char *buffer, int32_t bufferSize);
extern "C" uint32_t MCEEditorGetPanelVisibility(MCE_CTX,  const char *panelId, uint32_t defaultValue);
extern "C" void MCEEditorSetPanelVisibility(MCE_CTX,  const char *panelId, uint32_t visible);
extern "C" uint32_t MCEEditorGetHeaderOpen(MCE_CTX,  const char *headerId, uint32_t defaultValue);
extern "C" void MCEEditorSetHeaderOpen(MCE_CTX,  const char *headerId, uint32_t open);
extern "C" uint32_t MCEEditorGetAssetDisplayName(MCE_CTX, const char *handle, char *buffer, int32_t bufferSize);
extern "C" uint32_t MCEEditorGetAssetsRootPath(MCE_CTX,  char *buffer, int32_t bufferSize);
extern "C" int32_t MCEEditorGetAssetCount(MCE_CTX);
extern "C" uint32_t MCEEditorGetAssetAt(MCE_CTX,  int32_t index,
                                        char *handleBuffer, int32_t handleBufferSize,
                                        int32_t *typeOut,
                                        char *pathBuffer, int32_t pathBufferSize,
                                        char *nameBuffer, int32_t nameBufferSize);
extern "C" void MCEEditorSaveSettings(MCE_CTX);
extern "C" int32_t MCEEditorGetThemeMode(MCE_CTX);
extern "C" void MCEEditorSetThemeMode(MCE_CTX, int32_t value);
extern "C" void MCEEditorGetThemeAccent(MCE_CTX, float *r, float *g, float *b);
extern "C" void MCEEditorSetThemeAccent(MCE_CTX, float r, float g, float b);
extern "C" float MCEEditorGetThemeUIScale(MCE_CTX);
extern "C" void MCEEditorSetThemeUIScale(MCE_CTX, float value);
extern "C" uint32_t MCEEditorGetThemeRoundedUI(MCE_CTX);
extern "C" void MCEEditorSetThemeRoundedUI(MCE_CTX, uint32_t value);
extern "C" float MCEEditorGetThemeCornerRounding(MCE_CTX);
extern "C" void MCEEditorSetThemeCornerRounding(MCE_CTX, float value);
extern "C" int32_t MCEEditorGetThemeSpacingPreset(MCE_CTX);
extern "C" void MCEEditorSetThemeSpacingPreset(MCE_CTX, int32_t value);
extern "C" uint32_t MCEEditorGetViewportShowWorldIcons(MCE_CTX);
extern "C" void MCEEditorSetViewportShowWorldIcons(MCE_CTX, uint32_t value);
extern "C" float MCEEditorGetViewportWorldIconBaseSize(MCE_CTX);
extern "C" void MCEEditorSetViewportWorldIconBaseSize(MCE_CTX, float value);
extern "C" float MCEEditorGetViewportWorldIconDistanceScale(MCE_CTX);
extern "C" void MCEEditorSetViewportWorldIconDistanceScale(MCE_CTX, float value);
extern "C" float MCEEditorGetViewportWorldIconMinSize(MCE_CTX);
extern "C" void MCEEditorSetViewportWorldIconMinSize(MCE_CTX, float value);
extern "C" float MCEEditorGetViewportWorldIconMaxSize(MCE_CTX);
extern "C" void MCEEditorSetViewportWorldIconMaxSize(MCE_CTX, float value);
extern "C" uint32_t MCEEditorGetViewportShowSelectedCameraFrustum(MCE_CTX);
extern "C" void MCEEditorSetViewportShowSelectedCameraFrustum(MCE_CTX, uint32_t value);
extern "C" uint32_t MCEEditorGetViewportPreviewEnabled(MCE_CTX);
extern "C" void MCEEditorSetViewportPreviewEnabled(MCE_CTX, uint32_t value);
extern "C" float MCEEditorGetViewportPreviewSize(MCE_CTX);
extern "C" void MCEEditorSetViewportPreviewSize(MCE_CTX, float value);
extern "C" int32_t MCEEditorGetViewportPreviewPosition(MCE_CTX);
extern "C" void MCEEditorSetViewportPreviewPosition(MCE_CTX, int32_t value);
extern "C" uint32_t MCEEditorGetViewportSnapEnabled(MCE_CTX);
extern "C" void MCEEditorSetViewportSnapEnabled(MCE_CTX, uint32_t value);
extern "C" uint32_t MCEEditorGetDebugGridEnabled(MCE_CTX);
extern "C" void MCEEditorSetDebugGridEnabled(MCE_CTX, uint32_t value);
extern "C" uint32_t MCEEditorGetDebugOutlineEnabled(MCE_CTX);
extern "C" void MCEEditorSetDebugOutlineEnabled(MCE_CTX, uint32_t value);
extern "C" uint32_t MCEEditorGetDebugPhysicsEnabled(MCE_CTX);
extern "C" void MCEEditorSetDebugPhysicsEnabled(MCE_CTX, uint32_t value);
extern "C" uint32_t MCEEditorGetViewportDebugCategoryEnabled(MCE_CTX, int32_t categoryRawValue);
extern "C" void MCEEditorSetViewportDebugCategoryEnabled(MCE_CTX, int32_t categoryRawValue, uint32_t value);
extern "C" void MCEEditorGetViewportDebugCategoryColor(MCE_CTX, int32_t categoryRawValue, float *rOut, float *gOut, float *bOut);
extern "C" void MCEEditorSetViewportDebugCategoryColor(MCE_CTX, int32_t categoryRawValue, float r, float g, float b);
extern "C" float MCEEditorGetViewportDebugCategoryOpacity(MCE_CTX, int32_t categoryRawValue);
extern "C" void MCEEditorSetViewportDebugCategoryOpacity(MCE_CTX, int32_t categoryRawValue, float value);
extern "C" float MCEEditorGetViewportDebugCategoryThickness(MCE_CTX, int32_t categoryRawValue);
extern "C" void MCEEditorSetViewportDebugCategoryThickness(MCE_CTX, int32_t categoryRawValue, float value);
extern "C" float MCEEditorGetViewportWorldIconsOpacity(MCE_CTX);
extern "C" void MCEEditorSetViewportWorldIconsOpacity(MCE_CTX, float value);
extern "C" uint32_t MCEEditorGetViewportProbeShellShowInnerBox(MCE_CTX);
extern "C" void MCEEditorSetViewportProbeShellShowInnerBox(MCE_CTX, uint32_t value);
extern "C" uint32_t MCEEditorGetViewportProbeShellShowOuterBox(MCE_CTX);
extern "C" void MCEEditorSetViewportProbeShellShowOuterBox(MCE_CTX, uint32_t value);
extern "C" uint32_t MCEEditorGetViewportProbeShellShowConnectorLines(MCE_CTX);
extern "C" void MCEEditorSetViewportProbeShellShowConnectorLines(MCE_CTX, uint32_t value);
extern "C" uint32_t MCEEditorGetLastSelectedEntityId(MCE_CTX,  char *buffer, int32_t bufferSize);
extern "C" void MCEEditorSetLastSelectedEntityId(MCE_CTX,  const char *value);
extern "C" uint32_t MCEEditorConsumeOpenAnimationGraphEditor(MCE_CTX, char *buffer, int32_t bufferSize);
extern "C" uint32_t MCEEditorGetAnimationGraphInfo(MCE_CTX, const char *handle,
                                                    char *nameBuffer, int32_t nameBufferSize,
                                                    char *outputNodeIdBuffer, int32_t outputNodeIdBufferSize,
                                                    int32_t *parameterCountOut,
                                                    int32_t *nodeCountOut,
                                                    int32_t *linkCountOut);
extern "C" int32_t MCEEditorGetAnimationGraphLocalVariableCount(MCE_CTX, const char *handle);
extern "C" uint32_t MCEEditorGetAnimationGraphParameterAt(MCE_CTX, const char *handle, int32_t index,
                                                           char *nameBuffer, int32_t nameBufferSize,
                                                           int32_t *typeOut,
                                                           float *defaultFloatOut,
                                                           uint32_t *defaultBoolOut,
                                                           int32_t *defaultIntOut);
extern "C" uint32_t MCEEditorGetAnimationGraphLocalVariableAt(MCE_CTX, const char *handle, int32_t index,
                                                               char *nameBuffer, int32_t nameBufferSize,
                                                               int32_t *typeOut,
                                                               float *defaultFloatOut,
                                                               uint32_t *defaultBoolOut,
                                                               int32_t *defaultIntOut);
extern "C" uint32_t MCEEditorGetAnimationGraphNodeAt(MCE_CTX, const char *handle, int32_t index,
                                                      char *nodeIdBuffer, int32_t nodeIdBufferSize,
                                                      int32_t *typeOut,
                                                      char *titleBuffer, int32_t titleBufferSize,
                                                      float *posXOut, float *posYOut,
                                                      char *clipHandleBuffer, int32_t clipHandleBufferSize,
                                                      uint32_t *isOutputOut);
extern "C" uint32_t MCEEditorGetAnimationGraphLinkAt(MCE_CTX, const char *handle, int32_t index,
                                                      char *linkIdBuffer, int32_t linkIdBufferSize,
                                                      char *fromNodeIdBuffer, int32_t fromNodeIdBufferSize,
                                                      int32_t *fromSlotOut,
                                                      char *toNodeIdBuffer, int32_t toNodeIdBufferSize,
                                                      int32_t *toSlotOut);
extern "C" uint32_t MCEEditorSetAnimationGraphMetadata(MCE_CTX, const char *handle, const char *name, const char *outputNodeId);
extern "C" uint32_t MCEEditorAddAnimationGraphParameter(MCE_CTX, const char *handle, const char *name, int32_t type, float defaultFloat, uint32_t defaultBool, int32_t defaultInt);
extern "C" uint32_t MCEEditorUpdateAnimationGraphParameter(MCE_CTX, const char *handle, int32_t index, const char *name, int32_t type, float defaultFloat, uint32_t defaultBool, int32_t defaultInt);
extern "C" uint32_t MCEEditorRemoveAnimationGraphParameter(MCE_CTX, const char *handle, int32_t index);
extern "C" uint32_t MCEEditorAddAnimationGraphLocalVariable(MCE_CTX, const char *handle, const char *name, int32_t type, float defaultFloat, uint32_t defaultBool, int32_t defaultInt);
extern "C" uint32_t MCEEditorUpdateAnimationGraphLocalVariable(MCE_CTX, const char *handle, int32_t index, const char *name, int32_t type, float defaultFloat, uint32_t defaultBool, int32_t defaultInt);
extern "C" uint32_t MCEEditorRemoveAnimationGraphLocalVariable(MCE_CTX, const char *handle, int32_t index);
extern "C" uint32_t MCEEditorAddAnimationGraphNode(MCE_CTX, const char *handle, int32_t type, const char *title, float posX, float posY, const char *clipHandle, char *outNodeId, int32_t outNodeIdSize);
extern "C" uint32_t MCEEditorUpdateAnimationGraphNode(MCE_CTX, const char *handle, const char *nodeId, const char *title, float posX, float posY, const char *clipHandle);
extern "C" uint32_t MCEEditorSetAnimationGraphNodeParameterName(MCE_CTX, const char *handle, const char *nodeId, const char *parameterName);
extern "C" uint32_t MCEEditorGetAnimationGraphBlend1DNode(MCE_CTX, const char *handle, const char *nodeId,
                                                           char *parameterNameBuffer, int32_t parameterNameBufferSize,
                                                           int32_t *sampleCountOut);
extern "C" uint32_t MCEEditorGetAnimationGraphBlend1DSampleAt(MCE_CTX, const char *handle, const char *nodeId, int32_t index,
                                                               char *clipHandleBuffer, int32_t clipHandleBufferSize,
                                                               float *thresholdOut);
extern "C" uint32_t MCEEditorSetAnimationGraphBlend1DNode(MCE_CTX, const char *handle, const char *nodeId, const char *parameterName);
extern "C" uint32_t MCEEditorAddAnimationGraphBlend1DSample(MCE_CTX, const char *handle, const char *nodeId, const char *clipHandle, float threshold);
extern "C" uint32_t MCEEditorUpdateAnimationGraphBlend1DSample(MCE_CTX, const char *handle, const char *nodeId, int32_t index, const char *clipHandle, float threshold);
extern "C" uint32_t MCEEditorRemoveAnimationGraphBlend1DSample(MCE_CTX, const char *handle, const char *nodeId, int32_t index);
extern "C" uint32_t MCEEditorGetAnimationGraphBlend2DNode(MCE_CTX, const char *handle, const char *nodeId,
                                                           char *parameterXNameBuffer, int32_t parameterXNameBufferSize,
                                                           char *parameterYNameBuffer, int32_t parameterYNameBufferSize,
                                                           int32_t *sampleCountOut);
extern "C" uint32_t MCEEditorGetAnimationGraphBlend2DSampleAt(MCE_CTX, const char *handle, const char *nodeId, int32_t index,
                                                               char *clipHandleBuffer, int32_t clipHandleBufferSize,
                                                               float *xOut, float *yOut);
extern "C" uint32_t MCEEditorSetAnimationGraphBlend2DNode(MCE_CTX, const char *handle, const char *nodeId, const char *parameterXName, const char *parameterYName);
extern "C" uint32_t MCEEditorAddAnimationGraphBlend2DSample(MCE_CTX, const char *handle, const char *nodeId, const char *clipHandle, float x, float y);
extern "C" uint32_t MCEEditorUpdateAnimationGraphBlend2DSample(MCE_CTX, const char *handle, const char *nodeId, int32_t index, const char *clipHandle, float x, float y);
extern "C" uint32_t MCEEditorRemoveAnimationGraphBlend2DSample(MCE_CTX, const char *handle, const char *nodeId, int32_t index);
extern "C" uint32_t MCEEditorGetAnimationGraphStateMachineNode(MCE_CTX, const char *handle, const char *nodeId,
                                                                char *defaultStateIdBuffer, int32_t defaultStateIdBufferSize,
                                                                int32_t *stateCountOut,
                                                                int32_t *transitionCountOut);
extern "C" uint32_t MCEEditorSetAnimationGraphStateMachineDefaultState(MCE_CTX, const char *handle, const char *nodeId, const char *stateId);
extern "C" uint32_t MCEEditorGetAnimationGraphStateMachineStateAt(MCE_CTX, const char *handle, const char *nodeId, int32_t index,
                                                                   char *stateIdBuffer, int32_t stateIdBufferSize,
                                                                   char *nameBuffer, int32_t nameBufferSize,
                                                                   char *clipHandleBuffer, int32_t clipHandleBufferSize,
                                                                   char *nodeRefIdBuffer, int32_t nodeRefIdBufferSize,
                                                                   uint32_t *isOneShotOut,
                                                                   uint32_t *usesRootMotionOut);
extern "C" uint32_t MCEEditorAddAnimationGraphStateMachineState(MCE_CTX, const char *handle, const char *nodeId,
                                                                 const char *name, const char *clipHandle, const char *nodeRefId,
                                                                 uint32_t isOneShot,
                                                                 uint32_t usesRootMotion,
                                                                 char *outStateId, int32_t outStateIdSize);
extern "C" uint32_t MCEEditorUpdateAnimationGraphStateMachineState(MCE_CTX, const char *handle, const char *nodeId,
                                                                    const char *stateId, const char *name, const char *clipHandle, const char *nodeRefId,
                                                                    uint32_t isOneShot,
                                                                    uint32_t usesRootMotion);
extern "C" uint32_t MCEEditorRemoveAnimationGraphStateMachineState(MCE_CTX, const char *handle, const char *nodeId, const char *stateId);
extern "C" uint32_t MCEEditorGetAnimationGraphStateMachineTransitionAt(MCE_CTX, const char *handle, const char *nodeId, int32_t index,
                                                                        char *transitionIdBuffer, int32_t transitionIdBufferSize,
                                                                        char *fromStateIdBuffer, int32_t fromStateIdBufferSize,
                                                                        char *toStateIdBuffer, int32_t toStateIdBufferSize,
                                                                        float *durationOut,
                                                                        uint32_t *hasMinimumNormalizedTimeOut,
                                                                        float *minimumNormalizedTimeOut,
                                                                        int32_t *conditionCountOut);
extern "C" uint32_t MCEEditorAddAnimationGraphStateMachineTransition(MCE_CTX, const char *handle, const char *nodeId,
                                                                      const char *fromStateId, const char *toStateId,
                                                                      float duration, uint32_t hasMinimumNormalizedTime, float minimumNormalizedTime,
                                                                      char *outTransitionId, int32_t outTransitionIdSize);
extern "C" uint32_t MCEEditorUpdateAnimationGraphStateMachineTransition(MCE_CTX, const char *handle, const char *nodeId,
                                                                         const char *transitionId, const char *fromStateId, const char *toStateId,
                                                                         float duration, uint32_t hasMinimumNormalizedTime, float minimumNormalizedTime);
extern "C" uint32_t MCEEditorRemoveAnimationGraphStateMachineTransition(MCE_CTX, const char *handle, const char *nodeId, const char *transitionId);
extern "C" uint32_t MCEEditorGetAnimationGraphStateMachineConditionAt(MCE_CTX, const char *handle, const char *nodeId, const char *transitionId, int32_t index,
                                                                       char *parameterNameBuffer, int32_t parameterNameBufferSize,
                                                                       char *opBuffer, int32_t opBufferSize,
                                                                       float *floatValueOut, int32_t *intValueOut, uint32_t *boolValueOut,
                                                                       uint32_t *hasFloatOut, uint32_t *hasIntOut, uint32_t *hasBoolOut);
extern "C" uint32_t MCEEditorAddAnimationGraphStateMachineCondition(MCE_CTX, const char *handle, const char *nodeId, const char *transitionId,
                                                                     const char *parameterName, const char *op,
                                                                     float floatValue, int32_t intValue, uint32_t boolValue,
                                                                     uint32_t hasFloat, uint32_t hasInt, uint32_t hasBool);
extern "C" uint32_t MCEEditorUpdateAnimationGraphStateMachineCondition(MCE_CTX, const char *handle, const char *nodeId, const char *transitionId, int32_t index,
                                                                        const char *parameterName, const char *op,
                                                                        float floatValue, int32_t intValue, uint32_t boolValue,
                                                                        uint32_t hasFloat, uint32_t hasInt, uint32_t hasBool);
extern "C" uint32_t MCEEditorRemoveAnimationGraphStateMachineCondition(MCE_CTX, const char *handle, const char *nodeId, const char *transitionId, int32_t index);
extern "C" uint32_t MCEEditorRemoveAnimationGraphNode(MCE_CTX, const char *handle, const char *nodeId);
extern "C" uint32_t MCEEditorSetAnimationGraphOutputNode(MCE_CTX, const char *handle, const char *nodeId);
extern "C" uint32_t MCEEditorAddAnimationGraphLink(MCE_CTX, const char *handle, const char *fromNodeId, int32_t fromSlot, const char *toNodeId, int32_t toSlot, char *outLinkId, int32_t outLinkIdSize);
extern "C" uint32_t MCEEditorRemoveAnimationGraphLink(MCE_CTX, const char *handle, const char *linkId);
extern "C" uint32_t MCEEditorValidateAnimationGraph(MCE_CTX, const char *handle, uint32_t *validOut, char *messageBuffer, int32_t messageBufferSize);
extern "C" uint32_t MCEEditorGetAnimationGraphStateMachineTransitionGraphInfo(MCE_CTX, const char *handle, const char *nodeId, const char *transitionId,
                                                                               uint32_t *hasInlineGraphOut, int32_t *nodeCountOut, int32_t *linkCountOut,
                                                                               char *outputNodeIdBuffer, int32_t outputNodeIdBufferSize);
extern "C" uint32_t MCEEditorGetAnimationGraphStateMachineTransitionGraphNodeAt(MCE_CTX, const char *handle, const char *nodeId, const char *transitionId, int32_t index,
                                                                                 char *nodeIdBuffer, int32_t nodeIdBufferSize,
                                                                                 char *typeBuffer, int32_t typeBufferSize,
                                                                                 char *titleBuffer, int32_t titleBufferSize,
                                                                                 float *posXOut, float *posYOut,
                                                                                 char *parameterNameBuffer, int32_t parameterNameBufferSize,
                                                                                 float *floatValueOut, uint32_t *hasFloatValueOut,
                                                                                 uint32_t *boolValueOut, uint32_t *hasBoolValueOut,
                                                                                 uint32_t *synchronizeValueOut, uint32_t *hasSynchronizeValueOut);
extern "C" uint32_t MCEEditorGetAnimationGraphStateMachineTransitionGraphLinkAt(MCE_CTX, const char *handle, const char *nodeId, const char *transitionId, int32_t index,
                                                                                 char *linkIdBuffer, int32_t linkIdBufferSize,
                                                                                 char *fromNodeIdBuffer, int32_t fromNodeIdBufferSize, int32_t *fromSlotOut,
                                                                                 char *toNodeIdBuffer, int32_t toNodeIdBufferSize, int32_t *toSlotOut);
extern "C" uint32_t MCEEditorGetAnimatorMode(MCE_CTX, const char *entityId, int32_t *modeOut, char *graphHandle, int32_t graphHandleSize);
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
extern "C" int32_t MCEEditorGetAnimatorGraphLocalVariableCount(MCE_CTX, const char *entityId);
extern "C" uint32_t MCEEditorGetAnimatorGraphLocalVariableAt(MCE_CTX, const char *entityId, int32_t index,
                                                              char *nameBuffer, int32_t nameBufferSize,
                                                              int32_t *typeOut,
                                                              float *defaultFloatOut,
                                                              uint32_t *defaultBoolOut,
                                                              int32_t *defaultIntOut,
                                                              float *floatValueOut,
                                                              uint32_t *boolValueOut,
                                                              int32_t *intValueOut);
extern "C" uint32_t MCEEditorGetAnimatorGraphStateMachineRuntime(MCE_CTX, const char *entityId, const char *stateMachineNodeId,
                                                                  char *currentStateBuffer, int32_t currentStateBufferSize,
                                                                  char *nextStateBuffer, int32_t nextStateBufferSize,
                                                                  float *transitionElapsedOut,
                                                                  float *transitionDurationOut);
extern "C" uint32_t MCEEditorSetAnimatorGraphDebugTraceEnabled(MCE_CTX, const char *entityId, uint32_t enabled);
extern "C" int32_t MCEEditorGetAnimatorGraphDebugTraceCount(MCE_CTX, const char *entityId);
extern "C" uint32_t MCEEditorGetAnimatorGraphDebugTraceEntryAt(MCE_CTX, const char *entityId, int32_t index,
                                                                char *nodeIDBuffer, int32_t nodeIDBufferSize,
                                                                char *nodeTypeBuffer, int32_t nodeTypeBufferSize,
                                                                char *nodeTitleBuffer, int32_t nodeTitleBufferSize,
                                                                char *outputSummaryBuffer, int32_t outputSummaryBufferSize);
extern "C" uint32_t MCEEditorEntityHasComponent(MCE_CTX, const char *entityId, int32_t componentType);
extern "C" uint32_t MCEEditorGetSkinnedMesh(MCE_CTX, const char *entityId,
                                            char *skeletonHandle, int32_t skeletonHandleSize,
                                            int32_t *jointCountOut, uint32_t *isValidSkeletonOut);
extern "C" int32_t MCEEditorLogCount(MCE_CTX);
extern "C" uint32_t MCEEditorLogEntryAt(MCE_CTX,  int32_t index, int32_t *levelOut, int32_t *categoryOut, double *timestampOut, char *messageBuffer, int32_t messageBufferSize);
extern "C" uint64_t MCEEditorLogRevision(MCE_CTX);
extern "C" void MCEEditorLogClear(MCE_CTX);
extern "C" void MCEEditorLogMessage(MCE_CTX, int32_t level, int32_t category, const char *message);
extern "C" void MCEEditorRequestQuit(MCE_CTX);
extern "C" uint32_t MCEImportIsOpen(MCE_CTX);
extern "C" uint32_t MCEImportIsReimport(MCE_CTX);
extern "C" void MCEImportCancel(MCE_CTX);
extern "C" uint32_t MCEImportCommit(MCE_CTX);
extern "C" int32_t MCEImportGetPendingAssetType(MCE_CTX);
extern "C" uint32_t MCEImportGetSourceFilename(MCE_CTX, char *buffer, int32_t bufferSize);
extern "C" uint32_t MCEImportGetDestinationFolder(MCE_CTX, char *buffer, int32_t bufferSize);
extern "C" uint32_t MCEImportGetOptionBool(MCE_CTX, const char *key, uint32_t defaultValue);
extern "C" void MCEImportSetOptionBool(MCE_CTX, const char *key, uint32_t value);
extern "C" uint32_t MCEImportGetOptionString(MCE_CTX, const char *key, char *buffer, int32_t bufferSize);
extern "C" void MCEImportSetOptionString(MCE_CTX, const char *key, const char *value);
extern "C" float MCEImportGetOptionFloat(MCE_CTX, const char *key, float defaultValue);
extern "C" void MCEImportSetOptionFloat(MCE_CTX, const char *key, float value);
extern "C" int32_t MCEImportGetMeshCount(MCE_CTX);
extern "C" int32_t MCEImportGetSubmeshCount(MCE_CTX);
extern "C" int32_t MCEImportGetMaterialCount(MCE_CTX);
extern "C" uint32_t MCEImportGetMaterialNameAt(MCE_CTX, int32_t index, char *buffer, int32_t bufferSize);
extern "C" int32_t MCEImportGetTextureCount(MCE_CTX);
extern "C" uint32_t MCEImportGetTextureNameAt(MCE_CTX, int32_t index, char *buffer, int32_t bufferSize);
extern "C" int32_t MCEImportGetWarningCount(MCE_CTX);
extern "C" uint32_t MCEImportGetWarningAt(MCE_CTX, int32_t index, char *buffer, int32_t bufferSize);
extern "C" uint32_t MCEImportGetMeshHasUVs(MCE_CTX);
extern "C" uint32_t MCEImportGetMeshHasNormals(MCE_CTX);
extern "C" uint32_t MCEImportGetMeshHasTangents(MCE_CTX);
extern "C" uint32_t MCEImportGetCommitHandle(MCE_CTX, char *buffer, int32_t bufferSize);
extern "C" int32_t MCEImportGetCommitAssetType(MCE_CTX);
extern "C" uint32_t MCEImportGetCommitMeshPath(MCE_CTX, char *buffer, int32_t bufferSize);
extern "C" uint32_t MCEImportGetCommitSkeletonHandle(MCE_CTX, char *buffer, int32_t bufferSize);
extern "C" uint32_t MCEImportGetCommitDefaultClipHandle(MCE_CTX, char *buffer, int32_t bufferSize);
extern "C" uint32_t MCEImportGetCommitSubmeshMaterialHandles(MCE_CTX, char *buffer, int32_t bufferSize);
extern "C" void MCEImportClearCommitResult(MCE_CTX);
extern "C" uint32_t MCEImportGetLastError(MCE_CTX, char *buffer, int32_t bufferSize);
extern "C" void *MCEContextGetUIPanelState(MCE_CTX);
extern bool ImGui_ImplOSX_HandleEvent(NSEvent* event, NSView* view);

extern "C" bool MCEImGuiHandleEvent(void *event, void *view) {
    if (!event || !view) { return false; }
    return ImGui_ImplOSX_HandleEvent((__bridge NSEvent *)event, (__bridge NSView *)view);
}

extern "C" bool MCEImGuiWantsCaptureKeyboard(void) {
    ImGuiIO& io = ImGui::GetIO();
    return io.WantCaptureKeyboard || io.WantTextInput;
}

struct LogEntrySnapshot {
    int32_t level = 0;
    int32_t category = 0;
    double timestamp = 0.0;
    std::string message;
    std::string singleLineMessage;
    std::string timeLabel;
    std::string label;
    std::string displayLabel;
};

@interface ImGuiBridge () {
@public
    void *_context;
    bool _ImGuiInitialized;
    bool _ViewportHovered;
    bool _ViewportFocused;
    bool _ViewportUIHovered;
    CGSize _ViewportContentSize;
    CGPoint _ViewportContentOrigin;
    CGPoint _ViewportImageOrigin;
    CGSize _ViewportImageSize;
    bool _GizmoCaptureMouse;
    bool _GizmoCaptureKeyboard;
    bool _ShowSceneHierarchyPanel;
    bool _ShowInspectorPanel;
    bool _ShowContentBrowserPanel;
    bool _ShowViewportPanel;
    bool _ShowAnimationGraphPanel;
    bool _ShowProfilingPanel;
    bool _ShowLogsPanel;
    bool _ShowSettingsModal;
    int _SettingsCategoryIndex;
    bool _LoadedPanelVisibility;
    char _SelectedEntityId[64];

    uint64_t _LogRevision;
    std::vector<LogEntrySnapshot> _LogEntries;
    std::vector<int32_t> _LogFilteredIndices;
    bool _LogFilterDirty;
    char _LogFilterText[256];
    bool _LogFilterTrace;
    bool _LogFilterInfo;
    bool _LogFilterWarn;
    bool _LogFilterError;
    ImGuiTextFilter _LogFilter;
    bool _LogShowTrace;
    bool _LogShowInfo;
    bool _LogShowWarn;
    bool _LogShowError;
    bool _LogAutoScroll;
}
@end

struct EditorThemeSettings {
    int mode = 0; // 0: Dark, 1: Dark Gray, 2: Light
    float accent[3] = { 0.18f, 0.58f, 0.84f };
    float uiScale = 1.0f;
    bool roundedUI = true;
    float cornerRounding = 6.0f;
    int spacingPreset = 1; // 0: Compact, 1: Comfortable, 2: Spacious
};

static EditorThemeSettings gThemeSettings;
static bool gThemeLoaded = false;

static float Clamp01(float value) {
    return std::max(0.0f, std::min(1.0f, value));
}

static ImVec4 LerpColor(const ImVec4 &a, const ImVec4 &b, float t) {
    const float alpha = Clamp01(t);
    return ImVec4(
        a.x + (b.x - a.x) * alpha,
        a.y + (b.y - a.y) * alpha,
        a.z + (b.z - a.z) * alpha,
        a.w + (b.w - a.w) * alpha
    );
}

static void LoadThemeSettingsIfNeeded(void *context) {
    if (gThemeLoaded) {
        return;
    }
    gThemeLoaded = true;
    gThemeSettings.mode = static_cast<int>(MCEEditorGetThemeMode(context));
    MCEEditorGetThemeAccent(context, &gThemeSettings.accent[0], &gThemeSettings.accent[1], &gThemeSettings.accent[2]);
    gThemeSettings.uiScale = MCEEditorGetThemeUIScale(context);
    gThemeSettings.roundedUI = MCEEditorGetThemeRoundedUI(context) != 0;
    gThemeSettings.cornerRounding = MCEEditorGetThemeCornerRounding(context);
    gThemeSettings.spacingPreset = static_cast<int>(MCEEditorGetThemeSpacingPreset(context));
}

static void ApplyEditorTheme(const EditorThemeSettings &settings) {
    ImGuiStyle &style = ImGui::GetStyle();
    const float scale = std::max(0.75f, std::min(2.0f, settings.uiScale));
    ImGui::GetIO().FontGlobalScale = scale;

    const float spacingScale = settings.spacingPreset == 0 ? 0.85f : (settings.spacingPreset == 2 ? 1.2f : 1.0f);
    style.WindowPadding = ImVec2(12.0f * spacingScale, 10.0f * spacingScale);
    style.FramePadding = ImVec2(8.0f * spacingScale, 6.0f * spacingScale);
    style.ItemSpacing = ImVec2(8.0f * spacingScale, 6.0f * spacingScale);
    style.ItemInnerSpacing = ImVec2(6.0f * spacingScale, 4.0f * spacingScale);
    style.ScrollbarSize = 12.0f * spacingScale;
    const float round = settings.roundedUI ? std::max(0.0f, std::min(16.0f, settings.cornerRounding)) : 0.0f;
    style.WindowRounding = round;
    style.ChildRounding = round;
    style.FrameRounding = round;
    style.GrabRounding = round * 0.75f;
    style.PopupRounding = round;
    style.TabRounding = round * 0.8f;
    style.TabBarOverlineSize = 0.0f;
    style.WindowBorderSize = 1.0f;
    style.FrameBorderSize = 1.0f;

    const ImVec4 accent = ImVec4(Clamp01(settings.accent[0]), Clamp01(settings.accent[1]), Clamp01(settings.accent[2]), 1.0f);
    const ImVec4 accentMuted = ImVec4(accent.x * 0.8f, accent.y * 0.8f, accent.z * 0.8f, 1.0f);
    const bool lightTheme = settings.mode == 2;
    const bool darkGray = settings.mode == 1;

    ImVec4 *colors = style.Colors;
    if (lightTheme) {
        colors[ImGuiCol_Text] = ImVec4(0.13f, 0.13f, 0.14f, 1.0f);
        colors[ImGuiCol_TextDisabled] = ImVec4(0.45f, 0.45f, 0.48f, 1.0f);
        colors[ImGuiCol_WindowBg] = ImVec4(0.93f, 0.93f, 0.95f, 1.0f);
        colors[ImGuiCol_ChildBg] = ImVec4(0.96f, 0.96f, 0.98f, 1.0f);
        colors[ImGuiCol_PopupBg] = ImVec4(0.97f, 0.97f, 0.98f, 1.0f);
        colors[ImGuiCol_Border] = ImVec4(0.74f, 0.74f, 0.78f, 1.0f);
        colors[ImGuiCol_FrameBg] = ImVec4(0.86f, 0.86f, 0.9f, 1.0f);
        colors[ImGuiCol_FrameBgHovered] = ImVec4(0.81f, 0.82f, 0.86f, 1.0f);
        colors[ImGuiCol_FrameBgActive] = ImVec4(0.76f, 0.77f, 0.82f, 1.0f);
        colors[ImGuiCol_TitleBg] = ImVec4(0.89f, 0.89f, 0.92f, 1.0f);
        colors[ImGuiCol_TitleBgActive] = ImVec4(0.86f, 0.86f, 0.9f, 1.0f);
        colors[ImGuiCol_MenuBarBg] = ImVec4(0.88f, 0.88f, 0.9f, 1.0f);
        colors[ImGuiCol_Button] = ImVec4(0.82f, 0.83f, 0.87f, 1.0f);
        colors[ImGuiCol_ButtonHovered] = ImVec4(0.76f, 0.78f, 0.84f, 1.0f);
        colors[ImGuiCol_ButtonActive] = ImVec4(0.71f, 0.73f, 0.8f, 1.0f);
        colors[ImGuiCol_Header] = ImVec4(0.82f, 0.83f, 0.87f, 1.0f);
        colors[ImGuiCol_HeaderHovered] = ImVec4(0.76f, 0.78f, 0.84f, 1.0f);
        colors[ImGuiCol_HeaderActive] = ImVec4(0.71f, 0.73f, 0.8f, 1.0f);
        colors[ImGuiCol_Tab] = ImVec4(0.82f, 0.83f, 0.88f, 1.0f);
        colors[ImGuiCol_TabHovered] = ImVec4(0.77f, 0.79f, 0.85f, 1.0f);
        colors[ImGuiCol_TabActive] = ImVec4(0.74f, 0.76f, 0.83f, 1.0f);
        colors[ImGuiCol_ScrollbarBg] = ImVec4(0.9f, 0.9f, 0.93f, 1.0f);
        colors[ImGuiCol_ScrollbarGrab] = ImVec4(0.68f, 0.69f, 0.75f, 1.0f);
    } else {
        const float base = darkGray ? 0.16f : 0.11f;
        const float frame = darkGray ? 0.22f : 0.18f;
        colors[ImGuiCol_Text] = ImVec4(0.92f, 0.92f, 0.94f, 1.0f);
        colors[ImGuiCol_TextDisabled] = ImVec4(0.55f, 0.55f, 0.58f, 1.0f);
        colors[ImGuiCol_WindowBg] = ImVec4(base, base, base + 0.01f, 1.0f);
        colors[ImGuiCol_ChildBg] = ImVec4(base + 0.01f, base + 0.01f, base + 0.02f, 1.0f);
        colors[ImGuiCol_PopupBg] = ImVec4(base + 0.02f, base + 0.02f, base + 0.03f, 1.0f);
        colors[ImGuiCol_Border] = ImVec4(base + 0.13f, base + 0.13f, base + 0.15f, 1.0f);
        colors[ImGuiCol_FrameBg] = ImVec4(frame, frame, frame + 0.02f, 1.0f);
        colors[ImGuiCol_FrameBgHovered] = ImVec4(frame + 0.05f, frame + 0.05f, frame + 0.07f, 1.0f);
        colors[ImGuiCol_FrameBgActive] = ImVec4(frame + 0.08f, frame + 0.08f, frame + 0.1f, 1.0f);
        colors[ImGuiCol_TitleBg] = ImVec4(base - 0.02f, base - 0.02f, base - 0.01f, 1.0f);
        colors[ImGuiCol_TitleBgActive] = ImVec4(base + 0.01f, base + 0.01f, base + 0.02f, 1.0f);
        colors[ImGuiCol_MenuBarBg] = ImVec4(base - 0.02f, base - 0.02f, base - 0.01f, 1.0f);
        colors[ImGuiCol_Button] = ImVec4(frame + 0.02f, frame + 0.02f, frame + 0.04f, 1.0f);
        colors[ImGuiCol_ButtonHovered] = ImVec4(frame + 0.1f, frame + 0.09f, frame + 0.12f, 1.0f);
        colors[ImGuiCol_ButtonActive] = ImVec4(frame + 0.14f, frame + 0.13f, frame + 0.16f, 1.0f);
        colors[ImGuiCol_Header] = ImVec4(frame + 0.02f, frame + 0.02f, frame + 0.04f, 1.0f);
        colors[ImGuiCol_HeaderHovered] = ImVec4(frame + 0.1f, frame + 0.09f, frame + 0.12f, 1.0f);
        colors[ImGuiCol_HeaderActive] = ImVec4(frame + 0.14f, frame + 0.13f, frame + 0.16f, 1.0f);
        colors[ImGuiCol_Tab] = ImVec4(frame, frame, frame + 0.02f, 1.0f);
        colors[ImGuiCol_TabHovered] = ImVec4(frame + 0.08f, frame + 0.08f, frame + 0.11f, 1.0f);
        colors[ImGuiCol_TabActive] = ImVec4(frame + 0.06f, frame + 0.06f, frame + 0.09f, 1.0f);
        colors[ImGuiCol_ScrollbarBg] = ImVec4(base + 0.03f, base + 0.03f, base + 0.05f, 1.0f);
        colors[ImGuiCol_ScrollbarGrab] = ImVec4(frame + 0.07f, frame + 0.08f, frame + 0.11f, 1.0f);
    }

    colors[ImGuiCol_CheckMark] = accent;
    colors[ImGuiCol_SliderGrab] = accentMuted;
    colors[ImGuiCol_SliderGrabActive] = accent;
    colors[ImGuiCol_ResizeGrip] = ImVec4(accent.x, accent.y, accent.z, 0.55f);
    colors[ImGuiCol_ResizeGripHovered] = ImVec4(accent.x, accent.y, accent.z, 0.75f);
    colors[ImGuiCol_ResizeGripActive] = accent;
    const ImVec4 tabBase = colors[ImGuiCol_Tab];
    const ImVec4 tabHoverBase = colors[ImGuiCol_TabHovered];
    const ImVec4 tabSelectedBase = colors[ImGuiCol_TabActive];
    const ImVec4 tabUnfocusedBase = LerpColor(tabBase, colors[ImGuiCol_TitleBg], 0.35f);
    const ImVec4 tabUnfocusedSelectedBase = LerpColor(tabSelectedBase, colors[ImGuiCol_TitleBg], 0.25f);
    const float tabTint = lightTheme ? 0.18f : 0.28f;
    const float tabHoverTint = lightTheme ? 0.24f : 0.34f;
    const float tabSelectedTint = lightTheme ? 0.28f : 0.40f;
    const float tabUnfocusedTint = lightTheme ? 0.12f : 0.18f;
    const float tabUnfocusedSelectedTint = lightTheme ? 0.17f : 0.26f;
    const ImVec4 themedTab = LerpColor(tabBase, accent, tabTint);
    const ImVec4 themedTabHovered = LerpColor(tabHoverBase, accent, tabHoverTint);
    const ImVec4 themedTabSelected = LerpColor(tabSelectedBase, accent, tabSelectedTint);
    const ImVec4 themedTabUnfocused = LerpColor(tabUnfocusedBase, accent, tabUnfocusedTint);
    const ImVec4 themedTabUnfocusedSelected = LerpColor(tabUnfocusedSelectedBase, accent, tabUnfocusedSelectedTint);
    colors[ImGuiCol_Tab] = themedTab;
    colors[ImGuiCol_TabHovered] = themedTabHovered;
    colors[ImGuiCol_TabSelected] = themedTabSelected;
    colors[ImGuiCol_TabActive] = themedTabSelected;
    colors[ImGuiCol_TabDimmed] = themedTabUnfocused;
    colors[ImGuiCol_TabUnfocused] = themedTabUnfocused;
    colors[ImGuiCol_TabDimmedSelected] = themedTabUnfocusedSelected;
    colors[ImGuiCol_TabUnfocusedActive] = themedTabUnfocusedSelected;
    colors[ImGuiCol_TabSelectedOverline] = accent;
    colors[ImGuiCol_TabDimmedSelectedOverline] = ImVec4(accent.x, accent.y, accent.z, lightTheme ? 0.55f : 0.45f);
    colors[ImGuiCol_NavHighlight] = accent;
    colors[ImGuiCol_DockingPreview] = ImVec4(accent.x, accent.y, accent.z, 0.35f);
    colors[ImGuiCol_TableHeaderBg] = colors[ImGuiCol_Header];
    colors[ImGuiCol_TableBorderStrong] = colors[ImGuiCol_Border];
    colors[ImGuiCol_TableBorderLight] = colors[ImGuiCol_Border];
    colors[ImGuiCol_TableRowBg] = colors[ImGuiCol_ChildBg];
    colors[ImGuiCol_TableRowBgAlt] = ImVec4(colors[ImGuiCol_ChildBg].x + (lightTheme ? -0.02f : 0.02f),
                                            colors[ImGuiCol_ChildBg].y + (lightTheme ? -0.02f : 0.02f),
                                            colors[ImGuiCol_ChildBg].z + (lightTheme ? -0.02f : 0.02f),
                                            1.0f);
    colors[ImGuiCol_TextSelectedBg] = ImVec4(accent.x, accent.y, accent.z, 0.35f);
    colors[ImGuiCol_DragDropTarget] = ImVec4(accent.x, accent.y, accent.z, 0.9f);
    colors[ImGuiCol_NavWindowingHighlight] = ImVec4(accent.x, accent.y, accent.z, 0.7f);
    colors[ImGuiCol_NavWindowingDimBg] = lightTheme ? ImVec4(0.6f, 0.6f, 0.65f, 0.25f) : ImVec4(0.1f, 0.1f, 0.12f, 0.7f);
}

static std::string FormatTimestamp(double seconds) {
    if (seconds <= 0.0) { return "-"; }
    std::time_t timeValue = static_cast<std::time_t>(seconds);
    std::tm localTime {};
    localtime_r(&timeValue, &localTime);
    char buffer[64] = {0};
    if (std::strftime(buffer, sizeof(buffer), "%Y-%m-%d %H:%M", &localTime) == 0) {
        return "-";
    }
    return std::string(buffer);
}

static std::string FormatClockTime(double seconds) {
    if (seconds <= 0.0) { return "--:--:--"; }
    std::time_t timeValue = static_cast<std::time_t>(seconds);
    std::tm localTime {};
    localtime_r(&timeValue, &localTime);
    char buffer[32] = {0};
    if (std::strftime(buffer, sizeof(buffer), "%H:%M:%S", &localTime) == 0) {
        return "--:--:--";
    }
    return std::string(buffer);
}

static const char *LogCategoryLabel(int32_t category) {
    switch (category) {
    case 0: return "Core";
    case 1: return "Editor";
    case 2: return "Project";
    case 3: return "Scene";
    case 4: return "Assets";
    case 5: return "Renderer";
    case 6: return "Serialization";
    case 7: return "Input";
    default: return "Other";
    }
}

static std::string NormalizeLogMessageForDisplay(const char *raw) {
    if (!raw) { return std::string(); }
    std::string text(raw);
    std::string normalized;
    normalized.reserve(text.size());
    for (size_t i = 0; i < text.size(); ++i) {
        const char c = text[i];
        if (c == '\\' && (i + 1) < text.size()) {
            const char next = text[i + 1];
            if (next == 'n' || next == 'r') {
                normalized.push_back('\n');
                ++i;
                continue;
            }
            if (next == 't') {
                normalized.push_back('\t');
                ++i;
                continue;
            }
        }
        if (c == '\r') {
            if ((i + 1) < text.size() && text[i + 1] == '\n') {
                ++i;
            }
            normalized.push_back('\n');
            continue;
        }
        if (static_cast<unsigned char>(c) < 0x20 && c != '\n' && c != '\t') {
            normalized.push_back(' ');
            continue;
        }
        normalized.push_back(c);
    }
    return normalized;
}

static std::string NormalizeLogMessageToSingleLine(const char *raw) {
    const std::string text = NormalizeLogMessageForDisplay(raw);
    std::string normalized;
    normalized.reserve(text.size());
    for (size_t i = 0; i < text.size(); ++i) {
        const char c = text[i];
        if (c == '\r') {
            if (i + 1 < text.size() && text[i + 1] == '\n') {
                ++i;
            }
            normalized += " \\n ";
            continue;
        }
        if (c == '\n') {
            normalized += " \\n ";
            continue;
        }
        if (c == '\t') {
            normalized += "    ";
            continue;
        }
        if (static_cast<unsigned char>(c) < 0x20) {
            normalized.push_back(' ');
            continue;
        }
        normalized.push_back(c);
    }
    return normalized;
}

static void RefreshLogSnapshotIfNeeded(ImGuiBridge *bridge) {
    const uint64_t revision = MCEEditorLogRevision(bridge->_context);
    if (revision == bridge->_LogRevision) { return; }
    bridge->_LogRevision = revision;
    bridge->_LogEntries.clear();
    bridge->_LogFilteredIndices.clear();

    const int32_t count = MCEEditorLogCount(bridge->_context);
    bridge->_LogEntries.reserve(static_cast<size_t>(count));
    for (int32_t i = 0; i < count; ++i) {
        char message[8192] = {0};
        int32_t level = 0;
        int32_t category = 0;
        double timestamp = 0.0;
        if (MCEEditorLogEntryAt(bridge->_context, i, &level, &category, &timestamp, message, sizeof(message)) == 0) { continue; }
        LogEntrySnapshot entry;
        entry.level = level;
        entry.category = category;
        entry.timestamp = timestamp;
        entry.message = NormalizeLogMessageForDisplay(message);
        entry.singleLineMessage = NormalizeLogMessageToSingleLine(entry.message.c_str());
        entry.timeLabel = FormatClockTime(timestamp);
        entry.label = "[" + entry.timeLabel + "] [" + LogCategoryLabel(category) + "] " + entry.singleLineMessage;
        entry.displayLabel = "[" + entry.timeLabel + "] [" + LogCategoryLabel(category) + "] " + entry.message;
        bridge->_LogEntries.push_back(std::move(entry));
    }

    bridge->_LogFilterDirty = true;
}

static void RebuildLogFilterIfNeeded(ImGuiBridge *bridge, ImGuiTextFilter &filter, bool showTrace, bool showInfo, bool showWarn, bool showError) {
    if (strcmp(bridge->_LogFilterText, filter.InputBuf) != 0) {
        strncpy(bridge->_LogFilterText, filter.InputBuf, sizeof(bridge->_LogFilterText) - 1);
        bridge->_LogFilterText[sizeof(bridge->_LogFilterText) - 1] = 0;
        bridge->_LogFilterDirty = true;
    }

    if (bridge->_LogFilterTrace != showTrace || bridge->_LogFilterInfo != showInfo || bridge->_LogFilterWarn != showWarn || bridge->_LogFilterError != showError) {
        bridge->_LogFilterTrace = showTrace;
        bridge->_LogFilterInfo = showInfo;
        bridge->_LogFilterWarn = showWarn;
        bridge->_LogFilterError = showError;
        bridge->_LogFilterDirty = true;
    }

    if (!bridge->_LogFilterDirty) { return; }
    bridge->_LogFilterDirty = false;
    bridge->_LogFilteredIndices.clear();
    bridge->_LogFilteredIndices.reserve(bridge->_LogEntries.size());

    for (int32_t i = 0; i < static_cast<int32_t>(bridge->_LogEntries.size()); ++i) {
        const auto &entry = bridge->_LogEntries[i];
        const bool levelEnabled = (entry.level == 0 && showTrace) || (entry.level == 1 && showInfo) ||
            (entry.level == 2 && showWarn) || (entry.level == 3 && showError);
        if (!levelEnabled) { continue; }
        if (!filter.PassFilter(entry.message.c_str())) { continue; }
        bridge->_LogFilteredIndices.push_back(i);
    }
}

static void DrawHistorySeries(ImDrawList *drawList,
                              const ImVec2 &min,
                              const ImVec2 &max,
                              const float *values,
                              int count,
                              int offset,
                              float minValue,
                              float maxValue,
                              ImU32 color) {
    if (!values || count < 2) { return; }
    float range = maxValue - minValue;
    if (range <= 0.001f) { range = 1.0f; }
    ImVec2 prev;
    for (int i = 0; i < count; ++i) {
        int index = (offset + i) % count;
        float value = values[index];
        float t = (value - minValue) / range;
        t = std::max(0.0f, std::min(1.0f, t));
        float x = min.x + (static_cast<float>(i) / static_cast<float>(count - 1)) * (max.x - min.x);
        float y = max.y - t * (max.y - min.y);
        ImVec2 point(x, y);
        if (i > 0) {
            drawList->AddLine(prev, point, color, 1.5f);
        }
        prev = point;
    }
}

static void DrawLegendItem(const char *label, const ImVec4 &color) {
    ImGui::PushID(label);
    ImGui::ColorButton("##LegendSwatch",
                       color,
                       ImGuiColorEditFlags_NoTooltip | ImGuiColorEditFlags_NoDragDrop | ImGuiColorEditFlags_NoPicker,
                       ImVec2(10.0f, 10.0f));
    ImGui::PopID();
    ImGui::SameLine();
    ImGui::TextUnformatted(label);
    ImGui::SameLine();
}

static void LoadPanelVisibilityIfNeeded(ImGuiBridge *bridge) {
    if (bridge->_LoadedPanelVisibility) { return; }
    bridge->_LoadedPanelVisibility = true;

    bridge->_ShowSceneHierarchyPanel = MCEEditorGetPanelVisibility(bridge->_context, "SceneHierarchy", 1) != 0;
    const bool propertiesVisible = MCEEditorGetPanelVisibility(bridge->_context, "Properties", 1) != 0;
    const bool inspectorLegacyVisible = MCEEditorGetPanelVisibility(bridge->_context, "Inspector", propertiesVisible ? 1 : 0) != 0;
    bridge->_ShowInspectorPanel = propertiesVisible || inspectorLegacyVisible;
    bridge->_ShowContentBrowserPanel = MCEEditorGetPanelVisibility(bridge->_context, "ContentBrowser", 1) != 0;
    bridge->_ShowViewportPanel = MCEEditorGetPanelVisibility(bridge->_context, "Viewport", 1) != 0;
    bridge->_ShowAnimationGraphPanel = MCEEditorGetPanelVisibility(bridge->_context, "AnimationGraph", 1) != 0;
    bridge->_ShowProfilingPanel = MCEEditorGetPanelVisibility(bridge->_context, "Profiling", 0) != 0;
    bridge->_ShowLogsPanel = MCEEditorGetPanelVisibility(bridge->_context, "Logs", 1) != 0;

    char selectedBuffer[64] = {0};
    if (MCEEditorGetLastSelectedEntityId(bridge->_context, selectedBuffer, sizeof(selectedBuffer)) != 0) {
        strncpy(bridge->_SelectedEntityId, selectedBuffer, sizeof(bridge->_SelectedEntityId) - 1);
        bridge->_SelectedEntityId[sizeof(bridge->_SelectedEntityId) - 1] = 0;
    }
}

static void SetPanelVisibility(ImGuiBridge *bridge, const char *panelId, bool value) {
    MCEEditorSetPanelVisibility(bridge->_context, panelId, value ? 1 : 0);
}

struct PanelMenuEntry {
    const char *label = nullptr;
    const char *id = nullptr;
    bool *visible = nullptr;
};

static void DrawPanelMenuItem(ImGuiBridge *bridge, const PanelMenuEntry &entry) {
    if (!entry.label || !entry.id || !entry.visible) { return; }
    if (ImGui::MenuItem(entry.label, nullptr, entry.visible)) {
        SetPanelVisibility(bridge, entry.id, *entry.visible);
    }
}

static void DrawLogsPanel(ImGuiBridge *bridge, bool *isOpen) {
    if (!isOpen || !*isOpen) { return; }
    ImGui::Begin("Logs", isOpen);

    RefreshLogSnapshotIfNeeded(bridge);

    const bool copyClicked = ImGui::Button("Copy Entire Log");
    ImGui::SameLine();
    const bool clearClicked = ImGui::Button("Clear");
    ImGui::SameLine();
    ImGui::Checkbox("Auto-scroll", &bridge->_LogAutoScroll);
    ImGui::SameLine();
    bridge->_LogFilter.Draw("Filter", 200.0f);

    ImGui::Separator();
    ImGui::Checkbox("Trace", &bridge->_LogShowTrace);
    ImGui::SameLine();
    ImGui::Checkbox("Info", &bridge->_LogShowInfo);
    ImGui::SameLine();
    ImGui::Checkbox("Warn", &bridge->_LogShowWarn);
    ImGui::SameLine();
    ImGui::Checkbox("Error", &bridge->_LogShowError);

    RebuildLogFilterIfNeeded(bridge, bridge->_LogFilter, bridge->_LogShowTrace, bridge->_LogShowInfo, bridge->_LogShowWarn, bridge->_LogShowError);
    const int32_t filteredCount = static_cast<int32_t>(bridge->_LogFilteredIndices.size());
    const int32_t totalCount = static_cast<int32_t>(bridge->_LogEntries.size());

    if (clearClicked) {
        MCEEditorLogClear(bridge->_context);
    }
    if (copyClicked) {
        std::string output;
        output.reserve(static_cast<size_t>(filteredCount) * 80);
        for (int32_t index : bridge->_LogFilteredIndices) {
            if (index < 0 || index >= static_cast<int32_t>(bridge->_LogEntries.size())) { continue; }
            const auto &entry = bridge->_LogEntries[index];
            output += entry.displayLabel;
            output += "\n";
        }
        ImGui::SetClipboardText(output.c_str());
    }

    ImGui::Spacing();
    if (filteredCount != totalCount) {
        ImGui::TextDisabled("Visible: %d  |  Total: %d", filteredCount, totalCount);
    } else {
        ImGui::TextDisabled("Entries: %d", totalCount);
    }

    ImGui::Separator();
    ImGui::BeginChild("LogsScroll", ImVec2(0, 0), false, ImGuiWindowFlags_AlwaysVerticalScrollbar);
    const float scrollY = ImGui::GetScrollY();
    const float scrollMaxY = ImGui::GetScrollMaxY();
    const bool wasAtBottom = (scrollMaxY <= 0.0f) || (scrollY >= (scrollMaxY - 4.0f));

    ImGui::PushTextWrapPos(0.0f);
    for (int32_t row = 0; row < filteredCount; ++row) {
        const int32_t entryIndex = bridge->_LogFilteredIndices[row];
        if (entryIndex < 0 || entryIndex >= static_cast<int32_t>(bridge->_LogEntries.size())) { continue; }
        const auto &entry = bridge->_LogEntries[entryIndex];
        ImVec4 color = ImGui::GetStyleColorVec4(ImGuiCol_Text);
        if (entry.level == 0) {
            color = ImGui::GetStyleColorVec4(ImGuiCol_TextDisabled);
        } else if (entry.level == 2) {
            color = ImVec4(0.95f, 0.7f, 0.2f, 1.0f);
        } else if (entry.level == 3) {
            color = ImVec4(0.95f, 0.4f, 0.35f, 1.0f);
        }
        ImGui::PushStyleColor(ImGuiCol_Text, color);
        ImGui::TextUnformatted(entry.displayLabel.c_str());
        ImGui::PopStyleColor();
        ImGui::Spacing();
    }
    ImGui::PopTextWrapPos();

    if (bridge->_LogAutoScroll && wasAtBottom) {
        ImGui::SetScrollHereY(1.0f);
    }

    ImGui::EndChild();
    ImGui::End();
}

namespace {
    static int NodeInputCountForType(int32_t type) {
        switch (type) {
            case 0: return 1; // OutputPose
            case 1: return 0; // ClipPlayer
            case 2: return 1; // Blend1D parameter input
            case 3: return 2; // Blend2D parameter inputs
            case 4: return 0; // StateMachine
            case 24: return 1; // SetLocalFloat
            case 25: return 1; // SetLocalBool
            case 26: return 1; // SetLocalInt
            default: return 0;
        }
    }

    static int NodeOutputCountForType(int32_t type) {
        switch (type) {
            case 0: return 0; // OutputPose
            case 24: return 1; // SetLocalFloat passthrough
            case 25: return 1; // SetLocalBool passthrough
            case 26: return 1; // SetLocalInt passthrough
            default: return 1;
        }
    }

    static const char *NodeTypeLabel(int32_t type) {
        switch (type) {
            case 0: return "Output Pose";
            case 1: return "Clip Player";
            case 2: return "Blend1D";
            case 3: return "Blend2D";
            case 4: return "State Machine";
            case 8: return "Parameter Float";
            case 9: return "Parameter Bool";
            case 10: return "Parameter Trigger";
            case 20: return "Parameter Int";
            case 21: return "Local Float";
            case 22: return "Local Bool";
            case 23: return "Local Int";
            case 24: return "Set Local Float";
            case 25: return "Set Local Bool";
            case 26: return "Set Local Int";
            default: return "Unknown";
        }
    }

    static const char *ParameterTypeLabel(int32_t type) {
        switch (type) {
            case 0: return "Float";
            case 1: return "Bool";
            case 2: return "Int";
            case 3: return "Trigger";
            default: return "Float";
        }
    }

    static int32_t ScriptSetterToParameterType(const std::string &setterName) {
        if (setterName == "Float") { return 0; }
        if (setterName == "Bool") { return 1; }
        if (setterName == "Trigger") { return 3; }
        return 0;
    }

    static std::string TruncatedLabel(const std::string &value, size_t maxChars) {
        if (value.size() <= maxChars) { return value; }
        if (maxChars < 4) { return value.substr(0, maxChars); }
        return value.substr(0, maxChars - 3) + "...";
    }

    static std::string NodeQuickLine(const AnimationGraphNodeRecord &node) {
        switch (node.type) {
            case 1:
                return node.clipHandle.empty() ? std::string("clip <none>")
                                               : std::string("clip ") + TruncatedLabel(node.clipHandle, 18);
            case 2: {
                const std::string param = node.blend1DParameterName.empty() ? "<param>" : node.blend1DParameterName;
                return "param " + TruncatedLabel(param, 14) + "  samples " + std::to_string(node.blend1DSamples.size());
            }
            case 3: {
                const std::string x = node.blend2DParameterXName.empty() ? "<x>" : node.blend2DParameterXName;
                const std::string y = node.blend2DParameterYName.empty() ? "<y>" : node.blend2DParameterYName;
                return "x " + TruncatedLabel(x, 9) + "  y " + TruncatedLabel(y, 9);
            }
            case 4:
                return "states " + std::to_string(node.stateMachineStates.size()) +
                    "  trans " + std::to_string(node.stateMachineTransitions.size());
            default:
                return "";
        }
    }

    static const AnimationGraphNodeRecord *FindNodeById(const AnimationGraphSnapshot &snapshot, const std::string &nodeId) {
        for (const auto &node : snapshot.nodes) {
            if (node.id == nodeId) { return &node; }
        }
        return nullptr;
    }

    static const AnimationGraphNodeRecord::StateMachineStateRecord *FindStateInMachine(const AnimationGraphNodeRecord &machineNode,
                                                                                        const std::string &stateId) {
        for (const auto &state : machineNode.stateMachineStates) {
            if (state.id == stateId) { return &state; }
        }
        return nullptr;
    }

    static const AnimationGraphNodeRecord::StateMachineTransitionRecord *FindTransitionInMachine(const AnimationGraphNodeRecord &machineNode,
                                                                                                  const std::string &transitionId) {
        for (const auto &transition : machineNode.stateMachineTransitions) {
            if (transition.id == transitionId) { return &transition; }
        }
        return nullptr;
    }
    static void DrawAnimationGraphPanel(ImGuiBridge *bridge, bool *isOpen) {
        if (!isOpen || !*isOpen) {
            AnimationGraphUIStateStore::PruneStateToActiveGraph("");
            return;
        }
        auto *uiState = static_cast<MCEPanelState::EditorUIPanelState *>(MCEContextGetUIPanelState(bridge->_context));
        ::DrawAnimationGraphPanel(bridge->_context, uiState->animationGraph, bridge->_SelectedEntityId, isOpen);
    }
}

static void DrawSettingsModal(ImGuiBridge *bridge) {
    bool requestOpen = bridge->_ShowSettingsModal;
    bridge->_ShowSettingsModal = false;
    ImGui::SetNextWindowSizeConstraints(ImVec2(720.0f, 520.0f), ImVec2(1040.0f, 860.0f));
    ImGui::SetNextWindowSize(ImVec2(900.0f, 700.0f), ImGuiCond_Once);
    if (!EditorUI::BeginModal("Settings", &requestOpen, nullptr, ImGuiWindowFlags_None)) {
        return;
    }
    static const struct {
        EditorIcons::Id icon;
        const char *label;
    } kCategories[] = {
        { EditorIcons::Id::Folder, "General" },
        { EditorIcons::Id::Material, "UI & Theme" },
        { EditorIcons::Id::Camera, "Viewport" },
        { EditorIcons::Id::Translate, "Gizmos & Snapping" },
        { EditorIcons::Id::Select, "Selection & Picking" },
        { EditorIcons::Id::Mesh, "Rendering" },
        { EditorIcons::Id::DirectionalLight, "Lighting & Sky / IBL" },
        { EditorIcons::Id::Warning, "Shadows" },
        { EditorIcons::Id::Simulate, "Physics" },
        { EditorIcons::Id::Texture, "Assets & Import" },
        { EditorIcons::Id::File, "Debug / Experimental" }
    };
    bridge->_SettingsCategoryIndex = std::max(0, std::min(bridge->_SettingsCategoryIndex, static_cast<int>(IM_ARRAYSIZE(kCategories) - 1)));

    auto Info = [&](const char *text) {
        EditorUI::InfoIconTooltip(text, 420.0f);
    };

    const float footerHeight = 46.0f;
    ImVec2 fullAvail = ImGui::GetContentRegionAvail();
    ImVec2 contentSize(fullAvail.x, std::max(220.0f, fullAvail.y - footerHeight));
    ImGui::BeginChild("SettingsContent", contentSize, false);
    const float sidebarWidth = 220.0f;
    ImGui::BeginChild("SettingsSidebar", ImVec2(sidebarWidth, 0.0f), true, ImGuiWindowFlags_AlwaysVerticalScrollbar);
    for (int i = 0; i < IM_ARRAYSIZE(kCategories); ++i) {
        const bool selected = bridge->_SettingsCategoryIndex == i;
        std::string id = "settings_category_" + std::to_string(i);
        if (EditorUI::IconSelectable(id.c_str(), EditorIcons::Glyph(kCategories[i].icon), kCategories[i].label, selected)) {
            bridge->_SettingsCategoryIndex = i;
        }
    }
    ImGui::EndChild();

    ImGui::SameLine();
    ImGui::BeginChild("SettingsPage", ImVec2(0.0f, 0.0f), true, ImGuiWindowFlags_AlwaysVerticalScrollbar);
    const int category = bridge->_SettingsCategoryIndex;
    void *engineContext = MCEContextGetEngineContext(bridge->_context);

    if (category == 0) {
        EditorUI::SectionHeader("General (Editor)");
        if (EditorUI::BeginPropertyTable("SettingsGeneralTable")) {
            bool logsVisible = bridge->_ShowLogsPanel;
            EditorUI::SetNextPropertyInfoTooltip("Shows the Logs panel.\nUnits: N/A.\nPerformance: negligible.\nPersistence: Editor.");
            if (EditorUI::PropertyBool("Show Logs Panel", &logsVisible)) {
                bridge->_ShowLogsPanel = logsVisible;
                SetPanelVisibility(bridge, "Logs", logsVisible);
            }

            bool profilerVisible = bridge->_ShowProfilingPanel;
            EditorUI::SetNextPropertyInfoTooltip("Shows the Profiling panel.\nUnits: N/A.\nPerformance: negligible.\nPersistence: Editor.");
            if (EditorUI::PropertyBool("Show Profiling Panel", &profilerVisible)) {
                bridge->_ShowProfilingPanel = profilerVisible;
                SetPanelVisibility(bridge, "Profiling", profilerVisible);
            }
            EditorUI::EndPropertyTable();
        }
        ImGui::Spacing();
        ImGui::TextWrapped("Settings are stored per-project in editor state files unless stated otherwise.");
    } else if (category == 1) {
        EditorUI::SectionHeader("UI & Theme");
        if (EditorUI::BeginPropertyTable("SettingsThemeTable")) {
            const char *themeItems[] = { "Dark", "Dark Gray", "Light" };
            int mode = gThemeSettings.mode;
            EditorUI::SetNextPropertyInfoTooltip("Chooses the overall editor palette.\nUnits: N/A.\nPerformance: negligible.\nPersistence: Editor.");
            if (EditorUI::PropertyCombo("Theme Mode", &mode, themeItems, IM_ARRAYSIZE(themeItems))) {
                gThemeSettings.mode = mode;
                MCEEditorSetThemeMode(bridge->_context, static_cast<int32_t>(mode));
            }

            EditorUI::SetNextPropertyInfoTooltip("Single accent used for selections, focus, frustum lines, icon highlights, and outline.\nUnits: RGB.\nPerformance: negligible.\nPersistence: Editor.");
            if (EditorUI::PropertyColor3("Accent Color", gThemeSettings.accent)) {
                MCEEditorSetThemeAccent(bridge->_context, gThemeSettings.accent[0], gThemeSettings.accent[1], gThemeSettings.accent[2]);
            }

            float uiScale = gThemeSettings.uiScale;
            EditorUI::SetNextPropertyInfoTooltip("Global UI scale.\nUnits: scale factor.\nPerformance: minimal.\nPersistence: Editor.");
            if (EditorUI::PropertyFloat("UI Scale", &uiScale, 0.01f, 0.75f, 2.0f, "%.2f", true, false)) {
                gThemeSettings.uiScale = uiScale;
                MCEEditorSetThemeUIScale(bridge->_context, uiScale);
            }

            bool rounded = gThemeSettings.roundedUI;
            EditorUI::SetNextPropertyInfoTooltip("Enables rounded corners across editor chrome.\nUnits: boolean.\nPerformance: negligible.\nPersistence: Editor.");
            if (EditorUI::PropertyBool("Rounded UI", &rounded)) {
                gThemeSettings.roundedUI = rounded;
                MCEEditorSetThemeRoundedUI(bridge->_context, rounded ? 1 : 0);
            }

            float rounding = gThemeSettings.cornerRounding;
            EditorUI::SetNextPropertyInfoTooltip("Corner radius when Rounded UI is enabled.\nUnits: pixels.\nPerformance: negligible.\nPersistence: Editor.");
            if (EditorUI::PropertyFloat("Corner Radius (px)", &rounding, 0.1f, 0.0f, 16.0f, "%.1f", true, false)) {
                gThemeSettings.cornerRounding = rounding;
                MCEEditorSetThemeCornerRounding(bridge->_context, rounding);
            }

            const char *spacingItems[] = { "Compact", "Comfortable", "Spacious" };
            int spacing = gThemeSettings.spacingPreset;
            EditorUI::SetNextPropertyInfoTooltip("Layout density preset.\nUnits: preset.\nPerformance: negligible.\nPersistence: Editor.");
            if (EditorUI::PropertyCombo("Spacing Preset", &spacing, spacingItems, IM_ARRAYSIZE(spacingItems))) {
                gThemeSettings.spacingPreset = spacing;
                MCEEditorSetThemeSpacingPreset(bridge->_context, spacing);
            }
            EditorUI::EndPropertyTable();
        }
        ImGui::Spacing();
        ImGui::TextWrapped("Theme settings are saved per-editor project state and applied every frame.");
    } else if (category == 2) {
        EditorUI::SectionHeader("Viewport / Overlays");
        if (EditorUI::BeginPropertyTable("SettingsViewportTable")) {
            bool showIcons = MCEEditorGetViewportShowWorldIcons(bridge->_context) != 0;
            EditorUI::SetNextPropertyInfoTooltip("Show camera/light/probe icons in world space (edit mode).\nUnits: boolean.\nPerformance: low overlay cost.\nPersistence: Editor.");
            if (EditorUI::PropertyBool("Show World Icons", &showIcons)) {
                MCEEditorSetViewportShowWorldIcons(bridge->_context, showIcons ? 1 : 0);
            }

            float baseSize = MCEEditorGetViewportWorldIconBaseSize(bridge->_context);
            EditorUI::SetNextPropertyInfoTooltip("Base icon size before distance attenuation.\nUnits: pixels.\nPerformance: negligible.\nPersistence: Editor.");
            if (EditorUI::PropertyFloat("Base Icon Size (px)", &baseSize, 0.25f, 8.0f, 48.0f, "%.1f", true, false)) {
                MCEEditorSetViewportWorldIconBaseSize(bridge->_context, baseSize);
            }

            float distanceScale = MCEEditorGetViewportWorldIconDistanceScale(bridge->_context);
            EditorUI::SetNextPropertyInfoTooltip("Distance attenuation scale for world icons.\nUnits: scalar.\nPerformance: negligible.\nPersistence: Editor.");
            if (EditorUI::PropertyFloat("Distance Scale", &distanceScale, 0.01f, 0.1f, 2.0f, "%.2f", true, false)) {
                MCEEditorSetViewportWorldIconDistanceScale(bridge->_context, distanceScale);
            }

            float minSize = MCEEditorGetViewportWorldIconMinSize(bridge->_context);
            EditorUI::SetNextPropertyInfoTooltip("Minimum icon size clamp.\nUnits: pixels.\nPerformance: negligible.\nPersistence: Editor.");
            if (EditorUI::PropertyFloat("Min Icon Size (px)", &minSize, 0.25f, 4.0f, 48.0f, "%.1f", true, false)) {
                MCEEditorSetViewportWorldIconMinSize(bridge->_context, minSize);
            }

            float maxSize = MCEEditorGetViewportWorldIconMaxSize(bridge->_context);
            EditorUI::SetNextPropertyInfoTooltip("Maximum icon size clamp.\nUnits: pixels.\nPerformance: negligible.\nPersistence: Editor.");
            if (EditorUI::PropertyFloat("Max Icon Size (px)", &maxSize, 0.25f, 8.0f, 64.0f, "%.1f", true, false)) {
                MCEEditorSetViewportWorldIconMaxSize(bridge->_context, maxSize);
            }
            float iconOpacity = MCEEditorGetViewportWorldIconsOpacity(bridge->_context);
            EditorUI::SetNextPropertyInfoTooltip("Overall world-icon opacity.\nUnits: normalized alpha.\nPerformance: negligible.\nPersistence: Editor.");
            if (EditorUI::PropertyFloat("Icon Opacity", &iconOpacity, 0.025f, 0.0f, 1.0f, "%.2f", true, false)) {
                MCEEditorSetViewportWorldIconsOpacity(bridge->_context, iconOpacity);
            }
            EditorUI::EndPropertyTable();
        }
        EditorUI::StandardSpacing();

        EditorUI::SectionHeader("Camera Frustums");
        DrawViewportDebugStyleControls(
            bridge->_context,
            "SettingsCameraFrustumsTable",
            ViewportDebugCategory::CameraFrustums,
            "Enabled",
            "Color",
            "Thickness",
            "Opacity",
            "Show selected camera frustums in edit mode.\nUnits: boolean.\nPerformance: low overlay cost.\nPersistence: Editor.",
            "Camera frustum line color.\nUnits: RGB.\nPersistence: Editor.",
            "Camera frustum line thickness.\nUnits: world debug line width.\nPersistence: Editor.",
            "Camera frustum opacity.\nUnits: normalized alpha.\nPersistence: Editor."
        );
        EditorUI::StandardSpacing();

        EditorUI::SectionHeader("Reflection Probes");
        ImGui::TextWrapped("These are editor-side viewport debug visuals. They are independent from grid controls and reflection shading.");
        ImGui::Spacing();
        if (ImGui::TreeNodeEx("ReflectionProbeInfluenceSettings", ImGuiTreeNodeFlags_DefaultOpen, "Influence")) {
            DrawViewportDebugStyleControls(
                bridge->_context,
                "SettingsProbeInfluenceTable",
                ViewportDebugCategory::ReflectionProbeInfluence,
                "Enabled",
                "Color",
                "Thickness",
                "Opacity",
                "Show reflection probe influence bounds.\nUnits: boolean.\nPerformance: low overlay cost.\nPersistence: Editor.",
                "Influence box color.\nUnits: RGB.\nPersistence: Editor.",
                "Influence line thickness.\nUnits: world debug line width.\nPersistence: Editor.",
                "Influence box opacity.\nUnits: normalized alpha.\nPersistence: Editor."
            );
            ImGui::TreePop();
        }
        if (ImGui::TreeNodeEx("ReflectionProbeBlendShellSettings", ImGuiTreeNodeFlags_DefaultOpen, "Blend Shell")) {
            DrawViewportDebugStyleControls(
                bridge->_context,
                "SettingsProbeBlendShellTable",
                ViewportDebugCategory::ReflectionProbeBlendShell,
                "Enabled",
                "Color",
                "Thickness",
                "Opacity",
                "Show reflection probe blend shell bounds.\nUnits: boolean.\nPerformance: low overlay cost.\nPersistence: Editor.",
                "Blend shell color.\nUnits: RGB.\nPersistence: Editor.",
                "Blend shell line thickness.\nUnits: world debug line width.\nPersistence: Editor.",
                "Blend shell opacity.\nUnits: normalized alpha.\nPersistence: Editor."
            );
            if (EditorUI::BeginPropertyTable("SettingsProbeBlendShellFlagsTable")) {
                bool showInner = MCEEditorGetViewportProbeShellShowInnerBox(bridge->_context) != 0;
                EditorUI::SetNextPropertyInfoTooltip("Show the inner authored probe influence box inside the shell visualization.\nUnits: boolean.\nPersistence: Editor.");
                if (EditorUI::PropertyBool("Show Inner Box", &showInner)) {
                    MCEEditorSetViewportProbeShellShowInnerBox(bridge->_context, showInner ? 1 : 0);
                }
                bool showOuter = MCEEditorGetViewportProbeShellShowOuterBox(bridge->_context) != 0;
                EditorUI::SetNextPropertyInfoTooltip("Show the outer fade extent for the probe shell visualization.\nUnits: boolean.\nPersistence: Editor.");
                if (EditorUI::PropertyBool("Show Outer Box", &showOuter)) {
                    MCEEditorSetViewportProbeShellShowOuterBox(bridge->_context, showOuter ? 1 : 0);
                }
                bool showConnectors = MCEEditorGetViewportProbeShellShowConnectorLines(bridge->_context) != 0;
                EditorUI::SetNextPropertyInfoTooltip("Show connector lines between inner influence bounds and outer fade bounds.\nUnits: boolean.\nPersistence: Editor.");
                if (EditorUI::PropertyBool("Show Connectors", &showConnectors)) {
                    MCEEditorSetViewportProbeShellShowConnectorLines(bridge->_context, showConnectors ? 1 : 0);
                }
                EditorUI::EndPropertyTable();
            }
            ImGui::TreePop();
        }
        if (ImGui::TreeNodeEx("ReflectionProbeLinksSettings", ImGuiTreeNodeFlags_DefaultOpen, "Selection Links")) {
            DrawViewportDebugStyleControls(
                bridge->_context,
                "SettingsProbeLinksTable",
                ViewportDebugCategory::ReflectionProbeLinks,
                "Enabled",
                "Color",
                "Thickness",
                "Opacity",
                "Show object-to-probe selection links and fallback markers.\nUnits: boolean.\nPerformance: low overlay cost.\nPersistence: Editor.",
                "Selection-link color.\nUnits: RGB.\nPersistence: Editor.",
                "Selection-link thickness.\nUnits: world debug line width.\nPersistence: Editor.",
                "Selection-link opacity.\nUnits: normalized alpha.\nPersistence: Editor."
            );
            ImGui::TreePop();
        }
        EditorUI::StandardSpacing();

        EditorUI::SectionHeader("Physics Overlays");
        DrawViewportDebugStyleControls(
            bridge->_context,
            "SettingsPhysicsOverlaysTable",
            ViewportDebugCategory::Physics,
            "Enabled",
            "Color",
            "Thickness",
            "Opacity",
            "Enable physics debug wireframe overlays.\nUnits: boolean.\nPerformance: medium on heavy scenes.\nPersistence: Editor.",
            "Physics debug overlay tint.\nUnits: RGB.\nPersistence: Editor.",
            "Physics debug line thickness.\nUnits: world debug line width.\nPersistence: Editor.",
            "Physics debug overlay opacity.\nUnits: normalized alpha.\nPersistence: Editor."
        );
        EditorUI::StandardSpacing();

        EditorUI::SectionHeader("Generic Debug");
        if (ImGui::TreeNodeEx("GenericDebugLinesSettings", ImGuiTreeNodeFlags_None, "Generic Lines")) {
            DrawViewportDebugStyleControls(
                bridge->_context,
                "SettingsGenericLinesTable",
                ViewportDebugCategory::GenericLines,
                "Enabled",
                "Color",
                "Thickness",
                "Opacity",
                "Enable generic editor debug lines.\nUnits: boolean.\nPerformance: low overlay cost.\nPersistence: Editor.",
                "Generic debug line color.\nUnits: RGB.\nPersistence: Editor.",
                "Generic debug line thickness.\nUnits: world debug line width.\nPersistence: Editor.",
                "Generic debug line opacity.\nUnits: normalized alpha.\nPersistence: Editor."
            );
            ImGui::TreePop();
        }
        if (ImGui::TreeNodeEx("GenericDebugShapesSettings", ImGuiTreeNodeFlags_None, "Generic Shapes")) {
            DrawViewportDebugStyleControls(
                bridge->_context,
                "SettingsGenericShapesTable",
                ViewportDebugCategory::GenericShapes,
                "Enabled",
                "Color",
                "Thickness",
                "Opacity",
                "Enable generic editor debug shapes.\nUnits: boolean.\nPerformance: low overlay cost.\nPersistence: Editor.",
                "Generic debug shape color.\nUnits: RGB.\nPersistence: Editor.",
                "Generic debug shape thickness.\nUnits: world debug line width.\nPersistence: Editor.",
                "Generic debug shape opacity.\nUnits: normalized alpha.\nPersistence: Editor."
            );
            ImGui::TreePop();
        }
        EditorUI::StandardSpacing();

        EditorUI::SectionHeader("Camera Preview");
        if (EditorUI::BeginPropertyTable("SettingsViewportPreviewTable")) {

            bool previewEnabled = MCEEditorGetViewportPreviewEnabled(bridge->_context) != 0;
            EditorUI::SetNextPropertyInfoTooltip("Enable camera preview overlay in viewport.\nUnits: boolean.\nPerformance: moderate extra pass.\nPersistence: Editor.");
            if (EditorUI::PropertyBool("Enable Preview", &previewEnabled)) {
                MCEEditorSetViewportPreviewEnabled(bridge->_context, previewEnabled ? 1 : 0);
            }

            float previewSize = MCEEditorGetViewportPreviewSize(bridge->_context);
            EditorUI::SetNextPropertyInfoTooltip("Preview size as viewport fraction.\nUnits: normalized fraction.\nPerformance: moderate extra pass.\nPersistence: Editor.");
            if (EditorUI::PropertyFloat("Preview Size", &previewSize, 0.01f, 0.15f, 0.5f, "%.2f", true, false)) {
                MCEEditorSetViewportPreviewSize(bridge->_context, previewSize);
            }

            const char *previewPosItems[] = { "Top-left", "Top-right", "Bottom-left", "Bottom-right" };
            int previewPos = static_cast<int>(MCEEditorGetViewportPreviewPosition(bridge->_context));
            EditorUI::SetNextPropertyInfoTooltip("Preview anchor location.\nUnits: preset.\nPerformance: negligible.\nPersistence: Editor.");
            if (EditorUI::PropertyCombo("Preview Position", &previewPos, previewPosItems, IM_ARRAYSIZE(previewPosItems))) {
                MCEEditorSetViewportPreviewPosition(bridge->_context, previewPos);
            }
            EditorUI::EndPropertyTable();
        }
        EditorUI::StandardSpacing();
        EditorUI::SectionHeader("Viewport Grid");
        ImGui::TextWrapped("These controls are project renderer settings and apply immediately.");
        ImGuiRendererSettingsCategoryDraw(bridge->_context, ImGuiRendererSettingsCategoryViewportOverlays);
    } else if (category == 3) {
        EditorUI::SectionHeader("Gizmos & Snapping");
        if (EditorUI::BeginPropertyTable("SettingsGizmoTable")) {
            bool snapEnabled = MCEEditorGetViewportSnapEnabled(bridge->_context) != 0;
            EditorUI::SetNextPropertyInfoTooltip("Default snap toggle for transform gizmos.\nUnits: boolean.\nPerformance: negligible.\nPersistence: Project.");
            if (EditorUI::PropertyBool("Snap Enabled", &snapEnabled)) {
                MCEEditorSetViewportSnapEnabled(bridge->_context, snapEnabled ? 1 : 0);
            }
            EditorUI::EndPropertyTable();
        }
    } else if (category == 4) {
        EditorUI::SectionHeader("Selection & Picking");
        if (EditorUI::BeginPropertyTable("SettingsSelectionTable")) {
            bool outlineVisible = MCERendererGetOutlineEnabled(engineContext) != 0;
            EditorUI::SetNextPropertyInfoTooltip("Selection outline visibility.\nUnits: boolean.\nPerformance: low-to-medium.\nPersistence: Project.");
            if (EditorUI::PropertyBool("Show Selection Outline", &outlineVisible)) {
                MCERendererSetOutlineEnabled(engineContext, outlineVisible ? 1 : 0);
                MCESceneNotifyMutation(bridge->_context);
            }
            EditorUI::EndPropertyTable();
        }
        EditorUI::StandardSpacing();
        EditorUI::SectionHeader("Outline Appearance");
        ImGui::TextWrapped("These controls tune the renderer-side outline style and persist with the scene.");
        ImGuiRendererSettingsCategoryDraw(bridge->_context, ImGuiRendererSettingsCategorySelection);
    } else if (category == 5) {
        EditorUI::SectionHeader("Rendering");
        ImGuiRendererSettingsCategoryDraw(bridge->_context, ImGuiRendererSettingsCategoryCore);
    } else if (category == 6) {
        EditorUI::SectionHeader("Lighting & Sky / IBL");
        ImGuiRendererSettingsCategoryDraw(bridge->_context, ImGuiRendererSettingsCategoryLighting);
        ImGui::Spacing();
        ImGui::TextWrapped("Directional and spot light direction is transform-driven (local -Z forward).\nSky sun ray direction remains consistent with this convention.");
    } else if (category == 7) {
        EditorUI::SectionHeader("Shadows");
        ImGuiRendererSettingsCategoryDraw(bridge->_context, ImGuiRendererSettingsCategoryShadows);
    } else if (category == 8) {
        EditorUI::SectionHeader("Physics");
        if (EditorUI::BeginPropertyTable("PhysicsSettingsTable")) {
            bool physicsEnabled = MCEPhysicsGetEnabled(engineContext) != 0;
            EditorUI::SetNextPropertyInfoTooltip("Enable physics simulation.\nUnits: boolean.\nPerformance: medium-to-high depending on scene.\nPersistence: Project.");
            if (EditorUI::PropertyBool("Enable Physics", &physicsEnabled)) {
                MCEPhysicsSetEnabled(engineContext, physicsEnabled ? 1 : 0);
            }

            bool deterministic = MCEPhysicsGetDeterministic(engineContext) != 0;
            EditorUI::SetNextPropertyInfoTooltip("Single-thread deterministic stepping.\nUnits: boolean.\nPerformance: can reduce throughput.\nPersistence: Project.");
            if (EditorUI::PropertyBool("Deterministic Mode", &deterministic)) {
                MCEPhysicsSetDeterministic(engineContext, deterministic ? 1 : 0);
            }
            EditorUI::EndPropertyTable();
        }
        EditorUI::StandardSpacing();
        EditorUI::SectionHeader("Advanced");
        if (EditorUI::BeginPropertyTable("PhysicsAdvancedSettingsTable")) {
            float gx = 0.0f, gy = -9.81f, gz = 0.0f;
            MCEPhysicsGetGravity(engineContext, &gx, &gy, &gz);
            float gravity[3] = { gx, gy, gz };
            EditorUI::SetNextPropertyInfoTooltip("World gravity vector.\nUnits: m/s^2.\nPerformance: scene-dependent.\nPersistence: Project.");
            if (EditorUI::PropertyVec3("Gravity (m/s^2)", gravity, 0.0f, 0.1f, 0.0f, 0.0f, "%.2f", false, true)) {
                MCEPhysicsSetGravity(engineContext, gravity[0], gravity[1], gravity[2]);
            }

            float fixedDelta = MCEPhysicsGetFixedDeltaTime(engineContext);
            EditorUI::SetNextPropertyInfoTooltip("Fixed physics step.\nUnits: seconds.\nPerformance: lower values increase CPU cost.\nPersistence: Project.");
            if (EditorUI::PropertyFloat("Fixed Dt (s)", &fixedDelta, 0.0001f, 0.001f, 0.1f, "%.6f", true, true, 1.0f / 60.0f)) {
                MCEPhysicsSetFixedDeltaTime(engineContext, fixedDelta);
            }

            int maxSubsteps = static_cast<int>(MCEPhysicsGetMaxSubsteps(engineContext));
            EditorUI::SetNextPropertyInfoTooltip("Maximum simulation catch-up steps.\nUnits: count.\nPerformance: higher values increase CPU cost.\nPersistence: Project.");
            if (EditorUI::PropertyInt("Max Substeps", &maxSubsteps, 1, 16)) {
                MCEPhysicsSetMaxSubsteps(engineContext, static_cast<int32_t>(maxSubsteps));
            }

            int maxBodies = static_cast<int>(MCEPhysicsGetMaxBodies(engineContext));
            EditorUI::SetNextPropertyInfoTooltip("Maximum number of physics bodies in the world.\nUnits: count.\nPerformance/Memory: higher values allocate more.\nPersistence: Project.");
            if (EditorUI::PropertyInt("Max Bodies", &maxBodies, 1024, 131072)) {
                MCEPhysicsSetMaxBodies(engineContext, static_cast<uint32_t>(maxBodies));
            }

            int maxBodyPairs = static_cast<int>(MCEPhysicsGetMaxBodyPairs(engineContext));
            EditorUI::SetNextPropertyInfoTooltip("Maximum broad-phase body pairs.\nUnits: count.\nPerformance/Memory: higher values allocate more.\nPersistence: Project.");
            if (EditorUI::PropertyInt("Max Body Pairs", &maxBodyPairs, 1024, 131072)) {
                MCEPhysicsSetMaxBodyPairs(engineContext, static_cast<uint32_t>(maxBodyPairs));
            }

            int maxContactConstraints = static_cast<int>(MCEPhysicsGetMaxContactConstraints(engineContext));
            EditorUI::SetNextPropertyInfoTooltip("Maximum contact constraints.\nUnits: count.\nPerformance/Memory: higher values allocate more.\nPersistence: Project.");
            if (EditorUI::PropertyInt("Max Contact Constraints", &maxContactConstraints, 1024, 131072)) {
                MCEPhysicsSetMaxContactConstraints(engineContext, static_cast<uint32_t>(maxContactConstraints));
            }
            EditorUI::EndPropertyTable();
        }
    } else if (category == 9) {
        EditorUI::SectionHeader("Assets & Import");
        ImGui::TextWrapped("Import defaults are configured per import operation. Reimport keeps handles stable.");
        ImGui::Spacing();
        ImGui::TextWrapped("Asset import and registry settings are saved per-project.");
    } else {
        EditorUI::SectionHeader("Debug / Experimental");
        if (EditorUI::BeginPropertyTable("SettingsDebugTable")) {
            bool outlineEnabled = MCERendererGetOutlineEnabled(engineContext) != 0;
            EditorUI::SetNextPropertyInfoTooltip("Selected entity outline visibility.\nUnits: boolean.\nPerformance: low-to-medium.\nPersistence: Project.");
            if (EditorUI::PropertyBool("Selection Outline", &outlineEnabled)) {
                MCERendererSetOutlineEnabled(engineContext, outlineEnabled ? 1 : 0);
                MCESceneNotifyMutation(bridge->_context);
            }
            EditorUI::EndPropertyTable();
        }
        EditorUI::StandardSpacing();
        EditorUI::SectionHeader("Debug Tools");
        if (ImGui::Button("Raycast From Camera")) {
            MCEEditorDebugPhysicsRaycastFromCamera(bridge->_context, 50.0f);
        }
        ImGui::SameLine();
        Info("Casts a ray from the editor camera and draws one-frame hit debug lines.\nUnits: meters.\nPerformance: negligible.\nPersistence: N/A.");
    }
    ImGui::EndChild();
    ImGui::EndChild();

    ImGui::Separator();
    ImGui::AlignTextToFramePadding();
    ImGui::TextDisabled("Saved per-project/editor as noted.");
    ImGui::SameLine();
    const float closeWidth = 100.0f;
    const float resetWidth = 190.0f;
    const float rightEdge = ImGui::GetContentRegionAvail().x;
    ImGui::SetCursorPosX(std::max(0.0f, rightEdge - closeWidth - resetWidth - ImGui::GetStyle().ItemSpacing.x));
    if (ImGui::Button("Reset Editor UI & Overlays", ImVec2(resetWidth, 0.0f))) {
        gThemeSettings = EditorThemeSettings();
        MCEEditorSetThemeMode(bridge->_context, gThemeSettings.mode);
        MCEEditorSetThemeAccent(bridge->_context, gThemeSettings.accent[0], gThemeSettings.accent[1], gThemeSettings.accent[2]);
        MCEEditorSetThemeUIScale(bridge->_context, gThemeSettings.uiScale);
        MCEEditorSetThemeRoundedUI(bridge->_context, gThemeSettings.roundedUI ? 1 : 0);
        MCEEditorSetThemeCornerRounding(bridge->_context, gThemeSettings.cornerRounding);
        MCEEditorSetThemeSpacingPreset(bridge->_context, gThemeSettings.spacingPreset);
        MCEEditorSetViewportShowWorldIcons(bridge->_context, 1);
        MCEEditorSetViewportWorldIconBaseSize(bridge->_context, 18.0f);
        MCEEditorSetViewportWorldIconDistanceScale(bridge->_context, 0.75f);
        MCEEditorSetViewportWorldIconMinSize(bridge->_context, 11.0f);
        MCEEditorSetViewportWorldIconMaxSize(bridge->_context, 28.0f);
        MCEEditorSetViewportWorldIconsOpacity(bridge->_context, 1.0f);
        MCEEditorSetViewportDebugCategoryEnabled(bridge->_context, ViewportDebugCategory::CameraFrustums, 1);
        MCEEditorSetViewportDebugCategoryColor(bridge->_context, ViewportDebugCategory::CameraFrustums, 1.0f, 0.78f, 0.25f);
        MCEEditorSetViewportDebugCategoryThickness(bridge->_context, ViewportDebugCategory::CameraFrustums, 0.03f);
        MCEEditorSetViewportDebugCategoryOpacity(bridge->_context, ViewportDebugCategory::CameraFrustums, 0.95f);
        MCEEditorSetViewportDebugCategoryEnabled(bridge->_context, ViewportDebugCategory::ReflectionProbeInfluence, 1);
        MCEEditorSetViewportDebugCategoryColor(bridge->_context, ViewportDebugCategory::ReflectionProbeInfluence, 0.25f, 0.95f, 0.95f);
        MCEEditorSetViewportDebugCategoryThickness(bridge->_context, ViewportDebugCategory::ReflectionProbeInfluence, 0.04f);
        MCEEditorSetViewportDebugCategoryOpacity(bridge->_context, ViewportDebugCategory::ReflectionProbeInfluence, 0.95f);
        MCEEditorSetViewportDebugCategoryEnabled(bridge->_context, ViewportDebugCategory::ReflectionProbeBlendShell, 1);
        MCEEditorSetViewportDebugCategoryColor(bridge->_context, ViewportDebugCategory::ReflectionProbeBlendShell, 0.25f, 0.95f, 0.95f);
        MCEEditorSetViewportDebugCategoryThickness(bridge->_context, ViewportDebugCategory::ReflectionProbeBlendShell, 0.03f);
        MCEEditorSetViewportDebugCategoryOpacity(bridge->_context, ViewportDebugCategory::ReflectionProbeBlendShell, 0.55f);
        MCEEditorSetViewportProbeShellShowInnerBox(bridge->_context, 1);
        MCEEditorSetViewportProbeShellShowOuterBox(bridge->_context, 1);
        MCEEditorSetViewportProbeShellShowConnectorLines(bridge->_context, 1);
        MCEEditorSetViewportDebugCategoryEnabled(bridge->_context, ViewportDebugCategory::ReflectionProbeLinks, 1);
        MCEEditorSetViewportDebugCategoryColor(bridge->_context, ViewportDebugCategory::ReflectionProbeLinks, 1.0f, 0.72f, 0.22f);
        MCEEditorSetViewportDebugCategoryThickness(bridge->_context, ViewportDebugCategory::ReflectionProbeLinks, 0.03f);
        MCEEditorSetViewportDebugCategoryOpacity(bridge->_context, ViewportDebugCategory::ReflectionProbeLinks, 0.95f);
        MCEEditorSetViewportDebugCategoryEnabled(bridge->_context, ViewportDebugCategory::Physics, 0);
        MCEEditorSetViewportDebugCategoryColor(bridge->_context, ViewportDebugCategory::Physics, 0.9f, 0.95f, 0.3f);
        MCEEditorSetViewportDebugCategoryThickness(bridge->_context, ViewportDebugCategory::Physics, 0.03f);
        MCEEditorSetViewportDebugCategoryOpacity(bridge->_context, ViewportDebugCategory::Physics, 0.95f);
        MCEEditorSetViewportDebugCategoryEnabled(bridge->_context, ViewportDebugCategory::GenericLines, 1);
        MCEEditorSetViewportDebugCategoryColor(bridge->_context, ViewportDebugCategory::GenericLines, 0.95f, 0.95f, 1.0f);
        MCEEditorSetViewportDebugCategoryThickness(bridge->_context, ViewportDebugCategory::GenericLines, 0.03f);
        MCEEditorSetViewportDebugCategoryOpacity(bridge->_context, ViewportDebugCategory::GenericLines, 0.95f);
        MCEEditorSetViewportDebugCategoryEnabled(bridge->_context, ViewportDebugCategory::GenericShapes, 1);
        MCEEditorSetViewportDebugCategoryColor(bridge->_context, ViewportDebugCategory::GenericShapes, 0.8f, 0.9f, 1.0f);
        MCEEditorSetViewportDebugCategoryThickness(bridge->_context, ViewportDebugCategory::GenericShapes, 0.03f);
        MCEEditorSetViewportDebugCategoryOpacity(bridge->_context, ViewportDebugCategory::GenericShapes, 0.9f);
        MCEEditorSetViewportPreviewEnabled(bridge->_context, 1);
        MCEEditorSetViewportPreviewSize(bridge->_context, 0.28f);
        MCEEditorSetViewportPreviewPosition(bridge->_context, 3);
        MCEEditorSetDebugOutlineEnabled(bridge->_context, 1);
        MCEEditorSetDebugGridEnabled(bridge->_context, 1);
        MCEEditorSetDebugPhysicsEnabled(bridge->_context, 0);
    }
    ImGui::SameLine();
    Info("Reset editor theme, viewport overlay toggles, and debug-visual editor settings to defaults. This does not reset project renderer settings.\nPersistence: Editor.");
    ImGui::SameLine();
    if (ImGui::Button("Close", ImVec2(closeWidth, 0.0f))) {
        ImGui::CloseCurrentPopup();
    }

    ImGui::EndPopup();
}

static void DrawImportModal(void *context) {
    if (MCEImportIsOpen(context) != 0) {
        ImGui::OpenPopup("Import Asset");
    }

    if (!ImGui::BeginPopupModal("Import Asset", nullptr, ImGuiWindowFlags_AlwaysAutoResize)) {
        return;
    }

    char filename[256] = {0};
    char destination[128] = {0};
    MCEImportGetSourceFilename(context, filename, sizeof(filename));
    MCEImportGetDestinationFolder(context, destination, sizeof(destination));
    int32_t typeCode = MCEImportGetPendingAssetType(context);
    const bool isReimport = MCEImportIsReimport(context) != 0;

    ImGui::Text("Source: %s", filename[0] != 0 ? filename : "Unknown");
    ImGui::Text("Destination: %s", destination[0] != 0 ? destination : "Assets");
    if (isReimport) {
        ImGui::TextColored(ImVec4(0.75f, 0.82f, 0.9f, 1.0f), "Reimport (preserve handles)");
    }
    ImGui::Separator();

    if (typeCode == 0) {
        const char *semanticOptions[] = {
            "Auto", "Albedo", "Normal", "Roughness", "Metallic", "Occlusion", "Height", "Emissive", "ORM"
        };
        char semanticValue[64] = {0};
        MCEImportGetOptionString(context, "semantic", semanticValue, sizeof(semanticValue));
        int semanticIndex = 0;
        if (semanticValue[0] != 0) {
            if (strcmp(semanticValue, "albedo") == 0) semanticIndex = 1;
            else if (strcmp(semanticValue, "normal") == 0) semanticIndex = 2;
            else if (strcmp(semanticValue, "roughness") == 0) semanticIndex = 3;
            else if (strcmp(semanticValue, "metallic") == 0) semanticIndex = 4;
            else if (strcmp(semanticValue, "occlusion") == 0) semanticIndex = 5;
            else if (strcmp(semanticValue, "height") == 0) semanticIndex = 6;
            else if (strcmp(semanticValue, "emissive") == 0) semanticIndex = 7;
            else if (strcmp(semanticValue, "orm") == 0) semanticIndex = 8;
        }
        bool semanticIsData = semanticIndex == 2
            || semanticIndex == 3
            || semanticIndex == 4
            || semanticIndex == 5
            || semanticIndex == 6
            || semanticIndex == 8;
        bool semanticIsColor = semanticIndex == 1 || semanticIndex == 7;
        bool srgb = MCEImportGetOptionBool(context, "srgb", semanticIsColor ? 1 : 0) != 0;
        if (semanticIsData) {
            srgb = false;
            MCEImportSetOptionBool(context, "srgb", 0);
        }
        if (semanticIsData) {
            ImGui::BeginDisabled();
        }
        if (ImGui::Checkbox("sRGB", &srgb)) {
            MCEImportSetOptionBool(context, "srgb", srgb ? 1 : 0);
        }
        if (semanticIsData) {
            ImGui::EndDisabled();
            ImGui::TextDisabled("Data textures are always linear.");
        }
        bool mipmaps = MCEImportGetOptionBool(context, "mipmaps", 1) != 0;
        if (ImGui::Checkbox("Generate Mipmaps", &mipmaps)) {
            MCEImportSetOptionBool(context, "mipmaps", mipmaps ? 1 : 0);
        }

        if (ImGui::BeginCombo("Semantic", semanticOptions[semanticIndex])) {
            for (int i = 0; i < 9; ++i) {
                bool selected = (i == semanticIndex);
                if (ImGui::Selectable(semanticOptions[i], selected)) {
                    semanticIndex = i;
                    const char *value = "";
                    switch (i) {
                        case 1: value = "albedo"; break;
                        case 2: value = "normal"; break;
                        case 3: value = "roughness"; break;
                        case 4: value = "metallic"; break;
                        case 5: value = "occlusion"; break;
                        case 6: value = "height"; break;
                        case 7: value = "emissive"; break;
                        case 8: value = "orm"; break;
                        default: value = ""; break;
                    }
                    MCEImportSetOptionString(context, "semantic", value);
                    const bool selectedData = i == 2 || i == 3 || i == 4 || i == 5 || i == 6 || i == 8;
                    const bool selectedColor = i == 1 || i == 7;
                    if (selectedData) {
                        MCEImportSetOptionBool(context, "srgb", 0);
                    } else if (selectedColor) {
                        MCEImportSetOptionBool(context, "srgb", 1);
                    }
                }
                if (selected) {
                    ImGui::SetItemDefaultFocus();
                }
            }
            ImGui::EndCombo();
        }
    } else if (typeCode == 3) {
        bool srgb = false;
        ImGui::BeginDisabled();
        ImGui::Checkbox("sRGB", &srgb);
        ImGui::EndDisabled();
        ImGui::TextDisabled("Environment maps are always imported as linear HDR.");
        MCEImportSetOptionBool(context, "srgb", 0);
        MCEImportSetOptionString(context, "semantic", "environment");
    } else if (typeCode == 1) {
        int32_t meshCount = MCEImportGetMeshCount(context);
        int32_t submeshCount = MCEImportGetSubmeshCount(context);
        ImGui::Text("Meshes: %d", meshCount);
        ImGui::Text("Submeshes: %d", submeshCount);

        bool hasUVs = MCEImportGetMeshHasUVs(context) != 0;
        bool hasNormals = MCEImportGetMeshHasNormals(context) != 0;
        bool hasTangents = MCEImportGetMeshHasTangents(context) != 0;
        ImGui::Text("UVs: %s", hasUVs ? "Yes" : "No");
        ImGui::Text("Normals: %s", hasNormals ? "Yes" : "No");
        ImGui::Text("Tangents: %s", hasTangents ? "Yes" : "No");

        int32_t materialCount = MCEImportGetMaterialCount(context);
        if (materialCount > 0 && ImGui::CollapsingHeader("Materials", ImGuiTreeNodeFlags_DefaultOpen)) {
            for (int32_t i = 0; i < materialCount; ++i) {
                char nameBuffer[128] = {0};
                if (MCEImportGetMaterialNameAt(context, i, nameBuffer, sizeof(nameBuffer)) != 0) {
                    ImGui::BulletText("%s", nameBuffer);
                }
            }
        }

        int32_t textureCount = MCEImportGetTextureCount(context);
        if (textureCount > 0 && ImGui::CollapsingHeader("Textures", ImGuiTreeNodeFlags_DefaultOpen)) {
            for (int32_t i = 0; i < textureCount; ++i) {
                char nameBuffer[128] = {0};
                if (MCEImportGetTextureNameAt(context, i, nameBuffer, sizeof(nameBuffer)) != 0) {
                    ImGui::BulletText("%s", nameBuffer);
                }
            }
        }

        ImGui::Separator();
        bool importMaterials = MCEImportGetOptionBool(context, "importMaterials", 1) != 0;
        if (ImGui::Checkbox("Import Materials", &importMaterials)) {
            MCEImportSetOptionBool(context, "importMaterials", importMaterials ? 1 : 0);
        }
        bool importTextures = MCEImportGetOptionBool(context, "importTextures", 1) != 0;
        if (ImGui::Checkbox("Import Textures", &importTextures)) {
            MCEImportSetOptionBool(context, "importTextures", importTextures ? 1 : 0);
        }
        bool copyTextures = MCEImportGetOptionBool(context, "copyTextures", 1) != 0;
        if (ImGui::Checkbox("Copy Textures into Project", &copyTextures)) {
            MCEImportSetOptionBool(context, "copyTextures", copyTextures ? 1 : 0);
        }
        bool flipNormalY = MCEImportGetOptionBool(context, "flipNormalY", 0) != 0;
        if (ImGui::Checkbox("Flip Normal Y", &flipNormalY)) {
            MCEImportSetOptionBool(context, "flipNormalY", flipNormalY ? 1 : 0);
        }
        bool generateTangents = MCEImportGetOptionBool(context, "generateTangents", 1) != 0;
        if (ImGui::Checkbox("Generate Tangents", &generateTangents)) {
            MCEImportSetOptionBool(context, "generateTangents", generateTangents ? 1 : 0);
        }
        float scale = MCEImportGetOptionFloat(context, "scale", 1.0f);
        if (ImGui::InputFloat("Scale Factor", &scale, 0.1f, 1.0f, "%.3f")) {
            MCEImportSetOptionFloat(context, "scale", scale);
        }
        bool combineORM = MCEImportGetOptionBool(context, "combineORM", 0) != 0;
        if (ImGui::Checkbox("Combine ORM", &combineORM)) {
            MCEImportSetOptionBool(context, "combineORM", combineORM ? 1 : 0);
        }
        bool createPrefab = MCEImportGetOptionBool(context, "createPrefab", 0) != 0;
        if (ImGui::Checkbox("Create Prefab", &createPrefab)) {
            MCEImportSetOptionBool(context, "createPrefab", createPrefab ? 1 : 0);
        }
        bool createHierarchy = MCEImportGetOptionBool(context, "createHierarchy", 0) != 0;
        if (ImGui::Checkbox("Create Hierarchy", &createHierarchy)) {
            MCEImportSetOptionBool(context, "createHierarchy", createHierarchy ? 1 : 0);
        }

        int32_t warningCount = MCEImportGetWarningCount(context);
        if (warningCount > 0) {
            ImGui::Separator();
            for (int32_t i = 0; i < warningCount; ++i) {
                char warningBuffer[256] = {0};
                if (MCEImportGetWarningAt(context, i, warningBuffer, sizeof(warningBuffer)) != 0) {
                    ImGui::TextColored(ImVec4(1.0f, 0.75f, 0.35f, 1.0f), "%s", warningBuffer);
                }
            }
        }
    }

    char errorMessage[256] = {0};
    if (MCEImportGetLastError(context, errorMessage, sizeof(errorMessage)) != 0 && errorMessage[0] != 0) {
        ImGui::Separator();
        ImGui::TextColored(ImVec4(1.0f, 0.35f, 0.35f, 1.0f), "%s", errorMessage);
    }

    ImGui::Separator();
    if (ImGui::Button("Cancel")) {
        MCEImportCancel(context);
        ImGui::CloseCurrentPopup();
    }
    ImGui::SameLine();
    if (ImGui::Button(isReimport ? "Reimport" : "Import")) {
        if (MCEImportCommit(context) != 0) {
            int32_t commitType = MCEImportGetCommitAssetType(context);
            if (commitType == 1) {
                char handleBuffer[64] = {0};
                if (MCEImportGetCommitHandle(context, handleBuffer, sizeof(handleBuffer)) != 0) {
                    char skeletonBuffer[64] = {0};
                    char defaultClipBuffer[64] = {0};
                    char materialHandlesBuffer[2048] = {0};
                    char meshPathBuffer[1024] = {0};
                    (void)MCEImportGetCommitSkeletonHandle(context, skeletonBuffer, sizeof(skeletonBuffer));
                    (void)MCEImportGetCommitDefaultClipHandle(context, defaultClipBuffer, sizeof(defaultClipBuffer));
                    (void)MCEImportGetCommitSubmeshMaterialHandles(context, materialHandlesBuffer, sizeof(materialHandlesBuffer));
                    (void)MCEImportGetCommitMeshPath(context, meshPathBuffer, sizeof(meshPathBuffer));
                    char createdId[64] = {0};
                    MCEEditorCreateImportedMeshEntity(
                        context,
                        handleBuffer,
                        skeletonBuffer[0] != 0 ? skeletonBuffer : nullptr,
                        defaultClipBuffer[0] != 0 ? defaultClipBuffer : nullptr,
                        materialHandlesBuffer[0] != 0 ? materialHandlesBuffer : nullptr,
                        meshPathBuffer[0] != 0 ? meshPathBuffer : nullptr,
                        createdId,
                        sizeof(createdId)
                    );
                }
            }
            MCEImportClearCommitResult(context);
            ImGui::CloseCurrentPopup();
        }
    }

    ImGui::EndPopup();
}

static void DrawProfilingPanel(void *context, bool *isOpen) {
    if (!isOpen || !*isOpen) { return; }
    ImGui::Begin("Profiling", isOpen);

    void *engineContext = MCEContextGetEngineContext(context);
    float frameMs = MCERendererGetFrameMs(engineContext);
    float gpuMs = MCERendererGetGpuMs(engineContext);
    static float frameHistory[120] = {0};
    static float updateHistory[120] = {0};
    static float renderHistory[120] = {0};
    static float postHistory[120] = {0};
    static int frameOffset = 0;
    const float updateMs = MCERendererGetUpdateMs(engineContext);
    const float renderMs = MCERendererGetRenderMs(engineContext);
    const float postMs = MCERendererGetBloomMs(engineContext) + MCERendererGetCompositeMs(engineContext) + MCERendererGetOverlaysMs(engineContext);
    frameHistory[frameOffset] = frameMs;
    updateHistory[frameOffset] = updateMs;
    renderHistory[frameOffset] = renderMs;
    postHistory[frameOffset] = postMs;
    frameOffset = (frameOffset + 1) % IM_ARRAYSIZE(frameHistory);

    static bool autoRange = true;
    static float rangeMin = 0.0f;
    static float rangeMax = 40.0f;
    ImGui::TextUnformatted("Frame History");
    ImGui::SameLine();
    ImGui::TextDisabled("(ms)");
    DrawLegendItem("Frame", ImVec4(0.74f, 0.64f, 0.84f, 1.0f));
    DrawLegendItem("Update", ImVec4(0.36f, 0.62f, 0.44f, 1.0f));
    DrawLegendItem("Render", ImVec4(0.78f, 0.55f, 0.38f, 1.0f));
    DrawLegendItem("Post", ImVec4(0.55f, 0.48f, 0.72f, 1.0f));
    ImGui::NewLine();
    ImGui::Checkbox("Auto Range", &autoRange);

    float minValue = rangeMin;
    float maxValue = rangeMax;
    if (autoRange) {
        minValue = frameHistory[0];
        maxValue = frameHistory[0];
        for (int i = 1; i < IM_ARRAYSIZE(frameHistory); ++i) {
            minValue = std::min(minValue, frameHistory[i]);
            minValue = std::min(minValue, updateHistory[i]);
            minValue = std::min(minValue, renderHistory[i]);
            minValue = std::min(minValue, postHistory[i]);
            maxValue = std::max(maxValue, frameHistory[i]);
            maxValue = std::max(maxValue, updateHistory[i]);
            maxValue = std::max(maxValue, renderHistory[i]);
            maxValue = std::max(maxValue, postHistory[i]);
        }
        maxValue = std::max(minValue + 5.0f, maxValue);
    } else {
        ImGui::SetNextItemWidth(120.0f);
        ImGui::DragFloat("Min##FrameRange", &rangeMin, 0.5f, 0.0f, rangeMax - 1.0f, "%.1f");
        ImGui::SameLine();
        ImGui::SetNextItemWidth(120.0f);
        ImGui::DragFloat("Max##FrameRange", &rangeMax, 0.5f, rangeMin + 1.0f, 200.0f, "%.1f");
        minValue = rangeMin;
        maxValue = rangeMax;
    }

    ImVec2 graphSize(ImGui::GetContentRegionAvail().x, 110.0f);
    ImVec2 graphMin = ImGui::GetCursorScreenPos();
    ImGui::InvisibleButton("##FrameHistoryGraph", graphSize);
    ImVec2 graphMax(graphMin.x + graphSize.x, graphMin.y + graphSize.y);

    ImDrawList *drawList = ImGui::GetWindowDrawList();
    drawList->AddRectFilled(graphMin, graphMax, IM_COL32(24, 24, 27, 255), 4.0f);
    drawList->AddRect(graphMin, graphMax, IM_COL32(60, 60, 66, 255), 4.0f);

    const ImU32 frameColor = IM_COL32(189, 164, 214, 255);
    const ImU32 updateColor = IM_COL32(92, 158, 112, 255);
    const ImU32 renderColor = IM_COL32(198, 140, 98, 255);
    const ImU32 postColor = IM_COL32(140, 122, 183, 255);
    DrawHistorySeries(drawList, graphMin, graphMax, frameHistory, IM_ARRAYSIZE(frameHistory), frameOffset, minValue, maxValue, frameColor);
    DrawHistorySeries(drawList, graphMin, graphMax, updateHistory, IM_ARRAYSIZE(updateHistory), frameOffset, minValue, maxValue, updateColor);
    DrawHistorySeries(drawList, graphMin, graphMax, renderHistory, IM_ARRAYSIZE(renderHistory), frameOffset, minValue, maxValue, renderColor);
    DrawHistorySeries(drawList, graphMin, graphMax, postHistory, IM_ARRAYSIZE(postHistory), frameOffset, minValue, maxValue, postColor);

    char maxLabel[32] = {0};
    char minLabel[32] = {0};
    snprintf(maxLabel, sizeof(maxLabel), "%.1f ms", maxValue);
    snprintf(minLabel, sizeof(minLabel), "%.1f ms", minValue);
    drawList->AddText(ImVec2(graphMin.x + 6.0f, graphMin.y + 4.0f), IM_COL32(180, 180, 185, 255), maxLabel);
    drawList->AddText(ImVec2(graphMin.x + 6.0f, graphMax.y - 18.0f), IM_COL32(180, 180, 185, 255), minLabel);

    ImGui::Separator();
    ImGui::Text("Frame: %.2f ms", frameMs);
    ImGui::Text("GPU:   %.2f ms", gpuMs);

    ImGui::Separator();
    ImGui::TextUnformatted("CPU Breakdown");
    ImGui::Text("Update:     %.2f ms", MCERendererGetUpdateMs(engineContext));
    ImGui::Text("  Scene Update: %.2f ms", MCERendererGetSceneUpdateMs(engineContext));
    ImGui::Text("  Fixed Update: %.2f ms", MCERendererGetFixedUpdateMs(engineContext));
    ImGui::Text("  Late Update: %.2f ms", MCERendererGetLateUpdateMs(engineContext));
    ImGui::Text("  Snapshot Extract: %.2f ms", MCERendererGetSnapshotExtractMs(engineContext));
    ImGui::Text("  RenderGraph Encode: %.2f ms", MCERendererGetRenderGraphEncodeMs(engineContext));
    ImGui::Text("    Script Fixed: %.2f ms", MCERendererGetScriptFixedMs(engineContext));
    ImGui::Text("    Character Fixed: %.2f ms", MCERendererGetCharacterFixedMs(engineContext));
    ImGui::Text("    Physics Step: %.2f ms", MCERendererGetPhysicsStepMs(engineContext));
    ImGui::Text("    Physics Events: %.2f ms", MCERendererGetPhysicsEventsMs(engineContext));
    ImGui::Text("    Script Physics Dispatch: %.2f ms", MCERendererGetScriptPhysicsDispatchMs(engineContext));
    ImGui::Text("Scene:      %.2f ms", MCERendererGetSceneMs(engineContext));
    ImGui::Text("Render:     %.2f ms", MCERendererGetRenderMs(engineContext));
    ImGui::Text("Render Batches: %.2f ms", MCERendererGetRenderBatchMs(engineContext));
    ImGui::Text("Bloom:      %.2f ms", MCERendererGetBloomMs(engineContext));
    ImGui::Text("  Extract:  %.2f ms", MCERendererGetBloomExtractMs(engineContext));
    ImGui::Text("  Downsample: %.2f ms", MCERendererGetBloomDownsampleMs(engineContext));
    ImGui::Text("  Blur:     %.2f ms", MCERendererGetBloomBlurMs(engineContext));
    ImGui::Text("Composite:  %.2f ms", MCERendererGetCompositeMs(engineContext));
    ImGui::Text("Overlays:   %.2f ms", MCERendererGetOverlaysMs(engineContext));
    ImGui::Text("Present:    %.2f ms", MCERendererGetPresentMs(engineContext));

    ImGui::Separator();
    ImGui::TextUnformatted("GPU Passes");
    bool gpuPassSupported = MCERendererGetGpuPassTimingsSupported(engineContext) != 0;
    bool gpuPassTimings = MCERendererGetGpuPassTimingsEnabled(engineContext) != 0;
    if (ImGui::Checkbox("Enable GPU Pass Timings", &gpuPassTimings)) {
        MCERendererSetGpuPassTimingsEnabled(engineContext, gpuPassTimings ? 1 : 0);
    }
    if (gpuPassTimings && !gpuPassSupported) {
        ImGui::TextDisabled("GPU pass timings unsupported on this device.");
    }
#if DEBUG
    char gpuTimingInfo[256] = {};
    MCERendererCopyGpuPassTimingDebugInfo(engineContext, gpuTimingInfo, sizeof(gpuTimingInfo));
    if (gpuTimingInfo[0] != 0) {
        ImGui::TextDisabled("%s", gpuTimingInfo);
    }
#endif
    if (gpuPassTimings && gpuPassSupported) {
        ImGui::Text("Shadows:    %.2f ms", MCERendererGetGpuShadowPassMs(engineContext));
        ImGui::Text("Depth:      %.2f ms", MCERendererGetGpuDepthPrepassMs(engineContext));
        ImGui::Text("Scene:      %.2f ms", MCERendererGetGpuScenePassMs(engineContext));
        ImGui::Text("Grid:       %.2f ms", MCERendererGetGpuGridPassMs(engineContext));
        ImGui::Text("Picking:    %.2f ms", MCERendererGetGpuPickingPassMs(engineContext));
        ImGui::Text("Outline:    %.2f ms", MCERendererGetGpuOutlinePassMs(engineContext));
        ImGui::Text("Bloom Extract: %.2f ms", MCERendererGetGpuBloomExtractPassMs(engineContext));
        ImGui::Text("Bloom Blur: %.2f ms", MCERendererGetGpuBloomBlurPassMs(engineContext));
        ImGui::Text("Composite:  %.2f ms", MCERendererGetGpuFinalCompositePassMs(engineContext));
    }

    ImGui::End();
}

static void EnsureImGuiKeyResponder(NSView *view) {
    if (!view || !view.window) { return; }
    Class responderClass = NSClassFromString(@"KeyEventResponder");
    if (!responderClass) { return; }
    for (NSView *subview in view.subviews) {
        if ([subview isKindOfClass:responderClass]) {
            if (view.window.firstResponder != subview) {
                [view.window makeFirstResponder:subview];
            }
            return;
        }
    }
}

static ImGuiKey MapKeyCode(uint16_t keyCode) {
    switch (keyCode) {
        case 0x31: return ImGuiKey_Space;
        case 0x30: return ImGuiKey_Tab;
        case 0x24: return ImGuiKey_Enter;
        case 0x4C: return ImGuiKey_KeypadEnter;
        case 0x35: return ImGuiKey_Escape;
        case 0x33: return ImGuiKey_Backspace;
        case 0x75: return ImGuiKey_Delete;
        case 0x7B: return ImGuiKey_LeftArrow;
        case 0x7C: return ImGuiKey_RightArrow;
        case 0x7D: return ImGuiKey_DownArrow;
        case 0x7E: return ImGuiKey_UpArrow;
        case 0x00: return ImGuiKey_A;
        case 0x0B: return ImGuiKey_B;
        case 0x08: return ImGuiKey_C;
        case 0x02: return ImGuiKey_D;
        case 0x0E: return ImGuiKey_E;
        case 0x03: return ImGuiKey_F;
        case 0x05: return ImGuiKey_G;
        case 0x04: return ImGuiKey_H;
        case 0x22: return ImGuiKey_I;
        case 0x26: return ImGuiKey_J;
        case 0x28: return ImGuiKey_K;
        case 0x25: return ImGuiKey_L;
        case 0x2E: return ImGuiKey_M;
        case 0x2D: return ImGuiKey_N;
        case 0x1F: return ImGuiKey_O;
        case 0x23: return ImGuiKey_P;
        case 0x0C: return ImGuiKey_Q;
        case 0x0F: return ImGuiKey_R;
        case 0x01: return ImGuiKey_S;
        case 0x11: return ImGuiKey_T;
        case 0x20: return ImGuiKey_U;
        case 0x09: return ImGuiKey_V;
        case 0x0D: return ImGuiKey_W;
        case 0x07: return ImGuiKey_X;
        case 0x10: return ImGuiKey_Y;
        case 0x06: return ImGuiKey_Z;
        case 0x1D: return ImGuiKey_0;
        case 0x12: return ImGuiKey_1;
        case 0x13: return ImGuiKey_2;
        case 0x14: return ImGuiKey_3;
        case 0x15: return ImGuiKey_4;
        case 0x17: return ImGuiKey_5;
        case 0x16: return ImGuiKey_6;
        case 0x1A: return ImGuiKey_7;
        case 0x1C: return ImGuiKey_8;
        case 0x19: return ImGuiKey_9;
        default: return ImGuiKey_None;
    }
}

@implementation ImGuiBridge

- (instancetype)initWithContext:(void *)context {
    self = [super init];
    if (self) {
        _context = context;
        _ImGuiInitialized = false;
        _ViewportHovered = false;
        _ViewportFocused = false;
        _ViewportUIHovered = false;
        _ViewportContentSize = {0, 0};
        _ViewportContentOrigin = {0, 0};
        _ViewportImageOrigin = {0, 0};
        _ViewportImageSize = {0, 0};
        _GizmoCaptureMouse = false;
        _GizmoCaptureKeyboard = false;
        _ShowSceneHierarchyPanel = true;
        _ShowInspectorPanel = true;
        _ShowContentBrowserPanel = true;
        _ShowViewportPanel = true;
        _ShowAnimationGraphPanel = true;
        _ShowProfilingPanel = false;
        _ShowLogsPanel = true;
        _LoadedPanelVisibility = false;
        _SelectedEntityId[0] = 0;
        _LogRevision = 0;
        _LogEntries.clear();
        _LogFilteredIndices.clear();
        _LogFilterDirty = true;
        _LogFilterText[0] = 0;
        _LogFilterTrace = true;
        _LogFilterInfo = true;
        _LogFilterWarn = true;
        _LogFilterError = true;
        _LogShowTrace = true;
        _LogShowInfo = true;
        _LogShowWarn = true;
        _LogShowError = true;
        _LogAutoScroll = true;
    }
    return self;
}

- (void)setupWithView:(MTKView *)view {
    if (_ImGuiInitialized) { return; }
    _ImGuiInitialized = true;

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO();
    (void)io;

    // Store ImGui config in Application Support so it persists with or without sandbox.
    char iniPathBuffer[512] = {0};
    if (MCEEditorGetImGuiIniPath(_context, iniPathBuffer, sizeof(iniPathBuffer)) != 0) {
        io.IniFilename = strdup(iniPathBuffer);
    }

    // Nice defaults
    io.ConfigFlags |= ImGuiConfigFlags_DockingEnable;
    io.ConfigFlags |= ImGuiConfigFlags_ViewportsEnable;
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;
    io.ConfigInputTrickleEventQueue = false;

    ImGui::StyleColorsDark();
    LoadThemeSettingsIfNeeded(_context);
    ApplyEditorTheme(gThemeSettings);
    ImGuiStyle& style = ImGui::GetStyle();
    if (io.ConfigFlags & ImGuiConfigFlags_ViewportsEnable) {
        style.Colors[ImGuiCol_WindowBg].w = 1.0f;
    }

    // Backends
    // OS X backend needs the NSView
    ImGui_ImplOSX_Init(view);
    // Metal backend now only needs the device
    ImGui_ImplMetal_Init(view.device);

    // Prefer the system UI font for macOS.
    const char *fontCandidates[] = {
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/SFNSDisplay.ttf",
        "/System/Library/Fonts/SFNSRounded.ttf"
    };
    bool loadedBaseFont = false;
    for (const char *path : fontCandidates) {
        NSString *fontPath = [NSString stringWithUTF8String:path];
        if ([[NSFileManager defaultManager] fileExistsAtPath:fontPath]) {
            ImFont *font = io.Fonts->AddFontFromFileTTF(path, 14.5f);
            if (font != nullptr) {
                io.FontDefault = font;
                loadedBaseFont = true;
                break;
            }
        }
    }
    if (!loadedBaseFont) {
        io.Fonts->AddFontDefault();
    }

    // Merge Font Awesome Free 7 fonts into the default atlas.
    static const ImWchar iconRanges[] = { 0x0020, 0x00FF, 0xF000, 0xF8FF, 0 };
    ImFontConfig iconConfig {};
    iconConfig.MergeMode = true;
    iconConfig.PixelSnapH = true;
    iconConfig.OversampleH = 1;
    iconConfig.OversampleV = 1;

    const std::string solidFontPath = ResolveEditorIconFontPath("FA7Free-Solid-900.otf");
    const std::string regularFontPath = ResolveEditorIconFontPath("FA7Free-Regular-400.otf");
    if (solidFontPath.empty()) {
        MCEEditorLogMessage(_context, 3, 1,
                            "Bundled Editor icon font is missing: Icons/FA7Free-Solid-900.otf");
    }
    if (regularFontPath.empty()) {
        MCEEditorLogMessage(_context, 3, 1,
                            "Bundled Editor icon font is missing: Icons/FA7Free-Regular-400.otf");
    }

    bool loadedAnyIconFont = false;
    bool loadedAllIconFonts = !solidFontPath.empty() && !regularFontPath.empty();
    if (!solidFontPath.empty()) {
        ImFont *solidFont = io.Fonts->AddFontFromFileTTF(solidFontPath.c_str(), 13.0f, &iconConfig, iconRanges);
        if (solidFont == nullptr) {
            loadedAllIconFonts = false;
            MCEEditorLogMessage(_context, 3, 1,
                                "Failed to load bundled Editor icon font: Icons/FA7Free-Solid-900.otf");
        } else {
            loadedAnyIconFont = true;
        }
    }
    if (!regularFontPath.empty()) {
        ImFont *regularFont = io.Fonts->AddFontFromFileTTF(regularFontPath.c_str(), 13.0f, &iconConfig, iconRanges);
        if (regularFont == nullptr) {
            loadedAllIconFonts = false;
            MCEEditorLogMessage(_context, 3, 1,
                                "Failed to load bundled Editor icon font: Icons/FA7Free-Regular-400.otf");
        } else {
            loadedAnyIconFont = true;
        }
    }
    if (!loadedAnyIconFont) {
        MCEEditorLogMessage(_context, 3, 1,
                            "No bundled Editor icon fonts loaded; icon glyphs will be unavailable.");
    } else if (!loadedAllIconFonts) {
        MCEEditorLogMessage(_context, 3, 1,
                            "The bundled Editor icon font set is incomplete; some icon glyphs may be unavailable.");
    }

    if (!io.Fonts->Build()) {
        MCEEditorLogMessage(_context, 3, 1,
                            "Failed to build the Editor font atlas; embedded default text remains available.");
    }
}

- (void)newFrameWithView:(MTKView *)view deltaTime:(float)dt {
    if (!_ImGuiInitialized) { [self setupWithView:view]; }
    EnsureImGuiKeyResponder(view);

    ImGuiIO& io = ImGui::GetIO();
    io.DeltaTime = (dt > 0.0f) ? dt : (1.0f / 60.0f);

    ImGui_ImplMetal_NewFrame(view.currentRenderPassDescriptor);
    ImGui_ImplOSX_NewFrame(view);
    LoadThemeSettingsIfNeeded(_context);
    ApplyEditorTheme(gThemeSettings);
    void *engineContext = MCEContextGetEngineContext(_context);
    MCEPhysicsSetDebugDrawEnabled(engineContext, MCEEditorGetDebugPhysicsEnabled(_context));
    ImGui::NewFrame();
}

- (void)applyInputStateWithKeys:(const uint8_t *)keys
                       keyCount:(int32_t)keyCount
                       textUTF8:(const char *)textUTF8 {
    ImGuiIO& io = ImGui::GetIO();
    (void)keys;
    (void)keyCount;
    (void)textUTF8;
}

- (void)buildUIWithSceneTexture:(id<MTLTexture> _Nullable)sceneTexture
                 previewTexture:(id<MTLTexture> _Nullable)previewTexture {
    static char _AlertMessage[512] = {0};
    _GizmoCaptureMouse = false;
    _GizmoCaptureKeyboard = false;
    if (_AlertMessage[0] == 0) {
        if (MCEEditorPopNextAlert(_context, _AlertMessage, sizeof(_AlertMessage)) != 0) {
            ImGui::OpenPopup("Error");
        }
    }

    LoadPanelVisibilityIfNeeded(self);
    char pendingAnimationGraphHandle[64] = {0};
    if (MCEEditorConsumeOpenAnimationGraphEditor(_context, pendingAnimationGraphHandle, sizeof(pendingAnimationGraphHandle)) != 0) {
        auto *panelState = static_cast<MCEPanelState::EditorUIPanelState *>(MCEContextGetUIPanelState(_context));
        panelState->animationGraph.activeGraphHandle = pendingAnimationGraphHandle;
        AnimationGraphWorkspaceRouter::ResetWorkspacePathForHandle(panelState->animationGraph.activeGraphHandle);
        panelState->animationGraph.pendingWorkspaceNavigationKind = MCEPanelState::AnimationGraphPanelState::WorkspaceNavigationNone;
        panelState->animationGraph.pendingWorkspaceNodeId.clear();
        panelState->animationGraph.pendingWorkspaceStateId.clear();
        panelState->animationGraph.pendingWorkspaceTransitionId.clear();
        panelState->animationGraph.hasInteractedWithCanvas = false;
        _ShowAnimationGraphPanel = true;
        SetPanelVisibility(self, "AnimationGraph", _ShowAnimationGraphPanel);
    }

    if (ImGui::BeginPopupModal("Error", nullptr, ImGuiWindowFlags_AlwaysAutoResize)) {
        ImGui::TextWrapped("%s", _AlertMessage);
        if (ImGui::Button("OK")) {
            _AlertMessage[0] = 0;
            ImGui::CloseCurrentPopup();
        }
        ImGui::EndPopup();
    }
    DrawImportModal(_context);
    DrawSettingsModal(self);

    // Dockspace host window (fills main viewport)
    ImGuiViewport* vp = ImGui::GetMainViewport();
    ImGui::SetNextWindowPos(vp->Pos);
    ImGui::SetNextWindowSize(vp->Size);
    ImGui::SetNextWindowViewport(vp->ID);

    ImGuiWindowFlags hostFlags =
        ImGuiWindowFlags_NoTitleBar |
        ImGuiWindowFlags_NoCollapse |
        ImGuiWindowFlags_NoResize |
        ImGuiWindowFlags_NoMove |
        ImGuiWindowFlags_NoBringToFrontOnFocus |
        ImGuiWindowFlags_NoNavFocus |
        ImGuiWindowFlags_MenuBar;

    ImGui::PushStyleVar(ImGuiStyleVar_WindowRounding, 0.0f);
    ImGui::PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0.0f);
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(0,0));

    ImGui::Begin("DockSpaceHost", nullptr, hostFlags);

    ImGuiID dockspaceId = ImGui::GetID("MainDockspace");
    ImGui::DockSpace(dockspaceId, ImVec2(0,0), ImGuiDockNodeFlags_PassthruCentralNode);

    // Menu bar
    EditorUI::PushMenuBarStyle();
    if (ImGui::BeginMenuBar()) {
        if (ImGui::BeginMenu("File")) {
            EditorUI::PushMenuPopupStyle();
            if (ImGui::MenuItem("New Project...")) {
                MCEProjectNew(_context);
            }
            if (ImGui::MenuItem("Open Project...")) {
                MCEProjectOpen(_context);
            }
            bool hasProject = MCEProjectHasOpen(_context) != 0;
            bool sceneDirty = MCESceneIsDirty(_context) != 0;
            if (ImGui::MenuItem("Save", nullptr, false, hasProject && sceneDirty)) {
                MCEProjectSaveAll(_context);
            }
            int32_t recentCount = MCEProjectRecentCount(_context);
            if (ImGui::BeginMenu("Recent Projects", recentCount > 0)) {
                if (recentCount == 0) {
                    ImGui::MenuItem("No recent projects", nullptr, false, false);
                }
                for (int32_t i = 0; i < recentCount && i < 10; ++i) {
                    char pathBuffer[512] = {0};
                    if (MCEProjectRecentPathAt(_context, i, pathBuffer, sizeof(pathBuffer)) <= 0) { continue; }
                    std::string path = pathBuffer;
                    size_t slash = path.find_last_of('/');
                    std::string name = (slash == std::string::npos) ? path : path.substr(slash + 1);
                    std::string label = name + "##recent" + std::to_string(i);
                    if (ImGui::MenuItem(label.c_str())) {
                        MCEProjectOpenRecent(_context, pathBuffer);
                    }
                }
                ImGui::EndMenu();
            }
            ImGui::Separator();
            if (ImGui::MenuItem("Exit")) {
                MCEEditorRequestQuit(_context);
            }
            EditorUI::PopMenuPopupStyle();
            ImGui::EndMenu();
        }
        if (ImGui::BeginMenu("View")) {
            EditorUI::PushMenuPopupStyle();
            DrawPanelMenuItem(self, { "Scene Hierarchy", "SceneHierarchy", &_ShowSceneHierarchyPanel });
            DrawPanelMenuItem(self, { "Properties", "Properties", &_ShowInspectorPanel });
            DrawPanelMenuItem(self, { "Content Browser", "ContentBrowser", &_ShowContentBrowserPanel });
            DrawPanelMenuItem(self, { "Animation Graph", "AnimationGraph", &_ShowAnimationGraphPanel });
            DrawPanelMenuItem(self, { "Profiling", "Profiling", &_ShowProfilingPanel });
            DrawPanelMenuItem(self, { "Logs", "Logs", &_ShowLogsPanel });
            DrawPanelMenuItem(self, { "Viewport", "Viewport", &_ShowViewportPanel });
            EditorUI::PopMenuPopupStyle();
            ImGui::EndMenu();
        }
        if (ImGui::MenuItem("Settings...")) {
            _ShowSettingsModal = true;
        }
        ImGui::SameLine();
        ImGui::SetCursorPosX(ImGui::GetWindowContentRegionMax().x - 140.0f);
        if (MCESceneIsDirty(_context) != 0) {
            ImGui::TextColored(ImVec4(0.95f, 0.7f, 0.2f, 1.0f), "Scene: Modified");
        } else {
            ImGui::TextDisabled("Scene: Saved");
        }
        ImGui::EndMenuBar();
    }
    EditorUI::PopMenuBarStyle();

    ImGui::PopStyleVar(3);

    if (MCEProjectNeedsModal(_context) != 0) {
        ImGui::OpenPopup("Create or Open Project");
    }
    if (ImGui::BeginPopupModal("Create or Open Project", nullptr, ImGuiWindowFlags_AlwaysAutoResize)) {
        ImGui::TextUnformatted("Select a project to get started.");
        if (MCEProjectHasOpen(_context) != 0) {
            if (ImGui::Button("Continue with Loaded Project")) {
                MCEProjectDismissModal(_context);
                ImGui::CloseCurrentPopup();
            }
            ImGui::Separator();
        }

        if (ImGui::Button("Open Other Project...")) {
            MCEProjectOpen(_context);
        }
        ImGui::SameLine();
        if (ImGui::Button("New Project...")) {
            MCEProjectNew(_context);
        }
        ImGui::Separator();

        static int32_t _SelectedProjectIndex = -1;
        static char _SelectedProjectPath[512] = {0};
        static bool _ConfirmDeleteProjectOpen = false;

        ImGui::TextUnformatted("Projects");
        if (ImGui::BeginChild("ProjectList", ImVec2(520, 240), true)) {
            int32_t projectCount = MCEProjectListCount(_context);
            if (projectCount <= 0) {
                ImGui::TextUnformatted("No projects found in the Projects folder.");
            }
            if (ImGui::BeginTable("ProjectTable", 3, ImGuiTableFlags_RowBg | ImGuiTableFlags_BordersInnerV | ImGuiTableFlags_SizingStretchProp)) {
                ImGui::TableSetupColumn("Name", ImGuiTableColumnFlags_WidthStretch);
                ImGui::TableSetupColumn("Path", ImGuiTableColumnFlags_WidthStretch);
                ImGui::TableSetupColumn("Modified", ImGuiTableColumnFlags_WidthFixed, 140.0f);
                ImGui::TableHeadersRow();

                for (int32_t i = 0; i < projectCount; ++i) {
                    char nameBuffer[256] = {0};
                    char pathBuffer[512] = {0};
                    double modified = 0.0;
                    if (MCEProjectListAt(_context, i, nameBuffer, sizeof(nameBuffer), pathBuffer, sizeof(pathBuffer), &modified) == 0) {
                        continue;
                    }
                    ImGui::TableNextRow();
                    ImGui::TableSetColumnIndex(0);
                    ImGui::PushID(i);
                    bool selected = (_SelectedProjectIndex == i);
                    if (ImGui::Selectable(nameBuffer, selected, ImGuiSelectableFlags_SpanAllColumns)) {
                        _SelectedProjectIndex = i;
                        strncpy(_SelectedProjectPath, pathBuffer, sizeof(_SelectedProjectPath) - 1);
                        _SelectedProjectPath[sizeof(_SelectedProjectPath) - 1] = 0;
                    }
                    if (ImGui::IsItemHovered() && ImGui::IsMouseDoubleClicked(0)) {
                        if (MCEProjectOpenAtPath(_context, pathBuffer) != 0) {
                            MCEProjectDismissModal(_context);
                            ImGui::CloseCurrentPopup();
                        }
                    }
                    ImGui::TableSetColumnIndex(1);
                    ImGui::TextUnformatted(pathBuffer);
                    ImGui::TableSetColumnIndex(2);
                    std::string timeText = FormatTimestamp(modified);
                    ImGui::TextUnformatted(timeText.c_str());
                    ImGui::PopID();
                }
                ImGui::EndTable();
            }
        }
        ImGui::EndChild();

        bool hasSelection = _SelectedProjectIndex >= 0 && _SelectedProjectPath[0] != 0;
        if (ImGui::Button("Open Selected") && hasSelection) {
            if (MCEProjectOpenAtPath(_context, _SelectedProjectPath) != 0) {
                MCEProjectDismissModal(_context);
                ImGui::CloseCurrentPopup();
            }
        }
        ImGui::SameLine();
        ImGui::BeginDisabled(!hasSelection);
        if (ImGui::Button("Delete")) {
            _ConfirmDeleteProjectOpen = true;
        }
        ImGui::EndDisabled();
        EditorUI::ConfirmModal("Confirm Delete Project",
                               &_ConfirmDeleteProjectOpen,
                               "Delete the selected project? This will remove it from disk.",
                               "Delete",
                               "Cancel",
                               [&]() {
            MCEProjectDeleteAtPath(_context, _SelectedProjectPath);
            _SelectedProjectIndex = -1;
            _SelectedProjectPath[0] = 0;
        });

        ImGui::EndPopup();
    }

    // --- Panels ---
    bool hierarchyOpen = _ShowSceneHierarchyPanel;
    if (hierarchyOpen) {
        ImGuiSceneHierarchyPanelDraw(_context, &hierarchyOpen, _SelectedEntityId, sizeof(_SelectedEntityId));
        if (hierarchyOpen != _ShowSceneHierarchyPanel) {
            _ShowSceneHierarchyPanel = hierarchyOpen;
            SetPanelVisibility(self, "SceneHierarchy", _ShowSceneHierarchyPanel);
        }
    }

    bool inspectorOpen = _ShowInspectorPanel;
    if (inspectorOpen) {
        ImGuiInspectorPanelDraw(_context, &inspectorOpen, _SelectedEntityId);
        if (inspectorOpen != _ShowInspectorPanel) {
            _ShowInspectorPanel = inspectorOpen;
            SetPanelVisibility(self, "Properties", _ShowInspectorPanel);
            SetPanelVisibility(self, "Inspector", _ShowInspectorPanel);
        }
    }

    bool contentOpen = _ShowContentBrowserPanel;
    if (contentOpen) {
        ImGuiContentBrowserPanelDraw(_context, &contentOpen);
        if (contentOpen != _ShowContentBrowserPanel) {
            _ShowContentBrowserPanel = contentOpen;
            SetPanelVisibility(self, "ContentBrowser", _ShowContentBrowserPanel);
        }
    }

    bool profilingOpen = _ShowProfilingPanel;
    if (profilingOpen) {
        DrawProfilingPanel(_context, &profilingOpen);
        if (profilingOpen != _ShowProfilingPanel) {
            _ShowProfilingPanel = profilingOpen;
            SetPanelVisibility(self, "Profiling", _ShowProfilingPanel);
        }
    }

    bool logsOpen = _ShowLogsPanel;
    if (logsOpen) {
        DrawLogsPanel(self, &logsOpen);
        if (logsOpen != _ShowLogsPanel) {
            _ShowLogsPanel = logsOpen;
            SetPanelVisibility(self, "Logs", _ShowLogsPanel);
        }
    }

    if (_ShowViewportPanel) {
        _ViewportUIHovered = false;
        ImGuiViewportPanelDraw(_context,
                               sceneTexture,
                               previewTexture,
                               _SelectedEntityId,
                               &_ViewportHovered,
                               &_ViewportFocused,
                               &_ViewportUIHovered,
                               &_ViewportContentSize,
                               &_ViewportContentOrigin,
                               &_ViewportImageOrigin,
                               &_ViewportImageSize);
    } else {
        _ViewportUIHovered = false;
    }

    bool animationGraphOpen = _ShowAnimationGraphPanel;
    if (animationGraphOpen) {
        DrawAnimationGraphPanel(self, &animationGraphOpen);
        if (animationGraphOpen != _ShowAnimationGraphPanel) {
            _ShowAnimationGraphPanel = animationGraphOpen;
            SetPanelVisibility(self, "AnimationGraph", _ShowAnimationGraphPanel);
        }
    }

    ImGui::End(); // DockSpaceHost
}

- (void)renderWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
            renderPassDescriptor:(MTLRenderPassDescriptor *)renderPassDescriptor {

    ImGui::Render();

    id<MTLRenderCommandEncoder> encoder =
        [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    if (!encoder) { return; }

    // Draw ImGui into the active render target
    ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), commandBuffer, encoder);

    [encoder endEncoding];

    ImGuiIO& io = ImGui::GetIO();
    if (io.ConfigFlags & ImGuiConfigFlags_ViewportsEnable) {
        ImGui::UpdatePlatformWindows();
        ImGui::RenderPlatformWindowsDefault();
    }
}

- (bool)wantsCaptureMouse {
    if (!_ImGuiInitialized) { return false; }
    ImGuiIO& io = ImGui::GetIO();
    return io.WantCaptureMouse || _GizmoCaptureMouse;
}

- (bool)wantsCaptureKeyboard {
    if (!_ImGuiInitialized) { return false; }
    ImGuiIO& io = ImGui::GetIO();
    return io.WantCaptureKeyboard || _GizmoCaptureKeyboard;
}

- (bool)viewportIsHovered {
    return _ViewportHovered;
}

- (bool)viewportIsFocused {
    return _ViewportFocused;
}

- (bool)viewportIsUIHovered {
    return _ViewportUIHovered;
}

- (CGSize)viewportContentSize {
    return _ViewportContentSize;
}

- (CGPoint)viewportContentOrigin {
    return _ViewportContentOrigin;
}

- (CGPoint)viewportImageOrigin {
    return _ViewportImageOrigin;
}

- (CGSize)viewportImageSize {
    return _ViewportImageSize;
}

- (CGPoint)mousePosition {
    if (!_ImGuiInitialized) { return CGPointZero; }
    ImVec2 mousePos = ImGui::GetMousePos();
    return CGPointMake(mousePos.x, mousePos.y);
}

- (void)setSelectedEntityId:(NSString *)value {
    const char *utf8 = value != nil ? value.UTF8String : "";
    if (!utf8) { utf8 = ""; }
    if (strncmp(_SelectedEntityId, utf8, sizeof(_SelectedEntityId)) == 0) {
        return;
    }
    strncpy(_SelectedEntityId, utf8, sizeof(_SelectedEntityId) - 1);
    _SelectedEntityId[sizeof(_SelectedEntityId) - 1] = 0;
    MCEEditorSetLastSelectedEntityId(_context, _SelectedEntityId);
}

- (void)setGizmoCaptureMouse:(bool)wantsMouse keyboard:(bool)wantsKeyboard {
    _GizmoCaptureMouse = wantsMouse;
    _GizmoCaptureKeyboard = wantsKeyboard;
}

@end
