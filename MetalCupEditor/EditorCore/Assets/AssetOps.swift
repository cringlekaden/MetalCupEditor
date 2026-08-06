/// AssetOps.swift
/// Defines asset file operations for the editor.
/// Created by Kaden Cringle.

import Foundation
import ImageIO
import MetalCupEngine
import ModelIO
import simd

enum AssetOps {
    private static func resolveContext(_ contextPtr: UnsafeRawPointer?) -> MCEContext? {
        guard let contextPtr else { return nil }
        return Unmanaged<MCEContext>.fromOpaque(contextPtr).takeUnretainedValue()
    }

    private static func performAssetMutation(_ projectManager: EditorProjectManager, _ operation: () -> Bool) -> Bool {
        projectManager.performAssetMutation { operation() }
    }

    static func createFolder(context: UnsafeRawPointer?, relativePath: String?, name: String?) -> Bool {
        guard let context = resolveContext(context) else { return false }
        let projectManager = context.editorProjectManager
        let alertCenter = context.editorAlertCenter
        let logCenter = context.engineContext.log
        guard let rootURL = projectManager.assetRootURL() else { return false }
        let rel = relativePath ?? ""
        let folderName = name ?? "New Folder"
        guard let targetParent = resolveDirectoryURL(rootURL: rootURL, relativePath: rel) else { return false }
        let targetURL = targetParent.appendingPathComponent(folderName, isDirectory: true)
        let ok = performAssetMutation(projectManager) {
            do {
                try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
                return true
            } catch {
                alertCenter.enqueueError("Failed to create folder: \(error.localizedDescription)")
                return false
            }
        }
        if ok {
            logCenter.logInfo("Created folder: \(folderName)", category: .assets)
        }
        return ok
    }

    static func createScene(context: UnsafeRawPointer?, relativePath: String?, name: String?) -> Bool {
        guard let context = resolveContext(context) else { return false }
        let projectManager = context.editorProjectManager
        let alertCenter = context.editorAlertCenter
        let logCenter = context.engineContext.log
        guard let rootURL = projectManager.assetRootURL() else { return false }
        let rel = relativePath ?? ""
        let sceneName = name ?? "Untitled"
        guard let folderURL = resolveDirectoryURL(rootURL: rootURL, relativePath: rel) else { return false }
        let targetURL = folderURL.appendingPathComponent("\(sceneName).mcscene")
        let document = SceneDocument(id: UUID(), name: sceneName, entities: [])
        let scene = SerializedScene(document: document, engineContext: context.engineContext)
        let ok = performAssetMutation(projectManager) {
            do {
                try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
                try SceneSerializer.save(scene: scene, to: targetURL)
                return true
            } catch {
                alertCenter.enqueueError("Failed to create scene: \(error.localizedDescription)")
                return false
            }
        }
        if ok {
            logCenter.logInfo("Created scene: \(sceneName)", category: .scene)
        }
        return ok
    }

    static func createPrefab(context: UnsafeRawPointer?, relativePath: String?, name: String?) -> Bool {
        guard let context = resolveContext(context) else { return false }
        let projectManager = context.editorProjectManager
        let alertCenter = context.editorAlertCenter
        let logCenter = context.engineContext.log
        guard let rootURL = projectManager.assetRootURL() else { return false }
        let rel = (relativePath == nil || relativePath?.isEmpty == true) ? "Prefabs" : (relativePath ?? "")
        let prefabName = name ?? "Prefab"
        guard let folderURL = resolveDirectoryURL(rootURL: rootURL, relativePath: rel) else { return false }
        let targetURL = folderURL.appendingPathComponent("\(prefabName).prefab")
        let prefab = PrefabDocument(name: prefabName, entities: [])
        let ok = performAssetMutation(projectManager) {
            do {
                try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
                try PrefabSerializer.save(prefab: prefab, to: targetURL)
                return true
            } catch {
                alertCenter.enqueueError("Failed to create prefab: \(error.localizedDescription)")
                return false
            }
        }
        if ok {
            logCenter.logInfo("Created prefab: \(prefabName)", category: .assets)
        }
        return ok
    }

    static func createScript(context: UnsafeRawPointer?, relativePath: String?, name: String?) -> Bool {
        guard let context = resolveContext(context) else { return false }
        let projectManager = context.editorProjectManager
        let alertCenter = context.editorAlertCenter
        let logCenter = context.engineContext.log
        guard let rootURL = projectManager.assetRootURL() else { return false }
        let rel = (relativePath == nil || relativePath?.isEmpty == true) ? "Scripts" : (relativePath ?? "")
        let scriptName = name ?? "NewScript"
        guard let folderURL = resolveDirectoryURL(rootURL: rootURL, relativePath: rel) else { return false }
        let targetURL = folderURL.appendingPathComponent("\(scriptName).lua")
        let entryType = sanitizeName(scriptName)
        let template = """
        -- MetalCup script template
        -- Entry type: \(entryType.isEmpty ? "NewScript" : entryType)
        
        return {
            OnCreate = function(self)
            end,
            OnStart = function(self)
            end,
            OnUpdate = function(self, dt)
            end,
            OnFixedUpdate = function(self, dt)
            end,
            OnDestroy = function(self)
            end
        }
        """
        let ok = performAssetMutation(projectManager) {
            do {
                try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
                try template.write(to: targetURL, atomically: true, encoding: .utf8)
                return true
            } catch {
                alertCenter.enqueueError("Failed to create script: \(error.localizedDescription)")
                return false
            }
        }
        if ok {
            logCenter.logInfo("Created script: \(scriptName)", category: .assets)
        }
        return ok
    }

    static func createAnimationGraph(context: UnsafeRawPointer?, relativePath: String?, name: String?) -> AssetHandle? {
        guard let context = resolveContext(context) else { return nil }
        let projectManager = context.editorProjectManager
        let alertCenter = context.editorAlertCenter
        let logCenter = context.engineContext.log
        guard let rootURL = projectManager.assetRootURL() else { return nil }
        let rel = (relativePath == nil || relativePath?.isEmpty == true) ? "AnimationGraphs" : (relativePath ?? "")
        let graphName = sanitizeName((name == nil || name?.isEmpty == true) ? "NewAnimationGraph" : (name ?? "NewAnimationGraph"))
        guard let folderURL = resolveDirectoryURL(rootURL: rootURL, relativePath: rel) else { return nil }
        let graphURL = uniqueFileURL(folder: folderURL, baseName: graphName, fileExtension: "mcanimgraph")
        let handle = AssetHandle()
        let outputNodeID = UUID()
        let outputNode = AnimationGraphNodeDefinition(
            id: outputNodeID,
            type: .outputPose,
            title: "Output Pose",
            position: SIMD2<Float>(320.0, 120.0)
        )
        let relativePathValue = graphURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
        let graphAsset = AnimationGraphAsset(
            handle: handle,
            name: graphURL.deletingPathExtension().lastPathComponent,
            sourcePath: relativePathValue,
            outputNodeID: outputNodeID,
            parameters: [],
            nodes: [outputNode],
            links: []
        )
        let ok = performAssetMutation(projectManager) {
            do {
                try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            } catch {
                alertCenter.enqueueError("Failed to create animation graph folder: \(error.localizedDescription)")
                return false
            }
            if !AnimationGraphAssetSerializer.save(graphAsset, to: graphURL) {
                alertCenter.enqueueError("Failed to save animation graph file.")
                return false
            }
            registerAssetMetadata(projectManager: projectManager,
                                  handle: handle,
                                  type: .animationGraph,
                                  assetURL: graphURL,
                                  rootURL: rootURL)
            return true
        }
        if ok {
            logCenter.logInfo("Created animation graph: \(graphAsset.name)", category: .assets)
            return handle
        }
        return nil
    }

    static func createPrefab(context: UnsafeRawPointer?, prefab: PrefabDocument, relativePath: String?, name: String?) -> String? {
        guard let context = resolveContext(context) else { return nil }
        let projectManager = context.editorProjectManager
        let alertCenter = context.editorAlertCenter
        let logCenter = context.engineContext.log
        guard let rootURL = projectManager.assetRootURL() else { return nil }
        let rel = (relativePath == nil || relativePath?.isEmpty == true) ? "Prefabs" : (relativePath ?? "")
        let baseName = sanitizeName(name ?? prefab.name).isEmpty ? "Prefab" : sanitizeName(name ?? prefab.name)
        guard let folderURL = resolveDirectoryURL(rootURL: rootURL, relativePath: rel) else { return nil }
        let targetURL = uniqueFileURL(folder: folderURL, baseName: baseName, fileExtension: "prefab")
        var finalPrefab = prefab
        finalPrefab.name = targetURL.deletingPathExtension().lastPathComponent
        var createdPath: String?
        let ok = performAssetMutation(projectManager) {
            do {
                try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
                try PrefabSerializer.save(prefab: finalPrefab, to: targetURL)
                createdPath = PathUtils.relativePath(from: rootURL, to: targetURL)
                return true
            } catch {
                alertCenter.enqueueError("Failed to create prefab: \(error.localizedDescription)")
                return false
            }
        }
        if ok {
            logCenter.logInfo("Created prefab: \(finalPrefab.name)", category: .assets)
        }
        return ok ? createdPath : nil
    }

    static func createMaterial(context: UnsafeRawPointer?, named name: String, relativePath: String? = nil) -> AssetHandle? {
        guard let context = resolveContext(context) else { return nil }
        let projectManager = context.editorProjectManager
        let alertCenter = context.editorAlertCenter
        let logCenter = context.engineContext.log
        guard let rootURL = projectManager.assetRootURL() else { return nil }
        var rel = relativePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if rel.hasPrefix("Assets/") {
            rel = String(rel.dropFirst("Assets/".count))
        }
        let materialsFolder = rel.isEmpty
            ? rootURL
            : rootURL.appendingPathComponent(rel, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: materialsFolder, withIntermediateDirectories: true)
        } catch {
            alertCenter.enqueueError("Failed to create material folder: \(error.localizedDescription)")
            return nil
        }

