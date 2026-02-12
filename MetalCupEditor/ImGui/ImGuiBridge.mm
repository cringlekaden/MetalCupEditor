//
//  ImGuiBridge.mm
//  MetalCupEditor
//
//  Created by Kaden Cringle on 2/4/26.
//

#import "ImGuiBridge.h"

// ImGui
#import "imgui.h"
#import "backends/imgui_impl_osx.h"
#import "backends/imgui_impl_metal.h"

#import "Panels/RendererPanel.h"
#import "Panels/ViewportPanel.h"
#import "Panels/SceneHierarchyPanel.h"
#import "Panels/InspectorPanel.h"
#import "Panels/ContentBrowserPanel.h"
#import <Cocoa/Cocoa.h>
#include <cstring>
#include <ctime>
#include <string>

extern "C" void MCEProjectNew(void);
extern "C" void MCEProjectOpen(void);
extern "C" void MCEProjectSave(void);
extern "C" void MCEProjectSaveAs(void);
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
extern "C" uint32_t MCEEditorPopNextAlert(char *buffer, int32_t bufferSize);
extern "C" uint32_t MCEEditorPopNextStatus(char *buffer, int32_t bufferSize, int32_t *kindOut);
extern "C" uint32_t MCEEditorGetImGuiIniPath(char *buffer, int32_t bufferSize);

static bool g_ImGuiInitialized = false;
static bool g_ViewportHovered = false;
static bool g_ViewportFocused = false;
static CGSize g_ViewportContentSize = {0, 0};
static CGPoint g_ViewportContentOrigin = {0, 0};
static bool g_ShowRendererPanel = true;
static bool g_ShowSceneHierarchyPanel = true;
static bool g_ShowInspectorPanel = true;
static char g_SelectedEntityId[64] = {0};

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

    ImGui::StyleColorsDark();
    ImGuiStyle& style = ImGui::GetStyle();
    if (io.ConfigFlags & ImGuiConfigFlags_ViewportsEnable) {
        style.WindowRounding = 0.0f;
        style.Colors[ImGuiCol_WindowBg].w = 1.0f;
    }

    // Backends
    // OS X backend needs the NSView
    ImGui_ImplOSX_Init(view);
    ImGui_ImplOSX_SetKeyboardInputEnabled(view);
    // Metal backend now only needs the device
    ImGui_ImplMetal_Init(view.device);
}

+ (void)newFrameWithView:(MTKView *)view deltaTime:(float)dt {
    if (!g_ImGuiInitialized) { [self setupWithView:view]; }

    ImGuiIO& io = ImGui::GetIO();
    io.DeltaTime = (dt > 0.0f) ? dt : (1.0f / 60.0f);

    ImGui_ImplMetal_NewFrame(view.currentRenderPassDescriptor);
    ImGui_ImplOSX_NewFrame(view);
    ImGui_ImplOSX_SetKeyboardInputEnabled(view);
    ImGui::NewFrame();
}

+ (void)buildUIWithSceneTexture:(id<MTLTexture> _Nullable)sceneTexture {
    static char g_AlertMessage[512] = {0};
    static char g_StatusMessage[256] = {0};
    static int32_t g_StatusKind = 0;
    if (g_AlertMessage[0] == 0) {
        if (MCEEditorPopNextAlert(g_AlertMessage, sizeof(g_AlertMessage)) != 0) {
            ImGui::OpenPopup("Error");
            strncpy(g_StatusMessage, g_AlertMessage, sizeof(g_StatusMessage) - 1);
            g_StatusMessage[sizeof(g_StatusMessage) - 1] = 0;
            g_StatusKind = 2;
        }
    }
    char statusBuffer[256] = {0};
    int32_t statusKind = 0;
    if (MCEEditorPopNextStatus(statusBuffer, sizeof(statusBuffer), &statusKind) != 0) {
        strncpy(g_StatusMessage, statusBuffer, sizeof(g_StatusMessage) - 1);
        g_StatusMessage[sizeof(g_StatusMessage) - 1] = 0;
        g_StatusKind = statusKind;
    }

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
    if (ImGui::BeginMenuBar()) {
        if (ImGui::BeginMenu("File")) {
            if (ImGui::MenuItem("New Project...")) {
                MCEProjectNew();
            }
            if (ImGui::MenuItem("Open Project...")) {
                MCEProjectOpen();
            }
            bool hasProject = MCEProjectHasOpen() != 0;
            if (ImGui::MenuItem("Save Project", nullptr, false, hasProject)) {
                MCEProjectSave();
            }
            if (ImGui::MenuItem("Save Project As...", nullptr, false, hasProject)) {
                MCEProjectSaveAs();
            }
            ImGui::Separator();
            if (ImGui::MenuItem("Open Scene...", nullptr, false, hasProject)) {
                MCESceneLoad();
            }
            if (ImGui::MenuItem("Save Scene", nullptr, false, hasProject)) {
                MCESceneSave();
            }
            if (ImGui::MenuItem("Save Scene As...", nullptr, false, hasProject)) {
                MCESceneSaveAs();
            }
            ImGui::Separator();
            if (ImGui::MenuItem("Quit")) {
                [NSApp terminate:nil];
            }
            ImGui::EndMenu();
        }
        ImGui::EndMenuBar();
    }

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
    ImGuiRendererPanelDraw(&rendererOpen);
    if (!rendererOpen) {
        g_ShowRendererPanel = false;
        [NSApp terminate:nil];
    }

    bool hierarchyOpen = g_ShowSceneHierarchyPanel;
    ImGuiSceneHierarchyPanelDraw(&hierarchyOpen, g_SelectedEntityId, sizeof(g_SelectedEntityId));
    g_ShowSceneHierarchyPanel = hierarchyOpen;

    bool inspectorOpen = g_ShowInspectorPanel;
    ImGuiInspectorPanelDraw(&inspectorOpen, g_SelectedEntityId);
    g_ShowInspectorPanel = inspectorOpen;

    static bool contentOpen = true;
    ImGuiContentBrowserPanelDraw(&contentOpen);

    ImGuiViewportPanelDraw(sceneTexture,
                           &g_ViewportHovered,
                           &g_ViewportFocused,
                           &g_ViewportContentSize,
                           &g_ViewportContentOrigin);

    if (g_StatusMessage[0] != 0) {
        const float statusHeight = 24.0f;
        ImGui::SetNextWindowPos(ImVec2(vp->Pos.x, vp->Pos.y + vp->Size.y - statusHeight));
        ImGui::SetNextWindowSize(ImVec2(vp->Size.x, statusHeight));
        ImGui::SetNextWindowViewport(vp->ID);
        ImGuiWindowFlags statusFlags = ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoResize | ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoDocking | ImGuiWindowFlags_NoScrollbar;
        ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(10, 4));
        ImGui::Begin("StatusBar", nullptr, statusFlags);
        ImVec4 color = ImVec4(0.7f, 0.75f, 0.8f, 1.0f);
        if (g_StatusKind == 1) {
            color = ImVec4(0.95f, 0.7f, 0.2f, 1.0f);
        } else if (g_StatusKind == 2) {
            color = ImVec4(0.95f, 0.4f, 0.35f, 1.0f);
        }
        ImGui::TextColored(color, "%s", g_StatusMessage);
        ImGui::End();
        ImGui::PopStyleVar();
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
