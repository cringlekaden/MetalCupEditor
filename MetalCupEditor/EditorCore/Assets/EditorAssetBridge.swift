/// EditorAssetBridge.swift
/// Defines C-callable asset bridge helpers for the editor UI.
/// Created by Kaden Cringle.

import Foundation
import MetalCupEngine

private func resolveContext(_ contextPtr: UnsafeRawPointer?) -> MCEContext? {
    guard let contextPtr else { return nil }
    return Unmanaged<MCEContext>.fromOpaque(contextPtr).takeUnretainedValue()
}

private func refreshAssetSnapshotIfNeeded(_ context: MCEContext) {
    let revision = context.editorProjectManager.assetRevisionToken()
    if revision == context.assetSnapshotStore.revision { return }
    let assets = context.editorProjectManager.assetMetadataSnapshot()
    context.assetSnapshotStore.snapshot = assets.sorted { $0.sourcePath < $1.sourcePath }
    context.assetSnapshotStore.revision = revision
}

@_cdecl("MCEEditorGetAssetCount")
public func MCEEditorGetAssetCount(_ contextPtr: UnsafeRawPointer?) -> Int32 {
    guard let context = resolveContext(contextPtr) else { return 0 }
    refreshAssetSnapshotIfNeeded(context)
    return Int32(context.assetSnapshotStore.snapshot.count)
}

@_cdecl("MCEEditorGetAssetAt")
public func MCEEditorGetAssetAt(_ contextPtr: UnsafeRawPointer?,
                                _ index: Int32,
                                _ handleBuffer: UnsafeMutablePointer<CChar>?, _ handleBufferSize: Int32,
                                _ typeOut: UnsafeMutablePointer<Int32>?,
                                _ pathBuffer: UnsafeMutablePointer<CChar>?, _ pathBufferSize: Int32,
                                _ nameBuffer: UnsafeMutablePointer<CChar>?, _ nameBufferSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr) else { return 0 }
    let idx = Int(index)
    guard idx >= 0, idx < context.assetSnapshotStore.snapshot.count else { return 0 }
    let meta = context.assetSnapshotStore.snapshot[idx]

    _ = writeCString(meta.handle.rawValue.uuidString, to: handleBuffer, max: handleBufferSize)
    _ = writeCString(meta.sourcePath, to: pathBuffer, max: pathBufferSize)

    let displayName = AssetIO.assetDisplayName(for: meta, assetManager: context.engineContext.assets)
    _ = writeCString(displayName, to: nameBuffer, max: nameBufferSize)

    typeOut?.pointee = AssetTypes.code(for: meta.type)
    return 1
}

@_cdecl("MCEEditorGetAssetDisplayName")
public func MCEEditorGetAssetDisplayName(_ contextPtr: UnsafeRawPointer?,
                                         _ handle: UnsafePointer<CChar>?,
                                         _ buffer: UnsafeMutablePointer<CChar>?,
                                         _ bufferSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr) else { return 0 }
    guard let handle, let buffer, bufferSize > 0 else { return 0 }
    let handleString = String(cString: handle)
    guard let uuid = UUID(uuidString: handleString) else { return 0 }
    let assetHandle = AssetHandle(rawValue: uuid)
    refreshAssetSnapshotIfNeeded(context)
    guard let metadata = context.assetSnapshotStore.snapshot.first(where: { $0.handle == assetHandle }) else { return 0 }
    let name = AssetIO.assetDisplayName(for: metadata, assetManager: context.engineContext.assets)
    return name.withCString { ptr in
        let length = min(Int(bufferSize - 1), strlen(ptr))
        if length > 0 { memcpy(buffer, ptr, length) }
        buffer[length] = 0
        return 1
    }
}

