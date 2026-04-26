#pragma once

#include "AnimationGraphSchema.h"

#include <string>

namespace AnimationGraphValidation {

struct PinEndpoint {
    std::string nodeId;
    int32_t slot = 0;
    bool isInput = false;
    bool isSyntheticParameterNode = false;
    const AnimationGraphSchema::AnimGraphNodeSchema *nodeSchema = nullptr;
    const AnimationGraphSchema::AnimGraphPinSchema *pinSchema = nullptr;
};

struct LinkValidationResult {
    bool valid = false;
    bool parameterAssignment = false;
    std::string reason;
};

inline LinkValidationResult ValidateTypedLink(const PinEndpoint &outputEndpoint,
                                              const PinEndpoint &inputEndpoint) {
    LinkValidationResult result;
    if (outputEndpoint.nodeId.empty() || inputEndpoint.nodeId.empty()) {
        result.reason = "Missing pin endpoint.";
        return result;
    }
    if (outputEndpoint.nodeId == inputEndpoint.nodeId) {
        result.reason = "Links between pins on the same node are not allowed.";
        return result;
    }
    if (outputEndpoint.isInput || !inputEndpoint.isInput) {
        result.reason = "Links must connect output pins to input pins.";
        return result;
    }
    if (outputEndpoint.pinSchema == nullptr || inputEndpoint.pinSchema == nullptr) {
        result.reason = "Pin schema is unavailable.";
        return result;
    }
    if (outputEndpoint.pinSchema->type != inputEndpoint.pinSchema->type) {
        result.reason = "Pin types are incompatible.";
        return result;
    }
    result.valid = true;
    return result;
}

inline LinkValidationResult ValidateRootLink(const PinEndpoint &outputEndpoint,
                                             const PinEndpoint &inputEndpoint) {
    LinkValidationResult result;
    if (outputEndpoint.nodeId.empty() || inputEndpoint.nodeId.empty()) {
        result.reason = "Missing pin endpoint.";
        return result;
    }
    if (outputEndpoint.nodeId == inputEndpoint.nodeId) {
        result.reason = "Links between pins on the same node are not allowed.";
        return result;
    }
    if (outputEndpoint.isInput || !inputEndpoint.isInput) {
        result.reason = "Root graph links must connect output pins to input pins.";
        return result;
    }
    if (inputEndpoint.isSyntheticParameterNode) {
        result.reason = "Parameter nodes cannot receive graph links.";
        return result;
    }
    if (outputEndpoint.isSyntheticParameterNode) {
        if (inputEndpoint.nodeSchema == nullptr || inputEndpoint.pinSchema == nullptr) {
            result.reason = "Missing blend node schema.";
            return result;
        }
        const int32_t targetType = inputEndpoint.nodeSchema->runtimeType;
        const bool canAssignBlend1D = targetType == 2 && inputEndpoint.slot == 0 &&
            inputEndpoint.pinSchema->type == AnimationGraphSchema::PinType::Float;
        const bool canAssignBlend2D = targetType == 3 && (inputEndpoint.slot == 0 || inputEndpoint.slot == 1) &&
            inputEndpoint.pinSchema->type == AnimationGraphSchema::PinType::Float;
        if (!canAssignBlend1D && !canAssignBlend2D) {
            result.reason = "Parameter pins only bind Blend1D and Blend2D parameter inputs.";
            return result;
        }
        result.valid = true;
        result.parameterAssignment = true;
        return result;
    }
    if (inputEndpoint.nodeSchema == nullptr || inputEndpoint.nodeSchema->runtimeType != 0 || inputEndpoint.slot != 0) {
        result.reason = "Pose links in the root graph must end at Output Pose.";
        return result;
    }
    return ValidateTypedLink(outputEndpoint, inputEndpoint);
}

inline LinkValidationResult ValidateTransitionLink(const PinEndpoint &outputEndpoint,
                                                   const PinEndpoint &inputEndpoint) {
    return ValidateTypedLink(outputEndpoint, inputEndpoint);
}

inline bool CanCreateRootNodeFromPin(const PinEndpoint &sourceEndpoint,
                                     const AnimationGraphSchema::AnimGraphNodeSchema &candidateSchema) {
    if (sourceEndpoint.nodeId.empty()) {
        return candidateSchema.createMenu.creatable;
    }
    if (sourceEndpoint.isSyntheticParameterNode && !sourceEndpoint.isInput) {
        return candidateSchema.runtimeType == 2 || candidateSchema.runtimeType == 3;
    }
    if (sourceEndpoint.isInput) {
        return AnimationGraphSchema::PinCount(candidateSchema, AnimationGraphSchema::PinDirection::Output) > 0;
    }
    return AnimationGraphSchema::PinCount(candidateSchema, AnimationGraphSchema::PinDirection::Input) > 0;
}

inline bool CanCreateTransitionNodeFromPin(const PinEndpoint &sourceEndpoint,
                                           const AnimationGraphSchema::AnimGraphNodeSchema &candidateSchema) {
    if (sourceEndpoint.nodeId.empty()) {
        return candidateSchema.createMenu.creatable;
    }
    if (sourceEndpoint.pinSchema == nullptr) {
        return false;
    }
    const AnimationGraphSchema::PinDirection direction =
        sourceEndpoint.isInput ? AnimationGraphSchema::PinDirection::Output : AnimationGraphSchema::PinDirection::Input;
    const int32_t pinCount = AnimationGraphSchema::PinCount(candidateSchema, direction);
    for (int32_t slot = 0; slot < pinCount; ++slot) {
        const auto *pin = AnimationGraphSchema::PinAt(candidateSchema, direction, slot);
        if (pin != nullptr && pin->type == sourceEndpoint.pinSchema->type) {
            return true;
        }
    }
    return false;
}

inline int32_t FirstCompatibleSlot(const AnimationGraphSchema::AnimGraphNodeSchema &candidateSchema,
                                   const PinEndpoint &sourceEndpoint) {
    if (sourceEndpoint.pinSchema == nullptr) {
        return -1;
    }
    const AnimationGraphSchema::PinDirection direction =
        sourceEndpoint.isInput ? AnimationGraphSchema::PinDirection::Output : AnimationGraphSchema::PinDirection::Input;
    const int32_t pinCount = AnimationGraphSchema::PinCount(candidateSchema, direction);
    for (int32_t slot = 0; slot < pinCount; ++slot) {
        const auto *pin = AnimationGraphSchema::PinAt(candidateSchema, direction, slot);
        if (pin != nullptr && pin->type == sourceEndpoint.pinSchema->type) {
            return slot;
        }
    }
    return -1;
}

} // namespace AnimationGraphValidation
