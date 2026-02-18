// ContentBrowserPanel.mm
// Defines the ImGui ContentBrowser panel rendering and interaction logic.
// Created by Kaden Cringle.

#import "ContentBrowserPanel.h"

#import "../../ImGui/imgui.h"
#import "PanelState.h"
#import "../Widgets/UIWidgets.h"
#include <string>
#include <vector>
#include <algorithm>
#include <cctype>
#include <cstring>
#include <unordered_map>
#include <stdint.h>

extern "C" uint32_t MCEEditorGetAssetsRootPath(MCE_CTX,  char *buffer, int32_t bufferSize);
extern "C" uint64_t MCEEditorGetAssetRevision(MCE_CTX);
extern "C" int32_t MCEEditorListDirectory(MCE_CTX,  const char *relativePath);
extern "C" uint32_t MCEEditorGetDirectoryEntry(MCE_CTX,  int32_t index,
                                                char *nameBuffer, int32_t nameBufferSize,
                                                char *relativePathBuffer, int32_t relativePathBufferSize,
                                                uint32_t *isDirectoryOut,
                                                int32_t *typeOut,
                                                char *handleBuffer, int32_t handleBufferSize,
                                                double *modifiedOut);
extern "C" uint32_t MCEEditorCreateFolder(MCE_CTX,  const char *relativePath, const char *name);
extern "C" uint32_t MCEEditorCreateMaterial(MCE_CTX,  const char *relativePath, const char *name, char *outHandle, int32_t outHandleSize);
extern "C" uint32_t MCEEditorCreateScene(MCE_CTX,  const char *relativePath, const char *name);
extern "C" uint32_t MCEEditorCreatePrefab(MCE_CTX,  const char *relativePath, const char *name);
extern "C" uint32_t MCEEditorOpenSceneAtPath(MCE_CTX,  const char *relativePath);
extern "C" void MCEEditorSetSelectedMaterial(MCE_CTX,  const char *handle);
extern "C" void MCEEditorOpenMaterialEditor(MCE_CTX,  const char *handle);
extern "C" void MCEEditorRefreshAssets(MCE_CTX);
extern "C" uint32_t MCEEditorRenameAsset(MCE_CTX,  const char *relativePath, const char *newName, char *outPath, int32_t outPathSize);
extern "C" uint32_t MCEEditorDeleteAsset(MCE_CTX,  const char *relativePath);
extern "C" uint32_t MCEEditorDuplicateAsset(MCE_CTX,  const char *relativePath, char *outPath, int32_t outPathSize);
extern "C" uint32_t MCEEditorDuplicateMaterial(MCE_CTX,  const char *handle, char *outHandle, int32_t outHandleSize);
extern "C" uint32_t MCEEditorDeleteMaterial(MCE_CTX,  const char *handle);
extern "C" uint32_t MCEEditorGetAssetPathForHandle(MCE_CTX,  const char *handle, char *buffer, int32_t bufferSize);
extern "C" uint32_t MCEEditorGetLastContentBrowserPath(MCE_CTX,  char *buffer, int32_t bufferSize);
extern "C" void MCEEditorSetLastContentBrowserPath(MCE_CTX,  const char *value);
extern "C" void MCEEditorLogMessage(MCE_CTX,  int32_t level, int32_t category, const char *message);
extern "C" void *MCEContextGetUIPanelState(MCE_CTX);

namespace {
    using MCEPanelState::AssetType;
    using MCEPanelState::AssetEnvironment;
    using MCEPanelState::AssetMaterial;
    using MCEPanelState::AssetModel;
    using MCEPanelState::AssetPrefab;
    using MCEPanelState::AssetScene;
    using MCEPanelState::AssetTexture;
    using MCEPanelState::AssetUnknown;
    using MCEPanelState::BrowserEntry;
    using MCEPanelState::ContentBrowserState;
    using MCEPanelState::ContextTarget;
    using MCEPanelState::SortMode;
    using MCEPanelState::SortByModified;
    using MCEPanelState::SortByName;
    using MCEPanelState::SortByType;

