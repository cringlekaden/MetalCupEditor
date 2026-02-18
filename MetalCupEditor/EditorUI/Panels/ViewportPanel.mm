// ViewportPanel.mm
// Defines the ImGui Viewport panel rendering and interaction logic.
// Created by Kaden Cringle.

#import "ViewportPanel.h"

#import "../../ImGui/imgui.h"
#import "../../ImGuizmo/ImGuizmo.h"
#import "PanelState.h"
#import "../Widgets/UIWidgets.h"
#include <algorithm>
#include <cmath>

extern "C" void MCEScenePlay(MCE_CTX);
extern "C" void MCESceneStop(MCE_CTX);
extern "C" void MCEScenePause(MCE_CTX);
extern "C" void MCESceneResume(MCE_CTX);
extern "C" uint32_t MCESceneIsPlaying(MCE_CTX);
extern "C" uint32_t MCESceneIsPaused(MCE_CTX);
extern "C" int32_t MCEEditorCreateMeshEntityFromHandle(MCE_CTX,  const char *meshHandle, char *outId, int32_t outIdSize);
extern "C" int32_t MCEEditorInstantiatePrefabFromHandle(MCE_CTX,  const char *prefabHandle, char *outId, int32_t outIdSize);
extern "C" uint32_t MCEEditorOpenSceneAtPath(MCE_CTX,  const char *relativePath);
extern "C" int32_t MCEEditorCreateCameraFromView(MCE_CTX,  char *outId, int32_t outIdSize);
extern "C" uint32_t MCEEditorGetTransform(MCE_CTX,  const char *entityId,
                                          float *px, float *py, float *pz,
                                          float *rx, float *ry, float *rz,
                                          float *sx, float *sy, float *sz);
extern "C" void MCEEditorSetTransformNoLog(MCE_CTX,  const char *entityId,
                                           float px, float py, float pz,
                                           float rx, float ry, float rz,
                                           float sx, float sy, float sz);
extern "C" uint32_t MCEEditorGetEditorCameraMatrices(MCE_CTX,  float *viewOut, float *projectionOut);
extern "C" void MCEImGuiSetGizmoCapture(MCE_CTX,  uint32_t wantsMouse, uint32_t wantsKeyboard);
extern "C" uint32_t MCEEditorSetTransformFromMatrix(MCE_CTX,  const char *entityId, const float *matrix);
extern "C" uint32_t MCEEditorGetModelMatrix(MCE_CTX,  const char *entityId, float *matrixOut);
extern "C" void *MCEContextGetUIPanelState(MCE_CTX);

namespace {
    using MCEPanelState::GizmoOperation;
    using MCEPanelState::ViewportState;

    ViewportState &GetViewportState(void *context) {
        auto *state = static_cast<MCEPanelState::EditorUIPanelState *>(MCEContextGetUIPanelState(context));
        return state->viewport;
    }

    ImGuizmo::OPERATION ToImGuizmoOperation(GizmoOperation op) {
        switch (op) {
        case GizmoOperation::Translate:
            return ImGuizmo::TRANSLATE;
        case GizmoOperation::Rotate:
            return ImGuizmo::ROTATE;
        case GizmoOperation::Scale:
            return ImGuizmo::SCALE;
        case GizmoOperation::None:
        default:
            return ImGuizmo::TRANSLATE;
        }
    }

    bool GetModelMatrix(void *context, const char *entityId, float *outMatrix) {
        if (!entityId || entityId[0] == 0 || !outMatrix) {
            return false;
        }
        if (MCEEditorGetModelMatrix(context, entityId, outMatrix) == 0) {
            return false;
        }
        return true;
    }



    bool ToolbarToggleButton(const char *label, bool active) {
        ImGuiStyle& style = ImGui::GetStyle();
        if (active) {
            const ImVec4 activeColor = style.Colors[ImGuiCol_ButtonActive];
            ImGui::PushStyleColor(ImGuiCol_Button, activeColor);
            ImGui::PushStyleColor(ImGuiCol_ButtonHovered, activeColor);
            ImGui::PushStyleColor(ImGuiCol_ButtonActive, activeColor);
        }
        bool pressed = EditorUI::ToolbarButton(label, true);
        if (active) {
            ImGui::PopStyleColor(3);
        }
        return pressed;
    }

