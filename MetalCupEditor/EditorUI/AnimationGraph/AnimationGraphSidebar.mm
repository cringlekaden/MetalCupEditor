#include "AnimationGraphSidebar.h"

#include "AnimationGraphDebugView.h"
#include "AnimationGraphInspector.h"
#include "AnimationGraphSchema.h"
#include "AnimationGraphUIStateStore.h"

#include "../Widgets/UIWidgets.h"
#include "../../ImGui/imgui.h"

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstring>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

extern "C" int32_t MCEEditorGetAssetCount(void *context);
extern "C" uint32_t MCEEditorGetAssetAt(void *context, int32_t index,
                                        char *handleBuffer, int32_t handleBufferSize,
                                        int32_t *typeOut,
                                        char *pathBuffer, int32_t pathBufferSize,
                                        char *nameBuffer, int32_t nameBufferSize);
extern "C" uint32_t MCEEditorGetAssetDisplayName(void *context, const char *handle, char *buffer, int32_t bufferSize);
extern "C" uint32_t MCEEditorEntityHasComponent(void *context, const char *entityId, int32_t type);
extern "C" uint32_t MCEEditorGetSkinnedMesh(void *context, const char *entityId,
                                              char *skeletonHandleBuffer, int32_t skeletonHandleBufferSize,
                                              int32_t *jointCountOut,
                                              uint32_t *isValidSkeletonOut);
extern "C" uint32_t MCEEditorAddAnimationGraphParameter(void *context, const char *handle, const char *name, int32_t type, float defaultFloat, uint32_t defaultBool, int32_t defaultInt);
extern "C" uint32_t MCEEditorUpdateAnimationGraphParameter(void *context, const char *handle, int32_t index,
                                                             const char *name, int32_t type, float defaultFloat, uint32_t defaultBool, int32_t defaultInt);
extern "C" uint32_t MCEEditorRemoveAnimationGraphParameter(void *context, const char *handle, int32_t index);
extern "C" uint32_t MCEEditorAddAnimationGraphLocalVariable(void *context, const char *handle, const char *name, int32_t type, float defaultFloat, uint32_t defaultBool, int32_t defaultInt);
extern "C" uint32_t MCEEditorUpdateAnimationGraphLocalVariable(void *context, const char *handle, int32_t index,
                                                                 const char *name, int32_t type, float defaultFloat, uint32_t defaultBool, int32_t defaultInt);
extern "C" uint32_t MCEEditorRemoveAnimationGraphLocalVariable(void *context, const char *handle, int32_t index);
extern "C" uint32_t MCEEditorUpdateAnimationGraphNode(void *context, const char *handle, const char *nodeId,
                                                        const char *title, float posX, float posY, const char *clipHandle);
extern "C" uint32_t MCEEditorSetAnimationGraphOutputNode(void *context, const char *handle, const char *nodeId);
extern "C" uint32_t MCEEditorRemoveAnimationGraphNode(void *context, const char *handle, const char *nodeId);
extern "C" uint32_t MCEEditorSetAnimationGraphBlend1DNode(void *context, const char *handle, const char *nodeId, const char *parameterName);
extern "C" uint32_t MCEEditorAddAnimationGraphBlend1DSample(void *context, const char *handle, const char *nodeId, const char *clipHandle, float threshold);
extern "C" uint32_t MCEEditorUpdateAnimationGraphBlend1DSample(void *context, const char *handle, const char *nodeId, int32_t index, const char *clipHandle, float threshold);
extern "C" uint32_t MCEEditorRemoveAnimationGraphBlend1DSample(void *context, const char *handle, const char *nodeId, int32_t index);
extern "C" uint32_t MCEEditorSetAnimationGraphBlend2DNode(void *context, const char *handle, const char *nodeId, const char *parameterXName, const char *parameterYName);
extern "C" uint32_t MCEEditorAddAnimationGraphBlend2DSample(void *context, const char *handle, const char *nodeId, const char *clipHandle, float x, float y);
extern "C" uint32_t MCEEditorUpdateAnimationGraphBlend2DSample(void *context, const char *handle, const char *nodeId, int32_t index, const char *clipHandle, float x, float y);
extern "C" uint32_t MCEEditorRemoveAnimationGraphBlend2DSample(void *context, const char *handle, const char *nodeId, int32_t index);
extern "C" uint32_t MCEEditorSetAnimationGraphStateMachineDefaultState(void *context, const char *handle, const char *nodeId, const char *stateId);
extern "C" uint32_t MCEEditorRemoveAnimationGraphStateMachineState(void *context, const char *handle, const char *nodeId, const char *stateId);
extern "C" uint32_t MCEEditorAddAnimationGraphStateMachineState(void *context, const char *handle, const char *nodeId,
                                                                  const char *name, const char *clipHandle, const char *nodeRefId,
                                                                  uint32_t isOneShot,
                                                                  uint32_t usesRootMotion,
                                                                  char *outStateId, int32_t outStateIdSize);
