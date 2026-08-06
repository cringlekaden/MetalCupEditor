#include "AnimationGraphModels.h"
#include "AnimationGraphSchema.h"

#include <algorithm>
#include <unordered_set>

extern "C" uint32_t MCEEditorGetAnimationGraphInfo(void *context, const char *handle,
                                                     char *nameBuffer, int32_t nameBufferSize,
                                                     char *outputNodeIdBuffer, int32_t outputNodeIdBufferSize,
                                                     int32_t *parameterCountOut,
                                                     int32_t *nodeCountOut,
                                                     int32_t *linkCountOut);
extern "C" int32_t MCEEditorGetAnimationGraphLocalVariableCount(void *context, const char *handle);
extern "C" uint32_t MCEEditorGetAnimationGraphParameterAt(void *context, const char *handle, int32_t index,
                                                            char *nameBuffer, int32_t nameBufferSize,
                                                            int32_t *typeOut,
                                                            float *defaultFloatOut,
                                                            uint32_t *defaultBoolOut,
                                                            int32_t *defaultIntOut);
extern "C" uint32_t MCEEditorGetAnimationGraphLocalVariableAt(void *context, const char *handle, int32_t index,
                                                                char *nameBuffer, int32_t nameBufferSize,
                                                                int32_t *typeOut,
                                                                float *defaultFloatOut,
                                                                uint32_t *defaultBoolOut,
                                                                int32_t *defaultIntOut);
extern "C" uint32_t MCEEditorGetAnimationGraphNodeAt(void *context, const char *handle, int32_t index,
                                                       char *nodeIdBuffer, int32_t nodeIdBufferSize,
                                                       int32_t *typeOut,
                                                       char *titleBuffer, int32_t titleBufferSize,
                                                       float *posXOut, float *posYOut,
                                                       char *clipHandleBuffer, int32_t clipHandleBufferSize,
                                                       uint32_t *isOutputOut);
extern "C" uint32_t MCEEditorGetAnimationGraphLinkAt(void *context, const char *handle, int32_t index,
                                                       char *linkIdBuffer, int32_t linkIdBufferSize,
                                                       char *fromNodeIdBuffer, int32_t fromNodeIdBufferSize,
                                                       int32_t *fromSlotOut,
                                                       char *toNodeIdBuffer, int32_t toNodeIdBufferSize,
                                                       int32_t *toSlotOut);
extern "C" uint32_t MCEEditorGetAnimationGraphBlend1DNode(void *context, const char *handle, const char *nodeId,
                                                            char *parameterNameBuffer, int32_t parameterNameBufferSize,
                                                            int32_t *sampleCountOut);
extern "C" uint32_t MCEEditorGetAnimationGraphBlend1DSampleAt(void *context, const char *handle, const char *nodeId, int32_t index,
                                                                char *clipHandleBuffer, int32_t clipHandleBufferSize,
                                                                float *thresholdOut);
extern "C" uint32_t MCEEditorGetAnimationGraphBlend2DNode(void *context, const char *handle, const char *nodeId,
                                                            char *parameterXNameBuffer, int32_t parameterXNameBufferSize,
                                                            char *parameterYNameBuffer, int32_t parameterYNameBufferSize,
                                                            int32_t *sampleCountOut);
extern "C" uint32_t MCEEditorGetAnimationGraphBlend2DSampleAt(void *context, const char *handle, const char *nodeId, int32_t index,
                                                                char *clipHandleBuffer, int32_t clipHandleBufferSize,
                                                                float *xOut, float *yOut);
extern "C" uint32_t MCEEditorGetAnimationGraphStateMachineNode(void *context, const char *handle, const char *nodeId,
                                                                 char *defaultStateIdBuffer, int32_t defaultStateIdBufferSize,
                                                                 int32_t *stateCountOut,
                                                                 int32_t *transitionCountOut);
extern "C" uint32_t MCEEditorGetAnimationGraphStateMachineStateAt(void *context, const char *handle, const char *nodeId, int32_t index,
                                                                    char *stateIdBuffer, int32_t stateIdBufferSize,
                                                                    char *nameBuffer, int32_t nameBufferSize,
                                                                    char *clipHandleBuffer, int32_t clipHandleBufferSize,
                                                                    char *nodeRefIdBuffer, int32_t nodeRefIdBufferSize,
                                                                    uint32_t *isOneShotOut,
                                                                    uint32_t *usesRootMotionOut);
