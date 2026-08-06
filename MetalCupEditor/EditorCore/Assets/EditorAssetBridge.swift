/// EditorAssetBridge.swift
/// Defines C-callable asset bridge helpers for the editor UI.
/// Created by Kaden Cringle.

import Foundation
import AppKit
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

private func metadataForHandle(_ context: MCEContext, _ handleString: String) -> AssetMetadata? {
    guard let uuid = UUID(uuidString: handleString) else { return nil }
    refreshAssetSnapshotIfNeeded(context)
    let handle = AssetHandle(rawValue: uuid)
    return context.assetSnapshotStore.snapshot.first(where: { $0.handle == handle })
}

private func parseHandleList(_ raw: String?) -> [AssetHandle] {
    guard let raw, !raw.isEmpty else { return [] }
    return raw
        .split(separator: ",")
        .compactMap { UUID(uuidString: String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
        .map { AssetHandle(rawValue: $0) }
}

private func modelMetadata(forMeshHandleString meshHandleString: String, context: MCEContext) -> AssetMetadata? {
    guard let metadata = metadataForHandle(context, meshHandleString), metadata.type == .model else { return nil }
    return metadata
}

private func animationGraphHandle(from raw: UnsafePointer<CChar>?) -> AssetHandle? {
    guard let raw else { return nil }
    let value = String(cString: raw).trimmingCharacters(in: .whitespacesAndNewlines)
    guard let uuid = UUID(uuidString: value) else { return nil }
    return AssetHandle(rawValue: uuid)
}

private func animationGraphMetadata(context: MCEContext, handle: AssetHandle) -> AssetMetadata? {
    refreshAssetSnapshotIfNeeded(context)
    guard let metadata = context.assetSnapshotStore.snapshot.first(where: { $0.handle == handle }) else { return nil }
    guard metadata.type == .animationGraph else { return nil }
    return metadata
}

private func optionalUUID(from raw: UnsafePointer<CChar>?) -> UUID? {
    guard let raw else { return nil }
    let value = String(cString: raw).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return nil }
    return UUID(uuidString: value)
}

private func optionalAssetHandle(from raw: UnsafePointer<CChar>?) -> AssetHandle? {
    guard let uuid = optionalUUID(from: raw) else { return nil }
    return AssetHandle(rawValue: uuid)
}

private func loadAnimationGraph(context: MCEContext, handle: AssetHandle) -> (AnimationGraphAsset, URL)? {
    guard let metadata = animationGraphMetadata(context: context, handle: handle),
          let url = context.editorProjectManager.assetURL(for: metadata.handle),
          let graph = AnimationGraphAssetSerializer.load(from: url, fallbackHandle: handle) else {
        return nil
    }
    return (graph, url)
}

private func saveAnimationGraph(context: MCEContext, graph: AnimationGraphAsset, url: URL) -> Bool {
    let projectManager = context.editorProjectManager
    let saved = projectManager.performAssetMutation {
        return AnimationGraphAssetSerializer.save(graph, to: url)
    }
    guard saved else { return false }
    let compiled: CompiledAnimationGraph?
    switch AnimationGraphCompiler.compile(asset: graph, clipExists: { clipHandle in
        context.engineContext.assets.animationClip(handle: clipHandle) != nil
    }) {
    case let .success(result):
        compiled = result
    case .failure:
        compiled = nil
    }
    context.engineContext.assets.registerRuntimeAnimationGraph(handle: graph.handle, graph: graph, compiled: compiled)
    refreshAssetSnapshotIfNeeded(context)
    return true
}

private func mutateAnimationGraph(context: MCEContext,
                                  handle: AssetHandle,
                                  mutation: (inout AnimationGraphAsset) -> Bool) -> Bool {
    guard var loaded = loadAnimationGraph(context: context, handle: handle) else { return false }
    let didMutate = mutation(&loaded.0)
    guard didMutate else { return false }
    return saveAnimationGraph(context: context, graph: loaded.0, url: loaded.1)
}

private func defaultNodeTitle(for type: AnimationGraphNodeType) -> String {
    switch type {
    case .outputPose:
        return "Output Pose"
    case .clipPlayer:
        return "Clip Player"
    case .blend1D:
        return "Blend 1D"
    case .blend2D:
        return "Blend 2D"
    case .blendList:
        return "Blend List"
    case .additiveClip:
        return "Additive Clip"
    case .layeredBlend:
        return "Layered Blend"
    case .stateMachine:
        return "State Machine"
    case .parameterFloat:
        return "Parameter Float"
    case .parameterBool:
        return "Parameter Bool"
    case .parameterInt:
        return "Parameter Int"
    case .parameterTrigger:
        return "Parameter Trigger"
    case .select:
        return "Select"
    case .poseCache:
        return "Pose Cache"
    case .aimOffset:
        return "Aim Offset"
    case .lookAt:
        return "Look At"
    case .twoBoneIK:
        return "Two Bone IK"
    case .strideWarp:
        return "Stride Warp"
    case .orientationWarp:
        return "Orientation Warp"
    case .motionMatch:
        return "Motion Match"
    case .rootMotionModifier:
        return "Root Motion Modifier"
    default:
        return "Node"
    }
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

@_cdecl("MCEEditorGetImportedSkeletonHandleForMesh")
public func MCEEditorGetImportedSkeletonHandleForMesh(_ contextPtr: UnsafeRawPointer?,
                                                      _ meshHandle: UnsafePointer<CChar>?,
                                                      _ outHandle: UnsafeMutablePointer<CChar>?,
                                                      _ outHandleSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr), let meshHandle else { return 0 }
    let meshHandleString = String(cString: meshHandle)
    guard let metadata = modelMetadata(forMeshHandleString: meshHandleString, context: context),
          let skeletonRaw = metadata.importSettings["skeletonHandle"] else { return 0 }
    return writeCString(skeletonRaw, to: outHandle, max: outHandleSize) != 0 ? 1 : 0
}

@_cdecl("MCEEditorGetImportedClipCountForMesh")
public func MCEEditorGetImportedClipCountForMesh(_ contextPtr: UnsafeRawPointer?,
                                                 _ meshHandle: UnsafePointer<CChar>?) -> Int32 {
    guard let context = resolveContext(contextPtr), let meshHandle else { return 0 }
    let meshHandleString = String(cString: meshHandle)
    guard let metadata = modelMetadata(forMeshHandleString: meshHandleString, context: context) else { return 0 }
    return Int32(parseHandleList(metadata.importSettings["clipHandles"]).count)
}

@_cdecl("MCEEditorGetImportedClipHandleForMeshAt")
public func MCEEditorGetImportedClipHandleForMeshAt(_ contextPtr: UnsafeRawPointer?,
                                                    _ meshHandle: UnsafePointer<CChar>?,
                                                    _ index: Int32,
                                                    _ outHandle: UnsafeMutablePointer<CChar>?,
                                                    _ outHandleSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr), let meshHandle else { return 0 }
    let meshHandleString = String(cString: meshHandle)
    guard let metadata = modelMetadata(forMeshHandleString: meshHandleString, context: context) else { return 0 }
    let handles = parseHandleList(metadata.importSettings["clipHandles"])
    let i = Int(index)
    guard i >= 0, i < handles.count else { return 0 }
    return writeCString(handles[i].rawValue.uuidString, to: outHandle, max: outHandleSize) != 0 ? 1 : 0
}

@_cdecl("MCEEditorGetImportedDefaultClipHandleForMesh")
public func MCEEditorGetImportedDefaultClipHandleForMesh(_ contextPtr: UnsafeRawPointer?,
                                                         _ meshHandle: UnsafePointer<CChar>?,
                                                         _ outHandle: UnsafeMutablePointer<CChar>?,
                                                         _ outHandleSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr), let meshHandle else { return 0 }
    let meshHandleString = String(cString: meshHandle)
    guard let metadata = modelMetadata(forMeshHandleString: meshHandleString, context: context),
          let clipRaw = metadata.importSettings["defaultClipHandle"] else { return 0 }
    return writeCString(clipRaw, to: outHandle, max: outHandleSize) != 0 ? 1 : 0
}

@_cdecl("MCEEditorGetAnimationClipDuration")
public func MCEEditorGetAnimationClipDuration(_ contextPtr: UnsafeRawPointer?,
                                              _ clipHandle: UnsafePointer<CChar>?,
                                              _ durationOut: UnsafeMutablePointer<Float>?) -> UInt32 {
    guard let context = resolveContext(contextPtr), let clipHandle else { return 0 }
    let clipHandleString = String(cString: clipHandle)
    guard let uuid = UUID(uuidString: clipHandleString) else { return 0 }
    let handle = AssetHandle(rawValue: uuid)
    guard let clip = context.engineContext.assets.animationClip(handle: handle) else { return 0 }
    durationOut?.pointee = max(0.0, clip.durationSeconds)
    return 1
}

@_cdecl("MCEEditorGetAssetImportSetting")
public func MCEEditorGetAssetImportSetting(_ contextPtr: UnsafeRawPointer?,
                                           _ handle: UnsafePointer<CChar>?,
                                           _ key: UnsafePointer<CChar>?,
                                           _ valueOut: UnsafeMutablePointer<CChar>?,
                                           _ valueOutSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handle,
          let key else { return 0 }
    let handleString = String(cString: handle)
    guard let metadata = metadataForHandle(context, handleString) else { return 0 }
    let keyString = String(cString: key)
    guard let value = metadata.importSettings[keyString] else { return 0 }
    return writeCString(value, to: valueOut, max: valueOutSize) != 0 ? 1 : 0
}

@_cdecl("MCEEditorGetSkeletonJointCount")
public func MCEEditorGetSkeletonJointCount(_ contextPtr: UnsafeRawPointer?,
                                           _ skeletonHandle: UnsafePointer<CChar>?,
                                           _ countOut: UnsafeMutablePointer<Int32>?) -> UInt32 {
    guard let context = resolveContext(contextPtr), let skeletonHandle else { return 0 }
    let skeletonHandleString = String(cString: skeletonHandle)
    guard let uuid = UUID(uuidString: skeletonHandleString) else { return 0 }
    let handle = AssetHandle(rawValue: uuid)
    guard let skeleton = context.engineContext.assets.skeleton(handle: handle) else { return 0 }
    countOut?.pointee = Int32(skeleton.joints.count)
    return 1
}

@_cdecl("MCEEditorGetAssociatedClipCountForSkeleton")
public func MCEEditorGetAssociatedClipCountForSkeleton(_ contextPtr: UnsafeRawPointer?,
                                                       _ skeletonHandle: UnsafePointer<CChar>?) -> Int32 {
    guard let context = resolveContext(contextPtr), let skeletonHandle else { return 0 }
    let skeletonHandleString = String(cString: skeletonHandle)
    guard !skeletonHandleString.isEmpty else { return 0 }
    refreshAssetSnapshotIfNeeded(context)
    let count = context.assetSnapshotStore.snapshot.reduce(into: 0) { result, meta in
        guard meta.type == .animationClip else { return }
        if meta.importSettings["skeletonHandle"] == skeletonHandleString {
            result += 1
        }
    }
    return Int32(count)
}