extern "C" uint32_t MCEEditorUpdateAnimationGraphStateMachineState(void *context, const char *handle, const char *nodeId,
                                                                     const char *stateId, const char *name, const char *clipHandle, const char *nodeRefId,
                                                                     uint32_t isOneShot,
                                                                     uint32_t usesRootMotion);
extern "C" uint32_t MCEEditorAddAnimationGraphStateMachineTransition(void *context, const char *handle, const char *nodeId,
                                                                       const char *fromStateId, const char *toStateId,
                                                                       float duration, uint32_t hasMinimumNormalizedTime, float minimumNormalizedTime,
                                                                       char *outTransitionId, int32_t outTransitionIdSize);
extern "C" uint32_t MCEEditorUpdateAnimationGraphStateMachineTransition(void *context, const char *handle, const char *nodeId,
                                                                          const char *transitionId, const char *fromStateId, const char *toStateId,
                                                                          float duration, uint32_t hasMinimumNormalizedTime, float minimumNormalizedTime);
extern "C" uint32_t MCEEditorRemoveAnimationGraphStateMachineTransition(void *context, const char *handle, const char *nodeId, const char *transitionId);
extern "C" uint32_t MCEEditorAddAnimationGraphStateMachineCondition(void *context, const char *handle, const char *nodeId, const char *transitionId,
                                                                      const char *parameterName, const char *op,
                                                                      float floatValue, int32_t intValue, uint32_t boolValue,
                                                                      uint32_t hasFloat, uint32_t hasInt, uint32_t hasBool);
extern "C" uint32_t MCEEditorUpdateAnimationGraphStateMachineCondition(void *context, const char *handle, const char *nodeId, const char *transitionId, int32_t index,
                                                                         const char *parameterName, const char *op,
                                                                         float floatValue, int32_t intValue, uint32_t boolValue,
                                                                         uint32_t hasFloat, uint32_t hasInt, uint32_t hasBool);
extern "C" uint32_t MCEEditorRemoveAnimationGraphStateMachineCondition(void *context, const char *handle, const char *nodeId, const char *transitionId, int32_t index);

