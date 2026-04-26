#pragma once

#include "../Panels/PanelState.h"

void DrawAnimationGraphPanel(void *context,
                             MCEPanelState::AnimationGraphPanelState &panelState,
                             const char *selectedEntityId,
                             bool *isOpen);

