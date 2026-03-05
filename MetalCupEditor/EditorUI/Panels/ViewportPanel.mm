/// ViewportPanel.mm
/// Defines the ImGui Viewport panel rendering and interaction logic.
/// Created by Kaden Cringle.

#import "ViewportPanel.h"

#import "../../ImGui/imgui.h"
#import "../../ImGuizmo/ImGuizmo.h"
#import "PanelState.h"
#import "../Widgets/UIWidgets.h"
#import "../EditorIcons.h"
#include <algorithm>
#include <cmath>
#include <string.h>

extern "C" void MCEScenePlay(MCE_CTX);
extern "C" void MCESceneStop(MCE_CTX);
extern "C" void MCEScenePause(MCE_CTX);
extern "C" void MCESceneResume(MCE_CTX);
extern "C" void MCESceneSimulate(MCE_CTX);
extern "C" void MCESceneResetSimulation(MCE_CTX);
extern "C" uint32_t MCESceneIsPlaying(MCE_CTX);
extern "C" uint32_t MCESceneIsPaused(MCE_CTX);
extern "C" uint32_t MCESceneIsSimulating(MCE_CTX);
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
extern "C" uint32_t MCEImportBeginForHandle(MCE_CTX, const char *handle);
extern "C" int32_t MCEEditorGetViewportGizmoOperation(MCE_CTX);
extern "C" void MCEEditorSetViewportGizmoOperation(MCE_CTX, int32_t value);
extern "C" int32_t MCEEditorGetViewportGizmoSpaceMode(MCE_CTX);
extern "C" void MCEEditorSetViewportGizmoSpaceMode(MCE_CTX, int32_t value);
extern "C" uint32_t MCEEditorGetViewportSnapEnabled(MCE_CTX);
extern "C" void MCEEditorSetViewportSnapEnabled(MCE_CTX, uint32_t value);
extern "C" int32_t MCEEditorGetEntityCount(MCE_CTX);
extern "C" int32_t MCEEditorGetEntityIdAt(MCE_CTX, int32_t index, char *buffer, int32_t bufferSize);
extern "C" uint32_t MCEEditorGetCamera(MCE_CTX, const char *entityId,
                                      int32_t *projectionType,
                                      float *fovDegrees,
                                      float *orthoSize,
                                      float *nearPlane,
                                      float *farPlane,
                                      uint32_t *isPrimary,
                                      uint32_t *isEditor);
extern "C" uint32_t MCEEditorGetLight(MCE_CTX, const char *entityId, int32_t *type,
                                     float *colorX, float *colorY, float *colorZ,
                                     float *brightness, float *range, float *innerCos, float *outerCos,
                                     float *dirX, float *dirY, float *dirZ,
                                     uint32_t *castsShadows);
extern "C" uint32_t MCEEditorGetEntityName(MCE_CTX, const char *entityId, char *buffer, int32_t bufferSize);
extern "C" uint32_t MCEEditorGetViewportShowWorldIcons(MCE_CTX);
extern "C" float MCEEditorGetViewportWorldIconBaseSize(MCE_CTX);
extern "C" float MCEEditorGetViewportWorldIconDistanceScale(MCE_CTX);
extern "C" float MCEEditorGetViewportWorldIconMinSize(MCE_CTX);
extern "C" float MCEEditorGetViewportWorldIconMaxSize(MCE_CTX);
extern "C" uint32_t MCEEditorGetViewportShowSelectedCameraFrustum(MCE_CTX);
extern "C" uint32_t MCEEditorGetViewportPreviewEnabled(MCE_CTX);
extern "C" float MCEEditorGetViewportPreviewSize(MCE_CTX);
extern "C" int32_t MCEEditorGetViewportPreviewPosition(MCE_CTX);

namespace {
    using MCEPanelState::GizmoOperation;
    using MCEPanelState::ViewportState;
    struct Vec3 {
        float x;
        float y;
        float z;
    };

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

    ImVec4 MulMat4Vec4(const float *m, const ImVec4 &v) {
        return ImVec4(
            m[0] * v.x + m[4] * v.y + m[8] * v.z + m[12] * v.w,
            m[1] * v.x + m[5] * v.y + m[9] * v.z + m[13] * v.w,
            m[2] * v.x + m[6] * v.y + m[10] * v.z + m[14] * v.w,
            m[3] * v.x + m[7] * v.y + m[11] * v.z + m[15] * v.w
        );
    }