@_cdecl("MCEEditorGetAssociatedClipHandleForSkeletonAt")
public func MCEEditorGetAssociatedClipHandleForSkeletonAt(_ contextPtr: UnsafeRawPointer?,
                                                          _ skeletonHandle: UnsafePointer<CChar>?,
                                                          _ index: Int32,
                                                          _ outHandle: UnsafeMutablePointer<CChar>?,
                                                          _ outHandleSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr), let skeletonHandle else { return 0 }
    let skeletonHandleString = String(cString: skeletonHandle)
    guard !skeletonHandleString.isEmpty else { return 0 }
    refreshAssetSnapshotIfNeeded(context)
    let clips = context.assetSnapshotStore.snapshot
        .filter { $0.type == .animationClip && $0.importSettings["skeletonHandle"] == skeletonHandleString }
        .sorted { $0.sourcePath < $1.sourcePath }
    let i = Int(index)
    guard i >= 0, i < clips.count else { return 0 }
    return writeCString(clips[i].handle.rawValue.uuidString, to: outHandle, max: outHandleSize) != 0 ? 1 : 0
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
    _ uvTilingX: UnsafeMutablePointer<Float>?, _ uvTilingY: UnsafeMutablePointer<Float>?,
    _ uvOffsetX: UnsafeMutablePointer<Float>?, _ uvOffsetY: UnsafeMutablePointer<Float>?,
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
    uvTilingX?.pointee = material.uvTiling.x
    uvTilingY?.pointee = material.uvTiling.y
    uvOffsetX?.pointee = material.uvOffset.x
    uvOffsetY?.pointee = material.uvOffset.y
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
    _ uvTilingX: Float, _ uvTilingY: Float,
    _ uvOffsetX: Float, _ uvOffsetY: Float,
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
    material.uvTiling = SIMD2<Float>(uvTilingX, uvTilingY)
    material.uvOffset = SIMD2<Float>(uvOffsetX, uvOffsetY)
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
        var importFailed = false
        var importFailureReason = ""
        if !isDir, let meta = metadataLookup.first(where: { $0.sourcePath == relative }) {
            assetType = AssetTypes.code(for: meta.type)
            handleString = meta.handle.rawValue.uuidString
            let rawFailed = (meta.importSettings["importFailed"] ?? "").lowercased()
            importFailed = rawFailed == "true" || rawFailed == "1" || rawFailed == "yes"
            importFailureReason = meta.importSettings["importFailureReason"] ?? ""
        }
        let displayName = isDir ? name : AssetIO.displayNameForFile(url: url, modifiedTime: modified)
        entries.append(DirectoryEntrySnapshot(
            name: displayName,
            relativePath: relative,
            isDirectory: isDir,
            assetType: assetType,
            handle: handleString,
            modifiedTime: modified,
            importFailed: importFailed,
            importFailureReason: importFailureReason
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
                                       _ modifiedOut: UnsafeMutablePointer<Double>?,
                                       _ importFailedOut: UnsafeMutablePointer<UInt32>?,
                                       _ failureReasonBuffer: UnsafeMutablePointer<CChar>?, _ failureReasonBufferSize: Int32) -> UInt32 {
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
    importFailedOut?.pointee = entry.importFailed ? 1 : 0
    _ = writeCString(entry.importFailureReason, to: failureReasonBuffer, max: failureReasonBufferSize)
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

@_cdecl("MCEEditorCreateScript")
public func MCEEditorCreateScript(_ contextPtr: UnsafeRawPointer?,
                                  _ relativePath: UnsafePointer<CChar>?,
                                  _ name: UnsafePointer<CChar>?) -> UInt32 {
    let rel = relativePath != nil ? String(cString: relativePath!) : ""
    let scriptName = name != nil ? String(cString: name!) : "NewScript"
    return AssetOps.createScript(context: contextPtr, relativePath: rel, name: scriptName) ? 1 : 0
}

@_cdecl("MCEEditorCreateAnimationGraph")
public func MCEEditorCreateAnimationGraph(_ contextPtr: UnsafeRawPointer?,
                                          _ relativePath: UnsafePointer<CChar>?,
                                          _ name: UnsafePointer<CChar>?,
                                          _ outHandle: UnsafeMutablePointer<CChar>?,
                                          _ outHandleSize: Int32) -> UInt32 {
    let rel = relativePath != nil ? String(cString: relativePath!) : ""
    let graphName = name != nil ? String(cString: name!) : "NewAnimationGraph"
    guard let handle = AssetOps.createAnimationGraph(context: contextPtr, relativePath: rel, name: graphName) else { return 0 }
    _ = writeCString(handle.rawValue.uuidString, to: outHandle, max: outHandleSize)
    return 1
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

@_cdecl("MCEEditorOpenAssetAtPath")
public func MCEEditorOpenAssetAtPath(_ contextPtr: UnsafeRawPointer?, _ relativePath: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr) else { return 0 }
    guard let rootURL = context.editorProjectManager.assetRootURL() else { return 0 }
    guard let relativePath else { return 0 }
    let rel = String(cString: relativePath)
    guard let sanitized = AssetOps.sanitizeRelativePath(rel) else { return 0 }
    let assetURL = rootURL.appendingPathComponent(sanitized)
    guard FileManager.default.fileExists(atPath: assetURL.path) else { return 0 }
    refreshAssetSnapshotIfNeeded(context)
    if let metadata = context.assetSnapshotStore.snapshot.first(where: { $0.sourcePath == sanitized }),
       metadata.type == .animationGraph {
        context.editorSelection.requestOpenAnimationGraphEditor(handle: metadata.handle.rawValue.uuidString)
        return 1
    }
    NSWorkspace.shared.open(assetURL)
    return 1
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

@_cdecl("MCEEditorOpenAnimationGraphEditor")
public func MCEEditorOpenAnimationGraphEditor(_ contextPtr: UnsafeRawPointer?, _ handle: UnsafePointer<CChar>?) {
    guard let context = resolveContext(contextPtr) else { return }
    guard let handle else { return }
    let value = String(cString: handle).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return }
    context.editorSelection.requestOpenAnimationGraphEditor(handle: value)
}

@_cdecl("MCEEditorConsumeOpenAnimationGraphEditor")
public func MCEEditorConsumeOpenAnimationGraphEditor(_ contextPtr: UnsafeRawPointer?,
                                                     _ buffer: UnsafeMutablePointer<CChar>?,
                                                     _ bufferSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr) else { return 0 }
    guard let buffer, bufferSize > 0 else { return 0 }
    guard let value = context.editorSelection.consumeOpenAnimationGraphEditorHandle() else { return 0 }
    _ = writeCString(value, to: buffer, max: bufferSize)
    return 1
}

@_cdecl("MCEEditorGetAnimationGraphInfo")
public func MCEEditorGetAnimationGraphInfo(_ contextPtr: UnsafeRawPointer?,
                                           _ handle: UnsafePointer<CChar>?,
                                           _ nameBuffer: UnsafeMutablePointer<CChar>?, _ nameBufferSize: Int32,
                                           _ outputNodeIdBuffer: UnsafeMutablePointer<CChar>?, _ outputNodeIdBufferSize: Int32,
                                           _ parameterCountOut: UnsafeMutablePointer<Int32>?,
                                           _ nodeCountOut: UnsafeMutablePointer<Int32>?,
                                           _ linkCountOut: UnsafeMutablePointer<Int32>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handle = animationGraphHandle(from: handle),
          let (graph, _) = loadAnimationGraph(context: context, handle: handle) else { return 0 }
    _ = writeCString(graph.name, to: nameBuffer, max: nameBufferSize)
    _ = writeCString(graph.outputNodeID?.uuidString ?? "", to: outputNodeIdBuffer, max: outputNodeIdBufferSize)
    parameterCountOut?.pointee = Int32(graph.parameters.count)
    nodeCountOut?.pointee = Int32(graph.nodes.count)
    linkCountOut?.pointee = Int32(graph.links.count)
    return 1
}

@_cdecl("MCEEditorGetAnimationGraphParameterAt")
public func MCEEditorGetAnimationGraphParameterAt(_ contextPtr: UnsafeRawPointer?,
                                                  _ handle: UnsafePointer<CChar>?,
                                                  _ index: Int32,
                                                  _ nameBuffer: UnsafeMutablePointer<CChar>?, _ nameBufferSize: Int32,
                                                  _ typeOut: UnsafeMutablePointer<Int32>?,
                                                  _ defaultFloatOut: UnsafeMutablePointer<Float>?,
                                                  _ defaultBoolOut: UnsafeMutablePointer<UInt32>?,
                                                  _ defaultIntOut: UnsafeMutablePointer<Int32>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handle = animationGraphHandle(from: handle),
          let (graph, _) = loadAnimationGraph(context: context, handle: handle) else { return 0 }
    let i = Int(index)
    guard i >= 0, i < graph.parameters.count else { return 0 }
    let parameter = graph.parameters[i]
    _ = writeCString(parameter.name, to: nameBuffer, max: nameBufferSize)
    switch parameter.type {
    case .float: typeOut?.pointee = 0
    case .bool: typeOut?.pointee = 1
    case .int: typeOut?.pointee = 2
    case .trigger: typeOut?.pointee = 3
    }
    defaultFloatOut?.pointee = parameter.defaultFloat
    defaultBoolOut?.pointee = parameter.defaultBool ? 1 : 0
    defaultIntOut?.pointee = Int32(clamping: parameter.defaultInt)
    return 1
}

@_cdecl("MCEEditorGetAnimationGraphLocalVariableCount")
public func MCEEditorGetAnimationGraphLocalVariableCount(_ contextPtr: UnsafeRawPointer?,
                                                         _ handle: UnsafePointer<CChar>?) -> Int32 {
    guard let context = resolveContext(contextPtr),
          let handle = animationGraphHandle(from: handle),
          let (graph, _) = loadAnimationGraph(context: context, handle: handle) else { return 0 }
    return Int32(graph.localVariables.count)
}

@_cdecl("MCEEditorGetAnimationGraphLocalVariableAt")
public func MCEEditorGetAnimationGraphLocalVariableAt(_ contextPtr: UnsafeRawPointer?,
                                                      _ handle: UnsafePointer<CChar>?,
                                                      _ index: Int32,
                                                      _ nameBuffer: UnsafeMutablePointer<CChar>?, _ nameBufferSize: Int32,
                                                      _ typeOut: UnsafeMutablePointer<Int32>?,
                                                      _ defaultFloatOut: UnsafeMutablePointer<Float>?,
                                                      _ defaultBoolOut: UnsafeMutablePointer<UInt32>?,
                                                      _ defaultIntOut: UnsafeMutablePointer<Int32>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handle = animationGraphHandle(from: handle),
          let (graph, _) = loadAnimationGraph(context: context, handle: handle) else { return 0 }
    let i = Int(index)
    guard i >= 0, i < graph.localVariables.count else { return 0 }
    let local = graph.localVariables[i]
    _ = writeCString(local.name, to: nameBuffer, max: nameBufferSize)
    switch local.type {
    case .float: typeOut?.pointee = 0
    case .bool: typeOut?.pointee = 1
    case .int: typeOut?.pointee = 2
    }
    defaultFloatOut?.pointee = local.defaultFloat
    defaultBoolOut?.pointee = local.defaultBool ? 1 : 0
    defaultIntOut?.pointee = Int32(clamping: local.defaultInt)
    return 1
}

@_cdecl("MCEEditorGetAnimationGraphNodeAt")
public func MCEEditorGetAnimationGraphNodeAt(_ contextPtr: UnsafeRawPointer?,
                                             _ handle: UnsafePointer<CChar>?,
                                             _ index: Int32,
                                             _ nodeIdBuffer: UnsafeMutablePointer<CChar>?, _ nodeIdBufferSize: Int32,
                                             _ typeOut: UnsafeMutablePointer<Int32>?,
                                             _ titleBuffer: UnsafeMutablePointer<CChar>?, _ titleBufferSize: Int32,
                                             _ posXOut: UnsafeMutablePointer<Float>?,
                                             _ posYOut: UnsafeMutablePointer<Float>?,
                                             _ clipHandleBuffer: UnsafeMutablePointer<CChar>?, _ clipHandleBufferSize: Int32,
                                             _ isOutputOut: UnsafeMutablePointer<UInt32>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handle = animationGraphHandle(from: handle),
          let (graph, _) = loadAnimationGraph(context: context, handle: handle) else { return 0 }
    let i = Int(index)
    guard i >= 0, i < graph.nodes.count else { return 0 }
    let node = graph.nodes[i]
    _ = writeCString(node.id.uuidString, to: nodeIdBuffer, max: nodeIdBufferSize)
    switch node.type {
    case .outputPose: typeOut?.pointee = 0
    case .clipPlayer: typeOut?.pointee = 1
    case .blend1D: typeOut?.pointee = 2
    case .blend2D: typeOut?.pointee = 3
    case .stateMachine: typeOut?.pointee = 4
    case .blendList: typeOut?.pointee = 5
    case .additiveClip: typeOut?.pointee = 6
    case .layeredBlend: typeOut?.pointee = 7
    case .parameterFloat: typeOut?.pointee = 8
    case .parameterBool: typeOut?.pointee = 9
    case .parameterTrigger: typeOut?.pointee = 10
    case .select: typeOut?.pointee = 11
    case .poseCache: typeOut?.pointee = 12
    case .aimOffset: typeOut?.pointee = 13
    case .lookAt: typeOut?.pointee = 14
    case .twoBoneIK: typeOut?.pointee = 15
    case .strideWarp: typeOut?.pointee = 16
    case .orientationWarp: typeOut?.pointee = 17
    case .motionMatch: typeOut?.pointee = 18
    case .rootMotionModifier: typeOut?.pointee = 19
    case .parameterInt: typeOut?.pointee = 20
    case .localFloat: typeOut?.pointee = 21
    case .localBool: typeOut?.pointee = 22
    case .localInt: typeOut?.pointee = 23
    case .setLocalFloat: typeOut?.pointee = 24
    case .setLocalBool: typeOut?.pointee = 25
    case .setLocalInt: typeOut?.pointee = 26
    default: typeOut?.pointee = -1
    }
    _ = writeCString(node.title, to: titleBuffer, max: titleBufferSize)
    posXOut?.pointee = node.position.x
    posYOut?.pointee = node.position.y
    _ = writeCString(node.clipHandle?.rawValue.uuidString ?? "", to: clipHandleBuffer, max: clipHandleBufferSize)
    isOutputOut?.pointee = (graph.outputNodeID == node.id) ? 1 : 0
    return 1
}

@_cdecl("MCEEditorGetAnimationGraphLinkAt")
public func MCEEditorGetAnimationGraphLinkAt(_ contextPtr: UnsafeRawPointer?,
                                             _ handle: UnsafePointer<CChar>?,
                                             _ index: Int32,
                                             _ linkIdBuffer: UnsafeMutablePointer<CChar>?, _ linkIdBufferSize: Int32,
                                             _ fromNodeIdBuffer: UnsafeMutablePointer<CChar>?, _ fromNodeIdBufferSize: Int32,
                                             _ fromSlotOut: UnsafeMutablePointer<Int32>?,
                                             _ toNodeIdBuffer: UnsafeMutablePointer<CChar>?, _ toNodeIdBufferSize: Int32,
                                             _ toSlotOut: UnsafeMutablePointer<Int32>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handle = animationGraphHandle(from: handle),
          let (graph, _) = loadAnimationGraph(context: context, handle: handle) else { return 0 }
    let i = Int(index)
    guard i >= 0, i < graph.links.count else { return 0 }
    let link = graph.links[i]
    _ = writeCString(link.id.uuidString, to: linkIdBuffer, max: linkIdBufferSize)
    _ = writeCString(link.fromNodeID.uuidString, to: fromNodeIdBuffer, max: fromNodeIdBufferSize)
    fromSlotOut?.pointee = Int32(link.fromSlotIndex)
    _ = writeCString(link.toNodeID.uuidString, to: toNodeIdBuffer, max: toNodeIdBufferSize)
    toSlotOut?.pointee = Int32(link.toSlotIndex)
    return 1
}

@_cdecl("MCEEditorSetAnimationGraphMetadata")
public func MCEEditorSetAnimationGraphMetadata(_ contextPtr: UnsafeRawPointer?,
                                               _ handle: UnsafePointer<CChar>?,
                                               _ name: UnsafePointer<CChar>?,
                                               _ outputNodeId: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handleValue = animationGraphHandle(from: handle) else { return 0 }
    let nameValue = name != nil ? String(cString: name!).trimmingCharacters(in: .whitespacesAndNewlines) : ""
    let outputNodeValue = outputNodeId != nil ? String(cString: outputNodeId!).trimmingCharacters(in: .whitespacesAndNewlines) : ""
    let outputNodeUUID = UUID(uuidString: outputNodeValue)
    let didSave = mutateAnimationGraph(context: context, handle: handleValue) { graph in
        graph.name = nameValue.isEmpty ? graph.name : nameValue
        graph.outputNodeID = outputNodeUUID
        return true
    }
    return didSave ? 1 : 0
}

@_cdecl("MCEEditorAddAnimationGraphParameter")
public func MCEEditorAddAnimationGraphParameter(_ contextPtr: UnsafeRawPointer?,
                                                _ handle: UnsafePointer<CChar>?,
                                                _ name: UnsafePointer<CChar>?,
                                                _ type: Int32,
                                                _ defaultFloat: Float,
                                                _ defaultBool: UInt32,
                                                _ defaultInt: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handleValue = animationGraphHandle(from: handle) else { return 0 }
    let nameValue = name != nil ? String(cString: name!).trimmingCharacters(in: .whitespacesAndNewlines) : ""
    guard !nameValue.isEmpty else { return 0 }
    let parameterType: AnimationGraphParameterType
    switch type {
    case 1: parameterType = .bool
    case 2: parameterType = .int
    case 3: parameterType = .trigger
    default: parameterType = .float
    }
    let didSave = mutateAnimationGraph(context: context, handle: handleValue) { graph in
        graph.parameters.append(
            AnimationGraphParameterDefinition(name: nameValue,
                                              type: parameterType,
                                              defaultFloat: defaultFloat,
                                              defaultBool: defaultBool != 0,
                                              defaultInt: Int(defaultInt))
        )
        return true
    }
    return didSave ? 1 : 0
}

@_cdecl("MCEEditorUpdateAnimationGraphParameter")
public func MCEEditorUpdateAnimationGraphParameter(_ contextPtr: UnsafeRawPointer?,
                                                   _ handle: UnsafePointer<CChar>?,
                                                   _ index: Int32,
                                                   _ name: UnsafePointer<CChar>?,
                                                   _ type: Int32,
                                                   _ defaultFloat: Float,
                                                   _ defaultBool: UInt32,
                                                   _ defaultInt: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handleValue = animationGraphHandle(from: handle) else { return 0 }
    let i = Int(index)
    let nameValue = name != nil ? String(cString: name!).trimmingCharacters(in: .whitespacesAndNewlines) : ""
    guard !nameValue.isEmpty else { return 0 }
    let parameterType: AnimationGraphParameterType
    switch type {
    case 1: parameterType = .bool
    case 2: parameterType = .int
    case 3: parameterType = .trigger
    default: parameterType = .float
    }
    let didSave = mutateAnimationGraph(context: context, handle: handleValue) { graph in
        guard i >= 0, i < graph.parameters.count else { return false }
        graph.parameters[i] = AnimationGraphParameterDefinition(
            name: nameValue,
            type: parameterType,
            defaultFloat: defaultFloat,
            defaultBool: defaultBool != 0,
            defaultInt: Int(defaultInt)
        )
        return true
    }
    return didSave ? 1 : 0
}

@_cdecl("MCEEditorRemoveAnimationGraphParameter")
public func MCEEditorRemoveAnimationGraphParameter(_ contextPtr: UnsafeRawPointer?,
                                                   _ handle: UnsafePointer<CChar>?,
                                                   _ index: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handleValue = animationGraphHandle(from: handle) else { return 0 }
    let i = Int(index)
    let didSave = mutateAnimationGraph(context: context, handle: handleValue) { graph in
        guard i >= 0, i < graph.parameters.count else { return false }
        graph.parameters.remove(at: i)
        return true
    }
    return didSave ? 1 : 0
}

@_cdecl("MCEEditorAddAnimationGraphLocalVariable")
public func MCEEditorAddAnimationGraphLocalVariable(_ contextPtr: UnsafeRawPointer?,
                                                    _ handle: UnsafePointer<CChar>?,
                                                    _ name: UnsafePointer<CChar>?,
                                                    _ type: Int32,
                                                    _ defaultFloat: Float,
                                                    _ defaultBool: UInt32,
                                                    _ defaultInt: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handleValue = animationGraphHandle(from: handle) else { return 0 }
    let nameValue = name != nil ? String(cString: name!).trimmingCharacters(in: .whitespacesAndNewlines) : ""
    guard !nameValue.isEmpty else { return 0 }
    let localType: AnimationGraphLocalVariableType
    switch type {
    case 1: localType = .bool
    case 2: localType = .int
    default: localType = .float
    }
    let didSave = mutateAnimationGraph(context: context, handle: handleValue) { graph in
        graph.localVariables.append(
            AnimationGraphLocalVariableDefinition(name: nameValue,
                                                  type: localType,
                                                  defaultFloat: defaultFloat,
                                                  defaultBool: defaultBool != 0,
                                                  defaultInt: Int(defaultInt))
        )
        return true
    }
    return didSave ? 1 : 0
}

@_cdecl("MCEEditorUpdateAnimationGraphLocalVariable")
public func MCEEditorUpdateAnimationGraphLocalVariable(_ contextPtr: UnsafeRawPointer?,
                                                       _ handle: UnsafePointer<CChar>?,
                                                       _ index: Int32,
                                                       _ name: UnsafePointer<CChar>?,
                                                       _ type: Int32,
                                                       _ defaultFloat: Float,
                                                       _ defaultBool: UInt32,
                                                       _ defaultInt: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handleValue = animationGraphHandle(from: handle) else { return 0 }
    let i = Int(index)
    let nameValue = name != nil ? String(cString: name!).trimmingCharacters(in: .whitespacesAndNewlines) : ""
    guard !nameValue.isEmpty else { return 0 }
    let localType: AnimationGraphLocalVariableType
    switch type {
    case 1: localType = .bool
    case 2: localType = .int
    default: localType = .float
    }
    let didSave = mutateAnimationGraph(context: context, handle: handleValue) { graph in
        guard i >= 0, i < graph.localVariables.count else { return false }
        graph.localVariables[i] = AnimationGraphLocalVariableDefinition(name: nameValue,
                                                                         type: localType,
                                                                         defaultFloat: defaultFloat,
                                                                         defaultBool: defaultBool != 0,
                                                                         defaultInt: Int(defaultInt))
        return true
    }
    return didSave ? 1 : 0
}

@_cdecl("MCEEditorRemoveAnimationGraphLocalVariable")
public func MCEEditorRemoveAnimationGraphLocalVariable(_ contextPtr: UnsafeRawPointer?,
                                                       _ handle: UnsafePointer<CChar>?,
                                                       _ index: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handleValue = animationGraphHandle(from: handle) else { return 0 }
    let i = Int(index)
    let didSave = mutateAnimationGraph(context: context, handle: handleValue) { graph in
        guard i >= 0, i < graph.localVariables.count else { return false }
        graph.localVariables.remove(at: i)
        return true
    }
    return didSave ? 1 : 0
}

@_cdecl("MCEEditorAddAnimationGraphNode")
public func MCEEditorAddAnimationGraphNode(_ contextPtr: UnsafeRawPointer?,
                                           _ handle: UnsafePointer<CChar>?,
                                           _ type: Int32,
                                           _ title: UnsafePointer<CChar>?,
                                           _ posX: Float,
                                           _ posY: Float,
                                           _ clipHandle: UnsafePointer<CChar>?,
                                           _ outNodeId: UnsafeMutablePointer<CChar>?, _ outNodeIdSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handleValue = animationGraphHandle(from: handle) else { return 0 }
    let nodeID = UUID()
    let nodeType: AnimationGraphNodeType
    switch type {
    case 0: nodeType = .outputPose
    case 1: nodeType = .clipPlayer
    case 2: nodeType = .blend1D
    case 3: nodeType = .blend2D
    case 4: nodeType = .stateMachine
    case 5: nodeType = .blendList
    case 6: nodeType = .additiveClip
    case 7: nodeType = .layeredBlend
    case 8: nodeType = .parameterFloat
    case 9: nodeType = .parameterBool
    case 10: nodeType = .parameterTrigger
    case 11: nodeType = .select
    case 12: nodeType = .poseCache
    case 13: nodeType = .aimOffset
    case 14: nodeType = .lookAt
    case 15: nodeType = .twoBoneIK
    case 16: nodeType = .strideWarp
    case 17: nodeType = .orientationWarp
    case 18: nodeType = .motionMatch
    case 19: nodeType = .rootMotionModifier
    case 20: nodeType = .parameterInt
    case 21: nodeType = .localFloat
    case 22: nodeType = .localBool
    case 23: nodeType = .localInt
    case 24: nodeType = .setLocalFloat
    case 25: nodeType = .setLocalBool
    case 26: nodeType = .setLocalInt
    default: return 0
    }
    let titleValue = title != nil ? String(cString: title!).trimmingCharacters(in: .whitespacesAndNewlines) : ""
    let clipHandleValue = clipHandle.flatMap { UUID(uuidString: String(cString: $0)) }.map { AssetHandle(rawValue: $0) }
    let didSave = mutateAnimationGraph(context: context, handle: handleValue) { graph in
        let node = AnimationGraphNodeDefinition(
            id: nodeID,
            type: nodeType,
            title: titleValue.isEmpty ? defaultNodeTitle(for: nodeType) : titleValue,
            position: SIMD2<Float>(posX, posY),
            clipHandle: clipHandleValue
        )
        graph.nodes.append(node)
        if graph.outputNodeID == nil, nodeType == .outputPose {
            graph.outputNodeID = nodeID
        }
        return true
    }
    if didSave {
        _ = writeCString(nodeID.uuidString, to: outNodeId, max: outNodeIdSize)
    }
    return didSave ? 1 : 0
}

@_cdecl("MCEEditorSetAnimationGraphNodeParameterName")
public func MCEEditorSetAnimationGraphNodeParameterName(_ contextPtr: UnsafeRawPointer?,
                                                        _ handle: UnsafePointer<CChar>?,
                                                        _ nodeId: UnsafePointer<CChar>?,
                                                        _ parameterName: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handleValue = animationGraphHandle(from: handle),
          let nodeId,
          let nodeUUID = UUID(uuidString: String(cString: nodeId)) else { return 0 }
    let parameterValue = parameterName != nil ? String(cString: parameterName!).trimmingCharacters(in: .whitespacesAndNewlines) : ""
    let didSave = mutateAnimationGraph(context: context, handle: handleValue) { graph in
        guard let nodeIndex = graph.nodes.firstIndex(where: { $0.id == nodeUUID }) else { return false }
        graph.nodes[nodeIndex].parameterName = parameterValue.isEmpty ? nil : parameterValue
        return true
    }
    return didSave ? 1 : 0
}

@_cdecl("MCEEditorUpdateAnimationGraphNode")
public func MCEEditorUpdateAnimationGraphNode(_ contextPtr: UnsafeRawPointer?,
                                              _ handle: UnsafePointer<CChar>?,
                                              _ nodeId: UnsafePointer<CChar>?,
                                              _ title: UnsafePointer<CChar>?,
                                              _ posX: Float,
                                              _ posY: Float,
                                              _ clipHandle: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handleValue = animationGraphHandle(from: handle),
          let nodeId,
          let nodeUUID = UUID(uuidString: String(cString: nodeId)) else { return 0 }
    let titleValue = title != nil ? String(cString: title!).trimmingCharacters(in: .whitespacesAndNewlines) : ""
    let clipHandleValue = clipHandle.flatMap { UUID(uuidString: String(cString: $0)) }.map { AssetHandle(rawValue: $0) }
    let didSave = mutateAnimationGraph(context: context, handle: handleValue) { graph in
        guard let index = graph.nodes.firstIndex(where: { $0.id == nodeUUID }) else { return false }
        graph.nodes[index].title = titleValue.isEmpty ? graph.nodes[index].title : titleValue
        graph.nodes[index].position = SIMD2<Float>(posX, posY)
        graph.nodes[index].clipHandle = clipHandleValue
        return true
    }
    return didSave ? 1 : 0
}

@_cdecl("MCEEditorGetAnimationGraphBlend1DNode")
public func MCEEditorGetAnimationGraphBlend1DNode(_ contextPtr: UnsafeRawPointer?,
                                                  _ handle: UnsafePointer<CChar>?,
                                                  _ nodeId: UnsafePointer<CChar>?,
                                                  _ parameterNameBuffer: UnsafeMutablePointer<CChar>?, _ parameterNameBufferSize: Int32,
                                                  _ sampleCountOut: UnsafeMutablePointer<Int32>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handle = animationGraphHandle(from: handle),
          let nodeId,
          let nodeUUID = UUID(uuidString: String(cString: nodeId)),
          let (graph, _) = loadAnimationGraph(context: context, handle: handle),
          let node = graph.nodes.first(where: { $0.id == nodeUUID }),
          node.type == .blend1D,
          let blend = node.blend1D else { return 0 }
    _ = writeCString(blend.parameterName, to: parameterNameBuffer, max: parameterNameBufferSize)
    sampleCountOut?.pointee = Int32(blend.samples.count)
    return 1
}

@_cdecl("MCEEditorGetAnimationGraphBlend1DSampleAt")
public func MCEEditorGetAnimationGraphBlend1DSampleAt(_ contextPtr: UnsafeRawPointer?,
                                                      _ handle: UnsafePointer<CChar>?,
                                                      _ nodeId: UnsafePointer<CChar>?,
                                                      _ index: Int32,
                                                      _ clipHandleBuffer: UnsafeMutablePointer<CChar>?, _ clipHandleBufferSize: Int32,
                                                      _ thresholdOut: UnsafeMutablePointer<Float>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handle = animationGraphHandle(from: handle),
          let nodeId,
          let nodeUUID = UUID(uuidString: String(cString: nodeId)),
          let (graph, _) = loadAnimationGraph(context: context, handle: handle),
          let node = graph.nodes.first(where: { $0.id == nodeUUID }),
          node.type == .blend1D,
          let blend = node.blend1D else { return 0 }
    let i = Int(index)
    guard i >= 0, i < blend.samples.count else { return 0 }
    let sample = blend.samples[i]
    _ = writeCString(sample.clipHandle.rawValue.uuidString, to: clipHandleBuffer, max: clipHandleBufferSize)
    thresholdOut?.pointee = sample.threshold
    return 1
}

@_cdecl("MCEEditorSetAnimationGraphBlend1DNode")
public func MCEEditorSetAnimationGraphBlend1DNode(_ contextPtr: UnsafeRawPointer?,
                                                  _ handle: UnsafePointer<CChar>?,
                                                  _ nodeId: UnsafePointer<CChar>?,
                                                  _ parameterName: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handleValue = animationGraphHandle(from: handle),
          let nodeId,
          let nodeUUID = UUID(uuidString: String(cString: nodeId)) else { return 0 }
    let parameterNameValue = parameterName != nil ? String(cString: parameterName!).trimmingCharacters(in: .whitespacesAndNewlines) : ""
    let didSave = mutateAnimationGraph(context: context, handle: handleValue) { graph in
        guard let index = graph.nodes.firstIndex(where: { $0.id == nodeUUID }) else { return false }
        guard graph.nodes[index].type == .blend1D else { return false }
        if graph.nodes[index].blend1D == nil {
            graph.nodes[index].blend1D = AnimationGraphBlend1DDefinition(parameterName: parameterNameValue, samples: [])
        } else {
            graph.nodes[index].blend1D?.parameterName = parameterNameValue
        }
        return true
    }
    return didSave ? 1 : 0
}

@_cdecl("MCEEditorAddAnimationGraphBlend1DSample")
public func MCEEditorAddAnimationGraphBlend1DSample(_ contextPtr: UnsafeRawPointer?,
                                                    _ handle: UnsafePointer<CChar>?,
                                                    _ nodeId: UnsafePointer<CChar>?,
                                                    _ clipHandle: UnsafePointer<CChar>?,
                                                    _ threshold: Float) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handleValue = animationGraphHandle(from: handle),
          let nodeId,
          let nodeUUID = UUID(uuidString: String(cString: nodeId)),
          let clipHandle,
          let clipUUID = UUID(uuidString: String(cString: clipHandle)) else { return 0 }
    let clipHandleValue = AssetHandle(rawValue: clipUUID)
    let didSave = mutateAnimationGraph(context: context, handle: handleValue) { graph in
        guard let index = graph.nodes.firstIndex(where: { $0.id == nodeUUID }) else { return false }
        guard graph.nodes[index].type == .blend1D else { return false }
        if graph.nodes[index].blend1D == nil {
            graph.nodes[index].blend1D = AnimationGraphBlend1DDefinition(parameterName: "", samples: [])
        }
        graph.nodes[index].blend1D?.samples.append(AnimationGraphBlend1DSampleDefinition(clipHandle: clipHandleValue,
                                                                                          threshold: threshold))
        return true
    }
    return didSave ? 1 : 0
}

