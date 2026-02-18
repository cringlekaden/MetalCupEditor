/// EditorProjectManager.swift
/// Defines the EditorProjectManager types and helpers for the editor.
/// Created by Kaden Cringle.

import AppKit
import Foundation
import MetalCupEngine

final class EditorProjectManager {
    private let settingsStore: EditorSettingsStore
    private let uiState: EditorUIState
    private let logCenter: EngineLogger
    private let alertCenter: EditorAlertCenter
    private let sceneController: EditorSceneController
    private let layerCatalog: LayerCatalog

    private(set) var projectURL: URL?
    private(set) var projectRootURL: URL?
    private(set) var activeProjectPath: URL?
    private(set) var assetsRootPath: URL?
    private(set) var scenesRootPath: URL?
    private(set) var cachePath: URL?
    private(set) var intermediatePath: URL?
    private(set) var savedPath: URL?
    private(set) var projectDocument: ProjectDocument?
    private(set) var lastOpenedScenePath: String = ""
    private(set) var isProjectOpen: Bool = false

    private var assetRegistry: AssetRegistry?
    private var projectPaths: ProjectPaths?
    private var shouldShowProjectModal: Bool = false
    private var resourcesRootURL: URL?
    private var didRunStartupCheck: Bool = false
    private var sceneDirty: Bool = false
    private var assetRevision: UInt64 = 0

    init(settingsStore: EditorSettingsStore,
         uiState: EditorUIState,
         logCenter: EngineLogger,
         alertCenter: EditorAlertCenter,
         sceneController: EditorSceneController,
         layerCatalog: LayerCatalog) {
        self.settingsStore = settingsStore
        self.uiState = uiState
        self.logCenter = logCenter
        self.alertCenter = alertCenter
        self.sceneController = sceneController
        self.layerCatalog = layerCatalog
    }

    private struct ProjectListItem {
        let name: String
        let url: URL
        let modified: Date
    }

    func bootstrap(resourcesRootURL: URL?) {
        self.resourcesRootURL = resourcesRootURL
        settingsStore.load()
        if let projectsRoot = ensureProjectsRootURL() {
            let updated = ProjectMigration.migrateRecentProjects(settingsStore.recentProjects,
                                                                 projectsRoot: projectsRoot,
                                                                 logCenter: logCenter,
                                                                 alertCenter: alertCenter)
            if updated != settingsStore.recentProjects {
                settingsStore.replaceRecentProjects(updated)
                settingsStore.save()
            }
        }

        if let recent = settingsStore.recentProjects.first {
            let url = URL(fileURLWithPath: recent)
            _ = openProject(at: url, updateRecent: false)
        } else {
            let projects = listProjects()
            if projects.count == 1 {
                _ = openProject(at: projects[0].url, updateRecent: false)
            }
        }
        shouldShowProjectModal = true

        if !isProjectOpen {
            setEmptyScene()
        }

        performStartupSanityCheck()
    }

    func needsProjectModal() -> Bool {
        return shouldShowProjectModal
    }

    func dismissProjectModal() {
        shouldShowProjectModal = false
    }

    func recentProjects() -> [String] {
        return settingsStore.recentProjects
    }

    func newProject() {
        guard let projectsRoot = ensureProjectsRootURL() else {
            alertCenter.enqueueError("Failed to resolve Projects directory.")
            return
        }
        guard let url = EditorFileDialog.saveFile(defaultName: "NewProject.mcp",
                                                 allowedExtensions: ["mcp"],
                                                 directoryURL: projectsRoot,
                                                 message: "Create MetalCup Project") else {
            return
        }

        let projectName = url.deletingPathExtension().lastPathComponent
        let projectFolder = projectsRoot.appendingPathComponent(projectName, isDirectory: true)
        let assetsFolder = projectFolder.appendingPathComponent("Assets", isDirectory: true)
        let scenesFolder = assetsFolder.appendingPathComponent("Scenes", isDirectory: true)
        let cacheFolder = projectFolder.appendingPathComponent("Cache", isDirectory: true)
        let intermediateFolder = projectFolder.appendingPathComponent("Intermediate", isDirectory: true)
        let savedFolder = projectFolder.appendingPathComponent("Saved", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: assetsFolder, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: scenesFolder, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: intermediateFolder, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: savedFolder, withIntermediateDirectories: true)
        } catch {
            alertCenter.enqueueError("Failed to create project folders: \(error.localizedDescription)")
            return
        }

        let startScenePath = "Assets/Scenes/Default.mcscene"
        let project = ProjectDocument(
            schemaVersion: ProjectSchema.currentVersion,
            name: projectName,
            rootPath: ".",
            assetDirectory: "Assets",
            scenesDirectory: "Assets/Scenes",
            cacheDirectory: "Cache",
            intermediateDirectory: "Intermediate",
            savedDirectory: "Saved",
            startScene: startScenePath,
            layerNames: settingsStore.layerNames
        )

