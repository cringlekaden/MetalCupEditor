// ViewportPanel.mm
// Defines the ImGui Viewport panel rendering and interaction logic.
// Created by Kaden Cringle.

#import "ViewportPanel.h"

#import "../../ImGui/imgui.h"
#import "../Widgets/UIWidgets.h"

extern "C" void MCEScenePlay(void);
extern "C" void MCESceneStop(void);
extern "C" uint32_t MCESceneIsPlaying(void);
extern "C" int32_t MCEEditorCreateMeshEntityFromHandle(const char *meshHandle, char *outId, int32_t outIdSize);
extern "C" uint32_t MCEEditorOpenSceneAtPath(const char *relativePath);

void ImGuiViewportPanelDraw(id<MTLTexture> _Nullable sceneTexture,
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

    EditorUI::EndPanel();
}