@_cdecl("MCEEditorUpdateAnimationGraphBlend1DSample")
public func MCEEditorUpdateAnimationGraphBlend1DSample(_ contextPtr: UnsafeRawPointer?,
                                                       _ handle: UnsafePointer<CChar>?,
                                                       _ nodeId: UnsafePointer<CChar>?,
                                                       _ index: Int32,
                                                       _ clipHandle: UnsafePointer<CChar>?,
                                                       _ threshold: Float) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handleValue = animationGraphHandle(from: handle),
          let nodeId,
          let nodeUUID = UUID(uuidString: String(cString: nodeId)),
          let clipHandle,
          let clipUUID = UUID(uuidString: String(cString: clipHandle)) else { return 0 }
    let i = Int(index)
    let clipHandleValue = AssetHandle(rawValue: clipUUID)
    let didSave = mutateAnimationGraph(context: context, handle: handleValue) { graph in
        guard let nodeIndex = graph.nodes.firstIndex(where: { $0.id == nodeUUID }) else { return false }
        guard graph.nodes[nodeIndex].type == .blend1D,
              var blend = graph.nodes[nodeIndex].blend1D,
              i >= 0, i < blend.samples.count else { return false }
        blend.samples[i] = AnimationGraphBlend1DSampleDefinition(clipHandle: clipHandleValue, threshold: threshold)
        graph.nodes[nodeIndex].blend1D = blend
        return true
    }
    return didSave ? 1 : 0
}

@_cdecl("MCEEditorRemoveAnimationGraphBlend1DSample")
public func MCEEditorRemoveAnimationGraphBlend1DSample(_ contextPtr: UnsafeRawPointer?,
                                                       _ handle: UnsafePointer<CChar>?,
                                                       _ nodeId: UnsafePointer<CChar>?,
                                                       _ index: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handleValue = animationGraphHandle(from: handle),
          let nodeId,
          let nodeUUID = UUID(uuidString: String(cString: nodeId)) else { return 0 }
    let i = Int(index)
    let didSave = mutateAnimationGraph(context: context, handle: handleValue) { graph in
        guard let nodeIndex = graph.nodes.firstIndex(where: { $0.id == nodeUUID }) else { return false }
        guard graph.nodes[nodeIndex].type == .blend1D,
              var blend = graph.nodes[nodeIndex].blend1D,
              i >= 0, i < blend.samples.count else { return false }
        blend.samples.remove(at: i)
        graph.nodes[nodeIndex].blend1D = blend
        return true
    }
    return didSave ? 1 : 0
}

