// ImGuiBridge.mm
// Defines the ImGui bridge interface for editor rendering and input.
// Created by Kaden Cringle.

#import "ImGuiBridge.h"

// ImGui
#import "../../ImGui/imgui.h"
#import "../../ImGui/backends/imgui_impl_osx.h"
#import "../../ImGui/backends/imgui_impl_metal.h"

#import "../../EditorUI/Panels/RendererPanel.h"
#import "../../EditorUI/Panels/ViewportPanel.h"
#import "../../EditorUI/Panels/SceneHierarchyPanel.h"
#import "../../EditorUI/Panels/InspectorPanel.h"
#import "../../EditorUI/Panels/ContentBrowserPanel.h"
#import "../../EditorUI/Panels/PanelState.h"
#import "../Bridge/RendererSettingsBridge.h"
#import "../../EditorUI/Widgets/UIWidgets.h"
#import <Cocoa/Cocoa.h>
#include <algorithm>
#include <cstring>
#include <ctime>
#include <string>
#include <vector>
#include <sys/stat.h>

extern "C" void *MCEUIPanelStateCreate(void) {
    return new MCEPanelState::EditorUIPanelState();
}

extern "C" void MCEUIPanelStateDestroy(void *state) {
    delete static_cast<MCEPanelState::EditorUIPanelState *>(state);
}

extern "C" void MCEProjectNew(MCE_CTX);
extern "C" void MCEProjectOpen(MCE_CTX);
extern "C" void MCEProjectSave(MCE_CTX);
extern "C" void MCEProjectSaveAs(MCE_CTX);
extern "C" void MCEProjectSaveAll(MCE_CTX);
extern "C" uint32_t MCEProjectHasOpen(MCE_CTX);
extern "C" uint32_t MCEProjectNeedsModal(MCE_CTX);
extern "C" void MCEProjectDismissModal(MCE_CTX);
extern "C" int32_t MCEProjectRecentCount(MCE_CTX);
extern "C" int32_t MCEProjectRecentPathAt(MCE_CTX,  int32_t index, char *buffer, int32_t bufferSize);
extern "C" uint32_t MCEProjectOpenRecent(MCE_CTX,  const char *path);
extern "C" int32_t MCEProjectListCount(MCE_CTX);
extern "C" uint32_t MCEProjectListAt(MCE_CTX,  int32_t index,
                                     char *nameBuffer, int32_t nameBufferSize,
                                     char *pathBuffer, int32_t pathBufferSize,
                                     double *modifiedOut);
extern "C" uint32_t MCEProjectOpenAtPath(MCE_CTX,  const char *path);
extern "C" uint32_t MCEProjectDeleteAtPath(MCE_CTX,  const char *path);
extern "C" void MCESceneSave(MCE_CTX);
extern "C" void MCESceneSaveAs(MCE_CTX);
extern "C" void MCESceneLoad(MCE_CTX);
extern "C" void MCEScenePlay(MCE_CTX);
extern "C" void MCESceneStop(MCE_CTX);
extern "C" void MCEScenePause(MCE_CTX);
extern "C" void MCESceneResume(MCE_CTX);
extern "C" uint32_t MCESceneIsPlaying(MCE_CTX);
extern "C" uint32_t MCESceneIsPaused(MCE_CTX);
extern "C" uint32_t MCESceneIsDirty(MCE_CTX);
extern "C" uint32_t MCEEditorPopNextAlert(MCE_CTX,  char *buffer, int32_t bufferSize);
extern "C" uint32_t MCEEditorGetImGuiIniPath(MCE_CTX, char *buffer, int32_t bufferSize);
extern "C" uint32_t MCEEditorGetPanelVisibility(MCE_CTX,  const char *panelId, uint32_t defaultValue);
extern "C" void MCEEditorSetPanelVisibility(MCE_CTX,  const char *panelId, uint32_t visible);
extern "C" uint32_t MCEEditorGetHeaderOpen(MCE_CTX,  const char *headerId, uint32_t defaultValue);
extern "C" void MCEEditorSetHeaderOpen(MCE_CTX,  const char *headerId, uint32_t open);
extern "C" void MCEEditorSaveSettings(MCE_CTX);
extern "C" uint32_t MCEEditorGetLastSelectedEntityId(MCE_CTX,  char *buffer, int32_t bufferSize);
extern "C" void MCEEditorSetLastSelectedEntityId(MCE_CTX,  const char *value);
extern "C" int32_t MCEEditorLogCount(MCE_CTX);
extern "C" uint32_t MCEEditorLogEntryAt(MCE_CTX,  int32_t index, int32_t *levelOut, int32_t *categoryOut, double *timestampOut, char *messageBuffer, int32_t messageBufferSize);
extern "C" uint64_t MCEEditorLogRevision(MCE_CTX);
extern "C" void MCEEditorLogClear(MCE_CTX);
extern "C" void MCEEditorRequestQuit(MCE_CTX);

struct LogEntrySnapshot {
    int32_t level = 0;
    int32_t category = 0;
    double timestamp = 0.0;
    std::string message;
    std::string timeLabel;
    std::string label;
};

@interface ImGuiBridge () {
@public
    void *_context;
    bool _ImGuiInitialized;
    bool _ViewportHovered;
    bool _ViewportFocused;
    bool _ViewportUIHovered;
    CGSize _ViewportContentSize;
    CGPoint _ViewportContentOrigin;
    CGPoint _ViewportImageOrigin;
    CGSize _ViewportImageSize;
    bool _GizmoCaptureMouse;
    bool _GizmoCaptureKeyboard;
    bool _ShowRendererPanel;
    bool _ShowSceneHierarchyPanel;
    bool _ShowInspectorPanel;
    bool _ShowContentBrowserPanel;
    bool _ShowViewportPanel;
    bool _ShowProfilingPanel;
    bool _ShowLogsPanel;
    bool _LoadedPanelVisibility;
    char _SelectedEntityId[64];

    uint64_t _LogRevision;
    std::vector<LogEntrySnapshot> _LogEntries;
    std::vector<int32_t> _LogFilteredIndices;
    bool _LogFilterDirty;
    char _LogFilterText[256];
    bool _LogFilterTrace;
    bool _LogFilterInfo;
    bool _LogFilterWarn;
    bool _LogFilterError;
    ImGuiTextFilter _LogFilter;
    bool _LogShowTrace;
    bool _LogShowInfo;
    bool _LogShowWarn;
    bool _LogShowError;
    bool _LogAutoScroll;
}
@end

