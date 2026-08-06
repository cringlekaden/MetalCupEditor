#include "AnimationGraphModels.h"

extern "C" uint32_t MCESceneIsPlaying(void *context);
extern "C" uint32_t MCEEditorGetAnimatorMode(void *context, const char *entityId, int32_t *modeOut, char *graphHandle, int32_t graphHandleSize);
extern "C" uint32_t MCEEditorSetAnimatorGraphDebugTraceEnabled(void *context, const char *entityId, uint32_t enabled);
extern "C" int32_t MCEEditorGetAnimatorGraphParameterCount(void *context, const char *entityId);
extern "C" uint32_t MCEEditorGetAnimatorGraphParameterAt(void *context, const char *entityId, int32_t index,
                                                           char *nameBuffer, int32_t nameBufferSize,
                                                           int32_t *typeOut,
                                                           float *defaultFloatOut,
                                                           uint32_t *defaultBoolOut,
                                                           int32_t *defaultIntOut,
                                                           float *floatValueOut,
                                                           uint32_t *boolValueOut,
                                                           int32_t *intValueOut,
                                                           uint32_t *triggerValueOut);
extern "C" int32_t MCEEditorGetAnimatorGraphLocalVariableCount(void *context, const char *entityId);
extern "C" uint32_t MCEEditorGetAnimatorGraphLocalVariableAt(void *context, const char *entityId, int32_t index,
                                                               char *nameBuffer, int32_t nameBufferSize,
                                                               int32_t *typeOut,
                                                               float *defaultFloatOut,
                                                               uint32_t *defaultBoolOut,
                                                               int32_t *defaultIntOut,
                                                               float *floatValueOut,
                                                               uint32_t *boolValueOut,
                                                               int32_t *intValueOut);
extern "C" uint32_t MCEEditorGetAnimatorGraphStateMachineRuntime(void *context, const char *entityId, const char *stateMachineNodeId,
                                                                   char *currentStateBuffer, int32_t currentStateBufferSize,
                                                                   char *nextStateBuffer, int32_t nextStateBufferSize,
                                                                   float *transitionElapsedOut,
                                                                   float *transitionDurationOut);
extern "C" int32_t MCEEditorGetAnimatorGraphDebugTraceCount(void *context, const char *entityId);
extern "C" uint32_t MCEEditorGetAnimatorGraphDebugTraceEntryAt(void *context, const char *entityId, int32_t index,
                                                                 char *nodeIDBuffer, int32_t nodeIDBufferSize,
                                                                 char *nodeTypeBuffer, int32_t nodeTypeBufferSize,
                                                                 char *nodeTitleBuffer, int32_t nodeTitleBufferSize,
                                                                 char *outputSummaryBuffer, int32_t outputSummaryBufferSize);

