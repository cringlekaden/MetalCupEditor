#pragma once

#include "AnimationGraphModels.h"
#include "../Panels/PanelState.h"

void DrawAnimationGraphDebugView(const AnimationGraphSnapshot &snapshot,
                                 const AnimationGraphRuntimeDebugSnapshot &runtimeDebug,
                                 MCEPanelState::AnimationGraphPanelState &panelState);