extern "C" uint32_t MCEEditorGetAnimationGraphStateMachineTransitionAt(void *context, const char *handle, const char *nodeId, int32_t index,
                                                                         char *transitionIdBuffer, int32_t transitionIdBufferSize,
                                                                         char *fromStateIdBuffer, int32_t fromStateIdBufferSize,
                                                                         char *toStateIdBuffer, int32_t toStateIdBufferSize,
                                                                         float *durationOut,
                                                                         uint32_t *hasMinimumNormalizedTimeOut,
                                                                         float *minimumNormalizedTimeOut,
                                                                         int32_t *conditionCountOut);
extern "C" uint32_t MCEEditorGetAnimationGraphStateMachineConditionAt(void *context, const char *handle, const char *nodeId, const char *transitionId, int32_t index,
                                                                        char *parameterNameBuffer, int32_t parameterNameBufferSize,
                                                                        char *opBuffer, int32_t opBufferSize,
                                                                        float *floatValueOut, int32_t *intValueOut, uint32_t *boolValueOut,
                                                                        uint32_t *hasFloatOut, uint32_t *hasIntOut, uint32_t *hasBoolOut);
extern "C" uint32_t MCEEditorGetAnimationGraphStateMachineTransitionGraphInfo(void *context, const char *handle, const char *nodeId, const char *transitionId,
                                                                                uint32_t *hasInlineGraphOut, int32_t *nodeCountOut, int32_t *linkCountOut,
                                                                                char *outputNodeIdBuffer, int32_t outputNodeIdBufferSize);
extern "C" uint32_t MCEEditorGetAnimationGraphStateMachineTransitionGraphNodeAt(void *context, const char *handle, const char *nodeId, const char *transitionId, int32_t index,
                                                                                  char *nodeIdBuffer, int32_t nodeIdBufferSize,
                                                                                  char *typeBuffer, int32_t typeBufferSize,
                                                                                  char *titleBuffer, int32_t titleBufferSize,
                                                                                  float *posXOut, float *posYOut,
                                                                                  char *parameterNameBuffer, int32_t parameterNameBufferSize,
                                                                                  float *floatValueOut, uint32_t *hasFloatValueOut,
                                                                                  uint32_t *boolValueOut, uint32_t *hasBoolValueOut,
                                                                                  uint32_t *synchronizeValueOut, uint32_t *hasSynchronizeValueOut);
extern "C" uint32_t MCEEditorGetAnimationGraphStateMachineTransitionGraphLinkAt(void *context, const char *handle, const char *nodeId, const char *transitionId, int32_t index,
                                                                                  char *linkIdBuffer, int32_t linkIdBufferSize,
                                                                                  char *fromNodeIdBuffer, int32_t fromNodeIdBufferSize, int32_t *fromSlotOut,
                                                                                  char *toNodeIdBuffer, int32_t toNodeIdBufferSize, int32_t *toSlotOut);