@_cdecl("MCEEditorGetAnimationGraphBlend2DNode")
public func MCEEditorGetAnimationGraphBlend2DNode(_ contextPtr: UnsafeRawPointer?,
                                                  _ handle: UnsafePointer<CChar>?,
                                                  _ nodeId: UnsafePointer<CChar>?,
                                                  _ parameterXNameBuffer: UnsafeMutablePointer<CChar>?, _ parameterXNameBufferSize: Int32,
                                                  _ parameterYNameBuffer: UnsafeMutablePointer<CChar>?, _ parameterYNameBufferSize: Int32,
                                                  _ sampleCountOut: UnsafeMutablePointer<Int32>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handle = animationGraphHandle(from: handle),
          let nodeId,
          let nodeUUID = UUID(uuidString: String(cString: nodeId)),
          let (graph, _) = loadAnimationGraph(context: context, handle: handle),
          let node = graph.nodes.first(where: { $0.id == nodeUUID }),
          node.type == .blend2D,
          let blend = node.blend2D else { return 0 }
    _ = writeCString(blend.parameterXName, to: parameterXNameBuffer, max: parameterXNameBufferSize)
    _ = writeCString(blend.parameterYName, to: parameterYNameBuffer, max: parameterYNameBufferSize)
    sampleCountOut?.pointee = Int32(blend.samples.count)
    return 1
}

@_cdecl("MCEEditorGetAnimationGraphBlend2DSampleAt")
public func MCEEditorGetAnimationGraphBlend2DSampleAt(_ contextPtr: UnsafeRawPointer?,
                                                      _ handle: UnsafePointer<CChar>?,
                                                      _ nodeId: UnsafePointer<CChar>?,
                                                      _ index: Int32,
                                                      _ clipHandleBuffer: UnsafeMutablePointer<CChar>?, _ clipHandleBufferSize: Int32,
                                                      _ xOut: UnsafeMutablePointer<Float>?,
                                                      _ yOut: UnsafeMutablePointer<Float>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handle = animationGraphHandle(from: handle),
          let nodeId,
          let nodeUUID = UUID(uuidString: String(cString: nodeId)),
          let (graph, _) = loadAnimationGraph(context: context, handle: handle),
          let node = graph.nodes.first(where: { $0.id == nodeUUID }),
          node.type == .blend2D,
          let blend = node.blend2D else { return 0 }
    let i = Int(index)
    guard i >= 0, i < blend.samples.count else { return 0 }
    let sample = blend.samples[i]
    _ = writeCString(sample.clipHandle.rawValue.uuidString, to: clipHandleBuffer, max: clipHandleBufferSize)
    xOut?.pointee = sample.position.x
    yOut?.pointee = sample.position.y
    return 1
}

@_cdecl("MCEEditorSetAnimationGraphBlend2DNode")
public func MCEEditorSetAnimationGraphBlend2DNode(_ contextPtr: UnsafeRawPointer?,
                                                  _ handle: UnsafePointer<CChar>?,
                                                  _ nodeId: UnsafePointer<CChar>?,
                                                  _ parameterXName: UnsafePointer<CChar>?,
                                                  _ parameterYName: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handleValue = animationGraphHandle(from: handle),
          let nodeId,
          let nodeUUID = UUID(uuidString: String(cString: nodeId)) else { return 0 }
    let parameterXValue = parameterXName != nil ? String(cString: parameterXName!).trimmingCharacters(in: .whitespacesAndNewlines) : ""
    let parameterYValue = parameterYName != nil ? String(cString: parameterYName!).trimmingCharacters(in: .whitespacesAndNewlines) : ""
    let didSave = mutateAnimationGraph(context: context, handle: handleValue) { graph in
        guard let index = graph.nodes.firstIndex(where: { $0.id == nodeUUID }) else { return false }
        guard graph.nodes[index].type == .blend2D else { return false }
        if graph.nodes[index].blend2D == nil {
            graph.nodes[index].blend2D = AnimationGraphBlend2DDefinition(parameterXName: parameterXValue,
                                                                          parameterYName: parameterYValue,
                                                                          samples: [])
        } else {
            graph.nodes[index].blend2D?.parameterXName = parameterXValue
            graph.nodes[index].blend2D?.parameterYName = parameterYValue
        }
        return true
    }
    return didSave ? 1 : 0
}

@_cdecl("MCEEditorAddAnimationGraphBlend2DSample")
public func MCEEditorAddAnimationGraphBlend2DSample(_ contextPtr: UnsafeRawPointer?,
                                                    _ handle: UnsafePointer<CChar>?,
                                                    _ nodeId: UnsafePointer<CChar>?,
                                                    _ clipHandle: UnsafePointer<CChar>?,
                                                    _ x: Float,
                                                    _ y: Float) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handleValue = animationGraphHandle(from: handle),
          let nodeId,
          let nodeUUID = UUID(uuidString: String(cString: nodeId)),
          let clipHandle,
          let clipUUID = UUID(uuidString: String(cString: clipHandle)) else { return 0 }
    let clipHandleValue = AssetHandle(rawValue: clipUUID)
    let didSave = mutateAnimationGraph(context: context, handle: handleValue) { graph in
        guard let index = graph.nodes.firstIndex(where: { $0.id == nodeUUID }) else { return false }
        guard graph.nodes[index].type == .blend2D else { return false }
        if graph.nodes[index].blend2D == nil {
            graph.nodes[index].blend2D = AnimationGraphBlend2DDefinition(parameterXName: "",
                                                                          parameterYName: "",
                                                                          samples: [])
        }
        graph.nodes[index].blend2D?.samples.append(AnimationGraphBlend2DSampleDefinition(clipHandle: clipHandleValue,
                                                                                          position: SIMD2<Float>(x, y)))
        return true
    }
    return didSave ? 1 : 0
}

@_cdecl("MCEEditorUpdateAnimationGraphBlend2DSample")
public func MCEEditorUpdateAnimationGraphBlend2DSample(_ contextPtr: UnsafeRawPointer?,
                                                       _ handle: UnsafePointer<CChar>?,
                                                       _ nodeId: UnsafePointer<CChar>?,
                                                       _ index: Int32,
                                                       _ clipHandle: UnsafePointer<CChar>?,
                                                       _ x: Float,
                                                       _ y: Float) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handleValue = animationGraphHandle(from: handle),
          let nodeId,
          let nodeUUID = UUID(uuidString: String(cString: nodeId)),
          let clipHandle,
          let clipUUID = UUID(uuidString: String(cString: clipHandle)) else { return 0 }
    let i = Int(index)
    let clipHandleValue = AssetHandle(rawValue: clipUUID)
    let didSave = mutateAnimationGraph(context: context, handle: handleValue) { graph in
        guard let nodeIndex = graph.nodes.firstIndex(where: { $0.id == nodeUUID }) else { return false }
        guard graph.nodes[nodeIndex].type == .blend2D,
              var blend = graph.nodes[nodeIndex].blend2D,
              i >= 0, i < blend.samples.count else { return false }
        blend.samples[i] = AnimationGraphBlend2DSampleDefinition(clipHandle: clipHandleValue,
                                                                 position: SIMD2<Float>(x, y))
        graph.nodes[nodeIndex].blend2D = blend
        return true
    }
    return didSave ? 1 : 0
}

@_cdecl("MCEEditorRemoveAnimationGraphBlend2DSample")
public func MCEEditorRemoveAnimationGraphBlend2DSample(_ contextPtr: UnsafeRawPointer?,
                                                       _ handle: UnsafePointer<CChar>?,
                                                       _ nodeId: UnsafePointer<CChar>?,
                                                       _ index: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handleValue = animationGraphHandle(from: handle),
          let nodeId,
          let nodeUUID = UUID(uuidString: String(cString: nodeId)) else { return 0 }
    let i = Int(index)
    let didSave = mutateAnimationGraph(context: context, handle: handleValue) { graph in
        guard let nodeIndex = graph.nodes.firstIndex(where: { $0.id == nodeUUID }) else { return false }
        guard graph.nodes[nodeIndex].type == .blend2D,
              var blend = graph.nodes[nodeIndex].blend2D,
              i >= 0, i < blend.samples.count else { return false }
        blend.samples.remove(at: i)
        graph.nodes[nodeIndex].blend2D = blend
        return true
    }
    return didSave ? 1 : 0
}

@_cdecl("MCEEditorGetAnimationGraphStateMachineNode")
public func MCEEditorGetAnimationGraphStateMachineNode(_ contextPtr: UnsafeRawPointer?,
                                                       _ handle: UnsafePointer<CChar>?,
                                                       _ nodeId: UnsafePointer<CChar>?,
                                                       _ defaultStateIdBuffer: UnsafeMutablePointer<CChar>?, _ defaultStateIdBufferSize: Int32,
                                                       _ stateCountOut: UnsafeMutablePointer<Int32>?,
                                                       _ transitionCountOut: UnsafeMutablePointer<Int32>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handle = animationGraphHandle(from: handle),
          let nodeUUID = optionalUUID(from: nodeId),
          let (graph, _) = loadAnimationGraph(context: context, handle: handle),
          let node = graph.nodes.first(where: { $0.id == nodeUUID }),
          node.type == .stateMachine,
          let machine = node.stateMachine else { return 0 }
    _ = writeCString(machine.defaultStateID?.uuidString ?? "", to: defaultStateIdBuffer, max: defaultStateIdBufferSize)
    stateCountOut?.pointee = Int32(machine.states.count)
    transitionCountOut?.pointee = Int32(machine.transitions.count)
    return 1
}

@_cdecl("MCEEditorSetAnimationGraphStateMachineDefaultState")
public func MCEEditorSetAnimationGraphStateMachineDefaultState(_ contextPtr: UnsafeRawPointer?,
                                                               _ handle: UnsafePointer<CChar>?,
                                                               _ nodeId: UnsafePointer<CChar>?,
                                                               _ stateId: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handleValue = animationGraphHandle(from: handle),
          let nodeUUID = optionalUUID(from: nodeId) else { return 0 }
    let stateUUID = optionalUUID(from: stateId)
    let didSave = mutateAnimationGraph(context: context, handle: handleValue) { graph in
        guard let nodeIndex = graph.nodes.firstIndex(where: { $0.id == nodeUUID }) else { return false }
        guard graph.nodes[nodeIndex].type == .stateMachine else { return false }
        var machine = graph.nodes[nodeIndex].stateMachine ?? AnimationGraphStateMachineScaffold()
        if let stateUUID, !machine.states.contains(where: { $0.id == stateUUID }) { return false }
        machine.defaultStateID = stateUUID
        graph.nodes[nodeIndex].stateMachine = machine
        return true
    }
    return didSave ? 1 : 0
}

@_cdecl("MCEEditorGetAnimationGraphStateMachineStateAt")
public func MCEEditorGetAnimationGraphStateMachineStateAt(_ contextPtr: UnsafeRawPointer?,
                                                          _ handle: UnsafePointer<CChar>?,
                                                          _ nodeId: UnsafePointer<CChar>?,
                                                          _ index: Int32,
                                                          _ stateIdBuffer: UnsafeMutablePointer<CChar>?, _ stateIdBufferSize: Int32,
                                                          _ nameBuffer: UnsafeMutablePointer<CChar>?, _ nameBufferSize: Int32,
                                                          _ clipHandleBuffer: UnsafeMutablePointer<CChar>?, _ clipHandleBufferSize: Int32,
                                                          _ nodeRefIdBuffer: UnsafeMutablePointer<CChar>?, _ nodeRefIdBufferSize: Int32,
                                                          _ isOneShotOut: UnsafeMutablePointer<UInt32>?,
                                                          _ usesRootMotionOut: UnsafeMutablePointer<UInt32>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handle = animationGraphHandle(from: handle),
          let nodeUUID = optionalUUID(from: nodeId),
          let (graph, _) = loadAnimationGraph(context: context, handle: handle),
          let node = graph.nodes.first(where: { $0.id == nodeUUID }),
          node.type == .stateMachine,
          let machine = node.stateMachine else { return 0 }
    let i = Int(index)
    guard i >= 0, i < machine.states.count else { return 0 }
    let state = machine.states[i]
    _ = writeCString(state.id.uuidString, to: stateIdBuffer, max: stateIdBufferSize)
    _ = writeCString(state.name, to: nameBuffer, max: nameBufferSize)
    _ = writeCString(state.clipHandle?.rawValue.uuidString ?? "", to: clipHandleBuffer, max: clipHandleBufferSize)
    _ = writeCString(state.nodeID?.uuidString ?? "", to: nodeRefIdBuffer, max: nodeRefIdBufferSize)
    isOneShotOut?.pointee = state.isOneShot ? 1 : 0
    usesRootMotionOut?.pointee = state.usesRootMotion ? 1 : 0
    return 1
}

@_cdecl("MCEEditorAddAnimationGraphStateMachineState")
public func MCEEditorAddAnimationGraphStateMachineState(_ contextPtr: UnsafeRawPointer?,
                                                        _ handle: UnsafePointer<CChar>?,
                                                        _ nodeId: UnsafePointer<CChar>?,
                                                        _ name: UnsafePointer<CChar>?,
                                                        _ clipHandle: UnsafePointer<CChar>?,
                                                        _ nodeRefId: UnsafePointer<CChar>?,
                                                        _ isOneShot: UInt32,
                                                        _ usesRootMotion: UInt32,
                                                        _ outStateId: UnsafeMutablePointer<CChar>?, _ outStateIdSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handleValue = animationGraphHandle(from: handle),
          let nodeUUID = optionalUUID(from: nodeId) else { return 0 }
    let stateName = name != nil ? String(cString: name!).trimmingCharacters(in: .whitespacesAndNewlines) : ""
    guard !stateName.isEmpty else { return 0 }
    let stateClipHandle = optionalAssetHandle(from: clipHandle)
    let stateNodeID = optionalUUID(from: nodeRefId)
    if (stateClipHandle != nil) && (stateNodeID != nil) { return 0 }
    let stateID = UUID()
    let didSave = mutateAnimationGraph(context: context, handle: handleValue) { graph in
        guard let nodeIndex = graph.nodes.firstIndex(where: { $0.id == nodeUUID }) else { return false }
        guard graph.nodes[nodeIndex].type == .stateMachine else { return false }
        var machine = graph.nodes[nodeIndex].stateMachine ?? AnimationGraphStateMachineScaffold()
        let usesRootMotionValue = usesRootMotion != 0
        machine.states.append(AnimationGraphStateDefinition(id: stateID,
                                                            name: stateName,
                                                            clipHandle: stateClipHandle,
                                                            nodeID: stateNodeID,
                                                            isOneShot: isOneShot != 0,
                                                            usesRootMotion: usesRootMotionValue,
                                                            rootMotion: defaultRootMotionSettingsForMovementState(name: stateName,
                                                                                                                  usesRootMotion: usesRootMotionValue)))
        if machine.defaultStateID == nil {
            machine.defaultStateID = stateID
        }
        graph.nodes[nodeIndex].stateMachine = machine
        return true
    }
    if didSave {
        _ = writeCString(stateID.uuidString, to: outStateId, max: outStateIdSize)
    }
    return didSave ? 1 : 0
}