@_cdecl("MCEEditorCreateMaterial")
public func MCEEditorCreateMaterial(_ contextPtr: UnsafeRawPointer?,
                                    _ relativePath: UnsafePointer<CChar>?,
                                    _ name: UnsafePointer<CChar>?,
                                    _ outHandle: UnsafeMutablePointer<CChar>?,
                                    _ outHandleSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr) else { return 0 }
    let nameString = name != nil ? String(cString: name!) : "Material"
    let rel = relativePath != nil ? String(cString: relativePath!) : nil
    guard let sanitized = AssetOps.sanitizeRelativePath(rel) else { return 0 }
    let targetPath = sanitized.isEmpty ? "Materials" : sanitized
    guard let handle = AssetOps.createMaterial(context: contextPtr, named: nameString, relativePath: targetPath) else { return 0 }
    _ = writeCString(handle.rawValue.uuidString, to: outHandle, max: outHandleSize)
    return 1
}

@_cdecl("MCEEditorRenameMaterial")
public func MCEEditorRenameMaterial(_ contextPtr: UnsafeRawPointer?,
                                    _ handle: UnsafePointer<CChar>?,
                                    _ newName: UnsafePointer<CChar>?) -> UInt32 {
    guard resolveContext(contextPtr) != nil else { return 0 }
    guard let handle, let newName else { return 0 }
    let handleString = String(cString: handle)
    guard let uuid = UUID(uuidString: handleString) else { return 0 }
    let ok = AssetOps.renameMaterial(context: contextPtr, handle: AssetHandle(rawValue: uuid), newName: String(cString: newName))
    return ok ? 1 : 0
}

@_cdecl("MCEEditorDuplicateMaterial")
public func MCEEditorDuplicateMaterial(_ contextPtr: UnsafeRawPointer?,
                                       _ handle: UnsafePointer<CChar>?,
                                       _ outHandle: UnsafeMutablePointer<CChar>?,
                                       _ outHandleSize: Int32) -> UInt32 {
    guard resolveContext(contextPtr) != nil else { return 0 }
    guard let handle else { return 0 }
    let handleString = String(cString: handle)
    guard let uuid = UUID(uuidString: handleString) else { return 0 }
    guard let newHandle = AssetOps.duplicateMaterial(context: contextPtr, handle: AssetHandle(rawValue: uuid)) else { return 0 }
    _ = writeCString(newHandle.rawValue.uuidString, to: outHandle, max: outHandleSize)
    return 1
}

@_cdecl("MCEEditorDeleteMaterial")
public func MCEEditorDeleteMaterial(_ contextPtr: UnsafeRawPointer?, _ handle: UnsafePointer<CChar>?) -> UInt32 {
    guard resolveContext(contextPtr) != nil else { return 0 }
    guard let handle else { return 0 }
    let handleString = String(cString: handle)
    guard let uuid = UUID(uuidString: handleString) else { return 0 }
    return AssetOps.deleteMaterial(context: contextPtr, handle: AssetHandle(rawValue: uuid)) ? 1 : 0
}