bool LoadAnimationGraphSnapshot(void *context, const std::string &handle, AnimationGraphSnapshot &snapshot) {
    snapshot = AnimationGraphSnapshot();
    if (handle.empty()) { return false; }

    char nameBuffer[128] = {0};
    char outputNodeBuffer[64] = {0};
    int32_t parameterCount = 0;
    int32_t nodeCount = 0;
    int32_t linkCount = 0;
    if (MCEEditorGetAnimationGraphInfo(context, handle.c_str(),
                                       nameBuffer, sizeof(nameBuffer),
                                       outputNodeBuffer, sizeof(outputNodeBuffer),
                                       &parameterCount, &nodeCount, &linkCount) == 0) {
        return false;
    }
    snapshot.name = nameBuffer;
    snapshot.outputNodeId = outputNodeBuffer;

    snapshot.parameters.reserve(static_cast<size_t>(std::max(0, parameterCount)));
    for (int32_t i = 0; i < parameterCount; ++i) {
        AnimationGraphParameterRecord parameter;
        char paramName[128] = {0};
        uint32_t defaultBool = 0;
        if (MCEEditorGetAnimationGraphParameterAt(context, handle.c_str(), i,
                                                  paramName, sizeof(paramName),
                                                  &parameter.type,
                                                  &parameter.defaultFloat,
                                                  &defaultBool,
                                                  &parameter.defaultInt) == 0) {
            continue;
        }
        parameter.name = paramName;
        parameter.defaultBool = defaultBool != 0;
        snapshot.parameters.push_back(parameter);
    }

    const int32_t localVariableCount = MCEEditorGetAnimationGraphLocalVariableCount(context, handle.c_str());
    snapshot.localVariables.reserve(static_cast<size_t>(std::max(0, localVariableCount)));
    for (int32_t i = 0; i < localVariableCount; ++i) {
        AnimationGraphLocalVariableRecord localVariable;
        char localName[128] = {0};
        uint32_t defaultBool = 0;
        if (MCEEditorGetAnimationGraphLocalVariableAt(context, handle.c_str(), i,
                                                      localName, sizeof(localName),
                                                      &localVariable.type,
                                                      &localVariable.defaultFloat,
                                                      &defaultBool,
                                                      &localVariable.defaultInt) == 0) {
            continue;
        }
        localVariable.name = localName;
        localVariable.defaultBool = (defaultBool != 0);
        snapshot.localVariables.push_back(localVariable);
    }

    snapshot.nodes.reserve(static_cast<size_t>(std::max(0, nodeCount)));
    for (int32_t i = 0; i < nodeCount; ++i) {
        AnimationGraphNodeRecord node;
        char nodeId[64] = {0};
        char title[128] = {0};
        char clipHandle[64] = {0};
        uint32_t isOutput = 0;
        if (MCEEditorGetAnimationGraphNodeAt(context, handle.c_str(), i,
                                             nodeId, sizeof(nodeId),
                                             &node.type,
                                             title, sizeof(title),
                                             &node.position.x, &node.position.y,
                                             clipHandle, sizeof(clipHandle),
                                             &isOutput) == 0) {
            continue;
        }
        node.id = nodeId;
        node.title = title;
        node.clipHandle = clipHandle;
        node.isOutput = (isOutput != 0);

        if (node.type == 2) {
            char parameterName[128] = {0};
            int32_t sampleCount = 0;
            if (MCEEditorGetAnimationGraphBlend1DNode(context,
                                                      handle.c_str(),
                                                      node.id.c_str(),
                                                      parameterName,
                                                      sizeof(parameterName),
                                                      &sampleCount) != 0) {
                node.blend1DParameterName = parameterName;
                node.blend1DSamples.reserve(static_cast<size_t>(std::max(0, sampleCount)));
                for (int32_t sampleIndex = 0; sampleIndex < sampleCount; ++sampleIndex) {
                    AnimationGraphNodeRecord::Blend1DSampleRecord sample;
                    char clipSampleHandle[64] = {0};
                    if (MCEEditorGetAnimationGraphBlend1DSampleAt(context,
                                                                  handle.c_str(),
                                                                  node.id.c_str(),
                                                                  sampleIndex,
                                                                  clipSampleHandle,
                                                                  sizeof(clipSampleHandle),
                                                                  &sample.threshold) == 0) {
                        continue;
                    }
                    sample.clipHandle = clipSampleHandle;
                    node.blend1DSamples.push_back(sample);
                }
            }
        } else if (node.type == 3) {
            char parameterXName[128] = {0};
            char parameterYName[128] = {0};
            int32_t sampleCount = 0;
            if (MCEEditorGetAnimationGraphBlend2DNode(context,
                                                      handle.c_str(),
                                                      node.id.c_str(),
                                                      parameterXName,
                                                      sizeof(parameterXName),
                                                      parameterYName,
                                                      sizeof(parameterYName),
                                                      &sampleCount) != 0) {
                node.blend2DParameterXName = parameterXName;
                node.blend2DParameterYName = parameterYName;
                node.blend2DSamples.reserve(static_cast<size_t>(std::max(0, sampleCount)));
                for (int32_t sampleIndex = 0; sampleIndex < sampleCount; ++sampleIndex) {
                    AnimationGraphNodeRecord::Blend2DSampleRecord sample;
                    char clipSampleHandle[64] = {0};
                    if (MCEEditorGetAnimationGraphBlend2DSampleAt(context,
                                                                  handle.c_str(),
                                                                  node.id.c_str(),
                                                                  sampleIndex,
                                                                  clipSampleHandle,
                                                                  sizeof(clipSampleHandle),
                                                                  &sample.position.x,
                                                                  &sample.position.y) == 0) {
                        continue;
                    }
                    sample.clipHandle = clipSampleHandle;
                    node.blend2DSamples.push_back(sample);
                }
            }
        } else if (node.type == 4) {
            char defaultStateId[64] = {0};
            int32_t stateCount = 0;
            int32_t transitionCount = 0;
            if (MCEEditorGetAnimationGraphStateMachineNode(context,
                                                           handle.c_str(),
                                                           node.id.c_str(),
                                                           defaultStateId,
                                                           sizeof(defaultStateId),
                                                           &stateCount,
                                                           &transitionCount) != 0) {
                node.stateMachineDefaultStateId = defaultStateId;
                node.stateMachineStates.reserve(static_cast<size_t>(std::max(0, stateCount)));
                for (int32_t stateIndex = 0; stateIndex < stateCount; ++stateIndex) {
                    AnimationGraphNodeRecord::StateMachineStateRecord stateRecord;
                    char stateId[64] = {0};
                    char stateName[128] = {0};
                    char stateClipHandle[64] = {0};
                    char stateNodeRefId[64] = {0};
                    uint32_t isOneShot = 0;
                    uint32_t usesRootMotion = 0;
                    if (MCEEditorGetAnimationGraphStateMachineStateAt(context,
                                                                      handle.c_str(),
                                                                      node.id.c_str(),
                                                                      stateIndex,
                                                                      stateId,
                                                                      sizeof(stateId),
                                                                      stateName,
                                                                      sizeof(stateName),
                                                                      stateClipHandle,
                                                                      sizeof(stateClipHandle),
                                                                      stateNodeRefId,
                                                                      sizeof(stateNodeRefId),
                                                                      &isOneShot,
                                                                      &usesRootMotion) == 0) {
                        continue;
                    }
                    stateRecord.id = stateId;
                    stateRecord.name = stateName;
                    stateRecord.clipHandle = stateClipHandle;
                    stateRecord.nodeRefId = stateNodeRefId;
                    stateRecord.isOneShot = (isOneShot != 0);
                    stateRecord.usesRootMotion = (usesRootMotion != 0);
                    node.stateMachineStates.push_back(stateRecord);
                }

                node.stateMachineTransitions.reserve(static_cast<size_t>(std::max(0, transitionCount)));
                for (int32_t transitionIndex = 0; transitionIndex < transitionCount; ++transitionIndex) {
                    AnimationGraphNodeRecord::StateMachineTransitionRecord transitionRecord;
                    char transitionId[64] = {0};
                    char fromStateId[64] = {0};
                    char toStateId[64] = {0};
                    uint32_t hasMinimumNormalizedTime = 0;
                    int32_t conditionCount = 0;
                    if (MCEEditorGetAnimationGraphStateMachineTransitionAt(context,
                                                                           handle.c_str(),
                                                                           node.id.c_str(),
                                                                           transitionIndex,
                                                                           transitionId,
                                                                           sizeof(transitionId),
                                                                           fromStateId,
                                                                           sizeof(fromStateId),
                                                                           toStateId,
                                                                           sizeof(toStateId),
                                                                           &transitionRecord.duration,
                                                                           &hasMinimumNormalizedTime,
                                                                           &transitionRecord.minimumNormalizedTime,
                                                                           &conditionCount) == 0) {
                        continue;
                    }
                    transitionRecord.id = transitionId;
                    transitionRecord.fromStateId = fromStateId;
                    transitionRecord.toStateId = toStateId;
                    transitionRecord.hasMinimumNormalizedTime = (hasMinimumNormalizedTime != 0);
                    transitionRecord.conditions.reserve(static_cast<size_t>(std::max(0, conditionCount)));
                    for (int32_t conditionIndex = 0; conditionIndex < conditionCount; ++conditionIndex) {
                        AnimationGraphNodeRecord::StateMachineConditionRecord conditionRecord;
                        char parameterName[128] = {0};
                        char op[32] = {0};
                        uint32_t boolValue = 0;
                        uint32_t hasFloat = 0;
                        uint32_t hasInt = 0;
                        uint32_t hasBool = 0;
                        if (MCEEditorGetAnimationGraphStateMachineConditionAt(context,
                                                                              handle.c_str(),
                                                                              node.id.c_str(),
                                                                              transitionRecord.id.c_str(),
                                                                              conditionIndex,
                                                                              parameterName,
                                                                              sizeof(parameterName),
                                                                              op,
                                                                              sizeof(op),
                                                                              &conditionRecord.floatValue,
                                                                              &conditionRecord.intValue,
                                                                              &boolValue,
                                                                              &hasFloat,
                                                                              &hasInt,
                                                                              &hasBool) == 0) {
                            continue;
                        }
                        conditionRecord.parameterName = parameterName;
                        conditionRecord.op = op;
                        conditionRecord.boolValue = (boolValue != 0);
                        conditionRecord.hasFloat = (hasFloat != 0);
                        conditionRecord.hasInt = (hasInt != 0);
                        conditionRecord.hasBool = (hasBool != 0);
                        transitionRecord.conditions.push_back(conditionRecord);
                    }

                    uint32_t hasInlineTransitionGraph = 0;
                    int32_t transitionGraphNodeCount = 0;
                    int32_t transitionGraphLinkCount = 0;
                    char transitionGraphOutputNodeId[64] = {0};
                    if (MCEEditorGetAnimationGraphStateMachineTransitionGraphInfo(context,
                                                                                  handle.c_str(),
                                                                                  node.id.c_str(),
                                                                                  transitionRecord.id.c_str(),
                                                                                  &hasInlineTransitionGraph,
                                                                                  &transitionGraphNodeCount,
                                                                                  &transitionGraphLinkCount,
                                                                                  transitionGraphOutputNodeId,
                                                                                  sizeof(transitionGraphOutputNodeId)) != 0) {
                        transitionRecord.hasInlineTransitionGraph = (hasInlineTransitionGraph != 0);
                        transitionRecord.transitionGraphOutputNodeId = transitionGraphOutputNodeId;
                        transitionRecord.transitionGraphNodes.reserve(static_cast<size_t>(std::max(0, transitionGraphNodeCount)));
                        for (int32_t transitionNodeIndex = 0; transitionNodeIndex < transitionGraphNodeCount; ++transitionNodeIndex) {
                            AnimationGraphNodeRecord::StateMachineTransitionRecord::TransitionGraphNodeRecord graphNode;
                            char graphNodeId[64] = {0};
                            char graphNodeType[64] = {0};
                            char graphNodeTitle[128] = {0};
                            char graphParameterName[128] = {0};
                            uint32_t hasFloatValue = 0;
                            uint32_t hasBoolValue = 0;
                            uint32_t boolValue = 0;
                            uint32_t hasSynchronizeValue = 0;
                            uint32_t synchronizeValue = 0;
                            if (MCEEditorGetAnimationGraphStateMachineTransitionGraphNodeAt(context,
                                                                                            handle.c_str(),
                                                                                            node.id.c_str(),
                                                                                            transitionRecord.id.c_str(),
                                                                                            transitionNodeIndex,
                                                                                            graphNodeId,
                                                                                            sizeof(graphNodeId),
                                                                                            graphNodeType,
                                                                                            sizeof(graphNodeType),
                                                                                            graphNodeTitle,
                                                                                            sizeof(graphNodeTitle),
                                                                                            &graphNode.position.x,
                                                                                            &graphNode.position.y,
                                                                                            graphParameterName,
                                                                                            sizeof(graphParameterName),
                                                                                            &graphNode.floatValue,
                                                                                            &hasFloatValue,
                                                                                            &boolValue,
                                                                                            &hasBoolValue,
                                                                                            &synchronizeValue,
                                                                                            &hasSynchronizeValue) == 0) {
                                continue;
                            }
                            graphNode.id = graphNodeId;
                            graphNode.type = graphNodeType;
                            graphNode.title = graphNodeTitle;
                            graphNode.parameterName = graphParameterName;
                            graphNode.hasFloatValue = (hasFloatValue != 0);
                            graphNode.hasBoolValue = (hasBoolValue != 0);
                            graphNode.boolValue = (boolValue != 0);
                            graphNode.hasSynchronizeValue = (hasSynchronizeValue != 0);
                            graphNode.synchronizeValue = (synchronizeValue != 0);
                            transitionRecord.transitionGraphNodes.push_back(graphNode);
                        }
                        transitionRecord.transitionGraphLinks.reserve(static_cast<size_t>(std::max(0, transitionGraphLinkCount)));
                        for (int32_t transitionLinkIndex = 0; transitionLinkIndex < transitionGraphLinkCount; ++transitionLinkIndex) {
                            AnimationGraphNodeRecord::StateMachineTransitionRecord::TransitionGraphLinkRecord graphLink;
                            char graphLinkId[64] = {0};
                            char graphFromNodeId[64] = {0};
                            char graphToNodeId[64] = {0};
                            if (MCEEditorGetAnimationGraphStateMachineTransitionGraphLinkAt(context,
                                                                                            handle.c_str(),
                                                                                            node.id.c_str(),
                                                                                            transitionRecord.id.c_str(),
                                                                                            transitionLinkIndex,
                                                                                            graphLinkId,
                                                                                            sizeof(graphLinkId),
                                                                                            graphFromNodeId,
                                                                                            sizeof(graphFromNodeId),
                                                                                            &graphLink.fromSlot,
                                                                                            graphToNodeId,
                                                                                            sizeof(graphToNodeId),
                                                                                            &graphLink.toSlot) == 0) {
                                continue;
                            }
                            graphLink.id = graphLinkId;
                            graphLink.fromNodeId = graphFromNodeId;
                            graphLink.toNodeId = graphToNodeId;
                            transitionRecord.transitionGraphLinks.push_back(graphLink);
                        }
                    }
                    node.stateMachineTransitions.push_back(transitionRecord);
                }
            }
        }
        snapshot.nodes.push_back(node);
    }

    snapshot.links.reserve(static_cast<size_t>(std::max(0, linkCount)));
    std::unordered_set<std::string> nodeIdSet;
    for (const auto &node : snapshot.nodes) {
        nodeIdSet.insert(node.id);
    }
    for (int32_t i = 0; i < linkCount; ++i) {
        AnimationGraphLinkRecord link;
        char linkId[64] = {0};
        char fromNodeId[64] = {0};
        char toNodeId[64] = {0};
        if (MCEEditorGetAnimationGraphLinkAt(context, handle.c_str(), i,
                                             linkId, sizeof(linkId),
                                             fromNodeId, sizeof(fromNodeId),
                                             &link.fromSlot,
                                             toNodeId, sizeof(toNodeId),
                                             &link.toSlot) == 0) {
            continue;
        }
        link.id = linkId;
        link.fromNodeId = fromNodeId;
        link.toNodeId = toNodeId;
        if (nodeIdSet.count(link.fromNodeId) == 0 || nodeIdSet.count(link.toNodeId) == 0) {
            continue;
        }
        const auto fromNodeIt = std::find_if(snapshot.nodes.begin(), snapshot.nodes.end(), [&](const AnimationGraphNodeRecord &node) {
            return node.id == link.fromNodeId;
        });
        const auto toNodeIt = std::find_if(snapshot.nodes.begin(), snapshot.nodes.end(), [&](const AnimationGraphNodeRecord &node) {
            return node.id == link.toNodeId;
        });
        if (fromNodeIt == snapshot.nodes.end() || toNodeIt == snapshot.nodes.end()) {
            continue;
        }
        const AnimationGraphSchema::AnimGraphNodeSchema *fromSchema =
            AnimationGraphSchema::SchemaForRuntimeType(fromNodeIt->type);
        const AnimationGraphSchema::AnimGraphNodeSchema *toSchema =
            AnimationGraphSchema::SchemaForRuntimeType(toNodeIt->type);
        const int32_t fromOutputCount =
            fromSchema ? AnimationGraphSchema::PinCount(*fromSchema, AnimationGraphSchema::PinDirection::Output) : 0;
        const int32_t toInputCount =
            toSchema ? AnimationGraphSchema::PinCount(*toSchema, AnimationGraphSchema::PinDirection::Input) : 0;
        if (link.fromSlot < 0 || link.fromSlot >= fromOutputCount) {
            continue;
        }
        if (link.toSlot < 0 || link.toSlot >= toInputCount) {
            continue;
        }
        snapshot.links.push_back(link);
    }
    return true;
}