        let projectURL = projectFolder.appendingPathComponent("Project.mcp")
        if !writeProject(project, to: projectURL) {
            return
        }

        let sceneURL = projectFolder.appendingPathComponent(startScenePath)
        saveEmptyScene(to: sceneURL, name: "Default")
        seedDefaultAssetsIfNeeded(projectAssetsURL: assetsFolder)

        _ = openProject(at: projectURL)
    }

    func openProjectPanel() {
        let projectsRoot = ensureProjectsRootURL()
        guard let url = EditorFileDialog.openFile(allowedExtensions: ["mcp"], directoryURL: projectsRoot, message: "Open MetalCup Project") else {
            return
        }
        _ = openProject(at: url)
    }

    func saveProject() {
        guard let projectURL, let projectDocument else {
            alertCenter.enqueueError("No project is open to save.")
            return
        }
        if writeProject(projectDocument, to: projectURL) {
            logCenter.logInfo("Saved project.", category: .project)
        }
    }

    func saveProjectAs() {
        guard let projectDocument else {
            alertCenter.enqueueError("No project is open to save.")
            return
        }
        guard let url = EditorFileDialog.saveFile(defaultName: "\(projectDocument.name).mcp",
                                                 allowedExtensions: ["mcp"],
                                                 message: "Save Project As") else {
            return
        }
        guard writeProject(projectDocument, to: url) else { return }
        projectURL = url
        projectRootURL = url.deletingLastPathComponent()
        settingsStore.addRecentProject(url)
        settingsStore.save()
        logCenter.logInfo("Saved project as: \(url.lastPathComponent)", category: .project)
    }

    func openScenePanel() {
        guard let projectRootURL, let projectDocument else {
            alertCenter.enqueueError("Open a project before loading scenes.")
            return
        }
        let scenesRoot = projectRootURL.appendingPathComponent(projectDocument.scenesDirectory, isDirectory: true)
        guard let url = EditorFileDialog.openFile(allowedExtensions: ["mcscene", "scene"], directoryURL: scenesRoot, message: "Open Scene") else {
            return
        }
        let relativePath = relativePath(from: projectRootURL, to: url)
        loadScene(relativePath: relativePath)
    }

    func saveScene() {
        guard isProjectOpen else {
            alertCenter.enqueueError("Open a project before saving scenes.")
            return
        }
        if lastOpenedScenePath.isEmpty {
            saveSceneAs()
        } else {
            saveCurrentScene(relativePath: lastOpenedScenePath)
        }
    }

    func saveSceneAs() {
        guard let projectRootURL, let projectDocument else {
            alertCenter.enqueueError("Open a project before saving scenes.")
            return
        }
        let scenesRoot = projectRootURL.appendingPathComponent(projectDocument.scenesDirectory, isDirectory: true)
        guard let url = EditorFileDialog.saveFile(defaultName: "Untitled.mcscene",
                                                 allowedExtensions: ["mcscene", "scene"],
                                                 directoryURL: scenesRoot,
                                                 message: "Save Scene As") else {
            return
        }
        let relativePath = relativePath(from: projectRootURL, to: url)
        saveCurrentScene(relativePath: relativePath)
    }

    func loadScene(relativePath: String? = nil) {
        guard let projectDocument else { return }
        let path = relativePath ?? projectDocument.startScene
        loadScene(relativePath: path)
    }

    func saveCurrentScene(relativePath: String) {
        guard let projectRootURL else { return }
        let url = projectRootURL.appendingPathComponent(relativePath)
        do {
            try sceneController.saveScene(to: url)
            lastOpenedScenePath = relativePath
            saveEditorState()
            sceneDirty = false
            logCenter.logInfo("Saved scene: \(relativePath)", category: .scene)
        } catch {
            alertCenter.enqueueError("Failed to save scene: \(error.localizedDescription)")
        }
    }

    func openRecentProject(path: String) {
        let url = URL(fileURLWithPath: path)
        _ = openProject(at: url)
    }

    func openProjectAtPath(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        return openProject(at: url)
    }

    func deleteProject(at url: URL) -> Bool {
        let standardized = url.standardizedFileURL
        let projectFolder = standardized.deletingLastPathComponent()
        if let openRoot = projectRootURL?.standardizedFileURL, openRoot == projectFolder {
            alertCenter.enqueueError("Close the active project before deleting it.")
            return false
        }
        do {
            try FileManager.default.removeItem(at: projectFolder)
            settingsStore.removeRecentProject(at: standardized.path)
            settingsStore.save()
            logCenter.logInfo("Deleted project: \(projectFolder.lastPathComponent)", category: .project)
            return true
        } catch {
            alertCenter.enqueueError("Failed to delete project: \(error.localizedDescription)")
            return false
        }
    }

    private func openProject(at url: URL, updateRecent: Bool = true) -> Bool {
        let decoder = JSONDecoder()
        let projectsRoot = ensureProjectsRootURL() ?? url.deletingLastPathComponent()
        let resolvedProjectURL = ProjectMigration.migrateProjectIfNeeded(url: url,
                                                                         projectsRoot: projectsRoot,
                                                                         logCenter: logCenter,
                                                                         alertCenter: alertCenter) ?? url
        do {
            let data = try Data(contentsOf: resolvedProjectURL)
            let document = try decodeProject(from: data, decoder: decoder)
            let migrated = ProjectMigration.migrateDocumentIfNeeded(document,
                                                                    projectURL: resolvedProjectURL,
                                                                    projectsRoot: projectsRoot,
                                                                    logCenter: logCenter,
                                                                    alertCenter: alertCenter)
            let resolvedRootURL = resolvedProjectURL.deletingLastPathComponent().standardizedFileURL
            if sceneController.isPlaying {
                sceneController.stop()
            }
            projectDocument = migrated
            projectURL = resolvedProjectURL
            projectRootURL = resolvedRootURL
            activeProjectPath = resolvedRootURL
            layerCatalog.setNames(migrated.layerNames)
            settingsStore.setLayerNames(migrated.layerNames)

            let paths = ProjectPaths(projectRoot: resolvedRootURL, document: migrated)
            paths.ensureDirectoriesExist()
            projectPaths = paths
            assetsRootPath = paths.assetsRoot
            scenesRootPath = paths.scenesRoot
            cachePath = paths.cacheRoot
            intermediatePath = paths.intermediateRoot
            savedPath = paths.savedRoot
            isProjectOpen = true
            shouldShowProjectModal = false

            lastOpenedScenePath = ""
            seedDefaultAssetsIfNeeded(projectAssetsURL: paths.assetsRoot)
            configureAssets(project: migrated, rootURL: resolvedRootURL)
            loadEditorState(rootURL: resolvedRootURL, project: migrated)

            if updateRecent {
                settingsStore.addRecentProject(resolvedProjectURL)
                settingsStore.save()
            }

            let scenePath = lastOpenedScenePath.isEmpty ? migrated.startScene : lastOpenedScenePath
            loadScene(relativePath: scenePath)
            return true
        } catch {
            alertCenter.enqueueError("Failed to open project: \(error.localizedDescription)")
            return false
        }
    }

    private func configureAssets(project: ProjectDocument, rootURL: URL) {
        let resolvedAssetRoot = projectPaths?.assetsRoot ?? rootURL.appendingPathComponent("Assets", isDirectory: true)
        if !FileManager.default.fileExists(atPath: resolvedAssetRoot.path) {
            try? FileManager.default.createDirectory(at: resolvedAssetRoot, withIntermediateDirectories: true)
        }
        let registry = AssetRegistry(projectAssetRootURL: resolvedAssetRoot, logCenter: logCenter)
        registry.startWatching()
        assetRevision = 1
        registry.onChange = { [weak self] in
            guard let self else { return }
            self.assetRevision &+= 1
            AssetManager.clearCache()
            AssetManager.preload(from: registry)
            let prefabHandles = registry.allMetadata().filter { $0.type == .prefab }.map { $0.handle }
            self.sceneController.markPrefabsDirty(handles: prefabHandles)
            self.logCenter.logInfo("Assets reloaded.", category: .assets)
        }
        assetRegistry = registry
        Engine.assetDatabase = registry
        AssetManager.preload(from: registry)

        ResourceRegistry.resourcesRootURL = resourcesRootURL
        ResourceRegistry.shaderRootURLs = [resolvedAssetRoot.appendingPathComponent("Shaders", isDirectory: true)]
    }

    private func loadScene(relativePath: String) {
        guard let projectRootURL else { return }
        let url = projectRootURL.appendingPathComponent(relativePath)
        do {
            try sceneController.loadScene(from: url)
            lastOpenedScenePath = relativePath
            saveEditorState()
            sceneDirty = false
            logCenter.logInfo("Loaded scene: \(relativePath)", category: .scene)
        } catch {
            alertCenter.enqueueError("Failed to load scene: \(error.localizedDescription)")
        }
    }

    private func loadEditorState(rootURL: URL, project: ProjectDocument) {
        let cacheRoot = projectPaths?.cacheRoot
            ?? rootURL.appendingPathComponent(project.cacheDirectory, isDirectory: true)
        let stateURL = cacheRoot.appendingPathComponent("EditorState.json")
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: stateURL),
           let state = try? decoder.decode(EditorStateDocument.self, from: data) {
            let normalized = normalizeScenePathIfNeeded(state.lastOpenedScenePath, project: project)
            lastOpenedScenePath = normalized
            if normalized != state.lastOpenedScenePath {
                saveEditorState()
            }
        }
    }

    private func normalizeScenePathIfNeeded(_ path: String, project: ProjectDocument) -> String {
        guard let projectRootURL else { return path }
        if path.isEmpty { return "" }
        if PathUtils.isAbsolutePath(path) {
            let absoluteURL = URL(fileURLWithPath: path)
            return PathUtils.relativePath(from: projectRootURL, to: absoluteURL) ?? path
        }
        let legacyPrefix = "Scenes/"
        let targetPrefix = "\(project.scenesDirectory.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/"
        if path.hasPrefix(legacyPrefix) && !targetPrefix.isEmpty {
            return targetPrefix + path.dropFirst(legacyPrefix.count)
        }
        return path
    }

    private func saveEditorState() {
        guard let projectRootURL, let projectDocument else { return }
        let state = EditorStateDocument(lastOpenedScenePath: lastOpenedScenePath)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(state) {
            let cacheRoot = projectPaths?.cacheRoot
                ?? projectRootURL.appendingPathComponent(projectDocument.cacheDirectory, isDirectory: true)
            let url = cacheRoot.appendingPathComponent("EditorState.json")
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: [.atomic])
        }
    }

    private func ensureProjectsRootURL() -> URL? {
        guard let projectsRoot = EditorFileSystem.projectsRootURL(ensureExists: true) else { return nil }
        EditorFileSystem.seedBaseFromBundleIfNeeded(projectsRoot: projectsRoot)
        return projectsRoot
    }


    private func listProjects() -> [ProjectListItem] {
        guard let root = ensureProjectsRootURL() else { return [] }
        guard let directories = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }

        var items: [ProjectListItem] = []
        for dir in directories {
            let values = try? dir.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }
            let projectURL = dir.appendingPathComponent("Project.mcp")
            let fallbackURL = dir.appendingPathComponent("\(dir.lastPathComponent).mcp")
            let targetURL = FileManager.default.fileExists(atPath: projectURL.path) ? projectURL : fallbackURL
            guard FileManager.default.fileExists(atPath: targetURL.path) else { continue }
            let modified = (try? FileManager.default.attributesOfItem(atPath: targetURL.path)[.modificationDate] as? Date) ?? Date.distantPast
            let name = dir.lastPathComponent
            items.append(ProjectListItem(name: name, url: targetURL, modified: modified))
        }
        return items.sorted { $0.modified > $1.modified }
    }


    func assetMetadataSnapshot() -> [AssetMetadata] {
        assetRegistry?.allMetadata() ?? []
    }

    func assetURL(for handle: AssetHandle) -> URL? {
        assetRegistry?.assetURL(for: handle)
    }

    func assetRootURL() -> URL? {
        assetsRootPath
    }

    func assetRevisionToken() -> UInt64 {
        assetRevision
    }

    func refreshAssets() {
        assetRevision &+= 1
        assetRegistry?.refresh()
        if let registry = assetRegistry {
            let prefabHandles = registry.allMetadata().filter { $0.type == .prefab }.map { $0.handle }
            sceneController.markPrefabsDirty(handles: prefabHandles)
        }
    }

    func performAssetMutation(_ operation: () throws -> Bool) -> Bool {
        assetRegistry?.stopWatching()
        defer { assetRegistry?.startWatching() }
        do {
            let ok = try operation()
            if ok {
                refreshAssets()
            }
            return ok
        } catch {
            alertCenter.enqueueError("Asset operation failed: \(error.localizedDescription)")
            return false
        }
    }

    func notifySceneMutation() {
        markSceneDirty()
    }

    func markSceneDirty() {
        sceneDirty = true
    }

    func clearSceneDirty() {
        sceneDirty = false
    }

    func isSceneDirty() -> Bool {
        return sceneDirty
    }

    func saveAll() {
        guard isProjectOpen else { return }
        saveProject()
        if !lastOpenedScenePath.isEmpty {
            saveCurrentScene(relativePath: lastOpenedScenePath)
        }
    }

    func saveSettings() {
        settingsStore.save()
    }

    func panelIsVisible(_ panelId: String, defaultValue: Bool) -> Bool {
        uiState.panelIsVisible(panelId, defaultValue: defaultValue)
    }

    func setPanelVisible(_ panelId: String, visible: Bool) {
        uiState.setPanelVisible(panelId, visible: visible)
    }

    func headerIsOpen(_ headerId: String, defaultValue: Bool) -> Bool {
        uiState.headerIsOpen(headerId, defaultValue: defaultValue)
    }

    func setHeaderOpen(_ headerId: String, open: Bool) {
        uiState.setHeaderOpen(headerId, open: open)
    }

    func lastSelectedEntityId() -> String {
        uiState.lastSelectedEntityId()
    }

    func setLastSelectedEntityId(_ entityId: String) {
        uiState.setLastSelectedEntityId(entityId)
    }

    func lastContentBrowserPath() -> String {
        uiState.lastContentBrowserPath()
    }

    func setLastContentBrowserPath(_ path: String) {
        uiState.setLastContentBrowserPath(path)
    }

    func metaURLForAsset(assetURL: URL, relativePath: String) -> URL? {
        assetRegistry?.metaURLForAsset(assetURL: assetURL, relativePath: relativePath)
    }

    func saveMetadata(_ metadata: AssetMetadata, to url: URL) {
        assetRegistry?.saveMetadata(metadata, to: url)
    }

    func projectListItems() -> [(name: String, url: URL, modified: Date)] {
        return listProjects().map { ($0.name, $0.url, $0.modified) }
    }

    func projectsRootDirectory() -> URL? {
        ensureProjectsRootURL()
    }

    private func writeProject(_ project: ProjectDocument, to url: URL) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(project)
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            alertCenter.enqueueError("Failed to save project: \(error.localizedDescription)")
            return false
        }
    }

    private func decodeProject(from data: Data, decoder: JSONDecoder) throws -> ProjectDocument {
        if let project = try? decoder.decode(ProjectDocument.self, from: data) {
            return project
        }
        if let legacy = try? decoder.decode(LegacyProjectDocument.self, from: data) {
            return ProjectDocument(
                name: legacy.name,
                rootPath: legacy.assetRootPath,
                assetDirectory: ".",
                scenesDirectory: "Scenes",
                cacheDirectory: "Cache",
                intermediateDirectory: "Intermediate",
                savedDirectory: "Saved",
                startScene: legacy.defaultScenePath,
                layerNames: LayerCatalog.defaultNames()
            )
        }
        throw NSError(
            domain: "MetalCupEditor.Project",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unknown project format."]
        )
    }

    private func saveEmptyScene(to url: URL, name: String) {
        let document = SceneDocument(id: UUID(), name: name, entities: [])
        let scene = SerializedScene(document: document)
        do {
            try SceneSerializer.save(scene: scene, to: url)
        } catch {
            alertCenter.enqueueError("Failed to write default scene: \(error.localizedDescription)")
        }
    }

    private func setEmptyScene() {
        layerCatalog.setNames(settingsStore.layerNames)
        let document = SceneDocument(id: UUID(), name: "Untitled", entities: [])
        let scene = SerializedScene(document: document)
        sceneController.setScene(scene)
    }

    private func relativePath(from root: URL, to url: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let targetPath = url.standardizedFileURL.path
        if targetPath.hasPrefix(rootPath + "/") {
            return String(targetPath.dropFirst(rootPath.count + 1))
        }
        return url.lastPathComponent
    }

    private struct DefaultAssetsMarker: Codable {
        let version: String
        let paths: [String]
    }

    private func seedDefaultAssetsIfNeeded(projectAssetsURL: URL) {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: projectAssetsURL.path) {
            PathUtils.ensureDirectoryExists(projectAssetsURL)
        }

        guard let templateURL = EditorFileSystem.defaultAssetsTemplateURL(resourcesRootURL: resourcesRootURL) else {
            ensureProjectAssetFolders(projectAssetsURL: projectAssetsURL)
            return
        }

        let markerURL = projectAssetsURL.appendingPathComponent(".mce_defaults_version.json")
        let version = "1"
        var templatePaths: [String] = []
        var needsScan = true

        if let data = try? Data(contentsOf: markerURL),
           let marker = try? JSONDecoder().decode(DefaultAssetsMarker.self, from: data),
           marker.version == version {
            templatePaths = marker.paths
            needsScan = false
        }

        if needsScan {
            templatePaths = collectTemplateFilePaths(templateRoot: templateURL)
        }

        let missing = templatePaths.filter { relative in
            let target = projectAssetsURL.appendingPathComponent(relative)
            return !fileManager.fileExists(atPath: target.path)
        }

        if missing.isEmpty && !needsScan {
            return
        }

        copyMissingDefaults(from: templateURL, to: projectAssetsURL, relativePaths: missing)
        ensureProjectAssetFolders(projectAssetsURL: projectAssetsURL)

        let marker = DefaultAssetsMarker(version: version, paths: templatePaths)
        if let data = try? JSONEncoder().encode(marker) {
            try? data.write(to: markerURL, options: [.atomic])
        }
    }

    private func ensureProjectAssetFolders(projectAssetsURL: URL) {
        let folders = ["Materials", "Textures", "Meshes", "Scenes"]
        for folder in folders {
            let url = projectAssetsURL.appendingPathComponent(folder, isDirectory: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                PathUtils.ensureDirectoryExists(url)
            }
        }
    }

    private func collectTemplateFilePaths(templateRoot: URL) -> [String] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: templateRoot, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }
        var paths: [String] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true { continue }
            guard let relative = PathUtils.relativePath(from: templateRoot, to: url) else { continue }
            paths.append(relative)
        }
        return paths.sorted()
    }

    private func copyMissingDefaults(from templateRoot: URL, to assetsRoot: URL, relativePaths: [String]) {
        let fileManager = FileManager.default
        for relative in relativePaths {
            let source = templateRoot.appendingPathComponent(relative)
            let destination = assetsRoot.appendingPathComponent(relative)
            let parent = destination.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: parent.path) {
                PathUtils.ensureDirectoryExists(parent)
            }
            if !fileManager.fileExists(atPath: destination.path) {
                try? fileManager.copyItem(at: source, to: destination)
            }
        }
    }

    private func performStartupSanityCheck() {
        guard !didRunStartupCheck else { return }
        didRunStartupCheck = true

        let activeProject = projectRootURL?.path ?? "<none>"
        let assetsRoot = assetsRootPath?.path ?? "<none>"

        logCenter.logTrace("Editor startup activeProject=\(activeProject)", category: .project)
        logCenter.logTrace("Editor startup assetsRoot=\(assetsRoot)", category: .project)

        if let projectRootURL {
            if !FileManager.default.fileExists(atPath: projectRootURL.path) {
                alertCenter.enqueueError("Active project folder is missing.")
            }
        } else {
            logCenter.logInfo("No active project loaded.", category: .project)
        }

        assetRegistry?.refresh()
    }
}