    ContentBrowserState &GetContentBrowserState(void *context) {
        auto *state = static_cast<MCEPanelState::EditorUIPanelState *>(MCEContextGetUIPanelState(context));
        return state->contentBrowser;
    }

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
        case AssetPrefab: return "MCE_ASSET_PREFAB";
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

    void LogAssetError(void *context, const std::string &message) {
        MCEEditorLogMessage(context, 2, 3, message.c_str());
    }

    void BeginRename(ContentBrowserState &state, const BrowserEntry &entry) {
        state.renamePath = entry.relativePath;
        state.renameActive = true;
        state.renameFocusNext = true;
        std::string base = entry.isDirectory ? entry.fileName : StripExtension(entry.fileName);
        strncpy(state.renameBuffer, base.c_str(), sizeof(state.renameBuffer) - 1);
        state.renameBuffer[sizeof(state.renameBuffer) - 1] = 0;
    }

    void CancelRename(ContentBrowserState &state) {
        state.renameActive = false;
        state.renameFocusNext = false;
        state.renamePath.clear();
        state.renameBuffer[0] = 0;
    }

    void PushHistory(ContentBrowserState &state, const std::string &path) {
        if (state.historyIndex >= 0 && state.historyIndex < static_cast<int>(state.history.size())) {
            if (state.history[state.historyIndex] == path) {
                return;
            }
        }
        if (state.historyIndex + 1 < static_cast<int>(state.history.size())) {
            state.history.erase(state.history.begin() + state.historyIndex + 1, state.history.end());
        }
        state.history.push_back(path);
        state.historyIndex = static_cast<int>(state.history.size()) - 1;
    }

    void NavigateTo(void *context, ContentBrowserState &state, const std::string &path) {
        state.currentPath = path;
        PushHistory(state, path);
        MCEEditorSetLastContentBrowserPath(context, state.currentPath.c_str());
    }

    void InvalidateDirectoryCache(ContentBrowserState &state) {
        state.directoryCache.clear();
        state.filteredEntries.clear();
        state.filteredPath.clear();
        state.filteredSearch.clear();
        state.filteredRevision = 0;
    }

    void RefreshDirectoryCacheIfNeeded(void *context, ContentBrowserState &state) {
        const uint64_t revision = MCEEditorGetAssetRevision(context);
        if (revision != state.lastAssetRevision) {
            state.lastAssetRevision = revision;
            InvalidateDirectoryCache(state);
        }
    }

