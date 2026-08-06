#include "AnimationGraphBlendSpaceWorkspace.h"

#include "AnimationGraphInlineWidgets.h"
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
void DrawBlendWorkspaceBanner(const char *title, const char *subtitle) {
    ImDrawList *draw = ImGui::GetWindowDrawList();
    const ImVec2 start = ImGui::GetCursorScreenPos();
    const float width = ImGui::GetContentRegionAvail().x;
    const ImVec2 size(width, 48.0f);
    draw->AddRectFilled(start, ImVec2(start.x + size.x, start.y + size.y), IM_COL32(24, 27, 32, 255), 8.0f);
    draw->AddRect(start, ImVec2(start.x + size.x, start.y + size.y), IM_COL32(56, 63, 74, 255), 8.0f, 0, 1.0f);
    draw->AddText(ImVec2(start.x + 14.0f, start.y + 8.0f), IM_COL32(226, 232, 240, 245), title);
    draw->AddText(ImVec2(start.x + 14.0f, start.y + 26.0f), IM_COL32(148, 158, 174, 230), subtitle);
    ImGui::Dummy(size);
}

constexpr int32_t kAssetTypeAnimationClip = 9;

struct AnimationClipOption {
    std::string handle;
    std::string label;
};

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

std::vector<AnimationClipOption> CollectAnimationClipOptions(void *context) {
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
        if (type != kAssetTypeAnimationClip || handle[0] == 0) {
            continue;
        }
        options.push_back({handle, name[0] != 0 ? name : handle});
    }
    std::sort(options.begin(), options.end(), [](const AnimationClipOption &a, const AnimationClipOption &b) {
        return a.label < b.label;
    });
    return options;
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
    const int32_t sampleCount = node->type == 2 ? static_cast<int32_t>(node->blend1DSamples.size()) : static_cast<int32_t>(node->blend2DSamples.size());
    if (workspaceState.selectedSampleIndex >= sampleCount) {
        workspaceState.selectedSampleIndex = -1;
    }
    const std::vector<AnimationClipOption> clipOptions = CollectAnimationClipOptions(context);
    std::vector<AnimationGraphInlineWidgets::ClipOption> sharedClipOptions;
    sharedClipOptions.reserve(clipOptions.size());
    for (const auto &option : clipOptions) {
        sharedClipOptions.push_back({option.handle, option.label});
    }

    const char *title = node->title.empty() ? "Blend Space" : node->title.c_str();
    DrawBlendWorkspaceBanner(title,
                             node->type == 2
                                ? "Place and edit samples directly on the graph."
                                : "Place, drag, and tune samples directly on the graph.");
    auto firstAnimationClipHandle = [&]() -> std::string {
        for (const auto &option : clipOptions) {
            if (!option.handle.empty()) {
                return option.handle;
            }
        }
        return {};
    };
    auto addSampleAt = [&](const ImVec2 &graphPos, const std::string &clipHandle) {
        if (clipHandle.empty()) { return; }
        if (node->type == 2) {
            MCEEditorAddAnimationGraphBlend1DSample(context,
                                                    panelState.activeGraphHandle.c_str(),
                                                    node->id.c_str(),
                                                    clipHandle.c_str(),
                                                    graphPos.x);
        } else {
            MCEEditorAddAnimationGraphBlend2DSample(context,
                                                    panelState.activeGraphHandle.c_str(),
                                                    node->id.c_str(),
                                                    clipHandle.c_str(),
                                                    graphPos.x,
                                                    graphPos.y);
        }
    };

    ImGui::BeginChild("BlendSpaceCanvas", ImVec2(0.0f, ImGui::GetContentRegionAvail().y * 0.72f), true);
    ImDrawList *draw = ImGui::GetWindowDrawList();
    const ImVec2 origin = ImGui::GetCursorScreenPos();
    const ImVec2 avail = ImGui::GetContentRegionAvail();
    const float graphPadding = 22.0f;
    const ImVec2 minGraph(origin.x + graphPadding, origin.y + graphPadding);
    const ImVec2 maxGraph(origin.x + avail.x - graphPadding, origin.y + avail.y - graphPadding);
    std::string xLabel = node->type == 2
        ? (node->blend1DParameterName.empty() ? "Parameter" : node->blend1DParameterName)
        : (node->blend2DParameterXName.empty() ? "X" : node->blend2DParameterXName);
    std::string yLabel = node->blend2DParameterYName.empty() ? "Y" : node->blend2DParameterYName;
    float xMin = -1.0f;
    float xMax = 1.0f;
    float yMin = -1.0f;
    float yMax = 1.0f;
    auto expandAxis = [](float value, float &minValue, float &maxValue) {
        minValue = std::min(minValue, value);
        maxValue = std::max(maxValue, value);
    };
    if (node->type == 2) {
        for (const auto &sample : node->blend1DSamples) {
            expandAxis(sample.threshold, xMin, xMax);
        }
    } else {
        for (const auto &sample : node->blend2DSamples) {
            expandAxis(sample.position.x, xMin, xMax);
            expandAxis(sample.position.y, yMin, yMax);
        }
    }
    if (runtimeDebug && runtimeDebug->available) {
        if (node->type == 2) {
            if (!node->blend1DParameterName.empty()) {
                auto it = std::find_if(runtimeDebug->parameters.begin(),
                                       runtimeDebug->parameters.end(),
                                       [&](const AnimationGraphRuntimeParameterValueRecord &record) {
                    return record.name == node->blend1DParameterName && record.type == 0;
                });
                if (it != runtimeDebug->parameters.end()) {
                    expandAxis(it->floatValue, xMin, xMax);
                }
            }
        } else {
            if (!node->blend2DParameterXName.empty()) {
                auto it = std::find_if(runtimeDebug->parameters.begin(),
                                       runtimeDebug->parameters.end(),
                                       [&](const AnimationGraphRuntimeParameterValueRecord &record) {
                    return record.name == node->blend2DParameterXName && record.type == 0;
                });
                if (it != runtimeDebug->parameters.end()) {
                    expandAxis(it->floatValue, xMin, xMax);
                }
            }
            if (!node->blend2DParameterYName.empty()) {
                auto it = std::find_if(runtimeDebug->parameters.begin(),
                                       runtimeDebug->parameters.end(),
                                       [&](const AnimationGraphRuntimeParameterValueRecord &record) {
                    return record.name == node->blend2DParameterYName && record.type == 0;
                });
                if (it != runtimeDebug->parameters.end()) {
                    expandAxis(it->floatValue, yMin, yMax);
                }
            }
        }
    }
    const float xPadding = std::max(0.35f, (xMax - xMin) * 0.2f);
    const float yPadding = std::max(0.35f, (yMax - yMin) * 0.2f);
    xMin -= xPadding;
    xMax += xPadding;
    yMin -= yPadding;
    yMax += yPadding;
    auto graphToScreen = [&](float x, float y) -> ImVec2 {
        const float nx = (x - xMin) / std::max(xMax - xMin, 0.001f);
        const float ny = (y - yMin) / std::max(yMax - yMin, 0.001f);
        return ImVec2(minGraph.x + nx * (maxGraph.x - minGraph.x),
                      maxGraph.y - ny * (maxGraph.y - minGraph.y));
    };
    auto screenToGraph = [&](const ImVec2 &p) -> ImVec2 {
        const float nx = (p.x - minGraph.x) / std::max(maxGraph.x - minGraph.x, 0.001f);
        const float ny = (maxGraph.y - p.y) / std::max(maxGraph.y - minGraph.y, 0.001f);
        return ImVec2(xMin + nx * (xMax - xMin),
                      yMin + ny * (yMax - yMin));
    };
    draw->AddRectFilled(origin, ImVec2(origin.x + avail.x, origin.y + avail.y), IM_COL32(22, 25, 30, 255), 8.0f);
    draw->AddRect(origin, ImVec2(origin.x + avail.x, origin.y + avail.y), IM_COL32(60, 68, 80, 255), 8.0f);
    for (int i = 0; i <= 10; ++i) {
        const float t = static_cast<float>(i) / 10.0f;
        const float x = minGraph.x + t * (maxGraph.x - minGraph.x);
        const float y = minGraph.y + t * (maxGraph.y - minGraph.y);
        const ImU32 gridColor = (i == 5) ? IM_COL32(114, 124, 142, 190) : IM_COL32(72, 78, 90, 130);
        draw->AddLine(ImVec2(x, minGraph.y), ImVec2(x, maxGraph.y), gridColor, (i == 5) ? 1.6f : 1.0f);
        draw->AddLine(ImVec2(minGraph.x, y), ImVec2(maxGraph.x, y), gridColor, (i == 5) ? 1.6f : 1.0f);
    }
    draw->AddRect(minGraph, maxGraph, IM_COL32(100, 110, 126, 210), 2.0f, 0, 1.0f);
    draw->AddText(ImVec2(minGraph.x + 6.0f, minGraph.y + 6.0f), IM_COL32(188, 198, 216, 255), yLabel.c_str());
    draw->AddText(ImVec2(maxGraph.x - 64.0f, maxGraph.y - 18.0f), IM_COL32(188, 198, 216, 255), xLabel.c_str());
    const char *canvasHint = workspaceState.selectedSampleIndex >= 0
        ? "Drag the point or edit the selected sample card."
        : "Drop a clip or right-click to add a sample.";
    draw->AddText(ImVec2(minGraph.x + 6.0f, maxGraph.y - 18.0f), IM_COL32(152, 164, 182, 220), canvasHint);
    if (ImGui::IsWindowHovered() && ImGui::IsMouseClicked(ImGuiMouseButton_Left)) {
        workspaceState.selectedSampleIndex = -1;
    }

    int32_t deleteIndex = -1;
    ImVec2 addPosition(0.0f, 0.0f);
    bool addRequested = false;
    if (node->type == 2) {
        for (int32_t i = 0; i < static_cast<int32_t>(node->blend1DSamples.size()); ++i) {
            const auto &sample = node->blend1DSamples[static_cast<size_t>(i)];
            const ImVec2 p = graphToScreen(sample.threshold, 0.0f);
            const bool selected = workspaceState.selectedSampleIndex == i;
            draw->AddCircleFilled(p, selected ? 7.5f : 5.5f, selected ? IM_COL32(255, 210, 118, 255) : IM_COL32(95, 184, 241, 255));
            if (selected) {
                draw->AddCircle(p, 12.0f, IM_COL32(255, 210, 118, 105), 24, 2.0f);
            }
            const std::string sampleName = DisplayNameForAssetHandle(context, sample.clipHandle);
            draw->AddText(ImVec2(p.x + 6.0f, p.y - 6.0f), IM_COL32(220, 228, 240, 235), sampleName.c_str());

            ImGui::SetCursorScreenPos(ImVec2(p.x - 10.0f, p.y - 10.0f));
            ImGui::PushID(i);
            ImGui::InvisibleButton("Blend1DSamplePoint", ImVec2(20.0f, 20.0f));
            if (ImGui::IsItemClicked(ImGuiMouseButton_Left)) {
                workspaceState.selectedSampleIndex = i;
            }
            if (ImGui::BeginDragDropTarget()) {
                if (const ImGuiPayload *payload = ImGui::AcceptDragDropPayload("MCE_ASSET_ANIMATION_CLIP")) {
                    const char *clipHandle = static_cast<const char *>(payload->Data);
                    if (clipHandle && clipHandle[0] != 0) {
                        MCEEditorUpdateAnimationGraphBlend1DSample(context,
                                                                   panelState.activeGraphHandle.c_str(),
                                                                   node->id.c_str(),
                                                                   i,
                                                                   clipHandle,
                                                                   sample.threshold);
                        workspaceState.selectedSampleIndex = i;
                    }
                }
                ImGui::EndDragDropTarget();
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
            draw->AddCircleFilled(p, selected ? 7.5f : 5.5f, selected ? IM_COL32(255, 210, 118, 255) : IM_COL32(95, 184, 241, 255));
            if (selected) {
                draw->AddCircle(p, 12.0f, IM_COL32(255, 210, 118, 105), 24, 2.0f);
            }
            const std::string sampleName = DisplayNameForAssetHandle(context, sample.clipHandle);
            draw->AddText(ImVec2(p.x + 6.0f, p.y - 6.0f), IM_COL32(220, 228, 240, 235), sampleName.c_str());

            ImGui::SetCursorScreenPos(ImVec2(p.x - 10.0f, p.y - 10.0f));
            ImGui::PushID(i);
            ImGui::InvisibleButton("Blend2DSamplePoint", ImVec2(20.0f, 20.0f));
            if (ImGui::IsItemClicked(ImGuiMouseButton_Left)) {
                workspaceState.selectedSampleIndex = i;
            }
            if (ImGui::BeginDragDropTarget()) {
                if (const ImGuiPayload *payload = ImGui::AcceptDragDropPayload("MCE_ASSET_ANIMATION_CLIP")) {
                    const char *clipHandle = static_cast<const char *>(payload->Data);
                    if (clipHandle && clipHandle[0] != 0) {
                        MCEEditorUpdateAnimationGraphBlend2DSample(context,
                                                                   panelState.activeGraphHandle.c_str(),
                                                                   node->id.c_str(),
                                                                   i,
                                                                   clipHandle,
                                                                   sample.position.x,
                                                                   sample.position.y);
                        workspaceState.selectedSampleIndex = i;
                    }
                }
                ImGui::EndDragDropTarget();
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
            draw->AddText(ImVec2(previewPoint.x + 9.0f, previewPoint.y - 14.0f), IM_COL32(92, 248, 152, 220), "Live");
        }
    }

    if (workspaceState.selectedSampleIndex >= 0 && workspaceState.selectedSampleIndex < sampleCount) {
        const bool isBlend1D = node->type == 2;
        const int32_t selectedSampleIndex = workspaceState.selectedSampleIndex;
        const std::string clipHandle = isBlend1D
            ? node->blend1DSamples[static_cast<size_t>(selectedSampleIndex)].clipHandle
            : node->blend2DSamples[static_cast<size_t>(selectedSampleIndex)].clipHandle;
        const ImVec2 samplePos = isBlend1D
            ? graphToScreen(node->blend1DSamples[static_cast<size_t>(selectedSampleIndex)].threshold, 0.0f)
            : graphToScreen(node->blend2DSamples[static_cast<size_t>(selectedSampleIndex)].position.x,
                            node->blend2DSamples[static_cast<size_t>(selectedSampleIndex)].position.y);
        const float overlayWidth = std::min(320.0f, std::max(232.0f, avail.x * 0.42f));
        const float overlayHeight = isBlend1D ? 184.0f : 206.0f;
        ImVec2 overlayMin(samplePos.x + 18.0f, samplePos.y - overlayHeight - 18.0f);
        overlayMin.x = std::clamp(overlayMin.x, origin.x + 10.0f, origin.x + avail.x - overlayWidth - 10.0f);
        overlayMin.y = std::clamp(overlayMin.y, origin.y + 10.0f, origin.y + avail.y - overlayHeight - 10.0f);
        const ImVec2 overlayMax(overlayMin.x + overlayWidth, overlayMin.y + overlayHeight);
        draw->AddLine(samplePos,
                      ImVec2(overlayMin.x, overlayMin.y + 18.0f),
                      IM_COL32(100, 110, 126, 210),
                      1.2f);
        draw->AddRectFilled(overlayMin, overlayMax, IM_COL32(28, 32, 38, 242), 8.0f);
        draw->AddRect(overlayMin, overlayMax, IM_COL32(100, 110, 126, 220), 8.0f, 0, 1.1f);
        const std::string sampleTitle = std::string("Sample ").append(std::to_string(selectedSampleIndex + 1));
        draw->AddText(ImVec2(overlayMin.x + 10.0f, overlayMin.y + 8.0f), IM_COL32(224, 232, 242, 245), sampleTitle.c_str());
        draw->AddText(ImVec2(overlayMin.x + 10.0f, overlayMin.y + 28.0f), IM_COL32(152, 164, 182, 235), "Edit the selected point here.");
        draw->AddText(ImVec2(overlayMin.x + 10.0f, overlayMin.y + 44.0f), IM_COL32(188, 198, 216, 240), "Clip");

        auto updateSelectedSampleClip = [&](const std::string &updatedClipHandle) {
            if (isBlend1D) {
                const auto &sample = node->blend1DSamples[static_cast<size_t>(selectedSampleIndex)];
                MCEEditorUpdateAnimationGraphBlend1DSample(context,
                                                           panelState.activeGraphHandle.c_str(),
                                                           node->id.c_str(),
                                                           selectedSampleIndex,
                                                           updatedClipHandle.c_str(),
                                                           sample.threshold);
            } else {
                const auto &sample = node->blend2DSamples[static_cast<size_t>(selectedSampleIndex)];
                MCEEditorUpdateAnimationGraphBlend2DSample(context,
                                                           panelState.activeGraphHandle.c_str(),
                                                           node->id.c_str(),
                                                           selectedSampleIndex,
                                                           updatedClipHandle.c_str(),
                                                           sample.position.x,
                                                           sample.position.y);
            }
        };

        ImGui::SetCursorScreenPos(ImVec2(overlayMin.x + 10.0f, overlayMin.y + 60.0f));
        std::string updatedClipHandle = clipHandle;
        const std::string popupId = std::string("BlendSampleClipPopup##").append(node->id).append("|").append(std::to_string(selectedSampleIndex));
        const std::string fieldId = std::string("BlendSampleClipField##").append(node->id).append("|").append(std::to_string(selectedSampleIndex));
        if (AnimationGraphInlineWidgets::DrawClipField(fieldId.c_str(),
                                                       popupId.c_str(),
                                                       updatedClipHandle,
                                                       DisplayNameForAssetHandle(context, clipHandle),
                                                       sharedClipOptions)) {
            updateSelectedSampleClip(updatedClipHandle);
        }

        ImGui::SetCursorScreenPos(ImVec2(overlayMin.x + 10.0f, overlayMin.y + 92.0f));
        ImGui::InvisibleButton("##BlendSampleCardDropTarget", ImVec2(overlayWidth - 20.0f, 18.0f));
        if (ImGui::BeginDragDropTarget()) {
            if (const ImGuiPayload *payload = ImGui::AcceptDragDropPayload("MCE_ASSET_ANIMATION_CLIP")) {
                const char *droppedClipHandle = static_cast<const char *>(payload->Data);
                if (droppedClipHandle && droppedClipHandle[0] != 0) {
                    updateSelectedSampleClip(droppedClipHandle);
                }
            }
            ImGui::EndDragDropTarget();
        }
        draw->AddText(ImVec2(overlayMin.x + 10.0f, overlayMin.y + 92.0f), IM_COL32(152, 164, 182, 220), "Drop a clip on this card to replace it.");

        ImGui::SetCursorScreenPos(ImVec2(overlayMin.x + 10.0f, overlayMin.y + 118.0f));
        draw->AddText(ImVec2(overlayMin.x + 10.0f, overlayMin.y + 104.0f), IM_COL32(188, 198, 216, 240), "Position");
        if (isBlend1D) {
            const auto &sample = node->blend1DSamples[static_cast<size_t>(selectedSampleIndex)];
            float threshold = sample.threshold;
            if (AnimationGraphInlineWidgets::DrawFloatField("##BlendSampleThreshold",
                                                            xLabel.c_str(),
                                                            threshold,
                                                            0.01f,
                                                            xMin,
                                                            xMax,
                                                            "%.3f",
                                                            true,
                                                            false,
                                                            overlayWidth - 72.0f)) {
                MCEEditorUpdateAnimationGraphBlend1DSample(context,
                                                           panelState.activeGraphHandle.c_str(),
                                                           node->id.c_str(),
                                                           selectedSampleIndex,
                                                           sample.clipHandle.c_str(),
                                                           threshold);
            }
        } else {
            const auto &sample = node->blend2DSamples[static_cast<size_t>(selectedSampleIndex)];
            float sampleX = sample.position.x;
            float sampleY = sample.position.y;
            if (AnimationGraphInlineWidgets::DrawFloatField("##BlendSampleX",
                                                            xLabel.c_str(),
                                                            sampleX,
                                                            0.01f,
                                                            xMin,
                                                            xMax,
                                                            "%.3f",
                                                            true,
                                                            false,
                                                            overlayWidth - 72.0f)) {
                MCEEditorUpdateAnimationGraphBlend2DSample(context,
                                                           panelState.activeGraphHandle.c_str(),
                                                           node->id.c_str(),
                                                           selectedSampleIndex,
                                                           sample.clipHandle.c_str(),
                                                           sampleX,
                                                           sample.position.y);
            }
            ImGui::SetCursorScreenPos(ImVec2(overlayMin.x + 10.0f, overlayMin.y + 148.0f));
            if (AnimationGraphInlineWidgets::DrawFloatField("##BlendSampleY",
                                                            yLabel.c_str(),
                                                            sampleY,
                                                            0.01f,
                                                            yMin,
                                                            yMax,
                                                            "%.3f",
                                                            true,
                                                            false,
                                                            overlayWidth - 72.0f)) {
                MCEEditorUpdateAnimationGraphBlend2DSample(context,
                                                           panelState.activeGraphHandle.c_str(),
                                                           node->id.c_str(),
                                                           selectedSampleIndex,
                                                           sample.clipHandle.c_str(),
                                                           sample.position.x,
                                                           sampleY);
            }
        }

        ImGui::SetCursorScreenPos(ImVec2(overlayMin.x + 10.0f, overlayMax.y - 32.0f));
        if (ImGui::SmallButton("Done")) {
            workspaceState.selectedSampleIndex = -1;
        }
        ImGui::SetCursorScreenPos(ImVec2(overlayMax.x - 104.0f, overlayMax.y - 32.0f));
        if (ImGui::SmallButton("Delete Sample")) {
            deleteIndex = selectedSampleIndex;
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
        addSampleAt(addPosition, firstAnimationClipHandle());
    }
}