        let baseName = sanitizeName(name.isEmpty ? "Material" : name)
        let materialURL = uniqueFileURL(folder: materialsFolder, baseName: baseName, fileExtension: "mcmat")
        let handle = AssetHandle()
        let material = MaterialAsset.default(handle: handle, name: baseName)
        let ok = performAssetMutation(projectManager) {
            if !MaterialSerializer.save(material, to: materialURL) {
                alertCenter.enqueueError("Failed to save material file.")
                return false
            }
            registerMaterialMetadata(projectManager: projectManager, handle: handle, materialURL: materialURL, rootURL: rootURL)
            return true
        }
        if ok {
            logCenter.logInfo("Saved material: \(baseName)", category: .assets)
        }
        return ok ? handle : nil
    }

    static func renameMaterial(context: UnsafeRawPointer?, handle: AssetHandle, newName: String) -> Bool {
        guard let context = resolveContext(context) else { return false }
        let projectManager = context.editorProjectManager
        let alertCenter = context.editorAlertCenter
        let logCenter = context.engineContext.log
        let sanitized = sanitizeName(newName)
        guard !sanitized.isEmpty else { return false }
        guard let rootURL = projectManager.assetRootURL(),
              let metadata = metadata(projectManager: projectManager, for: handle),
              let assetURL = projectManager.assetURL(for: handle) else { return false }
        guard isProjectAssetURL(assetURL, rootURL: rootURL) else {
            alertCenter.enqueueError("Shared Assets are read-only.")
            return false
        }

        let newURL = uniqueFileURL(folder: assetURL.deletingLastPathComponent(), baseName: sanitized, fileExtension: "mcmat")
        let ok = performAssetMutation(projectManager) {
            do {
                try FileManager.default.moveItem(at: assetURL, to: newURL)
            } catch {
                alertCenter.enqueueError("Failed to rename material: \(error.localizedDescription)")
                return false
            }

            if let material = MaterialSerializer.load(from: newURL, fallbackHandle: handle) {
                var updated = material
                updated.name = sanitized
                _ = MaterialSerializer.save(updated, to: newURL)
            }

            let oldMetaURL = projectManager.metaURLForAsset(assetURL: assetURL, relativePath: metadata.sourcePath)
            let newRelativePath = newURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
            let newMetaURL = projectManager.metaURLForAsset(assetURL: newURL, relativePath: newRelativePath)
            if let oldMetaURL, let newMetaURL, FileManager.default.fileExists(atPath: oldMetaURL.path) {
                try? FileManager.default.moveItem(at: oldMetaURL, to: newMetaURL)
            }

            if let newMetaURL {
                let updatedMeta = AssetMetadata(
                    handle: handle,
                    type: .material,
                    sourcePath: newRelativePath,
                    importSettings: metadata.importSettings,
                    dependencies: metadata.dependencies,
                    lastModified: Date().timeIntervalSince1970
                )
                projectManager.saveMetadata(updatedMeta, to: newMetaURL)
            }
            return true
        }

        if ok {
            logCenter.logInfo("Renamed material to: \(sanitized)", category: .assets)
        }
        return ok
    }

    static func duplicateMaterial(context: UnsafeRawPointer?, handle: AssetHandle) -> AssetHandle? {
        guard let context = resolveContext(context) else { return nil }
        let projectManager = context.editorProjectManager
        let alertCenter = context.editorAlertCenter
        let logCenter = context.engineContext.log
        guard let rootURL = projectManager.assetRootURL(),
              let assetURL = projectManager.assetURL(for: handle) else { return nil }
        guard isProjectAssetURL(assetURL, rootURL: rootURL) else {
            alertCenter.enqueueError("Shared Assets are read-only.")
            return nil
        }
        let baseName = assetURL.deletingPathExtension().lastPathComponent + " Copy"
        let newURL = uniqueFileURL(folder: assetURL.deletingLastPathComponent(), baseName: baseName, fileExtension: "mcmat")
        let newHandle = AssetHandle()
        let material = MaterialSerializer.load(from: assetURL, fallbackHandle: handle)
            ?? MaterialAsset.default(handle: newHandle, name: baseName)
        var duplicate = material
        duplicate.handle = newHandle
        duplicate.name = baseName
        let ok = performAssetMutation(projectManager) {
            if !MaterialSerializer.save(duplicate, to: newURL) {
                alertCenter.enqueueError("Failed to duplicate material.")
                return false
            }
            registerMaterialMetadata(projectManager: projectManager, handle: newHandle, materialURL: newURL, rootURL: rootURL)
            return true
        }
        if ok {
            logCenter.logInfo("Duplicated material: \(baseName)", category: .assets)
        }
        return ok ? newHandle : nil
    }

    static func deleteMaterial(context: UnsafeRawPointer?, handle: AssetHandle) -> Bool {
        guard let context = resolveContext(context) else { return false }
        let projectManager = context.editorProjectManager
        let alertCenter = context.editorAlertCenter
        let logCenter = context.engineContext.log
        guard let metadata = metadata(projectManager: projectManager, for: handle),
              let assetURL = projectManager.assetURL(for: handle) else { return false }
        if let rootURL = projectManager.assetRootURL(),
           !isProjectAssetURL(assetURL, rootURL: rootURL) {
            alertCenter.enqueueError("Shared Assets are read-only.")
            return false
        }
        let ok = performAssetMutation(projectManager) {
            do {
                try FileManager.default.removeItem(at: assetURL)
            } catch {
                alertCenter.enqueueError("Failed to delete material: \(error.localizedDescription)")
                return false
            }
            if let metaURL = projectManager.metaURLForAsset(assetURL: assetURL, relativePath: metadata.sourcePath) {
                try? FileManager.default.removeItem(at: metaURL)
            }
            return true
        }
        if ok {
            logCenter.logInfo("Deleted material.", category: .assets)
        }
        return ok
    }

    static func renameAsset(context: UnsafeRawPointer?, relativePath: String, newName: String) -> URL? {
        guard let context = resolveContext(context) else { return nil }
        let projectManager = context.editorProjectManager
        let logCenter = context.engineContext.log
        guard let rootURL = projectManager.assetRootURL() else { return nil }
        guard let assetURL = resolveAssetURL(rootURL: rootURL, relativePath: relativePath) else { return nil }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: assetURL.path, isDirectory: &isDirectory) else { return nil }

        let sanitizedBase = sanitizeFileName(baseNameWithoutExtension(newName), fallback: "Asset")
        if sanitizedBase.isEmpty { return nil }

        let parentURL = assetURL.deletingLastPathComponent()
        let newURL: URL
        if isDirectory.boolValue {
            newURL = parentURL.appendingPathComponent(sanitizedBase, isDirectory: true)
        } else {
            let ext = assetURL.pathExtension
            if ext.isEmpty {
                newURL = parentURL.appendingPathComponent(sanitizedBase)
            } else {
                newURL = parentURL.appendingPathComponent("\(sanitizedBase).\(ext)")
            }
        }

        if newURL.standardizedFileURL.path == assetURL.standardizedFileURL.path { return newURL }
        if FileManager.default.fileExists(atPath: newURL.path) { return nil }

        let ok = projectManager.performAssetMutation {
            try FileManager.default.moveItem(at: assetURL, to: newURL)
            if !isDirectory.boolValue {
                let oldMeta = AssetIO.metaURL(for: assetURL)
                let newMeta = AssetIO.metaURL(for: newURL)
                if FileManager.default.fileExists(atPath: oldMeta.path) {
                    try? FileManager.default.moveItem(at: oldMeta, to: newMeta)
                }
                AssetIO.updateMaterialNameIfNeeded(url: newURL, newName: sanitizedBase)
                AssetIO.updateSceneNameIfNeeded(url: newURL, newName: sanitizedBase)
            }
            return true
        }

        guard ok else { return nil }
        logCenter.logInfo("Renamed asset: \(relativePath) -> \(newURL.lastPathComponent)", category: .assets)
        return newURL
    }

    static func deleteAsset(context: UnsafeRawPointer?, relativePath: String) -> Bool {
        guard let context = resolveContext(context) else { return false }
        let projectManager = context.editorProjectManager
        let logCenter = context.engineContext.log
        guard let rootURL = projectManager.assetRootURL() else { return false }
        guard let assetURL = resolveAssetURL(rootURL: rootURL, relativePath: relativePath) else { return false }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: assetURL.path, isDirectory: &isDirectory) else { return false }

        let ok = projectManager.performAssetMutation {
            if isDirectory.boolValue {
                try FileManager.default.removeItem(at: assetURL)
            } else {
                try FileManager.default.removeItem(at: assetURL)
                let metaURL = AssetIO.metaURL(for: assetURL)
                if FileManager.default.fileExists(atPath: metaURL.path) {
                    try? FileManager.default.removeItem(at: metaURL)
                }
            }
            return true
        }

        if ok {
            logCenter.logInfo("Deleted asset: \(relativePath)", category: .assets)
            return true
        }
        return false
    }

    static func duplicateAsset(context: UnsafeRawPointer?, relativePath: String) -> URL? {
        guard let context = resolveContext(context) else { return nil }
        let projectManager = context.editorProjectManager
        let logCenter = context.engineContext.log
        guard let rootURL = projectManager.assetRootURL() else { return nil }
        guard let assetURL = resolveAssetURL(rootURL: rootURL, relativePath: relativePath) else { return nil }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: assetURL.path, isDirectory: &isDirectory) else { return nil }
        guard !isDirectory.boolValue else { return nil }

        let baseName = assetURL.deletingPathExtension().lastPathComponent
        let ext = assetURL.pathExtension
        if ext.lowercased() == "mcmat" { return nil }

        let newURL = uniqueCopyURL(folder: assetURL.deletingLastPathComponent(), baseName: baseName, fileExtension: ext)
        let ok = projectManager.performAssetMutation {
            try FileManager.default.copyItem(at: assetURL, to: newURL)
            AssetIO.updateSceneNameIfNeeded(url: newURL, newName: newURL.deletingPathExtension().lastPathComponent)
            return true
        }

        guard ok else { return nil }
        logCenter.logInfo("Duplicated asset: \(relativePath)", category: .assets)
        return newURL
    }

    static func resolveDirectoryURL(rootURL: URL, relativePath: String) -> URL? {
        guard let sanitized = sanitizeRelativePath(relativePath) else { return nil }
        var normalized = sanitized
        if normalized.hasPrefix("Assets/") {
            normalized = String(normalized.dropFirst("Assets/".count))
        }
        let target = normalized.isEmpty ? rootURL : rootURL.appendingPathComponent(normalized, isDirectory: true)
        let standardizedRoot = rootURL.standardizedFileURL
        let standardizedTarget = target.standardizedFileURL
        guard standardizedTarget.path.hasPrefix(standardizedRoot.path) else { return nil }
        return standardizedTarget
    }

    static func resolveAssetURL(rootURL: URL, relativePath: String) -> URL? {
        guard let sanitized = sanitizeRelativePath(relativePath), !sanitized.isEmpty else { return nil }
        var normalized = sanitized
        if normalized.hasPrefix("Assets/") {
            normalized = String(normalized.dropFirst("Assets/".count))
        }
        let target = rootURL.appendingPathComponent(normalized)
        let standardizedRoot = rootURL.standardizedFileURL
        let standardizedTarget = target.standardizedFileURL
        guard standardizedTarget.path.hasPrefix(standardizedRoot.path) else { return nil }
        return standardizedTarget
    }

    static func sanitizeRelativePath(_ path: String?) -> String? {
        guard let path else { return "" }
        return PathUtils.sanitizeRelativePath(path)
    }

    private static func registerMaterialMetadata(projectManager: EditorProjectManager,
                                                 handle: AssetHandle,
                                                 materialURL: URL,
                                                 rootURL: URL) {
        registerAssetMetadata(projectManager: projectManager,
                              handle: handle,
                              type: .material,
                              assetURL: materialURL,
                              rootURL: rootURL)
    }

    private static func registerAssetMetadata(projectManager: EditorProjectManager,
                                              handle: AssetHandle,
                                              type: AssetType,
                                              assetURL: URL,
                                              rootURL: URL) {
        let relativePath = assetURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
        guard let metaURL = projectManager.metaURLForAsset(assetURL: assetURL, relativePath: relativePath) else { return }
        let metadata = AssetMetadata(
            handle: handle,
            type: type,
            sourcePath: relativePath,
            importSettings: [:],
            dependencies: [],
            lastModified: Date().timeIntervalSince1970
        )
        projectManager.saveMetadata(metadata, to: metaURL)
    }

    private static func metadata(projectManager: EditorProjectManager, for handle: AssetHandle) -> AssetMetadata? {
        let snapshot = projectManager.assetMetadataSnapshot()
        return snapshot.first(where: { $0.handle == handle })
    }

    private static func sanitizeName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Material" }
        let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|")
        return trimmed.components(separatedBy: invalid).joined(separator: "_")
    }

    private static func sanitizeFileName(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|")
        let sanitized = trimmed.components(separatedBy: invalid).joined(separator: "_")
        return sanitized.isEmpty ? fallback : sanitized
    }

    private static func baseNameWithoutExtension(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        return URL(fileURLWithPath: trimmed).deletingPathExtension().lastPathComponent
    }

    private static func uniqueFileURL(folder: URL, baseName: String, fileExtension: String) -> URL {
        let fm = FileManager.default
        var candidate = folder.appendingPathComponent("\(baseName).\(fileExtension)")
        if !fm.fileExists(atPath: candidate.path) { return candidate }
        var index = 1
        while true {
            let name = "\(baseName) \(index)"
            candidate = folder.appendingPathComponent("\(name).\(fileExtension)")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }

    private static func uniqueCopyURL(folder: URL, baseName: String, fileExtension: String) -> URL {
        let fm = FileManager.default
        let baseCopy = baseName + " Copy"
        let hasExtension = !fileExtension.isEmpty
        var candidate = folder.appendingPathComponent(hasExtension ? "\(baseCopy).\(fileExtension)" : baseCopy)
        if !fm.fileExists(atPath: candidate.path) { return candidate }
        var index = 2
        while true {
            let name = "\(baseCopy) \(index)"
            candidate = folder.appendingPathComponent(hasExtension ? "\(name).\(fileExtension)" : name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }

    private static func isProjectAssetURL(_ url: URL, rootURL: URL) -> Bool {
        let rootPath = rootURL.standardizedFileURL.path
        let targetPath = url.standardizedFileURL.path
        return targetPath == rootPath || targetPath.hasPrefix(rootPath + "/")
    }
}

// MARK: - Asset Importing (Phase 2)

struct AssetPathResolver {
    let assetsRootURL: URL

    func destinationFolder(for type: AssetType) -> URL? {
        switch type {
        case .texture:
            return assetsRootURL.appendingPathComponent("Textures", isDirectory: true)
        case .model:
            return assetsRootURL.appendingPathComponent("Meshes", isDirectory: true)
        case .environment:
            return assetsRootURL.appendingPathComponent("Environments", isDirectory: true)
        case .material:
            return assetsRootURL.appendingPathComponent("Materials", isDirectory: true)
        case .prefab:
            return assetsRootURL.appendingPathComponent("Prefabs", isDirectory: true)
        case .scene:
            return assetsRootURL.appendingPathComponent("Scenes", isDirectory: true)
        case .script:
            return assetsRootURL.appendingPathComponent("Scripts", isDirectory: true)
        case .skeleton:
            return assetsRootURL.appendingPathComponent("Skeletons", isDirectory: true)
        case .animationClip:
            return assetsRootURL.appendingPathComponent("Animations", isDirectory: true)
        case .animationGraph:
            return assetsRootURL.appendingPathComponent("AnimationGraphs", isDirectory: true)
        case .audio:
            return assetsRootURL.appendingPathComponent("Audio", isDirectory: true)
        case .unknown:
            return nil
        @unknown default:
            return nil
        }
    }

    func destinationURL(for type: AssetType, suggestedName: String, ext: String) -> URL? {
        guard let folder = destinationFolder(for: type) else { return nil }
        let base = sanitizeFileName(suggestedName.isEmpty ? "Asset" : suggestedName)
        return uniqueFileURL(in: folder, baseName: base, ext: ext)
    }

    private func uniqueFileURL(in folder: URL, baseName: String, ext: String) -> URL {
        let fm = FileManager.default
        let trimmedExt = ext.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = trimmedExt.isEmpty ? "" : ".\(trimmedExt)"
        var candidate = folder.appendingPathComponent(baseName + suffix)
        if !fm.fileExists(atPath: candidate.path) { return candidate }
        var index = 1
        while true {
            let name = "\(baseName)_\(index)"
            candidate = folder.appendingPathComponent(name + suffix)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }

    private func sanitizeFileName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|")
        let sanitized = trimmed.components(separatedBy: invalid).joined(separator: "_")
        return sanitized.isEmpty ? "Asset" : sanitized
    }
}

struct ImportScanResult {
    let sourceURL: URL
    let assetType: AssetType
    let suggestedName: String
    let details: [String: String]
    let meshInfo: MeshScanInfo?
}

struct MeshScanInfo {
    let meshCount: Int
    let submeshCount: Int
    let submeshMaterialIndices: [Int]
    let materialNames: [String]
    let textureNames: [String]
    let hasUVs: Bool
    let hasNormals: Bool
    let hasTangents: Bool
    let suggestFlipNormalY: Bool
    let embeddedTextureCount: Int
    let isSkinned: Bool
    let skeletonInfo: MeshSkeletonScanInfo?
    let clipInfos: [MeshAnimationClipScanInfo]
    let hasRootMotion: Bool
    let rootMotionBoneName: String?
    let warnings: [String]
    let materials: [MeshScanMaterial]
}

struct MeshSkeletonScanInfo {
    let jointCount: Int
    let joints: [SkeletonAsset.Joint]
}

struct MeshAnimationClipScanInfo {
    let name: String
    let durationSeconds: Float
    let tracks: [AnimationClipAsset.JointTrack]
}

enum MeshTextureSemantic: String {
    case baseColor
    case normal
    case metallicRoughness
    case metallic
    case roughness
    case occlusion
    case emissive
}

struct MeshScanTexture {
    let semantic: MeshTextureSemantic
    let url: URL?
    let name: String
    let isEmbedded: Bool
    let mdlTexture: MDLTexture?
}

struct MeshScanMaterial {
    let name: String
    let baseColor: SIMD3<Float>
    let emissiveColor: SIMD3<Float>
    let metallicFactor: Float
    let roughnessFactor: Float
    let aoFactor: Float
    let alphaMode: MaterialAlphaMode
    let alphaCutoff: Float
    let doubleSided: Bool
    let unlit: Bool
    let textures: [MeshTextureSemantic: MeshScanTexture]
}

struct ImportSettings {
    var values: [String: String]

    func boolValue(_ key: String, default defaultValue: Bool) -> Bool {
        guard let raw = values[key]?.lowercased() else { return defaultValue }
        return raw == "true" || raw == "1" || raw == "yes"
    }
}

struct ImportCommitResult {
    let primaryHandle: AssetHandle
    let writtenPaths: [String]
    let dependencyHandles: [AssetHandle]
    let meshPath: String?
    let skeletonHandle: AssetHandle?
    let defaultClipHandle: AssetHandle?
    let submeshMaterialHandles: [AssetHandle]
}

private struct TextureImportDiagnostics {
    let sourceAssetPath: String
    let width: Int
    let height: Int
    let channelCount: Int
    let bitDepth: Int
    let semantic: String
    let srgb: Bool
    let internalPixelFormat: String
    let outputFormat: String
    let failedStage: String
    let reason: String

    func formattedLog() -> String {
        return """
        Texture import failed:
          sourcePath=\(sourceAssetPath)
          stage=\(failedStage)
          reason=\(reason)
          decoded=\(width)x\(height), channels=\(channelCount), bitDepth=\(bitDepth)
          semantic=\(semantic), colorSpace=\(srgb ? "sRGB" : "Linear")
          internalPixelFormat=\(internalPixelFormat), outputFormat=\(outputFormat)
        """
    }
}

private enum TextureProbeOutcome {
    case success(TextureImportDiagnostics)
    case failure(TextureImportDiagnostics)
}

private enum EmbeddedTextureExportOutcome {
    case success
    case failure(String)
}

private func inferInternalPixelFormat(srgb: Bool, bitDepth: Int, channelCount: Int) -> String {
    if bitDepth > 8 {
        if channelCount >= 4 { return "rgba16Float" }
        if channelCount == 3 { return "rgb16Float" }
        return "r16Float"
    }
    if channelCount >= 4 { return srgb ? "rgba8Unorm_srgb" : "rgba8Unorm" }
    if channelCount == 2 { return "rg8Unorm" }
    return "r8Unorm"
}

private func probeTextureImport(url: URL, semantic: String, srgb: Bool, outputFormat: String) -> TextureProbeOutcome {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        let diag = TextureImportDiagnostics(
            sourceAssetPath: url.path,
            width: 0,
            height: 0,
            channelCount: 0,
            bitDepth: 0,
            semantic: semantic,
            srgb: srgb,
            internalPixelFormat: inferInternalPixelFormat(srgb: srgb, bitDepth: 0, channelCount: 4),
            outputFormat: outputFormat,
            failedStage: "decode",
            reason: "CGImageSourceCreateWithURL returned nil"
        )
        return .failure(diag)
    }

    guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        let diag = TextureImportDiagnostics(
            sourceAssetPath: url.path,
            width: 0,
            height: 0,
            channelCount: 0,
            bitDepth: 0,
            semantic: semantic,
            srgb: srgb,
            internalPixelFormat: inferInternalPixelFormat(srgb: srgb, bitDepth: 0, channelCount: 4),
            outputFormat: outputFormat,
            failedStage: "decode",
            reason: "CGImageSourceCreateImageAtIndex returned nil"
        )
        return .failure(diag)
    }

    let width = image.width
    let height = image.height
    let bitsPerPixel = image.bitsPerPixel
    let bitsPerComponent = image.bitsPerComponent
    let channels = bitsPerComponent > 0 ? max(1, bitsPerPixel / bitsPerComponent) : 0
    let bitDepth = max(bitsPerComponent, 0)

    let diag = TextureImportDiagnostics(
        sourceAssetPath: url.path,
        width: width,
        height: height,
        channelCount: channels,
        bitDepth: bitDepth,
        semantic: semantic,
        srgb: srgb,
        internalPixelFormat: inferInternalPixelFormat(srgb: srgb, bitDepth: bitDepth, channelCount: channels),
        outputFormat: outputFormat,
        failedStage: "",
        reason: ""
    )
    return .success(diag)
}

private func defaultTextureImportSettings(settings: ImportSettings,
                                          importerId: String,
                                          importerVersion: String,
                                          sourcePath: String,
                                          sourcePathAbs: String) -> [String: String] {
    var merged = settings.values
    merged["importer"] = importerId
    merged["importerVersion"] = importerVersion
    merged["sourcePath"] = sourcePath
    merged["sourcePathAbs"] = sourcePathAbs
    return merged
}

private func setTextureFailureState(projectManager: EditorProjectManager,
                                    scan: ImportScanResult,
                                    settings: ImportSettings,
                                    importerId: String,
                                    importerVersion: String,
                                    reason: String) {
    guard let rootURL = projectManager.assetRootURL() else { return }
    let sourceURL = scan.sourceURL.standardizedFileURL
    guard isUnderRoot(sourceURL, rootURL: rootURL),
          let relativePath = PathUtils.relativePath(from: rootURL, to: sourceURL) else {
        return
    }

    let metaURL = projectManager.metaURLForAsset(assetURL: sourceURL, relativePath: relativePath) ?? AssetIO.metaURL(for: sourceURL)
    let existing = (try? Data(contentsOf: metaURL)).flatMap { try? JSONDecoder().decode(AssetMetadata.self, from: $0) }
    let sourceRelativePath = relativePath
    let settingsValues = defaultTextureImportSettings(
        settings: settings,
        importerId: importerId,
        importerVersion: importerVersion,
        sourcePath: sourceRelativePath,
        sourcePathAbs: sourceURL.path
    )
    var failedSettings = settingsValues
    failedSettings["importFailed"] = "true"
    failedSettings["importFailureReason"] = reason
    failedSettings["importFailureAt"] = String(format: "%.3f", Date().timeIntervalSince1970)
    let metadata = AssetMetadata(
        handle: existing?.handle ?? AssetHandle(),
        type: .texture,
        sourcePath: relativePath,
        importSettings: failedSettings,
        dependencies: existing?.dependencies ?? [],
        lastModified: Date().timeIntervalSince1970
    )
    projectManager.saveMetadata(metadata, to: metaURL)
}

protocol AssetImporter {
    var importerId: String { get }
    var importerVersion: String { get }
    func canImport(_ url: URL) -> Bool
    func scan(_ url: URL) -> ImportScanResult?
    func defaultSettings(for scan: ImportScanResult) -> ImportSettings
    func commit(scan: ImportScanResult,
                settings: ImportSettings,
                projectManager: EditorProjectManager,
                resolver: AssetPathResolver) -> ImportCommitResult?
}

struct TextureImporter: AssetImporter {
    let importerId = "TextureImporter"
    let importerVersion = "1"

    func canImport(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "tga", "bmp", "tif", "tiff"].contains(ext)
    }

    func scan(_ url: URL) -> ImportScanResult? {
        guard canImport(url) else { return nil }
        let name = url.deletingPathExtension().lastPathComponent
        let semantic = guessTextureSemantic(from: name)
        let srgb = isColorSemantic(semantic) ? "true" : "false"
        return ImportScanResult(
            sourceURL: url,
            assetType: .texture,
            suggestedName: name,
            details: [
                "semantic": semantic,
                "srgb": srgb
            ],
            meshInfo: nil
        )
    }

    func defaultSettings(for scan: ImportScanResult) -> ImportSettings {
        let name = scan.sourceURL.lastPathComponent
        let mipmaps = AssetManager.shouldGenerateMipmaps(path: name)
        let semantic = guessTextureSemantic(from: scan.suggestedName)
        let srgb = isColorSemantic(semantic)
        var values: [String: String] = [
            "srgb": srgb ? "true" : "false",
            "mipmaps": mipmaps ? "true" : "false"
        ]
        if !semantic.isEmpty {
            values["semantic"] = semantic
        }
        return ImportSettings(values: values)
    }

    func commit(scan: ImportScanResult,
                settings: ImportSettings,
                projectManager: EditorProjectManager,
                resolver: AssetPathResolver) -> ImportCommitResult? {
        let semantic = settings.values["semantic"]?.lowercased().isEmpty == false
            ? (settings.values["semantic"]?.lowercased() ?? "")
            : guessTextureSemantic(from: scan.suggestedName)
        let srgb = settings.boolValue("srgb", default: isColorSemantic(semantic))
        let outputFormat = scan.sourceURL.pathExtension.lowercased()
        switch probeTextureImport(url: scan.sourceURL, semantic: semantic, srgb: srgb, outputFormat: outputFormat) {
        case .success:
            break
        case .failure(let diag):
            let reason = "\(diag.failedStage): \(diag.reason)"
            EngineLoggerContext.log(
                diag.formattedLog(),
                level: .error,
                category: .assets
            )
            setTextureFailureState(
                projectManager: projectManager,
                scan: scan,
                settings: settings,
                importerId: importerId,
                importerVersion: importerVersion,
                reason: reason
            )
            return nil
        }
        return commitSourceAsset(scan: scan,
                                 settings: settings,
                                 projectManager: projectManager,
                                 resolver: resolver,
                                 assetType: .texture,
                                 importerId: importerId,
                                 importerVersion: importerVersion)
    }

    private func guessTextureSemantic(from name: String) -> String {
        let lowered = name.lowercased()
        if lowered.contains("orm") || (lowered.contains("occlusion") && lowered.contains("rough") && lowered.contains("metal")) { return "orm" }
        if lowered.contains("normal") { return "normal" }
        if lowered.contains("rough") { return "roughness" }
        if lowered.contains("metal") { return "metallic" }
        if lowered.contains("ao") || lowered.contains("occlusion") { return "occlusion" }
        if lowered.contains("height") || lowered.contains("displace") { return "height" }
        if lowered.contains("emissive") { return "emissive" }
        if lowered.contains("albedo") || lowered.contains("basecolor") || lowered.contains("diff") { return "albedo" }
        return ""
    }

    private func isColorSemantic(_ semantic: String) -> Bool {
        switch semantic.lowercased() {
        case "albedo", "basecolor", "diffuse", "diff", "emissive":
            return true
        case "normal", "roughness", "metallic", "occlusion", "ao", "height", "orm":
            return false
        default:
            return AssetManager.isColorTexture(path: semantic)
        }
    }
}

struct EnvironmentImporter: AssetImporter {
    let importerId = "EnvironmentImporter"
    let importerVersion = "1"

    func canImport(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["hdr", "exr"].contains(ext)
    }

    func scan(_ url: URL) -> ImportScanResult? {
        guard canImport(url) else { return nil }
        let name = url.deletingPathExtension().lastPathComponent
        return ImportScanResult(
            sourceURL: url,
            assetType: .environment,
            suggestedName: name,
            details: [:],
            meshInfo: nil
        )
    }