    ImVec4 ToWorldPoint(const float *model, const Vec3 &local) {
        return MulMat4Vec4(model, ImVec4(local.x, local.y, local.z, 1.0f));
    }

    bool ProjectWorldToScreen(const Vec3 &world,
                              const float *viewMatrix,
                              const float *projectionMatrix,
                              const ImVec2 &imageMin,
                              const ImVec2 &imageSize,
                              ImVec2 *outScreen,
                              float *outDepth,
                              bool clipToNDC = true) {
        const ImVec4 viewPos = MulMat4Vec4(viewMatrix, ImVec4(world.x, world.y, world.z, 1.0f));
        const ImVec4 clip = MulMat4Vec4(projectionMatrix, viewPos);
        if (clip.w <= 0.0001f) {
            return false;
        }
        const float ndcX = clip.x / clip.w;
        const float ndcY = clip.y / clip.w;
        const float ndcZ = clip.z / clip.w;
        if (clipToNDC && (ndcX < -1.0f || ndcX > 1.0f || ndcY < -1.0f || ndcY > 1.0f || ndcZ < -1.0f || ndcZ > 1.0f)) {
            return false;
        }
        outScreen->x = imageMin.x + (ndcX * 0.5f + 0.5f) * imageSize.x;
        outScreen->y = imageMin.y + (1.0f - (ndcY * 0.5f + 0.5f)) * imageSize.y;
        if (outDepth) {
            *outDepth = fabsf(viewPos.z);
        }
        return true;
    }

    ImU32 ImColorFromStyle(const ImVec4 &color) {
        return ImGui::ColorConvertFloat4ToU32(color);
    }

    void DrawWorldIcons(void *context,
                        const char *selectedEntityId,
                        const float *viewMatrix,
                        const float *projectionMatrix,
                        const ImVec2 &imageMin,
                        const ImVec2 &imageMax) {
        if (MCEEditorGetViewportShowWorldIcons(context) == 0) {
            return;
        }
        ImDrawList *drawList = ImGui::GetWindowDrawList();
        const ImVec2 imageSize(imageMax.x - imageMin.x, imageMax.y - imageMin.y);
        const float baseSize = MCEEditorGetViewportWorldIconBaseSize(context);
        const float distanceScale = MCEEditorGetViewportWorldIconDistanceScale(context);
        const float minSize = MCEEditorGetViewportWorldIconMinSize(context);
        const float maxSize = MCEEditorGetViewportWorldIconMaxSize(context);
        const ImU32 normalColor = ImColorFromStyle(ImGui::GetStyleColorVec4(ImGuiCol_Text));
        const ImU32 accentColor = ImColorFromStyle(ImGui::GetStyleColorVec4(ImGuiCol_CheckMark));

        const int32_t entityCount = MCEEditorGetEntityCount(context);
        for (int32_t i = 0; i < entityCount; ++i) {
            char entityId[64] = {0};
            if (MCEEditorGetEntityIdAt(context, i, entityId, sizeof(entityId)) == 0) {
                continue;
            }
            float modelMatrix[16] = {0};
            if (!GetModelMatrix(context, entityId, modelMatrix)) {
                continue;
            }
            const float px = modelMatrix[12];
            const float py = modelMatrix[13];
            const float pz = modelMatrix[14];

            const char *glyph = nullptr;
            int32_t projectionType = 0;
            float fov = 60.0f, orthoSize = 10.0f, nearPlane = 0.01f, farPlane = 1000.0f;
            uint32_t isPrimary = 0, isEditor = 0;
            if (MCEEditorGetCamera(context, entityId, &projectionType, &fov, &orthoSize, &nearPlane, &farPlane, &isPrimary, &isEditor) != 0) {
                if (isEditor != 0) {
                    continue;
                }
                glyph = EditorIcons::Glyph(EditorIcons::Id::Camera);
            } else {
                int32_t lightType = 0;
                if (MCEEditorGetLight(context, entityId, &lightType,
                                      nullptr, nullptr, nullptr,
                                      nullptr, nullptr, nullptr, nullptr,
                                      nullptr, nullptr, nullptr,
                                      nullptr) == 0) {
                    continue;
                }
                if (lightType == 2) {
                    glyph = EditorIcons::Glyph(EditorIcons::Id::DirectionalLight);
                } else if (lightType == 1) {
                    glyph = EditorIcons::Glyph(EditorIcons::Id::SpotLight);
                } else {
                    glyph = EditorIcons::Glyph(EditorIcons::Id::PointLight);
                }
            }

            ImVec2 screenPos {};
            float depth = 0.0f;
            if (!ProjectWorldToScreen(Vec3 { px, py, pz }, viewMatrix, projectionMatrix, imageMin, imageSize, &screenPos, &depth)) {
                continue;
            }

            float scaled = baseSize / (1.0f + depth * distanceScale * 0.1f);
            scaled = std::max(minSize, std::min(maxSize, scaled));
            const bool selected = selectedEntityId && selectedEntityId[0] != 0 && strcmp(selectedEntityId, entityId) == 0;
            const ImU32 color = selected ? accentColor : normalColor;
            ImVec2 glyphSize = ImGui::CalcTextSize(glyph);
            float fontSize = ImGui::GetFontSize();
            float scale = scaled / std::max(1.0f, fontSize);
            drawList->AddText(ImGui::GetFont(), fontSize * scale, ImVec2(screenPos.x - glyphSize.x * 0.5f * scale, screenPos.y - glyphSize.y * 0.5f * scale), color, glyph);
        }
    }

