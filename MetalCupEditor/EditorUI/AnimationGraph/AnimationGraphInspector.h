#pragma once

#include "AnimationGraphModels.h"
#include "../Panels/PanelState.h"

void DrawAnimationGraphInspector(void *context,
                                 AnimationGraphSnapshot &snapshot,
                                 MCEPanelState::AnimationGraphPanelState &panelState,
                                 int32_t &selectedInputIndex,
                                 int32_t &selectedLocalIndex,
                                 bool &focusInputRename,
                                 bool &focusLocalRename,
                                 bool hasRuntimeDebugSnapshot,
                                 const AnimationGraphRuntimeDebugSnapshot &runtimeDebugSnapshot);