@_cdecl("MCEEditorUpdateAnimationGraphStateMachineState")
public func MCEEditorUpdateAnimationGraphStateMachineState(_ contextPtr: UnsafeRawPointer?,
                                                           _ handle: UnsafePointer<CChar>?,
                                                           _ nodeId: UnsafePointer<CChar>?,
                                                           _ stateId: UnsafePointer<CChar>?,
                                                           _ name: UnsafePointer<CChar>?,
                                                           _ clipHandle: UnsafePointer<CChar>?,
                                                           _ nodeRefId: UnsafePointer<CChar>?,
                                                           _ isOneShot: UInt32,
                                                           _ usesRootMotion: UInt32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handleValue = animationGraphHandle(from: handle),
          let nodeUUID = optionalUUID(from: nodeId),
          let stateUUID = optionalUUID(from: stateId) else { return 0 }
    let stateName = name != nil ? String(cString: name!).trimmingCharacters(in: .whitespacesAndNewlines) : ""
    guard !stateName.isEmpty else { return 0 }
    let stateClipHandle = optionalAssetHandle(from: clipHandle)
    let stateNodeID = optionalUUID(from: nodeRefId)
    if (stateClipHandle != nil) == (stateNodeID != nil) { return 0 }
    let didSave = mutateAnimationGraph(context: context, handle: handleValue) { graph in
        guard let nodeIndex = graph.nodes.firstIndex(where: { $0.id == nodeUUID }) else { return false }
        guard graph.nodes[nodeIndex].type == .stateMachine else { return false }
        var machine = graph.nodes[nodeIndex].stateMachine ?? AnimationGraphStateMachineScaffold()
        guard let stateIndex = machine.states.firstIndex(where: { $0.id == stateUUID }) else { return false }
        let usesRootMotionValue = usesRootMotion != 0
        let existingRootMotion = machine.states[stateIndex].rootMotion
        let rootMotionSettings = existingRootMotion
            ?? defaultRootMotionSettingsForMovementState(name: stateName, usesRootMotion: usesRootMotionValue)
        machine.states[stateIndex] = AnimationGraphStateDefinition(id: stateUUID,
                                                                   name: stateName,
                                                                   clipHandle: stateClipHandle,
                                                                   nodeID: stateNodeID,
                                                                   isOneShot: isOneShot != 0,
                                                                   usesRootMotion: usesRootMotionValue,
                                                                   rootMotion: rootMotionSettings)
        graph.nodes[nodeIndex].stateMachine = machine
        return true
    }
    return didSave ? 1 : 0
}

@_cdecl("MCEEditorRemoveAnimationGraphStateMachineState")
public func MCEEditorRemoveAnimationGraphStateMachineState(_ contextPtr: UnsafeRawPointer?,
                                                           _ handle: UnsafePointer<CChar>?,
                                                           _ nodeId: UnsafePointer<CChar>?,
                                                           _ stateId: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handleValue = animationGraphHandle(from: handle),
          let nodeUUID = optionalUUID(from: nodeId),
          let stateUUID = optionalUUID(from: stateId) else { return 0 }
    let didSave = mutateAnimationGraph(context: context, handle: handleValue) { graph in
        guard let nodeIndex = graph.nodes.firstIndex(where: { $0.id == nodeUUID }) else { return false }
        guard graph.nodes[nodeIndex].type == .stateMachine else { return false }
        var machine = graph.nodes[nodeIndex].stateMachine ?? AnimationGraphStateMachineScaffold()
        let countBefore = machine.states.count
        machine.states.removeAll { $0.id == stateUUID }
        guard machine.states.count != countBefore else { return false }
        machine.transitions.removeAll { $0.fromStateID == stateUUID || $0.toStateID == stateUUID }
        if machine.defaultStateID == stateUUID {
            machine.defaultStateID = machine.states.first?.id
        }
        graph.nodes[nodeIndex].stateMachine = machine
        return true
    }
    return didSave ? 1 : 0
}

@_cdecl("MCEEditorGetAnimationGraphStateMachineTransitionAt")
public func MCEEditorGetAnimationGraphStateMachineTransitionAt(_ contextPtr: UnsafeRawPointer?,
                                                               _ handle: UnsafePointer<CChar>?,
                                                               _ nodeId: UnsafePointer<CChar>?,
                                                               _ index: Int32,
                                                               _ transitionIdBuffer: UnsafeMutablePointer<CChar>?, _ transitionIdBufferSize: Int32,
                                                               _ fromStateIdBuffer: UnsafeMutablePointer<CChar>?, _ fromStateIdBufferSize: Int32,
                                                               _ toStateIdBuffer: UnsafeMutablePointer<CChar>?, _ toStateIdBufferSize: Int32,
                                                               _ durationOut: UnsafeMutablePointer<Float>?,
                                                               _ hasMinimumNormalizedTimeOut: UnsafeMutablePointer<UInt32>?,
                                                               _ minimumNormalizedTimeOut: UnsafeMutablePointer<Float>?,
                                                               _ conditionCountOut: UnsafeMutablePointer<Int32>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handle = animationGraphHandle(from: handle),
          let nodeUUID = optionalUUID(from: nodeId),
          let (graph, _) = loadAnimationGraph(context: context, handle: handle),
          let node = graph.nodes.first(where: { $0.id == nodeUUID }),
          node.type == .stateMachine,
          let machine = node.stateMachine else { return 0 }
    let i = Int(index)
    guard i >= 0, i < machine.transitions.count else { return 0 }
    let transition = machine.transitions[i]
    _ = writeCString(transition.id.uuidString, to: transitionIdBuffer, max: transitionIdBufferSize)
    _ = writeCString(transition.fromStateID.uuidString, to: fromStateIdBuffer, max: fromStateIdBufferSize)
    _ = writeCString(transition.toStateID.uuidString, to: toStateIdBuffer, max: toStateIdBufferSize)
    durationOut?.pointee = transition.durationSeconds
    hasMinimumNormalizedTimeOut?.pointee = transition.minimumNormalizedTime != nil ? 1 : 0
    minimumNormalizedTimeOut?.pointee = transition.minimumNormalizedTime ?? 0.0
    conditionCountOut?.pointee = Int32(transition.conditions.count)
    return 1
}

@_cdecl("MCEEditorAddAnimationGraphStateMachineTransition")
public func MCEEditorAddAnimationGraphStateMachineTransition(_ contextPtr: UnsafeRawPointer?,
                                                             _ handle: UnsafePointer<CChar>?,
                                                             _ nodeId: UnsafePointer<CChar>?,
                                                             _ fromStateId: UnsafePointer<CChar>?,
                                                             _ toStateId: UnsafePointer<CChar>?,
                                                             _ duration: Float,
                                                             _ hasMinimumNormalizedTime: UInt32,
                                                             _ minimumNormalizedTime: Float,
                                                             _ outTransitionId: UnsafeMutablePointer<CChar>?, _ outTransitionIdSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handleValue = animationGraphHandle(from: handle),
          let nodeUUID = optionalUUID(from: nodeId),
          let fromStateUUID = optionalUUID(from: fromStateId),
          let toStateUUID = optionalUUID(from: toStateId) else { return 0 }
    let transitionID = UUID()
    let didSave = mutateAnimationGraph(context: context, handle: handleValue) { graph in
        guard let nodeIndex = graph.nodes.firstIndex(where: { $0.id == nodeUUID }) else { return false }
        guard graph.nodes[nodeIndex].type == .stateMachine else { return false }
        var machine = graph.nodes[nodeIndex].stateMachine ?? AnimationGraphStateMachineScaffold()
        guard machine.states.contains(where: { $0.id == fromStateUUID }),
              machine.states.contains(where: { $0.id == toStateUUID }) else { return false }
        machine.transitions.append(AnimationGraphTransitionDefinition(
            id: transitionID,
            fromStateID: fromStateUUID,
            toStateID: toStateUUID,
            durationSeconds: max(0.0, duration),
            minimumNormalizedTime: hasMinimumNormalizedTime != 0 ? min(max(0.0, minimumNormalizedTime), 1.0) : nil,
            conditions: []
        ))
        graph.nodes[nodeIndex].stateMachine = machine
        return true
    }
    if didSave {
        _ = writeCString(transitionID.uuidString, to: outTransitionId, max: outTransitionIdSize)
    }
    return didSave ? 1 : 0
}

@_cdecl("MCEEditorUpdateAnimationGraphStateMachineTransition")
public func MCEEditorUpdateAnimationGraphStateMachineTransition(_ contextPtr: UnsafeRawPointer?,
                                                                _ handle: UnsafePointer<CChar>?,
                                                                _ nodeId: UnsafePointer<CChar>?,
                                                                _ transitionId: UnsafePointer<CChar>?,
                                                                _ fromStateId: UnsafePointer<CChar>?,
                                                                _ toStateId: UnsafePointer<CChar>?,
                                                                _ duration: Float,
                                                                _ hasMinimumNormalizedTime: UInt32,
                                                                _ minimumNormalizedTime: Float) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handleValue = animationGraphHandle(from: handle),
          let nodeUUID = optionalUUID(from: nodeId),
          let transitionUUID = optionalUUID(from: transitionId),
          let fromStateUUID = optionalUUID(from: fromStateId),
          let toStateUUID = optionalUUID(from: toStateId) else { return 0 }
    let didSave = mutateAnimationGraph(context: context, handle: handleValue) { graph in
        guard let nodeIndex = graph.nodes.firstIndex(where: { $0.id == nodeUUID }) else { return false }
        guard graph.nodes[nodeIndex].type == .stateMachine else { return false }
        var machine = graph.nodes[nodeIndex].stateMachine ?? AnimationGraphStateMachineScaffold()
        guard machine.states.contains(where: { $0.id == fromStateUUID }),
              machine.states.contains(where: { $0.id == toStateUUID }),
              let transitionIndex = machine.transitions.firstIndex(where: { $0.id == transitionUUID }) else { return false }
        machine.transitions[transitionIndex].fromStateID = fromStateUUID
        machine.transitions[transitionIndex].toStateID = toStateUUID
        machine.transitions[transitionIndex].durationSeconds = max(0.0, duration)
        machine.transitions[transitionIndex].minimumNormalizedTime = hasMinimumNormalizedTime != 0 ? min(max(0.0, minimumNormalizedTime), 1.0) : nil
        graph.nodes[nodeIndex].stateMachine = machine
        return true
    }
    return didSave ? 1 : 0
}

@_cdecl("MCEEditorRemoveAnimationGraphStateMachineTransition")
public func MCEEditorRemoveAnimationGraphStateMachineTransition(_ contextPtr: UnsafeRawPointer?,
                                                                _ handle: UnsafePointer<CChar>?,
                                                                _ nodeId: UnsafePointer<CChar>?,
                                                                _ transitionId: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handleValue = animationGraphHandle(from: handle),
          let nodeUUID = optionalUUID(from: nodeId),
          let transitionUUID = optionalUUID(from: transitionId) else { return 0 }
    let didSave = mutateAnimationGraph(context: context, handle: handleValue) { graph in
        guard let nodeIndex = graph.nodes.firstIndex(where: { $0.id == nodeUUID }) else { return false }
        guard graph.nodes[nodeIndex].type == .stateMachine else { return false }
        var machine = graph.nodes[nodeIndex].stateMachine ?? AnimationGraphStateMachineScaffold()
        let countBefore = machine.transitions.count
        machine.transitions.removeAll { $0.id == transitionUUID }
        guard machine.transitions.count != countBefore else { return false }
        graph.nodes[nodeIndex].stateMachine = machine
        return true
    }
    return didSave ? 1 : 0
}

@_cdecl("MCEEditorGetAnimationGraphStateMachineConditionAt")
public func MCEEditorGetAnimationGraphStateMachineConditionAt(_ contextPtr: UnsafeRawPointer?,
                                                              _ handle: UnsafePointer<CChar>?,
                                                              _ nodeId: UnsafePointer<CChar>?,
                                                              _ transitionId: UnsafePointer<CChar>?,
                                                              _ index: Int32,
                                                              _ parameterNameBuffer: UnsafeMutablePointer<CChar>?, _ parameterNameBufferSize: Int32,
                                                              _ opBuffer: UnsafeMutablePointer<CChar>?, _ opBufferSize: Int32,
                                                              _ floatValueOut: UnsafeMutablePointer<Float>?,
                                                              _ intValueOut: UnsafeMutablePointer<Int32>?,
                                                              _ boolValueOut: UnsafeMutablePointer<UInt32>?,
                                                              _ hasFloatOut: UnsafeMutablePointer<UInt32>?,
                                                              _ hasIntOut: UnsafeMutablePointer<UInt32>?,
                                                              _ hasBoolOut: UnsafeMutablePointer<UInt32>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handle = animationGraphHandle(from: handle),
          let nodeUUID = optionalUUID(from: nodeId),
          let transitionUUID = optionalUUID(from: transitionId),
          let (graph, _) = loadAnimationGraph(context: context, handle: handle),
          let node = graph.nodes.first(where: { $0.id == nodeUUID }),
          node.type == .stateMachine,
          let machine = node.stateMachine,
          let transition = machine.transitions.first(where: { $0.id == transitionUUID }) else { return 0 }
    let i = Int(index)
    guard i >= 0, i < transition.conditions.count else { return 0 }
    let condition = transition.conditions[i]
    _ = writeCString(condition.parameterName, to: parameterNameBuffer, max: parameterNameBufferSize)
    _ = writeCString(condition.op, to: opBuffer, max: opBufferSize)
    floatValueOut?.pointee = condition.floatValue ?? 0.0
    intValueOut?.pointee = Int32(condition.intValue ?? 0)
    boolValueOut?.pointee = (condition.boolValue ?? false) ? 1 : 0
    hasFloatOut?.pointee = condition.floatValue != nil ? 1 : 0
    hasIntOut?.pointee = condition.intValue != nil ? 1 : 0
    hasBoolOut?.pointee = condition.boolValue != nil ? 1 : 0
    return 1
}

@_cdecl("MCEEditorGetAnimationGraphStateMachineTransitionGraphInfo")
public func MCEEditorGetAnimationGraphStateMachineTransitionGraphInfo(_ contextPtr: UnsafeRawPointer?,
                                                                      _ handle: UnsafePointer<CChar>?,
                                                                      _ nodeId: UnsafePointer<CChar>?,
                                                                      _ transitionId: UnsafePointer<CChar>?,
                                                                      _ hasInlineGraphOut: UnsafeMutablePointer<UInt32>?,
                                                                      _ nodeCountOut: UnsafeMutablePointer<Int32>?,
                                                                      _ linkCountOut: UnsafeMutablePointer<Int32>?,
                                                                      _ outputNodeIdBuffer: UnsafeMutablePointer<CChar>?,
                                                                      _ outputNodeIdBufferSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handle = animationGraphHandle(from: handle),
          let nodeUUID = optionalUUID(from: nodeId),
          let transitionUUID = optionalUUID(from: transitionId),
          let (graph, _) = loadAnimationGraph(context: context, handle: handle),
          let node = graph.nodes.first(where: { $0.id == nodeUUID }),
          node.type == .stateMachine,
          let machine = node.stateMachine,
          let transition = machine.transitions.first(where: { $0.id == transitionUUID }) else { return 0 }
    let inlineGraph = transition.transitionGraph?.inlineGraph
    hasInlineGraphOut?.pointee = inlineGraph != nil ? 1 : 0
    nodeCountOut?.pointee = Int32(inlineGraph?.nodes.count ?? 0)
    linkCountOut?.pointee = Int32(inlineGraph?.links.count ?? 0)
    _ = writeCString(inlineGraph?.outputNodeID?.uuidString ?? "", to: outputNodeIdBuffer, max: outputNodeIdBufferSize)
    return 1
}