namespace {
constexpr int32_t kAssetTypeAnimationClip = 9;
constexpr int32_t kComponentSkinnedMesh = 11;

struct AnimationClipOption {
    std::string handle;
    std::string label;
};

struct VariableDraftState {
    std::string name;
    int type = 0;
    float defaultFloat = 0.0f;
    bool defaultBool = false;
    int defaultInt = 0;
};

static std::unordered_map<std::string, VariableDraftState> &InputDraftsByGraph() {
    static std::unordered_map<std::string, VariableDraftState> drafts;
    return drafts;
}

static std::unordered_map<std::string, VariableDraftState> &LocalDraftsByGraph() {
    static std::unordered_map<std::string, VariableDraftState> drafts;
    return drafts;
}

static std::unordered_map<std::string, bool> &InputCreationOpenByGraph() {
    static std::unordered_map<std::string, bool> openByGraph;
    return openByGraph;
}

static std::unordered_map<std::string, bool> &LocalCreationOpenByGraph() {
    static std::unordered_map<std::string, bool> openByGraph;
    return openByGraph;
}

static std::vector<AnimationClipOption> CollectAnimationClipOptions(void *context) {
    std::vector<AnimationClipOption> options;
    const int32_t assetCount = MCEEditorGetAssetCount(context);
    if (assetCount <= 0) { return options; }
    options.reserve(static_cast<size_t>(assetCount));
    for (int32_t i = 0; i < assetCount; ++i) {
        char handle[64] = {0};
        char path[512] = {0};
        char name[128] = {0};
        int32_t type = -1;
        if (MCEEditorGetAssetAt(context,
                                i,
                                handle,
                                sizeof(handle),
                                &type,
                                path,
                                sizeof(path),
                                name,
                                sizeof(name)) == 0) {
            continue;
        }
        if (type != kAssetTypeAnimationClip || handle[0] == 0) { continue; }
        AnimationClipOption option;
        option.handle = handle;
        option.label = name[0] != 0 ? name : handle;
        options.push_back(option);
    }
    std::sort(options.begin(), options.end(), [](const AnimationClipOption &a, const AnimationClipOption &b) {
        return a.label < b.label;
    });
    return options;
}

static std::string ShortHandleLabel(const std::string &handle) {
    if (handle.size() <= 12) { return handle; }
    return handle.substr(0, 8) + "..." + handle.substr(handle.size() - 4);
}

static std::string DisplayNameForAssetHandle(void *context, const std::string &handle) {
    if (handle.empty()) { return "<None>"; }
    char nameBuffer[128] = {0};
    if (MCEEditorGetAssetDisplayName(context, handle.c_str(), nameBuffer, sizeof(nameBuffer)) != 0 && nameBuffer[0] != 0) {
        return nameBuffer;
    }
    return ShortHandleLabel(handle);
}

template <typename RecordCollection>
static std::string UniqueDraftName(const char *baseName, const RecordCollection &records) {
    std::string name = baseName;
    int suffix = 1;
    auto exists = [&](const std::string &candidate) {
        return std::any_of(records.begin(), records.end(), [&](const auto &record) {
            return record.name == candidate;
        });
    };
    while (exists(name)) {
        name = std::string(baseName) + " " + std::to_string(suffix++);
    }
    return name;
}

static const char *InputTypeLabel(int32_t type) {
    switch (type) {
        case 1: return "Bool";
        case 2: return "Int";
        case 3: return "Trigger";
        default: return "Float";
    }
}

static const char *LocalTypeLabel(int32_t type) {
    switch (type) {
        case 1: return "Bool";
        case 2: return "Int";
        default: return "Float";
    }
}

static ImVec4 TypeTintForScalarType(int32_t type) {
    switch (type) {
        case 1: return ImVec4(0.76f, 0.35f, 0.86f, 1.0f);
        case 2: return ImVec4(0.44f, 0.84f, 0.45f, 1.0f);
        case 3: return ImVec4(0.96f, 0.43f, 0.31f, 1.0f);
        default: return ImVec4(0.36f, 0.74f, 0.96f, 1.0f);
    }
}

static void DrawSidebarSectionHeader(const char *title, const char *subtitle) {
    ImGui::TextUnformatted(title);
    if (subtitle && subtitle[0] != 0) {
        ImGui::TextDisabled("%s", subtitle);
    }
}

static void DrawVariableDefaultEditor(const char *idPrefix,
                                      int type,
                                      float &defaultFloat,
                                      bool &defaultBool,
                                      int &defaultInt) {
    if (type == 0) {
        ImGui::SetNextItemWidth(-1.0f);
        ImGui::DragFloat((std::string("##").append(idPrefix).append("Float")).c_str(), &defaultFloat, 0.01f, -10000.0f, 10000.0f, "%.3f");
    } else if (type == 1 || type == 3) {
        ImGui::Checkbox((std::string("##").append(idPrefix).append("Bool")).c_str(), &defaultBool);
    } else {
        ImGui::SetNextItemWidth(-1.0f);
        ImGui::DragInt((std::string("##").append(idPrefix).append("Int")).c_str(), &defaultInt, 1.0f, -10000, 10000);
    }
}

static bool DrawTypeCombo(const char *id, const char *const *labels, int count, int &type) {
    ImGui::SetNextItemWidth(-1.0f);
    return ImGui::Combo(id, &type, labels, count);
}

static void BeginRowDragSource(const char *payloadType,
                               int32_t type,
                               const std::string &name,
                               const char *labelPrefix) {
    if (!ImGui::BeginDragDropSource(ImGuiDragDropFlags_SourceAllowNullID)) {
        return;
    }
    std::string payload = std::to_string(type) + "|" + name;
    ImGui::SetDragDropPayload(payloadType, payload.c_str(), payload.size() + 1);
    ImGui::Text("%s", labelPrefix);
    ImGui::TextUnformatted(name.c_str());
    ImGui::EndDragDropSource();
}

}

