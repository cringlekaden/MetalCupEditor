/// AssetOps.swift
/// Defines asset file operations for the editor.
/// Created by Kaden Cringle.

import Foundation
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
    let warnings: [String]
    let materials: [MeshScanMaterial]
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
        let srgb = AssetManager.isColorTexture(path: url.lastPathComponent) ? "true" : "false"
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
        let srgb = AssetManager.isColorTexture(path: name)
        let mipmaps = AssetManager.shouldGenerateMipmaps(path: name)
        var values: [String: String] = [
            "srgb": srgb ? "true" : "false",
            "mipmaps": mipmaps ? "true" : "false"
        ]
        let semantic = guessTextureSemantic(from: scan.suggestedName)
        if !semantic.isEmpty {
            values["semantic"] = semantic
        }
        return ImportSettings(values: values)
    }

    func commit(scan: ImportScanResult,
                settings: ImportSettings,
                projectManager: EditorProjectManager,
                resolver: AssetPathResolver) -> ImportCommitResult? {
        commitSourceAsset(scan: scan,
                          settings: settings,
                          projectManager: projectManager,
                          resolver: resolver,
                          assetType: .texture,
                          importerId: importerId,
                          importerVersion: importerVersion)
    }

    private func guessTextureSemantic(from name: String) -> String {
        let lowered = name.lowercased()
        if lowered.contains("normal") { return "normal" }
        if lowered.contains("rough") { return "roughness" }
        if lowered.contains("metal") { return "metallic" }
        if lowered.contains("ao") || lowered.contains("occlusion") { return "occlusion" }
        if lowered.contains("height") || lowered.contains("displace") { return "height" }
        if lowered.contains("emissive") { return "emissive" }
        if lowered.contains("orm") || (lowered.contains("occlusion") && lowered.contains("rough") && lowered.contains("metal")) { return "orm" }
        if lowered.contains("albedo") || lowered.contains("basecolor") || lowered.contains("diff") { return "albedo" }
        return ""
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
        ImportSettings(values: [:])
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

extension MeshImporter {
    private static func scanMesh(url: URL, suggestedName: String) -> ImportScanResult? {
        let asset = MDLAsset(url: url)
        asset.loadTextures()
        let meshes = (asset.childObjects(of: MDLMesh.self) as? [MDLMesh]) ?? []
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
            alphaMode = .masked
        } else if opacity < 0.99 {
            alphaMode = .blended
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

    private static func exportEmbeddedTexture(_ texture: MDLTexture, to url: URL) -> Bool {
        let folder = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            try texture.write(to: url)
            return true
        } catch {
            return false
        }
    }

    private static func commitMesh(scan: ImportScanResult,
                                   settings: ImportSettings,
                                   projectManager: EditorProjectManager,
                                   resolver: AssetPathResolver,
                                   importerId: String,
                                   importerVersion: String) -> ImportCommitResult? {
        guard let rootURL = projectManager.assetRootURL() else { return nil }
        guard let meshInfo = scan.meshInfo else { return nil }
        guard let meshRoot = resolver.destinationFolder(for: .model) else { return nil }
        var meshFolder = uniqueFolderURL(in: meshRoot, baseName: scan.suggestedName)

        let texturesRoot = resolver.destinationFolder(for: .texture) ?? rootURL.appendingPathComponent("Textures", isDirectory: true)
        let materialsRoot = resolver.destinationFolder(for: .material) ?? rootURL.appendingPathComponent("Materials", isDirectory: true)
        let environmentsRoot = resolver.destinationFolder(for: .environment) ?? rootURL.appendingPathComponent("Environments", isDirectory: true)
        var texturesFolder = texturesRoot.appendingPathComponent(meshFolder.lastPathComponent, isDirectory: true)
        var materialsFolder = materialsRoot.appendingPathComponent(meshFolder.lastPathComponent, isDirectory: true)

        let sourceURL = scan.sourceURL.standardizedFileURL
        let sourceRelativePath = PathUtils.relativePath(from: rootURL, to: sourceURL) ?? sourceURL.lastPathComponent
        var sourcePathAbs = sourceURL.path
        let sourceExt = sourceURL.pathExtension.lowercased()
        let textureOrigin = (sourceExt == "usdz") ? "bottomLeft" : "topLeft"

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

        var commitResult: ImportCommitResult?
        let ok = projectManager.performAssetMutation {
            if let reimportMeshMeta {
                let existingMeshURL = rootURL.appendingPathComponent(reimportMeshMeta.sourcePath)
                meshFolder = existingMeshURL.deletingLastPathComponent()
                texturesFolder = texturesRoot.appendingPathComponent(meshFolder.lastPathComponent, isDirectory: true)
                materialsFolder = materialsRoot.appendingPathComponent(meshFolder.lastPathComponent, isDirectory: true)
            }
            try FileManager.default.createDirectory(at: meshFolder, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: texturesFolder, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: materialsFolder, withIntermediateDirectories: true)

            let sourceFileName = sourceURL.lastPathComponent
            let meshDestinationURL = reimportMeshMeta != nil
                ? rootURL.appendingPathComponent(reimportMeshMeta!.sourcePath)
                : meshFolder.appendingPathComponent(sourceFileName)
            let meshMetaURL = AssetIO.metaURL(for: meshDestinationURL)
            let sourceMetaURL = AssetIO.metaURL(for: sourceURL)

            let existingMeshHandle = reimportMeshMeta?.handle ?? loadHandle(from: sourceMetaURL) ?? loadHandle(from: meshMetaURL)

            if meshDestinationURL.standardizedFileURL.path != sourceURL.standardizedFileURL.path {
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
            let meshSourceKey = sourcePathAbs
            for meta in metadataSnapshot {
                if let abs = meta.importSettings["sourcePathAbs"], !abs.isEmpty {
                    existingBySourceAbs[abs] = meta
                }
                if meta.type == .material,
                   let meshSource = meta.importSettings["meshSourcePathAbs"],
                   let materialName = meta.importSettings["meshMaterialName"],
                   !meshSource.isEmpty,
                   meshSource == meshSourceKey {
                    let key = "\(meshSource)|\(materialName)"
                    existingMaterialsByKey[key] = meta
                }
                if (meta.type == .texture || meta.type == .environment),
                   let meshSource = meta.importSettings["meshSourcePathAbs"],
                   let semantic = meta.importSettings["meshTextureSemantic"],
                   !meshSource.isEmpty,
                   meshSource == meshSourceKey {
                    let materialName = meta.importSettings["meshMaterialName"] ?? ""
                    let key = "\(meshSource)|\(materialName)|\(semantic)"
                    existingTexturesByKey[key] = meta
                }
            }

            var textureHandleMap: [URL: AssetHandle] = [:]
            var textureDependencies: [AssetHandle] = []
            var embeddedTextureHandles: [String: AssetHandle] = [:]

            if settings.boolValue("importTextures", default: true) {
                let copyTextures = settings.boolValue("copyTextures", default: true)
                for material in meshInfo.materials {
                    for texture in material.textures.values {
                        if let url = texture.url {
                            if textureHandleMap[url] != nil { continue }
                            let ext = url.pathExtension.lowercased()
                            let destinationFolder = (ext == "hdr" || ext == "exr") ? environmentsRoot : texturesFolder
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
                                "semantic": semantic
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
                        if exportEmbeddedTexture(mdlTexture, to: destinationURL) {
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
                                "embedded": "true"
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
                    } else if reimportMeshMeta != nil && FileManager.default.fileExists(atPath: candidateURL.path) {
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

            let meshHandle = existingMeshHandle ?? AssetHandle()
            let meshRelativePath = PathUtils.relativePath(from: rootURL, to: meshDestinationURL) ?? meshDestinationURL.lastPathComponent

            var meshImportSettings = settings.values
            meshImportSettings["importer"] = importerId
            meshImportSettings["importerVersion"] = importerVersion
            meshImportSettings["sourcePath"] = sourceRelativePath
            meshImportSettings["sourcePathAbs"] = sourcePathAbs
            if !meshInfo.submeshMaterialIndices.isEmpty {
                let handleStrings = meshInfo.submeshMaterialIndices.map { index -> String in
                    if index >= 0 && index < materialHandles.count {
                        return materialHandles[index].rawValue.uuidString
                    }
                    return ""
                }
                meshImportSettings["submeshMaterials"] = handleStrings.joined(separator: ",")
            }

            let meshMetadata = AssetMetadata(
                handle: meshHandle,
                type: .model,
                sourcePath: meshRelativePath,
                importSettings: meshImportSettings,
                dependencies: materialHandles + textureDependencies,
                lastModified: Date().timeIntervalSince1970
            )
            projectManager.saveMetadata(meshMetadata, to: meshMetaURL)

            commitResult = ImportCommitResult(
                primaryHandle: meshHandle,
                writtenPaths: [meshRelativePath],
                dependencyHandles: materialHandles + textureDependencies
            )

            return true
        }

        return ok ? commitResult : nil
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
            dependencyHandles: []
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
    private let importers: [any AssetImporter] = [TextureImporter(), EnvironmentImporter(), MeshImporter()]

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
        lastErrorMessage = "Import failed."
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
