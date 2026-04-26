#pragma once

#include "AnimationGraphModels.h"
#include "AnimationGraphWorkspaceRouter.h"
#include "../Panels/PanelState.h"

void DrawAnimationGraphBlendSpaceWorkspace(void *context,
                                           const AnimationGraphSnapshot &snapshot,
                                           const AnimationGraphWorkspaceDescriptor &workspace,
                                           MCEPanelState::AnimationGraphPanelState &panelState,
                                           const AnimationGraphRuntimeDebugSnapshot *runtimeDebug);