@_cdecl("MCEEditorGetMaterialAsset")
public func MCEEditorGetMaterialAsset(
    _ contextPtr: UnsafeRawPointer?,
    _ handle: UnsafePointer<CChar>?,
    _ nameBuffer: UnsafeMutablePointer<CChar>?, _ nameBufferSize: Int32,
    _ version: UnsafeMutablePointer<Int32>?,
    _ baseColorX: UnsafeMutablePointer<Float>?, _ baseColorY: UnsafeMutablePointer<Float>?, _ baseColorZ: UnsafeMutablePointer<Float>?,
    _ metallic: UnsafeMutablePointer<Float>?, _ roughness: UnsafeMutablePointer<Float>?, _ ao: UnsafeMutablePointer<Float>?,
    _ emissiveX: UnsafeMutablePointer<Float>?, _ emissiveY: UnsafeMutablePointer<Float>?, _ emissiveZ: UnsafeMutablePointer<Float>?,
    _ emissiveIntensity: UnsafeMutablePointer<Float>?,
    _ alphaMode: UnsafeMutablePointer<Int32>?, _ alphaCutoff: UnsafeMutablePointer<Float>?,
    _ doubleSided: UnsafeMutablePointer<UInt32>?, _ unlit: UnsafeMutablePointer<UInt32>?,
    _ baseColorHandle: UnsafeMutablePointer<CChar>?, _ baseColorHandleSize: Int32,
    _ normalHandle: UnsafeMutablePointer<CChar>?, _ normalHandleSize: Int32,
    _ metalRoughnessHandle: UnsafeMutablePointer<CChar>?, _ metalRoughnessHandleSize: Int32,
    _ metallicHandle: UnsafeMutablePointer<CChar>?, _ metallicHandleSize: Int32,
    _ roughnessHandle: UnsafeMutablePointer<CChar>?, _ roughnessHandleSize: Int32,
    _ aoHandle: UnsafeMutablePointer<CChar>?, _ aoHandleSize: Int32,
    _ emissiveHandle: UnsafeMutablePointer<CChar>?, _ emissiveHandleSize: Int32
) -> UInt32 {
    guard let handle else { return 0 }
    let handleString = String(cString: handle)
    guard let uuid = UUID(uuidString: handleString) else { return 0 }
    let assetHandle = AssetHandle(rawValue: uuid)
    guard let context = resolveContext(contextPtr) else { return 0 }
    guard let material = context.engineContext.assets.material(handle: assetHandle) else { return 0 }

    _ = writeCString(material.name, to: nameBuffer, max: nameBufferSize)
    version?.pointee = Int32(material.version)
    baseColorX?.pointee = material.baseColorFactor.x
    baseColorY?.pointee = material.baseColorFactor.y
    baseColorZ?.pointee = material.baseColorFactor.z
    metallic?.pointee = material.metallicFactor
    roughness?.pointee = material.roughnessFactor
    ao?.pointee = material.aoFactor
    emissiveX?.pointee = material.emissiveColor.x
    emissiveY?.pointee = material.emissiveColor.y
    emissiveZ?.pointee = material.emissiveColor.z
    emissiveIntensity?.pointee = material.emissiveIntensity
    alphaMode?.pointee = MaterialAlphaModeCodes.code(for: material.alphaMode)
    alphaCutoff?.pointee = material.alphaCutoff
    doubleSided?.pointee = material.doubleSided ? 1 : 0
    unlit?.pointee = material.unlit ? 1 : 0

    _ = writeCString(material.textures.baseColor?.rawValue.uuidString ?? "", to: baseColorHandle, max: baseColorHandleSize)
    _ = writeCString(material.textures.normal?.rawValue.uuidString ?? "", to: normalHandle, max: normalHandleSize)
    _ = writeCString(material.textures.metalRoughness?.rawValue.uuidString ?? "", to: metalRoughnessHandle, max: metalRoughnessHandleSize)
    _ = writeCString(material.textures.metallic?.rawValue.uuidString ?? "", to: metallicHandle, max: metallicHandleSize)
    _ = writeCString(material.textures.roughness?.rawValue.uuidString ?? "", to: roughnessHandle, max: roughnessHandleSize)
    _ = writeCString(material.textures.ao?.rawValue.uuidString ?? "", to: aoHandle, max: aoHandleSize)
    _ = writeCString(material.textures.emissive?.rawValue.uuidString ?? "", to: emissiveHandle, max: emissiveHandleSize)

    return 1
}