bool LoadAnimationGraphRuntimeDebugSnapshot(void *context,
                                            const char *selectedEntityId,
                                            const AnimationGraphSnapshot &graphSnapshot,
                                            const std::string &graphHandle,
                                            bool captureTrace,
                                            AnimationGraphRuntimeDebugSnapshot &snapshot) {
    snapshot = AnimationGraphRuntimeDebugSnapshot();
    snapshot.isPlaying = MCESceneIsPlaying(context) != 0;
    if (!snapshot.isPlaying) {
        return false;
    }
    if (!selectedEntityId || selectedEntityId[0] == 0 || graphHandle.empty()) {
        return false;
    }

    int32_t animatorMode = 0;
    char animatorGraphHandle[64] = {0};
    if (MCEEditorGetAnimatorMode(context,
                                 selectedEntityId,
                                 &animatorMode,
                                 animatorGraphHandle,
                                 sizeof(animatorGraphHandle)) == 0) {
        return false;
    }
    if (animatorMode != 1 || graphHandle != animatorGraphHandle) {
        return false;
    }

    MCEEditorSetAnimatorGraphDebugTraceEnabled(context,
                                               selectedEntityId,
                                               captureTrace ? 1u : 0u);

    const int32_t parameterCount = MCEEditorGetAnimatorGraphParameterCount(context, selectedEntityId);
    if (parameterCount > 0) {
        snapshot.parameters.reserve(static_cast<size_t>(parameterCount));
        for (int32_t i = 0; i < parameterCount; ++i) {
            AnimationGraphRuntimeParameterValueRecord record;
            char name[128] = {0};
            float defaultFloat = 0.0f;
            uint32_t defaultBool = 0;
            int32_t defaultInt = 0;
            uint32_t boolValue = 0;
            uint32_t triggerValue = 0;
            if (MCEEditorGetAnimatorGraphParameterAt(context,
                                                     selectedEntityId,
                                                     i,
                                                     name,
                                                     sizeof(name),
                                                     &record.type,
                                                     &defaultFloat,
                                                     &defaultBool,
                                                     &defaultInt,
                                                     &record.floatValue,
                                                     &boolValue,
                                                     &record.intValue,
                                                     &triggerValue) == 0) {
                continue;
            }
            record.name = name;
            record.boolValue = (boolValue != 0);
            record.triggerValue = (triggerValue != 0);
            snapshot.parameters.push_back(record);
        }
    }

    const int32_t localVariableCount = MCEEditorGetAnimatorGraphLocalVariableCount(context, selectedEntityId);
    if (localVariableCount > 0) {
        snapshot.localVariables.reserve(static_cast<size_t>(localVariableCount));
        for (int32_t i = 0; i < localVariableCount; ++i) {
            AnimationGraphRuntimeLocalVariableValueRecord record;
            char name[128] = {0};
            float defaultFloat = 0.0f;
            uint32_t defaultBool = 0;
            int32_t defaultInt = 0;
            uint32_t boolValue = 0;
            if (MCEEditorGetAnimatorGraphLocalVariableAt(context,
                                                         selectedEntityId,
                                                         i,
                                                         name,
                                                         sizeof(name),
                                                         &record.type,
                                                         &defaultFloat,
                                                         &defaultBool,
                                                         &defaultInt,
                                                         &record.floatValue,
                                                         &boolValue,
                                                         &record.intValue) == 0) {
                continue;
            }
            record.name = name;
            record.boolValue = (boolValue != 0);
            snapshot.localVariables.push_back(record);
        }
    }

    for (const auto &node : graphSnapshot.nodes) {
        if (node.type != 4) { continue; }
        char currentStateID[64] = {0};
        char nextStateID[64] = {0};
        AnimationGraphStateMachineRuntimeRecord runtimeRecord;
        if (MCEEditorGetAnimatorGraphStateMachineRuntime(context,
                                                         selectedEntityId,
                                                         node.id.c_str(),
                                                         currentStateID,
                                                         sizeof(currentStateID),
                                                         nextStateID,
                                                         sizeof(nextStateID),
                                                         &runtimeRecord.transitionElapsed,
                                                         &runtimeRecord.transitionDuration) == 0) {
            continue;
        }
        runtimeRecord.currentStateID = currentStateID;
        runtimeRecord.nextStateID = nextStateID;
        snapshot.stateMachineRuntimeByNodeID[node.id] = runtimeRecord;
    }

    if (captureTrace) {
        const int32_t traceCount = MCEEditorGetAnimatorGraphDebugTraceCount(context, selectedEntityId);
        if (traceCount > 0) {
            snapshot.traceEntries.reserve(static_cast<size_t>(traceCount));
            for (int32_t i = 0; i < traceCount; ++i) {
                AnimationGraphRuntimeTraceRecord entry;
                char nodeID[64] = {0};
                char nodeType[64] = {0};
                char nodeTitle[128] = {0};
                char outputSummary[192] = {0};
                if (MCEEditorGetAnimatorGraphDebugTraceEntryAt(context,
                                                               selectedEntityId,
                                                               i,
                                                               nodeID,
                                                               sizeof(nodeID),
                                                               nodeType,
                                                               sizeof(nodeType),
                                                               nodeTitle,
                                                               sizeof(nodeTitle),
                                                               outputSummary,
                                                               sizeof(outputSummary)) == 0) {
                    continue;
                }
                entry.nodeID = nodeID;
                entry.nodeType = nodeType;
                entry.nodeTitle = nodeTitle;
                entry.outputSummary = outputSummary;
                snapshot.traceEntries.push_back(entry);
            }
        }
    }

    snapshot.available = true;
    return true;
}