@_cdecl("MCEEditorGetAnimationGraphStateMachineTransitionGraphNodeAt")
public func MCEEditorGetAnimationGraphStateMachineTransitionGraphNodeAt(_ contextPtr: UnsafeRawPointer?,
                                                                        _ handle: UnsafePointer<CChar>?,
                                                                        _ nodeId: UnsafePointer<CChar>?,
                                                                        _ transitionId: UnsafePointer<CChar>?,
                                                                        _ index: Int32,
                                                                        _ nodeIdBuffer: UnsafeMutablePointer<CChar>?, _ nodeIdBufferSize: Int32,
                                                                        _ typeBuffer: UnsafeMutablePointer<CChar>?, _ typeBufferSize: Int32,
                                                                        _ titleBuffer: UnsafeMutablePointer<CChar>?, _ titleBufferSize: Int32,
                                                                        _ posXOut: UnsafeMutablePointer<Float>?,
                                                                        _ posYOut: UnsafeMutablePointer<Float>?,
                                                                        _ parameterNameBuffer: UnsafeMutablePointer<CChar>?, _ parameterNameBufferSize: Int32,
                                                                        _ floatValueOut: UnsafeMutablePointer<Float>?,
                                                                        _ hasFloatValueOut: UnsafeMutablePointer<UInt32>?,
                                                                        _ boolValueOut: UnsafeMutablePointer<UInt32>?,
                                                                        _ hasBoolValueOut: UnsafeMutablePointer<UInt32>?,
                                                                        _ synchronizeValueOut: UnsafeMutablePointer<UInt32>?,
                                                                        _ hasSynchronizeValueOut: UnsafeMutablePointer<UInt32>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handle = animationGraphHandle(from: handle),
          let nodeUUID = optionalUUID(from: nodeId),
          let transitionUUID = optionalUUID(from: transitionId),
          let (graph, _) = loadAnimationGraph(context: context, handle: handle),
          let node = graph.nodes.first(where: { $0.id == nodeUUID }),
          node.type == .stateMachine,
          let machine = node.stateMachine,
          let transition = machine.transitions.first(where: { $0.id == transitionUUID }),
          let inlineGraph = transition.transitionGraph?.inlineGraph else { return 0 }
    let i = Int(index)
    guard i >= 0, i < inlineGraph.nodes.count else { return 0 }
    let graphNode = inlineGraph.nodes[i]
    _ = writeCString(graphNode.id.uuidString, to: nodeIdBuffer, max: nodeIdBufferSize)
    _ = writeCString(graphNode.type, to: typeBuffer, max: typeBufferSize)
    _ = writeCString(graphNode.title, to: titleBuffer, max: titleBufferSize)
    posXOut?.pointee = graphNode.position.x
    posYOut?.pointee = graphNode.position.y
    _ = writeCString(graphNode.parameterName ?? "", to: parameterNameBuffer, max: parameterNameBufferSize)
    floatValueOut?.pointee = graphNode.floatValue ?? 0.0
    hasFloatValueOut?.pointee = graphNode.floatValue != nil ? 1 : 0
    boolValueOut?.pointee = (graphNode.boolValue ?? false) ? 1 : 0
    hasBoolValueOut?.pointee = graphNode.boolValue != nil ? 1 : 0
    synchronizeValueOut?.pointee = (graphNode.synchronizeValue ?? false) ? 1 : 0
    hasSynchronizeValueOut?.pointee = graphNode.synchronizeValue != nil ? 1 : 0
    return 1
}

@_cdecl("MCEEditorGetAnimationGraphStateMachineTransitionGraphLinkAt")
public func MCEEditorGetAnimationGraphStateMachineTransitionGraphLinkAt(_ contextPtr: UnsafeRawPointer?,
                                                                        _ handle: UnsafePointer<CChar>?,
                                                                        _ nodeId: UnsafePointer<CChar>?,
                                                                        _ transitionId: UnsafePointer<CChar>?,
                                                                        _ index: Int32,
                                                                        _ linkIdBuffer: UnsafeMutablePointer<CChar>?, _ linkIdBufferSize: Int32,
                                                                        _ fromNodeIdBuffer: UnsafeMutablePointer<CChar>?, _ fromNodeIdBufferSize: Int32,
                                                                        _ fromSlotOut: UnsafeMutablePointer<Int32>?,
                                                                        _ toNodeIdBuffer: UnsafeMutablePointer<CChar>?, _ toNodeIdBufferSize: Int32,
                                                                        _ toSlotOut: UnsafeMutablePointer<Int32>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handle = animationGraphHandle(from: handle),
          let nodeUUID = optionalUUID(from: nodeId),
          let transitionUUID = optionalUUID(from: transitionId),
          let (graph, _) = loadAnimationGraph(context: context, handle: handle),
          let node = graph.nodes.first(where: { $0.id == nodeUUID }),
          node.type == .stateMachine,
          let machine = node.stateMachine,
          let transition = machine.transitions.first(where: { $0.id == transitionUUID }),
          let inlineGraph = transition.transitionGraph?.inlineGraph else { return 0 }
    let i = Int(index)
    guard i >= 0, i < inlineGraph.links.count else { return 0 }
    let link = inlineGraph.links[i]
    _ = writeCString(link.id.uuidString, to: linkIdBuffer, max: linkIdBufferSize)
    _ = writeCString(link.fromNodeID.uuidString, to: fromNodeIdBuffer, max: fromNodeIdBufferSize)
    fromSlotOut?.pointee = Int32(link.fromSlotIndex)
    _ = writeCString(link.toNodeID.uuidString, to: toNodeIdBuffer, max: toNodeIdBufferSize)
    toSlotOut?.pointee = Int32(link.toSlotIndex)
    return 1
}

@_cdecl("MCEEditorSetAnimationGraphStateMachineTransitionGraphOutputNode")
public func MCEEditorSetAnimationGraphStateMachineTransitionGraphOutputNode(_ contextPtr: UnsafeRawPointer?,
                                                                             _ handle: UnsafePointer<CChar>?,
                                                                             _ nodeId: UnsafePointer<CChar>?,
                                                                             _ transitionId: UnsafePointer<CChar>?,
                                                                             _ outputNodeId: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handleValue = animationGraphHandle(from: handle),
          let nodeUUID = optionalUUID(from: nodeId),
          let transitionUUID = optionalUUID(from: transitionId) else { return 0 }
    let outputUUID = optionalUUID(from: outputNodeId)
    let didSave = mutateAnimationGraph(context: context, handle: handleValue) { graph in
        guard let machineNodeIndex = graph.nodes.firstIndex(where: { $0.id == nodeUUID }),
              graph.nodes[machineNodeIndex].type == .stateMachine else { return false }
        var machine = graph.nodes[machineNodeIndex].stateMachine ?? AnimationGraphStateMachineScaffold()
        guard let transitionIndex = machine.transitions.firstIndex(where: { $0.id == transitionUUID }) else { return false }
        var transition = machine.transitions[transitionIndex]
        var reference = transition.transitionGraph ?? AnimationGraphTransitionGraphReference()
        var inlineGraph = reference.inlineGraph ?? AnimationGraphTransitionGraphDefinition(id: reference.transitionGraphID ?? UUID())
        if reference.transitionGraphID == nil {
            reference.transitionGraphID = inlineGraph.id
        }
        if let outputUUID {
            guard let outputNode = inlineGraph.nodes.first(where: { $0.id == outputUUID }) else { return false }
            let normalizedType = outputNode.type
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "_", with: "")
                .replacingOccurrences(of: " ", with: "")
            guard normalizedType == "transitionoutput" else { return false }
            inlineGraph.outputNodeID = outputUUID
        } else {
            inlineGraph.outputNodeID = nil
        }
        reference.inlineGraph = inlineGraph
        transition.transitionGraph = reference
        machine.transitions[transitionIndex] = transition
        graph.nodes[machineNodeIndex].stateMachine = machine
        return true
    }
    return didSave ? 1 : 0
}

@_cdecl("MCEEditorAddAnimationGraphStateMachineTransitionGraphNode")
public func MCEEditorAddAnimationGraphStateMachineTransitionGraphNode(_ contextPtr: UnsafeRawPointer?,
                                                                      _ handle: UnsafePointer<CChar>?,
                                                                      _ nodeId: UnsafePointer<CChar>?,
                                                                      _ transitionId: UnsafePointer<CChar>?,
                                                                      _ type: UnsafePointer<CChar>?,
                                                                      _ title: UnsafePointer<CChar>?,
                                                                      _ posX: Float,
                                                                      _ posY: Float,
                                                                      _ parameterName: UnsafePointer<CChar>?,
                                                                      _ floatValue: Float,
                                                                      _ hasFloatValue: UInt32,
                                                                      _ boolValue: UInt32,
                                                                      _ hasBoolValue: UInt32,
                                                                      _ synchronizeValue: UInt32,
                                                                      _ hasSynchronizeValue: UInt32,
                                                                      _ isOutputNode: UInt32,
                                                                      _ outNodeId: UnsafeMutablePointer<CChar>?,
                                                                      _ outNodeIdSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handleValue = animationGraphHandle(from: handle),
          let nodeUUID = optionalUUID(from: nodeId),
          let transitionUUID = optionalUUID(from: transitionId),
          let type else { return 0 }
    let typeValue = String(cString: type).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !typeValue.isEmpty else { return 0 }
    let normalizedType = typeValue.lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: " ", with: "")
    let defaultTitle: String
    switch normalizedType {
    case "floatconstant": defaultTitle = "Float Constant"
    case "boolconstant": defaultTitle = "Bool Constant"
    case "comparefloatgreater": defaultTitle = "Compare >"
    case "comparefloatless": defaultTitle = "Compare <"
    case "comparefloatequal": defaultTitle = "Compare =="
    case "and": defaultTitle = "Logical AND"
    case "or": defaultTitle = "Logical OR"
    case "not": defaultTitle = "Logical NOT"
    case "parameterfloat": defaultTitle = "Float Parameter"
    case "parameterbool": defaultTitle = "Bool Parameter"
    case "parameterint": defaultTitle = "Int Parameter"
    case "parametertrigger": defaultTitle = "Trigger Parameter"
    case "parameter": defaultTitle = "Parameter"
    case "localfloat": defaultTitle = "Float Local"
    case "localbool": defaultTitle = "Bool Local"
    case "localint": defaultTitle = "Int Local"
    case "setlocalfloat": defaultTitle = "Set Local Float"
    case "setlocalbool": defaultTitle = "Set Local Bool"
    case "setlocalint": defaultTitle = "Set Local Int"
    case "transitionoutput": defaultTitle = "Transition Output"
    default: defaultTitle = "Transition Node"
    }
    let titleValue = title != nil ? String(cString: title!).trimmingCharacters(in: .whitespacesAndNewlines) : ""
    let parameterNameValue = parameterName != nil ? String(cString: parameterName!).trimmingCharacters(in: .whitespacesAndNewlines) : ""
    let newNodeID = UUID()
    let didSave = mutateAnimationGraph(context: context, handle: handleValue) { graph in
        guard let machineNodeIndex = graph.nodes.firstIndex(where: { $0.id == nodeUUID }),
              graph.nodes[machineNodeIndex].type == .stateMachine else { return false }
        var machine = graph.nodes[machineNodeIndex].stateMachine ?? AnimationGraphStateMachineScaffold()
        guard let transitionIndex = machine.transitions.firstIndex(where: { $0.id == transitionUUID }) else { return false }
        var transition = machine.transitions[transitionIndex]
        var reference = transition.transitionGraph ?? AnimationGraphTransitionGraphReference()
        var inlineGraph = reference.inlineGraph ?? AnimationGraphTransitionGraphDefinition(id: reference.transitionGraphID ?? UUID())
        if reference.transitionGraphID == nil {
            reference.transitionGraphID = inlineGraph.id
        }

        let node = AnimationGraphTransitionGraphNodeDefinition(
            id: newNodeID,
            type: typeValue,
            title: titleValue.isEmpty ? defaultTitle : titleValue,
            position: SIMD2<Float>(posX, posY),
            parameterName: parameterNameValue.isEmpty ? nil : parameterNameValue,
            floatValue: hasFloatValue != 0 ? floatValue : nil,
            boolValue: hasBoolValue != 0 ? (boolValue != 0) : nil,
            synchronizeValue: hasSynchronizeValue != 0 ? (synchronizeValue != 0) : nil
        )
        inlineGraph.nodes.append(node)
        if isOutputNode != 0 || normalizedType == "transitionoutput" || inlineGraph.outputNodeID == nil {
            inlineGraph.outputNodeID = newNodeID
        }
        reference.inlineGraph = inlineGraph
        transition.transitionGraph = reference
        machine.transitions[transitionIndex] = transition
        graph.nodes[machineNodeIndex].stateMachine = machine
        return true
    }
    if didSave {
        _ = writeCString(newNodeID.uuidString, to: outNodeId, max: outNodeIdSize)
    }
    return didSave ? 1 : 0
}

@_cdecl("MCEEditorUpdateAnimationGraphStateMachineTransitionGraphNode")
public func MCEEditorUpdateAnimationGraphStateMachineTransitionGraphNode(_ contextPtr: UnsafeRawPointer?,
                                                                         _ handle: UnsafePointer<CChar>?,
                                                                         _ nodeId: UnsafePointer<CChar>?,
                                                                         _ transitionId: UnsafePointer<CChar>?,
                                                                         _ transitionNodeId: UnsafePointer<CChar>?,
                                                                         _ title: UnsafePointer<CChar>?,
                                                                         _ posX: Float,
                                                                         _ posY: Float,
                                                                         _ parameterName: UnsafePointer<CChar>?,
                                                                         _ floatValue: Float,
                                                                         _ hasFloatValue: UInt32,
                                                                         _ boolValue: UInt32,
                                                                         _ hasBoolValue: UInt32,
                                                                         _ synchronizeValue: UInt32,
                                                                         _ hasSynchronizeValue: UInt32,
                                                                         _ isOutputNode: UInt32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handleValue = animationGraphHandle(from: handle),
          let nodeUUID = optionalUUID(from: nodeId),
          let transitionUUID = optionalUUID(from: transitionId),
          let transitionNodeUUID = optionalUUID(from: transitionNodeId) else { return 0 }
    let titleValue = title != nil ? String(cString: title!).trimmingCharacters(in: .whitespacesAndNewlines) : ""
    let parameterNameValue = parameterName != nil ? String(cString: parameterName!).trimmingCharacters(in: .whitespacesAndNewlines) : ""
    let didSave = mutateAnimationGraph(context: context, handle: handleValue) { graph in
        guard let machineNodeIndex = graph.nodes.firstIndex(where: { $0.id == nodeUUID }),
              graph.nodes[machineNodeIndex].type == .stateMachine else { return false }
        var machine = graph.nodes[machineNodeIndex].stateMachine ?? AnimationGraphStateMachineScaffold()
        guard let transitionIndex = machine.transitions.firstIndex(where: { $0.id == transitionUUID }) else { return false }
        var transition = machine.transitions[transitionIndex]
        var reference = transition.transitionGraph ?? AnimationGraphTransitionGraphReference()
        guard var inlineGraph = reference.inlineGraph else { return false }
        if reference.transitionGraphID == nil {
            reference.transitionGraphID = inlineGraph.id
        }
        guard let graphNodeIndex = inlineGraph.nodes.firstIndex(where: { $0.id == transitionNodeUUID }) else { return false }
        inlineGraph.nodes[graphNodeIndex].title = titleValue
        inlineGraph.nodes[graphNodeIndex].position = SIMD2<Float>(posX, posY)
        inlineGraph.nodes[graphNodeIndex].parameterName = parameterNameValue.isEmpty ? nil : parameterNameValue
        inlineGraph.nodes[graphNodeIndex].floatValue = hasFloatValue != 0 ? floatValue : nil
        inlineGraph.nodes[graphNodeIndex].boolValue = hasBoolValue != 0 ? (boolValue != 0) : nil
        inlineGraph.nodes[graphNodeIndex].synchronizeValue = hasSynchronizeValue != 0 ? (synchronizeValue != 0) : nil
        if isOutputNode != 0 {
            inlineGraph.outputNodeID = transitionNodeUUID
        }
        reference.inlineGraph = inlineGraph
        transition.transitionGraph = reference
        machine.transitions[transitionIndex] = transition
        graph.nodes[machineNodeIndex].stateMachine = machine
        return true
    }
    return didSave ? 1 : 0
}