@_cdecl("MCEEditorSetMaterialAsset")
public func MCEEditorSetMaterialAsset(
    _ contextPtr: UnsafeRawPointer?,
    _ handle: UnsafePointer<CChar>?,
    _ name: UnsafePointer<CChar>?,
    _ version: Int32,
    _ baseColorX: Float, _ baseColorY: Float, _ baseColorZ: Float,
    _ metallic: Float, _ roughness: Float, _ ao: Float,
    _ emissiveX: Float, _ emissiveY: Float, _ emissiveZ: Float,
    _ emissiveIntensity: Float,
    _ alphaMode: Int32, _ alphaCutoff: Float,
    _ doubleSided: UInt32, _ unlit: UInt32,
    _ baseColorHandle: UnsafePointer<CChar>?,
    _ normalHandle: UnsafePointer<CChar>?,
    _ metalRoughnessHandle: UnsafePointer<CChar>?,
    _ metallicHandle: UnsafePointer<CChar>?,
    _ roughnessHandle: UnsafePointer<CChar>?,
    _ aoHandle: UnsafePointer<CChar>?,
    _ emissiveHandle: UnsafePointer<CChar>?
) -> UInt32 {
    guard let context = resolveContext(contextPtr) else { return 0 }
    guard let handle else { return 0 }
    let handleString = String(cString: handle)
    guard let uuid = UUID(uuidString: handleString) else { return 0 }
    let assetHandle = AssetHandle(rawValue: uuid)
    guard let assetURL = context.editorProjectManager.assetURL(for: assetHandle) else { return 0 }

    var material = context.engineContext.assets.material(handle: assetHandle)
        ?? MaterialAsset.default(handle: assetHandle, name: name != nil ? String(cString: name!) : "Material")

    if let name {
        material.name = String(cString: name)
    }
    material.version = Int(version)
    material.baseColorFactor = SIMD3<Float>(baseColorX, baseColorY, baseColorZ)
    material.metallicFactor = metallic
    material.roughnessFactor = roughness
    material.aoFactor = ao
    material.emissiveColor = SIMD3<Float>(emissiveX, emissiveY, emissiveZ)
    material.emissiveIntensity = emissiveIntensity
    material.alphaMode = MaterialAlphaModeCodes.mode(from: alphaMode)
    material.alphaCutoff = alphaCutoff
    material.doubleSided = doubleSided != 0
    material.unlit = unlit != 0

    material.textures.baseColor = handleFromCString(baseColorHandle)
    material.textures.normal = handleFromCString(normalHandle)
    material.textures.metalRoughness = handleFromCString(metalRoughnessHandle)
    material.textures.metallic = handleFromCString(metallicHandle)
    material.textures.roughness = handleFromCString(roughnessHandle)
    material.textures.ao = handleFromCString(aoHandle)
    material.textures.emissive = handleFromCString(emissiveHandle)
    material.textures.enforceMetalRoughnessRule()

    let ok = context.editorProjectManager.performAssetMutation {
        if !MaterialSerializer.save(material, to: assetURL) {
            context.editorAlertCenter.enqueueError("Failed to save material file.")
            return false
        }
        return true
    }
    if ok {
        context.engineContext.log.logInfo("Saved material: \(material.name)", category: .assets)
        return 1
    }
    return 0
}

@_cdecl("MCEEditorGetAssetsRootPath")
public func MCEEditorGetAssetsRootPath(_ contextPtr: UnsafeRawPointer?,
                                       _ buffer: UnsafeMutablePointer<CChar>?,
                                       _ bufferSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr) else { return 0 }
    guard let buffer, bufferSize > 0 else { return 0 }
    guard let rootURL = context.editorProjectManager.assetRootURL() else { return 0 }
    _ = writeCString(rootURL.standardizedFileURL.path, to: buffer, max: bufferSize)
    return 1
}

@_cdecl("MCEEditorListDirectory")
public func MCEEditorListDirectory(_ contextPtr: UnsafeRawPointer?, _ relativePath: UnsafePointer<CChar>?) -> Int32 {
    guard let context = resolveContext(contextPtr) else { return 0 }
    guard let rootURL = context.editorProjectManager.assetRootURL() else { return 0 }
    let rel = relativePath != nil ? String(cString: relativePath!) : ""
    guard let targetURL = AssetOps.resolveDirectoryURL(rootURL: rootURL, relativePath: rel) else { return 0 }

    let fileManager = FileManager.default
    guard let items = try? fileManager.contentsOfDirectory(at: targetURL, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) else {
        context.directorySnapshotStore.entries = []
        return 0
    }

    var entries: [DirectoryEntrySnapshot] = []
    entries.reserveCapacity(items.count)

    let metadataLookup = context.editorProjectManager.assetMetadataSnapshot()
    for url in items {
        let name = url.lastPathComponent
        if name.hasPrefix(".") { continue }
        if url.pathExtension == "meta" { continue }
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
        let isDir = values?.isDirectory ?? false
        let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        guard let relative = PathUtils.relativePath(from: rootURL, to: url) else { continue }
        var assetType: Int32 = AssetTypes.code(for: .unknown)
        var handleString = ""
        if !isDir, let meta = metadataLookup.first(where: { $0.sourcePath == relative }) {
            assetType = AssetTypes.code(for: meta.type)
            handleString = meta.handle.rawValue.uuidString
        }
        let displayName = isDir ? name : AssetIO.displayNameForFile(url: url, modifiedTime: modified)
        entries.append(DirectoryEntrySnapshot(
            name: displayName,
            relativePath: relative,
            isDirectory: isDir,
            assetType: assetType,
            handle: handleString,
            modifiedTime: modified
        ))
    }

    context.directorySnapshotStore.entries = entries
    return Int32(entries.count)
}

