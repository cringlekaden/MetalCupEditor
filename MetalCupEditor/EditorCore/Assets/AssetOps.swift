/// AssetOps.swift
/// Defines asset file operations for the editor.
/// Created by Kaden Cringle.

import Foundation
import MetalCupEngine

enum AssetOps {
    static func createFolder(relativePath: String?, name: String?) -> Bool {
        guard let rootURL = EditorProjectManager.shared.assetRootURL() else { return false }
        let rel = relativePath ?? ""
        let folderName = name ?? "New Folder"
        guard let targetParent = resolveDirectoryURL(rootURL: rootURL, relativePath: rel) else { return false }
        let targetURL = targetParent.appendingPathComponent(folderName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
            EditorProjectManager.shared.refreshAssets()
            EditorLogCenter.shared.logInfo("Created folder: \(folderName)", category: .assets)
            return true
        } catch {
            EditorAlertCenter.shared.enqueueError("Failed to create folder: \(error.localizedDescription)")
            return false
        }
    }

    static func createScene(relativePath: String?, name: String?) -> Bool {
        guard let rootURL = EditorProjectManager.shared.assetRootURL() else { return false }
        let rel = relativePath ?? ""
        let sceneName = name ?? "Untitled"
        guard let folderURL = resolveDirectoryURL(rootURL: rootURL, relativePath: rel) else { return false }
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        } catch {
            EditorAlertCenter.shared.enqueueError("Failed to create scene folder: \(error.localizedDescription)")
            return false
        }
        let targetURL = folderURL.appendingPathComponent("\(sceneName).mcscene")
        let document = SceneDocument(id: UUID(), name: sceneName, entities: [])
        let scene = SerializedScene(document: document)
        do {
            try SceneSerializer.save(scene: scene, to: targetURL)
            EditorProjectManager.shared.refreshAssets()
            EditorLogCenter.shared.logInfo("Created scene: \(sceneName)", category: .scene)
            return true
        } catch {
            EditorAlertCenter.shared.enqueueError("Failed to create scene: \(error.localizedDescription)")
            return false
        }
    }

    static func createPrefab(relativePath: String?, name: String?) -> Bool {
        guard let rootURL = EditorProjectManager.shared.assetRootURL() else { return false }
        let rel = relativePath ?? ""
        let prefabName = name ?? "Prefab"
        guard let folderURL = resolveDirectoryURL(rootURL: rootURL, relativePath: rel) else { return false }
        let targetURL = folderURL.appendingPathComponent("\(prefabName).prefab")
        let stub = "{\n  \"schemaVersion\": 1\n}\n"
        do {
            try stub.data(using: .utf8)?.write(to: targetURL, options: [.atomic])
            EditorProjectManager.shared.refreshAssets()
            EditorLogCenter.shared.logInfo("Created prefab: \(prefabName)", category: .assets)
            return true
        } catch {
            EditorAlertCenter.shared.enqueueError("Failed to create prefab: \(error.localizedDescription)")
            return false
        }
    }

    static func createMaterial(named name: String, relativePath: String? = nil) -> AssetHandle? {
        guard let rootURL = EditorProjectManager.shared.assetRootURL() else { return nil }
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
            EditorAlertCenter.shared.enqueueError("Failed to create material folder: \(error.localizedDescription)")
            return nil
        }

        let baseName = sanitizeName(name.isEmpty ? "Material" : name)
        let materialURL = uniqueFileURL(folder: materialsFolder, baseName: baseName, fileExtension: "mcmat")
        let handle = AssetHandle()
        let material = MaterialAsset.default(handle: handle, name: baseName)
        if !MaterialAssetSerializer.save(material, to: materialURL) {
            EditorAlertCenter.shared.enqueueError("Failed to save material file.")
            return nil
        }

        registerMaterialMetadata(handle: handle, materialURL: materialURL, rootURL: rootURL)
        EditorProjectManager.shared.refreshAssets()
        EditorLogCenter.shared.logInfo("Saved material: \(baseName)", category: .assets)
        return handle
    }

    static func renameMaterial(handle: AssetHandle, newName: String) -> Bool {
        let sanitized = sanitizeName(newName)
        guard !sanitized.isEmpty else { return false }
        guard let rootURL = EditorProjectManager.shared.assetRootURL(),
              let metadata = metadata(for: handle),
              let assetURL = EditorProjectManager.shared.assetURL(for: handle) else { return false }
        guard isProjectAssetURL(assetURL, rootURL: rootURL) else {
            EditorAlertCenter.shared.enqueueError("Shared Assets are read-only.")
            return false
        }

        let newURL = uniqueFileURL(folder: assetURL.deletingLastPathComponent(), baseName: sanitized, fileExtension: "mcmat")
        do {
            try FileManager.default.moveItem(at: assetURL, to: newURL)
        } catch {
            EditorAlertCenter.shared.enqueueError("Failed to rename material: \(error.localizedDescription)")
            return false
        }

        if let material = MaterialAssetSerializer.load(from: newURL, fallbackHandle: handle) {
            var updated = material
            updated.name = sanitized
            _ = MaterialAssetSerializer.save(updated, to: newURL)
        }

        let oldMetaURL = EditorProjectManager.shared.metaURLForAsset(assetURL: assetURL, relativePath: metadata.sourcePath)
        let newRelativePath = newURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
        let newMetaURL = EditorProjectManager.shared.metaURLForAsset(assetURL: newURL, relativePath: newRelativePath)
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
            EditorProjectManager.shared.saveMetadata(updatedMeta, to: newMetaURL)
        }

        EditorProjectManager.shared.refreshAssets()
        EditorLogCenter.shared.logInfo("Renamed material to: \(sanitized)", category: .assets)
        return true
    }

    static func duplicateMaterial(handle: AssetHandle) -> AssetHandle? {
        guard let rootURL = EditorProjectManager.shared.assetRootURL(),
              let assetURL = EditorProjectManager.shared.assetURL(for: handle) else { return nil }
        guard isProjectAssetURL(assetURL, rootURL: rootURL) else {
            EditorAlertCenter.shared.enqueueError("Shared Assets are read-only.")
            return nil
        }
        let baseName = assetURL.deletingPathExtension().lastPathComponent + " Copy"
        let newURL = uniqueFileURL(folder: assetURL.deletingLastPathComponent(), baseName: baseName, fileExtension: "mcmat")
        let newHandle = AssetHandle()
        let material = MaterialAssetSerializer.load(from: assetURL, fallbackHandle: handle)
            ?? MaterialAsset.default(handle: newHandle, name: baseName)
        var duplicate = material
        duplicate.handle = newHandle
        duplicate.name = baseName
        if !MaterialAssetSerializer.save(duplicate, to: newURL) {
            EditorAlertCenter.shared.enqueueError("Failed to duplicate material.")
            return nil
        }
        registerMaterialMetadata(handle: newHandle, materialURL: newURL, rootURL: rootURL)
        EditorProjectManager.shared.refreshAssets()
        EditorLogCenter.shared.logInfo("Duplicated material: \(baseName)", category: .assets)
        return newHandle
    }

    static func deleteMaterial(handle: AssetHandle) -> Bool {
        guard let metadata = metadata(for: handle),
              let assetURL = EditorProjectManager.shared.assetURL(for: handle) else { return false }
        if let rootURL = EditorProjectManager.shared.assetRootURL(),
           !isProjectAssetURL(assetURL, rootURL: rootURL) {
            EditorAlertCenter.shared.enqueueError("Shared Assets are read-only.")
            return false
        }
        do {
            try FileManager.default.removeItem(at: assetURL)
        } catch {
            EditorAlertCenter.shared.enqueueError("Failed to delete material: \(error.localizedDescription)")
            return false
        }
        if let metaURL = EditorProjectManager.shared.metaURLForAsset(assetURL: assetURL, relativePath: metadata.sourcePath) {
            try? FileManager.default.removeItem(at: metaURL)
        }
        EditorProjectManager.shared.refreshAssets()
        EditorLogCenter.shared.logInfo("Deleted material.", category: .assets)
        return true
    }

    static func renameAsset(relativePath: String, newName: String) -> URL? {
        guard let rootURL = EditorProjectManager.shared.assetRootURL() else { return nil }
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

        let ok = EditorProjectManager.shared.performAssetMutation {
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
        EditorLogCenter.shared.logInfo("Renamed asset: \(relativePath) -> \(newURL.lastPathComponent)", category: .assets)
        return newURL
    }

    static func deleteAsset(relativePath: String) -> Bool {
        guard let rootURL = EditorProjectManager.shared.assetRootURL() else { return false }
        guard let assetURL = resolveAssetURL(rootURL: rootURL, relativePath: relativePath) else { return false }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: assetURL.path, isDirectory: &isDirectory) else { return false }

        let ok = EditorProjectManager.shared.performAssetMutation {
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
            EditorLogCenter.shared.logInfo("Deleted asset: \(relativePath)", category: .assets)
            return true
        }
        return false
    }

    static func duplicateAsset(relativePath: String) -> URL? {
        guard let rootURL = EditorProjectManager.shared.assetRootURL() else { return nil }
        guard let assetURL = resolveAssetURL(rootURL: rootURL, relativePath: relativePath) else { return nil }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: assetURL.path, isDirectory: &isDirectory) else { return nil }
        guard !isDirectory.boolValue else { return nil }

        let baseName = assetURL.deletingPathExtension().lastPathComponent
        let ext = assetURL.pathExtension
        if ext.lowercased() == "mcmat" { return nil }

        let newURL = uniqueCopyURL(folder: assetURL.deletingLastPathComponent(), baseName: baseName, fileExtension: ext)
        let ok = EditorProjectManager.shared.performAssetMutation {
            try FileManager.default.copyItem(at: assetURL, to: newURL)
            AssetIO.updateSceneNameIfNeeded(url: newURL, newName: newURL.deletingPathExtension().lastPathComponent)
            return true
        }

        guard ok else { return nil }
        EditorLogCenter.shared.logInfo("Duplicated asset: \(relativePath)", category: .assets)
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

    private static func registerMaterialMetadata(handle: AssetHandle, materialURL: URL, rootURL: URL) {
        let relativePath = materialURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
        guard let metaURL = EditorProjectManager.shared.metaURLForAsset(assetURL: materialURL, relativePath: relativePath) else { return }
        let metadata = AssetMetadata(
            handle: handle,
            type: .material,
            sourcePath: relativePath,
            importSettings: [:],
            dependencies: [],
            lastModified: Date().timeIntervalSince1970
        )
        EditorProjectManager.shared.saveMetadata(metadata, to: metaURL)
    }

    private static func metadata(for handle: AssetHandle) -> AssetMetadata? {
        let snapshot = EditorProjectManager.shared.assetMetadataSnapshot()
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
