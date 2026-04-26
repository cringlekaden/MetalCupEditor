#include "AnimationGraphBlendSpaceWorkspace.h"

#include "AnimationGraphBlendSpaceStateStore.h"

#include "../Widgets/UIWidgets.h"
#include "../../ImGui/imgui.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <string>

extern "C" int32_t MCEEditorGetAssetCount(void *context);
extern "C" uint32_t MCEEditorGetAssetAt(void *context, int32_t index,
                                        char *handleBuffer, int32_t handleBufferSize,
                                        int32_t *typeOut,
                                        char *pathBuffer, int32_t pathBufferSize,
                                        char *nameBuffer, int32_t nameBufferSize);
extern "C" uint32_t MCEEditorGetAssetDisplayName(void *context, const char *handle, char *buffer, int32_t bufferSize);
extern "C" uint32_t MCEEditorAddAnimationGraphBlend1DSample(void *context, const char *handle, const char *nodeId, const char *clipHandle, float threshold);
extern "C" uint32_t MCEEditorUpdateAnimationGraphBlend1DSample(void *context, const char *handle, const char *nodeId, int32_t index, const char *clipHandle, float threshold);
extern "C" uint32_t MCEEditorRemoveAnimationGraphBlend1DSample(void *context, const char *handle, const char *nodeId, int32_t index);
extern "C" uint32_t MCEEditorAddAnimationGraphBlend2DSample(void *context, const char *handle, const char *nodeId, const char *clipHandle, float x, float y);
extern "C" uint32_t MCEEditorUpdateAnimationGraphBlend2DSample(void *context, const char *handle, const char *nodeId, int32_t index, const char *clipHandle, float x, float y);
extern "C" uint32_t MCEEditorRemoveAnimationGraphBlend2DSample(void *context, const char *handle, const char *nodeId, int32_t index);

namespace {
constexpr int32_t kAssetTypeAnimationClip = 9;

std::string ShortHandleLabel(const std::string &handle) {
    if (handle.size() <= 12) { return handle; }
    return handle.substr(0, 8) + "..." + handle.substr(handle.size() - 4);
}

std::string DisplayNameForAssetHandle(void *context, const std::string &handle) {
    if (handle.empty()) { return "<None>"; }
    char nameBuffer[128] = {0};
    if (MCEEditorGetAssetDisplayName(context, handle.c_str(), nameBuffer, sizeof(nameBuffer)) != 0 && nameBuffer[0] != 0) {
        return nameBuffer;
    }
    return ShortHandleLabel(handle);
}

const AnimationGraphNodeRecord *FindNodeById(const AnimationGraphSnapshot &snapshot, const std::string &nodeId) {
    for (const auto &node : snapshot.nodes) {
        if (node.id == nodeId) { return &node; }
    }
    return nullptr;
}
}

