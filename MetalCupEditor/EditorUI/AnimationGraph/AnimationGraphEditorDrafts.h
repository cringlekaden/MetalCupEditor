#pragma once

#include "../../ImGui/imgui.h"
#include <string>
#include <unordered_map>

struct AnimationGraphEditorDrafts {
    std::unordered_map<std::string, std::string> newBlend1DClipDraftByNode;
    std::unordered_map<std::string, float> newBlend1DThresholdDraftByNode;
    std::unordered_map<std::string, std::string> newBlend2DClipDraftByNode;
    std::unordered_map<std::string, ImVec2> newBlend2DPositionDraftByNode;
    std::unordered_map<std::string, std::string> selectedStateByNode;
    std::unordered_map<std::string, std::string> selectedTransitionByNode;
    std::unordered_map<std::string, std::string> newStateNameByNode;
    std::unordered_map<std::string, std::string> newStateClipByNode;
    std::unordered_map<std::string, std::string> newStateNodeRefByNode;
    std::unordered_map<std::string, bool> newStateOneShotByNode;
    std::unordered_map<std::string, bool> newStateUsesRootMotionByNode;
    std::unordered_map<std::string, int32_t> newTransitionFromByNode;
    std::unordered_map<std::string, int32_t> newTransitionToByNode;
    std::unordered_map<std::string, float> newTransitionDurationByNode;
    std::unordered_map<std::string, bool> newTransitionHasMinTimeByNode;
    std::unordered_map<std::string, float> newTransitionMinTimeByNode;
    std::unordered_map<std::string, int32_t> newConditionParameterIndexByTransition;
};

AnimationGraphEditorDrafts &GetAnimationGraphEditorDrafts();