private struct LegacyProjectDocument: Codable {
    var schemaVersion: Int
    var id: UUID
    var name: String
    var assetRootPath: String
    var defaultScenePath: String
    var rendererSettings: RendererSettingsDTO
    var editorStatePath: String
}

private func resolveContext(_ contextPtr: UnsafeMutableRawPointer) -> MCEContext {
    Unmanaged<MCEContext>.fromOpaque(contextPtr).takeUnretainedValue()
}

@_cdecl("MCEProjectSave")
public func MCEProjectSave(_ contextPtr: UnsafeMutableRawPointer) {
    resolveContext(contextPtr).editorProjectManager.saveProject()
}

@_cdecl("MCEProjectSaveAs")
public func MCEProjectSaveAs(_ contextPtr: UnsafeMutableRawPointer) {
    resolveContext(contextPtr).editorProjectManager.saveProjectAs()
}

@_cdecl("MCEProjectNew")
public func MCEProjectNew(_ contextPtr: UnsafeMutableRawPointer) {
    resolveContext(contextPtr).editorProjectManager.newProject()
}

@_cdecl("MCEProjectOpen")
public func MCEProjectOpen(_ contextPtr: UnsafeMutableRawPointer) {
    resolveContext(contextPtr).editorProjectManager.openProjectPanel()
}