static void ApplyEditorTheme() {
    ImGuiStyle& style = ImGui::GetStyle();
    style.WindowPadding = ImVec2(12.0f, 10.0f);
    style.FramePadding = ImVec2(8.0f, 6.0f);
    style.ItemSpacing = ImVec2(8.0f, 6.0f);
    style.ItemInnerSpacing = ImVec2(6.0f, 4.0f);
    style.ScrollbarSize = 12.0f;
    style.WindowRounding = 6.0f;
    style.ChildRounding = 6.0f;
    style.FrameRounding = 6.0f;
    style.GrabRounding = 4.0f;
    style.PopupRounding = 6.0f;
    style.TabRounding = 4.0f;
    style.TabBarOverlineSize = 0.0f;
    style.WindowBorderSize = 1.0f;
    style.FrameBorderSize = 1.0f;

    ImVec4* colors = style.Colors;
    const ImVec4 accent = ImVec4(0.58f, 0.46f, 0.72f, 1.0f);
    const ImVec4 accentMuted = ImVec4(0.48f, 0.4f, 0.6f, 1.0f);
    colors[ImGuiCol_Text] = ImVec4(0.92f, 0.92f, 0.94f, 1.0f);
    colors[ImGuiCol_TextDisabled] = ImVec4(0.55f, 0.55f, 0.58f, 1.0f);
    colors[ImGuiCol_WindowBg] = ImVec4(0.11f, 0.11f, 0.12f, 1.0f);
    colors[ImGuiCol_ChildBg] = ImVec4(0.12f, 0.12f, 0.13f, 1.0f);
    colors[ImGuiCol_PopupBg] = ImVec4(0.13f, 0.13f, 0.14f, 1.0f);
    colors[ImGuiCol_Border] = ImVec4(0.24f, 0.24f, 0.26f, 1.0f);
    colors[ImGuiCol_BorderShadow] = ImVec4(0.0f, 0.0f, 0.0f, 0.0f);

    colors[ImGuiCol_FrameBg] = ImVec4(0.18f, 0.18f, 0.2f, 1.0f);
    colors[ImGuiCol_FrameBgHovered] = ImVec4(0.23f, 0.23f, 0.25f, 1.0f);
    colors[ImGuiCol_FrameBgActive] = ImVec4(0.26f, 0.26f, 0.28f, 1.0f);

    colors[ImGuiCol_TitleBg] = ImVec4(0.09f, 0.09f, 0.1f, 1.0f);
    colors[ImGuiCol_TitleBgActive] = ImVec4(0.12f, 0.12f, 0.13f, 1.0f);
    colors[ImGuiCol_TitleBgCollapsed] = ImVec4(0.09f, 0.09f, 0.1f, 1.0f);
    colors[ImGuiCol_MenuBarBg] = ImVec4(0.09f, 0.09f, 0.1f, 1.0f);

    colors[ImGuiCol_Button] = ImVec4(0.2f, 0.2f, 0.22f, 1.0f);
    colors[ImGuiCol_ButtonHovered] = ImVec4(0.28f, 0.27f, 0.3f, 1.0f);
    colors[ImGuiCol_ButtonActive] = ImVec4(0.32f, 0.31f, 0.35f, 1.0f);

    colors[ImGuiCol_Header] = ImVec4(0.2f, 0.2f, 0.22f, 1.0f);
    colors[ImGuiCol_HeaderHovered] = ImVec4(0.28f, 0.27f, 0.3f, 1.0f);
    colors[ImGuiCol_HeaderActive] = ImVec4(0.32f, 0.31f, 0.36f, 1.0f);

    colors[ImGuiCol_Tab] = ImVec4(0.16f, 0.16f, 0.18f, 1.0f);
    colors[ImGuiCol_TabHovered] = ImVec4(0.26f, 0.24f, 0.29f, 1.0f);
    colors[ImGuiCol_TabActive] = ImVec4(0.23f, 0.22f, 0.27f, 1.0f);
    colors[ImGuiCol_TabSelectedOverline] = ImVec4(0.23f, 0.22f, 0.27f, 1.0f);
    colors[ImGuiCol_TabUnfocused] = ImVec4(0.16f, 0.16f, 0.18f, 1.0f);
    colors[ImGuiCol_TabUnfocusedActive] = ImVec4(0.2f, 0.2f, 0.24f, 1.0f);

    colors[ImGuiCol_Separator] = ImVec4(0.22f, 0.22f, 0.24f, 1.0f);
    colors[ImGuiCol_SeparatorHovered] = ImVec4(0.3f, 0.29f, 0.33f, 1.0f);
    colors[ImGuiCol_SeparatorActive] = ImVec4(0.35f, 0.33f, 0.38f, 1.0f);

    colors[ImGuiCol_ScrollbarBg] = ImVec4(0.14f, 0.14f, 0.16f, 1.0f);
    colors[ImGuiCol_ScrollbarGrab] = ImVec4(0.25f, 0.27f, 0.3f, 1.0f);
    colors[ImGuiCol_ScrollbarGrabHovered] = ImVec4(0.3f, 0.32f, 0.35f, 1.0f);
    colors[ImGuiCol_ScrollbarGrabActive] = ImVec4(0.35f, 0.37f, 0.41f, 1.0f);

    colors[ImGuiCol_CheckMark] = accent;
    colors[ImGuiCol_SliderGrab] = accentMuted;
    colors[ImGuiCol_SliderGrabActive] = accent;
    colors[ImGuiCol_ResizeGrip] = ImVec4(0.35f, 0.33f, 0.38f, 0.6f);
    colors[ImGuiCol_ResizeGripHovered] = ImVec4(0.45f, 0.42f, 0.5f, 0.7f);
    colors[ImGuiCol_ResizeGripActive] = accent;
    colors[ImGuiCol_NavHighlight] = accent;
    colors[ImGuiCol_DockingPreview] = ImVec4(accent.x, accent.y, accent.z, 0.35f);
    colors[ImGuiCol_DockingEmptyBg] = ImVec4(0.1f, 0.1f, 0.11f, 1.0f);
    colors[ImGuiCol_TableHeaderBg] = ImVec4(0.17f, 0.17f, 0.2f, 1.0f);
    colors[ImGuiCol_TableBorderStrong] = ImVec4(0.22f, 0.22f, 0.24f, 1.0f);
    colors[ImGuiCol_TableBorderLight] = ImVec4(0.2f, 0.2f, 0.22f, 1.0f);
    colors[ImGuiCol_TableRowBg] = ImVec4(0.12f, 0.12f, 0.13f, 1.0f);
    colors[ImGuiCol_TableRowBgAlt] = ImVec4(0.14f, 0.14f, 0.15f, 1.0f);
    colors[ImGuiCol_TextSelectedBg] = ImVec4(accent.x, accent.y, accent.z, 0.35f);
    colors[ImGuiCol_DragDropTarget] = ImVec4(accent.x, accent.y, accent.z, 0.9f);
    colors[ImGuiCol_NavWindowingHighlight] = ImVec4(accent.x, accent.y, accent.z, 0.7f);
    colors[ImGuiCol_NavWindowingDimBg] = ImVec4(0.1f, 0.1f, 0.12f, 0.7f);
}