    func defaultSettings(for scan: ImportScanResult) -> ImportSettings {
        ImportSettings(values: [
            "semantic": "environment",
            "srgb": "false"
        ])
    }

    func commit(scan: ImportScanResult,
                settings: ImportSettings,
                projectManager: EditorProjectManager,
                resolver: AssetPathResolver) -> ImportCommitResult? {
        commitSourceAsset(scan: scan,
                          settings: settings,
                          projectManager: projectManager,
                          resolver: resolver,
                          assetType: .environment,
                          importerId: importerId,
                          importerVersion: importerVersion)
    }
}

struct MeshImporter: AssetImporter {
    let importerId = "MeshImporter"
    let importerVersion = "1"

    func canImport(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["usdz", "gltf", "glb"].contains(ext)
    }

    func scan(_ url: URL) -> ImportScanResult? {
        guard canImport(url) else { return nil }
        let name = url.deletingPathExtension().lastPathComponent
        let scan = MeshImporter.scanMesh(url: url, suggestedName: name)
        return scan
    }

    func defaultSettings(for scan: ImportScanResult) -> ImportSettings {
        var values: [String: String] = [
            "importMaterials": "true",
            "importTextures": "true",
            "copyTextures": "true",
            "flipNormalY": "false",
            "generateTangents": "true",
            "scale": "1.0",
            "combineORM": "false",
            "createPrefab": "false",
            "createHierarchy": "false"
        ]
        if let info = scan.meshInfo {
                if info.hasTangents {
                    values["generateTangents"] = "false"
                }
                if !info.hasUVs {
                    values["importTextures"] = "false"
                }
                if info.suggestFlipNormalY {
                    values["flipNormalY"] = "true"
                }
            }
        return ImportSettings(values: values)
    }

    func commit(scan: ImportScanResult,
                settings: ImportSettings,
                projectManager: EditorProjectManager,
                resolver: AssetPathResolver) -> ImportCommitResult? {
        MeshImporter.commitMesh(scan: scan,
                                settings: settings,
                                projectManager: projectManager,
                                resolver: resolver,
                                importerId: importerId,
                                importerVersion: importerVersion)
    }
}

struct FbxImporter: AssetImporter {
    let importerId = "FbxImporter"
    let importerVersion = "1"

    func canImport(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "fbx"
    }

    func scan(_ url: URL) -> ImportScanResult? {
        guard canImport(url) else { return nil }
        let name = url.deletingPathExtension().lastPathComponent
        let fbxData = FbxSdkAdapter.scanFBX(url: url, suggestedName: name)
        guard let fbxData else {
            let failedInfo = MeshScanInfo(
                meshCount: 0,
                submeshCount: 0,
                submeshMaterialIndices: [],
                materialNames: [],
                textureNames: [],
                hasUVs: false,
                hasNormals: false,
                hasTangents: false,
                suggestFlipNormalY: false,
                embeddedTextureCount: 0,
                isSkinned: false,
                skeletonInfo: nil,
                clipInfos: [],
                hasRootMotion: false,
                rootMotionBoneName: nil,
                warnings: ["FBX import failed. FBX SDK bridge could not extract this FBX scene."],
                materials: []
            )
            return ImportScanResult(
                sourceURL: url,
                assetType: .model,
                suggestedName: name,
                details: ["fbxBackend": "fbxsdk", "warning": "FBX import failed. FBX SDK bridge could not extract this FBX scene."],
                meshInfo: failedInfo
            )
        }
        let info = FbxSdkAdapter.makeMeshScanInfo(from: fbxData)
        var details: [String: String] = [:]
        details["fbxBackend"] = FbxSdkAdapter.backendName(for: fbxData)
        details["fbxImportMode"] = fbxData.mode.rawValue
        details["fbxScaleNormalization"] = fbxData.importScaleNormalizationMode
        details["fbxScaleFactor"] = String(format: "%.6f", fbxData.importScaleFactor)
        details["fbxScaleSource"] = fbxData.importScaleSource

        let hasMeshes = info.meshCount > 0
        let hasClips = !info.clipInfos.isEmpty
        if !hasMeshes && hasClips {
            details["fbxImportMode"] = "animationOnly"
            return ImportScanResult(
                sourceURL: url,
                assetType: .animationClip,
                suggestedName: name,
                details: details,
                meshInfo: info
            )
        }
        details["fbxImportMode"] = info.isSkinned ? "skeletalMesh" : "staticMesh"
        return ImportScanResult(
            sourceURL: url,
            assetType: .model,
            suggestedName: name,
            details: details,
            meshInfo: info
        )
    }

    func defaultSettings(for scan: ImportScanResult) -> ImportSettings {
        if scan.assetType == .animationClip {
            return ImportSettings(values: [
                "associateSkeleton": "auto",
                "targetSkeletonHandle": ""
            ])
        }
        var values = MeshImporter().defaultSettings(for: scan).values
        values["fbxImportMode"] = scan.details["fbxImportMode"] ?? "skeletalMesh"
        return ImportSettings(values: values)
    }

    func commit(scan: ImportScanResult,
                settings: ImportSettings,
                projectManager: EditorProjectManager,
                resolver: AssetPathResolver) -> ImportCommitResult? {
        if scan.assetType == .animationClip {
            return FbxImporter.commitAnimationOnlyFBX(
                scan: scan,
                settings: settings,
                projectManager: projectManager,
                resolver: resolver,
                importerId: importerId,
                importerVersion: importerVersion
            )
        }
        return MeshImporter.commitMesh(
            scan: scan,
            settings: settings,
            projectManager: projectManager,
            resolver: resolver,
            importerId: importerId,
            importerVersion: importerVersion
        )
    }
}

extension MeshImporter {
    fileprivate static func scanMesh(url: URL, suggestedName: String) -> ImportScanResult? {
        let asset = MDLAsset(url: url)
        asset.loadTextures()
        let meshes = (asset.childObjects(of: MDLMesh.self) as? [MDLMesh]) ?? []
        let animationData = extractAnimationData(asset: asset, suggestedName: suggestedName)
        if meshes.isEmpty {
            return ImportScanResult(
                sourceURL: url,
                assetType: .model,
                suggestedName: suggestedName,
                details: ["warning": "No meshes found."],
                meshInfo: MeshScanInfo(
                meshCount: 0,
                submeshCount: 0,
                submeshMaterialIndices: [],
                materialNames: [],
                textureNames: [],
                hasUVs: false,
                hasNormals: false,
                hasTangents: false,
                suggestFlipNormalY: false,
                embeddedTextureCount: 0,
                isSkinned: false,
                skeletonInfo: animationData.skeletonInfo,
                clipInfos: animationData.clipInfos,
                hasRootMotion: animationData.hasRootMotion,
                rootMotionBoneName: animationData.rootMotionBoneName,
                warnings: ["No meshes found."],
                materials: []
            )
            )
        }

        var submeshCount = 0
        var hasUVs = false
        var hasNormals = false
        var hasTangents = false
        var warnings: [String] = []
        var embeddedTextureCount = 0
        var suggestFlipNormalY = false
        var hasJointIndices = false
        var hasJointWeights = false

        var materialList: [MeshScanMaterial] = []
        var materialNames = Set<String>()
        var textureNames = Set<String>()
        var submeshMaterialIndices: [Int] = []

        var materialIndexById: [ObjectIdentifier: Int] = [:]

        for (meshIndex, mesh) in meshes.enumerated() {
            if let submeshes = mesh.submeshes as? [MDLSubmesh] {
                if meshIndex == 0 {
                    submeshCount = submeshes.count
                }
                for submesh in submeshes {
                    if let material = submesh.material {
                        let materialId = ObjectIdentifier(material)
                        if let index = materialIndexById[materialId] {
                            if meshIndex == 0 {
                                submeshMaterialIndices.append(index)
                            }
                        } else {
                            let extracted = extractMaterial(material, baseURL: url.deletingLastPathComponent())
                            let newIndex = materialList.count
                            materialIndexById[materialId] = newIndex
                            materialList.append(extracted)
                            if meshIndex == 0 {
                                submeshMaterialIndices.append(newIndex)
                            }
                        }
                    } else {
                        if meshIndex == 0 {
                            submeshMaterialIndices.append(-1)
                        }
                    }
                }
            }

            let descriptor = mesh.vertexDescriptor
            if let attributes = descriptor.attributes as? [MDLVertexAttribute] {
                for attribute in attributes {
                    let name = attribute.name
                    let lowered = name.lowercased()
                    if name == MDLVertexAttributeTextureCoordinate
                        || lowered.contains("texturecoordinate")
                        || lowered.contains("texcoord")
                        || lowered.contains("uv0")
                        || lowered.contains("uv_0") {
                        hasUVs = true
                    }
                    if name == MDLVertexAttributeNormal { hasNormals = true }
                    if name == MDLVertexAttributeTangent { hasTangents = true }
                    if name == MDLVertexAttributeJointIndices || lowered.contains("jointindices") || lowered.contains("joints") {
                        hasJointIndices = true
                    }
                    if name == MDLVertexAttributeJointWeights || lowered.contains("jointweights") || lowered.contains("weights") {
                        hasJointWeights = true
                    }
                }
            }
        }

        for material in materialList {
            materialNames.insert(material.name)
            for texture in material.textures.values {
                if texture.isEmbedded { embeddedTextureCount += 1 }
                if !texture.name.isEmpty { textureNames.insert(texture.name) }
                if texture.semantic == .normal {
                    let lowered = texture.name.lowercased()
                    if lowered.contains("ogl") || lowered.contains("opengl") || lowered.contains("nor_gl") {
                        suggestFlipNormalY = true
                    }
                }
            }
        }

        if !hasUVs {
            warnings.append("No UVs detected; textures may not map correctly.")
        }
        if embeddedTextureCount > 0 {
            warnings.append("Embedded textures detected; they may not extract automatically.")
        }
        let isSkinned = hasJointIndices && hasJointWeights && animationData.skeletonInfo != nil
        if (hasJointIndices || hasJointWeights) && !isSkinned {
            warnings.append("Skinning streams detected but skeleton data was incomplete.")
        }

        let info = MeshScanInfo(
            meshCount: meshes.count,
            submeshCount: submeshCount,
            submeshMaterialIndices: submeshMaterialIndices,
            materialNames: materialNames.sorted(),
            textureNames: textureNames.sorted(),
            hasUVs: hasUVs,
            hasNormals: hasNormals,
            hasTangents: hasTangents,
            suggestFlipNormalY: suggestFlipNormalY,
            embeddedTextureCount: embeddedTextureCount,
            isSkinned: isSkinned,
            skeletonInfo: animationData.skeletonInfo,
            clipInfos: animationData.clipInfos,
            hasRootMotion: animationData.hasRootMotion,
            rootMotionBoneName: animationData.rootMotionBoneName,
            warnings: warnings,
            materials: materialList
        )

        return ImportScanResult(
            sourceURL: url,
            assetType: .model,
            suggestedName: suggestedName,
            details: [:],
            meshInfo: info
        )
    }

    fileprivate struct ExtractedAnimationData {
        let skeletonInfo: MeshSkeletonScanInfo?
        let clipInfos: [MeshAnimationClipScanInfo]
        let hasRootMotion: Bool
        let rootMotionBoneName: String?
    }

    fileprivate static func extractAnimationData(asset: MDLAsset, suggestedName: String) -> ExtractedAnimationData {
        var skeletonInfo: MeshSkeletonScanInfo?
        let skeletons = (asset.childObjects(of: MDLSkeleton.self) as? [MDLSkeleton]) ?? []
        if let skeleton = skeletons.first {
            let jointPaths = skeleton.jointPaths
            if !jointPaths.isEmpty {
                var joints: [SkeletonAsset.Joint] = []
                joints.reserveCapacity(jointPaths.count)
                for (index, path) in jointPaths.enumerated() {
                    let parentPath = (path as NSString).deletingLastPathComponent
                    let parentIndex: Int
                    if parentPath.isEmpty || parentPath == "." || parentPath == path {
                        parentIndex = -1
                    } else {
                        parentIndex = jointPaths.firstIndex(of: parentPath) ?? -1
                    }
                    let restMatrix = skeleton.jointRestTransforms.float4x4Array[index]
                    let decomposed = TransformMath.decomposeMatrix(restMatrix)
                    joints.append(
                        SkeletonAsset.Joint(
                            name: URL(fileURLWithPath: path).lastPathComponent,
                            parentIndex: parentIndex,
                            bindLocalPosition: decomposed.position,
                            bindLocalRotation: decomposed.rotation,
                            bindLocalScale: decomposed.scale
                        )
                    )
                }
                skeletonInfo = MeshSkeletonScanInfo(jointCount: joints.count, joints: joints)
            }
        }

        var clips: [MeshAnimationClipScanInfo] = []
        var hasRootMotion = false
        let packedAnimations = (asset.childObjects(of: MDLPackedJointAnimation.self) as? [MDLPackedJointAnimation]) ?? []
        for (index, packed) in packedAnimations.enumerated() {
            let jointPaths = packed.jointPaths
            let clipNameBase = packed.name.isEmpty ? "\(suggestedName)_Clip_\(index + 1)" : packed.name
            let clipName = meshSanitizeFileName(clipNameBase)

            var duration = Float(0)
            if let maxT = packed.translations.times.max() { duration = max(duration, Float(maxT)) }
            if let maxR = packed.rotations.times.max() { duration = max(duration, Float(maxR)) }
            if let maxS = packed.scales.times.max() { duration = max(duration, Float(maxS)) }

            var tracks: [AnimationClipAsset.JointTrack] = []
            let sampleTimes = (packed.translations.times + packed.rotations.times + packed.scales.times)
                .sorted()
                .reduce(into: [TimeInterval]()) { result, value in
                    if result.last != value { result.append(value) }
                }

            if !jointPaths.isEmpty, !sampleTimes.isEmpty {
                for (jointIndex, _) in jointPaths.enumerated() {
                    var translations: [AnimationClipAsset.TranslationKeyframe] = []
                    var rotations: [AnimationClipAsset.RotationKeyframe] = []
                    var scales: [AnimationClipAsset.ScaleKeyframe] = []
                    for t in sampleTimes {
                        let tr = packed.translations.float3Array(atTime: t)
                        let rr = packed.rotations.floatQuaternionArray(atTime: t)
                        let sr = packed.scales.float3Array(atTime: t)
                        if jointIndex < tr.count {
                            translations.append(AnimationClipAsset.TranslationKeyframe(time: Float(t), value: tr[jointIndex]))
                        }
                        if jointIndex < rr.count {
                            let q = rr[jointIndex]
                            let quat = SIMD4<Float>(q.imag.x, q.imag.y, q.imag.z, q.real)
                            rotations.append(AnimationClipAsset.RotationKeyframe(time: Float(t), value: quat))
                        }
                        if jointIndex < sr.count {
                            scales.append(AnimationClipAsset.ScaleKeyframe(time: Float(t), value: sr[jointIndex]))
                        }
                    }
                    if !translations.isEmpty || !rotations.isEmpty || !scales.isEmpty {
                        tracks.append(
                            AnimationClipAsset.JointTrack(
                                jointIndex: jointIndex,
                                translations: translations,
                                rotations: rotations,
                                scales: scales
                            )
                        )
                    }
                }
            }

            if !hasRootMotion {
                hasRootMotion = tracks.contains { track in
                    guard track.jointIndex == 0, track.translations.count > 1 else { return false }
                    let first = track.translations[0].value
                    return track.translations.contains { simd_length($0.value - first) > 0.001 }
                }
            }

            clips.append(
                MeshAnimationClipScanInfo(
                    name: clipName,
                    durationSeconds: duration,
                    tracks: tracks
                )
            )
        }

        let rootMotionBoneName = detectRootMotionBoneName(clips: clips, skeleton: skeletonInfo)
        return ExtractedAnimationData(
            skeletonInfo: skeletonInfo,
            clipInfos: clips,
            hasRootMotion: hasRootMotion,
            rootMotionBoneName: rootMotionBoneName
        )
    }

    fileprivate static func detectRootMotionBoneName(clips: [MeshAnimationClipScanInfo],
                                                     skeleton: MeshSkeletonScanInfo?) -> String? {
        guard let skeleton, !skeleton.joints.isEmpty else { return nil }
        let candidates = clips.flatMap(\.tracks).compactMap { track -> (jointIndex: Int, motion: Float)? in
            guard track.jointIndex >= 0, track.jointIndex < skeleton.joints.count else { return nil }
            guard track.translations.count > 1 else { return nil }
            let first = track.translations[0].value
            var motion: Float = 0.0
            for sample in track.translations {
                motion = max(motion, simd_length(sample.value - first))
            }
            guard motion > 0.001 else { return nil }
            return (track.jointIndex, motion)
        }
        guard !candidates.isEmpty else { return nil }

        func depth(for jointIndex: Int) -> Int {
            var depth = 0
            var cursor = jointIndex
            var visited: Set<Int> = []
            while cursor >= 0, cursor < skeleton.joints.count, !visited.contains(cursor) {
                visited.insert(cursor)
                let parent = skeleton.joints[cursor].parentIndex
                if parent < 0 { break }
                depth += 1
                cursor = parent
            }
            return depth
        }

        let minDepth = candidates.map { depth(for: $0.jointIndex) }.min() ?? 0
        let best = candidates.max { lhs, rhs in
            let lhsDepth = depth(for: lhs.jointIndex)
            let rhsDepth = depth(for: rhs.jointIndex)
            let lhsClose = lhsDepth <= (minDepth + 1)
            let rhsClose = rhsDepth <= (minDepth + 1)
            if lhsClose != rhsClose { return !lhsClose && rhsClose }
            if lhsDepth != rhsDepth { return lhsDepth > rhsDepth }
            if abs(lhs.motion - rhs.motion) > 1.0e-5 { return lhs.motion < rhs.motion }
            return lhs.jointIndex > rhs.jointIndex
        }
        guard let jointIndex = best?.jointIndex else { return nil }
        return skeleton.joints[jointIndex].name
    }

