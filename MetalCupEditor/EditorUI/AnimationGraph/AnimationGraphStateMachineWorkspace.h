#pragma once

#include "AnimationGraphModels.h"
#include "AnimationGraphWorkspaceRouter.h"
#include "../Panels/PanelState.h"

using AnimationGraphTransitionCanvasRenderer =
    bool (*)(const AnimationGraphNodeRecord::StateMachineTransitionRecord &transitionRecord, const char *canvasId);

void DrawAnimationGraphStateMachineWorkspace(void *context,
                                             const AnimationGraphSnapshot &snapshot,
                                             const AnimationGraphWorkspaceDescriptor &workspace,
                                             MCEPanelState::AnimationGraphPanelState &panelState,
                                             const AnimationGraphRuntimeDebugSnapshot *runtimeDebug,
                                             AnimationGraphTransitionCanvasRenderer transitionCanvasRenderer);

