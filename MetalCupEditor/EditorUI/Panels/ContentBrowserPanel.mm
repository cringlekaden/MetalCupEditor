// ContentBrowserPanel.mm
// Defines the ImGui ContentBrowser panel rendering and interaction logic.
// Created by Kaden Cringle.

#import "ContentBrowserPanel.h"

#import "../../ImGui/imgui.h"
#import "../Widgets/UIWidgets.h"
#include <string>
#include <vector>
#include <algorithm>
#include <cctype>
#include <cstring>
#include <unordered_map>
#include <stdint.h>

extern "C" uint32_t MCEEditorGetAssetsRootPath(char *buffer, int32_t bufferSize);
extern "C" uint64_t MCEEditorGetAssetRevision(void);
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
extern "C" uint32_t MCEEditorRenameAsset(const char *relativePath, const char *newName, char *outPath, int32_t outPathSize);
extern "C" uint32_t MCEEditorDeleteAsset(const char *relativePath);
extern "C" uint32_t MCEEditorDuplicateAsset(const char *relativePath, char *outPath, int32_t outPathSize);
extern "C" uint32_t MCEEditorDuplicateMaterial(const char *handle, char *outHandle, int32_t outHandleSize);
extern "C" uint32_t MCEEditorDeleteMaterial(const char *handle);
extern "C" uint32_t MCEEditorGetAssetPathForHandle(const char *handle, char *buffer, int32_t bufferSize);
extern "C" uint32_t MCEEditorGetLastContentBrowserPath(char *buffer, int32_t bufferSize);
extern "C" void MCEEditorSetLastContentBrowserPath(const char *value);
extern "C" void MCEEditorLogMessage(int32_t level, int32_t category, const char *message);

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
        std::string displayName;
        std::string displayNameLower;
        std::string fileName;
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
    static std::string g_RenamePath;
    static char g_RenameBuffer[128] = {0};
    static bool g_RenameActive = false;
    static bool g_RenameFocusNext = false;
    static std::string g_DeletePath;
    static std::string g_DeleteLabel;
    static bool g_DeleteIsDirectory = false;
    static int32_t g_DeleteType = AssetUnknown;
    static std::string g_DeleteHandle;
    static bool g_DeletePendingOpen = false;

    struct ContextTarget {
        bool valid = false;
        std::string relativePath;
        std::string displayName;
        std::string fileName;
        std::string handle;
        bool isDirectory = false;
        int32_t type = AssetUnknown;
    };

    static ContextTarget g_ContextTarget;
    static bool g_OpenContextMenu = false;
    static uint64_t g_LastAssetRevision = 0;
    static std::unordered_map<std::string, std::vector<BrowserEntry>> g_DirectoryCache;
    static std::vector<BrowserEntry> g_FilteredEntries;
    static std::string g_FilteredPath;
    static std::string g_FilteredSearch;
    static SortMode g_FilteredSort = SortByName;
    static bool g_FilteredAscending = true;
    static uint64_t g_FilteredRevision = 0;

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
        case AssetEnvironment: return "MCE_ASSET_ENVIRONMENT";
        case AssetScene: return "MCE_ASSET_SCENE";
        default: return "MCE_ASSET_GENERIC";
        }
    }

    std::string StripExtension(const std::string &name) {
        size_t dot = name.find_last_of('.');
        return dot == std::string::npos ? name : name.substr(0, dot);
    }

    bool NameExists(const std::vector<BrowserEntry> &entries, const std::string &name, bool isDirectory) {
        const std::string needle = EditorUI::ToLower(name);
        for (const auto &entry : entries) {
            if (entry.isDirectory != isDirectory) { continue; }
            if (EditorUI::ToLower(entry.fileName) == needle) { return true; }
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

    std::string TruncateLabelToWidth(const std::string &label, float maxWidth) {
        if (label.empty()) { return label; }
        if (ImGui::CalcTextSize(label.c_str()).x <= maxWidth) { return label; }
        const char *ellipsis = "...";
        const float ellipsisWidth = ImGui::CalcTextSize(ellipsis).x;
        if (maxWidth <= ellipsisWidth) { return std::string(ellipsis); }

        size_t low = 0;
        size_t high = label.size();
        while (low < high) {
            size_t mid = (low + high) / 2;
            std::string candidate = label.substr(0, mid);
            float width = ImGui::CalcTextSize(candidate.c_str()).x + ellipsisWidth;
            if (width <= maxWidth) {
                low = mid + 1;
            } else {
                high = mid;
            }
        }
        size_t fit = (low == 0) ? 0 : low - 1;
        return label.substr(0, fit) + ellipsis;
    }

    void LogAssetError(const std::string &message) {
        MCEEditorLogMessage(2, 3, message.c_str());
    }

    void BeginRename(const BrowserEntry &entry) {
        g_RenamePath = entry.relativePath;
        g_RenameActive = true;
        g_RenameFocusNext = true;
        std::string base = entry.isDirectory ? entry.fileName : StripExtension(entry.fileName);
        strncpy(g_RenameBuffer, base.c_str(), sizeof(g_RenameBuffer) - 1);
        g_RenameBuffer[sizeof(g_RenameBuffer) - 1] = 0;
    }

    void CancelRename() {
        g_RenameActive = false;
        g_RenameFocusNext = false;
        g_RenamePath.clear();
        g_RenameBuffer[0] = 0;
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
        MCEEditorSetLastContentBrowserPath(g_CurrentPath.c_str());
    }

    void InvalidateDirectoryCache() {
        g_DirectoryCache.clear();
        g_FilteredEntries.clear();
        g_FilteredPath.clear();
        g_FilteredSearch.clear();
        g_FilteredRevision = 0;
    }

    void RefreshDirectoryCacheIfNeeded() {
        const uint64_t revision = MCEEditorGetAssetRevision();
        if (revision != g_LastAssetRevision) {
            g_LastAssetRevision = revision;
            InvalidateDirectoryCache();
        }
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
            entry.displayName = nameBuffer;
            entry.displayNameLower = EditorUI::ToLower(entry.displayName);
            entry.relativePath = pathBuffer;
            entry.isDirectory = (isDirectory != 0);
            entry.type = type;
            entry.handle = handleBuffer;
            entry.modified = modified;
            std::string rel = entry.relativePath;
            size_t slash = rel.find_last_of('/');
            entry.fileName = (slash == std::string::npos) ? rel : rel.substr(slash + 1);
            entries.push_back(entry);
        }

        return entries;
    }

    const std::vector<BrowserEntry> &GetDirectoryEntries(const std::string &relativePath) {
        auto existing = g_DirectoryCache.find(relativePath);
        if (existing != g_DirectoryCache.end()) {
            return existing->second;
        }
        auto inserted = g_DirectoryCache.emplace(relativePath, FetchDirectoryEntries(relativePath));
        return inserted.first->second;
    }

    const std::vector<BrowserEntry> &GetFilteredEntries() {
        const std::string search = EditorUI::ToLower(std::string(g_Search));
        if (g_FilteredRevision != g_LastAssetRevision ||
            g_FilteredPath != g_CurrentPath ||
            g_FilteredSearch != search ||
            g_FilteredSort != g_Sort ||
            g_FilteredAscending != g_SortAscending) {
            g_FilteredEntries = GetDirectoryEntries(g_CurrentPath);
            if (!search.empty()) {
                g_FilteredEntries.erase(std::remove_if(g_FilteredEntries.begin(), g_FilteredEntries.end(),
                    [&](const BrowserEntry &entry) {
                        return entry.displayNameLower.find(search) == std::string::npos;
                    }),
                    g_FilteredEntries.end());
            }
            std::sort(g_FilteredEntries.begin(), g_FilteredEntries.end(), [&](const BrowserEntry &a, const BrowserEntry &b) {
                if (g_Sort == SortByType) {
                    if (a.isDirectory != b.isDirectory) {
                        return g_SortAscending ? a.isDirectory : !a.isDirectory;
                    }
                    int cmp = std::string(AssetTypeLabel(a.type)).compare(AssetTypeLabel(b.type));
                    return g_SortAscending ? cmp < 0 : cmp > 0;
                }
                if (g_Sort == SortByModified) {
                    if (a.modified == b.modified) {
                        return g_SortAscending ? a.displayName < b.displayName : a.displayName > b.displayName;
                    }
                    return g_SortAscending ? a.modified < b.modified : a.modified > b.modified;
                }
                if (a.isDirectory != b.isDirectory) {
                    return g_SortAscending ? a.isDirectory : !a.isDirectory;
                }
                return g_SortAscending ? a.displayName < b.displayName : a.displayName > b.displayName;
            });

            g_FilteredPath = g_CurrentPath;
            g_FilteredSearch = search;
            g_FilteredSort = g_Sort;
            g_FilteredAscending = g_SortAscending;
            g_FilteredRevision = g_LastAssetRevision;
        }

        return g_FilteredEntries;
    }

    void DrawDirectoryTree(const std::string &relativePath, const std::string &label) {
        ImGuiTreeNodeFlags flags = ImGuiTreeNodeFlags_OpenOnArrow | ImGuiTreeNodeFlags_SpanAvailWidth;
        if (relativePath == g_CurrentPath) {
            flags |= ImGuiTreeNodeFlags_Selected;
        }

        const auto &entries = GetDirectoryEntries(relativePath);
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
                DrawDirectoryTree(entry.relativePath, entry.displayName);
            }
            ImGui::TreePop();
        }
    }

    void DrawItemIcon(const BrowserEntry &entry, const ImVec2 &size, const ImVec2 &origin) {
        ImDrawList *drawList = ImGui::GetWindowDrawList();
        ImU32 color = IM_COL32(105, 105, 115, 255);
        if (entry.isDirectory) {
            color = IM_COL32(150, 120, 80, 255);
        } else if (entry.type == AssetMaterial) {
            color = IM_COL32(140, 120, 170, 255);
        } else if (entry.type == AssetTexture) {
            color = IM_COL32(130, 115, 150, 255);
        } else if (entry.type == AssetScene) {
            color = IM_COL32(190, 150, 90, 255);
        } else if (entry.type == AssetModel) {
            color = IM_COL32(125, 145, 150, 255);
        }
        ImVec2 max(origin.x + size.x, origin.y + size.y);
        drawList->AddRectFilled(origin, max, color, 6.0f);
        drawList->AddRect(origin, max, IM_COL32(20, 20, 20, 255), 6.0f);
    }

    void BeginAssetDragPayload(const BrowserEntry &entry) {
        if (ImGui::BeginDragDropSource(ImGuiDragDropFlags_SourceAllowNullID)) {
            const char *payloadType = PayloadTypeForAsset(entry.type);
            if (entry.type == AssetScene) {
                ImGui::SetDragDropPayload("MCE_ASSET_SCENE_PATH", entry.relativePath.c_str(), entry.relativePath.size() + 1);
            } else if (!entry.handle.empty()) {
                ImGui::SetDragDropPayload(payloadType, entry.handle.c_str(), entry.handle.size() + 1);
            }
            ImGui::Text("%s", entry.displayName.c_str());
            ImGui::EndDragDropSource();
        }
    }

    void SelectEntry(const BrowserEntry &entry, bool updateMaterialSelection) {
        g_SelectedPath = entry.relativePath;
        g_SelectedHandle = entry.handle;
        g_SelectedType = entry.type;
        g_SelectedIsDirectory = entry.isDirectory;
        if (updateMaterialSelection) {
            if (entry.type == AssetMaterial && !entry.handle.empty()) {
                MCEEditorSetSelectedMaterial(entry.handle.c_str());
            } else {
                MCEEditorSetSelectedMaterial(nullptr);
            }
        }
    }

    void SetContextTarget(const BrowserEntry &entry) {
        g_ContextTarget.valid = true;
        g_ContextTarget.relativePath = entry.relativePath;
        g_ContextTarget.displayName = entry.displayName;
        g_ContextTarget.fileName = entry.fileName;
        g_ContextTarget.handle = entry.handle;
        g_ContextTarget.isDirectory = entry.isDirectory;
        g_ContextTarget.type = entry.type;
        SelectEntry(entry, false);
    }

    void DrawEntryContextMenu() {
        if (!g_ContextTarget.valid) { return; }
        if (ImGui::BeginPopup("EntryContext")) {
            BrowserEntry entry;
            entry.relativePath = g_ContextTarget.relativePath;
            entry.displayName = g_ContextTarget.displayName;
            entry.fileName = g_ContextTarget.fileName;
            entry.handle = g_ContextTarget.handle;
            entry.isDirectory = g_ContextTarget.isDirectory;
            entry.type = g_ContextTarget.type;

            if (ImGui::MenuItem("Rename")) {
                BeginRename(entry);
            }
            if (!entry.isDirectory) {
                if (ImGui::MenuItem("Duplicate")) {
                    if (entry.type == AssetMaterial && !entry.handle.empty()) {
                        char newHandle[64] = {0};
                        if (MCEEditorDuplicateMaterial(entry.handle.c_str(), newHandle, sizeof(newHandle)) != 0) {
                            char newPath[512] = {0};
                            if (MCEEditorGetAssetPathForHandle(newHandle, newPath, sizeof(newPath)) != 0) {
                                g_SelectedPath = newPath;
                                g_SelectedHandle = newHandle;
                                g_SelectedType = entry.type;
                                g_SelectedIsDirectory = false;
                            }
                        } else {
                            LogAssetError("Duplicate failed.");
                        }
                    } else {
                        char newPath[512] = {0};
                        if (MCEEditorDuplicateAsset(entry.relativePath.c_str(), newPath, sizeof(newPath)) != 0) {
                            if (newPath[0] != 0) {
                                g_SelectedPath = newPath;
                                g_SelectedHandle.clear();
                                g_SelectedType = entry.type;
                                g_SelectedIsDirectory = false;
                            }
                        } else {
                            LogAssetError("Duplicate failed.");
                        }
                    }
                }
            }
            if (ImGui::MenuItem("Delete")) {
                g_DeletePath = entry.relativePath;
                g_DeleteLabel = entry.displayName;
                g_DeleteIsDirectory = entry.isDirectory;
                g_DeleteType = entry.type;
                g_DeleteHandle = entry.handle;
                g_DeletePendingOpen = true;
            }
            ImGui::EndPopup();
        }
        if (!ImGui::IsPopupOpen("EntryContext")) {
            g_ContextTarget.valid = false;
        }
    }
}