@_cdecl("MCEEditorGetDirectoryEntry")
public func MCEEditorGetDirectoryEntry(_ contextPtr: UnsafeRawPointer?,
                                       _ index: Int32,
                                       _ nameBuffer: UnsafeMutablePointer<CChar>?, _ nameBufferSize: Int32,
                                       _ relativePathBuffer: UnsafeMutablePointer<CChar>?, _ relativePathBufferSize: Int32,
                                       _ isDirectoryOut: UnsafeMutablePointer<UInt32>?,
                                       _ typeOut: UnsafeMutablePointer<Int32>?,
                                       _ handleBuffer: UnsafeMutablePointer<CChar>?, _ handleBufferSize: Int32,
                                       _ modifiedOut: UnsafeMutablePointer<Double>?) -> UInt32 {
    guard let context = resolveContext(contextPtr) else { return 0 }
    let idx = Int(index)
    guard idx >= 0, idx < context.directorySnapshotStore.entries.count else { return 0 }
    let entry = context.directorySnapshotStore.entries[idx]

    _ = writeCString(entry.name, to: nameBuffer, max: nameBufferSize)
    _ = writeCString(entry.relativePath, to: relativePathBuffer, max: relativePathBufferSize)
    isDirectoryOut?.pointee = entry.isDirectory ? 1 : 0
    typeOut?.pointee = entry.assetType
    _ = writeCString(entry.handle, to: handleBuffer, max: handleBufferSize)
    modifiedOut?.pointee = entry.modifiedTime
    return 1
}

@_cdecl("MCEEditorCreateFolder")
public func MCEEditorCreateFolder(_ contextPtr: UnsafeRawPointer?,
                                  _ relativePath: UnsafePointer<CChar>?,
                                  _ name: UnsafePointer<CChar>?) -> UInt32 {
    let rel = relativePath != nil ? String(cString: relativePath!) : ""
    let folderName = name != nil ? String(cString: name!) : "New Folder"
    return AssetOps.createFolder(context: contextPtr, relativePath: rel, name: folderName) ? 1 : 0
}

@_cdecl("MCEEditorCreateScene")
public func MCEEditorCreateScene(_ contextPtr: UnsafeRawPointer?,
                                 _ relativePath: UnsafePointer<CChar>?,
                                 _ name: UnsafePointer<CChar>?) -> UInt32 {
    let rel = relativePath != nil ? String(cString: relativePath!) : ""
    let sceneName = name != nil ? String(cString: name!) : "Untitled"
    return AssetOps.createScene(context: contextPtr, relativePath: rel, name: sceneName) ? 1 : 0
}

@_cdecl("MCEEditorCreatePrefab")
public func MCEEditorCreatePrefab(_ contextPtr: UnsafeRawPointer?,
                                  _ relativePath: UnsafePointer<CChar>?,
                                  _ name: UnsafePointer<CChar>?) -> UInt32 {
    let rel = relativePath != nil ? String(cString: relativePath!) : ""
    let prefabName = name != nil ? String(cString: name!) : "Prefab"
    return AssetOps.createPrefab(context: contextPtr, relativePath: rel, name: prefabName) ? 1 : 0
}


