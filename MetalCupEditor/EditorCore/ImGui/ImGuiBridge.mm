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
#import "../Bridge/RendererSettingsBridge.h"
#import "../../EditorUI/Widgets/UIWidgets.h"
#import <Cocoa/Cocoa.h>
#include <algorithm>
#include <cstring>
#include <ctime>
#include <string>
#include <vector>
#include <sys/stat.h>


extern "C" void MCEProjectNew(void);
extern "C" void MCEProjectOpen(void);
extern "C" void MCEProjectSave(void);
extern "C" void MCEProjectSaveAs(void);
extern "C" void MCEProjectSaveAll(void);
extern "C" uint32_t MCEProjectHasOpen(void);
extern "C" uint32_t MCEProjectNeedsModal(void);
extern "C" int32_t MCEProjectRecentCount(void);
extern "C" int32_t MCEProjectRecentPathAt(int32_t index, char *buffer, int32_t bufferSize);
extern "C" void MCEProjectOpenRecent(const char *path);
extern "C" int32_t MCEProjectListCount(void);
extern "C" uint32_t MCEProjectListAt(int32_t index,
                                     char *nameBuffer, int32_t nameBufferSize,
                                     char *pathBuffer, int32_t pathBufferSize,
                                     double *modifiedOut);
extern "C" uint32_t MCEProjectOpenAtPath(const char *path);
extern "C" uint32_t MCEProjectDeleteAtPath(const char *path);
extern "C" void MCESceneSave(void);
extern "C" void MCESceneSaveAs(void);
extern "C" void MCESceneLoad(void);
extern "C" void MCEScenePlay(void);
extern "C" void MCESceneStop(void);
extern "C" void MCEScenePause(void);
extern "C" void MCESceneResume(void);
extern "C" uint32_t MCESceneIsPlaying(void);
extern "C" uint32_t MCESceneIsPaused(void);
extern "C" uint32_t MCESceneIsDirty(void);
extern "C" uint32_t MCEEditorPopNextAlert(char *buffer, int32_t bufferSize);
extern "C" uint32_t MCEEditorGetImGuiIniPath(char *buffer, int32_t bufferSize);
extern "C" uint32_t MCEEditorGetPanelVisibility(const char *panelId, uint32_t defaultValue);
extern "C" void MCEEditorSetPanelVisibility(const char *panelId, uint32_t visible);
extern "C" uint32_t MCEEditorGetHeaderOpen(const char *headerId, uint32_t defaultValue);
extern "C" void MCEEditorSetHeaderOpen(const char *headerId, uint32_t open);
extern "C" void MCEEditorSaveSettings(void);
extern "C" uint32_t MCEEditorGetLastSelectedEntityId(char *buffer, int32_t bufferSize);
extern "C" void MCEEditorSetLastSelectedEntityId(const char *value);
extern "C" int32_t MCEEditorLogCount(void);
extern "C" uint32_t MCEEditorLogEntryAt(int32_t index, int32_t *levelOut, int32_t *categoryOut, double *timestampOut, char *messageBuffer, int32_t messageBufferSize);
extern "C" uint64_t MCEEditorLogRevision(void);
extern "C" void MCEEditorLogClear(void);
extern "C" void MCEEditorRequestQuit(void);

static bool g_ImGuiInitialized = false;
static bool g_ViewportHovered = false;
static bool g_ViewportFocused = false;
static CGSize g_ViewportContentSize = {0, 0};
static CGPoint g_ViewportContentOrigin = {0, 0};
static bool g_ShowRendererPanel = true;
static bool g_ShowSceneHierarchyPanel = true;
static bool g_ShowInspectorPanel = true;
static bool g_ShowContentBrowserPanel = true;
static bool g_ShowViewportPanel = true;
static bool g_ShowProfilingPanel = false;
static bool g_ShowLogsPanel = true;
static bool g_LoadedPanelVisibility = false;
static char g_SelectedEntityId[64] = {0};

struct LogEntrySnapshot {
    int32_t level = 0;
    int32_t category = 0;
    double timestamp = 0.0;
    std::string message;
    std::string timeLabel;
    std::string label;
};