static std::string FormatTimestamp(double seconds) {
    if (seconds <= 0.0) { return "-"; }
    std::time_t timeValue = static_cast<std::time_t>(seconds);
    std::tm localTime {};
    localtime_r(&timeValue, &localTime);
    char buffer[64] = {0};
    if (std::strftime(buffer, sizeof(buffer), "%Y-%m-%d %H:%M", &localTime) == 0) {
        return "-";
    }
    return std::string(buffer);
}

static std::string FormatClockTime(double seconds) {
    if (seconds <= 0.0) { return "--:--:--"; }
    std::time_t timeValue = static_cast<std::time_t>(seconds);
    std::tm localTime {};
    localtime_r(&timeValue, &localTime);
    char buffer[32] = {0};
    if (std::strftime(buffer, sizeof(buffer), "%H:%M:%S", &localTime) == 0) {
        return "--:--:--";
    }
    return std::string(buffer);
}

static const char *LogCategoryLabel(int32_t category) {
    switch (category) {
    case 0: return "Core";
    case 1: return "Editor";
    case 2: return "Project";
    case 3: return "Scene";
    case 4: return "Assets";
    case 5: return "Renderer";
    case 6: return "Serialization";
    case 7: return "Input";
    default: return "Other";
    }
}

static void RefreshLogSnapshotIfNeeded(ImGuiBridge *bridge) {
    const uint64_t revision = MCEEditorLogRevision(bridge->_context);
    if (revision == bridge->_LogRevision) { return; }
    bridge->_LogRevision = revision;
    bridge->_LogEntries.clear();
    bridge->_LogFilteredIndices.clear();

    const int32_t count = MCEEditorLogCount(bridge->_context);
    bridge->_LogEntries.reserve(static_cast<size_t>(count));
    for (int32_t i = 0; i < count; ++i) {
        char message[512] = {0};
        int32_t level = 0;
        int32_t category = 0;
        double timestamp = 0.0;
        if (MCEEditorLogEntryAt(bridge->_context, i, &level, &category, &timestamp, message, sizeof(message)) == 0) { continue; }
        LogEntrySnapshot entry;
        entry.level = level;
        entry.category = category;
        entry.timestamp = timestamp;
        entry.message = message;
        entry.timeLabel = FormatClockTime(timestamp);
        entry.label = "[" + entry.timeLabel + "] [" + LogCategoryLabel(category) + "] " + entry.message;
        bridge->_LogEntries.push_back(std::move(entry));
    }

    bridge->_LogFilterDirty = true;
}

static void RebuildLogFilterIfNeeded(ImGuiBridge *bridge, ImGuiTextFilter &filter, bool showTrace, bool showInfo, bool showWarn, bool showError) {
    if (strcmp(bridge->_LogFilterText, filter.InputBuf) != 0) {
        strncpy(bridge->_LogFilterText, filter.InputBuf, sizeof(bridge->_LogFilterText) - 1);
        bridge->_LogFilterText[sizeof(bridge->_LogFilterText) - 1] = 0;
        bridge->_LogFilterDirty = true;
    }

    if (bridge->_LogFilterTrace != showTrace || bridge->_LogFilterInfo != showInfo || bridge->_LogFilterWarn != showWarn || bridge->_LogFilterError != showError) {
        bridge->_LogFilterTrace = showTrace;
        bridge->_LogFilterInfo = showInfo;
        bridge->_LogFilterWarn = showWarn;
        bridge->_LogFilterError = showError;
        bridge->_LogFilterDirty = true;
    }

    if (!bridge->_LogFilterDirty) { return; }
    bridge->_LogFilterDirty = false;
    bridge->_LogFilteredIndices.clear();
    bridge->_LogFilteredIndices.reserve(bridge->_LogEntries.size());

    for (int32_t i = 0; i < static_cast<int32_t>(bridge->_LogEntries.size()); ++i) {
        const auto &entry = bridge->_LogEntries[i];
        const bool levelEnabled = (entry.level == 0 && showTrace) || (entry.level == 1 && showInfo) ||
            (entry.level == 2 && showWarn) || (entry.level == 3 && showError);
        if (!levelEnabled) { continue; }
        if (!filter.PassFilter(entry.message.c_str())) { continue; }
        bridge->_LogFilteredIndices.push_back(i);
    }
}

static void DrawHistorySeries(ImDrawList *drawList,
                              const ImVec2 &min,
                              const ImVec2 &max,
                              const float *values,
                              int count,
                              int offset,
                              float minValue,
                              float maxValue,
                              ImU32 color) {
    if (!values || count < 2) { return; }
    float range = maxValue - minValue;
    if (range <= 0.001f) { range = 1.0f; }
    ImVec2 prev;
    for (int i = 0; i < count; ++i) {
        int index = (offset + i) % count;
        float value = values[index];
        float t = (value - minValue) / range;
        t = std::max(0.0f, std::min(1.0f, t));
        float x = min.x + (static_cast<float>(i) / static_cast<float>(count - 1)) * (max.x - min.x);
        float y = max.y - t * (max.y - min.y);
        ImVec2 point(x, y);
        if (i > 0) {
            drawList->AddLine(prev, point, color, 1.5f);
        }
        prev = point;
    }
}

static void DrawLegendItem(const char *label, const ImVec4 &color) {
    ImGui::PushID(label);
    ImGui::ColorButton("##LegendSwatch",
                       color,
                       ImGuiColorEditFlags_NoTooltip | ImGuiColorEditFlags_NoDragDrop | ImGuiColorEditFlags_NoPicker,
                       ImVec2(10.0f, 10.0f));
    ImGui::PopID();
    ImGui::SameLine();
    ImGui::TextUnformatted(label);
    ImGui::SameLine();
}

