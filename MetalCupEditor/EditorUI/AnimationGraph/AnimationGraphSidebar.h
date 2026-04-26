#pragma once

#include "AnimationGraphModels.h"
#include "../Panels/PanelState.h"
#include <unordered_set>

void DrawAnimationGraphSidebar(void *context,
                               const char *selectedEntityId,
                               AnimationGraphSnapshot &snapshot,
                               std::unordered_set<std::string> &selectedNodeIds,
                               MCEPanelState::AnimationGraphPanelState &panelState,
                               bool hasRuntimeDebugSnapshot,
                               const AnimationGraphRuntimeDebugSnapshot &runtimeDebugSnapshot);