@_cdecl("MCEEditorRemoveAnimationGraphStateMachineTransitionGraphNode")
public func MCEEditorRemoveAnimationGraphStateMachineTransitionGraphNode(_ contextPtr: UnsafeRawPointer?,
                                                                         _ handle: UnsafePointer<CChar>?,
                                                                         _ nodeId: UnsafePointer<CChar>?,
                                                                         _ transitionId: UnsafePointer<CChar>?,
                                                                         _ transitionNodeId: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handleValue = animationGraphHandle(from: handle),
          let nodeUUID = optionalUUID(from: nodeId),
          let transitionUUID = optionalUUID(from: transitionId),
          let transitionNodeUUID = optionalUUID(from: transitionNodeId) else { return 0 }
    let didSave = mutateAnimationGraph(context: context, handle: handleValue) { graph in
        guard let machineNodeIndex = graph.nodes.firstIndex(where: { $0.id == nodeUUID }),
              graph.nodes[machineNodeIndex].type == .stateMachine else { return false }
        var machine = graph.nodes[machineNodeIndex].stateMachine ?? AnimationGraphStateMachineScaffold()
        guard let transitionIndex = machine.transitions.firstIndex(where: { $0.id == transitionUUID }) else { return false }
        var transition = machine.transitions[transitionIndex]
        var reference = transition.transitionGraph ?? AnimationGraphTransitionGraphReference()
        guard var inlineGraph = reference.inlineGraph else { return false }
        let nodeCountBefore = inlineGraph.nodes.count
        inlineGraph.nodes.removeAll { $0.id == transitionNodeUUID }
        guard inlineGraph.nodes.count != nodeCountBefore else { return false }
        inlineGraph.links.removeAll { $0.fromNodeID == transitionNodeUUID || $0.toNodeID == transitionNodeUUID }
        if inlineGraph.outputNodeID == transitionNodeUUID {
            inlineGraph.outputNodeID = inlineGraph.nodes.first {
                $0.type.lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: " ", with: "") == "transitionoutput"
            }?.id
        }
        reference.inlineGraph = inlineGraph
        transition.transitionGraph = reference
        machine.transitions[transitionIndex] = transition
        graph.nodes[machineNodeIndex].stateMachine = machine
        return true
    }
    return didSave ? 1 : 0
}

@_cdecl("MCEEditorAddAnimationGraphStateMachineTransitionGraphLink")
public func MCEEditorAddAnimationGraphStateMachineTransitionGraphLink(_ contextPtr: UnsafeRawPointer?,
                                                                      _ handle: UnsafePointer<CChar>?,
                                                                      _ nodeId: UnsafePointer<CChar>?,
                                                                      _ transitionId: UnsafePointer<CChar>?,
                                                                      _ fromNodeId: UnsafePointer<CChar>?,
                                                                      _ fromSlot: Int32,
                                                                      _ toNodeId: UnsafePointer<CChar>?,
                                                                      _ toSlot: Int32,
                                                                      _ outLinkId: UnsafeMutablePointer<CChar>?,
                                                                      _ outLinkIdSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handleValue = animationGraphHandle(from: handle),
          let nodeUUID = optionalUUID(from: nodeId),
          let transitionUUID = optionalUUID(from: transitionId),
          let fromNodeUUID = optionalUUID(from: fromNodeId),
          let toNodeUUID = optionalUUID(from: toNodeId),
          fromSlot >= 0,
          toSlot >= 0 else { return 0 }
    let newLinkID = UUID()
    let didSave = mutateAnimationGraph(context: context, handle: handleValue) { graph in
        guard let machineNodeIndex = graph.nodes.firstIndex(where: { $0.id == nodeUUID }),
              graph.nodes[machineNodeIndex].type == .stateMachine else { return false }
        var machine = graph.nodes[machineNodeIndex].stateMachine ?? AnimationGraphStateMachineScaffold()
        guard let transitionIndex = machine.transitions.firstIndex(where: { $0.id == transitionUUID }) else { return false }
        var transition = machine.transitions[transitionIndex]
        var reference = transition.transitionGraph ?? AnimationGraphTransitionGraphReference()
        guard var inlineGraph = reference.inlineGraph else { return false }
        guard inlineGraph.nodes.contains(where: { $0.id == fromNodeUUID }) &&
              inlineGraph.nodes.contains(where: { $0.id == toNodeUUID }) else { return false }
        inlineGraph.links.removeAll { $0.toNodeID == toNodeUUID && $0.toSlotIndex == Int(toSlot) }
        inlineGraph.links.append(
            AnimationGraphTransitionGraphLinkDefinition(
                id: newLinkID,
                fromNodeID: fromNodeUUID,
                fromSlotIndex: Int(fromSlot),
                toNodeID: toNodeUUID,
                toSlotIndex: Int(toSlot)
            )
        )
        reference.inlineGraph = inlineGraph
        transition.transitionGraph = reference
        machine.transitions[transitionIndex] = transition
        graph.nodes[machineNodeIndex].stateMachine = machine
        return true
    }
    if didSave {
        _ = writeCString(newLinkID.uuidString, to: outLinkId, max: outLinkIdSize)
    }
    return didSave ? 1 : 0
}

@_cdecl("MCEEditorRemoveAnimationGraphStateMachineTransitionGraphLink")
public func MCEEditorRemoveAnimationGraphStateMachineTransitionGraphLink(_ contextPtr: UnsafeRawPointer?,
                                                                         _ handle: UnsafePointer<CChar>?,
                                                                         _ nodeId: UnsafePointer<CChar>?,
                                                                         _ transitionId: UnsafePointer<CChar>?,
                                                                         _ linkId: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handleValue = animationGraphHandle(from: handle),
          let nodeUUID = optionalUUID(from: nodeId),
          let transitionUUID = optionalUUID(from: transitionId),
          let linkUUID = optionalUUID(from: linkId) else { return 0 }
    let didSave = mutateAnimationGraph(context: context, handle: handleValue) { graph in
        guard let machineNodeIndex = graph.nodes.firstIndex(where: { $0.id == nodeUUID }),
              graph.nodes[machineNodeIndex].type == .stateMachine else { return false }
        var machine = graph.nodes[machineNodeIndex].stateMachine ?? AnimationGraphStateMachineScaffold()
        guard let transitionIndex = machine.transitions.firstIndex(where: { $0.id == transitionUUID }) else { return false }
        var transition = machine.transitions[transitionIndex]
        var reference = transition.transitionGraph ?? AnimationGraphTransitionGraphReference()
        guard var inlineGraph = reference.inlineGraph else { return false }
        let countBefore = inlineGraph.links.count
        inlineGraph.links.removeAll { $0.id == linkUUID }
        guard inlineGraph.links.count != countBefore else { return false }
        reference.inlineGraph = inlineGraph
        transition.transitionGraph = reference
        machine.transitions[transitionIndex] = transition
        graph.nodes[machineNodeIndex].stateMachine = machine
        return true
    }
    return didSave ? 1 : 0
}

@_cdecl("MCEEditorAddAnimationGraphStateMachineCondition")
public func MCEEditorAddAnimationGraphStateMachineCondition(_ contextPtr: UnsafeRawPointer?,
                                                            _ handle: UnsafePointer<CChar>?,
                                                            _ nodeId: UnsafePointer<CChar>?,
                                                            _ transitionId: UnsafePointer<CChar>?,
                                                            _ parameterName: UnsafePointer<CChar>?,
                                                            _ op: UnsafePointer<CChar>?,
                                                            _ floatValue: Float,
                                                            _ intValue: Int32,
                                                            _ boolValue: UInt32,
                                                            _ hasFloat: UInt32,
                                                            _ hasInt: UInt32,
                                                            _ hasBool: UInt32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handleValue = animationGraphHandle(from: handle),
          let nodeUUID = optionalUUID(from: nodeId),
          let transitionUUID = optionalUUID(from: transitionId) else { return 0 }
    let parameterNameValue = parameterName != nil ? String(cString: parameterName!).trimmingCharacters(in: .whitespacesAndNewlines) : ""
    let opValue = op != nil ? String(cString: op!).trimmingCharacters(in: .whitespacesAndNewlines) : ""
    guard !parameterNameValue.isEmpty else { return 0 }
    let didSave = mutateAnimationGraph(context: context, handle: handleValue) { graph in
        guard let nodeIndex = graph.nodes.firstIndex(where: { $0.id == nodeUUID }) else { return false }
        guard graph.nodes[nodeIndex].type == .stateMachine else { return false }
        var machine = graph.nodes[nodeIndex].stateMachine ?? AnimationGraphStateMachineScaffold()
        guard let transitionIndex = machine.transitions.firstIndex(where: { $0.id == transitionUUID }) else { return false }
        machine.transitions[transitionIndex].conditions.append(
            AnimationGraphConditionDefinition(
                parameterName: parameterNameValue,
                op: opValue,
                floatValue: hasFloat != 0 ? floatValue : nil,
                intValue: hasInt != 0 ? Int(intValue) : nil,
                boolValue: hasBool != 0 ? (boolValue != 0) : nil
            )
        )
        graph.nodes[nodeIndex].stateMachine = machine
        return true
    }
    return didSave ? 1 : 0
}

@_cdecl("MCEEditorUpdateAnimationGraphStateMachineCondition")
public func MCEEditorUpdateAnimationGraphStateMachineCondition(_ contextPtr: UnsafeRawPointer?,
                                                               _ handle: UnsafePointer<CChar>?,
                                                               _ nodeId: UnsafePointer<CChar>?,
                                                               _ transitionId: UnsafePointer<CChar>?,
                                                               _ index: Int32,
                                                               _ parameterName: UnsafePointer<CChar>?,
                                                               _ op: UnsafePointer<CChar>?,
                                                               _ floatValue: Float,
                                                               _ intValue: Int32,
                                                               _ boolValue: UInt32,
                                                               _ hasFloat: UInt32,
                                                               _ hasInt: UInt32,
                                                               _ hasBool: UInt32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handleValue = animationGraphHandle(from: handle),
          let nodeUUID = optionalUUID(from: nodeId),
          let transitionUUID = optionalUUID(from: transitionId) else { return 0 }
    let conditionIndex = Int(index)
    let parameterNameValue = parameterName != nil ? String(cString: parameterName!).trimmingCharacters(in: .whitespacesAndNewlines) : ""
    let opValue = op != nil ? String(cString: op!).trimmingCharacters(in: .whitespacesAndNewlines) : ""
    guard !parameterNameValue.isEmpty else { return 0 }
    let didSave = mutateAnimationGraph(context: context, handle: handleValue) { graph in
        guard let nodeIndex = graph.nodes.firstIndex(where: { $0.id == nodeUUID }) else { return false }
        guard graph.nodes[nodeIndex].type == .stateMachine else { return false }
        var machine = graph.nodes[nodeIndex].stateMachine ?? AnimationGraphStateMachineScaffold()
        guard let transitionIndex = machine.transitions.firstIndex(where: { $0.id == transitionUUID }),
              conditionIndex >= 0, conditionIndex < machine.transitions[transitionIndex].conditions.count else { return false }
        machine.transitions[transitionIndex].conditions[conditionIndex] = AnimationGraphConditionDefinition(
            parameterName: parameterNameValue,
            op: opValue,
            floatValue: hasFloat != 0 ? floatValue : nil,
            intValue: hasInt != 0 ? Int(intValue) : nil,
            boolValue: hasBool != 0 ? (boolValue != 0) : nil
        )
        graph.nodes[nodeIndex].stateMachine = machine
        return true
    }
    return didSave ? 1 : 0
}

@_cdecl("MCEEditorRemoveAnimationGraphStateMachineCondition")
public func MCEEditorRemoveAnimationGraphStateMachineCondition(_ contextPtr: UnsafeRawPointer?,
                                                               _ handle: UnsafePointer<CChar>?,
                                                               _ nodeId: UnsafePointer<CChar>?,
                                                               _ transitionId: UnsafePointer<CChar>?,
                                                               _ index: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handleValue = animationGraphHandle(from: handle),
          let nodeUUID = optionalUUID(from: nodeId),
          let transitionUUID = optionalUUID(from: transitionId) else { return 0 }
    let conditionIndex = Int(index)
    let didSave = mutateAnimationGraph(context: context, handle: handleValue) { graph in
        guard let nodeIndex = graph.nodes.firstIndex(where: { $0.id == nodeUUID }) else { return false }
        guard graph.nodes[nodeIndex].type == .stateMachine else { return false }
        var machine = graph.nodes[nodeIndex].stateMachine ?? AnimationGraphStateMachineScaffold()
        guard let transitionIndex = machine.transitions.firstIndex(where: { $0.id == transitionUUID }),
              conditionIndex >= 0, conditionIndex < machine.transitions[transitionIndex].conditions.count else { return false }
        machine.transitions[transitionIndex].conditions.remove(at: conditionIndex)
        graph.nodes[nodeIndex].stateMachine = machine
        return true
    }
    return didSave ? 1 : 0
}

@_cdecl("MCEEditorRemoveAnimationGraphNode")
public func MCEEditorRemoveAnimationGraphNode(_ contextPtr: UnsafeRawPointer?,
                                              _ handle: UnsafePointer<CChar>?,
                                              _ nodeId: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handleValue = animationGraphHandle(from: handle),
          let nodeId,
          let nodeUUID = UUID(uuidString: String(cString: nodeId)) else { return 0 }
    let didSave = mutateAnimationGraph(context: context, handle: handleValue) { graph in
        guard graph.nodes.contains(where: { $0.id == nodeUUID }) else { return false }
        graph.nodes.removeAll { $0.id == nodeUUID }
        graph.links.removeAll { $0.fromNodeID == nodeUUID || $0.toNodeID == nodeUUID }
        if graph.outputNodeID == nodeUUID {
            graph.outputNodeID = graph.nodes.first(where: { $0.type == .outputPose })?.id
        }
        return true
    }
    return didSave ? 1 : 0
}

@_cdecl("MCEEditorSetAnimationGraphOutputNode")
public func MCEEditorSetAnimationGraphOutputNode(_ contextPtr: UnsafeRawPointer?,
                                                 _ handle: UnsafePointer<CChar>?,
                                                 _ nodeId: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handleValue = animationGraphHandle(from: handle) else { return 0 }
    let nodeUUID = nodeId.flatMap { UUID(uuidString: String(cString: $0)) }
    let didSave = mutateAnimationGraph(context: context, handle: handleValue) { graph in
        if let nodeUUID {
            guard graph.nodes.contains(where: { $0.id == nodeUUID }) else { return false }
        }
        graph.outputNodeID = nodeUUID
        return true
    }
    return didSave ? 1 : 0
}

@_cdecl("MCEEditorAddAnimationGraphLink")
public func MCEEditorAddAnimationGraphLink(_ contextPtr: UnsafeRawPointer?,
                                           _ handle: UnsafePointer<CChar>?,
                                           _ fromNodeId: UnsafePointer<CChar>?, _ fromSlot: Int32,
                                           _ toNodeId: UnsafePointer<CChar>?, _ toSlot: Int32,
                                           _ outLinkId: UnsafeMutablePointer<CChar>?, _ outLinkIdSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handleValue = animationGraphHandle(from: handle),
          let fromNodeId, let toNodeId,
          let fromUUID = UUID(uuidString: String(cString: fromNodeId)),
          let toUUID = UUID(uuidString: String(cString: toNodeId)) else { return 0 }
    let linkID = UUID()
    let didSave = mutateAnimationGraph(context: context, handle: handleValue) { graph in
        guard graph.nodes.contains(where: { $0.id == fromUUID }),
              graph.nodes.contains(where: { $0.id == toUUID }) else { return false }
        let duplicate = graph.links.contains {
            $0.fromNodeID == fromUUID &&
            $0.toNodeID == toUUID &&
            $0.fromSlotIndex == Int(fromSlot) &&
            $0.toSlotIndex == Int(toSlot)
        }
        guard !duplicate else { return false }
        graph.links.append(
            AnimationGraphLinkDefinition(
                id: linkID,
                fromNodeID: fromUUID,
                fromSlotIndex: Int(fromSlot),
                toNodeID: toUUID,
                toSlotIndex: Int(toSlot)
            )
        )
        return true
    }
    if didSave {
        _ = writeCString(linkID.uuidString, to: outLinkId, max: outLinkIdSize)
    }
    return didSave ? 1 : 0
}