void DrawAnimationGraphBlendSpaceWorkspace(void *context,
                                           const AnimationGraphSnapshot &snapshot,
                                           const AnimationGraphWorkspaceDescriptor &workspace,
                                           MCEPanelState::AnimationGraphPanelState &panelState,
                                           const AnimationGraphRuntimeDebugSnapshot *runtimeDebug) {
    const auto *node = FindNodeById(snapshot, workspace.nodeId);
    if (!node || !(node->type == 2 || node->type == 3)) {
        ImGui::TextDisabled("Blend workspace target is missing.");
        return;
    }

    AnimationGraphBlendSpaceWorkspaceState &workspaceState =
        AnimationGraphBlendSpaceStateStore::StateForWorkspace(panelState.activeGraphHandle, workspace);
    if (!workspaceState.initializedFromNode) {
        if (!node->blend1DParameterName.empty()) { workspaceState.xLabel = node->blend1DParameterName; }
        if (!node->blend2DParameterXName.empty()) { workspaceState.xLabel = node->blend2DParameterXName; }
        if (!node->blend2DParameterYName.empty()) { workspaceState.yLabel = node->blend2DParameterYName; }
        workspaceState.initializedFromNode = true;
    }

    workspaceState.xMin = std::min(workspaceState.xMin, workspaceState.xMax - 0.001f);
    workspaceState.xMax = std::max(workspaceState.xMax, workspaceState.xMin + 0.001f);
    workspaceState.yMin = std::min(workspaceState.yMin, workspaceState.yMax - 0.001f);
    workspaceState.yMax = std::max(workspaceState.yMax, workspaceState.yMin + 0.001f);

    const int32_t sampleCount = node->type == 2 ? static_cast<int32_t>(node->blend1DSamples.size()) : static_cast<int32_t>(node->blend2DSamples.size());
    if (workspaceState.selectedSampleIndex >= sampleCount) {
        workspaceState.selectedSampleIndex = -1;
    }

    const char *title = node->title.empty() ? "Blend Space" : node->title.c_str();
    ImGui::SeparatorText(title);
    ImGui::TextDisabled("%s Workspace", node->type == 2 ? "Blend 1D" : "Blend 2D");
    if (EditorUI::BeginPropertyTable("BlendSpaceAxisProps")) {
        EditorUI::PropertyLabel("X Label");
        char xLabelBuffer[64] = {0};
        strncpy(xLabelBuffer, workspaceState.xLabel.c_str(), sizeof(xLabelBuffer) - 1);
        ImGui::SetNextItemWidth(-1.0f);
        if (ImGui::InputText("##BlendXAxisLabel", xLabelBuffer, sizeof(xLabelBuffer))) {
            workspaceState.xLabel = xLabelBuffer;
        }

        EditorUI::PropertyLabel("X Range");
        float xRange[2] = {workspaceState.xMin, workspaceState.xMax};
        ImGui::SetNextItemWidth(-1.0f);
        if (ImGui::DragFloat2("##BlendXAxisRange", xRange, 0.01f, -10000.0f, 10000.0f, "%.3f")) {
            workspaceState.xMin = std::min(xRange[0], xRange[1] - 0.001f);
            workspaceState.xMax = std::max(xRange[1], workspaceState.xMin + 0.001f);
        }

        EditorUI::PropertyLabel("Y Label");
        char yLabelBuffer[64] = {0};
        strncpy(yLabelBuffer, workspaceState.yLabel.c_str(), sizeof(yLabelBuffer) - 1);
        ImGui::SetNextItemWidth(-1.0f);
        if (ImGui::InputText("##BlendYAxisLabel", yLabelBuffer, sizeof(yLabelBuffer))) {
            workspaceState.yLabel = yLabelBuffer;
        }

        EditorUI::PropertyLabel("Y Range");
        float yRange[2] = {workspaceState.yMin, workspaceState.yMax};
        ImGui::SetNextItemWidth(-1.0f);
        if (ImGui::DragFloat2("##BlendYAxisRange", yRange, 0.01f, -10000.0f, 10000.0f, "%.3f")) {
            workspaceState.yMin = std::min(yRange[0], yRange[1] - 0.001f);
            workspaceState.yMax = std::max(yRange[1], workspaceState.yMin + 0.001f);
        }
        EditorUI::EndPropertyTable();
    }
    ImGui::BeginChild("BlendSpaceCanvas", ImVec2(0.0f, ImGui::GetContentRegionAvail().y * 0.72f), true);
    ImDrawList *draw = ImGui::GetWindowDrawList();
    const ImVec2 origin = ImGui::GetCursorScreenPos();
    const ImVec2 avail = ImGui::GetContentRegionAvail();
    const float graphPadding = 22.0f;
    const ImVec2 minGraph(origin.x + graphPadding, origin.y + graphPadding);
    const ImVec2 maxGraph(origin.x + avail.x - graphPadding, origin.y + avail.y - graphPadding);
    auto graphToScreen = [&](float x, float y) -> ImVec2 {
        const float nx = (x - workspaceState.xMin) / std::max(workspaceState.xMax - workspaceState.xMin, 0.001f);
        const float ny = (y - workspaceState.yMin) / std::max(workspaceState.yMax - workspaceState.yMin, 0.001f);
        return ImVec2(minGraph.x + nx * (maxGraph.x - minGraph.x),
                      maxGraph.y - ny * (maxGraph.y - minGraph.y));
    };
    auto screenToGraph = [&](const ImVec2 &p) -> ImVec2 {
        const float nx = (p.x - minGraph.x) / std::max(maxGraph.x - minGraph.x, 0.001f);
        const float ny = (maxGraph.y - p.y) / std::max(maxGraph.y - minGraph.y, 0.001f);
        return ImVec2(workspaceState.xMin + nx * (workspaceState.xMax - workspaceState.xMin),
                      workspaceState.yMin + ny * (workspaceState.yMax - workspaceState.yMin));
    };
    draw->AddRectFilled(origin, ImVec2(origin.x + avail.x, origin.y + avail.y), IM_COL32(20, 22, 26, 255), 4.0f);
    draw->AddRect(origin, ImVec2(origin.x + avail.x, origin.y + avail.y), IM_COL32(64, 70, 78, 255), 4.0f);
    for (int i = 0; i <= 10; ++i) {
        const float t = static_cast<float>(i) / 10.0f;
        const float x = minGraph.x + t * (maxGraph.x - minGraph.x);
        const float y = minGraph.y + t * (maxGraph.y - minGraph.y);
        const ImU32 gridColor = (i == 5) ? IM_COL32(114, 124, 142, 190) : IM_COL32(72, 78, 90, 130);
        draw->AddLine(ImVec2(x, minGraph.y), ImVec2(x, maxGraph.y), gridColor, (i == 5) ? 1.6f : 1.0f);
        draw->AddLine(ImVec2(minGraph.x, y), ImVec2(maxGraph.x, y), gridColor, (i == 5) ? 1.6f : 1.0f);
    }
    draw->AddRect(minGraph, maxGraph, IM_COL32(100, 110, 126, 210), 2.0f, 0, 1.0f);
    draw->AddText(ImVec2(minGraph.x + 6.0f, minGraph.y + 6.0f), IM_COL32(188, 198, 216, 255), workspaceState.yLabel.c_str());
    draw->AddText(ImVec2(maxGraph.x - 64.0f, maxGraph.y - 18.0f), IM_COL32(188, 198, 216, 255), workspaceState.xLabel.c_str());
    if (ImGui::IsWindowHovered() && ImGui::IsMouseClicked(ImGuiMouseButton_Left)) {
        workspaceState.selectedSampleIndex = -1;
    }

    int32_t deleteIndex = -1;
    ImVec2 addPosition(0.0f, 0.0f);
    bool addRequested = false;
    auto firstAnimationClipHandle = [&]() -> std::string {
        const int32_t assetCount = MCEEditorGetAssetCount(context);
        for (int32_t assetIndex = 0; assetIndex < assetCount; ++assetIndex) {
            char handle[64] = {0};
            char path[512] = {0};
            char name[128] = {0};
            int32_t type = -1;
            if (MCEEditorGetAssetAt(context,
                                    assetIndex,
                                    handle,
                                    sizeof(handle),
                                    &type,
                                    path,
                                    sizeof(path),
                                    name,
                                    sizeof(name)) == 0) {
                continue;
            }
            if (type == kAssetTypeAnimationClip && handle[0] != 0) {
                return std::string(handle);
            }
        }
        return {};
    };

    if (node->type == 2) {
        for (int32_t i = 0; i < static_cast<int32_t>(node->blend1DSamples.size()); ++i) {
            const auto &sample = node->blend1DSamples[static_cast<size_t>(i)];
            const ImVec2 p = graphToScreen(sample.threshold, 0.0f);
            const bool selected = workspaceState.selectedSampleIndex == i;
            draw->AddCircleFilled(p, selected ? 7.0f : 5.0f, selected ? IM_COL32(255, 210, 118, 255) : IM_COL32(95, 184, 241, 255));
            const std::string sampleName = DisplayNameForAssetHandle(context, sample.clipHandle);
            draw->AddText(ImVec2(p.x + 6.0f, p.y - 6.0f), IM_COL32(220, 228, 240, 235), sampleName.c_str());

            ImGui::SetCursorScreenPos(ImVec2(p.x - 10.0f, p.y - 10.0f));
            ImGui::PushID(i);
            ImGui::InvisibleButton("Blend1DSamplePoint", ImVec2(20.0f, 20.0f));
            if (ImGui::IsItemClicked(ImGuiMouseButton_Left)) {
                workspaceState.selectedSampleIndex = i;
            }
            if (ImGui::IsItemActive() && ImGui::IsMouseDragging(ImGuiMouseButton_Left)) {
                const ImVec2 graphPos = screenToGraph(ImGui::GetMousePos());
                MCEEditorUpdateAnimationGraphBlend1DSample(context,
                                                           panelState.activeGraphHandle.c_str(),
                                                           node->id.c_str(),
                                                           i,
                                                           sample.clipHandle.c_str(),
                                                           graphPos.x);
            }
            if (ImGui::BeginPopupContextItem("Blend1DSampleContext")) {
                if (ImGui::MenuItem("Delete Sample")) {
                    deleteIndex = i;
                }
                ImGui::EndPopup();
            }
            ImGui::PopID();
        }
    } else {
        for (int32_t i = 0; i < static_cast<int32_t>(node->blend2DSamples.size()); ++i) {
            const auto &sample = node->blend2DSamples[static_cast<size_t>(i)];
            const ImVec2 p = graphToScreen(sample.position.x, sample.position.y);
            const bool selected = workspaceState.selectedSampleIndex == i;
            draw->AddCircleFilled(p, selected ? 7.0f : 5.0f, selected ? IM_COL32(255, 210, 118, 255) : IM_COL32(95, 184, 241, 255));
            const std::string sampleName = DisplayNameForAssetHandle(context, sample.clipHandle);
            draw->AddText(ImVec2(p.x + 6.0f, p.y - 6.0f), IM_COL32(220, 228, 240, 235), sampleName.c_str());

            ImGui::SetCursorScreenPos(ImVec2(p.x - 10.0f, p.y - 10.0f));
            ImGui::PushID(i);
            ImGui::InvisibleButton("Blend2DSamplePoint", ImVec2(20.0f, 20.0f));
            if (ImGui::IsItemClicked(ImGuiMouseButton_Left)) {
                workspaceState.selectedSampleIndex = i;
            }
            if (ImGui::IsItemActive() && ImGui::IsMouseDragging(ImGuiMouseButton_Left)) {
                const ImVec2 graphPos = screenToGraph(ImGui::GetMousePos());
                MCEEditorUpdateAnimationGraphBlend2DSample(context,
                                                           panelState.activeGraphHandle.c_str(),
                                                           node->id.c_str(),
                                                           i,
                                                           sample.clipHandle.c_str(),
                                                           graphPos.x,
                                                           graphPos.y);
            }
            if (ImGui::BeginPopupContextItem("Blend2DSampleContext")) {
                if (ImGui::MenuItem("Delete Sample")) {
                    deleteIndex = i;
                }
                ImGui::EndPopup();
            }
            ImGui::PopID();
        }
    }

    if (ImGui::BeginPopupContextWindow("BlendSpaceBackgroundContext", ImGuiPopupFlags_MouseButtonRight | ImGuiPopupFlags_NoOpenOverItems)) {
        if (ImGui::MenuItem("Add Sample Here")) {
            addRequested = true;
            addPosition = screenToGraph(ImGui::GetMousePos());
        }
        ImGui::EndPopup();
    }
    if (ImGui::BeginDragDropTarget()) {
        if (const ImGuiPayload *payload = ImGui::AcceptDragDropPayload("MCE_ASSET_ANIMATION_CLIP")) {
            const char *clipHandle = static_cast<const char *>(payload->Data);
            if (clipHandle && clipHandle[0] != 0) {
                const ImVec2 graphPos = screenToGraph(ImGui::GetMousePos());
                if (node->type == 2) {
                    MCEEditorAddAnimationGraphBlend1DSample(context,
                                                            panelState.activeGraphHandle.c_str(),
                                                            node->id.c_str(),
                                                            clipHandle,
                                                            graphPos.x);
                } else {
                    MCEEditorAddAnimationGraphBlend2DSample(context,
                                                            panelState.activeGraphHandle.c_str(),
                                                            node->id.c_str(),
                                                            clipHandle,
                                                            graphPos.x,
                                                            graphPos.y);
                }
            }
        }
        ImGui::EndDragDropTarget();
    }
    if (runtimeDebug && runtimeDebug->available) {
        float previewX = 0.0f;
        float previewY = 0.0f;
        bool hasPreview = false;
        if (node->type == 2) {
            if (!node->blend1DParameterName.empty()) {
                auto it = std::find_if(runtimeDebug->parameters.begin(),
                                       runtimeDebug->parameters.end(),
                                       [&](const AnimationGraphRuntimeParameterValueRecord &record) {
                    return record.name == node->blend1DParameterName && record.type == 0;
                });
                if (it != runtimeDebug->parameters.end()) {
                    previewX = it->floatValue;
                    hasPreview = true;
                }
            }
        } else {
            bool hasX = false;
            bool hasY = false;
            if (!node->blend2DParameterXName.empty()) {
                auto it = std::find_if(runtimeDebug->parameters.begin(),
                                       runtimeDebug->parameters.end(),
                                       [&](const AnimationGraphRuntimeParameterValueRecord &record) {
                    return record.name == node->blend2DParameterXName && record.type == 0;
                });
                if (it != runtimeDebug->parameters.end()) {
                    previewX = it->floatValue;
                    hasX = true;
                }
            }
            if (!node->blend2DParameterYName.empty()) {
                auto it = std::find_if(runtimeDebug->parameters.begin(),
                                       runtimeDebug->parameters.end(),
                                       [&](const AnimationGraphRuntimeParameterValueRecord &record) {
                    return record.name == node->blend2DParameterYName && record.type == 0;
                });
                if (it != runtimeDebug->parameters.end()) {
                    previewY = it->floatValue;
                    hasY = true;
                }
            }
            hasPreview = hasX && hasY;
        }
        if (hasPreview) {
            const ImVec2 previewPoint = graphToScreen(previewX, previewY);
            draw->AddCircle(previewPoint, 10.0f, IM_COL32(92, 248, 152, 230), 20, 2.0f);
            draw->AddCircleFilled(previewPoint, 4.0f, IM_COL32(92, 248, 152, 255));
            draw->AddText(ImVec2(previewPoint.x + 9.0f, previewPoint.y - 14.0f), IM_COL32(92, 248, 152, 240), "Preview");
        }
    }
    ImGui::EndChild();

    if (deleteIndex >= 0) {
        if (node->type == 2) {
            MCEEditorRemoveAnimationGraphBlend1DSample(context,
                                                       panelState.activeGraphHandle.c_str(),
                                                       node->id.c_str(),
                                                       deleteIndex);
        } else {
            MCEEditorRemoveAnimationGraphBlend2DSample(context,
                                                       panelState.activeGraphHandle.c_str(),
                                                       node->id.c_str(),
                                                       deleteIndex);
        }
        workspaceState.selectedSampleIndex = -1;
    }
    if (addRequested) {
        const std::string clipHandle = firstAnimationClipHandle();
        if (!clipHandle.empty()) {
            if (node->type == 2) {
                MCEEditorAddAnimationGraphBlend1DSample(context,
                                                        panelState.activeGraphHandle.c_str(),
                                                        node->id.c_str(),
                                                        clipHandle.c_str(),
                                                        addPosition.x);
            } else {
                MCEEditorAddAnimationGraphBlend2DSample(context,
                                                        panelState.activeGraphHandle.c_str(),
                                                        node->id.c_str(),
                                                        clipHandle.c_str(),
                                                        addPosition.x,
                                                        addPosition.y);
            }
        }
    }

    if (workspaceState.selectedSampleIndex >= 0 && workspaceState.selectedSampleIndex < sampleCount) {
        ImGui::SeparatorText("Sample");
        if (node->type == 2) {
            const auto &sample = node->blend1DSamples[static_cast<size_t>(workspaceState.selectedSampleIndex)];
            ImGui::Text("Clip: %s", DisplayNameForAssetHandle(context, sample.clipHandle).c_str());
            ImGui::Text("X: %.3f", sample.threshold);
            ImGui::Text("Y: %.3f", 0.0f);
        } else {
            const auto &sample = node->blend2DSamples[static_cast<size_t>(workspaceState.selectedSampleIndex)];
            ImGui::Text("Clip: %s", DisplayNameForAssetHandle(context, sample.clipHandle).c_str());
            ImGui::Text("X: %.3f", sample.position.x);
            ImGui::Text("Y: %.3f", sample.position.y);
        }
    } else {
        ImGui::TextDisabled("Right click to add sample. Drag clip assets onto the space to create samples.");
    }
}

