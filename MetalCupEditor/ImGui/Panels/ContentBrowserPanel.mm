#import "ContentBrowserPanel.h"

#import "imgui.h"
#include <string>
#include <vector>
#include <algorithm>
#include <cctype>
#include <cstring>
#include <stdint.h>

extern "C" uint32_t MCEEditorGetAssetsRootPath(char *buffer, int32_t bufferSize);
extern "C" int32_t MCEEditorListDirectory(const char *relativePath);
extern "C" uint32_t MCEEditorGetDirectoryEntry(int32_t index,
                                                char *nameBuffer, int32_t nameBufferSize,
                                                char *relativePathBuffer, int32_t relativePathBufferSize,
                                                uint32_t *isDirectoryOut,
                                                int32_t *typeOut,
                                                char *handleBuffer, int32_t handleBufferSize,
                                                double *modifiedOut);
extern "C" uint32_t MCEEditorCreateFolder(const char *relativePath, const char *name);
extern "C" uint32_t MCEEditorCreateMaterial(const char *relativePath, const char *name, char *outHandle, int32_t outHandleSize);
extern "C" uint32_t MCEEditorCreateScene(const char *relativePath, const char *name);
extern "C" uint32_t MCEEditorCreatePrefab(const char *relativePath, const char *name);
extern "C" uint32_t MCEEditorOpenSceneAtPath(const char *relativePath);
extern "C" void MCEEditorSetSelectedMaterial(const char *handle);
extern "C" void MCEEditorOpenMaterialEditor(const char *handle);
extern "C" void MCEEditorRefreshAssets(void);

namespace {
    enum AssetType : int32_t {
        AssetTexture = 0,
        AssetModel = 1,
        AssetMaterial = 2,
        AssetEnvironment = 3,
        AssetScene = 4,
        AssetPrefab = 5,
        AssetUnknown = 6
    };

    enum SortMode : int32_t {
        SortByName = 0,
        SortByType = 1,
        SortByModified = 2
    };

    struct BrowserEntry {
        std::string name;
        std::string relativePath;
        bool isDirectory = false;
        int32_t type = AssetUnknown;
        std::string handle;
        double modified = 0.0;
    };

    static std::string g_CurrentPath;
    static std::vector<std::string> g_History;
    static int g_HistoryIndex = -1;
    static char g_Search[128] = {0};
    static SortMode g_Sort = SortByName;
    static bool g_SortAscending = true;
    static std::string g_SelectedPath;
    static std::string g_SelectedHandle;
    static int32_t g_SelectedType = AssetUnknown;
    static bool g_SelectedIsDirectory = false;
    static std::string g_StatusMessage;
    static double g_StatusExpiry = 0.0;

    const char *AssetTypeLabel(int32_t type) {
        switch (type) {
        case AssetTexture: return "Texture";
        case AssetModel: return "Model";
        case AssetMaterial: return "Material";
        case AssetEnvironment: return "Environment";
        case AssetScene: return "Scene";
        case AssetPrefab: return "Prefab";
        default: return "Unknown";
        }
    }

    const char *PayloadTypeForAsset(int32_t type) {
        switch (type) {
        case AssetTexture: return "MCE_ASSET_TEXTURE";
        case AssetMaterial: return "MCE_ASSET_MATERIAL";
        case AssetModel: return "MCE_ASSET_MODEL";
        case AssetScene: return "MCE_ASSET_SCENE";
        default: return "MCE_ASSET_GENERIC";
        }
    }