@_cdecl("MCEEditorRemoveAnimationGraphLink")
public func MCEEditorRemoveAnimationGraphLink(_ contextPtr: UnsafeRawPointer?,
                                              _ handle: UnsafePointer<CChar>?,
                                              _ linkId: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handleValue = animationGraphHandle(from: handle),
          let linkId,
          let linkUUID = UUID(uuidString: String(cString: linkId)) else { return 0 }
    let didSave = mutateAnimationGraph(context: context, handle: handleValue) { graph in
        let countBefore = graph.links.count
        graph.links.removeAll { $0.id == linkUUID }
        return graph.links.count != countBefore
    }
    return didSave ? 1 : 0
}

@_cdecl("MCEEditorValidateAnimationGraph")
public func MCEEditorValidateAnimationGraph(_ contextPtr: UnsafeRawPointer?,
                                            _ handle: UnsafePointer<CChar>?,
                                            _ validOut: UnsafeMutablePointer<UInt32>?,
                                            _ messageBuffer: UnsafeMutablePointer<CChar>?,
                                            _ messageBufferSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handle = animationGraphHandle(from: handle),
          let (graph, _) = loadAnimationGraph(context: context, handle: handle) else { return 0 }
    let result = AnimationGraphCompiler.compile(asset: graph) { clipHandle in
        context.engineContext.assets.animationClip(handle: clipHandle) != nil
    }
    switch result {
    case .success:
        validOut?.pointee = 1
        _ = writeCString("Valid", to: messageBuffer, max: messageBufferSize)
    case let .failure(error):
        validOut?.pointee = 0
        let messages: [String]
        switch error {
        case let .invalidGraph(diagnostics):
            messages = diagnostics
        }
        _ = writeCString(messages.joined(separator: "\n"), to: messageBuffer, max: messageBufferSize)
    }
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

@_cdecl("MCEImportBeginForHandle")
public func MCEImportBeginForHandle(_ contextPtr: UnsafeRawPointer?,
                                    _ handle: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr) else { return 0 }
    guard let handle else { return 0 }
    let handleString = String(cString: handle)
    guard let uuid = UUID(uuidString: handleString) else { return 0 }
    let assetHandle = AssetHandle(rawValue: uuid)
    return context.importController.beginImport(handle: assetHandle) ? 1 : 0
}

@_cdecl("MCEImportCanReimportHandle")
public func MCEImportCanReimportHandle(_ contextPtr: UnsafeRawPointer?,
                                       _ handle: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr) else { return 0 }
    guard let handle else { return 0 }
    let handleString = String(cString: handle)
    guard let uuid = UUID(uuidString: handleString) else { return 0 }
    let assetHandle = AssetHandle(rawValue: uuid)
    guard let metadata = context.editorProjectManager.assetMetadataSnapshot().first(where: { $0.handle == assetHandle }) else { return 0 }
    let hasSource = !(metadata.importSettings["sourcePathAbs"] ?? "").isEmpty
    let isSupported = metadata.type == .texture || metadata.type == .environment || metadata.type == .model
    return (hasSource && isSupported) ? 1 : 0
}

@_cdecl("MCEImportIsOpen")
public func MCEImportIsOpen(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    guard let context = resolveContext(contextPtr) else { return 0 }
    return context.importController.isOpen ? 1 : 0
}

@_cdecl("MCEImportIsReimport")
public func MCEImportIsReimport(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    guard let context = resolveContext(contextPtr) else { return 0 }
    return context.importController.isReimport ? 1 : 0
}

@_cdecl("MCEImportCancel")
public func MCEImportCancel(_ contextPtr: UnsafeRawPointer?) {
    guard let context = resolveContext(contextPtr) else { return }
    context.importController.cancel()
}

@_cdecl("MCEImportCommit")
public func MCEImportCommit(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    guard let context = resolveContext(contextPtr) else { return 0 }
    return context.importController.commit() ? 1 : 0
}

@_cdecl("MCEImportGetPendingAssetType")
public func MCEImportGetPendingAssetType(_ contextPtr: UnsafeRawPointer?) -> Int32 {
    guard let context = resolveContext(contextPtr) else { return AssetTypes.code(for: .unknown) }
    return AssetTypes.code(for: context.importController.assetType())
}

@_cdecl("MCEImportGetSourceFilename")
public func MCEImportGetSourceFilename(_ contextPtr: UnsafeRawPointer?,
                                       _ buffer: UnsafeMutablePointer<CChar>?,
                                       _ bufferSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr) else { return 0 }
    return writeCString(context.importController.sourceFilename(), to: buffer, max: bufferSize) > 0 ? 1 : 0
}

@_cdecl("MCEImportGetDestinationFolder")
public func MCEImportGetDestinationFolder(_ contextPtr: UnsafeRawPointer?,
                                          _ buffer: UnsafeMutablePointer<CChar>?,
                                          _ bufferSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr) else { return 0 }
    return writeCString(context.importController.destinationFolderName(), to: buffer, max: bufferSize) > 0 ? 1 : 0
}

@_cdecl("MCEImportGetOptionBool")
public func MCEImportGetOptionBool(_ contextPtr: UnsafeRawPointer?,
                                   _ key: UnsafePointer<CChar>?,
                                   _ defaultValue: UInt32) -> UInt32 {
    guard let context = resolveContext(contextPtr) else { return defaultValue }
    guard let key else { return defaultValue }
    let value = context.importController.optionBool(String(cString: key), default: defaultValue != 0)
    return value ? 1 : 0
}

@_cdecl("MCEImportSetOptionBool")
public func MCEImportSetOptionBool(_ contextPtr: UnsafeRawPointer?,
                                   _ key: UnsafePointer<CChar>?,
                                   _ value: UInt32) {
    guard let context = resolveContext(contextPtr) else { return }
    guard let key else { return }
    context.importController.setOptionBool(String(cString: key), value: value != 0)
}

@_cdecl("MCEImportGetOptionString")
public func MCEImportGetOptionString(_ contextPtr: UnsafeRawPointer?,
                                     _ key: UnsafePointer<CChar>?,
                                     _ buffer: UnsafeMutablePointer<CChar>?,
                                     _ bufferSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr) else { return 0 }
    guard let key else { return 0 }
    let value = context.importController.optionString(String(cString: key))
    return writeCString(value, to: buffer, max: bufferSize) > 0 ? 1 : 0
}

@_cdecl("MCEImportSetOptionString")
public func MCEImportSetOptionString(_ contextPtr: UnsafeRawPointer?,
                                     _ key: UnsafePointer<CChar>?,
                                     _ value: UnsafePointer<CChar>?) {
    guard let context = resolveContext(contextPtr) else { return }
    guard let key, let value else { return }
    context.importController.setOptionString(String(cString: key), value: String(cString: value))
}

@_cdecl("MCEImportGetOptionFloat")
public func MCEImportGetOptionFloat(_ contextPtr: UnsafeRawPointer?,
                                    _ key: UnsafePointer<CChar>?,
                                    _ defaultValue: Float) -> Float {
    guard let context = resolveContext(contextPtr) else { return defaultValue }
    guard let key else { return defaultValue }
    return context.importController.optionFloat(String(cString: key), default: defaultValue)
}

@_cdecl("MCEImportSetOptionFloat")
public func MCEImportSetOptionFloat(_ contextPtr: UnsafeRawPointer?,
                                    _ key: UnsafePointer<CChar>?,
                                    _ value: Float) {
    guard let context = resolveContext(contextPtr) else { return }
    guard let key else { return }
    context.importController.setOptionFloat(String(cString: key), value: value)
}

@_cdecl("MCEImportGetMeshCount")
public func MCEImportGetMeshCount(_ contextPtr: UnsafeRawPointer?) -> Int32 {
    guard let context = resolveContext(contextPtr) else { return 0 }
    return Int32(context.importController.meshCount())
}

@_cdecl("MCEImportGetSubmeshCount")
public func MCEImportGetSubmeshCount(_ contextPtr: UnsafeRawPointer?) -> Int32 {
    guard let context = resolveContext(contextPtr) else { return 0 }
    return Int32(context.importController.submeshCount())
}

@_cdecl("MCEImportGetMaterialCount")
public func MCEImportGetMaterialCount(_ contextPtr: UnsafeRawPointer?) -> Int32 {
    guard let context = resolveContext(contextPtr) else { return 0 }
    return Int32(context.importController.materialCount())
}

@_cdecl("MCEImportGetMaterialNameAt")
public func MCEImportGetMaterialNameAt(_ contextPtr: UnsafeRawPointer?,
                                       _ index: Int32,
                                       _ buffer: UnsafeMutablePointer<CChar>?,
                                       _ bufferSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr) else { return 0 }
    let name = context.importController.materialName(at: Int(index))
    return writeCString(name, to: buffer, max: bufferSize) > 0 ? 1 : 0
}

@_cdecl("MCEImportGetTextureCount")
public func MCEImportGetTextureCount(_ contextPtr: UnsafeRawPointer?) -> Int32 {
    guard let context = resolveContext(contextPtr) else { return 0 }
    return Int32(context.importController.textureCount())
}

@_cdecl("MCEImportGetTextureNameAt")
public func MCEImportGetTextureNameAt(_ contextPtr: UnsafeRawPointer?,
                                      _ index: Int32,
                                      _ buffer: UnsafeMutablePointer<CChar>?,
                                      _ bufferSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr) else { return 0 }
    let name = context.importController.textureName(at: Int(index))
    return writeCString(name, to: buffer, max: bufferSize) > 0 ? 1 : 0
}

@_cdecl("MCEImportGetWarningCount")
public func MCEImportGetWarningCount(_ contextPtr: UnsafeRawPointer?) -> Int32 {
    guard let context = resolveContext(contextPtr) else { return 0 }
    return Int32(context.importController.warningCount())
}

@_cdecl("MCEImportGetWarningAt")
public func MCEImportGetWarningAt(_ contextPtr: UnsafeRawPointer?,
                                  _ index: Int32,
                                  _ buffer: UnsafeMutablePointer<CChar>?,
                                  _ bufferSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr) else { return 0 }
    let warning = context.importController.warning(at: Int(index))
    return writeCString(warning, to: buffer, max: bufferSize) > 0 ? 1 : 0
}

@_cdecl("MCEImportGetMeshHasUVs")
public func MCEImportGetMeshHasUVs(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    guard let context = resolveContext(contextPtr) else { return 0 }
    return context.importController.hasUVs() ? 1 : 0
}

@_cdecl("MCEImportGetMeshHasNormals")
public func MCEImportGetMeshHasNormals(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    guard let context = resolveContext(contextPtr) else { return 0 }
    return context.importController.hasNormals() ? 1 : 0
}

@_cdecl("MCEImportGetMeshHasTangents")
public func MCEImportGetMeshHasTangents(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    guard let context = resolveContext(contextPtr) else { return 0 }
    return context.importController.hasTangents() ? 1 : 0
}

@_cdecl("MCEImportGetCommitHandle")
public func MCEImportGetCommitHandle(_ contextPtr: UnsafeRawPointer?,
                                     _ buffer: UnsafeMutablePointer<CChar>?,
                                     _ bufferSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr) else { return 0 }
    guard let result = context.importController.commitResult else { return 0 }
    let snapshot = context.editorProjectManager.assetMetadataSnapshot()
    if snapshot.contains(where: { $0.handle == result.primaryHandle }) {
        return writeCString(result.primaryHandle.rawValue.uuidString, to: buffer, max: bufferSize) > 0 ? 1 : 0
    }

    if let fallbackPath = result.writtenPaths.first,
       let resolved = snapshot.first(where: { $0.sourcePath == fallbackPath }) {
#if DEBUG
        context.engineContext.log.logDebug(
            "Import commit handle remapped from stale handle \(result.primaryHandle.rawValue.uuidString) to \(resolved.handle.rawValue.uuidString) via path \(fallbackPath)",
            category: .assets
        )
#endif
        return writeCString(resolved.handle.rawValue.uuidString, to: buffer, max: bufferSize) > 0 ? 1 : 0
    }

    return writeCString(result.primaryHandle.rawValue.uuidString, to: buffer, max: bufferSize) > 0 ? 1 : 0
}

@_cdecl("MCEImportGetCommitAssetType")
public func MCEImportGetCommitAssetType(_ contextPtr: UnsafeRawPointer?) -> Int32 {
    guard let context = resolveContext(contextPtr) else { return AssetTypes.code(for: .unknown) }
    return AssetTypes.code(for: context.importController.commitAssetType)
}

@_cdecl("MCEImportGetCommitMeshPath")
public func MCEImportGetCommitMeshPath(_ contextPtr: UnsafeRawPointer?,
                                       _ buffer: UnsafeMutablePointer<CChar>?,
                                       _ bufferSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let result = context.importController.commitResult,
          let path = result.meshPath else { return 0 }
    return writeCString(path, to: buffer, max: bufferSize) > 0 ? 1 : 0
}

@_cdecl("MCEImportGetCommitSkeletonHandle")
public func MCEImportGetCommitSkeletonHandle(_ contextPtr: UnsafeRawPointer?,
                                             _ buffer: UnsafeMutablePointer<CChar>?,
                                             _ bufferSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handle = context.importController.commitResult?.skeletonHandle else { return 0 }
    return writeCString(handle.rawValue.uuidString, to: buffer, max: bufferSize) > 0 ? 1 : 0
}

@_cdecl("MCEImportGetCommitDefaultClipHandle")
public func MCEImportGetCommitDefaultClipHandle(_ contextPtr: UnsafeRawPointer?,
                                                _ buffer: UnsafeMutablePointer<CChar>?,
                                                _ bufferSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let handle = context.importController.commitResult?.defaultClipHandle else { return 0 }
    return writeCString(handle.rawValue.uuidString, to: buffer, max: bufferSize) > 0 ? 1 : 0
}

@_cdecl("MCEImportGetCommitSubmeshMaterialHandles")
public func MCEImportGetCommitSubmeshMaterialHandles(_ contextPtr: UnsafeRawPointer?,
                                                     _ buffer: UnsafeMutablePointer<CChar>?,
                                                     _ bufferSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let result = context.importController.commitResult else { return 0 }
    let raw = result.submeshMaterialHandles.map { $0.rawValue.uuidString }.joined(separator: ",")
    return writeCString(raw, to: buffer, max: bufferSize) > 0 ? 1 : 0
}

@_cdecl("MCEImportClearCommitResult")
public func MCEImportClearCommitResult(_ contextPtr: UnsafeRawPointer?) {
    guard let context = resolveContext(contextPtr) else { return }
    context.importController.clearCommitResult()
}

@_cdecl("MCEImportGetLastError")
public func MCEImportGetLastError(_ contextPtr: UnsafeRawPointer?,
                                  _ buffer: UnsafeMutablePointer<CChar>?,
                                  _ bufferSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr) else { return 0 }
    return writeCString(context.importController.lastErrorMessage, to: buffer, max: bufferSize) > 0 ? 1 : 0
}

private func handleFromCString(_ cString: UnsafePointer<CChar>?) -> AssetHandle? {
    guard let cString else { return nil }
    let value = String(cString: cString)
    guard let uuid = UUID(uuidString: value) else { return nil }
    return AssetHandle(rawValue: uuid)
}

private func defaultRootMotionSettingsForMovementState(name: String,
                                                       usesRootMotion: Bool) -> AnimationGraphStateDefinition.RootMotionSettings? {
    guard usesRootMotion else { return nil }
    let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard normalized == "movement" else { return nil }
    return AnimationGraphStateDefinition.RootMotionSettings(
        applyTranslation: false,
        applyRotation: false,
        consumeTranslation: false,
        consumeRotation: false
    )
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
