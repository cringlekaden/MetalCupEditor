/// AssetOps.swift
/// Defines asset file operations for the editor.
/// Created by Kaden Cringle.

import Foundation
import MetalCupEngine

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
        let logCenter = context.editorLogCenter
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
        let logCenter = context.editorLogCenter
        guard let rootURL = projectManager.assetRootURL() else { return false }
        let rel = relativePath ?? ""
        let sceneName = name ?? "Untitled"
        guard let folderURL = resolveDirectoryURL(rootURL: rootURL, relativePath: rel) else { return false }
        let targetURL = folderURL.appendingPathComponent("\(sceneName).mcscene")
        let document = SceneDocument(id: UUID(), name: sceneName, entities: [])
        let scene = SerializedScene(document: document)
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
        let logCenter = context.editorLogCenter
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

    static func createPrefab(context: UnsafeRawPointer?, prefab: PrefabDocument, relativePath: String?, name: String?) -> String? {
        guard let context = resolveContext(context) else { return nil }
        let projectManager = context.editorProjectManager
        let alertCenter = context.editorAlertCenter
        let logCenter = context.editorLogCenter
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
        let logCenter = context.editorLogCenter
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
        let logCenter = context.editorLogCenter
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
        let logCenter = context.editorLogCenter
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
        let logCenter = context.editorLogCenter
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
        let logCenter = context.editorLogCenter
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
        let logCenter = context.editorLogCenter
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
        let logCenter = context.editorLogCenter
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
        let relativePath = materialURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
        guard let metaURL = projectManager.metaURLForAsset(assetURL: materialURL, relativePath: relativePath) else { return }
        let metadata = AssetMetadata(
            handle: handle,
            type: .material,
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