    private static func extractMaterial(_ material: MDLMaterial, baseURL: URL) -> MeshScanMaterial {
        let name = material.name.isEmpty ? "Material" : material.name

        let baseColorProp = property(material,
                                     semantics: [.baseColor],
                                     names: ["baseColor", "baseColorFactor", "diffuseColor", "diffuse", "albedo"])
        let emissiveProp = property(material,
                                    semantics: [.emission],
                                    names: ["emissive", "emissiveColor", "emission"])
        let metallicProp = property(material,
                                    semantics: [.metallic],
                                    names: ["metallic", "metallicFactor"])
        let roughnessProp = property(material,
                                     semantics: [.roughness],
                                     names: ["roughness", "roughnessFactor"])
        let metalRoughnessProp = property(material,
                                          semantics: [],
                                          names: ["metallicRoughness", "metalRoughness", "metallicRoughnessTexture"])
        let aoProp = property(material,
                              semantics: [.ambientOcclusion],
                              names: ["occlusion", "ao", "ambientOcclusion"])
        let normalProp = property(material,
                                  semantics: [.tangentSpaceNormal, .bump],
                                  names: ["normal", "normalTexture", "tangentSpaceNormal"])
        let opacityProp = property(material,
                                   semantics: [.opacity],
                                   names: ["opacity", "alpha"])
        let alphaCutoffProp = property(material,
                                       semantics: [],
                                       names: ["alphaCutoff", "cutoff", "opacityThreshold"])
        let doubleSidedProp = property(material,
                                       semantics: [],
                                       names: ["doubleSided", "isDoubleSided"])
        let unlitProp = property(material,
                                 semantics: [],
                                 names: ["unlit", "isUnlit"])

        let baseColorFactorProp = property(material,
                                           semantics: [],
                                           names: ["baseColorFactor", "diffuseColor", "albedoFactor"])
        let emissiveFactorProp = property(material,
                                          semantics: [],
                                          names: ["emissiveFactor", "emissiveColor", "emissiveIntensity"])
        let metallicFactorProp = property(material,
                                          semantics: [],
                                          names: ["metallicFactor"])
        let roughnessFactorProp = property(material,
                                           semantics: [],
                                           names: ["roughnessFactor"])
        let aoFactorProp = property(material,
                                    semantics: [],
                                    names: ["occlusionStrength", "aoFactor"])

        let baseColor = vectorFromProperty(baseColorFactorProp)
            ?? vectorFromProperty(baseColorProp)
            ?? SIMD3<Float>(1, 1, 1)
        let emissiveColor = vectorFromProperty(emissiveFactorProp)
            ?? vectorFromProperty(emissiveProp)
            ?? SIMD3<Float>(0, 0, 0)
        let metallicFactor = floatFromProperty(metallicFactorProp)
            ?? floatFromProperty(metallicProp)
            ?? 1.0
        let roughnessFactor = floatFromProperty(roughnessFactorProp)
            ?? floatFromProperty(roughnessProp)
            ?? 1.0
        let aoFactor = floatFromProperty(aoFactorProp)
            ?? floatFromProperty(aoProp)
            ?? 1.0
        let opacity = floatFromProperty(opacityProp) ?? 1.0
        let alphaCutoff = floatFromProperty(alphaCutoffProp) ?? 0.5

        var alphaMode: MaterialAlphaMode = .opaque
        if alphaCutoffProp != nil {
            alphaMode = .alphaClip
        } else if opacity < 0.99 {
            alphaMode = .transparent
        }

        let doubleSided = boolFromProperty(doubleSidedProp) ?? false
        let unlit = boolFromProperty(unlitProp) ?? false

        var textures: [MeshTextureSemantic: MeshScanTexture] = [:]
        if let texture = textureFromProperty(baseColorProp, semantic: .baseColor, baseURL: baseURL) {
            textures[.baseColor] = texture
        }
        if let texture = textureFromProperty(emissiveProp, semantic: .emissive, baseURL: baseURL) {
            textures[.emissive] = texture
        }
        if let texture = textureFromProperty(normalProp, semantic: .normal, baseURL: baseURL) {
            textures[.normal] = texture
        }
        if let texture = textureFromProperty(aoProp, semantic: .occlusion, baseURL: baseURL) {
            textures[.occlusion] = texture
        }
        if let texture = textureFromProperty(metalRoughnessProp, semantic: .metallicRoughness, baseURL: baseURL) {
            textures[.metallicRoughness] = texture
        }
        if let texture = textureFromProperty(metallicProp, semantic: .metallic, baseURL: baseURL) {
            textures[.metallic] = texture
        }
        if let texture = textureFromProperty(roughnessProp, semantic: .roughness, baseURL: baseURL) {
            textures[.roughness] = texture
        }

        if textures[.metallicRoughness] == nil,
           let metallic = textures[.metallic],
           let roughness = textures[.roughness],
           metallic.url == roughness.url && metallic.name == roughness.name {
            textures[.metallicRoughness] = metallic
        }

        return MeshScanMaterial(
            name: name,
            baseColor: baseColor,
            emissiveColor: emissiveColor,
            metallicFactor: metallicFactor,
            roughnessFactor: roughnessFactor,
            aoFactor: aoFactor,
            alphaMode: alphaMode,
            alphaCutoff: alphaCutoff,
            doubleSided: doubleSided,
            unlit: unlit,
            textures: textures
        )
    }

    private static func floatFromProperty(_ property: MDLMaterialProperty?) -> Float? {
        guard let property else { return nil }
        switch property.type {
        case .float:
            return property.floatValue
        case .float2:
            return property.float2Value.x
        case .float3:
            return property.float3Value.x
        case .float4:
            return property.float4Value.x
        case .string:
            if let value = property.stringValue {
                return Float(value)
            }
            return nil
        default:
            return nil
        }
    }

    private static func vectorFromProperty(_ property: MDLMaterialProperty?) -> SIMD3<Float>? {
        guard let property else { return nil }
        switch property.type {
        case .float2:
            let v = property.float2Value
            return SIMD3<Float>(v.x, v.y, 0.0)
        case .float3:
            return property.float3Value
        case .float4:
            let v = property.float4Value
            return SIMD3<Float>(v.x, v.y, v.z)
        case .color:
            let v = property.float4Value
            return SIMD3<Float>(v.x, v.y, v.z)
        default:
            return nil
        }
    }

    private static func boolFromProperty(_ property: MDLMaterialProperty?) -> Bool? {
        guard let property else { return nil }
        switch property.type {
        case .float, .float2, .float3, .float4:
            return floatFromProperty(property) ?? 0.0 > 0.5
        case .string:
            if let value = property.stringValue?.lowercased() {
                return value == "true" || value == "1" || value == "yes"
            }
            return nil
        default:
            return nil
        }
    }

    private static func property(_ material: MDLMaterial,
                                 semantics: [MDLMaterialSemantic],
                                 names: [String]) -> MDLMaterialProperty? {
        for semantic in semantics {
            if let property = material.property(with: semantic), property.type != .none {
                return property
            }
        }
        if !names.isEmpty {
            for name in names {
                if let property = material.propertyNamed(name), property.type != .none {
                    return property
                }
            }
            let lowered = Set(names.map { $0.lowercased() })
            let count = material.count
            if count > 0 {
                for index in 0..<count {
                    if let property = material[index], lowered.contains(property.name.lowercased()) {
                        return property
                    }
                }
            }
        }
        return nil
    }

    private static func textureFromProperty(_ property: MDLMaterialProperty?,
                                            semantic: MeshTextureSemantic,
                                            baseURL: URL) -> MeshScanTexture? {
        guard let property else { return nil }
        if property.type == .texture,
           let texture = property.textureSamplerValue?.texture {
            if let url = (texture as? MDLURLTexture)?.url {
                let name = url.deletingPathExtension().lastPathComponent
                let resolved = resolveURL(url, baseURL: baseURL)
                return MeshScanTexture(semantic: semantic, url: resolved, name: name, isEmbedded: false, mdlTexture: nil)
            }
            var name = texture.name ?? ""
            if name.isEmpty { name = semantic.rawValue }
            return MeshScanTexture(semantic: semantic, url: nil, name: name, isEmbedded: true, mdlTexture: texture)
        }
        if property.type == .URL, let url = property.urlValue {
            let resolved = resolveURL(url, baseURL: baseURL)
            let name = resolved.deletingPathExtension().lastPathComponent
            return MeshScanTexture(semantic: semantic, url: resolved, name: name, isEmbedded: false, mdlTexture: nil)
        }
        if property.type == .string, let value = property.stringValue, !value.isEmpty {
            let url = URL(fileURLWithPath: value, relativeTo: baseURL).standardizedFileURL
            let resolved = resolveURL(url, baseURL: baseURL)
            let name = resolved.deletingPathExtension().lastPathComponent
            return MeshScanTexture(semantic: semantic, url: resolved, name: name, isEmbedded: false, mdlTexture: nil)
        }
        return nil
    }

    private static func resolveURL(_ url: URL, baseURL: URL) -> URL {
        if url.isFileURL && url.path.hasPrefix("/") { return url.standardizedFileURL }
        return baseURL.appendingPathComponent(url.path).standardizedFileURL
    }