    bool DrawGizmoToolbar(ViewportState &state, const ImVec2& imageMin, const ImVec2& imageMax) {
        const float toolbarPadding = 10.0f;
        const ImVec2 padding = ImGui::GetStyle().FramePadding;
        const float spacing = ImGui::GetStyle().ItemSpacing.x;
        const char *labels[] = {"Select", "Move", "Rotate", "Scale", "Local", "World"};

        float widths[6];
        float maxLabelHeight = 0.0f;
        for (int i = 0; i < 6; ++i) {
            ImVec2 labelSize = ImGui::CalcTextSize(labels[i]);
            widths[i] = labelSize.x + padding.x * 2.0f;
            maxLabelHeight = std::max(maxLabelHeight, labelSize.y);
        }
        float toolbarWidth = widths[0] + widths[1] + widths[2] + widths[3] + widths[4] + widths[5] + spacing * 5.0f;
        float toolbarHeight = maxLabelHeight + padding.y * 2.0f;

        ImGui::SetCursorScreenPos(ImVec2(imageMin.x + toolbarPadding, imageMin.y + toolbarPadding));
        ImGui::BeginChild("ViewportGizmoToolbar", ImVec2(toolbarWidth, toolbarHeight), false,
                          ImGuiWindowFlags_NoScrollbar | ImGuiWindowFlags_NoScrollWithMouse | ImGuiWindowFlags_NoBackground);
        bool hovered = false;
        if (ToolbarToggleButton("Select", state.operation == GizmoOperation::None)) {
            state.operation = GizmoOperation::None;
        }
        hovered = hovered || ImGui::IsItemHovered() || ImGui::IsItemActive();
        ImGui::SameLine();
        if (ToolbarToggleButton("Move", state.operation == GizmoOperation::Translate)) {
            state.operation = GizmoOperation::Translate;
        }
        hovered = hovered || ImGui::IsItemHovered() || ImGui::IsItemActive();
        ImGui::SameLine();
        if (ToolbarToggleButton("Rotate", state.operation == GizmoOperation::Rotate)) {
            state.operation = GizmoOperation::Rotate;
        }
        hovered = hovered || ImGui::IsItemHovered() || ImGui::IsItemActive();
        ImGui::SameLine();
        if (ToolbarToggleButton("Scale", state.operation == GizmoOperation::Scale)) {
            state.operation = GizmoOperation::Scale;
        }
        hovered = hovered || ImGui::IsItemHovered() || ImGui::IsItemActive();
        ImGui::SameLine();
        if (ToolbarToggleButton("Local", state.mode == 0)) {
            state.mode = 0;
        }
        hovered = hovered || ImGui::IsItemHovered() || ImGui::IsItemActive();
        ImGui::SameLine();
        if (ToolbarToggleButton("World", state.mode == 1)) {
            state.mode = 1;
        }
        hovered = hovered || ImGui::IsItemHovered() || ImGui::IsItemActive();
        ImGui::EndChild();
        return hovered;
    }
}