static void LoadPanelVisibilityIfNeeded(ImGuiBridge *bridge) {
    if (bridge->_LoadedPanelVisibility) { return; }
    bridge->_LoadedPanelVisibility = true;

    bridge->_ShowRendererPanel = MCEEditorGetPanelVisibility(bridge->_context, "Renderer", 1) != 0;
    bridge->_ShowSceneHierarchyPanel = MCEEditorGetPanelVisibility(bridge->_context, "SceneHierarchy", 1) != 0;
    bridge->_ShowInspectorPanel = MCEEditorGetPanelVisibility(bridge->_context, "Inspector", 1) != 0;
    bridge->_ShowContentBrowserPanel = MCEEditorGetPanelVisibility(bridge->_context, "ContentBrowser", 1) != 0;
    bridge->_ShowViewportPanel = MCEEditorGetPanelVisibility(bridge->_context, "Viewport", 1) != 0;
    bridge->_ShowProfilingPanel = MCEEditorGetPanelVisibility(bridge->_context, "Profiling", 0) != 0;
    bridge->_ShowLogsPanel = MCEEditorGetPanelVisibility(bridge->_context, "Logs", 1) != 0;

    char selectedBuffer[64] = {0};
    if (MCEEditorGetLastSelectedEntityId(bridge->_context, selectedBuffer, sizeof(selectedBuffer)) != 0) {
        strncpy(bridge->_SelectedEntityId, selectedBuffer, sizeof(bridge->_SelectedEntityId) - 1);
        bridge->_SelectedEntityId[sizeof(bridge->_SelectedEntityId) - 1] = 0;
    }
}

static void SetPanelVisibility(ImGuiBridge *bridge, const char *panelId, bool value) {
    MCEEditorSetPanelVisibility(bridge->_context, panelId, value ? 1 : 0);
}

struct PanelMenuEntry {
    const char *label = nullptr;
    const char *id = nullptr;
    bool *visible = nullptr;
};

static void DrawPanelMenuItem(ImGuiBridge *bridge, const PanelMenuEntry &entry) {
    if (!entry.label || !entry.id || !entry.visible) { return; }
    if (ImGui::MenuItem(entry.label, nullptr, entry.visible)) {
        SetPanelVisibility(bridge, entry.id, *entry.visible);
    }
}

static void DrawLogsPanel(ImGuiBridge *bridge, bool *isOpen) {
    if (!isOpen || !*isOpen) { return; }
    ImGui::Begin("Logs", isOpen);

    RefreshLogSnapshotIfNeeded(bridge);

    if (ImGui::Button("Clear")) {
        MCEEditorLogClear(bridge->_context);
    }
    ImGui::SameLine();
    if (ImGui::Button("Copy")) {
        std::string output;
        RebuildLogFilterIfNeeded(bridge, bridge->_LogFilter, bridge->_LogShowTrace, bridge->_LogShowInfo, bridge->_LogShowWarn, bridge->_LogShowError);
        output.reserve(static_cast<size_t>(bridge->_LogFilteredIndices.size()) * 80);
        for (int32_t index : bridge->_LogFilteredIndices) {
            if (index < 0 || index >= static_cast<int32_t>(bridge->_LogEntries.size())) { continue; }
            const auto &entry = bridge->_LogEntries[index];
            output += entry.label;
            output += "\n";
        }
        ImGui::SetClipboardText(output.c_str());
    }
    ImGui::SameLine();
    ImGui::Checkbox("Auto-scroll", &bridge->_LogAutoScroll);
    ImGui::SameLine();
    bridge->_LogFilter.Draw("Filter", 200.0f);

    ImGui::Separator();
    ImGui::Checkbox("Trace", &bridge->_LogShowTrace);
    ImGui::SameLine();
    ImGui::Checkbox("Info", &bridge->_LogShowInfo);
    ImGui::SameLine();
    ImGui::Checkbox("Warn", &bridge->_LogShowWarn);
    ImGui::SameLine();
    ImGui::Checkbox("Error", &bridge->_LogShowError);

    ImGui::Separator();
    ImGui::BeginChild("LogsScroll", ImVec2(0, 0), false, ImGuiWindowFlags_AlwaysVerticalScrollbar);

    RebuildLogFilterIfNeeded(bridge, bridge->_LogFilter, bridge->_LogShowTrace, bridge->_LogShowInfo, bridge->_LogShowWarn, bridge->_LogShowError);

    const int32_t filteredCount = static_cast<int32_t>(bridge->_LogFilteredIndices.size());
    ImGuiListClipper clipper;
    clipper.Begin(filteredCount);
    while (clipper.Step()) {
        for (int32_t row = clipper.DisplayStart; row < clipper.DisplayEnd; ++row) {
            const int32_t entryIndex = bridge->_LogFilteredIndices[row];
            if (entryIndex < 0 || entryIndex >= static_cast<int32_t>(bridge->_LogEntries.size())) { continue; }
            const auto &entry = bridge->_LogEntries[entryIndex];
            ImVec4 color = ImVec4(0.82f, 0.82f, 0.86f, 1.0f);
            if (entry.level == 0) {
                color = ImVec4(0.55f, 0.6f, 0.65f, 1.0f);
            } else if (entry.level == 2) {
                color = ImVec4(0.95f, 0.7f, 0.2f, 1.0f);
            } else if (entry.level == 3) {
                color = ImVec4(0.95f, 0.4f, 0.35f, 1.0f);
            }
            ImGui::PushStyleColor(ImGuiCol_Text, color);
            bool clicked = ImGui::Selectable(entry.label.c_str(), false, ImGuiSelectableFlags_SpanAllColumns);
            ImGui::PopStyleColor();
            if (clicked) {
                ImGui::SetClipboardText(entry.message.c_str());
            }
        }
    }

    if (bridge->_LogAutoScroll && ImGui::GetScrollY() >= ImGui::GetScrollMaxY() - 4.0f) {
        ImGui::SetScrollHereY(1.0f);
    }

    ImGui::EndChild();
    ImGui::End();
}