void ImGuiContentBrowserPanelDraw(bool *isOpen) {
    if (!isOpen || !*isOpen) { return; }
    if (!EditorUI::BeginPanel("Content Browser", isOpen)) {
        EditorUI::EndPanel();
        return;
    }

    ImGui::BeginChild("ContentBrowserRoot", ImVec2(0, 0), false, ImGuiWindowFlags_NoScrollbar);
    RefreshDirectoryCacheIfNeeded();

    if (g_HistoryIndex < 0) {
        char savedPath[512] = {0};
        if (MCEEditorGetLastContentBrowserPath(savedPath, sizeof(savedPath)) != 0) {
            std::string restored = savedPath;
            if (restored.rfind("Assets/", 0) == 0) {
                restored = restored.substr(strlen("Assets/"));
            }
            NavigateTo(restored);
        } else {
            NavigateTo("");
        }
    }

    ImGui::PushStyleVar(ImGuiStyleVar_ItemSpacing, ImVec2(6, 6));

    bool backDisabled = g_HistoryIndex <= 0;
    bool forwardDisabled = g_HistoryIndex >= static_cast<int>(g_History.size()) - 1;

    ImGui::BeginDisabled(backDisabled);
    if (ImGui::Button("<")) {
        g_HistoryIndex = std::max(0, g_HistoryIndex - 1);
        g_CurrentPath = g_History[g_HistoryIndex];
        MCEEditorSetLastContentBrowserPath(g_CurrentPath.c_str());
    }
    ImGui::EndDisabled();
    ImGui::SameLine();
    ImGui::BeginDisabled(forwardDisabled);
    if (ImGui::Button(">")) {
        g_HistoryIndex = std::min(static_cast<int>(g_History.size()) - 1, g_HistoryIndex + 1);
        g_CurrentPath = g_History[g_HistoryIndex];
        MCEEditorSetLastContentBrowserPath(g_CurrentPath.c_str());
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

        const auto &entries = GetFilteredEntries();

        const float thumbnailSize = 64.0f;
        const float tilePadding = 8.0f;
        const float gutter = 12.0f;
        float tileWidth = thumbnailSize + tilePadding * 2.0f;
        const float textLineHeight = ImGui::GetTextLineHeight();
        const float labelHeight = std::max(textLineHeight, ImGui::GetFrameHeight());
        float tileHeight = thumbnailSize + labelHeight + tilePadding * 3.4f;
        float cellSize = tileWidth + gutter;
        float panelWidth = ImGui::GetContentRegionAvail().x;
        int columnCount = static_cast<int>(panelWidth / cellSize);
        if (columnCount < 1) { columnCount = 1; }

        if (ImGui::BeginTable("AssetGrid", columnCount, ImGuiTableFlags_SizingFixedFit)) {
            const int entryCount = static_cast<int>(entries.size());
            const int rowCount = (entryCount + columnCount - 1) / columnCount;
            ImGuiListClipper clipper;
            clipper.Begin(rowCount, tileHeight + gutter);
            while (clipper.Step()) {
                for (int row = clipper.DisplayStart; row < clipper.DisplayEnd; ++row) {
                    ImGui::TableNextRow(0, tileHeight + gutter);
                    for (int column = 0; column < columnCount; ++column) {
                        ImGui::TableSetColumnIndex(column);
                        const int index = row * columnCount + column;
                        if (index >= entryCount) {
                            ImGui::Dummy(ImVec2(tileWidth, tileHeight));
                            continue;
                        }
                        const auto &entry = entries[index];
                        ImGui::PushID(index);

                        ImVec2 iconSize(thumbnailSize, thumbnailSize);
                        ImVec2 tileSize(tileWidth, tileHeight);
                        const bool isSelected = (g_SelectedPath == entry.relativePath);

                        ImGui::InvisibleButton("##Entry", tileSize);
                        const bool hovered = ImGui::IsItemHovered();
                        if (hovered && ImGui::IsMouseClicked(0)) {
                            SelectEntry(entry, true);
                        }
                        if (hovered && ImGui::IsMouseClicked(1)) {
                            SelectEntry(entry, false);
                        }

                        BeginAssetDragPayload(entry);
                        if (ImGui::IsItemClicked(ImGuiMouseButton_Right)) {
                            SetContextTarget(entry);
                            g_OpenContextMenu = true;
                        }

                        ImVec2 itemMin = ImGui::GetItemRectMin();
                        ImVec2 itemMax = ImGui::GetItemRectMax();
                        ImDrawList *drawList = ImGui::GetWindowDrawList();
                        if (isSelected) {
                            drawList->AddRectFilled(itemMin, itemMax, IM_COL32(120, 95, 150, 70), 6.0f);
                            drawList->AddRect(itemMin, itemMax, IM_COL32(155, 120, 190, 180), 6.0f, 0, 2.0f);
                        } else if (hovered) {
                            drawList->AddRect(itemMin, itemMax, IM_COL32(90, 90, 100, 120), 6.0f);
                        }

                        DrawItemIcon(entry, iconSize, ImVec2(itemMin.x + tilePadding, itemMin.y + tilePadding));

                        ImVec2 textPos(itemMin.x + tilePadding, itemMin.y + tilePadding + iconSize.y + 6.0f);
                        float textAreaWidth = tileWidth - tilePadding * 2.0f;
                        float textAreaHeight = labelHeight;
                        const bool isRenaming = g_RenameActive && g_RenamePath == entry.relativePath;
                        if (isRenaming) {
                            ImGui::PushStyleVar(ImGuiStyleVar_FramePadding, ImVec2(6.0f, 3.0f));
                            float inputHeight = ImGui::GetFrameHeight();
                            ImVec2 inputPos(textPos.x, textPos.y - (inputHeight - textLineHeight) * 0.5f);
                            ImGui::SetCursorScreenPos(inputPos);
                            ImGui::PushItemWidth(textAreaWidth);
                            if (g_RenameFocusNext) {
                                ImGui::SetKeyboardFocusHere();
                                g_RenameFocusNext = false;
                            }
                            bool committed = ImGui::InputText("##RenameInput", g_RenameBuffer, sizeof(g_RenameBuffer), ImGuiInputTextFlags_EnterReturnsTrue);
                            ImGui::PopItemWidth();
                            ImGui::PopStyleVar();
                            if (ImGui::IsItemActive() && ImGui::IsKeyPressed(ImGuiKey_Escape)) {
                                CancelRename();
                            } else if (!ImGui::IsItemActive() && ImGui::IsMouseClicked(0)) {
                                CancelRename();
                            } else if (committed) {
                                char newPath[512] = {0};
                                if (MCEEditorRenameAsset(entry.relativePath.c_str(), g_RenameBuffer, newPath, sizeof(newPath)) != 0) {
                                    std::string resolvedPath = newPath[0] != 0 ? std::string(newPath) : entry.relativePath;
                                    g_SelectedPath = resolvedPath;
                                    g_SelectedHandle = entry.handle;
                                    g_SelectedType = entry.type;
                                    g_SelectedIsDirectory = entry.isDirectory;
                                } else {
                                    LogAssetError("Rename failed.");
                                }
                                CancelRename();
                            }
                        } else {
                            std::string label = TruncateLabelToWidth(entry.displayName, textAreaWidth);
                            ImGui::PushClipRect(ImVec2(textPos.x, textPos.y),
                                                ImVec2(textPos.x + textAreaWidth, textPos.y + textAreaHeight),
                                                true);
                            float textWidth = ImGui::CalcTextSize(label.c_str()).x;
                            float textX = textPos.x + std::max(0.0f, (textAreaWidth - textWidth) * 0.5f);
                            drawList->AddText(ImVec2(textX, textPos.y), ImGui::GetColorU32(ImGuiCol_Text), label.c_str());
                            ImGui::PopClipRect();
                            ImGui::SetCursorScreenPos(textPos);
                            ImGui::InvisibleButton("##RenameClick", ImVec2(textAreaWidth, textAreaHeight));
                            BeginAssetDragPayload(entry);
                            if (ImGui::IsItemClicked(ImGuiMouseButton_Right)) {
                                SetContextTarget(entry);
                                g_OpenContextMenu = true;
                            }
                            if (ImGui::IsItemClicked(0)) {
                                if (!isSelected) {
                                    SelectEntry(entry, false);
                                }
                                BeginRename(entry);
                            }
                        }

                        if (!isRenaming && hovered && ImGui::IsMouseDoubleClicked(0)) {
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
                }
            }
            ImGui::EndTable();
        }

        if (g_OpenContextMenu) {
            ImGui::OpenPopup("EntryContext");
            g_OpenContextMenu = false;
        }
        DrawEntryContextMenu();

        if (!ImGui::IsPopupOpen("EntryContext") &&
            ImGui::BeginPopupContextWindow("ContentGridContext", ImGuiPopupFlags_MouseButtonRight | ImGuiPopupFlags_NoOpenOverItems)) {
            if (ImGui::BeginMenu("Create")) {
                if (ImGui::MenuItem("Folder")) {
                    const auto &entries = GetDirectoryEntries(g_CurrentPath);
                    const std::string uniqueName = MakeUniqueName(entries, "New Folder", true, "");
                    if (MCEEditorCreateFolder(g_CurrentPath.empty() ? nullptr : g_CurrentPath.c_str(), uniqueName.c_str()) == 0) {
                        LogAssetError("Failed to create folder.");
                    } else {
                        MCEEditorRefreshAssets();
                        g_SelectedPath = g_CurrentPath.empty() ? uniqueName : g_CurrentPath + "/" + uniqueName;
                        g_SelectedHandle.clear();
                        g_SelectedType = AssetUnknown;
                        g_SelectedIsDirectory = true;
                    }
                }
                if (ImGui::MenuItem("Material")) {
                    const std::string targetPath = g_CurrentPath.empty() ? "Materials" : g_CurrentPath;
                    const auto &entries = GetDirectoryEntries(targetPath);
                    const std::string uniqueName = MakeUniqueName(entries, "NewMaterial", false, "mcmat");
                    char outHandle[64] = {0};
                    if (MCEEditorCreateMaterial(targetPath.c_str(), uniqueName.c_str(), outHandle, sizeof(outHandle)) == 0) {
                        LogAssetError("Failed to create material.");
                    } else {
                        if (g_CurrentPath.empty()) {
                            NavigateTo(targetPath);
                        }
                        MCEEditorRefreshAssets();
                        g_SelectedPath = targetPath + "/" + uniqueName + ".mcmat";
                        g_SelectedHandle = outHandle;
                        g_SelectedType = AssetMaterial;
                        g_SelectedIsDirectory = false;
                    }
                }
                if (ImGui::MenuItem("Scene")) {
                    const std::string targetPath = g_CurrentPath.empty() ? "Scenes" : g_CurrentPath;
                    const auto &entries = GetDirectoryEntries(targetPath);
                    const std::string uniqueName = MakeUniqueName(entries, "NewScene", false, "mcscene");
                    if (MCEEditorCreateScene(targetPath.c_str(), uniqueName.c_str()) == 0) {
                        LogAssetError("Failed to create scene.");
                    } else {
                        if (g_CurrentPath.empty()) {
                            NavigateTo(targetPath);
                        }
                        MCEEditorRefreshAssets();
                        g_SelectedPath = targetPath + "/" + uniqueName + ".mcscene";
                        g_SelectedHandle.clear();
                        g_SelectedType = AssetScene;
                        g_SelectedIsDirectory = false;
                    }
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

        ImGui::EndChild();
        ImGui::EndTable();
    }

    if (g_DeletePendingOpen) {
        ImGui::OpenPopup("Confirm Delete");
        g_DeletePendingOpen = false;
    }

    if (ImGui::BeginPopupModal("Confirm Delete", nullptr, ImGuiWindowFlags_AlwaysAutoResize)) {
        if (g_DeleteIsDirectory) {
            ImGui::TextWrapped("Delete folder \"%s\" and all contents?", g_DeleteLabel.c_str());
        } else {
            ImGui::TextWrapped("Delete \"%s\"?", g_DeleteLabel.c_str());
        }
        if (ImGui::Button("Delete")) {
            bool deleted = false;
            if (!g_DeletePath.empty()) {
                if (g_DeleteType == AssetMaterial && !g_DeleteHandle.empty()) {
                    deleted = MCEEditorDeleteMaterial(g_DeleteHandle.c_str()) != 0;
                    if (!deleted) {
                        deleted = MCEEditorDeleteAsset(g_DeletePath.c_str()) != 0;
                    }
                } else {
                    deleted = MCEEditorDeleteAsset(g_DeletePath.c_str()) != 0;
                }
            }
            if (deleted) {
                if (g_DeleteType == AssetMaterial && !g_DeletePath.empty()) {
                    std::string message = "Deleted material: " + g_DeletePath;
                    MCEEditorLogMessage(1, 3, message.c_str());
                }
                MCEEditorRefreshAssets();
                if (g_SelectedPath == g_DeletePath) {
                    g_SelectedPath.clear();
                    g_SelectedHandle.clear();
                    g_SelectedType = AssetUnknown;
                    g_SelectedIsDirectory = false;
                }
            } else {
                LogAssetError("Delete failed.");
            }
            g_DeletePath.clear();
            g_DeleteLabel.clear();
            g_DeleteIsDirectory = false;
            g_DeleteType = AssetUnknown;
            g_DeleteHandle.clear();
            ImGui::CloseCurrentPopup();
        }
        ImGui::SameLine();
        if (ImGui::Button("Cancel")) {
            ImGui::CloseCurrentPopup();
        }
        ImGui::EndPopup();
    }

    ImGui::PopStyleVar();
    ImGui::EndChild();
    EditorUI::EndPanel();
}