static uint64_t g_LogRevision = 0;
static std::vector<LogEntrySnapshot> g_LogEntries;
static std::vector<int32_t> g_LogFilteredIndices;
static bool g_LogFilterDirty = true;
static char g_LogFilterText[256] = {0};
static bool g_LogFilterTrace = true;
static bool g_LogFilterInfo = true;
static bool g_LogFilterWarn = true;
static bool g_LogFilterError = true;

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
    case 0: return "Editor";
    case 1: return "Project";
    case 2: return "Scene";
    case 3: return "Assets";
    case 4: return "Renderer";
    case 5: return "Serialization";
    case 6: return "Input";
    default: return "Other";
    }
}

static void RefreshLogSnapshotIfNeeded() {
    const uint64_t revision = MCEEditorLogRevision();
    if (revision == g_LogRevision) { return; }
    g_LogRevision = revision;
    g_LogEntries.clear();
    g_LogFilteredIndices.clear();

    const int32_t count = MCEEditorLogCount();
    g_LogEntries.reserve(static_cast<size_t>(count));
    for (int32_t i = 0; i < count; ++i) {
        char message[512] = {0};
        int32_t level = 0;
        int32_t category = 0;
        double timestamp = 0.0;
        if (MCEEditorLogEntryAt(i, &level, &category, &timestamp, message, sizeof(message)) == 0) { continue; }
        LogEntrySnapshot entry;
        entry.level = level;
        entry.category = category;
        entry.timestamp = timestamp;
        entry.message = message;
        entry.timeLabel = FormatClockTime(timestamp);
        entry.label = "[" + entry.timeLabel + "] [" + LogCategoryLabel(category) + "] " + entry.message;
        g_LogEntries.push_back(std::move(entry));
    }

    g_LogFilterDirty = true;
}