    std::string ToLower(const std::string &value) {
        std::string output = value;
        std::transform(output.begin(), output.end(), output.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
        return output;
    }

    std::string StripExtension(const std::string &name) {
        size_t dot = name.find_last_of('.');
        return dot == std::string::npos ? name : name.substr(0, dot);
    }

    bool NameExists(const std::vector<BrowserEntry> &entries, const std::string &name, bool isDirectory) {
        const std::string needle = ToLower(name);
        for (const auto &entry : entries) {
            if (entry.isDirectory != isDirectory) { continue; }
            if (ToLower(entry.name) == needle) { return true; }
        }
        return false;
    }

    std::string MakeUniqueName(const std::vector<BrowserEntry> &entries,
                               const std::string &baseName,
                               bool isDirectory,
                               const std::string &extension) {
        std::string sanitizedBase = StripExtension(baseName.empty() ? std::string("New Item") : baseName);
        std::string candidate = sanitizedBase;
        int suffix = 1;
        while (true) {
            std::string testName = candidate;
            if (!extension.empty()) {
                testName += "." + extension;
            }
            if (!NameExists(entries, testName, isDirectory)) {
                return candidate;
            }
            candidate = sanitizedBase + " " + std::to_string(++suffix);
        }
    }

    std::string TruncateLabel(const std::string &label, size_t maxChars) {
        if (label.size() <= maxChars) { return label; }
        if (maxChars <= 3) { return label.substr(0, maxChars); }
        return label.substr(0, maxChars - 3) + "...";
    }

    void SetStatusMessage(const std::string &message) {
        g_StatusMessage = message;
        g_StatusExpiry = ImGui::GetTime() + 3.0;
    }

    void PushHistory(const std::string &path) {
        if (g_HistoryIndex >= 0 && g_HistoryIndex < static_cast<int>(g_History.size())) {
            if (g_History[g_HistoryIndex] == path) {
                return;
            }
        }
        if (g_HistoryIndex + 1 < static_cast<int>(g_History.size())) {
            g_History.erase(g_History.begin() + g_HistoryIndex + 1, g_History.end());
        }
        g_History.push_back(path);
        g_HistoryIndex = static_cast<int>(g_History.size()) - 1;
    }

    void NavigateTo(const std::string &path) {
        g_CurrentPath = path;
        PushHistory(path);
    }

    std::vector<BrowserEntry> FetchDirectoryEntries(const std::string &relativePath) {
        std::vector<BrowserEntry> entries;
        const int32_t count = MCEEditorListDirectory(relativePath.empty() ? nullptr : relativePath.c_str());
        entries.reserve(count);

        for (int32_t i = 0; i < count; ++i) {
            char nameBuffer[256] = {0};
            char pathBuffer[512] = {0};
            char handleBuffer[64] = {0};
            uint32_t isDirectory = 0;
            int32_t type = AssetUnknown;
            double modified = 0.0;
            if (MCEEditorGetDirectoryEntry(i,
                                          nameBuffer, sizeof(nameBuffer),
                                          pathBuffer, sizeof(pathBuffer),
                                          &isDirectory,
                                          &type,
                                          handleBuffer, sizeof(handleBuffer),
                                          &modified) == 0) {
                continue;
            }

            BrowserEntry entry;
            entry.name = nameBuffer;
            entry.relativePath = pathBuffer;
            entry.isDirectory = (isDirectory != 0);
            entry.type = type;
            entry.handle = handleBuffer;
            entry.modified = modified;
            entries.push_back(entry);
        }

        return entries;
    }

    void DrawDirectoryTree(const std::string &relativePath, const std::string &label) {
        ImGuiTreeNodeFlags flags = ImGuiTreeNodeFlags_OpenOnArrow | ImGuiTreeNodeFlags_SpanAvailWidth;
        if (relativePath == g_CurrentPath) {
            flags |= ImGuiTreeNodeFlags_Selected;
        }

        auto entries = FetchDirectoryEntries(relativePath);
        bool hasChild = std::any_of(entries.begin(), entries.end(), [](const BrowserEntry &entry) { return entry.isDirectory; });
        if (!hasChild) {
            flags |= ImGuiTreeNodeFlags_Leaf;
        }

        bool opened = ImGui::TreeNodeEx(label.c_str(), flags);
        if (ImGui::IsItemClicked()) {
            NavigateTo(relativePath);
        }

        if (opened) {
            for (const auto &entry : entries) {
                if (!entry.isDirectory) { continue; }
                DrawDirectoryTree(entry.relativePath, entry.name);
            }
            ImGui::TreePop();
        }
    }

    void DrawItemIcon(const BrowserEntry &entry, const ImVec2 &size, const ImVec2 &origin) {
        ImDrawList *drawList = ImGui::GetWindowDrawList();
        ImU32 color = IM_COL32(90, 120, 180, 255);
        if (entry.isDirectory) {
            color = IM_COL32(140, 110, 60, 255);
        } else if (entry.type == AssetMaterial) {
            color = IM_COL32(90, 150, 120, 255);
        } else if (entry.type == AssetTexture) {
            color = IM_COL32(120, 90, 160, 255);
        } else if (entry.type == AssetScene) {
            color = IM_COL32(200, 160, 90, 255);
        } else if (entry.type == AssetModel) {
            color = IM_COL32(90, 160, 190, 255);
        }
        ImVec2 max(origin.x + size.x, origin.y + size.y);
        drawList->AddRectFilled(origin, max, color, 6.0f);
        drawList->AddRect(origin, max, IM_COL32(20, 20, 20, 255), 6.0f);
    }
}

void ImGuiContentBrowserPanelDraw(bool *isOpen) {
    if (!isOpen || !*isOpen) { return; }
    ImGui::Begin("Content Browser", isOpen);

    ImGui::BeginChild("ContentBrowserRoot", ImVec2(0, 0), false, ImGuiWindowFlags_NoScrollbar);

    if (g_HistoryIndex < 0) {
        NavigateTo("");
    }

    ImGui::PushStyleVar(ImGuiStyleVar_ItemSpacing, ImVec2(6, 6));

    bool backDisabled = g_HistoryIndex <= 0;
    bool forwardDisabled = g_HistoryIndex >= static_cast<int>(g_History.size()) - 1;

    ImGui::BeginDisabled(backDisabled);
    if (ImGui::Button("<")) {
        g_HistoryIndex = std::max(0, g_HistoryIndex - 1);
        g_CurrentPath = g_History[g_HistoryIndex];
    }
    ImGui::EndDisabled();
    ImGui::SameLine();
    ImGui::BeginDisabled(forwardDisabled);
    if (ImGui::Button(">")) {
        g_HistoryIndex = std::min(static_cast<int>(g_History.size()) - 1, g_HistoryIndex + 1);
        g_CurrentPath = g_History[g_HistoryIndex];
    }
    ImGui::EndDisabled();
    ImGui::SameLine();

    char rootPath[512] = {0};
    MCEEditorGetAssetsRootPath(rootPath, sizeof(rootPath));
    std::string fullPath = std::string(rootPath);
    if (!g_CurrentPath.empty()) {
        fullPath += "/" + g_CurrentPath;
    }
    char pathBuffer[512] = {0};
    strncpy(pathBuffer, fullPath.c_str(), sizeof(pathBuffer) - 1);
    ImGui::SetNextItemWidth(260.0f);
    ImGui::InputText("##Path", pathBuffer, sizeof(pathBuffer), ImGuiInputTextFlags_ReadOnly);

    ImGui::SameLine();
    ImGui::SetNextItemWidth(180.0f);
    ImGui::InputTextWithHint("##Search", "Search", g_Search, sizeof(g_Search));

    ImGui::SameLine();
    const char *sortItems[] = {"Name", "Type", "Modified"};
    int sortIndex = static_cast<int>(g_Sort);
    ImGui::SetNextItemWidth(110.0f);
    if (ImGui::Combo("##Sort", &sortIndex, sortItems, IM_ARRAYSIZE(sortItems))) {
        g_Sort = static_cast<SortMode>(sortIndex);
    }
    ImGui::SameLine();
    if (ImGui::Button(g_SortAscending ? "Asc" : "Desc")) {
        g_SortAscending = !g_SortAscending;
    }

    ImGui::Separator();

    ImGui::BeginChild("Breadcrumbs", ImVec2(0, 28), false, ImGuiWindowFlags_NoScrollbar | ImGuiWindowFlags_NoScrollWithMouse);
    if (ImGui::Button("Assets")) {
        NavigateTo("");
    }
    if (!g_CurrentPath.empty()) {
        std::string accumulated;
        size_t start = 0;
        while (start < g_CurrentPath.size()) {
            size_t slash = g_CurrentPath.find('/', start);
            std::string segment = (slash == std::string::npos)
                ? g_CurrentPath.substr(start)
                : g_CurrentPath.substr(start, slash - start);
            accumulated = accumulated.empty() ? segment : accumulated + "/" + segment;
            ImGui::SameLine();
            ImGui::TextUnformatted("/");
            ImGui::SameLine();
            if (ImGui::Button(segment.c_str())) {
                NavigateTo(accumulated);
            }
            if (slash == std::string::npos) { break; }
            start = slash + 1;
        }
    }
    ImGui::EndChild();

    if (ImGui::BeginTable("ContentBrowserSplit", 2, ImGuiTableFlags_Resizable | ImGuiTableFlags_BordersInnerV)) {
        ImGui::TableSetupColumn("Tree", ImGuiTableColumnFlags_WidthFixed, 220.0f);
        ImGui::TableSetupColumn("Grid", ImGuiTableColumnFlags_WidthStretch);

        ImGui::TableNextRow();
        ImGui::TableSetColumnIndex(0);
        ImGui::BeginChild("DirectoryTree", ImVec2(0, 0), true, ImGuiWindowFlags_AlwaysVerticalScrollbar);
        DrawDirectoryTree("", "Assets");
        ImGui::EndChild();

        ImGui::TableSetColumnIndex(1);
        ImGui::BeginChild("ContentGrid", ImVec2(0, 0), true, ImGuiWindowFlags_AlwaysVerticalScrollbar);

        if (ImGui::BeginPopupContextWindow("ContentGridContext", ImGuiPopupFlags_MouseButtonRight)) {
            if (ImGui::BeginMenu("Create")) {
                if (ImGui::MenuItem("Folder")) {
                    ImGui::OpenPopup("CreateItem");
                    ImGui::SetNextWindowFocus();
                    ImGui::SetItemDefaultFocus();
                    ImGui::SetKeyboardFocusHere();
                }
                if (ImGui::MenuItem("Material")) {
                    ImGui::OpenPopup("CreateMaterial");
                }
                if (ImGui::MenuItem("Scene")) {
                    ImGui::OpenPopup("CreateScene");
                }
                ImGui::BeginDisabled();
                ImGui::MenuItem("Prefab (TODO)");
                ImGui::EndDisabled();
                ImGui::EndMenu();
            }
            if (ImGui::MenuItem("Refresh")) {
                MCEEditorRefreshAssets();
            }
            ImGui::EndPopup();
        }

        static char createName[128] = {0};
        if (ImGui::BeginPopupModal("CreateItem", nullptr, ImGuiWindowFlags_AlwaysAutoResize)) {
            ImGui::InputText("Folder Name", createName, sizeof(createName));
            if (ImGui::Button("Create")) {
                const auto entries = FetchDirectoryEntries(g_CurrentPath);
                const std::string baseName = createName[0] != 0 ? std::string(createName) : std::string("New Folder");
                const std::string uniqueName = MakeUniqueName(entries, baseName, true, "");
                if (MCEEditorCreateFolder(g_CurrentPath.empty() ? nullptr : g_CurrentPath.c_str(), uniqueName.c_str()) == 0) {
                    SetStatusMessage("Failed to create folder.");
                } else {
                    g_SelectedPath = g_CurrentPath.empty() ? uniqueName : g_CurrentPath + "/" + uniqueName;
                    g_SelectedHandle.clear();
                    g_SelectedType = AssetUnknown;
                    g_SelectedIsDirectory = true;
                }
                createName[0] = 0;
                ImGui::CloseCurrentPopup();
            }
            ImGui::SameLine();
            if (ImGui::Button("Cancel")) {
                ImGui::CloseCurrentPopup();
            }
            ImGui::EndPopup();
        }
        if (ImGui::BeginPopupModal("CreateMaterial", nullptr, ImGuiWindowFlags_AlwaysAutoResize)) {
            ImGui::InputText("Material Name", createName, sizeof(createName));
            if (ImGui::Button("Create")) {
                const std::string targetPath = g_CurrentPath.empty() ? "Materials" : g_CurrentPath;
                const auto entries = FetchDirectoryEntries(targetPath);
                const std::string baseName = createName[0] != 0 ? std::string(createName) : std::string("NewMaterial");
                const std::string uniqueName = MakeUniqueName(entries, baseName, false, "mcmat");
                char outHandle[64] = {0};
                if (MCEEditorCreateMaterial(targetPath.c_str(), uniqueName.c_str(), outHandle, sizeof(outHandle)) == 0) {
                    SetStatusMessage("Failed to create material.");
                } else {
                    if (g_CurrentPath.empty()) {
                        NavigateTo(targetPath);
                    }
                    MCEEditorOpenMaterialEditor(outHandle);
                    g_SelectedPath = targetPath + "/" + uniqueName + ".mcmat";
                    g_SelectedHandle = outHandle;
                    g_SelectedType = AssetMaterial;
                    g_SelectedIsDirectory = false;
                }
                createName[0] = 0;
                ImGui::CloseCurrentPopup();
            }
            ImGui::SameLine();
            if (ImGui::Button("Cancel")) {
                ImGui::CloseCurrentPopup();
            }
            ImGui::EndPopup();
        }
        if (ImGui::BeginPopupModal("CreateScene", nullptr, ImGuiWindowFlags_AlwaysAutoResize)) {
            ImGui::InputText("Scene Name", createName, sizeof(createName));
            if (ImGui::Button("Create")) {
                const std::string targetPath = g_CurrentPath.empty() ? "Scenes" : g_CurrentPath;
                const auto entries = FetchDirectoryEntries(targetPath);
                const std::string baseName = createName[0] != 0 ? std::string(createName) : std::string("NewScene");
                const std::string uniqueName = MakeUniqueName(entries, baseName, false, "scene");
                if (MCEEditorCreateScene(targetPath.c_str(), uniqueName.c_str()) == 0) {
                    SetStatusMessage("Failed to create scene.");
                } else {
                    if (g_CurrentPath.empty()) {
                        NavigateTo(targetPath);
                    }
                    g_SelectedPath = targetPath + "/" + uniqueName + ".scene";
                    g_SelectedHandle.clear();
                    g_SelectedType = AssetScene;
                    g_SelectedIsDirectory = false;
                }
                createName[0] = 0;
                ImGui::CloseCurrentPopup();
            }
            ImGui::SameLine();
            if (ImGui::Button("Cancel")) {
                ImGui::CloseCurrentPopup();
            }
            ImGui::EndPopup();
        }
        if (!g_StatusMessage.empty() && ImGui::GetTime() < g_StatusExpiry) {
            ImGui::TextColored(ImVec4(0.95f, 0.4f, 0.4f, 1.0f), "%s", g_StatusMessage.c_str());
        }

        auto entries = FetchDirectoryEntries(g_CurrentPath);
        const std::string filter = ToLower(g_Search);
        entries.erase(std::remove_if(entries.begin(), entries.end(), [&](const BrowserEntry &entry) {
            if (filter.empty()) { return false; }
            return ToLower(entry.name).find(filter) == std::string::npos;
        }), entries.end());

        std::sort(entries.begin(), entries.end(), [&](const BrowserEntry &a, const BrowserEntry &b) {
            if (g_Sort == SortByType) {
                if (a.isDirectory != b.isDirectory) {
                    return g_SortAscending ? a.isDirectory : !a.isDirectory;
                }
                int cmp = std::string(AssetTypeLabel(a.type)).compare(AssetTypeLabel(b.type));
                return g_SortAscending ? cmp < 0 : cmp > 0;
            }
            if (g_Sort == SortByModified) {
                if (a.modified == b.modified) {
                    return g_SortAscending ? a.name < b.name : a.name > b.name;
                }
                return g_SortAscending ? a.modified < b.modified : a.modified > b.modified;
            }
            if (a.isDirectory != b.isDirectory) {
                return g_SortAscending ? a.isDirectory : !a.isDirectory;
            }
            return g_SortAscending ? a.name < b.name : a.name > b.name;
        });

        const float thumbnailSize = 64.0f;
        const float padding = 12.0f;
        float cellSize = thumbnailSize + padding;
        float panelWidth = ImGui::GetContentRegionAvail().x;
        int columnCount = static_cast<int>(panelWidth / cellSize);
        if (columnCount < 1) { columnCount = 1; }

        if (ImGui::BeginTable("AssetGrid", columnCount, ImGuiTableFlags_SizingFixedFit)) {
            int index = 0;
            for (const auto &entry : entries) {
                ImGui::TableNextColumn();
                ImGui::PushID(index++);

                ImVec2 iconSize(thumbnailSize, thumbnailSize);
                float textHeight = ImGui::GetTextLineHeightWithSpacing();
                ImVec2 tileSize(thumbnailSize, thumbnailSize + textHeight + 6.0f);
                const bool isSelected = (g_SelectedPath == entry.relativePath);

                if (ImGui::Selectable("##Entry", isSelected, ImGuiSelectableFlags_AllowDoubleClick, tileSize)) {
                    g_SelectedPath = entry.relativePath;
                    g_SelectedHandle = entry.handle;
                    g_SelectedType = entry.type;
                    g_SelectedIsDirectory = entry.isDirectory;
                    if (entry.type == AssetMaterial) {
                        MCEEditorSetSelectedMaterial(entry.handle.c_str());
                    } else {
                        MCEEditorSetSelectedMaterial(nullptr);
                    }
                }

                ImVec2 itemMin = ImGui::GetItemRectMin();
                ImVec2 itemMax = ImGui::GetItemRectMax();
                ImDrawList *drawList = ImGui::GetWindowDrawList();
                if (isSelected) {
                    drawList->AddRectFilled(itemMin, itemMax, IM_COL32(60, 110, 170, 70), 6.0f);
                    drawList->AddRect(itemMin, itemMax, IM_COL32(90, 150, 210, 180), 6.0f, 0, 2.0f);
                }

                DrawItemIcon(entry, iconSize, itemMin);

                std::string label = TruncateLabel(entry.name, 24);
                ImVec2 textPos(itemMin.x, itemMin.y + iconSize.y + 4.0f);
                drawList->AddText(textPos, ImGui::GetColorU32(ImGuiCol_Text), label.c_str());

                if (ImGui::BeginDragDropSource()) {
                    if (!entry.handle.empty()) {
                        const char *payloadType = PayloadTypeForAsset(entry.type);
                        ImGui::SetDragDropPayload(payloadType, entry.handle.c_str(), entry.handle.size() + 1);
                        ImGui::Text("%s", entry.name.c_str());
                    }
                    ImGui::EndDragDropSource();
                }

                if (ImGui::IsItemHovered() && ImGui::IsMouseDoubleClicked(0)) {
                    if (entry.isDirectory) {
                        NavigateTo(entry.relativePath);
                    } else if (entry.type == AssetScene) {
                        MCEEditorOpenSceneAtPath(entry.relativePath.c_str());
                    } else if (entry.type == AssetMaterial) {
                        MCEEditorOpenMaterialEditor(entry.handle.c_str());
                    }
                }
                ImGui::PopID();
            }
            ImGui::EndTable();
        }

        ImGui::EndChild();
        ImGui::EndTable();
    }

    ImGui::PopStyleVar();
    ImGui::EndChild();
    ImGui::End();
}