@_cdecl("MCEProjectHasOpen")
public func MCEProjectHasOpen(_ contextPtr: UnsafeMutableRawPointer) -> UInt32 {
    return resolveContext(contextPtr).editorProjectManager.isProjectOpen ? 1 : 0
}

@_cdecl("MCEProjectNeedsModal")
public func MCEProjectNeedsModal(_ contextPtr: UnsafeMutableRawPointer) -> UInt32 {
    return resolveContext(contextPtr).editorProjectManager.needsProjectModal() ? 1 : 0
}

@_cdecl("MCEProjectDismissModal")
public func MCEProjectDismissModal(_ contextPtr: UnsafeMutableRawPointer) {
    resolveContext(contextPtr).editorProjectManager.dismissProjectModal()
}

@_cdecl("MCEProjectRecentCount")
public func MCEProjectRecentCount(_ contextPtr: UnsafeMutableRawPointer) -> Int32 {
    return Int32(resolveContext(contextPtr).editorProjectManager.recentProjects().count)
}

@_cdecl("MCEProjectRecentPathAt")
public func MCEProjectRecentPathAt(_ contextPtr: UnsafeMutableRawPointer,
                                   _ index: Int32,
                                   _ buffer: UnsafeMutablePointer<CChar>?,
                                   _ bufferSize: Int32) -> Int32 {
    let list = resolveContext(contextPtr).editorProjectManager.recentProjects()
    guard index >= 0, index < Int32(list.count), let buffer, bufferSize > 0 else { return 0 }
    let path = list[Int(index)]
    return path.withCString { ptr in
        let length = min(Int(bufferSize - 1), strlen(ptr))
        if length > 0 {
            memcpy(buffer, ptr, length)
        }
        buffer[length] = 0
        return Int32(length)
    }
}