@_cdecl("MCEEditorOpenSceneAtPath")
public func MCEEditorOpenSceneAtPath(_ contextPtr: UnsafeRawPointer?, _ relativePath: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr) else { return 0 }
    guard let rootURL = context.editorProjectManager.projectRootURL else { return 0 }
    guard let relativePath else { return 0 }
    let rel = String(cString: relativePath)
    guard let sanitized = AssetOps.sanitizeRelativePath(rel) else { return 0 }
    var url = rootURL.appendingPathComponent(sanitized)
    if let assetRoot = context.editorProjectManager.assetRootURL() {
        if !sanitized.hasPrefix("Assets/") && !sanitized.hasPrefix("Assets") {
            let assetURL = assetRoot.appendingPathComponent(sanitized)
            if FileManager.default.fileExists(atPath: assetURL.path) {
                url = assetURL
            }
        }
    }
    do {
        try context.editorSceneController.loadScene(from: url)
        context.engineContext.log.logInfo("Opened scene.", category: .scene)
        return 1
    } catch {
        context.editorAlertCenter.enqueueError("Failed to open scene: \(error.localizedDescription)")
        return 0
    }
}

@_cdecl("MCEEditorSetSelectedMaterial")
public func MCEEditorSetSelectedMaterial(_ contextPtr: UnsafeRawPointer?, _ handle: UnsafePointer<CChar>?) {
    guard let context = resolveContext(contextPtr) else { return }
    context.editorSelection.setSelectedMaterial(handle: handle != nil ? String(cString: handle!) : nil)
}

@_cdecl("MCEEditorGetSelectedMaterial")
public func MCEEditorGetSelectedMaterial(_ contextPtr: UnsafeRawPointer?,
                                         _ buffer: UnsafeMutablePointer<CChar>?,
                                         _ bufferSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr) else { return 0 }
    guard let buffer, bufferSize > 0 else { return 0 }
    _ = writeCString(context.editorSelection.selectedMaterialHandle, to: buffer, max: bufferSize)
    return context.editorSelection.selectedMaterialHandle.isEmpty ? 0 : 1
}

@_cdecl("MCEEditorOpenMaterialEditor")
public func MCEEditorOpenMaterialEditor(_ contextPtr: UnsafeRawPointer?, _ handle: UnsafePointer<CChar>?) {
    guard let context = resolveContext(contextPtr) else { return }
    guard let handle else { return }
    let value = String(cString: handle)
    guard !value.isEmpty else { return }
    context.editorSelection.requestOpenMaterialEditor(handle: value)
}

@_cdecl("MCEEditorConsumeOpenMaterialEditor")
public func MCEEditorConsumeOpenMaterialEditor(_ contextPtr: UnsafeRawPointer?,
                                               _ buffer: UnsafeMutablePointer<CChar>?,
                                               _ bufferSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr) else { return 0 }
    guard let buffer, bufferSize > 0 else { return 0 }
    guard let value = context.editorSelection.consumeOpenMaterialEditorHandle() else { return 0 }
    _ = writeCString(value, to: buffer, max: bufferSize)
    return 1
}

@_cdecl("MCEEditorRefreshAssets")
public func MCEEditorRefreshAssets(_ contextPtr: UnsafeRawPointer?) {
    guard let context = resolveContext(contextPtr) else { return }
    AssetIO.clearDisplayNameCache()
    context.editorProjectManager.refreshAssets()
}

@_cdecl("MCEEditorGetAssetRevision")
public func MCEEditorGetAssetRevision(_ contextPtr: UnsafeRawPointer?) -> UInt64 {
    guard let context = resolveContext(contextPtr) else { return 0 }
    return context.editorProjectManager.assetRevisionToken()
}