void DrawAnimationGraphSidebar(void *context,
                               const char *selectedEntityId,
                               AnimationGraphSnapshot &snapshot,
                               MCEPanelState::AnimationGraphPanelState &state,
                               bool hasRuntimeDebugSnapshot,
                               const AnimationGraphRuntimeDebugSnapshot &runtimeDebugSnapshot) {
    VariableDraftState &inputDraft = InputDraftsByGraph()[state.activeGraphHandle];
    VariableDraftState &localDraft = LocalDraftsByGraph()[state.activeGraphHandle];
    bool &inputCreationOpen = InputCreationOpenByGraph()[state.activeGraphHandle];
    bool &localCreationOpen = LocalCreationOpenByGraph()[state.activeGraphHandle];
    static const char *kInputTypes[] = {"Float", "Bool", "Int", "Trigger"};
    static const char *kLocalTypes[] = {"Float", "Bool", "Int"};

            ImGui::BeginChild("AnimationGraphSidebar", ImVec2(0.0f, 0.0f), false, ImGuiWindowFlags_AlwaysVerticalScrollbar);
            int32_t &selectedInputIndex = AnimationGraphUIStateStore::SelectedInputIndexForGraph(state.activeGraphHandle);
            int32_t &selectedLocalIndex = AnimationGraphUIStateStore::SelectedLocalIndexForGraph(state.activeGraphHandle);
            state.selectedInputIndex = selectedInputIndex;
            state.selectedLocalVariableIndex = selectedLocalIndex;
            if (selectedInputIndex >= static_cast<int32_t>(snapshot.parameters.size())) {
                selectedInputIndex = -1;
            }
            if (selectedLocalIndex >= static_cast<int32_t>(snapshot.localVariables.size())) {
                selectedLocalIndex = -1;
            }
            const float sidebarHeight = ImGui::GetContentRegionAvail().y;
            const float topHeight = std::max(170.0f, sidebarHeight * std::clamp(state.sidebarSplitRatio, 0.25f, 0.80f));
            ImGui::BeginChild("AnimationAuthoringTop", ImVec2(0.0f, topHeight), true);
            DrawSidebarSectionHeader("Skeleton", "Reference binding from the selected skinned entity.");
            const bool hasSelectedEntity = selectedEntityId[0] != 0;
            const bool hasSkinnedMeshComponent = hasSelectedEntity &&
                (MCEEditorEntityHasComponent(context, selectedEntityId, kComponentSkinnedMesh) != 0);
            if (!hasSelectedEntity) {
                ImGui::TextDisabled("Select an entity to inspect skeleton binding.");
            } else if (!hasSkinnedMeshComponent) {
                ImGui::TextDisabled("Selected entity has no skinned mesh.");
            } else {
                char skeletonHandle[64] = {0};
                int32_t jointCount = 0;
                uint32_t isValidSkeleton = 0;
                if (MCEEditorGetSkinnedMesh(context,
                                            selectedEntityId,
                                            skeletonHandle,
                                            sizeof(skeletonHandle),
                                            &jointCount,
                                            &isValidSkeleton) != 0 &&
                    skeletonHandle[0] != 0) {
                    const std::string skeletonLabel = DisplayNameForAssetHandle(context, skeletonHandle);
                    ImGui::Text("Bound: %s", skeletonLabel.c_str());
                    ImGui::TextDisabled("Joints: %d", jointCount);
                    ImGui::TextDisabled("%s", isValidSkeleton != 0 ? "Status: Valid" : "Status: Missing/Invalid");
                } else {
                    ImGui::TextDisabled("No skeleton assigned.");
                }
            }
            ImGui::Spacing();
            DrawSidebarSectionHeader("Inputs", "Define graph-facing parameters and drag them into the canvas.");
            ImGui::SameLine();
            if (ImGui::SmallButton("+##AddInput")) {
                inputDraft.name = UniqueDraftName("New Input", snapshot.parameters);
                inputDraft.type = 0;
                inputDraft.defaultFloat = 0.0f;
                inputDraft.defaultBool = false;
                inputDraft.defaultInt = 0;
                inputCreationOpen = true;
                selectedInputIndex = -1;
            }
            if (inputCreationOpen) {
                ImGui::BeginChild("InputCreateRow", ImVec2(0.0f, 72.0f), true);
                char nameBuffer[128] = {0};
                std::strncpy(nameBuffer, inputDraft.name.c_str(), sizeof(nameBuffer) - 1);
                ImGui::SetNextItemWidth(-1.0f);
                if (ImGui::InputTextWithHint("##NewInputName", "Input name", nameBuffer, sizeof(nameBuffer))) {
                    inputDraft.name = nameBuffer;
                }
                if (ImGui::BeginTable("InputCreateTable", 4, ImGuiTableFlags_SizingStretchProp)) {
                    ImGui::TableSetupColumn("Type", ImGuiTableColumnFlags_WidthStretch, 0.28f);
                    ImGui::TableSetupColumn("Default", ImGuiTableColumnFlags_WidthStretch, 0.36f);
                    ImGui::TableSetupColumn("Create", ImGuiTableColumnFlags_WidthFixed, 60.0f);
                    ImGui::TableSetupColumn("Cancel", ImGuiTableColumnFlags_WidthFixed, 60.0f);
                    ImGui::TableNextRow();
                    ImGui::TableSetColumnIndex(0);
                    DrawTypeCombo("##NewInputType", kInputTypes, IM_ARRAYSIZE(kInputTypes), inputDraft.type);
                    ImGui::TableSetColumnIndex(1);
                    DrawVariableDefaultEditor("NewInputDefault", inputDraft.type, inputDraft.defaultFloat, inputDraft.defaultBool, inputDraft.defaultInt);
                    ImGui::TableSetColumnIndex(2);
                    const bool canCreateInput = !inputDraft.name.empty();
                    if (!canCreateInput) {
                        ImGui::BeginDisabled();
                    }
                    if (ImGui::Button("Create##Input", ImVec2(-1.0f, 0.0f))) {
                        if (MCEEditorAddAnimationGraphParameter(context,
                                                                state.activeGraphHandle.c_str(),
                                                                inputDraft.name.c_str(),
                                                                inputDraft.type,
                                                                inputDraft.defaultFloat,
                                                                inputDraft.defaultBool ? 1u : 0u,
                                                                inputDraft.defaultInt) != 0) {
                            inputCreationOpen = false;
                            selectedInputIndex = -1;
                        }
                    }
                    if (!canCreateInput) {
                        ImGui::EndDisabled();
                    }
                    ImGui::TableSetColumnIndex(3);
                    if (ImGui::Button("Cancel##InputCreate", ImVec2(-1.0f, 0.0f))) {
                        inputCreationOpen = false;
                    }
                    ImGui::EndTable();
                }
                ImGui::EndChild();
            }
            ImGui::BeginChild("InputsList", ImVec2(0.0f, 164.0f), true);
            if (ImGui::BeginTable("InputsTable", 4, ImGuiTableFlags_SizingStretchProp | ImGuiTableFlags_RowBg | ImGuiTableFlags_BordersInnerV)) {
                ImGui::TableSetupColumn("Name", ImGuiTableColumnFlags_WidthStretch, 0.38f);
                ImGui::TableSetupColumn("Type", ImGuiTableColumnFlags_WidthStretch, 0.18f);
                ImGui::TableSetupColumn("Default", ImGuiTableColumnFlags_WidthStretch, 0.24f);
                ImGui::TableSetupColumn("Tools", ImGuiTableColumnFlags_WidthFixed, 96.0f);
            for (size_t i = 0; i < snapshot.parameters.size(); ++i) {
                const auto &param = snapshot.parameters[i];
                ImGui::PushID(static_cast<int>(i));
                ImGui::TableNextRow();
                ImGui::TableSetColumnIndex(0);
                char nameBuffer[128] = {0};
                std::strncpy(nameBuffer, param.name.c_str(), sizeof(nameBuffer) - 1);
                if (ImGui::InputText("##InputName", nameBuffer, sizeof(nameBuffer))) {
                    MCEEditorUpdateAnimationGraphParameter(context,
                                                           state.activeGraphHandle.c_str(),
                                                           static_cast<int32_t>(i),
                                                           nameBuffer,
                                                           param.type,
                                                           param.defaultFloat,
                                                           param.defaultBool ? 1u : 0u,
                                                           param.defaultInt);
                }
                if (ImGui::IsItemActivated()) {
                    selectedInputIndex = static_cast<int32_t>(i);
                    selectedLocalIndex = -1;
                }
                if (hasRuntimeDebugSnapshot && state.showRuntimeDebug) {
                    auto runtimeIt = std::find_if(runtimeDebugSnapshot.parameters.begin(),
                                                  runtimeDebugSnapshot.parameters.end(),
                                                  [&](const AnimationGraphRuntimeParameterValueRecord &record) {
                        return record.name == param.name;
                    });
                    if (runtimeIt != runtimeDebugSnapshot.parameters.end()) {
                        std::string valueLabel;
                        switch (runtimeIt->type) {
                            case 0: valueLabel = std::to_string(runtimeIt->floatValue); break;
                            case 1: valueLabel = runtimeIt->boolValue ? "true" : "false"; break;
                            case 2: valueLabel = std::to_string(runtimeIt->intValue); break;
                            case 3: valueLabel = runtimeIt->triggerValue ? "triggered" : "idle"; break;
                            default: valueLabel = ""; break;
                        }
                        if (!valueLabel.empty()) {
                            ImGui::TextDisabled("Runtime: %s", valueLabel.c_str());
                        }
                    }
                }
                ImGui::TableSetColumnIndex(1);
                int type = param.type;
                if (DrawTypeCombo("##InputType", kInputTypes, IM_ARRAYSIZE(kInputTypes), type)) {
                    MCEEditorUpdateAnimationGraphParameter(context,
                                                           state.activeGraphHandle.c_str(),
                                                           static_cast<int32_t>(i),
                                                           param.name.c_str(),
                                                           type,
                                                           param.defaultFloat,
                                                           param.defaultBool ? 1u : 0u,
                                                           param.defaultInt);
                    selectedInputIndex = static_cast<int32_t>(i);
                    selectedLocalIndex = -1;
                }
                ImGui::TableSetColumnIndex(2);
                float defaultFloat = param.defaultFloat;
                bool defaultBool = param.defaultBool;
                int defaultInt = param.defaultInt;
                DrawVariableDefaultEditor("InputDefault", type, defaultFloat, defaultBool, defaultInt);
                if (ImGui::IsItemDeactivatedAfterEdit()) {
                    MCEEditorUpdateAnimationGraphParameter(context,
                                                           state.activeGraphHandle.c_str(),
                                                           static_cast<int32_t>(i),
                                                           param.name.c_str(),
                                                           type,
                                                           defaultFloat,
                                                           defaultBool ? 1u : 0u,
                                                           defaultInt);
                    selectedInputIndex = static_cast<int32_t>(i);
                    selectedLocalIndex = -1;
                }
                ImGui::TableSetColumnIndex(3);
                if (ImGui::SmallButton("Delete##Input")) {
                    MCEEditorRemoveAnimationGraphParameter(context, state.activeGraphHandle.c_str(), static_cast<int32_t>(i));
                    if (selectedInputIndex == static_cast<int32_t>(i)) {
                        selectedInputIndex = -1;
                    }
                    ImGui::PopID();
                    continue;
                }
                ImGui::SameLine();
                ImGui::Button("Drag##Input", ImVec2(-1.0f, 0.0f));
                BeginRowDragSource("MCE_ANIM_GRAPH_INPUT_DEF",
                                   type,
                                   param.name,
                                   "Input");
                if (ImGui::IsItemHovered()) {
                    ImGui::SetTooltip("Drag into the graph to create a matching node.");
                }
                ImGui::PopID();
            }
                ImGui::EndTable();
            }
            ImGui::EndChild();

            ImGui::Spacing();
            DrawSidebarSectionHeader("Locals", "Author internal graph state here. Keep runtime edits in the entity inspector.");
            ImGui::SameLine();
            if (ImGui::SmallButton("+##AddLocal")) {
                localDraft.name = UniqueDraftName("New Variable", snapshot.localVariables);
                localDraft.type = 0;
                localDraft.defaultFloat = 0.0f;
                localDraft.defaultBool = false;
                localDraft.defaultInt = 0;
                localCreationOpen = true;
                selectedLocalIndex = -1;
            }
            if (localCreationOpen) {
                ImGui::BeginChild("LocalCreateRow", ImVec2(0.0f, 72.0f), true);
                char nameBuffer[128] = {0};
                std::strncpy(nameBuffer, localDraft.name.c_str(), sizeof(nameBuffer) - 1);
                ImGui::SetNextItemWidth(-1.0f);
                if (ImGui::InputTextWithHint("##NewLocalName", "Local variable name", nameBuffer, sizeof(nameBuffer))) {
                    localDraft.name = nameBuffer;
                }
                if (ImGui::BeginTable("LocalCreateTable", 4, ImGuiTableFlags_SizingStretchProp)) {
                    ImGui::TableSetupColumn("Type", ImGuiTableColumnFlags_WidthStretch, 0.28f);
                    ImGui::TableSetupColumn("Default", ImGuiTableColumnFlags_WidthStretch, 0.36f);
                    ImGui::TableSetupColumn("Create", ImGuiTableColumnFlags_WidthFixed, 60.0f);
                    ImGui::TableSetupColumn("Cancel", ImGuiTableColumnFlags_WidthFixed, 60.0f);
                    ImGui::TableNextRow();
                    ImGui::TableSetColumnIndex(0);
                    DrawTypeCombo("##NewLocalType", kLocalTypes, IM_ARRAYSIZE(kLocalTypes), localDraft.type);
                    ImGui::TableSetColumnIndex(1);
                    DrawVariableDefaultEditor("NewLocalDefault", localDraft.type, localDraft.defaultFloat, localDraft.defaultBool, localDraft.defaultInt);
                    ImGui::TableSetColumnIndex(2);
                    const bool canCreateLocal = !localDraft.name.empty();
                    if (!canCreateLocal) {
                        ImGui::BeginDisabled();
                    }
                    if (ImGui::Button("Create##Local", ImVec2(-1.0f, 0.0f))) {
                        if (MCEEditorAddAnimationGraphLocalVariable(context,
                                                                    state.activeGraphHandle.c_str(),
                                                                    localDraft.name.c_str(),
                                                                    localDraft.type,
                                                                    localDraft.defaultFloat,
                                                                    localDraft.defaultBool ? 1u : 0u,
                                                                    localDraft.defaultInt) != 0) {
                            localCreationOpen = false;
                            selectedLocalIndex = -1;
                        }
                    }
                    if (!canCreateLocal) {
                        ImGui::EndDisabled();
                    }
                    ImGui::TableSetColumnIndex(3);
                    if (ImGui::Button("Cancel##LocalCreate", ImVec2(-1.0f, 0.0f))) {
                        localCreationOpen = false;
                    }
                    ImGui::EndTable();
                }
                ImGui::EndChild();
            }
            ImGui::BeginChild("LocalsList", ImVec2(0.0f, 168.0f), true);
            if (ImGui::BeginTable("LocalsTable", 4, ImGuiTableFlags_SizingStretchProp | ImGuiTableFlags_RowBg | ImGuiTableFlags_BordersInnerV)) {
                ImGui::TableSetupColumn("Name", ImGuiTableColumnFlags_WidthStretch, 0.38f);
                ImGui::TableSetupColumn("Type", ImGuiTableColumnFlags_WidthStretch, 0.18f);
                ImGui::TableSetupColumn("Default", ImGuiTableColumnFlags_WidthStretch, 0.24f);
                ImGui::TableSetupColumn("Tools", ImGuiTableColumnFlags_WidthFixed, 96.0f);
            for (size_t i = 0; i < snapshot.localVariables.size(); ++i) {
                const auto &local = snapshot.localVariables[i];
                ImGui::PushID(static_cast<int>(i));
                ImGui::TableNextRow();
                ImGui::TableSetColumnIndex(0);
                char nameBuffer[128] = {0};
                std::strncpy(nameBuffer, local.name.c_str(), sizeof(nameBuffer) - 1);
                if (ImGui::InputText("##LocalName", nameBuffer, sizeof(nameBuffer))) {
                    MCEEditorUpdateAnimationGraphLocalVariable(context,
                                                               state.activeGraphHandle.c_str(),
                                                               static_cast<int32_t>(i),
                                                               nameBuffer,
                                                               local.type,
                                                               local.defaultFloat,
                                                               local.defaultBool ? 1u : 0u,
                                                               local.defaultInt);
                }
                if (ImGui::IsItemActivated()) {
                    selectedLocalIndex = static_cast<int32_t>(i);
                    selectedInputIndex = -1;
                }
                if (hasRuntimeDebugSnapshot && state.showRuntimeDebug) {
                    auto runtimeIt = std::find_if(runtimeDebugSnapshot.localVariables.begin(),
                                                  runtimeDebugSnapshot.localVariables.end(),
                                                  [&](const AnimationGraphRuntimeLocalVariableValueRecord &record) {
                        return record.name == local.name;
                    });
                    if (runtimeIt != runtimeDebugSnapshot.localVariables.end()) {
                        std::string valueLabel;
                        switch (runtimeIt->type) {
                            case 0: valueLabel = std::to_string(runtimeIt->floatValue); break;
                            case 1: valueLabel = runtimeIt->boolValue ? "true" : "false"; break;
                            case 2: valueLabel = std::to_string(runtimeIt->intValue); break;
                            default: valueLabel = ""; break;
                        }
                        if (!valueLabel.empty()) {
                            ImGui::TextDisabled("Runtime: %s", valueLabel.c_str());
                        }
                    }
                }
                ImGui::TableSetColumnIndex(1);
                int type = local.type;
                if (DrawTypeCombo("##LocalType", kLocalTypes, IM_ARRAYSIZE(kLocalTypes), type)) {
                    MCEEditorUpdateAnimationGraphLocalVariable(context,
                                                               state.activeGraphHandle.c_str(),
                                                               static_cast<int32_t>(i),
                                                               local.name.c_str(),
                                                               type,
                                                               local.defaultFloat,
                                                               local.defaultBool ? 1u : 0u,
                                                               local.defaultInt);
                    selectedLocalIndex = static_cast<int32_t>(i);
                    selectedInputIndex = -1;
                }
                ImGui::TableSetColumnIndex(2);
                float defaultFloat = local.defaultFloat;
                bool defaultBool = local.defaultBool;
                int defaultInt = local.defaultInt;
                DrawVariableDefaultEditor("LocalDefault", type, defaultFloat, defaultBool, defaultInt);
                if (ImGui::IsItemDeactivatedAfterEdit()) {
                    MCEEditorUpdateAnimationGraphLocalVariable(context,
                                                               state.activeGraphHandle.c_str(),
                                                               static_cast<int32_t>(i),
                                                               local.name.c_str(),
                                                               type,
                                                               defaultFloat,
                                                               defaultBool ? 1u : 0u,
                                                               defaultInt);
                    selectedLocalIndex = static_cast<int32_t>(i);
                    selectedInputIndex = -1;
                }
                ImGui::TableSetColumnIndex(3);
                if (ImGui::SmallButton("Delete##Local")) {
                    MCEEditorRemoveAnimationGraphLocalVariable(context, state.activeGraphHandle.c_str(), static_cast<int32_t>(i));
                    if (selectedLocalIndex == static_cast<int32_t>(i)) {
                        selectedLocalIndex = -1;
                    }
                    ImGui::PopID();
                    continue;
                }
                ImGui::SameLine();
                ImGui::Button("Drag##Local", ImVec2(-1.0f, 0.0f));
                BeginRowDragSource("MCE_ANIM_GRAPH_LOCAL_DEF",
                                   type,
                                   local.name,
                                   "Local");
                if (ImGui::IsItemHovered()) {
                    ImGui::SetTooltip("Drag into the graph to create a matching node.");
                }
                ImGui::PopID();
            }
                ImGui::EndTable();
            }
            ImGui::EndChild();
            ImGui::EndChild();
            DrawAnimationGraphInspector(context,
                                      snapshot,
                                      state,
                                      hasRuntimeDebugSnapshot,
                                      runtimeDebugSnapshot);
            ImGui::EndChild();
}
