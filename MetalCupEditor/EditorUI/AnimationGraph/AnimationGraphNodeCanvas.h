#pragma once

#include "AnimationGraphModels.h"
#include "../Panels/PanelState.h"
#include <unordered_set>

void DrawAnimationGraphNodeCanvas(void *context,
                                  AnimationGraphSnapshot &snapshot,
                                  std::unordered_set<std::string> &selectedNodeIds,
                                  MCEPanelState::AnimationGraphPanelState &panelState,
                                  const AnimationGraphNodeCanvasScope *scope = nullptr);

void DrawAnimationGraphNodeCreatePopup(void *context,
                                       AnimationGraphSnapshot &snapshot,
                                       std::unordered_set<std::string> &selectedNodeIds,
                                       MCEPanelState::AnimationGraphPanelState &panelState,
                                       const AnimationGraphNodeCanvasScope *scope = nullptr);
