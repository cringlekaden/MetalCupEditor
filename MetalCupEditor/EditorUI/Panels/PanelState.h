#pragma once

#include "../../EditorCore/Bridge/MCEBridgeMacros.h"
#include <cstdint>
#include <string>
#include <unordered_map>
#include <vector>

namespace MCEPanelState {
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

    struct ContextTarget {
        bool valid = false;
        std::string relativePath;
        std::string displayName;
        std::string fileName;
        std::string handle;
        bool isDirectory = false;
        int32_t type = AssetUnknown;
    };

    struct ContentBrowserState {
        std::string currentPath;
        std::vector<std::string> history;
        int historyIndex = -1;
        char search[128] = {0};
        SortMode sort = SortByName;
        bool sortAscending = true;
        std::string selectedPath;
        std::string selectedHandle;
        int32_t selectedType = AssetUnknown;
        bool selectedIsDirectory = false;
        std::string renamePath;
        char renameBuffer[128] = {0};
        bool renameActive = false;
        bool renameFocusNext = false;
        std::string deletePath;
        std::string deleteLabel;
        bool deleteIsDirectory = false;
        int32_t deleteType = AssetUnknown;
        std::string deleteHandle;
        bool deletePendingOpen = false;
        ContextTarget contextTarget;
        bool openContextMenu = false;
        uint64_t lastAssetRevision = 0;
        std::unordered_map<std::string, std::vector<BrowserEntry>> directoryCache;
        std::vector<BrowserEntry> filteredEntries;
        std::string filteredPath;
        std::string filteredSearch;
        SortMode filteredSort = SortByName;
        bool filteredAscending = true;
        uint64_t filteredRevision = 0;
    };

    struct SceneHierarchyState {
        bool showPrefabPicker = false;
        bool requestPrefabPickerOpen = false;
        char prefabFilter[64] = {0};
        std::string selectedPrefabHandle;
    };

    struct MaterialEditorState {
        char name[128] = {0};
        int32_t version = 1;
        float baseColor[3] = {1.0f, 1.0f, 1.0f};
        float metallic = 1.0f;
        float roughness = 1.0f;
        float ao = 1.0f;
        float emissive[3] = {0.0f, 0.0f, 0.0f};
        float emissiveIntensity = 1.0f;
        int32_t alphaMode = 0;
        float alphaCutoff = 0.5f;
        bool doubleSided = false;
        bool unlit = false;
        char baseColorHandle[64] = {0};
        char normalHandle[64] = {0};
        char metalRoughnessHandle[64] = {0};
        char metallicHandle[64] = {0};
        char roughnessHandle[64] = {0};
        char aoHandle[64] = {0};
        char emissiveHandle[64] = {0};
    };

    struct TexturePickerState {
        bool open = false;
        bool requestOpen = false;
        bool didPick = false;
        char materialHandle[64] = {0};
        char *target = nullptr;
        char title[64] = {0};
        char filter[64] = {0};
    };

    struct EnvironmentPickerState {
        bool open = false;
        bool requestOpen = false;
        bool didPick = false;
        char *target = nullptr;
        char title[64] = {0};
        char filter[64] = {0};
        char entityId[64] = {0};
    };

    struct MeshPickerState {
        bool open = false;
        bool requestOpen = false;
        char title[64] = {0};
        char filter[64] = {0};
        char entityId[64] = {0};
        char materialHandle[64] = {0};
    };

    struct MaterialPickerState {
        bool open = false;
        bool requestOpen = false;
        char title[64] = {0};
        char filter[64] = {0};
        char entityId[64] = {0};
        char meshHandle[64] = {0};
        bool usesMeshRenderer = false;
    };

    struct MaterialPopupState {
        char handle[64] = {0};
        MaterialEditorState state;
        bool open = false;
        bool dirty = false;
        std::string title;
    };

    struct InspectorMaterialCache {
        char handle[64] = {0};
        MaterialEditorState state {};
        bool valid = false;
    };

    struct PendingSkyState {
        char entityId[64] = {0};
        bool hasPending = false;
        bool autoApply = false;
        int32_t mode = 0;
        uint32_t enabled = 1;
        float intensity = 1.0f;
        float tintX = 1.0f;
        float tintY = 1.0f;
        float tintZ = 1.0f;
        float turbidity = 2.0f;
        float azimuth = 0.0f;
        float elevation = 30.0f;
        char hdriHandle[64] = {0};
    };

    struct InspectorState {
        TexturePickerState texturePicker;
        EnvironmentPickerState environmentPicker;
        MeshPickerState meshPicker;
        MaterialPickerState materialPicker;
        MaterialPopupState materialPopup;
        InspectorMaterialCache materialCache;
        PendingSkyState pendingSky;
    };

    enum class GizmoOperation : uint8_t {
        None,
        Translate,
        Rotate,
        Scale
    };

    struct ViewportState {
        GizmoOperation operation = GizmoOperation::Translate;
        int mode = 0;
        bool snapEnabled = false;
        float translateSnap = 0.5f;
        float rotateSnap = 15.0f;
        float scaleSnap = 0.1f;
    };

    struct EditorUIPanelState {
        ContentBrowserState contentBrowser;
        SceneHierarchyState sceneHierarchy;
        InspectorState inspector;
        ViewportState viewport;
    };
}
