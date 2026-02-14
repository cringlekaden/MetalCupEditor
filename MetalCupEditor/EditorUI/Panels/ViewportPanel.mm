// ViewportPanel.mm
// Defines the ImGui Viewport panel rendering and interaction logic.
// Created by Kaden Cringle.

#import "ViewportPanel.h"

#import "../../ImGui/imgui.h"
#import "../../ImGuizmo/ImGuizmo.h"
#import "../Widgets/UIWidgets.h"
#include <algorithm>
#include <cmath>

extern "C" void MCEScenePlay(void);
extern "C" void MCESceneStop(void);
extern "C" uint32_t MCESceneIsPlaying(void);
extern "C" int32_t MCEEditorCreateMeshEntityFromHandle(const char *meshHandle, char *outId, int32_t outIdSize);
extern "C" uint32_t MCEEditorOpenSceneAtPath(const char *relativePath);
extern "C" uint32_t MCEEditorGetTransform(const char *entityId,
                                          float *px, float *py, float *pz,
                                          float *rx, float *ry, float *rz,
                                          float *sx, float *sy, float *sz);
extern "C" void MCEEditorSetTransformNoLog(const char *entityId,
                                           float px, float py, float pz,
                                           float rx, float ry, float rz,
                                           float sx, float sy, float sz);
extern "C" uint32_t MCEEditorGetEditorCameraMatrices(float *viewOut, float *projectionOut);
extern "C" void MCEImGuiSetGizmoCapture(uint32_t wantsMouse, uint32_t wantsKeyboard);
extern "C" void MCEEditorLogMessage(int32_t level, int32_t category, const char *message);
extern "C" uint32_t MCEEditorSetTransformFromMatrix(const char *entityId, const float *matrix);
extern "C" uint32_t MCEEditorGetModelMatrix(const char *entityId, float *matrixOut);

namespace {
    constexpr float kPi = 3.14159265358979323846f;
    constexpr float kDegToRad = 0.0174532925f;
    constexpr float kRadToDeg = 57.2957795f;

    enum class GizmoOperation : uint8_t {
        None,
        Translate,
        Rotate,
        Scale
    };

    struct GizmoState {
        GizmoOperation operation = GizmoOperation::Translate;
        ImGuizmo::MODE mode = ImGuizmo::LOCAL;
        bool snapEnabled = false;
        float translateSnap = 0.5f;
        float rotateSnap = 15.0f;
        float scaleSnap = 0.1f;
    };

    GizmoState g_GizmoState;

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

    float WrapAngle(float value) {
        float wrapped = fmodf(value + kPi, kPi * 2.0f);
        if (wrapped < 0) {
            wrapped += kPi * 2.0f;
        }
        return wrapped - kPi;
    }

    bool GetModelMatrix(const char *entityId, float *outMatrix) {
        if (!entityId || entityId[0] == 0 || !outMatrix) {
            return false;
        }
        if (MCEEditorGetModelMatrix(entityId, outMatrix) == 0) {
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

    void DrawGizmoToolbar(const ImVec2& imageMin, const ImVec2& imageMax) {
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
        if (ToolbarToggleButton("Select", g_GizmoState.operation == GizmoOperation::None)) {
            g_GizmoState.operation = GizmoOperation::None;
        }
        ImGui::SameLine();
        if (ToolbarToggleButton("Move", g_GizmoState.operation == GizmoOperation::Translate)) {
            g_GizmoState.operation = GizmoOperation::Translate;
        }
        ImGui::SameLine();
        if (ToolbarToggleButton("Rotate", g_GizmoState.operation == GizmoOperation::Rotate)) {
            g_GizmoState.operation = GizmoOperation::Rotate;
        }
        ImGui::SameLine();
        if (ToolbarToggleButton("Scale", g_GizmoState.operation == GizmoOperation::Scale)) {
            g_GizmoState.operation = GizmoOperation::Scale;
        }
        ImGui::SameLine();
        if (ToolbarToggleButton("Local", g_GizmoState.mode == ImGuizmo::LOCAL)) {
            g_GizmoState.mode = ImGuizmo::LOCAL;
        }
        ImGui::SameLine();
        if (ToolbarToggleButton("World", g_GizmoState.mode == ImGuizmo::WORLD)) {
            g_GizmoState.mode = ImGuizmo::WORLD;
        }
        ImGui::EndChild();
    }
}

void ImGuiViewportPanelDraw(id<MTLTexture> _Nullable sceneTexture,
                            const char *selectedEntityId,
                            bool *hovered,
                            bool *focused,
                            CGSize *contentSize,
                            CGPoint *contentOrigin,
                            CGPoint *imageOrigin,
                            CGSize *imageSize) {
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
    if (isHovered) {
        ImGui::SetNextFrameWantCaptureMouse(false);
    }
    if (isFocused) {
        ImGui::SetNextFrameWantCaptureKeyboard(false);
    }

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
            MCEEditorCreateMeshEntityFromHandle(payloadText, createdId, sizeof(createdId));
        }
        if (const ImGuiPayload* payload = ImGui::AcceptDragDropPayload("MCE_ASSET_SCENE_PATH")) {
            const char *payloadText = static_cast<const char *>(payload->Data);
            MCEEditorOpenSceneAtPath(payloadText);
        }
        ImGui::EndDragDropTarget();
    }

