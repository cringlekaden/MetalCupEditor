#pragma once

#include "AnimationGraphModels.h"
#include "AnimationGraphWorkspaceRouter.h"
#include "../Panels/PanelState.h"
#include <functional>

using AnimationGraphTransitionCanvasRenderer =
    std::function<bool(const AnimationGraphNodeRecord::StateMachineTransitionRecord &transitionRecord, const char *canvasId)>;

void DrawAnimationGraphStateMachineWorkspace(void *context,
                                             const AnimationGraphSnapshot &snapshot,
                                             const AnimationGraphWorkspaceDescriptor &workspace,
                                             MCEPanelState::AnimationGraphPanelState &panelState,
                                             const AnimationGraphRuntimeDebugSnapshot *runtimeDebug,
                                             AnimationGraphTransitionCanvasRenderer transitionCanvasRenderer);