static void RebuildLogFilterIfNeeded(ImGuiTextFilter &filter, bool showTrace, bool showInfo, bool showWarn, bool showError) {
    if (strcmp(g_LogFilterText, filter.InputBuf) != 0) {
        strncpy(g_LogFilterText, filter.InputBuf, sizeof(g_LogFilterText) - 1);
        g_LogFilterText[sizeof(g_LogFilterText) - 1] = 0;
        g_LogFilterDirty = true;
    }

    if (g_LogFilterTrace != showTrace || g_LogFilterInfo != showInfo || g_LogFilterWarn != showWarn || g_LogFilterError != showError) {
        g_LogFilterTrace = showTrace;
        g_LogFilterInfo = showInfo;
        g_LogFilterWarn = showWarn;
        g_LogFilterError = showError;
        g_LogFilterDirty = true;
    }

    if (!g_LogFilterDirty) { return; }
    g_LogFilterDirty = false;
    g_LogFilteredIndices.clear();
    g_LogFilteredIndices.reserve(g_LogEntries.size());

    for (int32_t i = 0; i < static_cast<int32_t>(g_LogEntries.size()); ++i) {
        const auto &entry = g_LogEntries[i];
        const bool levelEnabled = (entry.level == 0 && showTrace) || (entry.level == 1 && showInfo) ||
            (entry.level == 2 && showWarn) || (entry.level == 3 && showError);
        if (!levelEnabled) { continue; }
        if (!filter.PassFilter(entry.message.c_str())) { continue; }
        g_LogFilteredIndices.push_back(i);
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

static void LoadPanelVisibilityIfNeeded() {
    if (g_LoadedPanelVisibility) { return; }
    g_LoadedPanelVisibility = true;

    g_ShowRendererPanel = MCEEditorGetPanelVisibility("Renderer", 1) != 0;
    g_ShowSceneHierarchyPanel = MCEEditorGetPanelVisibility("SceneHierarchy", 1) != 0;
    g_ShowInspectorPanel = MCEEditorGetPanelVisibility("Inspector", 1) != 0;
    g_ShowContentBrowserPanel = MCEEditorGetPanelVisibility("ContentBrowser", 1) != 0;
    g_ShowViewportPanel = MCEEditorGetPanelVisibility("Viewport", 1) != 0;
    g_ShowProfilingPanel = MCEEditorGetPanelVisibility("Profiling", 0) != 0;
    g_ShowLogsPanel = MCEEditorGetPanelVisibility("Logs", 1) != 0;

    char selectedBuffer[64] = {0};
    if (MCEEditorGetLastSelectedEntityId(selectedBuffer, sizeof(selectedBuffer)) != 0) {
        strncpy(g_SelectedEntityId, selectedBuffer, sizeof(g_SelectedEntityId) - 1);
        g_SelectedEntityId[sizeof(g_SelectedEntityId) - 1] = 0;
    }
}

static void SetPanelVisibility(const char *panelId, bool value) {
    MCEEditorSetPanelVisibility(panelId, value ? 1 : 0);
}

struct PanelMenuEntry {
    const char *label = nullptr;
    const char *id = nullptr;
    bool *visible = nullptr;
};

static void DrawPanelMenuItem(const PanelMenuEntry &entry) {
    if (!entry.label || !entry.id || !entry.visible) { return; }
    if (ImGui::MenuItem(entry.label, nullptr, entry.visible)) {
        SetPanelVisibility(entry.id, *entry.visible);
    }
}

static void DrawLogsPanel(bool *isOpen) {
    if (!isOpen || !*isOpen) { return; }
    ImGui::Begin("Logs", isOpen);

    static ImGuiTextFilter filter;
    static bool showTrace = true;
    static bool showInfo = true;
    static bool showWarn = true;
    static bool showError = true;
    static bool autoScroll = true;

    RefreshLogSnapshotIfNeeded();

    if (ImGui::Button("Clear")) {
        MCEEditorLogClear();
    }
    ImGui::SameLine();
    if (ImGui::Button("Copy")) {
        std::string output;
        RebuildLogFilterIfNeeded(filter, showTrace, showInfo, showWarn, showError);
        output.reserve(static_cast<size_t>(g_LogFilteredIndices.size()) * 80);
        for (int32_t index : g_LogFilteredIndices) {
            if (index < 0 || index >= static_cast<int32_t>(g_LogEntries.size())) { continue; }
            const auto &entry = g_LogEntries[index];
            output += entry.label;
            output += "\n";
        }
        ImGui::SetClipboardText(output.c_str());
    }
    ImGui::SameLine();
    ImGui::Checkbox("Auto-scroll", &autoScroll);
    ImGui::SameLine();
    filter.Draw("Filter", 200.0f);

    ImGui::Separator();
    ImGui::Checkbox("Trace", &showTrace);
    ImGui::SameLine();
    ImGui::Checkbox("Info", &showInfo);
    ImGui::SameLine();
    ImGui::Checkbox("Warn", &showWarn);
    ImGui::SameLine();
    ImGui::Checkbox("Error", &showError);

    ImGui::Separator();
    ImGui::BeginChild("LogsScroll", ImVec2(0, 0), false, ImGuiWindowFlags_AlwaysVerticalScrollbar);

    RebuildLogFilterIfNeeded(filter, showTrace, showInfo, showWarn, showError);

    const int32_t filteredCount = static_cast<int32_t>(g_LogFilteredIndices.size());
    ImGuiListClipper clipper;
    clipper.Begin(filteredCount);
    while (clipper.Step()) {
        for (int32_t row = clipper.DisplayStart; row < clipper.DisplayEnd; ++row) {
            const int32_t entryIndex = g_LogFilteredIndices[row];
            if (entryIndex < 0 || entryIndex >= static_cast<int32_t>(g_LogEntries.size())) { continue; }
            const auto &entry = g_LogEntries[entryIndex];
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

    if (autoScroll && ImGui::GetScrollY() >= ImGui::GetScrollMaxY() - 4.0f) {
        ImGui::SetScrollHereY(1.0f);
    }

    ImGui::EndChild();
    ImGui::End();
}

static void DrawProfilingPanel(bool *isOpen) {
    if (!isOpen || !*isOpen) { return; }
    ImGui::Begin("Profiling", isOpen);

    float frameMs = MCERendererGetFrameMs();
    float gpuMs = MCERendererGetGpuMs();
    static float frameHistory[120] = {0};
    static float updateHistory[120] = {0};
    static float renderHistory[120] = {0};
    static float postHistory[120] = {0};
    static int frameOffset = 0;
    const float updateMs = MCERendererGetUpdateMs();
    const float renderMs = MCERendererGetRenderMs();
    const float postMs = MCERendererGetBloomMs() + MCERendererGetCompositeMs() + MCERendererGetOverlaysMs();
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
    ImGui::Text("Update:     %.2f ms", MCERendererGetUpdateMs());
    ImGui::Text("Scene:      %.2f ms", MCERendererGetSceneMs());
    ImGui::Text("Render:     %.2f ms", MCERendererGetRenderMs());
    ImGui::Text("Bloom:      %.2f ms", MCERendererGetBloomMs());
    ImGui::Text("  Extract:  %.2f ms", MCERendererGetBloomExtractMs());
    ImGui::Text("  Downsample: %.2f ms", MCERendererGetBloomDownsampleMs());
    ImGui::Text("  Blur:     %.2f ms", MCERendererGetBloomBlurMs());
    ImGui::Text("Composite:  %.2f ms", MCERendererGetCompositeMs());
    ImGui::Text("Overlays:   %.2f ms", MCERendererGetOverlaysMs());
    ImGui::Text("Present:    %.2f ms", MCERendererGetPresentMs());

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

+ (void)setupWithView:(MTKView *)view {
    if (g_ImGuiInitialized) { return; }
    g_ImGuiInitialized = true;

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO();
    (void)io;

    // Store ImGui config in Application Support so it persists with or without sandbox.
    char iniPathBuffer[512] = {0};
    if (MCEEditorGetImGuiIniPath(iniPathBuffer, sizeof(iniPathBuffer)) != 0) {
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

+ (void)newFrameWithView:(MTKView *)view deltaTime:(float)dt {
    if (!g_ImGuiInitialized) { [self setupWithView:view]; }
    EnsureImGuiKeyResponder(view);

    ImGuiIO& io = ImGui::GetIO();
    io.DeltaTime = (dt > 0.0f) ? dt : (1.0f / 60.0f);

    ImGui_ImplMetal_NewFrame(view.currentRenderPassDescriptor);
    ImGui_ImplOSX_NewFrame(view);
    ImGui::NewFrame();
}

+ (void)buildUIWithSceneTexture:(id<MTLTexture> _Nullable)sceneTexture {
    static char g_AlertMessage[512] = {0};
    if (g_AlertMessage[0] == 0) {
        if (MCEEditorPopNextAlert(g_AlertMessage, sizeof(g_AlertMessage)) != 0) {
            ImGui::OpenPopup("Error");
        }
    }

    LoadPanelVisibilityIfNeeded();

    if (ImGui::BeginPopupModal("Error", nullptr, ImGuiWindowFlags_AlwaysAutoResize)) {
        ImGui::TextWrapped("%s", g_AlertMessage);
        if (ImGui::Button("OK")) {
            g_AlertMessage[0] = 0;
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
                MCEProjectNew();
            }
            if (ImGui::MenuItem("Open Project...")) {
                MCEProjectOpen();
            }
            bool hasProject = MCEProjectHasOpen() != 0;
            if (ImGui::MenuItem("Save", nullptr, false, hasProject)) {
                MCEProjectSaveAll();
            }
            int32_t recentCount = MCEProjectRecentCount();
            if (ImGui::BeginMenu("Recent Projects", recentCount > 0)) {
                if (recentCount == 0) {
                    ImGui::MenuItem("No recent projects", nullptr, false, false);
                }
                for (int32_t i = 0; i < recentCount && i < 10; ++i) {
                    char pathBuffer[512] = {0};
                    if (MCEProjectRecentPathAt(i, pathBuffer, sizeof(pathBuffer)) <= 0) { continue; }
                    std::string path = pathBuffer;
                    size_t slash = path.find_last_of('/');
                    std::string name = (slash == std::string::npos) ? path : path.substr(slash + 1);
                    std::string label = name + "##recent" + std::to_string(i);
                    if (ImGui::MenuItem(label.c_str())) {
                        MCEProjectOpenRecent(pathBuffer);
                    }
                }
                ImGui::EndMenu();
            }
            ImGui::Separator();
            if (ImGui::MenuItem("Exit")) {
                MCEEditorRequestQuit();
            }
            EditorUI::PopMenuPopupStyle();
            ImGui::EndMenu();
        }
        if (ImGui::BeginMenu("View")) {
            EditorUI::PushMenuPopupStyle();
            DrawPanelMenuItem({ "Scene Hierarchy", "SceneHierarchy", &g_ShowSceneHierarchyPanel });
            DrawPanelMenuItem({ "Inspector", "Inspector", &g_ShowInspectorPanel });
            DrawPanelMenuItem({ "Content Browser", "ContentBrowser", &g_ShowContentBrowserPanel });
            DrawPanelMenuItem({ "Renderer", "Renderer", &g_ShowRendererPanel });
            DrawPanelMenuItem({ "Profiling", "Profiling", &g_ShowProfilingPanel });
            DrawPanelMenuItem({ "Logs", "Logs", &g_ShowLogsPanel });
            DrawPanelMenuItem({ "Viewport", "Viewport", &g_ShowViewportPanel });
            EditorUI::PopMenuPopupStyle();
            ImGui::EndMenu();
        }
        ImGui::EndMenuBar();
    }
    EditorUI::PopMenuBarStyle();

    ImGui::PopStyleVar(3);

    if (MCEProjectNeedsModal() != 0) {
        ImGui::OpenPopup("Create or Open Project");
    }
    if (ImGui::BeginPopupModal("Create or Open Project", nullptr, ImGuiWindowFlags_AlwaysAutoResize)) {
        ImGui::TextUnformatted("Select a project to get started.");
        if (ImGui::Button("New Project...")) {
            MCEProjectNew();
        }
        ImGui::SameLine();
        if (ImGui::Button("Open Project...")) {
            MCEProjectOpen();
        }
        ImGui::Separator();

        static int32_t g_SelectedProjectIndex = -1;
        static char g_SelectedProjectPath[512] = {0};

        ImGui::TextUnformatted("Projects");
        if (ImGui::BeginChild("ProjectList", ImVec2(520, 240), true)) {
            int32_t projectCount = MCEProjectListCount();
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
                    if (MCEProjectListAt(i, nameBuffer, sizeof(nameBuffer), pathBuffer, sizeof(pathBuffer), &modified) == 0) {
                        continue;
                    }
                    ImGui::TableNextRow();
                    ImGui::TableSetColumnIndex(0);
                    ImGui::PushID(i);
                    bool selected = (g_SelectedProjectIndex == i);
                    if (ImGui::Selectable(nameBuffer, selected, ImGuiSelectableFlags_SpanAllColumns)) {
                        g_SelectedProjectIndex = i;
                        strncpy(g_SelectedProjectPath, pathBuffer, sizeof(g_SelectedProjectPath) - 1);
                        g_SelectedProjectPath[sizeof(g_SelectedProjectPath) - 1] = 0;
                    }
                    if (ImGui::IsItemHovered() && ImGui::IsMouseDoubleClicked(0)) {
                        MCEProjectOpenAtPath(pathBuffer);
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

        bool hasSelection = g_SelectedProjectIndex >= 0 && g_SelectedProjectPath[0] != 0;
        if (ImGui::Button("Open Selected") && hasSelection) {
            MCEProjectOpenAtPath(g_SelectedProjectPath);
        }
        ImGui::SameLine();
        ImGui::BeginDisabled(!hasSelection);
        if (ImGui::Button("Delete")) {
            ImGui::OpenPopup("Confirm Delete Project");
        }
        ImGui::EndDisabled();
        if (ImGui::BeginPopupModal("Confirm Delete Project", nullptr, ImGuiWindowFlags_AlwaysAutoResize)) {
            ImGui::TextWrapped("Delete the selected project? This will remove it from disk.");
            if (ImGui::Button("Delete")) {
                MCEProjectDeleteAtPath(g_SelectedProjectPath);
                g_SelectedProjectIndex = -1;
                g_SelectedProjectPath[0] = 0;
                ImGui::CloseCurrentPopup();
            }
            ImGui::SameLine();
            if (ImGui::Button("Cancel")) {
                ImGui::CloseCurrentPopup();
            }
            ImGui::EndPopup();
        }

        if (MCEProjectHasOpen() != 0) {
            ImGui::CloseCurrentPopup();
        }
        ImGui::EndPopup();
    }

    // --- Panels ---
    bool rendererOpen = g_ShowRendererPanel;
    if (rendererOpen) {
        ImGuiRendererPanelDraw(&rendererOpen);
        if (rendererOpen != g_ShowRendererPanel) {
            g_ShowRendererPanel = rendererOpen;
            SetPanelVisibility("Renderer", g_ShowRendererPanel);
        }
    }

    bool hierarchyOpen = g_ShowSceneHierarchyPanel;
    if (hierarchyOpen) {
        ImGuiSceneHierarchyPanelDraw(&hierarchyOpen, g_SelectedEntityId, sizeof(g_SelectedEntityId));
        if (hierarchyOpen != g_ShowSceneHierarchyPanel) {
            g_ShowSceneHierarchyPanel = hierarchyOpen;
            SetPanelVisibility("SceneHierarchy", g_ShowSceneHierarchyPanel);
        }
    }

    bool inspectorOpen = g_ShowInspectorPanel;
    if (inspectorOpen) {
        ImGuiInspectorPanelDraw(&inspectorOpen, g_SelectedEntityId);
        if (inspectorOpen != g_ShowInspectorPanel) {
            g_ShowInspectorPanel = inspectorOpen;
            SetPanelVisibility("Inspector", g_ShowInspectorPanel);
        }
    }

    bool contentOpen = g_ShowContentBrowserPanel;
    if (contentOpen) {
        ImGuiContentBrowserPanelDraw(&contentOpen);
        if (contentOpen != g_ShowContentBrowserPanel) {
            g_ShowContentBrowserPanel = contentOpen;
            SetPanelVisibility("ContentBrowser", g_ShowContentBrowserPanel);
        }
    }

    bool profilingOpen = g_ShowProfilingPanel;
    if (profilingOpen) {
        DrawProfilingPanel(&profilingOpen);
        if (profilingOpen != g_ShowProfilingPanel) {
            g_ShowProfilingPanel = profilingOpen;
            SetPanelVisibility("Profiling", g_ShowProfilingPanel);
        }
    }

    bool logsOpen = g_ShowLogsPanel;
    if (logsOpen) {
        DrawLogsPanel(&logsOpen);
        if (logsOpen != g_ShowLogsPanel) {
            g_ShowLogsPanel = logsOpen;
            SetPanelVisibility("Logs", g_ShowLogsPanel);
        }
    }

    if (g_ShowViewportPanel) {
        ImGuiViewportPanelDraw(sceneTexture,
                               &g_ViewportHovered,
                               &g_ViewportFocused,
                               &g_ViewportContentSize,
                               &g_ViewportContentOrigin);
    }

    ImGui::End(); // DockSpaceHost
}

+ (void)renderWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
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

+ (bool)wantsCaptureMouse {
    if (!g_ImGuiInitialized) { return false; }
    ImGuiIO& io = ImGui::GetIO();
    return io.WantCaptureMouse;
}

+ (bool)wantsCaptureKeyboard {
    if (!g_ImGuiInitialized) { return false; }
    ImGuiIO& io = ImGui::GetIO();
    return io.WantCaptureKeyboard;
}

+ (bool)viewportIsHovered {
    return g_ViewportHovered;
}

+ (bool)viewportIsFocused {
    return g_ViewportFocused;
}

+ (CGSize)viewportContentSize {
    return g_ViewportContentSize;
}

+ (CGPoint)viewportContentOrigin {
    return g_ViewportContentOrigin;
}

@end