@_cdecl("MCEProjectOpenRecent")
public func MCEProjectOpenRecent(_ contextPtr: UnsafeMutableRawPointer,
                                 _ path: UnsafePointer<CChar>?) -> UInt32 {
    guard let path else { return 0 }
    return resolveContext(contextPtr).editorProjectManager.openProjectAtPath(String(cString: path)) ? 1 : 0
}

@_cdecl("MCEProjectListCount")
public func MCEProjectListCount(_ contextPtr: UnsafeMutableRawPointer) -> Int32 {
    return Int32(resolveContext(contextPtr).editorProjectManager.projectListItems().count)
}

@_cdecl("MCEProjectListAt")
public func MCEProjectListAt(_ contextPtr: UnsafeMutableRawPointer,
                             _ index: Int32,
                             _ nameBuffer: UnsafeMutablePointer<CChar>?, _ nameBufferSize: Int32,
                             _ pathBuffer: UnsafeMutablePointer<CChar>?, _ pathBufferSize: Int32,
                             _ modifiedOut: UnsafeMutablePointer<Double>?) -> UInt32 {
    let list = resolveContext(contextPtr).editorProjectManager.projectListItems()
    let idx = Int(index)
    guard idx >= 0, idx < list.count else { return 0 }
    let item = list[idx]
    if let nameBuffer, nameBufferSize > 0 {
        _ = item.name.withCString { ptr in
            let length = min(Int(nameBufferSize - 1), strlen(ptr))
            if length > 0 {
                memcpy(nameBuffer, ptr, length)
            }
            nameBuffer[length] = 0
            return length
        }
    }
    if let pathBuffer, pathBufferSize > 0 {
        _ = item.url.path.withCString { ptr in
            let length = min(Int(pathBufferSize - 1), strlen(ptr))
            if length > 0 {
                memcpy(pathBuffer, ptr, length)
            }
            pathBuffer[length] = 0
            return length
        }
    }
    modifiedOut?.pointee = item.modified.timeIntervalSince1970
    return 1
}