    if (imageMax.x > imageMin.x && imageMax.y > imageMin.y) {
        const float toolbarPadding = 10.0f;
        ImVec2 playLabel = ImGui::CalcTextSize("Play");
        ImVec2 stopLabel = ImGui::CalcTextSize("Stop");
        ImVec2 padding = ImGui::GetStyle().FramePadding;
        float playWidth = playLabel.x + padding.x * 2.0f;
        float stopWidth = stopLabel.x + padding.x * 2.0f;
        float spacing = ImGui::GetStyle().ItemSpacing.x;
        float toolbarWidth = playWidth + spacing + stopWidth;
        float toolbarHeight = (playLabel.y > stopLabel.y ? playLabel.y : stopLabel.y) + padding.y * 2.0f;
        float centerX = imageMin.x + (imageMax.x - imageMin.x - toolbarWidth) * 0.5f;
        ImGui::SetCursorScreenPos(ImVec2(centerX, imageMin.y + toolbarPadding));
        ImGui::BeginChild("ViewportToolbar", ImVec2(toolbarWidth, toolbarHeight), false,
                          ImGuiWindowFlags_NoScrollbar | ImGuiWindowFlags_NoScrollWithMouse | ImGuiWindowFlags_NoBackground);
        bool playing = MCESceneIsPlaying() != 0;
        if (EditorUI::ToolbarButton("Play", !playing)) {
            MCEScenePlay();
        }
        ImGui::SameLine();
        if (EditorUI::ToolbarButton("Stop", playing)) {
            MCESceneStop();
        }
        ImGui::EndChild();
    }

    if (imageMax.x > imageMin.x && imageMax.y > imageMin.y) {
        DrawGizmoToolbar(imageMin, imageMax);
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
    if (canHandleShortcuts && !cameraControlsActive) {
        if (ImGui::IsKeyPressed(ImGuiKey_Q)) {
            g_GizmoState.operation = GizmoOperation::None;
        }
        if (ImGui::IsKeyPressed(ImGuiKey_W)) {
            g_GizmoState.operation = GizmoOperation::Translate;
        }
        if (ImGui::IsKeyPressed(ImGuiKey_E)) {
            g_GizmoState.operation = GizmoOperation::Rotate;
        }
        if (ImGui::IsKeyPressed(ImGuiKey_R)) {
            g_GizmoState.operation = GizmoOperation::Scale;
        }
    }

    bool gizmoCapturesMouse = false;
    bool gizmoCapturesKeyboard = false;
    if (!cameraControlsActive
        && g_GizmoState.operation != GizmoOperation::None
        && selectedEntityId && selectedEntityId[0] != 0
        && imageMax.x > imageMin.x && imageMax.y > imageMin.y) {
        float px = 0, py = 0, pz = 0;
        float rx = 0, ry = 0, rz = 0;
        float sx = 1, sy = 1, sz = 1;
        if (MCEEditorGetTransform(selectedEntityId, &px, &py, &pz, &rx, &ry, &rz, &sx, &sy, &sz) != 0) {
            float viewMatrix[16] = {0};
            float projectionMatrix[16] = {0};
            if (MCEEditorGetEditorCameraMatrices(viewMatrix, projectionMatrix) != 0) {
                ImGuizmo::SetDrawlist();
                ImGuizmo::SetRect(imageMin.x, imageMin.y, imageMax.x - imageMin.x, imageMax.y - imageMin.y);

                float transformMatrix[16];
                if (!GetModelMatrix(selectedEntityId, transformMatrix)) {
                    MCEEditorLogMessage(3, 2, "Gizmo model matrix fetch failed; update skipped.");
                    EditorUI::EndPanel();
                    return;
                }

                ImGuizmo::OPERATION operation = ToImGuizmoOperation(g_GizmoState.operation);
                ImGuizmo::MODE mode = g_GizmoState.mode;
                float snapValues[3] = {0.0f, 0.0f, 0.0f};
                const bool useSnap = g_GizmoState.snapEnabled || io.KeyShift;
                const float *snap = nullptr;
                if (useSnap) {
                    switch (operation) {
                    case ImGuizmo::TRANSLATE:
                        snapValues[0] = g_GizmoState.translateSnap;
                        snapValues[1] = g_GizmoState.translateSnap;
                        snapValues[2] = g_GizmoState.translateSnap;
                        snap = snapValues;
                        break;
                    case ImGuizmo::ROTATE:
                        snapValues[0] = g_GizmoState.rotateSnap;
                        snapValues[1] = g_GizmoState.rotateSnap;
                        snapValues[2] = g_GizmoState.rotateSnap;
                        snap = snapValues;
                        break;
                    case ImGuizmo::SCALE:
                        snapValues[0] = g_GizmoState.scaleSnap;
                        snapValues[1] = g_GizmoState.scaleSnap;
                        snapValues[2] = g_GizmoState.scaleSnap;
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
                    if (MCEEditorSetTransformFromMatrix(selectedEntityId, transformMatrix) == 0) {
                        MCEEditorLogMessage(3, 2, "Gizmo transform decomposition failed; update skipped.");
                        return;
                    }
                }
            }
        }
    }

    MCEImGuiSetGizmoCapture(gizmoCapturesMouse ? 1 : 0, gizmoCapturesKeyboard ? 1 : 0);

    EditorUI::EndPanel();
}
