import Foundation
import MetalCupEngine

enum EditorMaterialLibrary {
    static func createMaterial(named name: String, relativePath: String? = nil) -> AssetHandle? {
        guard let rootURL = EditorProjectManager.shared.assetRootURL() else { return nil }
        let rel = relativePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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
        EditorStatusCenter.shared.enqueueInfo("Saved material: \(baseName)")
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
        EditorStatusCenter.shared.enqueueInfo("Renamed material to: \(sanitized)")
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
        EditorStatusCenter.shared.enqueueInfo("Duplicated material: \(baseName)")
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
        EditorStatusCenter.shared.enqueueInfo("Deleted material.")
        return true
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

    private static func isProjectAssetURL(_ url: URL, rootURL: URL) -> Bool {
        let rootPath = rootURL.standardizedFileURL.path
        let targetPath = url.standardizedFileURL.path
        return targetPath == rootPath || targetPath.hasPrefix(rootPath + "/")
    }
}