static void DrawProfilingPanel(void *context, bool *isOpen) {
    if (!isOpen || !*isOpen) { return; }
    ImGui::Begin("Profiling", isOpen);

    float frameMs = MCERendererGetFrameMs(context);
    float gpuMs = MCERendererGetGpuMs(context);
    static float frameHistory[120] = {0};
    static float updateHistory[120] = {0};
    static float renderHistory[120] = {0};
    static float postHistory[120] = {0};
    static int frameOffset = 0;
    const float updateMs = MCERendererGetUpdateMs(context);
    const float renderMs = MCERendererGetRenderMs(context);
    const float postMs = MCERendererGetBloomMs(context) + MCERendererGetCompositeMs(context) + MCERendererGetOverlaysMs(context);
    frameHistory[frameOffset] = frameMs;
    updateHistory[frameOffset] = updateMs;
    renderHistory[frameOffset] = renderMs;
    postHistory[frameOffset] = postMs;
    frameOffset = (frameOffset + 1) % IM_ARRAYSIZE(frameHistory);

    static bool autoRange = true;
    static float rangeMin = 0.0f;
    static float rangeMax = 40.0f;
    ImGui::TextUnformatted("Frame History");
    ImGui::SameLine();
    ImGui::TextDisabled("(ms)");
    DrawLegendItem("Frame", ImVec4(0.74f, 0.64f, 0.84f, 1.0f));
    DrawLegendItem("Update", ImVec4(0.36f, 0.62f, 0.44f, 1.0f));
    DrawLegendItem("Render", ImVec4(0.78f, 0.55f, 0.38f, 1.0f));
    DrawLegendItem("Post", ImVec4(0.55f, 0.48f, 0.72f, 1.0f));
    ImGui::NewLine();
    ImGui::Checkbox("Auto Range", &autoRange);

    float minValue = rangeMin;
    float maxValue = rangeMax;
    if (autoRange) {
        minValue = frameHistory[0];
        maxValue = frameHistory[0];
        for (int i = 1; i < IM_ARRAYSIZE(frameHistory); ++i) {
            minValue = std::min(minValue, frameHistory[i]);
            minValue = std::min(minValue, updateHistory[i]);
            minValue = std::min(minValue, renderHistory[i]);
            minValue = std::min(minValue, postHistory[i]);
            maxValue = std::max(maxValue, frameHistory[i]);
            maxValue = std::max(maxValue, updateHistory[i]);
            maxValue = std::max(maxValue, renderHistory[i]);
            maxValue = std::max(maxValue, postHistory[i]);
        }
        maxValue = std::max(minValue + 5.0f, maxValue);
    } else {
        ImGui::SetNextItemWidth(120.0f);
        ImGui::DragFloat("Min##FrameRange", &rangeMin, 0.5f, 0.0f, rangeMax - 1.0f, "%.1f");
        ImGui::SameLine();
        ImGui::SetNextItemWidth(120.0f);
        ImGui::DragFloat("Max##FrameRange", &rangeMax, 0.5f, rangeMin + 1.0f, 200.0f, "%.1f");
        minValue = rangeMin;
        maxValue = rangeMax;
    }

    ImVec2 graphSize(ImGui::GetContentRegionAvail().x, 110.0f);
    ImVec2 graphMin = ImGui::GetCursorScreenPos();
    ImGui::InvisibleButton("##FrameHistoryGraph", graphSize);
    ImVec2 graphMax(graphMin.x + graphSize.x, graphMin.y + graphSize.y);

    ImDrawList *drawList = ImGui::GetWindowDrawList();
    drawList->AddRectFilled(graphMin, graphMax, IM_COL32(24, 24, 27, 255), 4.0f);
    drawList->AddRect(graphMin, graphMax, IM_COL32(60, 60, 66, 255), 4.0f);

    const ImU32 frameColor = IM_COL32(189, 164, 214, 255);
    const ImU32 updateColor = IM_COL32(92, 158, 112, 255);
    const ImU32 renderColor = IM_COL32(198, 140, 98, 255);
    const ImU32 postColor = IM_COL32(140, 122, 183, 255);
    DrawHistorySeries(drawList, graphMin, graphMax, frameHistory, IM_ARRAYSIZE(frameHistory), frameOffset, minValue, maxValue, frameColor);
    DrawHistorySeries(drawList, graphMin, graphMax, updateHistory, IM_ARRAYSIZE(updateHistory), frameOffset, minValue, maxValue, updateColor);
    DrawHistorySeries(drawList, graphMin, graphMax, renderHistory, IM_ARRAYSIZE(renderHistory), frameOffset, minValue, maxValue, renderColor);
    DrawHistorySeries(drawList, graphMin, graphMax, postHistory, IM_ARRAYSIZE(postHistory), frameOffset, minValue, maxValue, postColor);

    char maxLabel[32] = {0};
    char minLabel[32] = {0};
    snprintf(maxLabel, sizeof(maxLabel), "%.1f ms", maxValue);
    snprintf(minLabel, sizeof(minLabel), "%.1f ms", minValue);
    drawList->AddText(ImVec2(graphMin.x + 6.0f, graphMin.y + 4.0f), IM_COL32(180, 180, 185, 255), maxLabel);
    drawList->AddText(ImVec2(graphMin.x + 6.0f, graphMax.y - 18.0f), IM_COL32(180, 180, 185, 255), minLabel);

    ImGui::Separator();
    ImGui::Text("Frame: %.2f ms", frameMs);
    ImGui::Text("GPU:   %.2f ms", gpuMs);

    ImGui::Separator();
    ImGui::TextUnformatted("CPU Breakdown");
    ImGui::Text("Update:     %.2f ms", MCERendererGetUpdateMs(context));
    ImGui::Text("Scene:      %.2f ms", MCERendererGetSceneMs(context));
    ImGui::Text("Render:     %.2f ms", MCERendererGetRenderMs(context));
    ImGui::Text("Bloom:      %.2f ms", MCERendererGetBloomMs(context));
    ImGui::Text("  Extract:  %.2f ms", MCERendererGetBloomExtractMs(context));
    ImGui::Text("  Downsample: %.2f ms", MCERendererGetBloomDownsampleMs(context));
    ImGui::Text("  Blur:     %.2f ms", MCERendererGetBloomBlurMs(context));
    ImGui::Text("Composite:  %.2f ms", MCERendererGetCompositeMs(context));
    ImGui::Text("Overlays:   %.2f ms", MCERendererGetOverlaysMs(context));
    ImGui::Text("Present:    %.2f ms", MCERendererGetPresentMs(context));

    ImGui::End();
}