void ImGuiViewportPanelDraw(void *context,
                            id<MTLTexture> _Nullable sceneTexture,
                            id<MTLTexture> _Nullable previewTexture,
                            const char *selectedEntityId,
                            bool *hovered,
                            bool *focused,
                            bool *uiHovered,
                            CGSize *contentSize,
                            CGPoint *contentOrigin,
                            CGPoint *imageOrigin,
                            CGSize *imageSize) {
    ViewportState &state = GetViewportState(context);
    if (!EditorUI::BeginPanel("Viewport")) {
        EditorUI::EndPanel();
        return;
    }

    ImVec2 avail = ImGui::GetContentRegionAvail();
    if (contentSize) {
        *contentSize = CGSizeMake(avail.x, avail.y);
    }
    const bool isHovered = ImGui::IsWindowHovered(ImGuiHoveredFlags_RootAndChildWindows);
    const bool isFocused = ImGui::IsWindowFocused(ImGuiFocusedFlags_RootAndChildWindows);
    if (hovered) {
        *hovered = isHovered;
    }
    if (focused) {
        *focused = isFocused;
    }
    bool viewportUIHovered = false;

    ImGuizmo::BeginFrame();

    ImVec2 contentMin = ImGui::GetWindowContentRegionMin();
    ImVec2 windowPos = ImGui::GetWindowPos();
    if (contentOrigin) {
        *contentOrigin = CGPointMake(windowPos.x + contentMin.x, windowPos.y + contentMin.y);
    }

    ImVec2 contentMax = ImGui::GetWindowContentRegionMax();
    ImVec2 contentSizeVec = ImVec2(contentMax.x - contentMin.x, contentMax.y - contentMin.y);

    if (sceneTexture && contentSizeVec.x > 1 && contentSizeVec.y > 1) {
        ImGui::Image((ImTextureID)sceneTexture, contentSizeVec, ImVec2(0.0f, 0.0f), ImVec2(1.0f, 1.0f));
    } else {
        ImGui::Dummy(contentSizeVec);
        ImGui::SetCursorPos(ImVec2(10, 10));
        ImGui::Text("No scene texture (yet).");
    }

    if (ImGui::IsItemHovered() && ImGui::IsMouseClicked(ImGuiMouseButton_Right)) {
        ImGui::SetWindowFocus();
    }

    ImVec2 imageMin = ImGui::GetItemRectMin();
    ImVec2 imageMax = ImGui::GetItemRectMax();
    if (imageOrigin) {
        *imageOrigin = CGPointMake(imageMin.x, imageMin.y);
    }
    if (imageSize) {
        *imageSize = CGSizeMake(imageMax.x - imageMin.x, imageMax.y - imageMin.y);
    }

    if (ImGui::BeginDragDropTarget()) {
        if (const ImGuiPayload* payload = ImGui::AcceptDragDropPayload("MCE_ASSET_MODEL")) {
            const char *payloadText = static_cast<const char *>(payload->Data);
            char createdId[64] = {0};
            MCEEditorCreateMeshEntityFromHandle(context, payloadText, createdId, sizeof(createdId));
        }
        if (const ImGuiPayload* payload = ImGui::AcceptDragDropPayload("MCE_ASSET_PREFAB")) {
            const char *payloadText = static_cast<const char *>(payload->Data);
            char createdId[64] = {0};
            MCEEditorInstantiatePrefabFromHandle(context, payloadText, createdId, sizeof(createdId));
        }
        if (const ImGuiPayload* payload = ImGui::AcceptDragDropPayload("MCE_ASSET_SCENE_PATH")) {
            const char *payloadText = static_cast<const char *>(payload->Data);
            MCEEditorOpenSceneAtPath(context, payloadText);
        }
        ImGui::EndDragDropTarget();
    }

    if (imageMax.x > imageMin.x && imageMax.y > imageMin.y) {
        const float toolbarPadding = 10.0f;
        ImVec2 playLabel = ImGui::CalcTextSize("Play");
        ImVec2 stopLabel = ImGui::CalcTextSize("Stop");
        ImVec2 pauseLabel = ImGui::CalcTextSize("Pause");
        ImVec2 resumeLabel = ImGui::CalcTextSize("Resume");
        ImVec2 cameraLabel = ImGui::CalcTextSize("Camera");
        ImVec2 padding = ImGui::GetStyle().FramePadding;
        float playWidth = playLabel.x + padding.x * 2.0f;
        float stopWidth = stopLabel.x + padding.x * 2.0f;
        float pauseWidth = std::max(pauseLabel.x, resumeLabel.x) + padding.x * 2.0f;
        float cameraWidth = cameraLabel.x + padding.x * 2.0f;
        float spacing = ImGui::GetStyle().ItemSpacing.x;
        float toolbarWidth = playWidth + spacing + pauseWidth + spacing + stopWidth + spacing + cameraWidth;
        float toolbarHeight = (playLabel.y > stopLabel.y ? playLabel.y : stopLabel.y) + padding.y * 2.0f;
        float centerX = imageMin.x + (imageMax.x - imageMin.x - toolbarWidth) * 0.5f;
        ImGui::SetCursorScreenPos(ImVec2(centerX, imageMin.y + toolbarPadding));
        ImGui::BeginChild("ViewportToolbar", ImVec2(toolbarWidth, toolbarHeight), false,
                          ImGuiWindowFlags_NoScrollbar | ImGuiWindowFlags_NoScrollWithMouse | ImGuiWindowFlags_NoBackground);
        bool playing = MCESceneIsPlaying(context) != 0;
        bool paused = MCESceneIsPaused(context) != 0;
        if (EditorUI::ToolbarButton("Play", !playing)) {
            MCEScenePlay(context);
        }
        viewportUIHovered = viewportUIHovered || ImGui::IsItemHovered() || ImGui::IsItemActive();
        ImGui::SameLine();
        if (EditorUI::ToolbarButton(paused ? "Resume" : "Pause", playing)) {
            if (paused) {
                MCESceneResume(context);
            } else {
                MCEScenePause(context);
            }
        }
        viewportUIHovered = viewportUIHovered || ImGui::IsItemHovered() || ImGui::IsItemActive();
        ImGui::SameLine();
        if (EditorUI::ToolbarButton("Stop", playing)) {
            MCESceneStop(context);
        }
        viewportUIHovered = viewportUIHovered || ImGui::IsItemHovered() || ImGui::IsItemActive();
        ImGui::SameLine();
        if (EditorUI::ToolbarButton("Camera", !playing)) {
            char createdId[64] = {0};
            MCEEditorCreateCameraFromView(context, createdId, sizeof(createdId));
        }
        viewportUIHovered = viewportUIHovered || ImGui::IsItemHovered() || ImGui::IsItemActive();
        ImGui::EndChild();
    }

    bool playing = MCESceneIsPlaying(context) != 0;
    if (!playing && imageMax.x > imageMin.x && imageMax.y > imageMin.y) {
        viewportUIHovered = viewportUIHovered || DrawGizmoToolbar(state, imageMin, imageMax);
    }

    if (previewTexture && imageMax.x > imageMin.x && imageMax.y > imageMin.y) {
        const float padding = 10.0f;
        float maxWidth = imageMax.x - imageMin.x;
        float maxHeight = imageMax.y - imageMin.y;
        float size = std::min(256.0f, std::min(maxWidth, maxHeight) * 0.35f);
        if (size >= 64.0f) {
            ImVec2 previewPos = ImVec2(imageMax.x - padding - size, imageMin.y + padding);
            ImGui::SetCursorScreenPos(previewPos);
            ImGui::BeginChild("CameraPreview",
                              ImVec2(size, size),
                              true,
                              ImGuiWindowFlags_NoScrollbar |
                                  ImGuiWindowFlags_NoScrollWithMouse |
                                  ImGuiWindowFlags_NoBackground |
                                  ImGuiWindowFlags_NoInputs);
            ImGui::Image((ImTextureID)previewTexture, ImVec2(size, size), ImVec2(0.0f, 0.0f), ImVec2(1.0f, 1.0f));
            ImGui::EndChild();
        }
    }

    ImGuiIO& io = ImGui::GetIO();
    const bool viewportActive = isHovered || isFocused;
    const bool cameraControlsActive =
        isHovered && (
            (io.KeyAlt && io.MouseDown[ImGuiMouseButton_Left]) ||
            (io.KeyAlt && io.MouseDown[ImGuiMouseButton_Right]) ||
            io.MouseDown[ImGuiMouseButton_Right]
        );
    const bool canHandleShortcuts = viewportActive && !(io.WantCaptureKeyboard || io.WantTextInput);
    if (!playing && canHandleShortcuts && !cameraControlsActive) {
        if (ImGui::IsKeyPressed(ImGuiKey_Q)) {
            state.operation = GizmoOperation::None;
        }
        if (ImGui::IsKeyPressed(ImGuiKey_W)) {
            state.operation = GizmoOperation::Translate;
        }
        if (ImGui::IsKeyPressed(ImGuiKey_E)) {
            state.operation = GizmoOperation::Rotate;
        }
        if (ImGui::IsKeyPressed(ImGuiKey_R)) {
            state.operation = GizmoOperation::Scale;
        }
    }

    bool gizmoCapturesMouse = false;
    bool gizmoCapturesKeyboard = false;
    if (!playing
        && !cameraControlsActive
        && state.operation != GizmoOperation::None
        && selectedEntityId && selectedEntityId[0] != 0
        && imageMax.x > imageMin.x && imageMax.y > imageMin.y) {
        float px = 0, py = 0, pz = 0;
        float rx = 0, ry = 0, rz = 0;
        float sx = 1, sy = 1, sz = 1;
        if (MCEEditorGetTransform(context, selectedEntityId, &px, &py, &pz, &rx, &ry, &rz, &sx, &sy, &sz) != 0) {
            float viewMatrix[16] = {0};
            float projectionMatrix[16] = {0};
            if (MCEEditorGetEditorCameraMatrices(context, viewMatrix, projectionMatrix) != 0) {
                ImGuizmo::SetDrawlist();
                ImGuizmo::SetRect(imageMin.x, imageMin.y, imageMax.x - imageMin.x, imageMax.y - imageMin.y);

                float transformMatrix[16];
                if (!GetModelMatrix(context, selectedEntityId, transformMatrix)) {
                    EditorUI::EndPanel();
                    return;
                }

                ImGuizmo::OPERATION operation = ToImGuizmoOperation(state.operation);
                ImGuizmo::MODE mode = (state.mode == 0) ? ImGuizmo::LOCAL : ImGuizmo::WORLD;
                float snapValues[3] = {0.0f, 0.0f, 0.0f};
                const bool useSnap = state.snapEnabled || io.KeyShift;
                const float *snap = nullptr;
                if (useSnap) {
                    switch (operation) {
                    case ImGuizmo::TRANSLATE:
                        snapValues[0] = state.translateSnap;
                        snapValues[1] = state.translateSnap;
                        snapValues[2] = state.translateSnap;
                        snap = snapValues;
                        break;
                    case ImGuizmo::ROTATE:
                        snapValues[0] = state.rotateSnap;
                        snapValues[1] = state.rotateSnap;
                        snapValues[2] = state.rotateSnap;
                        snap = snapValues;
                        break;
                    case ImGuizmo::SCALE:
                        snapValues[0] = state.scaleSnap;
                        snapValues[1] = state.scaleSnap;
                        snapValues[2] = state.scaleSnap;
                        snap = snapValues;
                        break;
                    default:
                        break;
                    }
                }

                const bool manipulated = ImGuizmo::Manipulate(viewMatrix, projectionMatrix, operation, mode, transformMatrix, nullptr, snap);
                gizmoCapturesMouse = ImGuizmo::IsOver() || ImGuizmo::IsUsing();
                gizmoCapturesKeyboard = ImGuizmo::IsUsing();

                if (manipulated) {
                    if (MCEEditorSetTransformFromMatrix(context, selectedEntityId, transformMatrix) == 0) {
                        return;
                    }
                }
            }
        }
    }

    viewportUIHovered = viewportUIHovered || gizmoCapturesMouse || gizmoCapturesKeyboard;
    if (uiHovered) {
        *uiHovered = viewportUIHovered;
    }
    if (isHovered && !viewportUIHovered) {
        ImGui::SetNextFrameWantCaptureMouse(false);
    }
    if (isFocused && !viewportUIHovered) {
        ImGui::SetNextFrameWantCaptureKeyboard(false);
    }
    MCEImGuiSetGizmoCapture(context, gizmoCapturesMouse ? 1 : 0, gizmoCapturesKeyboard ? 1 : 0);

    EditorUI::EndPanel();
}