    std::vector<BrowserEntry> FetchDirectoryEntries(void *context, const std::string &relativePath) {
        std::vector<BrowserEntry> entries;
        const int32_t count = MCEEditorListDirectory(context, relativePath.empty() ? nullptr : relativePath.c_str());
        entries.reserve(count);

        for (int32_t i = 0; i < count; ++i) {
            char nameBuffer[256] = {0};
            char pathBuffer[512] = {0};
            char handleBuffer[64] = {0};
            uint32_t isDirectory = 0;
            int32_t type = AssetUnknown;
            double modified = 0.0;
            if (MCEEditorGetDirectoryEntry(context, i,
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

    const std::vector<BrowserEntry> &GetDirectoryEntries(void *context, ContentBrowserState &state, const std::string &relativePath) {
        auto existing = state.directoryCache.find(relativePath);
        if (existing != state.directoryCache.end()) {
            return existing->second;
        }
        auto inserted = state.directoryCache.emplace(relativePath, FetchDirectoryEntries(context, relativePath));
        return inserted.first->second;
    }

    const std::vector<BrowserEntry> &GetFilteredEntries(void *context, ContentBrowserState &state) {
        const std::string search = EditorUI::ToLower(std::string(state.search));
        if (state.filteredRevision != state.lastAssetRevision ||
            state.filteredPath != state.currentPath ||
            state.filteredSearch != search ||
            state.filteredSort != state.sort ||
            state.filteredAscending != state.sortAscending) {
            state.filteredEntries = GetDirectoryEntries(context, state, state.currentPath);
            if (!search.empty()) {
                state.filteredEntries.erase(std::remove_if(state.filteredEntries.begin(), state.filteredEntries.end(),
                    [&](const BrowserEntry &entry) {
                        return entry.displayNameLower.find(search) == std::string::npos;
                    }),
                    state.filteredEntries.end());
            }
            std::sort(state.filteredEntries.begin(), state.filteredEntries.end(), [&](const BrowserEntry &a, const BrowserEntry &b) {
                if (state.sort == SortByType) {
                    if (a.isDirectory != b.isDirectory) {
                        return state.sortAscending ? a.isDirectory : !a.isDirectory;
                    }
                    int cmp = std::string(AssetTypeLabel(a.type)).compare(AssetTypeLabel(b.type));
                    return state.sortAscending ? cmp < 0 : cmp > 0;
                }
                if (state.sort == SortByModified) {
                    if (a.modified == b.modified) {
                        return state.sortAscending ? a.displayName < b.displayName : a.displayName > b.displayName;
                    }
                    return state.sortAscending ? a.modified < b.modified : a.modified > b.modified;
                }
                if (a.isDirectory != b.isDirectory) {
                    return state.sortAscending ? a.isDirectory : !a.isDirectory;
                }
                return state.sortAscending ? a.displayName < b.displayName : a.displayName > b.displayName;
            });

            state.filteredPath = state.currentPath;
            state.filteredSearch = search;
            state.filteredSort = state.sort;
            state.filteredAscending = state.sortAscending;
            state.filteredRevision = state.lastAssetRevision;
        }

        return state.filteredEntries;
    }

    void DrawDirectoryTree(void *context, ContentBrowserState &state, const std::string &relativePath, const std::string &label) {
        ImGuiTreeNodeFlags flags = ImGuiTreeNodeFlags_OpenOnArrow | ImGuiTreeNodeFlags_SpanAvailWidth;
        if (relativePath == state.currentPath) {
            flags |= ImGuiTreeNodeFlags_Selected;
        }

        const auto &entries = GetDirectoryEntries(context, state, relativePath);
        bool hasChild = std::any_of(entries.begin(), entries.end(), [](const BrowserEntry &entry) { return entry.isDirectory; });
        if (!hasChild) {
            flags |= ImGuiTreeNodeFlags_Leaf;
        }

        bool opened = ImGui::TreeNodeEx(label.c_str(), flags);
        if (ImGui::IsItemClicked()) {
            NavigateTo(context, state, relativePath);
        }

        if (opened) {
            for (const auto &entry : entries) {
                if (!entry.isDirectory) { continue; }
                DrawDirectoryTree(context, state, entry.relativePath, entry.displayName);
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

    void SelectEntry(void *context, ContentBrowserState &state, const BrowserEntry &entry, bool updateMaterialSelection) {
        state.selectedPath = entry.relativePath;
        state.selectedHandle = entry.handle;
        state.selectedType = entry.type;
        state.selectedIsDirectory = entry.isDirectory;
        if (updateMaterialSelection) {
            if (entry.type == AssetMaterial && !entry.handle.empty()) {
                MCEEditorSetSelectedMaterial(context, entry.handle.c_str());
            } else {
                MCEEditorSetSelectedMaterial(context, nullptr);
            }
        }
    }

    void SetContextTarget(void *context, ContentBrowserState &state, const BrowserEntry &entry) {
        state.contextTarget.valid = true;
        state.contextTarget.relativePath = entry.relativePath;
        state.contextTarget.displayName = entry.displayName;
        state.contextTarget.fileName = entry.fileName;
        state.contextTarget.handle = entry.handle;
        state.contextTarget.isDirectory = entry.isDirectory;
        state.contextTarget.type = entry.type;
        SelectEntry(context, state, entry, false);
    }

    void DrawEntryContextMenu(void *context, ContentBrowserState &state) {
        if (!state.contextTarget.valid) { return; }
        if (ImGui::BeginPopup("EntryContext")) {
            BrowserEntry entry;
            entry.relativePath = state.contextTarget.relativePath;
            entry.displayName = state.contextTarget.displayName;
            entry.fileName = state.contextTarget.fileName;
            entry.handle = state.contextTarget.handle;
            entry.isDirectory = state.contextTarget.isDirectory;
            entry.type = state.contextTarget.type;

            if (ImGui::MenuItem("Rename")) {
                BeginRename(state, entry);
            }
            if (!entry.isDirectory) {
                if (ImGui::MenuItem("Duplicate")) {
                    if (entry.type == AssetMaterial && !entry.handle.empty()) {
                        char newHandle[64] = {0};
                        if (MCEEditorDuplicateMaterial(context, entry.handle.c_str(), newHandle, sizeof(newHandle)) != 0) {
                            char newPath[512] = {0};
                            if (MCEEditorGetAssetPathForHandle(context, newHandle, newPath, sizeof(newPath)) != 0) {
                                state.selectedPath = newPath;
                                state.selectedHandle = newHandle;
                                state.selectedType = entry.type;
                                state.selectedIsDirectory = false;
                            }
                        } else {
                            LogAssetError(context, "Duplicate failed.");
                        }
                    } else {
                        char newPath[512] = {0};
                        if (MCEEditorDuplicateAsset(context, entry.relativePath.c_str(), newPath, sizeof(newPath)) != 0) {
                            if (newPath[0] != 0) {
                                state.selectedPath = newPath;
                                state.selectedHandle.clear();
                                state.selectedType = entry.type;
                                state.selectedIsDirectory = false;
                            }
                        } else {
                            LogAssetError(context, "Duplicate failed.");
                        }
                    }
                }
            }
            if (ImGui::MenuItem("Delete")) {
                state.deletePath = entry.relativePath;
                state.deleteLabel = entry.displayName;
                state.deleteIsDirectory = entry.isDirectory;
                state.deleteType = entry.type;
                state.deleteHandle = entry.handle;
                state.deletePendingOpen = true;
            }
            ImGui::EndPopup();
        }
        if (!ImGui::IsPopupOpen("EntryContext")) {
            state.contextTarget.valid = false;
        }
    }
}

void ImGuiContentBrowserPanelDraw(void *context, bool *isOpen) {
    if (!isOpen || !*isOpen) { return; }
    ContentBrowserState &state = GetContentBrowserState(context);
    if (!EditorUI::BeginPanel("Content Browser", isOpen)) {
        EditorUI::EndPanel();
        return;
    }

    ImGui::BeginChild("ContentBrowserRoot", ImVec2(0, 0), false, ImGuiWindowFlags_NoScrollbar);
    RefreshDirectoryCacheIfNeeded(context, state);

    if (state.historyIndex < 0) {
        char savedPath[512] = {0};
        if (MCEEditorGetLastContentBrowserPath(context, savedPath, sizeof(savedPath)) != 0) {
            std::string restored = savedPath;
            if (restored.rfind("Assets/", 0) == 0) {
                restored = restored.substr(strlen("Assets/"));
            }
            NavigateTo(context, state, restored);
        } else {
            NavigateTo(context, state, "");
        }
    }

    ImGui::PushStyleVar(ImGuiStyleVar_ItemSpacing, ImVec2(6, 6));

    bool backDisabled = state.historyIndex <= 0;
    bool forwardDisabled = state.historyIndex >= static_cast<int>(state.history.size()) - 1;

    ImGui::BeginDisabled(backDisabled);
    if (ImGui::Button("<")) {
        state.historyIndex = std::max(0, state.historyIndex - 1);
        state.currentPath = state.history[state.historyIndex];
        MCEEditorSetLastContentBrowserPath(context, state.currentPath.c_str());
    }
    ImGui::EndDisabled();
    ImGui::SameLine();
    ImGui::BeginDisabled(forwardDisabled);
    if (ImGui::Button(">")) {
        state.historyIndex = std::min(static_cast<int>(state.history.size()) - 1, state.historyIndex + 1);
        state.currentPath = state.history[state.historyIndex];
        MCEEditorSetLastContentBrowserPath(context, state.currentPath.c_str());
    }
    ImGui::EndDisabled();
    ImGui::SameLine();

    char rootPath[512] = {0};
    MCEEditorGetAssetsRootPath(context, rootPath, sizeof(rootPath));
    std::string fullPath = std::string(rootPath);
    if (!state.currentPath.empty()) {
        fullPath += "/" + state.currentPath;
    }
    char pathBuffer[512] = {0};
    strncpy(pathBuffer, fullPath.c_str(), sizeof(pathBuffer) - 1);
    ImGui::SetNextItemWidth(260.0f);
    ImGui::InputText("##Path", pathBuffer, sizeof(pathBuffer), ImGuiInputTextFlags_ReadOnly);

    ImGui::SameLine();
    ImGui::SetNextItemWidth(180.0f);
    ImGui::InputTextWithHint("##Search", "Search", state.search, sizeof(state.search));

    ImGui::SameLine();
    const char *sortItems[] = {"Name", "Type", "Modified"};
    int sortIndex = static_cast<int>(state.sort);
    ImGui::SetNextItemWidth(110.0f);
    if (ImGui::Combo("##Sort", &sortIndex, sortItems, IM_ARRAYSIZE(sortItems))) {
        state.sort = static_cast<SortMode>(sortIndex);
    }
    ImGui::SameLine();
    if (ImGui::Button(state.sortAscending ? "Asc" : "Desc")) {
        state.sortAscending = !state.sortAscending;
    }

    ImGui::Separator();

    ImGui::BeginChild("Breadcrumbs", ImVec2(0, 28), false, ImGuiWindowFlags_NoScrollbar | ImGuiWindowFlags_NoScrollWithMouse);
    if (ImGui::Button("Assets")) {
        NavigateTo(context, state, "");
    }
    if (!state.currentPath.empty()) {
        std::string accumulated;
        size_t start = 0;
        while (start < state.currentPath.size()) {
            size_t slash = state.currentPath.find('/', start);
            std::string segment = (slash == std::string::npos)
                ? state.currentPath.substr(start)
                : state.currentPath.substr(start, slash - start);
            accumulated = accumulated.empty() ? segment : accumulated + "/" + segment;
            ImGui::SameLine();
            ImGui::TextUnformatted("/");
            ImGui::SameLine();
            if (ImGui::Button(segment.c_str())) {
                NavigateTo(context, state, accumulated);
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
        DrawDirectoryTree(context, state, "", "Assets");
        ImGui::EndChild();

        ImGui::TableSetColumnIndex(1);
        ImGui::BeginChild("ContentGrid", ImVec2(0, 0), true, ImGuiWindowFlags_AlwaysVerticalScrollbar);

        const auto &entries = GetFilteredEntries(context, state);

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
                        const bool isSelected = (state.selectedPath == entry.relativePath);

                        ImGui::InvisibleButton("##Entry", tileSize);
                        const bool hovered = ImGui::IsItemHovered();
                        if (hovered && ImGui::IsMouseClicked(0)) {
                            SelectEntry(context, state, entry, true);
                        }
                        if (hovered && ImGui::IsMouseClicked(1)) {
                            SelectEntry(context, state, entry, false);
                        }

                        BeginAssetDragPayload(entry);
                        if (ImGui::IsItemClicked(ImGuiMouseButton_Right)) {
                            SetContextTarget(context, state, entry);
                            state.openContextMenu = true;
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
                        const bool isRenaming = state.renameActive && state.renamePath == entry.relativePath;
                        if (isRenaming) {
                            ImGui::PushStyleVar(ImGuiStyleVar_FramePadding, ImVec2(6.0f, 3.0f));
                            float inputHeight = ImGui::GetFrameHeight();
                            ImVec2 inputPos(textPos.x, textPos.y - (inputHeight - textLineHeight) * 0.5f);
                            ImGui::SetCursorScreenPos(inputPos);
                            ImGui::PushItemWidth(textAreaWidth);
                            if (state.renameFocusNext) {
                                ImGui::SetKeyboardFocusHere();
                                state.renameFocusNext = false;
                            }
                            bool committed = ImGui::InputText("##RenameInput", state.renameBuffer, sizeof(state.renameBuffer), ImGuiInputTextFlags_EnterReturnsTrue);
                            ImGui::PopItemWidth();
                            ImGui::PopStyleVar();
                            if (ImGui::IsItemActive() && ImGui::IsKeyPressed(ImGuiKey_Escape)) {
                                CancelRename(state);
                            } else if (!ImGui::IsItemActive() && ImGui::IsMouseClicked(0)) {
                                CancelRename(state);
                            } else if (committed) {
                                char newPath[512] = {0};
                                if (MCEEditorRenameAsset(context, entry.relativePath.c_str(), state.renameBuffer, newPath, sizeof(newPath)) != 0) {
                                    std::string resolvedPath = newPath[0] != 0 ? std::string(newPath) : entry.relativePath;
                                    state.selectedPath = resolvedPath;
                                    state.selectedHandle = entry.handle;
                                    state.selectedType = entry.type;
                                    state.selectedIsDirectory = entry.isDirectory;
                                } else {
                                    LogAssetError(context, "Rename failed.");
                                }
                                CancelRename(state);
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
                                SetContextTarget(context, state, entry);
                                state.openContextMenu = true;
                            }
                            if (ImGui::IsItemClicked(0)) {
                                if (!isSelected) {
                                    SelectEntry(context, state, entry, false);
                                }
                                BeginRename(state, entry);
                            }
                        }

                        if (!isRenaming && hovered && ImGui::IsMouseDoubleClicked(0)) {
                            if (entry.isDirectory) {
                                NavigateTo(context, state, entry.relativePath);
                            } else if (entry.type == AssetScene) {
                                MCEEditorOpenSceneAtPath(context, entry.relativePath.c_str());
                            } else if (entry.type == AssetMaterial) {
                                MCEEditorOpenMaterialEditor(context, entry.handle.c_str());
                            }
                        }

                        ImGui::PopID();
                    }
                }
            }
            ImGui::EndTable();
        }

        if (state.openContextMenu) {
            ImGui::OpenPopup("EntryContext");
            state.openContextMenu = false;
        }
        DrawEntryContextMenu(context, state);

        if (!ImGui::IsPopupOpen("EntryContext") &&
            ImGui::BeginPopupContextWindow("ContentGridContext", ImGuiPopupFlags_MouseButtonRight | ImGuiPopupFlags_NoOpenOverItems)) {
            if (ImGui::BeginMenu("Create")) {
                if (ImGui::MenuItem("Folder")) {
                    const auto &entries = GetDirectoryEntries(context, state, state.currentPath);
                    const std::string uniqueName = MakeUniqueName(entries, "New Folder", true, "");
                    if (MCEEditorCreateFolder(context, state.currentPath.empty() ? nullptr : state.currentPath.c_str(), uniqueName.c_str()) == 0) {
                        LogAssetError(context, "Failed to create folder.");
                    } else {
                        state.selectedPath = state.currentPath.empty() ? uniqueName : state.currentPath + "/" + uniqueName;
                        state.selectedHandle.clear();
                        state.selectedType = AssetUnknown;
                        state.selectedIsDirectory = true;
                    }
                }
                if (ImGui::MenuItem("Material")) {
                    const std::string targetPath = state.currentPath.empty() ? "Materials" : state.currentPath;
                    const auto &entries = GetDirectoryEntries(context, state, targetPath);
                    const std::string uniqueName = MakeUniqueName(entries, "NewMaterial", false, "mcmat");
                    char outHandle[64] = {0};
                    if (MCEEditorCreateMaterial(context, targetPath.c_str(), uniqueName.c_str(), outHandle, sizeof(outHandle)) == 0) {
                        LogAssetError(context, "Failed to create material.");
                    } else {
                        if (state.currentPath.empty()) {
                            NavigateTo(context, state, targetPath);
                        }
                        state.selectedPath = targetPath + "/" + uniqueName + ".mcmat";
                        state.selectedHandle = outHandle;
                        state.selectedType = AssetMaterial;
                        state.selectedIsDirectory = false;
                    }
                }
                if (ImGui::MenuItem("Scene")) {
                    const std::string targetPath = state.currentPath.empty() ? "Scenes" : state.currentPath;
                    const auto &entries = GetDirectoryEntries(context, state, targetPath);
                    const std::string uniqueName = MakeUniqueName(entries, "NewScene", false, "mcscene");
                    if (MCEEditorCreateScene(context, targetPath.c_str(), uniqueName.c_str()) == 0) {
                        LogAssetError(context, "Failed to create scene.");
                    } else {
                        if (state.currentPath.empty()) {
                            NavigateTo(context, state, targetPath);
                        }
                        state.selectedPath = targetPath + "/" + uniqueName + ".mcscene";
                        state.selectedHandle.clear();
                        state.selectedType = AssetScene;
                        state.selectedIsDirectory = false;
                    }
                }
                if (ImGui::MenuItem("Prefab")) {
                    const std::string targetPath = state.currentPath.empty() ? "Prefabs" : state.currentPath;
                    const auto &entries = GetDirectoryEntries(context, state, targetPath);
                    const std::string uniqueName = MakeUniqueName(entries, "NewPrefab", false, "prefab");
                    if (MCEEditorCreatePrefab(context, targetPath.c_str(), uniqueName.c_str()) == 0) {
                        LogAssetError(context, "Failed to create prefab.");
                    } else {
                        if (state.currentPath.empty()) {
                            NavigateTo(context, state, targetPath);
                        }
                        state.selectedPath = targetPath + "/" + uniqueName + ".prefab";
                        state.selectedHandle.clear();
                        state.selectedType = AssetPrefab;
                        state.selectedIsDirectory = false;
                    }
                }
                ImGui::EndMenu();
            }
            if (ImGui::MenuItem("Refresh")) {
                MCEEditorRefreshAssets(context);
            }
            ImGui::EndPopup();
        }

        ImGui::EndChild();
        ImGui::EndTable();
    }

    std::string deleteMessage;
    if (!state.deleteLabel.empty()) {
        if (state.deleteIsDirectory) {
            deleteMessage = "Delete folder \"" + state.deleteLabel + "\" and all contents?";
        } else {
            deleteMessage = "Delete \"" + state.deleteLabel + "\"?";
        }
    }

    EditorUI::ConfirmModal("Confirm Delete", &state.deletePendingOpen, deleteMessage.c_str(), "Delete", "Cancel", [&]() {
        bool deleted = false;
        if (!state.deletePath.empty()) {
            if (state.deleteType == AssetMaterial && !state.deleteHandle.empty()) {
                deleted = MCEEditorDeleteMaterial(context, state.deleteHandle.c_str()) != 0;
                if (!deleted) {
                    deleted = MCEEditorDeleteAsset(context, state.deletePath.c_str()) != 0;
                }
            } else {
                deleted = MCEEditorDeleteAsset(context, state.deletePath.c_str()) != 0;
            }
        }
        if (deleted) {
            if (state.deleteType == AssetMaterial && !state.deletePath.empty()) {
                std::string message = "Deleted material: " + state.deletePath;
                MCEEditorLogMessage(context, 1, 3, message.c_str());
            }
            if (state.selectedPath == state.deletePath) {
                state.selectedPath.clear();
                state.selectedHandle.clear();
                state.selectedType = AssetUnknown;
                state.selectedIsDirectory = false;
            }
        } else {
            LogAssetError(context, "Delete failed.");
        }
        state.deletePath.clear();
        state.deleteLabel.clear();
        state.deleteIsDirectory = false;
        state.deleteType = AssetUnknown;
        state.deleteHandle.clear();
    });

    ImGui::PopStyleVar();
    ImGui::EndChild();
    EditorUI::EndPanel();
}