static void EnsureImGuiKeyResponder(NSView *view) {
    if (!view || !view.window) { return; }
    Class responderClass = NSClassFromString(@"KeyEventResponder");
    if (!responderClass) { return; }
    for (NSView *subview in view.subviews) {
        if ([subview isKindOfClass:responderClass]) {
            if (view.window.firstResponder != subview) {
                [view.window makeFirstResponder:subview];
            }
            return;
        }
    }
}

@implementation ImGuiBridge

- (instancetype)initWithContext:(void *)context {
    self = [super init];
    if (self) {
        _context = context;
        _ImGuiInitialized = false;
        _ViewportHovered = false;
        _ViewportFocused = false;
        _ViewportUIHovered = false;
        _ViewportContentSize = {0, 0};
        _ViewportContentOrigin = {0, 0};
        _ViewportImageOrigin = {0, 0};
        _ViewportImageSize = {0, 0};
        _GizmoCaptureMouse = false;
        _GizmoCaptureKeyboard = false;
        _ShowRendererPanel = true;
        _ShowSceneHierarchyPanel = true;
        _ShowInspectorPanel = true;
        _ShowContentBrowserPanel = true;
        _ShowViewportPanel = true;
        _ShowProfilingPanel = false;
        _ShowLogsPanel = true;
        _LoadedPanelVisibility = false;
        _SelectedEntityId[0] = 0;
        _LogRevision = 0;
        _LogEntries.clear();
        _LogFilteredIndices.clear();
        _LogFilterDirty = true;
        _LogFilterText[0] = 0;
        _LogFilterTrace = true;
        _LogFilterInfo = true;
        _LogFilterWarn = true;
        _LogFilterError = true;
        _LogShowTrace = true;
        _LogShowInfo = true;
        _LogShowWarn = true;
        _LogShowError = true;
        _LogAutoScroll = true;
    }
    return self;
}

- (void)setupWithView:(MTKView *)view {
    if (_ImGuiInitialized) { return; }
    _ImGuiInitialized = true;

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO();
    (void)io;

    // Store ImGui config in Application Support so it persists with or without sandbox.
    char iniPathBuffer[512] = {0};
    if (MCEEditorGetImGuiIniPath(_context, iniPathBuffer, sizeof(iniPathBuffer)) != 0) {
        io.IniFilename = strdup(iniPathBuffer);
    }

    // Nice defaults
    io.ConfigFlags |= ImGuiConfigFlags_DockingEnable;
    io.ConfigFlags |= ImGuiConfigFlags_ViewportsEnable;
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;
    io.ConfigInputTrickleEventQueue = false;

    ImGui::StyleColorsDark();
    ApplyEditorTheme();
    ImGuiStyle& style = ImGui::GetStyle();
    if (io.ConfigFlags & ImGuiConfigFlags_ViewportsEnable) {
        style.Colors[ImGuiCol_WindowBg].w = 1.0f;
    }

    // Backends
    // OS X backend needs the NSView
    ImGui_ImplOSX_Init(view);
    // Metal backend now only needs the device
    ImGui_ImplMetal_Init(view.device);

    // Prefer the system UI font for macOS.
    const char *fontCandidates[] = {
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/SFNSDisplay.ttf",
        "/System/Library/Fonts/SFNSRounded.ttf"
    };
    for (const char *path : fontCandidates) {
        NSString *fontPath = [NSString stringWithUTF8String:path];
        if ([[NSFileManager defaultManager] fileExistsAtPath:fontPath]) {
            ImFont *font = io.Fonts->AddFontFromFileTTF(path, 14.5f);
            if (font != nullptr) {
                io.FontDefault = font;
                break;
            }
        }
    }
}

- (void)newFrameWithView:(MTKView *)view deltaTime:(float)dt {
    if (!_ImGuiInitialized) { [self setupWithView:view]; }
    EnsureImGuiKeyResponder(view);

    ImGuiIO& io = ImGui::GetIO();
    io.DeltaTime = (dt > 0.0f) ? dt : (1.0f / 60.0f);

    ImGui_ImplMetal_NewFrame(view.currentRenderPassDescriptor);
    ImGui_ImplOSX_NewFrame(view);
    ImGui::NewFrame();
}

