#pragma once

#include "../../ImGui/imgui.h"

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace AnimationGraphSchema {

enum class GraphDomain : int32_t {
    Root = 0,
    Transition = 1
};

enum class PinDirection : int32_t {
    Input = 0,
    Output = 1
};

enum class PinType : int32_t {
    Pose = 0,
    Float = 1,
    Bool = 2,
    Int = 3,
    Trigger = 4
};

enum class InlineFieldKind : int32_t {
    Text = 0,
    Float = 1,
    Bool = 2,
    ClipHandle = 3,
    ParameterName = 4,
    LocalName = 5
};

enum class FieldVisibility : int32_t {
    Always = 0,
    SelectedOnly = 1
};

enum class FieldBinding : int32_t {
    None = 0,
    Title = 1,
    ClipHandle = 2,
    ParameterName = 3,
    ParameterXName = 4,
    ParameterYName = 5,
    FloatValue = 6,
    BoolValue = 7,
    Duration = 8,
    SynchronizeValue = 9
};

enum class SubgraphOwnership : int32_t {
    None = 0,
    BlendSpace = 1,
    StateMachine = 2
};

struct WorkspaceAvailability {
    bool rootGraph = false;
    bool stateSubgraph = false;
    bool transitionGraph = false;
};

struct AnimGraphPinSchema {
    std::string id;
    PinDirection direction = PinDirection::Input;
    PinType type = PinType::Pose;
    std::string label;
    bool required = false;
    bool singleConnection = true;
    bool supportsCreateFromPin = true;
};

struct AnimGraphFieldSchema {
    std::string id;
    InlineFieldKind kind = InlineFieldKind::Text;
    std::string label;
    FieldVisibility visibility = FieldVisibility::Always;
    FieldBinding binding = FieldBinding::None;
};

struct NodeRenderStyle {
    ImVec4 headerTint = ImVec4(110.0f / 255.0f, 110.0f / 255.0f, 110.0f / 255.0f, 1.0f);
    ImVec4 linkTint = ImVec4(0.65f, 0.70f, 0.78f, 0.95f);
    bool emphasizeBorder = false;
};

struct NodeBehaviorFlags {
    bool supportsInlineTitle = false;
    bool canSetAsOutput = false;
    bool supportsWorkspaceEdit = false;
    bool acceptsClipDrop = false;
};

struct DragDropRules {
    bool acceptsAnimationClip = false;
    bool acceptsParameterDefinition = false;
    bool acceptsLocalDefinition = false;
};

struct CreateMenuMetadata {
    bool creatable = false;
    std::string label;
    std::string category;
    int32_t sortOrder = 0;
};

struct AnimGraphNodeSchema {
    std::string typeId;
    int32_t runtimeType = -1;
    std::string title;
    std::string category;
    GraphDomain domain = GraphDomain::Root;
    WorkspaceAvailability availability;
    std::vector<AnimGraphPinSchema> pins;
    std::vector<AnimGraphFieldSchema> inlineFields;
    NodeRenderStyle style;
    NodeBehaviorFlags behavior;
    SubgraphOwnership subgraph = SubgraphOwnership::None;
    DragDropRules dragDrop;
    CreateMenuMetadata createMenu;
};

inline std::string NormalizeTypeId(std::string_view value) {
    std::string normalized;
    normalized.reserve(value.size());
    for (char c : value) {
        if (c == '_' || c == ' ') {
            continue;
        }
        normalized.push_back(static_cast<char>(std::tolower(static_cast<unsigned char>(c))));
    }
    return normalized;
}

inline const char *ParameterTypeLabel(int32_t type) {
    switch (type) {
        case 0: return "Float";
        case 1: return "Bool";
        case 2: return "Int";
        case 3: return "Trigger";
        default: return "Float";
    }
}

inline PinType PinTypeForParameterValueType(int32_t type) {
    switch (type) {
        case 1: return PinType::Bool;
        case 2: return PinType::Int;
        case 3: return PinType::Trigger;
        default: return PinType::Float;
    }
}

inline ImVec4 PinColor(PinType type) {
    switch (type) {
        case PinType::Pose: return ImVec4(0.88f, 0.62f, 0.27f, 1.0f);
        case PinType::Float: return ImVec4(0.36f, 0.74f, 0.96f, 1.0f);
        case PinType::Bool: return ImVec4(0.76f, 0.35f, 0.86f, 1.0f);
        case PinType::Int: return ImVec4(0.44f, 0.84f, 0.45f, 1.0f);
        case PinType::Trigger: return ImVec4(0.96f, 0.43f, 0.31f, 1.0f);
        default: return ImVec4(0.75f, 0.75f, 0.75f, 1.0f);
    }
}

inline const char *PinIcon(PinType type) {
    return type == PinType::Pose ? "▲" : (type == PinType::Trigger ? "◆" : "●");
}

inline int32_t PinCount(const AnimGraphNodeSchema &schema, PinDirection direction) {
    return static_cast<int32_t>(std::count_if(schema.pins.begin(),
                                              schema.pins.end(),
                                              [&](const AnimGraphPinSchema &pin) { return pin.direction == direction; }));
}

inline const AnimGraphPinSchema *PinAt(const AnimGraphNodeSchema &schema,
                                       PinDirection direction,
                                       int32_t slot) {
    int32_t currentSlot = 0;
    for (const auto &pin : schema.pins) {
        if (pin.direction != direction) {
            continue;
        }
        if (currentSlot == slot) {
            return &pin;
        }
        currentSlot += 1;
    }
    return nullptr;
}

inline const AnimGraphNodeSchema *SchemaForRuntimeType(int32_t runtimeType);
inline const AnimGraphNodeSchema *SchemaForTransitionType(std::string_view typeId);
inline const AnimGraphNodeSchema *SchemaForParameterProxy(int32_t parameterType);

inline const std::vector<AnimGraphNodeSchema> &AllSchemas() {
    static const std::vector<AnimGraphNodeSchema> schemas = {
        {
            "outputPose",
            0,
            "Output Pose",
            "Graph",
            GraphDomain::Root,
            {true, true, false},
            {
                {"pose", PinDirection::Input, PinType::Pose, "Pose", true, true, true},
            },
            {
                {"title", InlineFieldKind::Text, "Title", FieldVisibility::Always, FieldBinding::Title},
            },
            {ImVec4(190.0f / 255.0f, 105.0f / 255.0f, 72.0f / 255.0f, 1.0f), ImVec4(0.40f, 0.62f, 0.90f, 0.95f), true},
            {true, false, false, false},
            SubgraphOwnership::None,
            {},
            {}
        },
        {
            "clipPlayer",
            1,
            "Clip Player",
            "Playback",
            GraphDomain::Root,
            {true, true, false},
            {
                {"pose", PinDirection::Output, PinType::Pose, "Pose", false, false, true},
            },
            {
                {"title", InlineFieldKind::Text, "Title", FieldVisibility::Always, FieldBinding::Title},
                {"clip", InlineFieldKind::ClipHandle, "Clip", FieldVisibility::Always, FieldBinding::ClipHandle},
            },
            {ImVec4(84.0f / 255.0f, 131.0f / 255.0f, 104.0f / 255.0f, 1.0f), ImVec4(0.44f, 0.72f, 0.54f, 0.95f), false},
            {true, false, false, true},
            SubgraphOwnership::None,
            {true, false, false},
            {true, "Clip Player", "Playback", 10}
        },
        {
            "blend1D",
            2,
            "Blend1D",
            "Blend",
            GraphDomain::Root,
            {true, true, false},
            {
                {"parameter", PinDirection::Input, PinType::Float, "Param", false, true, true},
                {"pose", PinDirection::Output, PinType::Pose, "Pose", false, false, true},
            },
            {
                {"title", InlineFieldKind::Text, "Title", FieldVisibility::Always, FieldBinding::Title},
                {"parameter", InlineFieldKind::ParameterName, "Parameter", FieldVisibility::SelectedOnly, FieldBinding::ParameterName},
            },
            {ImVec4(146.0f / 255.0f, 114.0f / 255.0f, 62.0f / 255.0f, 1.0f), ImVec4(0.83f, 0.63f, 0.34f, 0.95f), false},
            {true, false, true, false},
            SubgraphOwnership::BlendSpace,
            {false, true, false},
            {true, "Blend1D", "Blend", 20}
        },
        {
            "blend2D",
            3,
            "Blend2D",
            "Blend",
            GraphDomain::Root,
            {true, true, false},
            {
                {"x", PinDirection::Input, PinType::Float, "X", false, true, true},
                {"y", PinDirection::Input, PinType::Float, "Y", false, true, true},
                {"pose", PinDirection::Output, PinType::Pose, "Pose", false, false, true},
            },
            {
                {"title", InlineFieldKind::Text, "Title", FieldVisibility::Always, FieldBinding::Title},
                {"xParameter", InlineFieldKind::ParameterName, "X Parameter", FieldVisibility::SelectedOnly, FieldBinding::ParameterXName},
                {"yParameter", InlineFieldKind::ParameterName, "Y Parameter", FieldVisibility::SelectedOnly, FieldBinding::ParameterYName},
            },
            {ImVec4(136.0f / 255.0f, 92.0f / 255.0f, 126.0f / 255.0f, 1.0f), ImVec4(0.73f, 0.50f, 0.70f, 0.95f), false},
            {true, false, true, false},
            SubgraphOwnership::BlendSpace,
            {false, true, false},
            {true, "Blend2D", "Blend", 21}
        },
        {
            "stateMachine",
            4,
            "State Machine",
            "Graph",
            GraphDomain::Root,
            {true, true, false},
            {
                {"pose", PinDirection::Output, PinType::Pose, "Pose", false, false, true},
            },
            {
                {"title", InlineFieldKind::Text, "Title", FieldVisibility::Always, FieldBinding::Title},
            },
            {ImVec4(110.0f / 255.0f, 126.0f / 255.0f, 212.0f / 255.0f, 1.0f), ImVec4(0.58f, 0.62f, 0.86f, 0.95f), true},
            {true, false, true, false},
            SubgraphOwnership::StateMachine,
            {},
            {true, "State Machine", "Graph", 30}
        },
        {
            "parameterFloat",
            8,
            "Float Parameter",
            "Parameters",
            GraphDomain::Root,
            {true, true, true},
            {
                {"value", PinDirection::Output, PinType::Float, "Value", false, false, true},
            },
            {
                {"parameter", InlineFieldKind::ParameterName, "Parameter", FieldVisibility::Always, FieldBinding::ParameterName},
            },
            {ImVec4(72.0f / 255.0f, 120.0f / 255.0f, 156.0f / 255.0f, 1.0f), ImVec4(0.36f, 0.74f, 0.96f, 0.95f), false},
            {},
            SubgraphOwnership::None,
            {false, true, false},
            {true, "Parameter Float", "Parameters", 40}
        },
        {
            "parameterBool",
            9,
            "Bool Parameter",
            "Parameters",
            GraphDomain::Root,
            {true, true, true},
            {
                {"value", PinDirection::Output, PinType::Bool, "Value", false, false, true},
            },
            {
                {"parameter", InlineFieldKind::ParameterName, "Parameter", FieldVisibility::Always, FieldBinding::ParameterName},
            },
            {ImVec4(72.0f / 255.0f, 120.0f / 255.0f, 156.0f / 255.0f, 1.0f), ImVec4(0.76f, 0.35f, 0.86f, 0.95f), false},
            {},
            SubgraphOwnership::None,
            {false, true, false},
            {true, "Parameter Bool", "Parameters", 41}
        },
        {
            "parameterTrigger",
            10,
            "Trigger Parameter",
            "Parameters",
            GraphDomain::Root,
            {true, true, true},
            {
                {"value", PinDirection::Output, PinType::Trigger, "Value", false, false, true},
            },
            {
                {"parameter", InlineFieldKind::ParameterName, "Parameter", FieldVisibility::Always, FieldBinding::ParameterName},
            },
            {ImVec4(72.0f / 255.0f, 120.0f / 255.0f, 156.0f / 255.0f, 1.0f), ImVec4(0.96f, 0.43f, 0.31f, 0.95f), false},
            {},
            SubgraphOwnership::None,
            {false, true, false},
            {true, "Parameter Trigger", "Parameters", 43}
        },
        {
            "parameterInt",
            20,
            "Int Parameter",
            "Parameters",
            GraphDomain::Root,
            {true, true, true},
            {
                {"value", PinDirection::Output, PinType::Int, "Value", false, false, true},
            },
            {
                {"parameter", InlineFieldKind::ParameterName, "Parameter", FieldVisibility::Always, FieldBinding::ParameterName},
            },
            {ImVec4(72.0f / 255.0f, 120.0f / 255.0f, 156.0f / 255.0f, 1.0f), ImVec4(0.44f, 0.84f, 0.45f, 0.95f), false},
            {},
            SubgraphOwnership::None,
            {false, true, false},
            {true, "Parameter Int", "Parameters", 42}
        },
        {
            "localFloat",
            21,
            "Local Float",
            "Locals",
            GraphDomain::Root,
            {true, true, true},
            {
                {"value", PinDirection::Output, PinType::Float, "Value", false, false, true},
            },
            {
                {"local", InlineFieldKind::LocalName, "Local", FieldVisibility::Always, FieldBinding::ParameterName},
            },
            {ImVec4(126.0f / 255.0f, 102.0f / 255.0f, 62.0f / 255.0f, 1.0f), ImVec4(0.36f, 0.74f, 0.96f, 0.95f), false},
            {},
            SubgraphOwnership::None,
            {false, false, true},
            {true, "Local Float", "Locals", 50}
        },
        {
            "localBool",
            22,
            "Local Bool",
            "Locals",
            GraphDomain::Root,
            {true, true, true},
            {
                {"value", PinDirection::Output, PinType::Bool, "Value", false, false, true},
            },
            {
                {"local", InlineFieldKind::LocalName, "Local", FieldVisibility::Always, FieldBinding::ParameterName},
            },
            {ImVec4(126.0f / 255.0f, 102.0f / 255.0f, 62.0f / 255.0f, 1.0f), ImVec4(0.76f, 0.35f, 0.86f, 0.95f), false},
            {},
            SubgraphOwnership::None,
            {false, false, true},
            {true, "Local Bool", "Locals", 51}
        },
        {
            "localInt",
            23,
            "Local Int",
            "Locals",
            GraphDomain::Root,
            {true, true, true},
            {
                {"value", PinDirection::Output, PinType::Int, "Value", false, false, true},
            },
            {
                {"local", InlineFieldKind::LocalName, "Local", FieldVisibility::Always, FieldBinding::ParameterName},
            },
            {ImVec4(126.0f / 255.0f, 102.0f / 255.0f, 62.0f / 255.0f, 1.0f), ImVec4(0.44f, 0.84f, 0.45f, 0.95f), false},
            {},
            SubgraphOwnership::None,
            {false, false, true},
            {true, "Local Int", "Locals", 52}
        },
        {
            "setLocalFloat",
            24,
            "Set Local Float",
            "Locals",
            GraphDomain::Root,
            {true, true, true},
            {
                {"valueIn", PinDirection::Input, PinType::Float, "Value", true, true, true},
                {"valueOut", PinDirection::Output, PinType::Float, "Value", false, false, true},
            },
            {
                {"local", InlineFieldKind::LocalName, "Local", FieldVisibility::Always, FieldBinding::ParameterName},
            },
            {ImVec4(162.0f / 255.0f, 112.0f / 255.0f, 72.0f / 255.0f, 1.0f), ImVec4(0.36f, 0.74f, 0.96f, 0.95f), false},
            {},
            SubgraphOwnership::None,
            {false, false, true},
            {true, "Set Local Float", "Locals", 53}
        },
        {
            "setLocalBool",
            25,
            "Set Local Bool",
            "Locals",
            GraphDomain::Root,
            {true, true, true},
            {
                {"valueIn", PinDirection::Input, PinType::Bool, "Value", true, true, true},
                {"valueOut", PinDirection::Output, PinType::Bool, "Value", false, false, true},
            },
            {
                {"local", InlineFieldKind::LocalName, "Local", FieldVisibility::Always, FieldBinding::ParameterName},
            },
            {ImVec4(162.0f / 255.0f, 112.0f / 255.0f, 72.0f / 255.0f, 1.0f), ImVec4(0.76f, 0.35f, 0.86f, 0.95f), false},
            {},
            SubgraphOwnership::None,
            {false, false, true},
            {true, "Set Local Bool", "Locals", 54}
        },
        {
            "setLocalInt",
            26,
            "Set Local Int",
            "Locals",
            GraphDomain::Root,
            {true, true, true},
            {
                {"valueIn", PinDirection::Input, PinType::Int, "Value", true, true, true},
                {"valueOut", PinDirection::Output, PinType::Int, "Value", false, false, true},
            },
            {
                {"local", InlineFieldKind::LocalName, "Local", FieldVisibility::Always, FieldBinding::ParameterName},
            },
            {ImVec4(162.0f / 255.0f, 112.0f / 255.0f, 72.0f / 255.0f, 1.0f), ImVec4(0.44f, 0.84f, 0.45f, 0.95f), false},
            {},
            SubgraphOwnership::None,
            {false, false, true},
            {true, "Set Local Int", "Locals", 55}
        },
        {
            "__parameterProxyFloat",
            100,
            "Input Parameter",
            "Parameters",
            GraphDomain::Root,
            {true, true, false},
            {
                {"value", PinDirection::Output, PinType::Float, "Value", false, false, true},
            },
            {},
            {ImVec4(70.0f / 255.0f, 95.0f / 255.0f, 130.0f / 255.0f, 1.0f), ImVec4(0.36f, 0.74f, 0.96f, 0.95f), false},
            {},
            SubgraphOwnership::None,
            {},
            {}
        },
        {
            "__parameterProxyBool",
            101,
            "Input Parameter",
            "Parameters",
            GraphDomain::Root,
            {true, true, false},
            {
                {"value", PinDirection::Output, PinType::Bool, "Value", false, false, true},
            },
            {},
            {ImVec4(70.0f / 255.0f, 95.0f / 255.0f, 130.0f / 255.0f, 1.0f), ImVec4(0.76f, 0.35f, 0.86f, 0.95f), false},
            {},
            SubgraphOwnership::None,
            {},
            {}
        },
        {
            "__parameterProxyInt",
            102,
            "Input Parameter",
            "Parameters",
            GraphDomain::Root,
            {true, true, false},
            {
                {"value", PinDirection::Output, PinType::Int, "Value", false, false, true},
            },
            {},
            {ImVec4(70.0f / 255.0f, 95.0f / 255.0f, 130.0f / 255.0f, 1.0f), ImVec4(0.44f, 0.84f, 0.45f, 0.95f), false},
            {},
            SubgraphOwnership::None,
            {},
            {}
        },
        {
            "__parameterProxyTrigger",
            103,
            "Input Parameter",
            "Parameters",
            GraphDomain::Root,
            {true, true, false},
            {
                {"value", PinDirection::Output, PinType::Trigger, "Value", false, false, true},
            },
            {},
            {ImVec4(70.0f / 255.0f, 95.0f / 255.0f, 130.0f / 255.0f, 1.0f), ImVec4(0.96f, 0.43f, 0.31f, 0.95f), false},
            {},
            SubgraphOwnership::None,
            {},
            {}
        },
        {
            "transitionOutput",
            -1,
            "Transition Output",
            "Output",
            GraphDomain::Transition,
            {false, false, true},
            {
                {"transition", PinDirection::Input, PinType::Bool, "Transition", false, true, true},
                {"synchronize", PinDirection::Input, PinType::Bool, "Synchronize", false, true, true},
                {"duration", PinDirection::Input, PinType::Float, "Duration", false, true, true},
            },
            {
                {"title", InlineFieldKind::Text, "Title", FieldVisibility::Always, FieldBinding::Title},
                {"boolValue", InlineFieldKind::Bool, "Transition", FieldVisibility::Always, FieldBinding::BoolValue},
                {"synchronizeValue", InlineFieldKind::Bool, "Synchronize", FieldVisibility::Always, FieldBinding::SynchronizeValue},
                {"duration", InlineFieldKind::Float, "Duration", FieldVisibility::Always, FieldBinding::Duration},
            },
            {},
            {},
            SubgraphOwnership::None,
            {},
            {true, "Transition Output", "Output", 10}
        },
        {
            "floatConstant",
            -1,
            "Float Constant",
            "Constants",
            GraphDomain::Transition,
            {false, false, true},
            {
                {"value", PinDirection::Output, PinType::Float, "Value", false, false, true},
            },
            {
                {"floatValue", InlineFieldKind::Float, "Value", FieldVisibility::Always, FieldBinding::FloatValue},
            },
            {},
            {},
            SubgraphOwnership::None,
            {},
            {true, "Float Constant", "Constants", 20}
        },
        {
            "boolConstant",
            -1,
            "Bool Constant",
            "Constants",
            GraphDomain::Transition,
            {false, false, true},
            {
                {"value", PinDirection::Output, PinType::Bool, "Value", false, false, true},
            },
            {
                {"boolValue", InlineFieldKind::Bool, "Value", FieldVisibility::Always, FieldBinding::BoolValue},
            },
            {},
            {},
            SubgraphOwnership::None,
            {},
            {true, "Bool Constant", "Constants", 21}
        },
        {
            "compareFloatGreater",
            -1,
            "Compare >",
            "Comparisons",
            GraphDomain::Transition,
            {false, false, true},
            {
                {"x", PinDirection::Input, PinType::Float, "X", true, true, true},
                {"y", PinDirection::Input, PinType::Float, "Y", true, true, true},
                {"result", PinDirection::Output, PinType::Bool, "Result", false, false, true},
            },
            {},
            {},
            {},
            SubgraphOwnership::None,
            {},
            {true, "Compare Float >", "Comparisons", 30}
        },
        {
            "compareFloatLess",
            -1,
            "Compare <",
            "Comparisons",
            GraphDomain::Transition,
            {false, false, true},
            {
                {"x", PinDirection::Input, PinType::Float, "X", true, true, true},
                {"y", PinDirection::Input, PinType::Float, "Y", true, true, true},
                {"result", PinDirection::Output, PinType::Bool, "Result", false, false, true},
            },
            {},
            {},
            {},
            SubgraphOwnership::None,
            {},
            {true, "Compare Float <", "Comparisons", 31}
        },
        {
            "compareFloatEqual",
            -1,
            "Compare ==",
            "Comparisons",
            GraphDomain::Transition,
            {false, false, true},
            {
                {"x", PinDirection::Input, PinType::Float, "X", true, true, true},
                {"y", PinDirection::Input, PinType::Float, "Y", true, true, true},
                {"result", PinDirection::Output, PinType::Bool, "Result", false, false, true},
            },
            {},
            {},
            {},
            SubgraphOwnership::None,
            {},
            {true, "Compare Float ==", "Comparisons", 32}
        },
        {
            "and",
            -1,
            "Logical AND",
            "Logical",
            GraphDomain::Transition,
            {false, false, true},
            {
                {"a", PinDirection::Input, PinType::Bool, "A", true, true, true},
                {"b", PinDirection::Input, PinType::Bool, "B", true, true, true},
                {"result", PinDirection::Output, PinType::Bool, "Result", false, false, true},
            },
            {},
            {},
            {},
            SubgraphOwnership::None,
            {},
            {true, "AND", "Logical", 40}
        },
        {
            "or",
            -1,
            "Logical OR",
            "Logical",
            GraphDomain::Transition,
            {false, false, true},
            {
                {"a", PinDirection::Input, PinType::Bool, "A", true, true, true},
                {"b", PinDirection::Input, PinType::Bool, "B", true, true, true},
                {"result", PinDirection::Output, PinType::Bool, "Result", false, false, true},
            },
            {},
            {},
            {},
            SubgraphOwnership::None,
            {},
            {true, "OR", "Logical", 41}
        },
        {
            "not",
            -1,
            "Logical NOT",
            "Logical",
            GraphDomain::Transition,
            {false, false, true},
            {
                {"a", PinDirection::Input, PinType::Bool, "A", true, true, true},
                {"result", PinDirection::Output, PinType::Bool, "Result", false, false, true},
            },
            {},
            {},
            {},
            SubgraphOwnership::None,
            {},
            {true, "NOT", "Logical", 42}
        },
        {
            "parameterFloat",
            -1,
            "Float Parameter",
            "Parameters",
            GraphDomain::Transition,
            {false, false, true},
            {
                {"value", PinDirection::Output, PinType::Float, "Value", false, false, true},
            },
            {
                {"parameter", InlineFieldKind::ParameterName, "Parameter", FieldVisibility::Always, FieldBinding::ParameterName},
            },
            {},
            {},
            SubgraphOwnership::None,
            {false, true, false},
            {true, "Float Parameter", "Parameters", 50}
        },
        {
            "parameterBool",
            -1,
            "Bool Parameter",
            "Parameters",
            GraphDomain::Transition,
            {false, false, true},
            {
                {"value", PinDirection::Output, PinType::Bool, "Value", false, false, true},
            },
            {
                {"parameter", InlineFieldKind::ParameterName, "Parameter", FieldVisibility::Always, FieldBinding::ParameterName},
            },
            {},
            {},
            SubgraphOwnership::None,
            {false, true, false},
            {true, "Bool Parameter", "Parameters", 51}
        },
        {
            "parameterInt",
            -1,
            "Int Parameter",
            "Parameters",
            GraphDomain::Transition,
            {false, false, true},
            {
                {"value", PinDirection::Output, PinType::Int, "Value", false, false, true},
            },
            {
                {"parameter", InlineFieldKind::ParameterName, "Parameter", FieldVisibility::Always, FieldBinding::ParameterName},
            },
            {},
            {},
            SubgraphOwnership::None,
            {false, true, false},
            {true, "Int Parameter", "Parameters", 52}
        },
        {
            "parameterTrigger",
            -1,
            "Trigger Parameter",
            "Parameters",
            GraphDomain::Transition,
            {false, false, true},
            {
                {"value", PinDirection::Output, PinType::Trigger, "Value", false, false, true},
            },
            {
                {"parameter", InlineFieldKind::ParameterName, "Parameter", FieldVisibility::Always, FieldBinding::ParameterName},
            },
            {},
            {},
            SubgraphOwnership::None,
            {false, true, false},
            {true, "Trigger Parameter", "Parameters", 53}
        },
        {
            "localFloat",
            -1,
            "Float Local",
            "Locals",
            GraphDomain::Transition,
            {false, false, true},
            {
                {"value", PinDirection::Output, PinType::Float, "Value", false, false, true},
            },
            {
                {"local", InlineFieldKind::LocalName, "Local", FieldVisibility::Always, FieldBinding::ParameterName},
            },
            {},
            {},
            SubgraphOwnership::None,
            {false, false, true},
            {true, "Float Local", "Locals", 60}
        },
        {
            "localBool",
            -1,
            "Bool Local",
            "Locals",
            GraphDomain::Transition,
            {false, false, true},
            {
                {"value", PinDirection::Output, PinType::Bool, "Value", false, false, true},
            },
            {
                {"local", InlineFieldKind::LocalName, "Local", FieldVisibility::Always, FieldBinding::ParameterName},
            },
            {},
            {},
            SubgraphOwnership::None,
            {false, false, true},
            {true, "Bool Local", "Locals", 61}
        },
        {
            "localInt",
            -1,
            "Int Local",
            "Locals",
            GraphDomain::Transition,
            {false, false, true},
            {
                {"value", PinDirection::Output, PinType::Int, "Value", false, false, true},
            },
            {
                {"local", InlineFieldKind::LocalName, "Local", FieldVisibility::Always, FieldBinding::ParameterName},
            },
            {},
            {},
            SubgraphOwnership::None,
            {false, false, true},
            {true, "Int Local", "Locals", 62}
        },
        {
            "setLocalFloat",
            -1,
            "Set Local Float",
            "Locals",
            GraphDomain::Transition,
            {false, false, true},
            {
                {"valueIn", PinDirection::Input, PinType::Float, "Value", true, true, true},
                {"valueOut", PinDirection::Output, PinType::Float, "Value", false, false, true},
            },
            {
                {"local", InlineFieldKind::LocalName, "Local", FieldVisibility::Always, FieldBinding::ParameterName},
            },
            {},
            {},
            SubgraphOwnership::None,
            {false, false, true},
            {true, "Set Local Float", "Locals", 63}
        },
        {
            "setLocalBool",
            -1,
            "Set Local Bool",
            "Locals",
            GraphDomain::Transition,
            {false, false, true},
            {
                {"valueIn", PinDirection::Input, PinType::Bool, "Value", true, true, true},
                {"valueOut", PinDirection::Output, PinType::Bool, "Value", false, false, true},
            },
            {
                {"local", InlineFieldKind::LocalName, "Local", FieldVisibility::Always, FieldBinding::ParameterName},
            },
            {},
            {},
            SubgraphOwnership::None,
            {false, false, true},
            {true, "Set Local Bool", "Locals", 64}
        },
        {
            "setLocalInt",
            -1,
            "Set Local Int",
            "Locals",
            GraphDomain::Transition,
            {false, false, true},
            {
                {"valueIn", PinDirection::Input, PinType::Int, "Value", true, true, true},
                {"valueOut", PinDirection::Output, PinType::Int, "Value", false, false, true},
            },
            {
                {"local", InlineFieldKind::LocalName, "Local", FieldVisibility::Always, FieldBinding::ParameterName},
            },
            {},
            {},
            SubgraphOwnership::None,
            {false, false, true},
            {true, "Set Local Int", "Locals", 65}
        },
    };
    return schemas;
}

inline const AnimGraphNodeSchema *SchemaForRuntimeType(int32_t runtimeType) {
    const auto &schemas = AllSchemas();
    const auto found = std::find_if(schemas.begin(), schemas.end(), [&](const AnimGraphNodeSchema &schema) {
        return schema.runtimeType == runtimeType;
    });
    return found != schemas.end() ? &(*found) : nullptr;
}

inline const AnimGraphNodeSchema *SchemaForTransitionType(std::string_view typeId) {
    const std::string normalized = NormalizeTypeId(typeId);
    const auto &schemas = AllSchemas();
    const auto found = std::find_if(schemas.begin(), schemas.end(), [&](const AnimGraphNodeSchema &schema) {
        return schema.domain == GraphDomain::Transition && NormalizeTypeId(schema.typeId) == normalized;
    });
    return found != schemas.end() ? &(*found) : nullptr;
}

inline const AnimGraphNodeSchema *SchemaForParameterProxy(int32_t parameterType) {
    switch (parameterType) {
        case 1: return SchemaForRuntimeType(101);
        case 2: return SchemaForRuntimeType(102);
        case 3: return SchemaForRuntimeType(103);
        default: return SchemaForRuntimeType(100);
    }
}

inline std::vector<const AnimGraphNodeSchema *> CreatableSchemasForDomain(GraphDomain domain) {
    std::vector<const AnimGraphNodeSchema *> results;
    const auto &schemas = AllSchemas();
    for (const auto &schema : schemas) {
        if (schema.domain != domain || !schema.createMenu.creatable) {
            continue;
        }
        results.push_back(&schema);
    }
    std::sort(results.begin(), results.end(), [](const AnimGraphNodeSchema *lhs, const AnimGraphNodeSchema *rhs) {
        if (lhs->createMenu.category == rhs->createMenu.category) {
            return lhs->createMenu.sortOrder < rhs->createMenu.sortOrder;
        }
        if (lhs->createMenu.sortOrder == rhs->createMenu.sortOrder) {
            return lhs->createMenu.category < rhs->createMenu.category;
        }
        return lhs->createMenu.sortOrder < rhs->createMenu.sortOrder;
    });
    return results;
}

} // namespace AnimationGraphSchema