@_cdecl("MCEProjectOpenAtPath")
public func MCEProjectOpenAtPath(_ contextPtr: UnsafeMutableRawPointer,
                                 _ path: UnsafePointer<CChar>?) -> UInt32 {
    guard let path else { return 0 }
    let ok = resolveContext(contextPtr).editorProjectManager.openProjectAtPath(String(cString: path))
    return ok ? 1 : 0
}

@_cdecl("MCEProjectDeleteAtPath")
public func MCEProjectDeleteAtPath(_ contextPtr: UnsafeMutableRawPointer,
                                   _ path: UnsafePointer<CChar>?) -> UInt32 {
    guard let path else { return 0 }
    let url = URL(fileURLWithPath: String(cString: path))
    return resolveContext(contextPtr).editorProjectManager.deleteProject(at: url) ? 1 : 0
}

@_cdecl("MCESceneSave")
public func MCESceneSave(_ contextPtr: UnsafeMutableRawPointer) {
    resolveContext(contextPtr).editorProjectManager.saveScene()
}

@_cdecl("MCESceneSaveAs")
public func MCESceneSaveAs(_ contextPtr: UnsafeMutableRawPointer) {
    resolveContext(contextPtr).editorProjectManager.saveSceneAs()
}

@_cdecl("MCESceneLoad")
public func MCESceneLoad(_ contextPtr: UnsafeMutableRawPointer) {
    resolveContext(contextPtr).editorProjectManager.openScenePanel()
}