- (void)buildUIWithSceneTexture:(id<MTLTexture> _Nullable)sceneTexture
                 previewTexture:(id<MTLTexture> _Nullable)previewTexture {
    static char _AlertMessage[512] = {0};
    _GizmoCaptureMouse = false;
    _GizmoCaptureKeyboard = false;
    if (_AlertMessage[0] == 0) {
        if (MCEEditorPopNextAlert(_context, _AlertMessage, sizeof(_AlertMessage)) != 0) {
            ImGui::OpenPopup("Error");
        }
    }

    LoadPanelVisibilityIfNeeded(self);

    if (ImGui::BeginPopupModal("Error", nullptr, ImGuiWindowFlags_AlwaysAutoResize)) {
        ImGui::TextWrapped("%s", _AlertMessage);
        if (ImGui::Button("OK")) {
            _AlertMessage[0] = 0;
            ImGui::CloseCurrentPopup();
        }
        ImGui::EndPopup();
    }

    // Dockspace host window (fills main viewport)
    ImGuiViewport* vp = ImGui::GetMainViewport();
    ImGui::SetNextWindowPos(vp->Pos);
    ImGui::SetNextWindowSize(vp->Size);
    ImGui::SetNextWindowViewport(vp->ID);

    ImGuiWindowFlags hostFlags =
        ImGuiWindowFlags_NoTitleBar |
        ImGuiWindowFlags_NoCollapse |
        ImGuiWindowFlags_NoResize |
        ImGuiWindowFlags_NoMove |
        ImGuiWindowFlags_NoBringToFrontOnFocus |
        ImGuiWindowFlags_NoNavFocus |
        ImGuiWindowFlags_MenuBar;

    ImGui::PushStyleVar(ImGuiStyleVar_WindowRounding, 0.0f);
    ImGui::PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0.0f);
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(0,0));

    ImGui::Begin("DockSpaceHost", nullptr, hostFlags);

    ImGuiID dockspaceId = ImGui::GetID("MainDockspace");
    ImGui::DockSpace(dockspaceId, ImVec2(0,0), ImGuiDockNodeFlags_PassthruCentralNode);

    // Menu bar
    EditorUI::PushMenuBarStyle();
    if (ImGui::BeginMenuBar()) {
        if (ImGui::BeginMenu("File")) {
            EditorUI::PushMenuPopupStyle();
            if (ImGui::MenuItem("New Project...")) {
                MCEProjectNew(_context);
            }
            if (ImGui::MenuItem("Open Project...")) {
                MCEProjectOpen(_context);
            }
            bool hasProject = MCEProjectHasOpen(_context) != 0;
            if (ImGui::MenuItem("Save", nullptr, false, hasProject)) {
                MCEProjectSaveAll(_context);
            }
            int32_t recentCount = MCEProjectRecentCount(_context);
            if (ImGui::BeginMenu("Recent Projects", recentCount > 0)) {
                if (recentCount == 0) {
                    ImGui::MenuItem("No recent projects", nullptr, false, false);
                }
                for (int32_t i = 0; i < recentCount && i < 10; ++i) {
                    char pathBuffer[512] = {0};
                    if (MCEProjectRecentPathAt(_context, i, pathBuffer, sizeof(pathBuffer)) <= 0) { continue; }
                    std::string path = pathBuffer;
                    size_t slash = path.find_last_of('/');
                    std::string name = (slash == std::string::npos) ? path : path.substr(slash + 1);
                    std::string label = name + "##recent" + std::to_string(i);
                    if (ImGui::MenuItem(label.c_str())) {
                        MCEProjectOpenRecent(_context, pathBuffer);
                    }
                }
                ImGui::EndMenu();
            }
            ImGui::Separator();
            if (ImGui::MenuItem("Exit")) {
                MCEEditorRequestQuit(_context);
            }
            EditorUI::PopMenuPopupStyle();
            ImGui::EndMenu();
        }
        if (ImGui::BeginMenu("View")) {
            EditorUI::PushMenuPopupStyle();
            DrawPanelMenuItem(self, { "Scene Hierarchy", "SceneHierarchy", &_ShowSceneHierarchyPanel });
            DrawPanelMenuItem(self, { "Inspector", "Inspector", &_ShowInspectorPanel });
            DrawPanelMenuItem(self, { "Content Browser", "ContentBrowser", &_ShowContentBrowserPanel });
            DrawPanelMenuItem(self, { "Renderer", "Renderer", &_ShowRendererPanel });
            DrawPanelMenuItem(self, { "Profiling", "Profiling", &_ShowProfilingPanel });
            DrawPanelMenuItem(self, { "Logs", "Logs", &_ShowLogsPanel });
            DrawPanelMenuItem(self, { "Viewport", "Viewport", &_ShowViewportPanel });
            EditorUI::PopMenuPopupStyle();
            ImGui::EndMenu();
        }
        ImGui::EndMenuBar();
    }
    EditorUI::PopMenuBarStyle();

    ImGui::PopStyleVar(3);

    if (MCEProjectNeedsModal(_context) != 0) {
        ImGui::OpenPopup("Create or Open Project");
    }
    if (ImGui::BeginPopupModal("Create or Open Project", nullptr, ImGuiWindowFlags_AlwaysAutoResize)) {
        ImGui::TextUnformatted("Select a project to get started.");
        if (MCEProjectHasOpen(_context) != 0) {
            if (ImGui::Button("Continue with Loaded Project")) {
                MCEProjectDismissModal(_context);
                ImGui::CloseCurrentPopup();
            }
            ImGui::Separator();
        }

        if (ImGui::Button("Open Other Project...")) {
            MCEProjectOpen(_context);
        }
        ImGui::SameLine();
        if (ImGui::Button("New Project...")) {
            MCEProjectNew(_context);
        }
        ImGui::Separator();

        static int32_t _SelectedProjectIndex = -1;
        static char _SelectedProjectPath[512] = {0};
        static bool _ConfirmDeleteProjectOpen = false;

        ImGui::TextUnformatted("Projects");
        if (ImGui::BeginChild("ProjectList", ImVec2(520, 240), true)) {
            int32_t projectCount = MCEProjectListCount(_context);
            if (projectCount <= 0) {
                ImGui::TextUnformatted("No projects found in the Projects folder.");
            }
            if (ImGui::BeginTable("ProjectTable", 3, ImGuiTableFlags_RowBg | ImGuiTableFlags_BordersInnerV | ImGuiTableFlags_SizingStretchProp)) {
                ImGui::TableSetupColumn("Name", ImGuiTableColumnFlags_WidthStretch);
                ImGui::TableSetupColumn("Path", ImGuiTableColumnFlags_WidthStretch);
                ImGui::TableSetupColumn("Modified", ImGuiTableColumnFlags_WidthFixed, 140.0f);
                ImGui::TableHeadersRow();

                for (int32_t i = 0; i < projectCount; ++i) {
                    char nameBuffer[256] = {0};
                    char pathBuffer[512] = {0};
                    double modified = 0.0;
                    if (MCEProjectListAt(_context, i, nameBuffer, sizeof(nameBuffer), pathBuffer, sizeof(pathBuffer), &modified) == 0) {
                        continue;
                    }
                    ImGui::TableNextRow();
                    ImGui::TableSetColumnIndex(0);
                    ImGui::PushID(i);
                    bool selected = (_SelectedProjectIndex == i);
                    if (ImGui::Selectable(nameBuffer, selected, ImGuiSelectableFlags_SpanAllColumns)) {
                        _SelectedProjectIndex = i;
                        strncpy(_SelectedProjectPath, pathBuffer, sizeof(_SelectedProjectPath) - 1);
                        _SelectedProjectPath[sizeof(_SelectedProjectPath) - 1] = 0;
                    }
                    if (ImGui::IsItemHovered() && ImGui::IsMouseDoubleClicked(0)) {
                        if (MCEProjectOpenAtPath(_context, pathBuffer) != 0) {
                            MCEProjectDismissModal(_context);
                            ImGui::CloseCurrentPopup();
                        }
                    }
                    ImGui::TableSetColumnIndex(1);
                    ImGui::TextUnformatted(pathBuffer);
                    ImGui::TableSetColumnIndex(2);
                    std::string timeText = FormatTimestamp(modified);
                    ImGui::TextUnformatted(timeText.c_str());
                    ImGui::PopID();
                }
                ImGui::EndTable();
            }
        }
        ImGui::EndChild();

        bool hasSelection = _SelectedProjectIndex >= 0 && _SelectedProjectPath[0] != 0;
        if (ImGui::Button("Open Selected") && hasSelection) {
            if (MCEProjectOpenAtPath(_context, _SelectedProjectPath) != 0) {
                MCEProjectDismissModal(_context);
                ImGui::CloseCurrentPopup();
            }
        }
        ImGui::SameLine();
        ImGui::BeginDisabled(!hasSelection);
        if (ImGui::Button("Delete")) {
            _ConfirmDeleteProjectOpen = true;
        }
        ImGui::EndDisabled();
        EditorUI::ConfirmModal("Confirm Delete Project",
                               &_ConfirmDeleteProjectOpen,
                               "Delete the selected project? This will remove it from disk.",
                               "Delete",
                               "Cancel",
                               [&]() {
            MCEProjectDeleteAtPath(_context, _SelectedProjectPath);
            _SelectedProjectIndex = -1;
            _SelectedProjectPath[0] = 0;
        });

        ImGui::EndPopup();
    }

    // --- Panels ---
    bool rendererOpen = _ShowRendererPanel;
    if (rendererOpen) {
        ImGuiRendererPanelDraw(_context, &rendererOpen);
        if (rendererOpen != _ShowRendererPanel) {
            _ShowRendererPanel = rendererOpen;
            SetPanelVisibility(self, "Renderer", _ShowRendererPanel);
        }
    }

    bool hierarchyOpen = _ShowSceneHierarchyPanel;
    if (hierarchyOpen) {
        ImGuiSceneHierarchyPanelDraw(_context, &hierarchyOpen, _SelectedEntityId, sizeof(_SelectedEntityId));
        if (hierarchyOpen != _ShowSceneHierarchyPanel) {
            _ShowSceneHierarchyPanel = hierarchyOpen;
            SetPanelVisibility(self, "SceneHierarchy", _ShowSceneHierarchyPanel);
        }
    }

    bool inspectorOpen = _ShowInspectorPanel;
    if (inspectorOpen) {
        ImGuiInspectorPanelDraw(_context, &inspectorOpen, _SelectedEntityId);
        if (inspectorOpen != _ShowInspectorPanel) {
            _ShowInspectorPanel = inspectorOpen;
            SetPanelVisibility(self, "Inspector", _ShowInspectorPanel);
        }
    }

    bool contentOpen = _ShowContentBrowserPanel;
    if (contentOpen) {
        ImGuiContentBrowserPanelDraw(_context, &contentOpen);
        if (contentOpen != _ShowContentBrowserPanel) {
            _ShowContentBrowserPanel = contentOpen;
            SetPanelVisibility(self, "ContentBrowser", _ShowContentBrowserPanel);
        }
    }

    bool profilingOpen = _ShowProfilingPanel;
    if (profilingOpen) {
        DrawProfilingPanel(_context, &profilingOpen);
        if (profilingOpen != _ShowProfilingPanel) {
            _ShowProfilingPanel = profilingOpen;
            SetPanelVisibility(self, "Profiling", _ShowProfilingPanel);
        }
    }

    bool logsOpen = _ShowLogsPanel;
    if (logsOpen) {
        DrawLogsPanel(self, &logsOpen);
        if (logsOpen != _ShowLogsPanel) {
            _ShowLogsPanel = logsOpen;
            SetPanelVisibility(self, "Logs", _ShowLogsPanel);
        }
    }

    if (_ShowViewportPanel) {
        _ViewportUIHovered = false;
        ImGuiViewportPanelDraw(_context,
                               sceneTexture,
                               previewTexture,
                               _SelectedEntityId,
                               &_ViewportHovered,
                               &_ViewportFocused,
                               &_ViewportUIHovered,
                               &_ViewportContentSize,
                               &_ViewportContentOrigin,
                               &_ViewportImageOrigin,
                               &_ViewportImageSize);
    } else {
        _ViewportUIHovered = false;
    }

    ImGui::End(); // DockSpaceHost
}

