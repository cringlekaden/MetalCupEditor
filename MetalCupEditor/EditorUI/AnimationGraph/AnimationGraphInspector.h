#pragma once

#include "AnimationGraphModels.h"
#include "../Panels/PanelState.h"

void DrawAnimationGraphInspector(void *context,
                                 AnimationGraphSnapshot &snapshot,
                                 MCEPanelState::AnimationGraphPanelState &panelState,
                                 bool hasRuntimeDebugSnapshot,
                                 const AnimationGraphRuntimeDebugSnapshot &runtimeDebugSnapshot);