@_cdecl("MCEEditorGetAssetPathForHandle")
public func MCEEditorGetAssetPathForHandle(_ contextPtr: UnsafeRawPointer?,
                                           _ handle: UnsafePointer<CChar>?,
                                           _ buffer: UnsafeMutablePointer<CChar>?,
                                           _ bufferSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr) else { return 0 }
    guard let handle, let buffer, bufferSize > 0 else { return 0 }
    let handleString = String(cString: handle)
    guard let uuid = UUID(uuidString: handleString) else { return 0 }
    let assetHandle = AssetHandle(rawValue: uuid)
    guard let assetURL = context.editorProjectManager.assetURL(for: assetHandle),
          let rootURL = context.editorProjectManager.assetRootURL(),
          let relative = PathUtils.relativePath(from: rootURL, to: assetURL) else { return 0 }
    return relative.withCString { ptr in
        let length = min(Int(bufferSize - 1), strlen(ptr))
        if length > 0 { memcpy(buffer, ptr, length) }
        buffer[length] = 0
        return 1
    }
}

@_cdecl("MCEEditorRenameAsset")
public func MCEEditorRenameAsset(_ contextPtr: UnsafeRawPointer?,
                                 _ relativePath: UnsafePointer<CChar>?,
                                 _ newName: UnsafePointer<CChar>?,
                                 _ outPath: UnsafeMutablePointer<CChar>?,
                                 _ outPathSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr) else { return 0 }
    guard let relativePath, let newName else { return 0 }
    let rel = String(cString: relativePath)
    let rawName = String(cString: newName)
    guard let rootURL = context.editorProjectManager.assetRootURL() else { return 0 }
    guard let originalURL = AssetOps.resolveAssetURL(rootURL: rootURL, relativePath: rel) else { return 0 }
    guard let newURL = AssetOps.renameAsset(context: contextPtr, relativePath: rel, newName: rawName) else { return 0 }
    if newURL.standardizedFileURL.path == originalURL.standardizedFileURL.path { return 1 }
    guard let outPath, outPathSize > 0,
          let relative = PathUtils.relativePath(from: rootURL, to: newURL) else { return 1 }
    return relative.withCString { ptr in
        let length = min(Int(outPathSize - 1), strlen(ptr))
        if length > 0 { memcpy(outPath, ptr, length) }
        outPath[length] = 0
        return 1
    }
}

@_cdecl("MCEEditorDeleteAsset")
public func MCEEditorDeleteAsset(_ contextPtr: UnsafeRawPointer?, _ relativePath: UnsafePointer<CChar>?) -> UInt32 {
    guard let relativePath else { return 0 }
    let rel = String(cString: relativePath)
    return AssetOps.deleteAsset(context: contextPtr, relativePath: rel) ? 1 : 0
}

@_cdecl("MCEEditorDuplicateAsset")
public func MCEEditorDuplicateAsset(_ contextPtr: UnsafeRawPointer?,
                                    _ relativePath: UnsafePointer<CChar>?,
                                    _ outPath: UnsafeMutablePointer<CChar>?,
                                    _ outPathSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr) else { return 0 }
    guard let relativePath else { return 0 }
    let rel = String(cString: relativePath)
    guard let newURL = AssetOps.duplicateAsset(context: contextPtr, relativePath: rel) else { return 0 }
    guard let rootURL = context.editorProjectManager.assetRootURL() else { return 1 }
    guard let outPath, outPathSize > 0,
          let relative = PathUtils.relativePath(from: rootURL, to: newURL) else { return 1 }
    return relative.withCString { ptr in
        let length = min(Int(outPathSize - 1), strlen(ptr))
        if length > 0 { memcpy(outPath, ptr, length) }
        outPath[length] = 0
        return 1
    }
}

private func handleFromCString(_ cString: UnsafePointer<CChar>?) -> AssetHandle? {
    guard let cString else { return nil }
    let value = String(cString: cString)
    guard let uuid = UUID(uuidString: value) else { return nil }
    return AssetHandle(rawValue: uuid)
}

private func writeCString(_ string: String, to buffer: UnsafeMutablePointer<CChar>?, max: Int32) -> Int32 {
    guard let buffer, max > 0 else { return 0 }
    return string.withCString { ptr in
        let length = min(Int(max - 1), strlen(ptr))
        if length > 0 {
            memcpy(buffer, ptr, length)
        }
        buffer[length] = 0
        return Int32(length)
    }
}