    private static func exportEmbeddedTexture(_ texture: MDLTexture, to url: URL) -> EmbeddedTextureExportOutcome {
        let folder = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            try texture.write(to: url)
            return .success
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    fileprivate static func commitMesh(scan: ImportScanResult,
                                   settings: ImportSettings,
                                   projectManager: EditorProjectManager,
                                   resolver: AssetPathResolver,
                                   importerId: String,
                                   importerVersion: String) -> ImportCommitResult? {
        guard let rootURL = projectManager.assetRootURL() else { return nil }
        guard let meshInfo = scan.meshInfo else { return nil }
        let sourceURL = scan.sourceURL.standardizedFileURL
        let sourceFolderURL = sourceURL.deletingLastPathComponent().standardizedFileURL
        let sourceRelativePath = PathUtils.relativePath(from: rootURL, to: sourceURL) ?? sourceURL.lastPathComponent
        var sourcePathAbs = sourceURL.path
        let isFBXImporter = importerId == "FbxImporter"
        let useFBXSourceFolderOutputs = isFBXImporter && isUnderRoot(sourceURL, rootURL: rootURL)
        let sourceFolderRelativePath = PathUtils.relativePath(from: rootURL, to: sourceFolderURL) ?? sourceFolderURL.lastPathComponent
        guard let meshRoot = resolver.destinationFolder(for: .model) else { return nil }
        var meshFolder = useFBXSourceFolderOutputs ? sourceFolderURL : uniqueFolderURL(in: meshRoot, baseName: scan.suggestedName)

        let texturesRoot = resolver.destinationFolder(for: .texture) ?? rootURL.appendingPathComponent("Textures", isDirectory: true)
        let materialsRoot = resolver.destinationFolder(for: .material) ?? rootURL.appendingPathComponent("Materials", isDirectory: true)
        let skeletonsRoot = resolver.destinationFolder(for: .skeleton) ?? rootURL.appendingPathComponent("Skeletons", isDirectory: true)
        let clipsRoot = resolver.destinationFolder(for: .animationClip) ?? rootURL.appendingPathComponent("Animations", isDirectory: true)
        let environmentsRoot = resolver.destinationFolder(for: .environment) ?? rootURL.appendingPathComponent("Environments", isDirectory: true)
        var texturesFolder = useFBXSourceFolderOutputs ? meshFolder : texturesRoot.appendingPathComponent(meshFolder.lastPathComponent, isDirectory: true)
        var materialsFolder = useFBXSourceFolderOutputs ? meshFolder : materialsRoot.appendingPathComponent(meshFolder.lastPathComponent, isDirectory: true)
        var skeletonsFolder = useFBXSourceFolderOutputs ? meshFolder : skeletonsRoot.appendingPathComponent(meshFolder.lastPathComponent, isDirectory: true)
        var clipsFolder = useFBXSourceFolderOutputs ? meshFolder : clipsRoot.appendingPathComponent(meshFolder.lastPathComponent, isDirectory: true)
        let sourceExt = sourceURL.pathExtension.lowercased()
        let textureOrigin = (sourceExt == "usdz") ? "bottomLeft" : "topLeft"
        let usesFbxBakedMesh = importerId == "FbxImporter" && scan.assetType == .model
        let fbxDataForMesh = usesFbxBakedMesh ? FbxSdkAdapter.scanFBX(url: sourceURL, suggestedName: scan.suggestedName) : nil
        let canBakeFbxMesh = fbxDataForMesh?.mode != .animationOnly && !(fbxDataForMesh?.meshes.isEmpty ?? true)
        let hasSkinnedMeshDataWithoutSkeleton: Bool = {
            guard let fbxDataForMesh else { return false }
            let hasSkinningStreams = fbxDataForMesh.meshes.contains(where: { $0.hasSkinning })
            return hasSkinningStreams && fbxDataForMesh.skeleton == nil
        }()

        let metadataSnapshotForReimport = projectManager.assetMetadataSnapshot()
        var reimportMeshMeta: AssetMetadata?
        if let existing = projectManager.metadataForSourcePathAbs(sourcePathAbs),
           existing.type == .model,
           existing.importSettings["importer"] == importerId {
            reimportMeshMeta = existing
        } else {
            let sourceMetaURL = AssetIO.metaURL(for: sourceURL)
            if let handle = loadHandle(from: sourceMetaURL),
               let existing = metadataSnapshotForReimport.first(where: { $0.handle == handle }),
               existing.type == .model,
               existing.importSettings["importer"] == importerId {
                reimportMeshMeta = existing
            } else if isUnderRoot(sourceURL, rootURL: rootURL),
                      let relativePath = PathUtils.relativePath(from: rootURL, to: sourceURL),
                      let existing = metadataSnapshotForReimport.first(where: { $0.type == .model && $0.sourcePath == relativePath }),
                      existing.importSettings["importer"] == importerId {
                reimportMeshMeta = existing
            }
        }
        if let reimportMeshMeta,
           let originalSourceAbs = reimportMeshMeta.importSettings["sourcePathAbs"],
           !originalSourceAbs.isEmpty {
            sourcePathAbs = originalSourceAbs
        }
        let preExistingGeneratedPaths: Set<String> = Set(metadataSnapshotForReimport.compactMap { meta in
            if meta.handle == reimportMeshMeta?.handle {
                return meta.sourcePath
            }
            guard let meshSource = meta.importSettings["meshSourcePathAbs"], meshSource == sourcePathAbs else { return nil }
            if useFBXSourceFolderOutputs {
                let metaURL = rootURL.appendingPathComponent(meta.sourcePath).standardizedFileURL
                if metaURL.deletingLastPathComponent() != sourceFolderURL { return nil }
            }
            switch meta.type {
            case .texture, .environment, .material, .skeleton, .animationClip:
                return meta.sourcePath
            default:
                return nil
            }
        })

        var commitResult: ImportCommitResult?
        let ok = projectManager.performAssetMutation {
            if hasSkinnedMeshDataWithoutSkeleton {
                EngineLoggerContext.log(
                    "FBX import failed for \(sourceURL.lastPathComponent): skinned mesh data present but skeleton extraction failed. Import aborted to prevent invalid skinning output.",
                    level: .error,
                    category: .assets
                )
                return false
            }
            if let reimportMeshMeta, !useFBXSourceFolderOutputs {
                let existingMeshURL = rootURL.appendingPathComponent(reimportMeshMeta.sourcePath)
                meshFolder = existingMeshURL.deletingLastPathComponent()
                texturesFolder = texturesRoot.appendingPathComponent(meshFolder.lastPathComponent, isDirectory: true)
                materialsFolder = materialsRoot.appendingPathComponent(meshFolder.lastPathComponent, isDirectory: true)
                skeletonsFolder = skeletonsRoot.appendingPathComponent(meshFolder.lastPathComponent, isDirectory: true)
                clipsFolder = clipsRoot.appendingPathComponent(meshFolder.lastPathComponent, isDirectory: true)
            }
            try FileManager.default.createDirectory(at: meshFolder, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: texturesFolder, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: materialsFolder, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: skeletonsFolder, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: clipsFolder, withIntermediateDirectories: true)

            let sourceFileName = sourceURL.lastPathComponent
            let bakedMeshFileName = "\(sourceURL.deletingPathExtension().lastPathComponent).mcmesh"
            let meshDestinationURL: URL
            if let reimportMeshMeta {
                let existingURL = rootURL.appendingPathComponent(reimportMeshMeta.sourcePath)
                if useFBXSourceFolderOutputs && canBakeFbxMesh {
                    meshDestinationURL = meshFolder.appendingPathComponent(bakedMeshFileName)
                } else if canBakeFbxMesh {
                    if existingURL.pathExtension.lowercased() == "mcmesh" {
                        meshDestinationURL = existingURL
                    } else {
                        meshDestinationURL = meshFolder.appendingPathComponent(bakedMeshFileName)
                    }
                } else {
                    meshDestinationURL = existingURL
                }
            } else if canBakeFbxMesh {
                meshDestinationURL = meshFolder.appendingPathComponent(bakedMeshFileName)
            } else {
                meshDestinationURL = meshFolder.appendingPathComponent(sourceFileName)
            }
            let meshMetaURL = AssetIO.metaURL(for: meshDestinationURL)
            let sourceMetaURL = AssetIO.metaURL(for: sourceURL)

            let existingMeshHandle = reimportMeshMeta?.handle ?? loadHandle(from: sourceMetaURL) ?? loadHandle(from: meshMetaURL)

            if canBakeFbxMesh, let fbxDataForMesh {
                if FileManager.default.fileExists(atPath: meshDestinationURL.path) {
                    try? FileManager.default.removeItem(at: meshDestinationURL)
                }
                let bakedOK = FbxSdkAdapter.writeBakedMeshAsset(
                    from: fbxDataForMesh,
                    name: scan.suggestedName,
                    to: meshDestinationURL
                )
                guard bakedOK else {
                    EngineLoggerContext.log(
                        "FBX import failed to persist baked mesh asset for \(sourceURL.lastPathComponent).",
                        level: .error,
                        category: .assets
                    )
                    return false
                }
                if meshDestinationURL.standardizedFileURL.path != sourceURL.standardizedFileURL.path,
                   FileManager.default.fileExists(atPath: sourceMetaURL.path),
                   let sourceMetaHandle = loadHandle(from: sourceMetaURL),
                   sourceMetaHandle == existingMeshHandle {
                    // Avoid duplicate metadata handle collision between raw FBX source and baked runtime mesh.
                    try? FileManager.default.removeItem(at: sourceMetaURL)
                }
            } else if meshDestinationURL.standardizedFileURL.path != sourceURL.standardizedFileURL.path {
                if FileManager.default.fileExists(atPath: meshDestinationURL.path) {
                    try? FileManager.default.removeItem(at: meshDestinationURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: meshDestinationURL)
                if reimportMeshMeta != nil && isUnderRoot(sourceURL, rootURL: rootURL) {
                    try? FileManager.default.removeItem(at: sourceURL)
                    if FileManager.default.fileExists(atPath: sourceMetaURL.path) {
                        try? FileManager.default.removeItem(at: sourceMetaURL)
                    }
                }
            }

            let metadataSnapshot = projectManager.assetMetadataSnapshot()
            var existingBySourceAbs: [String: AssetMetadata] = [:]
            var existingMaterialsByKey: [String: AssetMetadata] = [:]
            var existingTexturesByKey: [String: AssetMetadata] = [:]
            var existingSkeletonBySource: AssetMetadata?
            var existingClipByName: [String: AssetMetadata] = [:]
            let meshSourceKey = sourcePathAbs
            for meta in metadataSnapshot {
                let metaURL = rootURL.appendingPathComponent(meta.sourcePath).standardizedFileURL
                let isMetaInSourceFamily = metaURL.deletingLastPathComponent() == sourceFolderURL
                if let abs = meta.importSettings["sourcePathAbs"], !abs.isEmpty {
                    if !useFBXSourceFolderOutputs || isMetaInSourceFamily || meta.type == .texture || meta.type == .environment {
                        existingBySourceAbs[abs] = meta
                    }
                }
                if meta.type == .material,
                   let meshSource = meta.importSettings["meshSourcePathAbs"],
                   let materialName = meta.importSettings["meshMaterialName"],
                   !meshSource.isEmpty,
                   meshSource == meshSourceKey,
                   (!useFBXSourceFolderOutputs || isMetaInSourceFamily) {
                    let key = "\(meshSource)|\(materialName)"
                    existingMaterialsByKey[key] = meta
                }
                if (meta.type == .texture || meta.type == .environment),
                   let meshSource = meta.importSettings["meshSourcePathAbs"],
                   let semantic = meta.importSettings["meshTextureSemantic"],
                   !meshSource.isEmpty,
                   meshSource == meshSourceKey,
                   (!useFBXSourceFolderOutputs || isMetaInSourceFamily) {
                    let materialName = meta.importSettings["meshMaterialName"] ?? ""
                    let key = "\(meshSource)|\(materialName)|\(semantic)"
                    existingTexturesByKey[key] = meta
                }
                if meta.type == .skeleton,
                   let meshSource = meta.importSettings["meshSourcePathAbs"],
                   meshSource == meshSourceKey,
                   (!useFBXSourceFolderOutputs || isMetaInSourceFamily) {
                    existingSkeletonBySource = meta
                }
                if meta.type == .animationClip,
                   let meshSource = meta.importSettings["meshSourcePathAbs"],
                   let clipName = meta.importSettings["clipName"],
                   meshSource == meshSourceKey,
                   (!useFBXSourceFolderOutputs || isMetaInSourceFamily) {
                    existingClipByName[clipName] = meta
                }
            }

            var textureHandleMap: [URL: AssetHandle] = [:]
            var textureDependencies: [AssetHandle] = []
            var embeddedTextureHandles: [String: AssetHandle] = [:]
            var writtenPaths: [String] = []

            if settings.boolValue("importTextures", default: true) {
                let copyTextures = settings.boolValue("copyTextures", default: true)
                for material in meshInfo.materials {
                    for texture in material.textures.values {
                        if let url = texture.url {
                            if textureHandleMap[url] != nil { continue }
                            let ext = url.pathExtension.lowercased()
                            let destinationFolder = useFBXSourceFolderOutputs ? texturesFolder : ((ext == "hdr" || ext == "exr") ? environmentsRoot : texturesFolder)
                            var destinationURL = url
                            let sourceTextureAbs = url.standardizedFileURL.path
                            let textureKey = "\(meshSourceKey)|\(material.name)|\(texture.semantic.rawValue)"
                            if let existing = existingBySourceAbs[sourceTextureAbs],
                               existing.type == ((ext == "hdr" || ext == "exr") ? .environment : .texture) {
                                destinationURL = rootURL.appendingPathComponent(existing.sourcePath)
                            } else if let existing = existingTexturesByKey[textureKey] {
                                destinationURL = rootURL.appendingPathComponent(existing.sourcePath)
                            } else if copyTextures || !isUnderRoot(url, rootURL: rootURL) {
                                let candidate = destinationFolder.appendingPathComponent(url.lastPathComponent)
                                if reimportMeshMeta != nil && FileManager.default.fileExists(atPath: candidate.path) {
                                    destinationURL = candidate
                                } else {
                                    destinationURL = meshUniqueFileURL(in: destinationFolder,
                                                                       baseName: url.deletingPathExtension().lastPathComponent,
                                                                       ext: url.pathExtension)
                                }
                            }
                            if isUnderRoot(url, rootURL: rootURL) {
                                if url.standardizedFileURL.path != destinationURL.standardizedFileURL.path {
                                    try FileManager.default.copyItem(at: url, to: destinationURL)
                                    if reimportMeshMeta != nil {
                                        try? FileManager.default.removeItem(at: url)
                                        let sourceMetaURL = AssetIO.metaURL(for: url)
                                        if FileManager.default.fileExists(atPath: sourceMetaURL.path) {
                                            try? FileManager.default.removeItem(at: sourceMetaURL)
                                        }
                                    }
                                }
                            } else if copyTextures {
                                if FileManager.default.fileExists(atPath: destinationURL.path) {
                                    try? FileManager.default.removeItem(at: destinationURL)
                                }
                                try FileManager.default.copyItem(at: url, to: destinationURL)
                            } else {
                                continue
                            }
                            let metaURL = AssetIO.metaURL(for: destinationURL)
                            let handle = existingBySourceAbs[sourceTextureAbs]?.handle ?? loadHandle(from: metaURL) ?? AssetHandle()
                            let relativePath = PathUtils.relativePath(from: rootURL, to: destinationURL) ?? destinationURL.lastPathComponent
                            let semantic = texture.semantic.rawValue
                            let srgbValue = (semantic == MeshTextureSemantic.baseColor.rawValue || semantic == MeshTextureSemantic.emissive.rawValue) ? "true" : "false"
                            var settingsValues = [
                                "importer": importerId,
                                "importerVersion": importerVersion,
                                "sourcePath": PathUtils.relativePath(from: rootURL, to: url) ?? url.lastPathComponent,
                                "sourcePathAbs": sourceTextureAbs,
                                "meshSourcePathAbs": meshSourceKey,
                                "meshMaterialName": material.name,
                                "meshTextureSemantic": semantic,
                                "origin": textureOrigin,
                                "srgb": srgbValue,
                                "mipmaps": "true",
                                "semantic": semantic,
                                "importFailed": "false"
                            ]
                            if settings.boolValue("flipNormalY", default: false), semantic == MeshTextureSemantic.normal.rawValue {
                                settingsValues["flipNormalY"] = "true"
                            }
                            let type: AssetType = (ext == "hdr" || ext == "exr") ? .environment : .texture
                            let metadata = AssetMetadata(
                                handle: handle,
                                type: type,
                                sourcePath: relativePath,
                                importSettings: settingsValues,
                                dependencies: [],
                                lastModified: Date().timeIntervalSince1970
                            )
                            projectManager.saveMetadata(metadata, to: metaURL)
                            textureHandleMap[url] = handle
                            textureDependencies.append(handle)
                            continue
                        }

                        guard let mdlTexture = texture.mdlTexture else { continue }
                        let embeddedBase = "\(meshSanitizeFileName(material.name))_\(texture.semantic.rawValue)"
                        let embeddedCandidate = texturesFolder.appendingPathComponent("\(embeddedBase).png")
                        let textureKey = "\(meshSourceKey)|\(material.name)|\(texture.semantic.rawValue)"
                        let destinationURL: URL
                        if let existing = existingTexturesByKey[textureKey] {
                            destinationURL = rootURL.appendingPathComponent(existing.sourcePath)
                        } else if reimportMeshMeta != nil && FileManager.default.fileExists(atPath: embeddedCandidate.path) {
                            destinationURL = embeddedCandidate
                        } else {
                            destinationURL = meshUniqueFileURL(in: texturesFolder, baseName: embeddedBase, ext: "png")
                        }
                        switch exportEmbeddedTexture(mdlTexture, to: destinationURL) {
                        case .success:
                            let metaURL = AssetIO.metaURL(for: destinationURL)
                            let handle = existingTexturesByKey[textureKey]?.handle ?? loadHandle(from: metaURL) ?? AssetHandle()
                            let relativePath = PathUtils.relativePath(from: rootURL, to: destinationURL) ?? destinationURL.lastPathComponent
                            let semantic = texture.semantic.rawValue
                            let srgbValue = (semantic == MeshTextureSemantic.baseColor.rawValue || semantic == MeshTextureSemantic.emissive.rawValue) ? "true" : "false"
                            var settingsValues = [
                                "importer": importerId,
                                "importerVersion": importerVersion,
                                "sourcePath": sourceRelativePath,
                                "sourcePathAbs": sourcePathAbs,
                                "meshSourcePathAbs": meshSourceKey,
                                "meshMaterialName": material.name,
                                "meshTextureSemantic": semantic,
                                "origin": textureOrigin,
                                "srgb": srgbValue,
                                "mipmaps": "true",
                                "semantic": semantic,
                                "embedded": "true",
                                "importFailed": "false"
                            ]
                            if settings.boolValue("flipNormalY", default: false), semantic == MeshTextureSemantic.normal.rawValue {
                                settingsValues["flipNormalY"] = "true"
                            }
                            let metadata = AssetMetadata(
                                handle: handle,
                                type: .texture,
                                sourcePath: relativePath,
                                importSettings: settingsValues,
                                dependencies: [],
                                lastModified: Date().timeIntervalSince1970
                            )
                            projectManager.saveMetadata(metadata, to: metaURL)
                            let key = "\(material.name)|\(texture.semantic.rawValue)"
                            embeddedTextureHandles[key] = handle
                            textureDependencies.append(handle)
                        case .failure(let errorReason):
                            let semantic = texture.semantic.rawValue
                            let srgbValue = (semantic == MeshTextureSemantic.baseColor.rawValue || semantic == MeshTextureSemantic.emissive.rawValue)
                            let width = Int(mdlTexture.dimensions.x)
                            let height = Int(mdlTexture.dimensions.y)
                            let channels = Int(mdlTexture.channelCount)
                            let bitDepth = Int(mdlTexture.channelEncoding.rawValue)
                            let outputFormat = destinationURL.pathExtension.lowercased()
                            let diagnostics = TextureImportDiagnostics(
                                sourceAssetPath: destinationURL.path,
                                width: width,
                                height: height,
                                channelCount: channels,
                                bitDepth: bitDepth,
                                semantic: semantic,
                                srgb: srgbValue,
                                internalPixelFormat: inferInternalPixelFormat(srgb: srgbValue, bitDepth: max(bitDepth, 8), channelCount: max(channels, 4)),
                                outputFormat: outputFormat,
                                failedStage: "write",
                                reason: errorReason
                            )
                            EngineLoggerContext.log(
                                diagnostics.formattedLog(),
                                level: .error,
                                category: .assets
                            )
                            let metaURL = AssetIO.metaURL(for: destinationURL)
                            let failedHandle = existingTexturesByKey[textureKey]?.handle ?? loadHandle(from: metaURL) ?? AssetHandle()
                            let relativePath = PathUtils.relativePath(from: rootURL, to: destinationURL) ?? destinationURL.lastPathComponent
                            var failureSettings: [String: String] = [
                                "importer": importerId,
                                "importerVersion": importerVersion,
                                "sourcePath": sourceRelativePath,
                                "sourcePathAbs": sourcePathAbs,
                                "meshSourcePathAbs": meshSourceKey,
                                "meshMaterialName": material.name,
                                "meshTextureSemantic": semantic,
                                "origin": textureOrigin,
                                "srgb": srgbValue ? "true" : "false",
                                "mipmaps": "true",
                                "semantic": semantic,
                                "embedded": "true",
                                "importFailed": "true",
                                "importFailureReason": "write: \(errorReason)",
                                "importFailureAt": String(format: "%.3f", Date().timeIntervalSince1970)
                            ]
                            if settings.boolValue("flipNormalY", default: false), semantic == MeshTextureSemantic.normal.rawValue {
                                failureSettings["flipNormalY"] = "true"
                            }
                            let failedMetadata = AssetMetadata(
                                handle: failedHandle,
                                type: .texture,
                                sourcePath: relativePath,
                                importSettings: failureSettings,
                                dependencies: [],
                                lastModified: Date().timeIntervalSince1970
                            )
                            projectManager.saveMetadata(failedMetadata, to: metaURL)
                        }
                    }
                }
            }

            var materialHandles: [AssetHandle] = []
            if settings.boolValue("importMaterials", default: true) {
                for material in meshInfo.materials {
                    let baseName = meshSanitizeFileName(material.name.isEmpty ? "Material" : material.name)
                    let candidateURL = materialsFolder.appendingPathComponent("\(baseName).mcmat")
                    let materialKey = "\(meshSourceKey)|\(material.name)"
                    let materialURL: URL
                    let handle: AssetHandle
                    if let existing = existingMaterialsByKey[materialKey] {
                        materialURL = rootURL.appendingPathComponent(existing.sourcePath)
                        handle = existing.handle
                    } else if useFBXSourceFolderOutputs || (reimportMeshMeta != nil && FileManager.default.fileExists(atPath: candidateURL.path)) {
                        materialURL = candidateURL
                        handle = loadHandle(from: AssetIO.metaURL(for: materialURL)) ?? AssetHandle()
                    } else {
                        materialURL = meshUniqueFileURL(in: materialsFolder, baseName: baseName, ext: "mcmat")
                        handle = loadHandle(from: AssetIO.metaURL(for: materialURL)) ?? AssetHandle()
                    }
                    var textureSlots = MaterialTextureSlots()
                    var materialDependencies: [AssetHandle] = []

                    let combineORM = settings.boolValue("combineORM", default: false)

                    func handleFor(_ semantic: MeshTextureSemantic) -> AssetHandle? {
                        guard let texture = material.textures[semantic] else { return nil }
                        if let url = texture.url, let handle = textureHandleMap[url] {
                            materialDependencies.append(handle)
                            return handle
                        }
                        let key = "\(material.name)|\(semantic.rawValue)"
                        if let handle = embeddedTextureHandles[key] {
                            materialDependencies.append(handle)
                            return handle
                        }
                        return nil
                    }

                    let metallicHandle = handleFor(.metallic)
                    let roughnessHandle = handleFor(.roughness)
                    let metalRoughnessHandle = handleFor(.metallicRoughness)
                    textureSlots.baseColor = handleFor(.baseColor)
                    textureSlots.normal = handleFor(.normal)
                    let aoHandle = handleFor(.occlusion)
                    textureSlots.emissive = handleFor(.emissive)

                    var maskMode: PBRMaskMode = .separate
                    let directORMHandle = (aoHandle != nil && aoHandle == metalRoughnessHandle) ? aoHandle : nil
                    let sharedORMHandle = directORMHandle ?? (combineORM
                        ? (aoHandle != nil && aoHandle == metallicHandle && aoHandle == roughnessHandle ? aoHandle : nil)
                        : nil)

                    if let ormHandle = sharedORMHandle {
                        textureSlots.orm = ormHandle
                        maskMode = .orm
                    } else if let metalRoughnessHandle {
                        textureSlots.metalRoughness = metalRoughnessHandle
                        maskMode = .metallicRoughness
                    } else if let metallic = metallicHandle,
                              let roughness = roughnessHandle,
                              metallic == roughness {
                        // USDZ often exposes packed MR as separate metallic/roughness refs to the same texture.
                        textureSlots.metalRoughness = metallic
                        maskMode = .metallicRoughness
                    } else {
                        textureSlots.metallic = metallicHandle
                        textureSlots.roughness = roughnessHandle
                        maskMode = .separate
                    }

                    if maskMode != .orm {
                        textureSlots.ao = aoHandle
                    }
                    textureSlots.enforceMetalRoughnessRule()
                    let maskChannels = PBRMaskChannels()

                    let materialAsset = MaterialAsset(
                        handle: handle,
                        name: baseName,
                        baseColorFactor: material.baseColor,
                        metallicFactor: material.metallicFactor,
                        roughnessFactor: material.roughnessFactor,
                        aoFactor: material.aoFactor,
                        emissiveColor: material.emissiveColor,
                        emissiveIntensity: 1.0,
                        alphaMode: material.alphaMode,
                        alphaCutoff: material.alphaCutoff,
                        doubleSided: material.doubleSided,
                        unlit: material.unlit,
                        textures: textureSlots,
                        pbrMaskMode: maskMode,
                        pbrMaskChannels: maskChannels
                    )

                    _ = MaterialSerializer.save(materialAsset, to: materialURL)

                    let relativePath = PathUtils.relativePath(from: rootURL, to: materialURL) ?? materialURL.lastPathComponent
                    let metaURL = AssetIO.metaURL(for: materialURL)
                    let metadata = AssetMetadata(
                        handle: handle,
                        type: .material,
                        sourcePath: relativePath,
                        importSettings: [
                            "importer": importerId,
                            "importerVersion": importerVersion,
                            "sourcePath": sourceRelativePath,
                            "sourcePathAbs": sourcePathAbs,
                            "meshSourcePathAbs": meshSourceKey,
                            "meshMaterialName": material.name
                        ],
                        dependencies: materialDependencies,
                        lastModified: Date().timeIntervalSince1970
                    )
                    projectManager.saveMetadata(metadata, to: metaURL)
                    materialHandles.append(handle)
                }
            }

            var skeletonHandle: AssetHandle?
            var clipHandles: [AssetHandle] = []
            var clipSummaryEntries: [String] = []
            if meshInfo.isSkinned, let skeletonInfo = meshInfo.skeletonInfo, skeletonInfo.jointCount > 0 {
                let skeletonBaseName = useFBXSourceFolderOutputs
                    ? meshSanitizeFileName(sourceURL.deletingPathExtension().lastPathComponent)
                    : meshSanitizeFileName("\(scan.suggestedName)_Skeleton")
                let skeletonCandidateURL = skeletonsFolder.appendingPathComponent("\(skeletonBaseName).mcskeleton")
                let skeletonURL: URL
                if let existing = existingSkeletonBySource {
                    skeletonURL = rootURL.appendingPathComponent(existing.sourcePath)
                    skeletonHandle = existing.handle
                } else if useFBXSourceFolderOutputs || (reimportMeshMeta != nil && FileManager.default.fileExists(atPath: skeletonCandidateURL.path)) {
                    skeletonURL = skeletonCandidateURL
                    skeletonHandle = loadHandle(from: AssetIO.metaURL(for: skeletonURL)) ?? AssetHandle()
                } else {
                    skeletonURL = meshUniqueFileURL(in: skeletonsFolder, baseName: skeletonBaseName, ext: "mcskeleton")
                    skeletonHandle = loadHandle(from: AssetIO.metaURL(for: skeletonURL)) ?? AssetHandle()
                }

                let resolvedSkeletonHandle = skeletonHandle ?? AssetHandle()
                let skeletonAsset = SkeletonAsset(
                    handle: resolvedSkeletonHandle,
                    name: skeletonBaseName,
                    sourcePath: sourceRelativePath,
                    joints: skeletonInfo.joints
                )
                _ = SkeletonAssetSerializer.save(skeletonAsset, to: skeletonURL)

                let skeletonRelativePath = PathUtils.relativePath(from: rootURL, to: skeletonURL) ?? skeletonURL.lastPathComponent
                let skeletonMetaURL = AssetIO.metaURL(for: skeletonURL)
                let skeletonMeta = AssetMetadata(
                    handle: resolvedSkeletonHandle,
                    type: .skeleton,
                    sourcePath: skeletonRelativePath,
                    importSettings: [
                        "importer": importerId,
                        "importerVersion": importerVersion,
                        "sourcePath": sourceRelativePath,
                        "sourcePathAbs": sourcePathAbs,
                        "meshSourcePathAbs": meshSourceKey,
                        "jointCount": String(skeletonInfo.jointCount),
                        "importScaleApplied": scan.details["fbxScaleFactor"] ?? (settings.values["scale"] ?? "1.0"),
                        "importScaleNormalization": scan.details["fbxScaleNormalization"] ?? "none",
                        "importScaleSource": scan.details["fbxScaleSource"] ?? "unknown"
                    ],
                    dependencies: [],
                    lastModified: Date().timeIntervalSince1970
                )
                projectManager.saveMetadata(skeletonMeta, to: skeletonMetaURL)
                writtenPaths.append(skeletonRelativePath)
                skeletonHandle = resolvedSkeletonHandle

                for (index, clipInfo) in meshInfo.clipInfos.enumerated() {
                    let clipName = meshSanitizeFileName(clipInfo.name.isEmpty ? "\(scan.suggestedName)_Clip_\(index + 1)" : clipInfo.name)
                    let clipCandidateURL = clipsFolder.appendingPathComponent("\(clipName).mcanim")
                    let clipURL: URL
                    let clipHandle: AssetHandle
                    if let existing = existingClipByName[clipName] {
                        clipURL = rootURL.appendingPathComponent(existing.sourcePath)
                        clipHandle = existing.handle
                    } else if useFBXSourceFolderOutputs || (reimportMeshMeta != nil && FileManager.default.fileExists(atPath: clipCandidateURL.path)) {
                        clipURL = clipCandidateURL
                        clipHandle = loadHandle(from: AssetIO.metaURL(for: clipURL)) ?? AssetHandle()
                    } else {
                        clipURL = meshUniqueFileURL(in: clipsFolder, baseName: clipName, ext: "mcanim")
                        clipHandle = loadHandle(from: AssetIO.metaURL(for: clipURL)) ?? AssetHandle()
                    }

                    let clipAsset = AnimationClipAsset(
                        handle: clipHandle,
                        name: clipName,
                        sourcePath: sourceRelativePath,
                        durationSeconds: clipInfo.durationSeconds,
                        tracks: clipInfo.tracks
                    )
                    _ = AnimationClipAssetSerializer.save(clipAsset, to: clipURL)

                    let clipRelativePath = PathUtils.relativePath(from: rootURL, to: clipURL) ?? clipURL.lastPathComponent
                    let clipMetaURL = AssetIO.metaURL(for: clipURL)
                    let clipDependencies = skeletonHandle.map { [$0] } ?? []
                    let clipMeta = AssetMetadata(
                        handle: clipHandle,
                        type: .animationClip,
                        sourcePath: clipRelativePath,
                        importSettings: [
                            "importer": importerId,
                            "importerVersion": importerVersion,
                            "sourcePath": sourceRelativePath,
                            "sourcePathAbs": sourcePathAbs,
                            "meshSourcePathAbs": meshSourceKey,
                            "clipName": clipName,
                            "durationSeconds": String(format: "%.6f", clipInfo.durationSeconds),
                            "skeletonHandle": resolvedSkeletonHandle.rawValue.uuidString,
                            "importScaleApplied": scan.details["fbxScaleFactor"] ?? (settings.values["scale"] ?? "1.0"),
                            "importScaleSource": scan.details["fbxScaleSource"] ?? "meshImport",
                            "associationState": "resolved",
                            "targetSkeletonJointCount": String(skeletonInfo.jointCount),
                            "clipCanonicalJointCountAfterRemap": String(skeletonInfo.jointCount)
                        ],
                        dependencies: clipDependencies,
                        lastModified: Date().timeIntervalSince1970
                    )
                    projectManager.saveMetadata(clipMeta, to: clipMetaURL)
                    writtenPaths.append(clipRelativePath)
                    clipHandles.append(clipHandle)
                    clipSummaryEntries.append("\(clipName):\(String(format: "%.6f", clipInfo.durationSeconds))")
                }

                if importerId == "FbxImporter", !clipHandles.isEmpty {
                    MeshImporter.repairAnimationGraphClipHandlesAfterFbxImport(
                        projectManager: projectManager,
                        rootURL: rootURL,
                        sourceFolderURL: sourceFolderURL,
                        sourceURL: sourceURL,
                        newClipHandles: clipHandles,
                        clipInfos: meshInfo.clipInfos
                    )
                }
            }

            let meshHandle = existingMeshHandle ?? AssetHandle()
            let meshRelativePath = PathUtils.relativePath(from: rootURL, to: meshDestinationURL) ?? meshDestinationURL.lastPathComponent

            var meshImportSettings = settings.values
            meshImportSettings["importer"] = importerId
            meshImportSettings["importerVersion"] = importerVersion
            meshImportSettings["sourcePath"] = sourceRelativePath
            meshImportSettings["sourcePathAbs"] = sourcePathAbs
            if importerId == "FbxImporter" {
                meshImportSettings["importScaleNormalization"] = scan.details["fbxScaleNormalization"] ?? "none"
                meshImportSettings["importScaleApplied"] = scan.details["fbxScaleFactor"] ?? (meshImportSettings["scale"] ?? "1.0")
                meshImportSettings["importScaleSource"] = scan.details["fbxScaleSource"] ?? "unknown"
            }
            if !meshInfo.submeshMaterialIndices.isEmpty {
                let handleStrings = meshInfo.submeshMaterialIndices.map { index -> String in
                    if index >= 0 && index < materialHandles.count {
                        return materialHandles[index].rawValue.uuidString
                    }
                    return ""
                }
                meshImportSettings["submeshMaterials"] = handleStrings.joined(separator: ",")
            }
            meshImportSettings["isSkinned"] = meshInfo.isSkinned ? "true" : "false"
            meshImportSettings["hasRootMotion"] = meshInfo.hasRootMotion ? "true" : "false"
            if let rootMotionBoneName = meshInfo.rootMotionBoneName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !rootMotionBoneName.isEmpty {
                meshImportSettings["rootBoneName"] = rootMotionBoneName
            } else {
                meshImportSettings.removeValue(forKey: "rootBoneName")
            }
            if let skeletonHandle {
                meshImportSettings["skeletonHandle"] = skeletonHandle.rawValue.uuidString
            } else {
                meshImportSettings.removeValue(forKey: "skeletonHandle")
            }
            if !clipHandles.isEmpty {
                meshImportSettings["clipHandles"] = clipHandles.map { $0.rawValue.uuidString }.joined(separator: ",")
                meshImportSettings["defaultClipHandle"] = clipHandles[0].rawValue.uuidString
                meshImportSettings["clipSummaries"] = clipSummaryEntries.joined(separator: ";")
            } else {
                meshImportSettings.removeValue(forKey: "clipHandles")
                meshImportSettings.removeValue(forKey: "defaultClipHandle")
                meshImportSettings.removeValue(forKey: "clipSummaries")
            }

            let skeletonDependencies = skeletonHandle.map { [$0] } ?? []
            let allDependencies = materialHandles + textureDependencies + skeletonDependencies + clipHandles
            let meshMetadata = AssetMetadata(
                handle: meshHandle,
                type: .model,
                sourcePath: meshRelativePath,
                importSettings: meshImportSettings,
                dependencies: allDependencies,
                lastModified: Date().timeIntervalSince1970
            )
            projectManager.saveMetadata(meshMetadata, to: meshMetaURL)

#if DEBUG
            if importerId == "FbxImporter" {
                let clipDefault = clipHandles.first?.rawValue.uuidString ?? "<none>"
                let generatedOutputPaths = ([meshRelativePath] + writtenPaths)
                let outputPathSummary = generatedOutputPaths.map { path in
                    let status = preExistingGeneratedPaths.contains(path) ? "overwrite" : "new"
                    return "\(status):\(path)"
                }.joined(separator: "\n")
                EngineLoggerContext.log(
                    "FBX import summary source=\(sourceURL.path)\nmode=\(scan.details["fbxImportMode"] ?? "<unknown>")\noutputPolicy=\(useFBXSourceFolderOutputs ? "sourceFolder" : "defaultResolverFolders")\nsourceFolder=\(sourceFolderRelativePath)\nmeshHandle=\(meshHandle.rawValue.uuidString)\nmeshPath=\(meshRelativePath)\nskeletonHandle=\(skeletonHandle?.rawValue.uuidString ?? "<none>")\nclipCount=\(clipHandles.count)\ndefaultClip=\(clipDefault)\nmaterialCount=\(materialHandles.count)\ngeneratedOutputs=\n\(outputPathSummary)",
                    level: .debug,
                    category: .assets
                )
            }
#endif

            commitResult = ImportCommitResult(
                primaryHandle: meshHandle,
                writtenPaths: [meshRelativePath] + writtenPaths,
                dependencyHandles: allDependencies,
                meshPath: meshRelativePath,
                skeletonHandle: skeletonHandle,
                defaultClipHandle: clipHandles.first,
                submeshMaterialHandles: materialHandles
            )

            return true
        }

        return ok ? commitResult : nil
    }

    private struct GraphClipCandidate {
        let handle: AssetHandle
        let clipName: String
        let sourcePath: String
        let sourceStem: String
    }

    fileprivate static func repairAnimationGraphClipHandlesAfterFbxImport(projectManager: EditorProjectManager,
                                                                          rootURL: URL,
                                                                          sourceFolderURL: URL,
                                                                          sourceURL: URL,
                                                                          newClipHandles: [AssetHandle],
                                                                          clipInfos: [MeshAnimationClipScanInfo]) {
        let metadataSnapshot = projectManager.assetMetadataSnapshot()
        let clipMetas = metadataSnapshot.filter { $0.type == .animationClip }
        let clipMetaByHandle = Dictionary(uniqueKeysWithValues: clipMetas.map { ($0.handle, $0) })
        let validClipHandleSet = Set(clipMetas.map(\.handle))
        let graphMetas = metadataSnapshot.filter { meta in
            guard meta.type == .animationGraph else { return false }
            let graphURL = rootURL.appendingPathComponent(meta.sourcePath).standardizedFileURL
            return graphURL.deletingLastPathComponent().standardizedFileURL == sourceFolderURL.standardizedFileURL
        }
        guard !graphMetas.isEmpty else { return }

        let sourceStem = sourceURL.deletingPathExtension().lastPathComponent.lowercased()
        let newClipCandidates: [GraphClipCandidate] = newClipHandles.enumerated().map { index, handle in
            let clipName = index < clipInfos.count ? clipInfos[index].name : ""
            let meta = clipMetaByHandle[handle]
            return GraphClipCandidate(
                handle: handle,
                clipName: normalizeGraphClipName(meta?.importSettings["clipName"] ?? clipName),
                sourcePath: meta?.sourcePath ?? "",
                sourceStem: normalizedSourceStem(meta: meta, fallback: sourceStem)
            )
        }
        guard !newClipCandidates.isEmpty else { return }

        for graphMeta in graphMetas {
            let graphURL = rootURL.appendingPathComponent(graphMeta.sourcePath).standardizedFileURL
            guard let loaded = AnimationGraphAssetSerializer.load(from: graphURL, fallbackHandle: graphMeta.handle) else { continue }
            var graph = loaded
            var changed = false
            var ambiguousWarnings: [String] = []

            func resolveReplacement(for staleHandle: AssetHandle,
                                    hintName: String) -> AssetHandle? {
                if let oldMeta = clipMetaByHandle[staleHandle], oldMeta.type == .animationClip {
                    let samePathMatches = newClipCandidates.filter { !$0.sourcePath.isEmpty && $0.sourcePath == oldMeta.sourcePath }
                    if let chosen = samePathMatches.first {
                        if samePathMatches.count > 1 {
                            ambiguousWarnings.append("path:\(oldMeta.sourcePath)")
                        }
                        return chosen.handle
                    }

                    let oldClipName = normalizeGraphClipName(oldMeta.importSettings["clipName"] ?? "")
                    if !oldClipName.isEmpty {
                        let nameMatches = newClipCandidates.filter { $0.clipName == oldClipName }
                        if let chosen = nameMatches.first {
                            if nameMatches.count > 1 {
                                ambiguousWarnings.append("name:\(oldClipName)")
                            }
                            return chosen.handle
                        }
                    }

                    let oldStem = normalizedSourceStem(meta: oldMeta, fallback: sourceStem)
                    let stemMatches = newClipCandidates.filter { $0.sourceStem == oldStem }
                    if let chosen = stemMatches.first {
                        if stemMatches.count > 1 {
                            ambiguousWarnings.append("source:\(oldStem)")
                        }
                        return chosen.handle
                    }
                }

                let hint = normalizeGraphClipName(hintName)
                if !hint.isEmpty {
                    let nameMatches = newClipCandidates.filter {
                        !$0.clipName.isEmpty && ($0.clipName == hint || $0.clipName.contains(hint) || hint.contains($0.clipName))
                    }
                    if let chosen = nameMatches.first {
                        if nameMatches.count > 1 {
                            ambiguousWarnings.append("hint:\(hint)")
                        }
                        return chosen.handle
                    }
                }

                let stemMatches = newClipCandidates.filter { $0.sourceStem == sourceStem }
                if let chosen = stemMatches.first {
                    if stemMatches.count > 1 {
                        ambiguousWarnings.append("fallbackSource:\(sourceStem)")
                    }
                    return chosen.handle
                }

                return newClipCandidates.first?.handle
            }

            func remapHandle(_ handle: AssetHandle?, hintName: String) -> AssetHandle? {
                guard let handle else { return nil }
                if validClipHandleSet.contains(handle) {
                    return handle
                }
                guard let replacement = resolveReplacement(for: handle, hintName: hintName) else {
                    return handle
                }
                if replacement != handle {
                    changed = true
                }
                return replacement
            }

            for nodeIndex in graph.nodes.indices {
                var node = graph.nodes[nodeIndex]
                node.clipHandle = remapHandle(node.clipHandle, hintName: node.title)

                if var blend1D = node.blend1D {
                    for sampleIndex in blend1D.samples.indices {
                        let sample = blend1D.samples[sampleIndex]
                        let remapped = remapHandle(sample.clipHandle, hintName: node.title) ?? sample.clipHandle
                        if remapped != sample.clipHandle {
                            blend1D.samples[sampleIndex] = AnimationGraphBlend1DSampleDefinition(
                                clipHandle: remapped,
                                threshold: sample.threshold
                            )
                        }
                    }
                    node.blend1D = blend1D
                }

                if var blend2D = node.blend2D {
                    for sampleIndex in blend2D.samples.indices {
                        let sample = blend2D.samples[sampleIndex]
                        let remapped = remapHandle(sample.clipHandle, hintName: node.title) ?? sample.clipHandle
                        if remapped != sample.clipHandle {
                            blend2D.samples[sampleIndex] = AnimationGraphBlend2DSampleDefinition(
                                clipHandle: remapped,
                                position: sample.position
                            )
                        }
                    }
                    node.blend2D = blend2D
                }

                if var stateMachine = node.stateMachine {
                    for stateIndex in stateMachine.states.indices {
                        var state = stateMachine.states[stateIndex]
                        state.clipHandle = remapHandle(state.clipHandle, hintName: state.name)
                        stateMachine.states[stateIndex] = state
                    }
                    node.stateMachine = stateMachine
                }

                graph.nodes[nodeIndex] = node
            }

            let allGraphClipHandles = collectGraphClipHandles(graph)
            let unresolved = allGraphClipHandles.filter { !validClipHandleSet.contains($0) }
            if !unresolved.isEmpty {
                EngineLoggerContext.log(
                    "AnimationGraph repair unresolved clip handles graph=\(graphURL.lastPathComponent) count=\(unresolved.count)",
                    level: .warning,
                    category: .assets
                )
            }

            if changed {
                _ = AnimationGraphAssetSerializer.save(graph, to: graphURL)
                if let metaURL = projectManager.metaURLForAsset(assetURL: graphURL, relativePath: graphMeta.sourcePath) {
                    var updatedMeta = graphMeta
                    updatedMeta.lastModified = Date().timeIntervalSince1970
                    projectManager.saveMetadata(updatedMeta, to: metaURL)
                }
                if !ambiguousWarnings.isEmpty {
                    EngineLoggerContext.log(
                        "AnimationGraph clip remap applied graph=\(graphURL.lastPathComponent) ambiguousRules=\(Array(Set(ambiguousWarnings)).joined(separator: ", "))",
                        level: .warning,
                        category: .assets
                    )
                } else {
                    EngineLoggerContext.log(
                        "AnimationGraph clip remap applied graph=\(graphURL.lastPathComponent)",
                        level: .info,
                        category: .assets
                    )
                }
            }


            let compile = AnimationGraphCompiler.compile(asset: graph) { handle in
                validClipHandleSet.contains(handle)
            }
            if case let .failure(.invalidGraph(errors)) = compile {
                EngineLoggerContext.log(
                    "AnimationGraph validation failed after clip remap graph=\(graphURL.lastPathComponent) errors=\(errors.prefix(8).joined(separator: " | "))",
                    level: .warning,
                    category: .assets
                )
            }
        }
    }

    private static func collectGraphClipHandles(_ graph: AnimationGraphAsset) -> [AssetHandle] {
        var handles: [AssetHandle] = []
        for node in graph.nodes {
            if let clip = node.clipHandle {
                handles.append(clip)
            }
            if let blend1D = node.blend1D {
                handles.append(contentsOf: blend1D.samples.map(\.clipHandle))
            }
            if let blend2D = node.blend2D {
                handles.append(contentsOf: blend2D.samples.map(\.clipHandle))
            }
            if let stateMachine = node.stateMachine {
                handles.append(contentsOf: stateMachine.states.compactMap(\.clipHandle))
            }
        }
        return handles
    }

    private static func normalizeGraphClipName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedSourceStem(meta: AssetMetadata?, fallback: String) -> String {
        guard let meta else { return fallback }
        let candidate = (meta.importSettings["sourcePath"] ?? meta.importSettings["sourcePathAbs"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.isEmpty { return fallback }
        return URL(fileURLWithPath: candidate).deletingPathExtension().lastPathComponent.lowercased()
    }

    private static func normalizeClipToken(_ raw: String) -> String {
        raw.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func uniqueFolderURL(in folder: URL, baseName: String) -> URL {
        let fm = FileManager.default
        let sanitized = meshSanitizeFileName(baseName.isEmpty ? "Mesh" : baseName)
        var candidate = folder.appendingPathComponent(sanitized, isDirectory: true)
        if !fm.fileExists(atPath: candidate.path) { return candidate }
        var index = 1
        while true {
            let name = "\(sanitized)_\(index)"
            candidate = folder.appendingPathComponent(name, isDirectory: true)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }
}

extension FbxImporter {
    private struct SameFolderSkeletonResolution {
        let handle: AssetHandle?
        let skeletonPath: String?
        let source: String
        let isAmbiguous: Bool
    }

    private struct SkeletonAssociationCandidate {
        let metadata: AssetMetadata
        let score: Float
    }

    private struct ClipRemapDiagnostics {
        let totalChannels: Int
        let mappedChannels: Int
        let unmappedChannelNames: [String]
    }

    private struct AnimationImportScaleResolution {
        let factor: Float
        let source: String
    }

    private static func resolveAnimationImportScale(scan: ImportScanResult,
                                                    metadataSnapshot: [AssetMetadata],
                                                    resolvedSkeletonHandle: AssetHandle?) -> AnimationImportScaleResolution {
        let scanFactor = parseScale(scan.details["fbxScaleFactor"])
        if abs(scanFactor - 1.0) > 0.0001 {
            return AnimationImportScaleResolution(
                factor: scanFactor,
                source: scan.details["fbxScaleSource"] ?? "fbxScan"
            )
        }

        if let resolvedSkeletonHandle,
           let skeletonMeta = metadataSnapshot.first(where: { $0.type == .skeleton && $0.handle == resolvedSkeletonHandle }) {
            let skeletonScale = parseScale(skeletonMeta.importSettings["importScaleApplied"])
            if abs(skeletonScale - 1.0) > 0.0001 {
                return AnimationImportScaleResolution(factor: skeletonScale, source: "skeletonMetadata")
            }
        }

        if let resolvedSkeletonHandle,
           let skeletonMeta = metadataSnapshot.first(where: { $0.type == .skeleton && $0.handle == resolvedSkeletonHandle }),
           let meshSourcePathAbs = skeletonMeta.importSettings["meshSourcePathAbs"],
           let meshMeta = metadataSnapshot.first(where: {
               $0.type == .model
                   && $0.importSettings["importer"] == "FbxImporter"
                   && $0.importSettings["sourcePathAbs"] == meshSourcePathAbs
           }) {
            let meshScale = parseScale(meshMeta.importSettings["importScaleApplied"])
            if abs(meshScale - 1.0) > 0.0001 {
                return AnimationImportScaleResolution(factor: meshScale, source: "associatedMeshMetadata")
            }
        }

        return AnimationImportScaleResolution(factor: scanFactor, source: "default")
    }

    private static func applyTranslationScaleToClipInfo(_ clip: MeshAnimationClipScanInfo, factor: Float) -> MeshAnimationClipScanInfo {
        guard abs(factor - 1.0) > 0.0001 else { return clip }
        let scaledTracks = clip.tracks.map { track in
            AnimationClipAsset.JointTrack(
                jointIndex: track.jointIndex,
                translations: track.translations.map {
                    AnimationClipAsset.TranslationKeyframe(time: $0.time, value: $0.value * factor)
                },
                rotations: track.rotations,
                scales: track.scales
            )
        }
        return MeshAnimationClipScanInfo(
            name: clip.name,
            durationSeconds: clip.durationSeconds,
            tracks: scaledTracks
        )
    }

    private static func parseScale(_ raw: String?) -> Float {
        guard let raw else { return 1.0 }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = Float(trimmed), parsed.isFinite, parsed > 0 else { return 1.0 }
        return parsed
    }

    private static func canonicalJointName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        var normalized = trimmed.replacingOccurrences(of: "\\", with: "/")
        if let lastPath = normalized.split(separator: "/").last {
            normalized = String(lastPath)
        }
        if let lastNode = normalized.split(separator: "|").last {
            normalized = String(lastNode)
        }
        if let namespaceSplit = normalized.split(separator: ":").last {
            normalized = String(namespaceSplit)
        }
        return normalized.lowercased()
    }

    private static func commitAnimationOnlyFBX(scan: ImportScanResult,
                                               settings: ImportSettings,
                                               projectManager: EditorProjectManager,
                                               resolver: AssetPathResolver,
                                               importerId: String,
                                               importerVersion: String) -> ImportCommitResult? {
        guard let rootURL = projectManager.assetRootURL() else { return nil }
        guard let meshInfo = scan.meshInfo, !meshInfo.clipInfos.isEmpty else { return nil }
        let sourceURL = scan.sourceURL.standardizedFileURL
        let sourceFolderURL = sourceURL.deletingLastPathComponent().standardizedFileURL
        let clipRoot = isUnderRoot(sourceURL, rootURL: rootURL)
            ? sourceFolderURL
            : (resolver.destinationFolder(for: .animationClip) ?? sourceFolderURL)
        let sourceRelativePath = PathUtils.relativePath(from: rootURL, to: sourceURL) ?? sourceURL.lastPathComponent
        let sourcePathAbs = sourceURL.path
        let sourceFolder = sourceURL.deletingLastPathComponent().standardizedFileURL.path
        let metadataSnapshot = projectManager.assetMetadataSnapshot()
        var existingClipByName: [String: AssetMetadata] = [:]
        var existingSkeletonAssociation: AssetHandle?
        for meta in metadataSnapshot where meta.type == .animationClip {
            guard meta.importSettings["importer"] == importerId else { continue }
            if meta.importSettings["sourcePathAbs"] == sourcePathAbs,
               let clipName = meta.importSettings["clipName"] {
                existingClipByName[clipName] = meta
                if existingSkeletonAssociation == nil,
                   let raw = meta.importSettings["skeletonHandle"],
                   let uuid = UUID(uuidString: raw) {
                    existingSkeletonAssociation = AssetHandle(rawValue: uuid)
                }
            }
        }
        let preExistingClipPaths: Set<String> = Set(metadataSnapshot.compactMap { meta in
            guard meta.type == .animationClip else { return nil }
            guard meta.importSettings["importer"] == importerId else { return nil }
            guard meta.importSettings["sourcePathAbs"] == sourcePathAbs else { return nil }
            return meta.sourcePath
        })

        let forcedSkeletonHandle: AssetHandle? = {
            let raw = settings.values["targetSkeletonHandle"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !raw.isEmpty, let uuid = UUID(uuidString: raw) else { return nil }
            return AssetHandle(rawValue: uuid)
        }()

        let sameFolderResolution = resolveSameFolderSkeleton(
            metadataSnapshot: metadataSnapshot,
            rootURL: rootURL,
            sourceFolderURL: sourceFolderURL
        )

        var resolvedSkeletonHandle: AssetHandle? = forcedSkeletonHandle
            ?? sameFolderResolution.handle
            ?? existingSkeletonAssociation
        var skeletonResolutionSource: String = {
            if forcedSkeletonHandle != nil { return "forcedSkeletonHandle" }
            if sameFolderResolution.handle != nil { return sameFolderResolution.source }
            if existingSkeletonAssociation != nil { return "existingClipAssociation" }
            return "none"
        }()

        if sameFolderResolution.isAmbiguous {
#if DEBUG
            EngineLoggerContext.log(
                "FBX animation-only skeleton resolution warning source=\(sourceURL.path)\nreason=multipleSameFolderSkeletons\nfolder=\(sourceFolderURL.path)",
                level: .warning,
                category: .assets
            )
#endif
        }

        if sameFolderResolution.handle != nil {
#if DEBUG
            EngineLoggerContext.log(
                "FBX animation-only same-folder skeleton resolution sourceClip=\(sourceURL.path)\nchosenSkeletonPath=\(sameFolderResolution.skeletonPath ?? "<none>")\nchosenSkeletonHandle=\(sameFolderResolution.handle?.rawValue.uuidString ?? "<none>")",
                level: .debug,
                category: .assets
            )
#endif
        }

        if resolvedSkeletonHandle == nil {
            resolvedSkeletonHandle = resolveSkeletonFromImportedMeshMetadata(
                metadataSnapshot: metadataSnapshot,
                rootURL: rootURL,
                sourceFolderPath: sourceFolder,
                sourceSkeleton: meshInfo.skeletonInfo,
                clipInfos: meshInfo.clipInfos
            )
            if resolvedSkeletonHandle != nil {
                skeletonResolutionSource = "sameFolderMeshMetadata"
            }
        }
        if resolvedSkeletonHandle == nil {
            let candidates = compatibleSkeletonCandidates(
                metadataSnapshot: metadataSnapshot,
                rootURL: rootURL,
                sourceFolderPath: sourceFolder,
                sourceSkeleton: meshInfo.skeletonInfo,
                clipInfos: meshInfo.clipInfos
            )
            if let best = candidates.first {
                if candidates.count == 1 {
                    resolvedSkeletonHandle = best.metadata.handle
                    skeletonResolutionSource = "canonicalCompatibilitySingle"
                } else if let second = candidates.dropFirst().first,
                          (best.score - second.score) >= 0.05 {
                    resolvedSkeletonHandle = best.metadata.handle
                    skeletonResolutionSource = "canonicalCompatibilityBestScore"
                }
            }
        }
        var importScaleResolution = resolveAnimationImportScale(
            scan: scan,
            metadataSnapshot: metadataSnapshot,
            resolvedSkeletonHandle: resolvedSkeletonHandle
        )
        if skeletonResolutionSource == "sameFolderSkeleton",
           let resolvedSkeletonHandle,
           let skeletonScale = skeletonImportScale(handle: resolvedSkeletonHandle, metadataSnapshot: metadataSnapshot),
           abs(skeletonScale - 1.0) > 0.0001 {
            importScaleResolution = AnimationImportScaleResolution(factor: skeletonScale, source: "sameFolderSkeleton")
        }
        let importScaleApplied = importScaleResolution.factor
        let targetSkeleton = resolvedSkeletonHandle.flatMap {
            loadSkeletonAsset(handle: $0, metadataSnapshot: metadataSnapshot, rootURL: rootURL)
        }
        let remapResult = remapClipInfosToSkeleton(
            clipInfos: meshInfo.clipInfos,
            sourceSkeleton: meshInfo.skeletonInfo,
            targetSkeleton: targetSkeleton
        )
        let clipSourceInfos: [MeshAnimationClipScanInfo] = targetSkeleton == nil ? meshInfo.clipInfos : remapResult.clips
        let canonicalJointCount = meshInfo.skeletonInfo?.jointCount ?? 0
        let targetSkeletonJointCount = targetSkeleton?.joints.count ?? 0

        var commitResult: ImportCommitResult?
        let ok = projectManager.performAssetMutation {
            try FileManager.default.createDirectory(at: clipRoot, withIntermediateDirectories: true)
            var clipHandles: [AssetHandle] = []
            var writtenPaths: [String] = []
            var unresolvedReasons: [String] = []

            for (index, clipInfo) in clipSourceInfos.enumerated() {
                let clipName = meshSanitizeFileName(clipInfo.name.isEmpty ? "\(scan.suggestedName)_Clip_\(index + 1)" : clipInfo.name)
                let clipURL: URL
                let clipHandle: AssetHandle
                if let existing = existingClipByName[clipName] {
                    clipURL = rootURL.appendingPathComponent(existing.sourcePath)
                    clipHandle = existing.handle
                } else {
                    let candidate = clipRoot.appendingPathComponent("\(clipName).mcanim")
                    if FileManager.default.fileExists(atPath: candidate.path) {
                        let candidateMetaURL = AssetIO.metaURL(for: candidate)
                        let candidateRelativePath = PathUtils.relativePath(from: rootURL, to: candidate)
                        let candidateMeta = candidateRelativePath.flatMap { rel in
                            metadataSnapshot.first(where: { $0.type == .animationClip && $0.sourcePath == rel })
                        }
                        let candidateSource = candidateMeta?.importSettings["sourcePathAbs"] ?? ""
                        if candidateSource == sourcePathAbs {
                            clipURL = candidate
                            clipHandle = loadHandle(from: candidateMetaURL) ?? AssetHandle()
                        } else {
                            clipURL = meshUniqueFileURL(in: clipRoot, baseName: clipName, ext: "mcanim")
                            clipHandle = loadHandle(from: AssetIO.metaURL(for: clipURL)) ?? AssetHandle()
                            if let candidateMeta {
                                EngineLoggerContext.log(
                                    "FBX animation import name collision clip=\(clipName).mcanim existingSource=\(candidateSource.isEmpty ? "<unknown>" : candidateSource) newSource=\(sourcePathAbs) action=disambiguate",
                                    level: .warning,
                                    category: .assets
                                )
                            }
                        }
                    } else {
                        clipURL = meshUniqueFileURL(in: clipRoot, baseName: clipName, ext: "mcanim")
                        clipHandle = loadHandle(from: AssetIO.metaURL(for: clipURL)) ?? AssetHandle()
                    }
                }

                let clipAsset = AnimationClipAsset(
                    handle: clipHandle,
                    name: clipName,
                    sourcePath: sourceRelativePath,
                    durationSeconds: clipInfo.durationSeconds,
                    tracks: clipInfo.tracks
                )
                _ = AnimationClipAssetSerializer.save(clipAsset, to: clipURL)

                let associationState: String
                var associationReason = ""
                if resolvedSkeletonHandle != nil {
                    associationState = "resolved"
                } else {
                    associationState = "unresolved"
                    associationReason = "No canonical skeleton match found for animation-only FBX."
                    unresolvedReasons.append("\(clipName): \(associationReason)")
                }

                var importSettings: [String: String] = [
                    "importer": importerId,
                    "importerVersion": importerVersion,
                    "sourcePath": sourceRelativePath,
                    "sourcePathAbs": sourcePathAbs,
                    "fbxImportMode": "animationOnly",
                    "fileKind": "animationOnly",
                    "clipName": clipName,
                    "durationSeconds": String(format: "%.6f", clipInfo.durationSeconds),
                    "importScaleApplied": String(format: "%.6f", importScaleApplied),
                    "importScaleSource": importScaleResolution.source,
                    "associationState": associationState,
                    "clipCanonicalJointCountAfterRemap": String(remapResult.diagnostics.mappedChannels > 0 ? targetSkeletonJointCount : canonicalJointCount),
                    "targetSkeletonJointCount": String(targetSkeletonJointCount)
                ]
                if let resolvedSkeletonHandle {
                    importSettings["skeletonHandle"] = resolvedSkeletonHandle.rawValue.uuidString
                }
                if !associationReason.isEmpty {
                    importSettings["associationReason"] = associationReason
                }

                let clipRelativePath = PathUtils.relativePath(from: rootURL, to: clipURL) ?? clipURL.lastPathComponent
                let clipMeta = AssetMetadata(
                    handle: clipHandle,
                    type: .animationClip,
                    sourcePath: clipRelativePath,
                    importSettings: importSettings,
                    dependencies: resolvedSkeletonHandle.map { [$0] } ?? [],
                    lastModified: Date().timeIntervalSince1970
                )
                projectManager.saveMetadata(clipMeta, to: AssetIO.metaURL(for: clipURL))
                clipHandles.append(clipHandle)
                writtenPaths.append(clipRelativePath)
#if DEBUG
                EngineLoggerContext.log(
                    "FBX animation-only clip write source=\(sourceURL.lastPathComponent) clip=\(clipName) path=\(clipRelativePath)",
                    level: .debug,
                    category: .assets
                )
#endif
            }

#if DEBUG
            if !unresolvedReasons.isEmpty {
                EngineLoggerContext.log(
                    "FBX animation import unresolved skeleton association:\n" + unresolvedReasons.joined(separator: "\n"),
                    level: .warning,
                    category: .assets
                )
            }
            let outputPathSummary = writtenPaths.map { path in
                let status = preExistingClipPaths.contains(path) ? "overwrite" : "new"
                return "\(status):\(path)"
            }.joined(separator: "\n")
            EngineLoggerContext.log(
                "FBX animation-only import summary source=\(sourceURL.path)\noutputPolicy=\(isUnderRoot(sourceURL, rootURL: rootURL) ? "sourceFolder" : "defaultResolverFolders")\nclipRoot=\(clipRoot.path)\nclipCount=\(clipHandles.count)\nresolvedSkeleton=\(resolvedSkeletonHandle?.rawValue.uuidString ?? "<none>")\nskeletonResolutionSource=\(skeletonResolutionSource)\ncanonicalJointCount=\(canonicalJointCount)\ntargetSkeletonJointCount=\(targetSkeletonJointCount)\nclipCanonicalJointCountAfterRemap=\(targetSkeletonJointCount > 0 ? targetSkeletonJointCount : canonicalJointCount)\nremappedAnimationChannels=\(remapResult.diagnostics.mappedChannels)/\(remapResult.diagnostics.totalChannels)\nunmappedAnimationChannels=\(remapResult.diagnostics.unmappedChannelNames.count)\nunmappedAnimationChannelNames=\(remapResult.diagnostics.unmappedChannelNames.prefix(8).joined(separator: ", "))\nimportScaleApplied=\(String(format: "%.6f", importScaleApplied))\nimportScaleSource=\(importScaleResolution.source)\ngeneratedOutputs=\n\(outputPathSummary)",
                level: .debug,
                category: .assets
            )
#endif

            guard let primary = clipHandles.first else { return false }
            commitResult = ImportCommitResult(
                primaryHandle: primary,
                writtenPaths: writtenPaths,
                dependencyHandles: (resolvedSkeletonHandle.map { [$0] } ?? []) + clipHandles,
                meshPath: nil,
                skeletonHandle: resolvedSkeletonHandle,
                defaultClipHandle: clipHandles.first,
                submeshMaterialHandles: []
            )
            return true
        }

        return ok ? commitResult : nil
    }

    private static func compatibleSkeletonCandidates(metadataSnapshot: [AssetMetadata],
                                                     rootURL: URL,
                                                     sourceFolderPath: String,
                                                     sourceSkeleton: MeshSkeletonScanInfo?,
                                                     clipInfos: [MeshAnimationClipScanInfo]) -> [SkeletonAssociationCandidate] {
        var candidates: [SkeletonAssociationCandidate] = []
        for meta in metadataSnapshot where meta.type == .skeleton {
            guard let skeleton = loadSkeletonAsset(handle: meta.handle, metadataSnapshot: metadataSnapshot, rootURL: rootURL) else { continue }
            guard let compatibilityScore = skeletonCompatibilityScore(source: sourceSkeleton, clipInfos: clipInfos, candidate: skeleton) else { continue }
            var score = compatibilityScore
            let assetURL = rootURL.appendingPathComponent(meta.sourcePath).standardizedFileURL
            if assetURL.deletingLastPathComponent().path == sourceFolderPath {
                score += 0.05
            }
            candidates.append(SkeletonAssociationCandidate(metadata: meta, score: score))
        }
        candidates.sort { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.metadata.handle.rawValue.uuidString < rhs.metadata.handle.rawValue.uuidString
            }
            return lhs.score > rhs.score
        }
        return candidates
    }

    private static func resolveSameFolderSkeleton(metadataSnapshot: [AssetMetadata],
                                                  rootURL: URL,
                                                  sourceFolderURL: URL) -> SameFolderSkeletonResolution {
        let candidates: [AssetMetadata] = metadataSnapshot.filter { meta in
            guard meta.type == .skeleton else { return false }
            guard meta.sourcePath.lowercased().hasSuffix(".mcskeleton") else { return false }
            let skeletonURL = rootURL.appendingPathComponent(meta.sourcePath).standardizedFileURL
            return skeletonURL.deletingLastPathComponent() == sourceFolderURL
        }
        if candidates.count == 1, let first = candidates.first {
            return SameFolderSkeletonResolution(
                handle: first.handle,
                skeletonPath: first.sourcePath,
                source: "sameFolderSkeleton",
                isAmbiguous: false
            )
        }
        if candidates.count > 1 {
            return SameFolderSkeletonResolution(
                handle: nil,
                skeletonPath: nil,
                source: "sameFolderSkeletonAmbiguous",
                isAmbiguous: true
            )
        }
        return SameFolderSkeletonResolution(
            handle: nil,
            skeletonPath: nil,
            source: "none",
            isAmbiguous: false
        )
    }

    private static func skeletonImportScale(handle: AssetHandle,
                                            metadataSnapshot: [AssetMetadata]) -> Float? {
        guard let skeletonMeta = metadataSnapshot.first(where: { $0.type == .skeleton && $0.handle == handle }) else {
            return nil
        }
        let value = parseScale(skeletonMeta.importSettings["importScaleApplied"])
        return value.isFinite && value > 0 ? value : nil
    }

    private static func resolveSkeletonFromImportedMeshMetadata(metadataSnapshot: [AssetMetadata],
                                                                rootURL: URL,
                                                                sourceFolderPath: String,
                                                                sourceSkeleton: MeshSkeletonScanInfo?,
                                                                clipInfos: [MeshAnimationClipScanInfo]) -> AssetHandle? {
        let meshMetas = metadataSnapshot.filter { meta in
            guard meta.type == .model else { return false }
            guard meta.importSettings["importer"] == "FbxImporter" else { return false }
            guard let rawSkeleton = meta.importSettings["skeletonHandle"], UUID(uuidString: rawSkeleton) != nil else { return false }
            let assetFolder = rootURL.appendingPathComponent(meta.sourcePath).standardizedFileURL.deletingLastPathComponent().path
            return assetFolder == sourceFolderPath
        }

        var ranked: [(handle: AssetHandle, score: Float)] = []
        for meta in meshMetas {
            guard let rawSkeleton = meta.importSettings["skeletonHandle"],
                  let skeletonUUID = UUID(uuidString: rawSkeleton) else { continue }
            let skeletonHandle = AssetHandle(rawValue: skeletonUUID)
            guard let skeleton = loadSkeletonAsset(handle: skeletonHandle, metadataSnapshot: metadataSnapshot, rootURL: rootURL) else { continue }
            guard let score = skeletonCompatibilityScore(source: sourceSkeleton, clipInfos: clipInfos, candidate: skeleton) else { continue }
            ranked.append((handle: skeletonHandle, score: score))
        }
        ranked.sort { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.handle.rawValue.uuidString < rhs.handle.rawValue.uuidString
            }
            return lhs.score > rhs.score
        }
        guard let best = ranked.first else { return nil }
        if ranked.count == 1 {
            return best.handle
        }
        guard let second = ranked.dropFirst().first else { return best.handle }
        return (best.score - second.score) >= 0.05 ? best.handle : nil
    }

    private static func remapClipInfosToSkeleton(clipInfos: [MeshAnimationClipScanInfo],
                                                 sourceSkeleton: MeshSkeletonScanInfo?,
                                                 targetSkeleton: SkeletonAsset?) -> (clips: [MeshAnimationClipScanInfo], diagnostics: ClipRemapDiagnostics) {
        guard let sourceSkeleton, let targetSkeleton else {
            let totalChannels = clipInfos.reduce(0) { $0 + $1.tracks.count }
            return (
                clipInfos,
                ClipRemapDiagnostics(totalChannels: totalChannels, mappedChannels: totalChannels, unmappedChannelNames: [])
            )
        }

        var targetIndexByName: [String: Int] = [:]
        var targetIndicesByCanonicalName: [String: [Int]] = [:]
        targetIndexByName.reserveCapacity(targetSkeleton.joints.count)
        targetIndicesByCanonicalName.reserveCapacity(targetSkeleton.joints.count)
        for (index, joint) in targetSkeleton.joints.enumerated() {
            if targetIndexByName[joint.name] == nil {
                targetIndexByName[joint.name] = index
            }
            let canonical = canonicalJointName(joint.name)
            guard !canonical.isEmpty else { continue }
            targetIndicesByCanonicalName[canonical, default: []].append(index)
        }
        var remappedClips: [MeshAnimationClipScanInfo] = []
        remappedClips.reserveCapacity(clipInfos.count)
        var totalChannels = 0
        var mappedChannels = 0
        var unmappedChannelNames = Set<String>()

        for clip in clipInfos {
            var remappedTracks: [AnimationClipAsset.JointTrack] = []
            remappedTracks.reserveCapacity(clip.tracks.count)
            for track in clip.tracks {
                totalChannels += 1
                guard track.jointIndex >= 0, track.jointIndex < sourceSkeleton.joints.count else { continue }
                let sourceJointName = sourceSkeleton.joints[track.jointIndex].name
                let canonicalSourceJointName = canonicalJointName(sourceJointName)
                let canonicalMatches = targetIndicesByCanonicalName[canonicalSourceJointName] ?? []
                let canonicalResolved = canonicalMatches.count == 1 ? canonicalMatches[0] : nil
                guard let targetJointIndex = targetIndexByName[sourceJointName] ?? canonicalResolved else {
                    if !sourceJointName.isEmpty {
                        unmappedChannelNames.insert(sourceJointName)
                    }
                    continue
                }
                mappedChannels += 1
                remappedTracks.append(
                    AnimationClipAsset.JointTrack(
                        jointIndex: targetJointIndex,
                        translations: track.translations,
                        rotations: track.rotations,
                        scales: track.scales
                    )
                )
            }
            remappedClips.append(
                MeshAnimationClipScanInfo(
                    name: clip.name,
                    durationSeconds: clip.durationSeconds,
                    tracks: remappedTracks
                )
            )
        }

        return (
            remappedClips,
            ClipRemapDiagnostics(
                totalChannels: totalChannels,
                mappedChannels: mappedChannels,
                unmappedChannelNames: Array(unmappedChannelNames).sorted()
            )
        )
    }

    private static func loadSkeletonAsset(handle: AssetHandle,
                                          metadataSnapshot: [AssetMetadata],
                                          rootURL: URL) -> SkeletonAsset? {
        guard let skeletonMeta = metadataSnapshot.first(where: { $0.type == .skeleton && $0.handle == handle }) else { return nil }
        let skeletonURL = rootURL.appendingPathComponent(skeletonMeta.sourcePath).standardizedFileURL
        return SkeletonAssetSerializer.load(from: skeletonURL, fallbackHandle: handle)
    }

    private static func skeletonCompatibilityScore(source: MeshSkeletonScanInfo?,
                                                   clipInfos: [MeshAnimationClipScanInfo],
                                                   candidate: SkeletonAsset) -> Float? {
        guard let source else { return nil }
        let sourceTrackJointIndices = Set(clipInfos.flatMap { $0.tracks.map(\.jointIndex) })
        let sourceHierarchy = canonicalHierarchyEntries(from: source.joints, restrictedTo: sourceTrackJointIndices)
        guard !sourceHierarchy.isEmpty else { return nil }
        let candidateHierarchy = canonicalHierarchyEntries(from: candidate.joints, restrictedTo: nil)
        guard !candidateHierarchy.isEmpty else { return nil }

        var mappedCount = 0
        var parentMatchedCount = 0
        for (jointName, sourceParentName) in sourceHierarchy {
            guard let candidateParentName = candidateHierarchy[jointName] else { continue }
            mappedCount += 1
            if sourceParentName == candidateParentName {
                parentMatchedCount += 1
            }
        }

        let coverage = Float(mappedCount) / Float(max(1, sourceHierarchy.count))
        guard coverage >= 0.8 else { return nil }
        let parentAgreement = mappedCount > 0 ? (Float(parentMatchedCount) / Float(mappedCount)) : 0
        return (coverage * 0.85) + (parentAgreement * 0.15)
    }

    private static func canonicalHierarchyEntries(from joints: [SkeletonAsset.Joint],
                                                  restrictedTo restrictedIndices: Set<Int>?) -> [String: String] {
        var map: [String: String] = [:]
        map.reserveCapacity(joints.count)
        for (index, joint) in joints.enumerated() {
            if let restrictedIndices, !restrictedIndices.contains(index) {
                continue
            }
            let canonicalName = canonicalJointName(joint.name)
            guard !canonicalName.isEmpty else { continue }
            if map[canonicalName] != nil { continue }

            let canonicalParent: String
            if joint.parentIndex >= 0, joint.parentIndex < joints.count {
                canonicalParent = canonicalJointName(joints[joint.parentIndex].name)
            } else {
                canonicalParent = ""
            }
            map[canonicalName] = canonicalParent
        }
        return map
    }
}

private func commitSourceAsset(scan: ImportScanResult,
                               settings: ImportSettings,
                               projectManager: EditorProjectManager,
                               resolver: AssetPathResolver,
                               assetType: AssetType,
                               importerId: String,
                               importerVersion: String) -> ImportCommitResult? {
    guard let assetsRoot = projectManager.assetRootURL() else { return nil }
    guard let destinationFolder = resolver.destinationFolder(for: assetType) else { return nil }

    let sourceURL = scan.sourceURL.standardizedFileURL
    let sourceRelativePath = PathUtils.relativePath(from: assetsRoot, to: sourceURL) ?? sourceURL.lastPathComponent
    let sourcePathAbs = sourceURL.path
    let ext = sourceURL.pathExtension
    guard var destinationURL = resolver.destinationURL(for: assetType, suggestedName: scan.suggestedName, ext: ext) else { return nil }

    var existingHandle: AssetHandle?
    if let existingMeta = projectManager.metadataForSourcePathAbs(sourcePathAbs),
       existingMeta.type == assetType {
        let existingURL = assetsRoot.appendingPathComponent(existingMeta.sourcePath)
        destinationURL = existingURL
        existingHandle = existingMeta.handle
    }

    if sourceURL.deletingLastPathComponent().standardizedFileURL == destinationFolder.standardizedFileURL {
        destinationURL = sourceURL
    }

    var commitResult: ImportCommitResult?
    let ok = projectManager.performAssetMutation {
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        let sourceMetaURL = AssetIO.metaURL(for: sourceURL)
        let destinationMetaURL = AssetIO.metaURL(for: destinationURL)
        let existingHandle = existingHandle ?? loadHandle(from: sourceMetaURL) ?? loadHandle(from: destinationMetaURL)

        if destinationURL != sourceURL {
            if isUnderRoot(sourceURL, rootURL: assetsRoot) {
                try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
                if FileManager.default.fileExists(atPath: sourceMetaURL.path),
                   sourceMetaURL.path != destinationMetaURL.path {
                    try? FileManager.default.moveItem(at: sourceMetaURL, to: destinationMetaURL)
                }
            } else {
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                if FileManager.default.fileExists(atPath: sourceMetaURL.path),
                   sourceMetaURL.path != destinationMetaURL.path {
                    try? FileManager.default.copyItem(at: sourceMetaURL, to: destinationMetaURL)
                }
            }
        }

        let handle = existingHandle ?? AssetHandle()
        let destinationRelativePath = PathUtils.relativePath(from: assetsRoot, to: destinationURL) ?? destinationURL.lastPathComponent
        let metaURL = projectManager.metaURLForAsset(assetURL: destinationURL, relativePath: destinationRelativePath) ?? destinationMetaURL

        var importSettings = settings.values
        importSettings["importer"] = importerId
        importSettings["importerVersion"] = importerVersion
        importSettings["sourcePath"] = sourceRelativePath
        importSettings["sourcePathAbs"] = sourcePathAbs
        importSettings["importFailed"] = "false"
        importSettings.removeValue(forKey: "importFailureReason")
        importSettings.removeValue(forKey: "importFailureAt")

        let metadata = AssetMetadata(
            handle: handle,
            type: assetType,
            sourcePath: destinationRelativePath,
            importSettings: importSettings,
            dependencies: [],
            lastModified: Date().timeIntervalSince1970
        )
        projectManager.saveMetadata(metadata, to: metaURL)

        commitResult = ImportCommitResult(
            primaryHandle: handle,
            writtenPaths: [destinationRelativePath],
            dependencyHandles: [],
            meshPath: destinationRelativePath,
            skeletonHandle: nil,
            defaultClipHandle: nil,
            submeshMaterialHandles: []
        )
        return true
    }

    return ok ? commitResult : nil
}

private func loadHandle(from metaURL: URL) -> AssetHandle? {
    guard let data = try? Data(contentsOf: metaURL) else { return nil }
    guard let metadata = try? JSONDecoder().decode(AssetMetadata.self, from: data) else { return nil }
    return metadata.handle
}

private func isUnderRoot(_ url: URL, rootURL: URL) -> Bool {
    let rootPath = rootURL.standardizedFileURL.path
    let targetPath = url.standardizedFileURL.path
    return targetPath == rootPath || targetPath.hasPrefix(rootPath + "/")
}

private func meshSanitizeFileName(_ name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|")
    let sanitized = trimmed.components(separatedBy: invalid).joined(separator: "_")
    return sanitized.isEmpty ? "Asset" : sanitized
}

private func meshUniqueFileURL(in folder: URL, baseName: String, ext: String) -> URL {
    let fm = FileManager.default
    let trimmedExt = ext.trimmingCharacters(in: .whitespacesAndNewlines)
    let suffix = trimmedExt.isEmpty ? "" : ".\(trimmedExt)"
    var candidate = folder.appendingPathComponent(baseName + suffix)
    if !fm.fileExists(atPath: candidate.path) { return candidate }
    var index = 1
    while true {
        let name = "\(baseName)_\(index)"
        candidate = folder.appendingPathComponent(name + suffix)
        if !fm.fileExists(atPath: candidate.path) { return candidate }
        index += 1
    }
}

final class ImportController {
    private let projectManager: EditorProjectManager
    private let logCenter: EngineLogger
    private let importers: [any AssetImporter] = [TextureImporter(), EnvironmentImporter(), FbxImporter(), MeshImporter()]

    private(set) var isOpen: Bool = false
    private(set) var scanResult: ImportScanResult?
    private(set) var settings: ImportSettings = ImportSettings(values: [:])
    private(set) var lastErrorMessage: String = ""
    private(set) var commitResult: ImportCommitResult?
    private(set) var commitAssetType: AssetType = .unknown
    private(set) var isReimport: Bool = false

    private var importer: (any AssetImporter)?

    init(projectManager: EditorProjectManager, logCenter: EngineLogger) {
        self.projectManager = projectManager
        self.logCenter = logCenter
    }

    func beginImport(handle: AssetHandle) -> Bool {
        if isOpen { return false }
        guard let rootURL = projectManager.assetRootURL() else { return false }
        guard let assetURL = projectManager.assetURL(for: handle) else { return false }
        guard let metadata = projectManager.assetMetadataSnapshot().first(where: { $0.handle == handle }) else { return false }
        guard shouldImport(metadata: metadata) else { return false }

        let sourcePathAbs = metadata.importSettings["sourcePathAbs"]
        var sourceURL = assetURL
        if let sourcePathAbs, !sourcePathAbs.isEmpty {
            let candidate = URL(fileURLWithPath: sourcePathAbs)
            if FileManager.default.fileExists(atPath: candidate.path) {
                sourceURL = candidate
            }
        }

        guard let selectedImporter = importerFor(url: sourceURL) else { return false }
        guard let scan = selectedImporter.scan(sourceURL) else { return false }

        let resolver = AssetPathResolver(assetsRootURL: rootURL)
        guard resolver.destinationFolder(for: scan.assetType) != nil else { return false }

        self.importer = selectedImporter
        self.scanResult = scan
        let defaults = selectedImporter.defaultSettings(for: scan)
        self.settings = settingsFromMetadata(metadata, defaults: defaults, assetType: scan.assetType)
        if let sourcePathAbs, !sourcePathAbs.isEmpty {
            self.settings.values["sourcePathAbs"] = sourcePathAbs
        }
        self.commitResult = nil
        self.commitAssetType = scan.assetType
        self.lastErrorMessage = ""
        self.isOpen = true
        self.isReimport = isReimportable(metadata: metadata)
        return true
    }

    func cancel() {
        isOpen = false
        scanResult = nil
        importer = nil
        commitResult = nil
        lastErrorMessage = ""
        isReimport = false
    }

    func commit() -> Bool {
        guard let scan = scanResult,
              let importer,
              let rootURL = projectManager.assetRootURL() else { return false }
        let resolver = AssetPathResolver(assetsRootURL: rootURL)
        if let result = importer.commit(scan: scan,
                                        settings: settings,
                                        projectManager: projectManager,
                                        resolver: resolver) {
            commitResult = result
            commitAssetType = scan.assetType
            isOpen = false
            scanResult = nil
            isReimport = false
#if DEBUG
            if scan.sourceURL.lastPathComponent.lowercased().contains("damagedhelmet"),
               let meshInfo = scan.meshInfo {
                var lines: [String] = []
                for material in meshInfo.materials {
                    for texture in material.textures.values {
                        let srgb = (texture.semantic == .baseColor || texture.semantic == .emissive) ? "sRGB" : "Linear"
                        lines.append("  \(material.name) - \(texture.semantic.rawValue): \(texture.name) [\(srgb)]")
                    }
                }
                logCenter.logDebug(
                    "DamagedHelmet import textures:\n" + lines.joined(separator: "\n"),
                    category: .assets
                )
            }
#endif
            logCenter.logInfo("Imported asset: \(result.writtenPaths.first ?? scan.sourceURL.lastPathComponent)", category: .assets)
            return true
        }
        if scan.assetType == .texture {
            if let rootURL = projectManager.assetRootURL(),
               isUnderRoot(scan.sourceURL.standardizedFileURL, rootURL: rootURL),
               let relativePath = PathUtils.relativePath(from: rootURL, to: scan.sourceURL.standardizedFileURL),
               let failedMeta = projectManager.assetMetadataSnapshot().first(where: { $0.sourcePath == relativePath }),
               let reason = failedMeta.importSettings["importFailureReason"],
               !reason.isEmpty {
                lastErrorMessage = "Texture import failed: \(reason)"
            } else {
                setTextureFailureState(
                    projectManager: projectManager,
                    scan: scan,
                    settings: settings,
                    importerId: importer.importerId,
                    importerVersion: importer.importerVersion,
                    reason: "write: commit failed before metadata write"
                )
                lastErrorMessage = "Texture import failed: write: commit failed before metadata write"
            }
        } else {
            lastErrorMessage = "Import failed."
        }
        return false
    }

    func sourceFilename() -> String {
        scanResult?.sourceURL.lastPathComponent ?? ""
    }

    func assetType() -> AssetType {
        scanResult?.assetType ?? .unknown
    }

    func destinationFolderName() -> String {
        guard let scan = scanResult, let rootURL = projectManager.assetRootURL() else { return "" }
        let resolver = AssetPathResolver(assetsRootURL: rootURL)
        guard let folder = resolver.destinationFolder(for: scan.assetType) else { return "" }
        return folder.lastPathComponent
    }

    func optionBool(_ key: String, default defaultValue: Bool) -> Bool {
        settings.boolValue(key, default: defaultValue)
    }

    func setOptionBool(_ key: String, value: Bool) {
        settings.values[key] = value ? "true" : "false"
    }

    func optionString(_ key: String) -> String {
        settings.values[key] ?? ""
    }

    func setOptionString(_ key: String, value: String) {
        settings.values[key] = value
    }

    func optionFloat(_ key: String, default defaultValue: Float) -> Float {
        guard let raw = settings.values[key], let value = Float(raw) else { return defaultValue }
        return value
    }

    func setOptionFloat(_ key: String, value: Float) {
        settings.values[key] = String(format: "%.3f", value)
    }

    func meshCount() -> Int {
        scanResult?.meshInfo?.meshCount ?? 0
    }

    func submeshCount() -> Int {
        scanResult?.meshInfo?.submeshCount ?? 0
    }

    func materialCount() -> Int {
        scanResult?.meshInfo?.materialNames.count ?? 0
    }

    func materialName(at index: Int) -> String {
        guard let list = scanResult?.meshInfo?.materialNames, index >= 0, index < list.count else { return "" }
        return list[index]
    }

    func textureCount() -> Int {
        scanResult?.meshInfo?.textureNames.count ?? 0
    }

    func textureName(at index: Int) -> String {
        guard let list = scanResult?.meshInfo?.textureNames, index >= 0, index < list.count else { return "" }
        return list[index]
    }

    func warningCount() -> Int {
        scanResult?.meshInfo?.warnings.count ?? 0
    }

    func warning(at index: Int) -> String {
        guard let list = scanResult?.meshInfo?.warnings, index >= 0, index < list.count else { return "" }
        return list[index]
    }

    func hasUVs() -> Bool {
        scanResult?.meshInfo?.hasUVs ?? false
    }

    func hasNormals() -> Bool {
        scanResult?.meshInfo?.hasNormals ?? false
    }

    func hasTangents() -> Bool {
        scanResult?.meshInfo?.hasTangents ?? false
    }

    func consumeCommitResult() -> ImportCommitResult? {
        let result = commitResult
        commitResult = nil
        return result
    }

    func clearCommitResult() {
        commitResult = nil
    }

    private func importerFor(url: URL) -> (any AssetImporter)? {
        for importer in importers where importer.canImport(url) {
            return importer
        }
        return nil
    }

    private func shouldImport(metadata: AssetMetadata) -> Bool {
        if metadata.type == .material || metadata.type == .prefab || metadata.type == .scene {
            return false
        }
        if metadata.importSettings["importer"] != nil {
            return isReimportable(metadata: metadata)
        }
        return true
    }

    private func isReimportable(metadata: AssetMetadata) -> Bool {
        if metadata.type == .texture || metadata.type == .environment || metadata.type == .model {
            return !(metadata.importSettings["sourcePathAbs"] ?? "").isEmpty
        }
        return false
    }

    private func settingsFromMetadata(_ metadata: AssetMetadata,
                                      defaults: ImportSettings,
                                      assetType: AssetType) -> ImportSettings {
        var values = defaults.values
        let allowedKeys: Set<String>
        switch assetType {
        case .texture:
            allowedKeys = ["srgb", "mipmaps", "semantic"]
        case .environment:
            allowedKeys = []
        case .model:
            allowedKeys = [
                "importMaterials", "importTextures", "copyTextures",
                "flipNormalY", "generateTangents", "scale",
                "combineORM", "createPrefab", "createHierarchy"
            ]
        default:
            allowedKeys = []
        }
        for (key, value) in metadata.importSettings where allowedKeys.contains(key) {
            values[key] = value
        }
        return ImportSettings(values: values)
    }
}