@_cdecl("MCEScenePlay")
public func MCEScenePlay(_ contextPtr: UnsafeMutableRawPointer) {
    resolveContext(contextPtr).editorSceneController.play()
}

@_cdecl("MCESceneStop")
public func MCESceneStop(_ contextPtr: UnsafeMutableRawPointer) {
    resolveContext(contextPtr).editorSceneController.stop()
}

@_cdecl("MCEScenePause")
public func MCEScenePause(_ contextPtr: UnsafeMutableRawPointer) {
    resolveContext(contextPtr).editorSceneController.pause()
}

@_cdecl("MCESceneResume")
public func MCESceneResume(_ contextPtr: UnsafeMutableRawPointer) {
    resolveContext(contextPtr).editorSceneController.resume()
}

@_cdecl("MCESceneIsPlaying")
public func MCESceneIsPlaying(_ contextPtr: UnsafeMutableRawPointer) -> UInt32 {
    return resolveContext(contextPtr).editorSceneController.isPlaying ? 1 : 0
}

@_cdecl("MCESceneIsPaused")
public func MCESceneIsPaused(_ contextPtr: UnsafeMutableRawPointer) -> UInt32 {
    return resolveContext(contextPtr).editorSceneController.isPaused ? 1 : 0
}

@_cdecl("MCESceneIsDirty")
public func MCESceneIsDirty(_ contextPtr: UnsafeMutableRawPointer) -> UInt32 {
    return resolveContext(contextPtr).editorProjectManager.isSceneDirty() ? 1 : 0
}

