#pragma once

#include "../../ImGui/imgui.h"
#include <cstdint>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

struct AnimationGraphParameterRecord {
    std::string name;
    int32_t type = 0;
    float defaultFloat = 0.0f;
    bool defaultBool = false;
    int32_t defaultInt = 0;
    bool isArray = false;
};

struct AnimationGraphLocalVariableRecord {
    std::string name;
    int32_t type = 0;
    float defaultFloat = 0.0f;
    bool defaultBool = false;
    int32_t defaultInt = 0;
    bool isArray = false;
};

struct AnimationGraphNodeRecord {
    struct Blend1DSampleRecord {
        std::string clipHandle;
        float threshold = 0.0f;
    };

    struct Blend2DSampleRecord {
        std::string clipHandle;
        ImVec2 position = ImVec2(0.0f, 0.0f);
    };

    struct StateMachineStateRecord {
        std::string id;
        std::string name;
        std::string clipHandle;
        std::string nodeRefId;
        bool isOneShot = false;
        bool usesRootMotion = false;
    };

    struct StateMachineConditionRecord {
        std::string parameterName;
        std::string op;
        float floatValue = 0.0f;
        int32_t intValue = 0;
        bool boolValue = false;
        bool hasFloat = false;
        bool hasInt = false;
        bool hasBool = false;
    };

    struct StateMachineTransitionRecord {
        struct TransitionGraphNodeRecord {
            std::string id;
            std::string type;
            std::string title;
            ImVec2 position = ImVec2(0.0f, 0.0f);
            std::string parameterName;
            bool hasFloatValue = false;
            float floatValue = 0.0f;
            bool hasBoolValue = false;
            bool boolValue = false;
            bool hasSynchronizeValue = false;
            bool synchronizeValue = false;
        };

        struct TransitionGraphLinkRecord {
            std::string id;
            std::string fromNodeId;
            int32_t fromSlot = 0;
            std::string toNodeId;
            int32_t toSlot = 0;
        };

        std::string id;
        std::string fromStateId;
        std::string toStateId;
        float duration = 0.15f;
        bool hasMinimumNormalizedTime = false;
        float minimumNormalizedTime = 0.0f;
        std::vector<StateMachineConditionRecord> conditions;
        bool hasInlineTransitionGraph = false;
        std::string transitionGraphOutputNodeId;
        std::vector<TransitionGraphNodeRecord> transitionGraphNodes;
        std::vector<TransitionGraphLinkRecord> transitionGraphLinks;
    };

    std::string id;
    int32_t type = 0;
    std::string title;
    ImVec2 position = ImVec2(0.0f, 0.0f);
    std::string clipHandle;
    std::string blend1DParameterName;
    std::vector<Blend1DSampleRecord> blend1DSamples;
    std::string blend2DParameterXName;
    std::string blend2DParameterYName;
    std::vector<Blend2DSampleRecord> blend2DSamples;
    std::string stateMachineDefaultStateId;
    std::vector<StateMachineStateRecord> stateMachineStates;
    std::vector<StateMachineTransitionRecord> stateMachineTransitions;
    bool isOutput = false;
};

struct AnimationGraphLinkRecord {
    std::string id;
    std::string fromNodeId;
    int32_t fromSlot = 0;
    std::string toNodeId;
    int32_t toSlot = 0;
};

struct AnimationGraphSnapshot {
    std::string name;
    std::string outputNodeId;
    std::vector<AnimationGraphParameterRecord> parameters;
    std::vector<AnimationGraphLocalVariableRecord> localVariables;
    std::vector<AnimationGraphNodeRecord> nodes;
    std::vector<AnimationGraphLinkRecord> links;
};

struct AnimationGraphNodeCanvasScope {
    bool enabled = false;
    std::unordered_set<std::string> visibleNodeIds;
};

struct AnimationGraphRuntimeParameterValueRecord {
    std::string name;
    int32_t type = 0;
    float floatValue = 0.0f;
    bool boolValue = false;
    int32_t intValue = 0;
    bool triggerValue = false;
};

struct AnimationGraphRuntimeLocalVariableValueRecord {
    std::string name;
    int32_t type = 0;
    float floatValue = 0.0f;
    bool boolValue = false;
    int32_t intValue = 0;
};

struct AnimationGraphRuntimeTraceRecord {
    std::string nodeID;
    std::string nodeType;
    std::string nodeTitle;
    std::string outputSummary;
};

struct AnimationGraphStateMachineRuntimeRecord {
    std::string currentStateID;
    std::string nextStateID;
    float transitionElapsed = 0.0f;
    float transitionDuration = 0.0f;
};

struct AnimationGraphRuntimeDebugSnapshot {
    bool isPlaying = false;
    bool available = false;
    std::vector<AnimationGraphRuntimeParameterValueRecord> parameters;
    std::vector<AnimationGraphRuntimeLocalVariableValueRecord> localVariables;
    std::vector<AnimationGraphRuntimeTraceRecord> traceEntries;
    std::unordered_map<std::string, AnimationGraphStateMachineRuntimeRecord> stateMachineRuntimeByNodeID;
};

bool LoadAnimationGraphSnapshot(void *context, const std::string &handle, AnimationGraphSnapshot &snapshot);

bool LoadAnimationGraphRuntimeDebugSnapshot(void *context,
                                            const char *selectedEntityId,
                                            const AnimationGraphSnapshot &graphSnapshot,
                                            const std::string &graphHandle,
                                            bool captureTrace,
                                            AnimationGraphRuntimeDebugSnapshot &snapshot);