    bool ToolbarToggleButton(const char *id, const char *icon, const char *tooltip, bool active) {
        return EditorUI::IconButton(id, icon, tooltip, active, false);
    }

    bool DrawGizmoToolbar(void *context, ViewportState &state, const ImVec2& imageMin, const ImVec2& imageMax) {
        const float toolbarPadding = 10.0f;
        const ImVec2 padding = ImGui::GetStyle().FramePadding;
        const float spacing = ImGui::GetStyle().ItemSpacing.x;
        const char *icons[] = {
            EditorIcons::Glyph(EditorIcons::Id::Select),
            EditorIcons::Glyph(EditorIcons::Id::Translate),
            EditorIcons::Glyph(EditorIcons::Id::Rotate),
            EditorIcons::Glyph(EditorIcons::Id::Scale),
            EditorIcons::Glyph(EditorIcons::Id::Local),
            EditorIcons::Glyph(EditorIcons::Id::World),
            EditorIcons::Glyph(EditorIcons::Id::Snap)
        };
        const char *ids[] = { "gizmo_select", "gizmo_translate", "gizmo_rotate", "gizmo_scale", "gizmo_local", "gizmo_world", "gizmo_snap" };
        const char *tooltips[] = {
            "Select (Q)",
            "Translate (W)",
            "Rotate (E)",
            "Scale (R)",
            "Local gizmo space",
            "World gizmo space",
            "Snap toggle"
        };

        float widths[7];
        float maxLabelHeight = 0.0f;
        for (int i = 0; i < 7; ++i) {
            ImVec2 labelSize = ImGui::CalcTextSize(icons[i]);
            widths[i] = labelSize.x + padding.x * 2.0f;
            maxLabelHeight = std::max(maxLabelHeight, labelSize.y);
        }
        float toolbarWidth = widths[0] + widths[1] + widths[2] + widths[3] + widths[4] + widths[5] + widths[6] + spacing * 6.0f;
        float toolbarHeight = maxLabelHeight + padding.y * 2.0f;

        ImGui::SetCursorScreenPos(ImVec2(imageMin.x + toolbarPadding, imageMin.y + toolbarPadding));
        ImGui::BeginChild("ViewportGizmoToolbar", ImVec2(toolbarWidth, toolbarHeight), false,
                          ImGuiWindowFlags_NoScrollbar | ImGuiWindowFlags_NoScrollWithMouse | ImGuiWindowFlags_NoBackground);
        bool hovered = false;
        if (ToolbarToggleButton(ids[0], icons[0], tooltips[0], state.operation == GizmoOperation::None)) {
            state.operation = GizmoOperation::None;
            MCEEditorSetViewportGizmoOperation(context, static_cast<int32_t>(state.operation));
        }
        hovered = hovered || ImGui::IsItemHovered() || ImGui::IsItemActive();
        ImGui::SameLine();
        if (ToolbarToggleButton(ids[1], icons[1], tooltips[1], state.operation == GizmoOperation::Translate)) {
            state.operation = GizmoOperation::Translate;
            MCEEditorSetViewportGizmoOperation(context, static_cast<int32_t>(state.operation));
        }
        hovered = hovered || ImGui::IsItemHovered() || ImGui::IsItemActive();
        ImGui::SameLine();
        if (ToolbarToggleButton(ids[2], icons[2], tooltips[2], state.operation == GizmoOperation::Rotate)) {
            state.operation = GizmoOperation::Rotate;
            MCEEditorSetViewportGizmoOperation(context, static_cast<int32_t>(state.operation));
        }
        hovered = hovered || ImGui::IsItemHovered() || ImGui::IsItemActive();
        ImGui::SameLine();
        if (ToolbarToggleButton(ids[3], icons[3], tooltips[3], state.operation == GizmoOperation::Scale)) {
            state.operation = GizmoOperation::Scale;
            MCEEditorSetViewportGizmoOperation(context, static_cast<int32_t>(state.operation));
        }
        hovered = hovered || ImGui::IsItemHovered() || ImGui::IsItemActive();
        ImGui::SameLine();
        if (ToolbarToggleButton(ids[4], icons[4], tooltips[4], state.mode == 0)) {
            state.mode = 0;
            MCEEditorSetViewportGizmoSpaceMode(context, state.mode);
        }
        hovered = hovered || ImGui::IsItemHovered() || ImGui::IsItemActive();
        ImGui::SameLine();
        if (ToolbarToggleButton(ids[5], icons[5], tooltips[5], state.mode == 1)) {
            state.mode = 1;
            MCEEditorSetViewportGizmoSpaceMode(context, state.mode);
        }
        hovered = hovered || ImGui::IsItemHovered() || ImGui::IsItemActive();
        ImGui::SameLine();
        if (ToolbarToggleButton(ids[6], icons[6], tooltips[6], state.snapEnabled)) {
            state.snapEnabled = !state.snapEnabled;
            MCEEditorSetViewportSnapEnabled(context, state.snapEnabled ? 1 : 0);
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
    static bool loadedViewportSettings = false;
    if (!loadedViewportSettings) {
        loadedViewportSettings = true;
        const int operation = MCEEditorGetViewportGizmoOperation(context);
        if (operation >= static_cast<int>(GizmoOperation::None) && operation <= static_cast<int>(GizmoOperation::Scale)) {
            state.operation = static_cast<GizmoOperation>(operation);
        }
        const int mode = MCEEditorGetViewportGizmoSpaceMode(context);
        state.mode = (mode == 1) ? 1 : 0;
        state.snapEnabled = MCEEditorGetViewportSnapEnabled(context) != 0;
    }
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
        if (MCESceneIsPlaying(context) == 0 && MCESceneIsSimulating(context) == 0) {
            if (const ImGuiPayload* payload = ImGui::AcceptDragDropPayload("MCE_ASSET_MODEL")) {
                const char *payloadText = static_cast<const char *>(payload->Data);
                if (MCEImportBeginForHandle(context, payloadText) == 0) {
                    char createdId[64] = {0};
                    MCEEditorCreateMeshEntityFromHandle(context, payloadText, createdId, sizeof(createdId));
                }
            }
            if (const ImGuiPayload* payload = ImGui::AcceptDragDropPayload("MCE_ASSET_PREFAB")) {
                const char *payloadText = static_cast<const char *>(payload->Data);
                char createdId[64] = {0};
                MCEEditorInstantiatePrefabFromHandle(context, payloadText, createdId, sizeof(createdId));
            }
        } else {
            ImGui::AcceptDragDropPayload("MCE_ASSET_MODEL");
            ImGui::AcceptDragDropPayload("MCE_ASSET_PREFAB");
        }
        if (const ImGuiPayload* payload = ImGui::AcceptDragDropPayload("MCE_ASSET_TEXTURE")) {
            const char *payloadText = static_cast<const char *>(payload->Data);
            (void)MCEImportBeginForHandle(context, payloadText);
        }
        if (const ImGuiPayload* payload = ImGui::AcceptDragDropPayload("MCE_ASSET_ENVIRONMENT")) {
            const char *payloadText = static_cast<const char *>(payload->Data);
            (void)MCEImportBeginForHandle(context, payloadText);
        }
        if (const ImGuiPayload* payload = ImGui::AcceptDragDropPayload("MCE_ASSET_SCENE_PATH")) {
            const char *payloadText = static_cast<const char *>(payload->Data);
            MCEEditorOpenSceneAtPath(context, payloadText);
        }
        ImGui::EndDragDropTarget();
    }

    bool playing = MCESceneIsPlaying(context) != 0;
    bool paused = MCESceneIsPaused(context) != 0;
    bool simulating = MCESceneIsSimulating(context) != 0;
    if (imageMax.x > imageMin.x && imageMax.y > imageMin.y) {
        const float toolbarPadding = 10.0f;
        const char *modeLabel = "Mode: Edit";
        if (playing) {
            modeLabel = paused ? "Mode: Play (Paused)" : "Mode: Play";
        } else if (simulating) {
            modeLabel = "Mode: Simulate";
        }
        ImVec2 modeTextSize = ImGui::CalcTextSize(modeLabel);
        ImVec2 playLabel = ImGui::CalcTextSize(EditorIcons::Glyph(EditorIcons::Id::Play));
        ImVec2 simulateLabel = ImGui::CalcTextSize(EditorIcons::Glyph(EditorIcons::Id::Simulate));
        ImVec2 stopLabel = ImGui::CalcTextSize(EditorIcons::Glyph(EditorIcons::Id::Stop));
        ImVec2 resetLabel = ImGui::CalcTextSize(EditorIcons::Glyph(EditorIcons::Id::Reset));
        ImVec2 pauseLabel = ImGui::CalcTextSize(EditorIcons::Glyph(EditorIcons::Id::Pause));
        ImVec2 resumeLabel = ImGui::CalcTextSize(EditorIcons::Glyph(EditorIcons::Id::Play));
        ImVec2 padding = ImGui::GetStyle().FramePadding;
        float modeWidth = modeTextSize.x;
        float playWidth = playLabel.x + padding.x * 2.0f;
        float simulateWidth = simulateLabel.x + padding.x * 2.0f;
        float stopWidth = stopLabel.x + padding.x * 2.0f;
        float resetWidth = resetLabel.x + padding.x * 2.0f;
        float pauseWidth = std::max(pauseLabel.x, resumeLabel.x) + padding.x * 2.0f;
        float spacing = ImGui::GetStyle().ItemSpacing.x;
        float actionWidth = playing
            ? (pauseWidth + spacing + stopWidth)
            : (simulating ? resetWidth : (playWidth + spacing + simulateWidth));
        float toolbarWidth = modeWidth + spacing + actionWidth;
        float toolbarHeight = (playLabel.y > stopLabel.y ? playLabel.y : stopLabel.y) + padding.y * 2.0f;
        float centerX = imageMin.x + (imageMax.x - imageMin.x - toolbarWidth) * 0.5f;
        ImGui::SetCursorScreenPos(ImVec2(centerX, imageMin.y + toolbarPadding));
        ImGui::BeginChild("ViewportToolbar", ImVec2(toolbarWidth, toolbarHeight), false,
                          ImGuiWindowFlags_NoScrollbar | ImGuiWindowFlags_NoScrollWithMouse | ImGuiWindowFlags_NoBackground);
        ImGui::TextUnformatted(modeLabel);
        viewportUIHovered = viewportUIHovered || ImGui::IsItemHovered() || ImGui::IsItemActive();
        ImGui::SameLine();
        if (playing) {
            if (EditorUI::IconButton("viewport_resume_pause",
                                     paused ? EditorIcons::Glyph(EditorIcons::Id::Play) : EditorIcons::Glyph(EditorIcons::Id::Pause),
                                     paused ? "Resume play mode" : "Pause play mode",
                                     false,
                                     false)) {
                if (paused) {
                    MCESceneResume(context);
                } else {
                    MCEScenePause(context);
                }
            }
            viewportUIHovered = viewportUIHovered || ImGui::IsItemHovered() || ImGui::IsItemActive();
            ImGui::SameLine();
            if (EditorUI::IconButton("viewport_stop", EditorIcons::Glyph(EditorIcons::Id::Stop), "Stop play mode", false, false)) {
                MCESceneStop(context);
            }
            viewportUIHovered = viewportUIHovered || ImGui::IsItemHovered() || ImGui::IsItemActive();
        } else if (simulating) {
            if (EditorUI::IconButton("viewport_reset", EditorIcons::Glyph(EditorIcons::Id::Reset), "Reset simulation", false, false)) {
                MCESceneResetSimulation(context);
            }
            viewportUIHovered = viewportUIHovered || ImGui::IsItemHovered() || ImGui::IsItemActive();
        } else {
            if (EditorUI::IconButton("viewport_play", EditorIcons::Glyph(EditorIcons::Id::Play), "Play", false, false)) {
                MCEScenePlay(context);
            }
            viewportUIHovered = viewportUIHovered || ImGui::IsItemHovered() || ImGui::IsItemActive();
            ImGui::SameLine();
            if (EditorUI::IconButton("viewport_simulate", EditorIcons::Glyph(EditorIcons::Id::Simulate), "Simulate", false, false)) {
                MCESceneSimulate(context);
            }
            viewportUIHovered = viewportUIHovered || ImGui::IsItemHovered() || ImGui::IsItemActive();
        }
        ImGui::EndChild();
    }

    if (imageMax.x > imageMin.x && imageMax.y > imageMin.y) {
        const float padding = 10.0f;
        ImVec2 cameraLabel = ImGui::CalcTextSize(EditorIcons::Glyph(EditorIcons::Id::Camera));
        ImVec2 framePadding = ImGui::GetStyle().FramePadding;
        float cameraWidth = cameraLabel.x + framePadding.x * 2.0f;
        float cameraHeight = cameraLabel.y + framePadding.y * 2.0f;
        ImVec2 cameraPos = ImVec2(imageMax.x - padding - cameraWidth, imageMin.y + padding);
        ImGui::SetCursorScreenPos(cameraPos);
        ImGui::BeginChild("ViewportCameraButton", ImVec2(cameraWidth, cameraHeight), false,
                          ImGuiWindowFlags_NoScrollbar | ImGuiWindowFlags_NoScrollWithMouse | ImGuiWindowFlags_NoBackground);
        if (EditorUI::IconButton("viewport_create_camera",
                                 EditorIcons::Glyph(EditorIcons::Id::Camera),
                                 "Create Camera From View",
                                 false,
                                 playing || simulating)) {
            char createdId[64] = {0};
            MCEEditorCreateCameraFromView(context, createdId, sizeof(createdId));
        }
        viewportUIHovered = viewportUIHovered || ImGui::IsItemHovered() || ImGui::IsItemActive();
        ImGui::EndChild();
    }

    if (!playing && imageMax.x > imageMin.x && imageMax.y > imageMin.y) {
        viewportUIHovered = viewportUIHovered || DrawGizmoToolbar(context, state, imageMin, imageMax);
    }

    if (!playing && imageMax.x > imageMin.x && imageMax.y > imageMin.y) {
        float viewMatrix[16] = {0};
        float projectionMatrix[16] = {0};
        if (MCEEditorGetEditorCameraMatrices(context, viewMatrix, projectionMatrix) != 0) {
            DrawWorldIcons(context, selectedEntityId, viewMatrix, projectionMatrix, imageMin, imageMax);
        }
    }

    const bool previewEnabled = MCEEditorGetViewportPreviewEnabled(context) != 0;
    if (previewEnabled && previewTexture && imageMax.x > imageMin.x && imageMax.y > imageMin.y) {
        const float padding = 10.0f;
        float maxWidth = imageMax.x - imageMin.x;
        float maxHeight = imageMax.y - imageMin.y;
        const float sizeFactor = std::max(0.15f, std::min(0.5f, MCEEditorGetViewportPreviewSize(context)));
        float size = std::min(320.0f, std::min(maxWidth, maxHeight) * sizeFactor);
        if (size >= 64.0f) {
            ImVec2 previewPos = ImVec2(imageMax.x - padding - size, imageMax.y - padding - size);
            const int32_t previewPosition = MCEEditorGetViewportPreviewPosition(context);
            if (previewPosition == 0) {
                previewPos = ImVec2(imageMin.x + padding, imageMin.y + padding);
            } else if (previewPosition == 1) {
                previewPos = ImVec2(imageMax.x - padding - size, imageMin.y + padding);
            } else if (previewPosition == 2) {
                previewPos = ImVec2(imageMin.x + padding, imageMax.y - padding - size);
            }
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
            MCEEditorSetViewportGizmoOperation(context, static_cast<int32_t>(state.operation));
        }
        if (ImGui::IsKeyPressed(ImGuiKey_W)) {
            state.operation = GizmoOperation::Translate;
            MCEEditorSetViewportGizmoOperation(context, static_cast<int32_t>(state.operation));
        }
        if (ImGui::IsKeyPressed(ImGuiKey_E)) {
            state.operation = GizmoOperation::Rotate;
            MCEEditorSetViewportGizmoOperation(context, static_cast<int32_t>(state.operation));
        }
        if (ImGui::IsKeyPressed(ImGuiKey_R)) {
            state.operation = GizmoOperation::Scale;
            MCEEditorSetViewportGizmoOperation(context, static_cast<int32_t>(state.operation));
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