@_cdecl("MCEProjectSaveAll")
public func MCEProjectSaveAll(_ contextPtr: UnsafeMutableRawPointer) {
    resolveContext(contextPtr).editorProjectManager.saveAll()
}

@_cdecl("MCEEditorSaveSettings")
public func MCEEditorSaveSettings(_ contextPtr: UnsafeMutableRawPointer) {
    resolveContext(contextPtr).editorProjectManager.saveSettings()
}

@_cdecl("MCEEditorGetPanelVisibility")
public func MCEEditorGetPanelVisibility(_ contextPtr: UnsafeMutableRawPointer,
                                        _ panelId: UnsafePointer<CChar>?,
                                        _ defaultValue: UInt32) -> UInt32 {
    guard let panelId else { return defaultValue }
    let key = String(cString: panelId)
    return resolveContext(contextPtr).editorProjectManager.panelIsVisible(key, defaultValue: defaultValue != 0) ? 1 : 0
}

@_cdecl("MCEEditorSetPanelVisibility")
public func MCEEditorSetPanelVisibility(_ contextPtr: UnsafeMutableRawPointer,
                                        _ panelId: UnsafePointer<CChar>?,
                                        _ visible: UInt32) {
    guard let panelId else { return }
    let key = String(cString: panelId)
    let manager = resolveContext(contextPtr).editorProjectManager
    manager.setPanelVisible(key, visible: visible != 0)
    manager.saveSettings()
}
@_cdecl("MCEEditorGetHeaderOpen")
public func MCEEditorGetHeaderOpen(_ contextPtr: UnsafeMutableRawPointer,
                                   _ headerId: UnsafePointer<CChar>?,
                                   _ defaultValue: UInt32) -> UInt32 {
    guard let headerId else { return defaultValue }
    let key = String(cString: headerId)
    return resolveContext(contextPtr).editorProjectManager.headerIsOpen(key, defaultValue: defaultValue != 0) ? 1 : 0
}

@_cdecl("MCEEditorSetHeaderOpen")
public func MCEEditorSetHeaderOpen(_ contextPtr: UnsafeMutableRawPointer,
                                   _ headerId: UnsafePointer<CChar>?,
                                   _ open: UInt32) {
    guard let headerId else { return }
    let key = String(cString: headerId)
    let manager = resolveContext(contextPtr).editorProjectManager
    manager.setHeaderOpen(key, open: open != 0)
    manager.saveSettings()
}

@_cdecl("MCEEditorGetLastSelectedEntityId")
public func MCEEditorGetLastSelectedEntityId(_ contextPtr: UnsafeMutableRawPointer,
                                             _ buffer: UnsafeMutablePointer<CChar>?,
                                             _ bufferSize: Int32) -> UInt32 {
    guard let buffer, bufferSize > 0 else { return 0 }
    let value = resolveContext(contextPtr).editorProjectManager.lastSelectedEntityId()
    let length = min(Int(bufferSize - 1), value.count)
    value.withCString { ptr in
        if length > 0 { memcpy(buffer, ptr, length) }
    }
    buffer[length] = 0
    return value.isEmpty ? 0 : 1
}

@_cdecl("MCEEditorSetLastSelectedEntityId")
public func MCEEditorSetLastSelectedEntityId(_ contextPtr: UnsafeMutableRawPointer,
                                             _ value: UnsafePointer<CChar>?) {
    guard let value else { return }
    let idString = String(cString: value)
    let context = resolveContext(contextPtr)
    context.editorProjectManager.setLastSelectedEntityId(idString)
    context.editorSceneController.setSelectedEntityId(idString)
    context.editorProjectManager.saveSettings()
}

@_cdecl("MCEEditorGetLastContentBrowserPath")
public func MCEEditorGetLastContentBrowserPath(_ contextPtr: UnsafeMutableRawPointer,
                                               _ buffer: UnsafeMutablePointer<CChar>?,
                                               _ bufferSize: Int32) -> UInt32 {
    guard let buffer, bufferSize > 0 else { return 0 }
    let value = resolveContext(contextPtr).editorProjectManager.lastContentBrowserPath()
    let length = min(Int(bufferSize - 1), value.count)
    value.withCString { ptr in
        if length > 0 { memcpy(buffer, ptr, length) }
    }
    buffer[length] = 0
    return value.isEmpty ? 0 : 1
}

@_cdecl("MCEEditorSetLastContentBrowserPath")
public func MCEEditorSetLastContentBrowserPath(_ contextPtr: UnsafeMutableRawPointer,
                                               _ value: UnsafePointer<CChar>?) {
    guard let value else { return }
    let manager = resolveContext(contextPtr).editorProjectManager
    manager.setLastContentBrowserPath(String(cString: value))
    manager.saveSettings()
}