- (void)renderWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
            renderPassDescriptor:(MTLRenderPassDescriptor *)renderPassDescriptor {

    ImGui::Render();

    id<MTLRenderCommandEncoder> encoder =
        [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    if (!encoder) { return; }

    // Draw ImGui into the active render target
    ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), commandBuffer, encoder);

    [encoder endEncoding];

    ImGuiIO& io = ImGui::GetIO();
    if (io.ConfigFlags & ImGuiConfigFlags_ViewportsEnable) {
        ImGui::UpdatePlatformWindows();
        ImGui::RenderPlatformWindowsDefault();
    }
}

- (bool)wantsCaptureMouse {
    if (!_ImGuiInitialized) { return false; }
    ImGuiIO& io = ImGui::GetIO();
    return io.WantCaptureMouse || _GizmoCaptureMouse;
}

- (bool)wantsCaptureKeyboard {
    if (!_ImGuiInitialized) { return false; }
    ImGuiIO& io = ImGui::GetIO();
    return io.WantCaptureKeyboard || _GizmoCaptureKeyboard;
}

- (bool)viewportIsHovered {
    return _ViewportHovered;
}

- (bool)viewportIsFocused {
    return _ViewportFocused;
}

- (bool)viewportIsUIHovered {
    return _ViewportUIHovered;
}

- (CGSize)viewportContentSize {
    return _ViewportContentSize;
}

- (CGPoint)viewportContentOrigin {
    return _ViewportContentOrigin;
}

- (CGPoint)viewportImageOrigin {
    return _ViewportImageOrigin;
}

- (CGSize)viewportImageSize {
    return _ViewportImageSize;
}

- (CGPoint)mousePosition {
    if (!_ImGuiInitialized) { return CGPointZero; }
    ImVec2 mousePos = ImGui::GetMousePos();
    return CGPointMake(mousePos.x, mousePos.y);
}

- (void)setSelectedEntityId:(NSString *)value {
    const char *utf8 = value != nil ? value.UTF8String : "";
    if (!utf8) { utf8 = ""; }
    strncpy(_SelectedEntityId, utf8, sizeof(_SelectedEntityId) - 1);
    _SelectedEntityId[sizeof(_SelectedEntityId) - 1] = 0;
    MCEEditorSetLastSelectedEntityId(_context, _SelectedEntityId);
}

- (void)setGizmoCaptureMouse:(bool)wantsMouse keyboard:(bool)wantsKeyboard {
    _GizmoCaptureMouse = wantsMouse;
    _GizmoCaptureKeyboard = wantsKeyboard;
}

@end
