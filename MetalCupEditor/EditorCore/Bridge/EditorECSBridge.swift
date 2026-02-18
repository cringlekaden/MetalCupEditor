/// EditorECSBridge.swift
/// Defines ECS bridge helpers for editor UI integration.
/// Created by Kaden Cringle.

import Foundation
import MetalCupEngine
import simd

private enum EditorComponentType: Int32 {
    case name = 0
    case transform = 1
    case meshRenderer = 2
    case light = 3
    case skyLight = 4
    case material = 5
    case camera = 6
}

#if DEBUG
private enum ResolveContextDebug {
    static var invalidCount: Int = 0
}
#endif

private func resolveContext(_ contextPtr: UnsafeRawPointer?) -> MCEContext? {
    guard let contextPtr else { return nil }
    let raw = UInt(bitPattern: contextPtr)
    if raw < 0x1000 {
        #if DEBUG
        if ResolveContextDebug.invalidCount == 0 {
            ResolveContextDebug.invalidCount += 1
            assertionFailure("Invalid MCEContext pointer (too small) passed to bridge.")
        }
        #endif
        return nil
    }
    #if DEBUG
    // Note: Do not add per-call logging here; only assert once on invalid inputs.
    #endif
    let object = Unmanaged<AnyObject>.fromOpaque(contextPtr).takeUnretainedValue()
    guard let context = object as? MCEContext else { return nil }
    #if DEBUG
    if context.debugMagic != MCEContext.debugMagicExpected ||
        context.debugVersion != MCEContext.debugVersionExpected {
        if ResolveContextDebug.invalidCount == 0 {
            ResolveContextDebug.invalidCount += 1
            assertionFailure("Invalid MCEContext pointer passed to bridge.")
        }
        return nil
    }
    #endif
    return context
}


private func editorECS(_ context: MCEContext) -> SceneECS? {
    return context.editorSceneController.activeScene()?.ecs
}

private func entity(from idPointer: UnsafePointer<CChar>?, context: MCEContext) -> Entity? {
    guard let idPointer else { return nil }
    let idString = String(cString: idPointer)
    guard let uuid = UUID(uuidString: idString) else { return nil }
    return editorECS(context)?.entity(with: uuid)
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

private func handleFromString(_ string: String) -> AssetHandle? {
    guard !string.isEmpty, let uuid = UUID(uuidString: string) else { return nil }
    return AssetHandle(rawValue: uuid)
}

private func prefabURL(from handleString: String, context: MCEContext) -> URL? {
    guard let handle = handleFromString(handleString) else { return nil }
    return context.editorProjectManager.assetURL(for: handle)
}

private func componentsDocument(for entity: Entity, ecs: SceneECS) -> ComponentsDocument {
    return ComponentsDocument(
        name: ecs.get(NameComponent.self, for: entity).map { NameComponentDTO(name: $0.name) },
        transform: ecs.get(TransformComponent.self, for: entity).map { component in
            TransformComponentDTO(
                position: Vector3DTO(component.position),
                rotation: Vector3DTO(component.rotation),
                scale: Vector3DTO(component.scale)
            )
        },
        layer: ecs.get(LayerComponent.self, for: entity).map { component in
            LayerComponentDTO(layerIndex: component.index)
        },
        meshRenderer: ecs.get(MeshRendererComponent.self, for: entity).map { component in
            MeshRendererComponentDTO(
                meshHandle: component.meshHandle,
                materialHandle: component.materialHandle,
                material: component.material.map { MaterialDTO(material: $0) },
                albedoMapHandle: component.albedoMapHandle,
                normalMapHandle: component.normalMapHandle,
                metallicMapHandle: component.metallicMapHandle,
                roughnessMapHandle: component.roughnessMapHandle,
                mrMapHandle: component.mrMapHandle,
                aoMapHandle: component.aoMapHandle,
                emissiveMapHandle: component.emissiveMapHandle
            )
        },
        materialComponent: ecs.get(MaterialComponent.self, for: entity).map { component in
            MaterialComponentDTO(materialHandle: component.materialHandle)
        },
        light: ecs.get(LightComponent.self, for: entity).map { component in
            LightComponentDTO(
                type: LightTypeDTO(from: component.type),
                data: LightDataDTO(from: component.data),
                direction: Vector3DTO(component.direction),
                range: component.range,
                innerConeCos: component.innerConeCos,
                outerConeCos: component.outerConeCos
            )
        },
        lightOrbit: ecs.get(LightOrbitComponent.self, for: entity).map { component in
            LightOrbitComponentDTO(component: component)
        },
        camera: ecs.get(CameraComponent.self, for: entity).map { component in
            CameraComponentDTO(component: component)
        },
        sky: ecs.get(SkyComponent.self, for: entity).map { component in
            SkyComponentDTO(environmentMapHandle: component.environmentMapHandle)
        },
        skyLight: ecs.get(SkyLightComponent.self, for: entity).map { component in
            SkyLightComponentDTO(
                mode: component.mode.rawValue,
                enabled: component.enabled,
                intensity: component.intensity,
                skyTint: Vector3DTO(component.skyTint),
                turbidity: component.turbidity,
                azimuthDegrees: component.azimuthDegrees,
                elevationDegrees: component.elevationDegrees,
                hdriHandle: component.hdriHandle,
                realtimeUpdate: component.realtimeUpdate
            )
        },
        skyLightTag: ecs.get(SkyLightTag.self, for: entity).map { _ in TagComponentDTO() },
        skySunTag: ecs.get(SkySunTag.self, for: entity).map { _ in TagComponentDTO() }
    )
}

private func allSkyEntities(ecs: SceneECS) -> [Entity] {
    return ecs.allEntities().filter { ecs.get(SkyLightComponent.self, for: $0) != nil }
}

private func ensureActiveSkyEntity(ecs: SceneECS, logCenter: EditorLogCenter) -> Entity? {
    if let active = ecs.activeSkyLight()?.0 {
        return active
    }
    let skyEntities = allSkyEntities(ecs: ecs)
    guard let first = skyEntities.first else { return nil }
    ecs.add(SkyLightTag(), to: first)
    logCenter.logInfo("Sky active assigned: \(first.id.uuidString)", category: .scene)
    return first
}

private func setActiveSky(ecs: SceneECS, entity: Entity, logCenter: EditorLogCenter) {
    for skyEntity in allSkyEntities(ecs: ecs) {
        if skyEntity.id != entity.id {
            ecs.remove(SkyLightTag.self, from: skyEntity)
        }
    }
    ecs.add(SkyLightTag(), to: entity)
    if var sky = ecs.get(SkyLightComponent.self, for: entity) {
        sky.needsRegenerate = true
        ecs.add(sky, to: entity)
        logCenter.logInfo("Sky regenerate requested: \(entity.id.uuidString)", category: .scene)
    }
    logCenter.logInfo("Sky active set: \(entity.id.uuidString)", category: .scene)
}

private func findEditorCamera(ecs: SceneECS) -> (Entity, TransformComponent, CameraComponent)? {
    var result: (Entity, TransformComponent, CameraComponent)?
    ecs.viewCameras { entity, transform, camera in
        if result != nil { return }
        guard camera.isEditor, let transform else { return }
        result = (entity, transform, camera)
    }
    return result
}

private func hasPrimaryRuntimeCamera(ecs: SceneECS) -> Bool {
    var hasPrimary = false
    ecs.viewCameras { _, _, camera in
        if camera.isEditor { return }
        if camera.isPrimary { hasPrimary = true }
    }
    return hasPrimary
}

private func setPrimaryCamera(ecs: SceneECS, entity: Entity) {
    ecs.viewCameras { otherEntity, _, camera in
        var updated = camera
        if otherEntity == entity {
            updated.isPrimary = true
        } else if !camera.isEditor {
            updated.isPrimary = false
        } else {
            return
        }
        ecs.add(updated, to: otherEntity)
    }
}

@_cdecl("MCEEditorGetEntityCount")
public func MCEEditorGetEntityCount(_ contextPtr: UnsafeRawPointer?) -> Int32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context) else { return 0 }
    return Int32(ecs.allEntities().count)
}

@_cdecl("MCEEditorGetEntityIdAt")
public func MCEEditorGetEntityIdAt(_ contextPtr: UnsafeRawPointer?,
                                   _ index: Int32,
                                   _ buffer: UnsafeMutablePointer<CChar>?,
                                   _ bufferSize: Int32) -> Int32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          index >= 0 else { return 0 }
    let entities = ecs.allEntities().sorted { lhs, rhs in
        let lhsName = ecs.get(NameComponent.self, for: lhs)?.name ?? ""
        let rhsName = ecs.get(NameComponent.self, for: rhs)?.name ?? ""
        if lhsName != rhsName {
            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
    guard index < Int32(entities.count) else { return 0 }
    let idString = entities[Int(index)].id.uuidString
    return writeCString(idString, to: buffer, max: bufferSize)
}

@_cdecl("MCEEditorGetEntityName")
public func MCEEditorGetEntityName(_ contextPtr: UnsafeRawPointer?,
                                   _ entityId: UnsafePointer<CChar>?,
                                   _ buffer: UnsafeMutablePointer<CChar>?,
                                   _ bufferSize: Int32) -> Int32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return 0 }
    let name = ecs.get(NameComponent.self, for: entity)?.name ?? ""
    return writeCString(name, to: buffer, max: bufferSize)
}

@_cdecl("MCEEditorEntityExists")
public func MCEEditorEntityExists(_ contextPtr: UnsafeRawPointer?, _ entityId: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let _ = entity(from: entityId, context: context) else { return 0 }
    return 1
}

@_cdecl("MCEEditorSetEntityName")
public func MCEEditorSetEntityName(_ contextPtr: UnsafeRawPointer?,
                                   _ entityId: UnsafePointer<CChar>?,
                                   _ name: UnsafePointer<CChar>?) {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let name else { return }
    let newName = String(cString: name)
    ecs.add(NameComponent(name: newName), to: entity)
    context.editorProjectManager.notifySceneMutation()
    context.editorLogCenter.logInfo("Entity renamed: \(entity.id.uuidString) \(newName)", category: .scene)
}

@_cdecl("MCEEditorCreateEntity")
public func MCEEditorCreateEntity(_ contextPtr: UnsafeRawPointer?,
                                  _ name: UnsafePointer<CChar>?,
                                  _ outId: UnsafeMutablePointer<CChar>?,
                                  _ outIdSize: Int32) -> Int32 {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          let ecs = editorECS(context) else { return 0 }
    let entityName = name != nil ? String(cString: name!) : "Entity"
    let entity = ecs.createEntity(name: entityName)
    context.editorProjectManager.notifySceneMutation()
    return writeCString(entity.id.uuidString, to: outId, max: outIdSize)
}

@_cdecl("MCEEditorCreateMeshEntity")
public func MCEEditorCreateMeshEntity(_ contextPtr: UnsafeRawPointer?,
                                      _ meshType: Int32,
                                      _ outId: UnsafeMutablePointer<CChar>?,
                                      _ outIdSize: Int32) -> Int32 {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          let ecs = editorECS(context) else { return 0 }
    let entity: Entity
    let meshHandle: AssetHandle?

    switch meshType {
    case 0:
        entity = ecs.createEntity(name: "Cube")
        meshHandle = BuiltinAssets.cubeMesh
    case 1:
        entity = ecs.createEntity(name: "Sphere")
        meshHandle = AssetManager.handle(forSourcePath: "sphere/sphere.obj")
    case 2:
        entity = ecs.createEntity(name: "Plane")
        meshHandle = BuiltinAssets.planeMesh
    default:
        entity = ecs.createEntity(name: "Mesh")
        meshHandle = nil
    }

    ecs.add(TransformComponent(), to: entity)
    ecs.add(MeshRendererComponent(meshHandle: meshHandle), to: entity)
    context.editorProjectManager.notifySceneMutation()
    return writeCString(entity.id.uuidString, to: outId, max: outIdSize)
}

@_cdecl("MCEEditorCreateMeshEntityFromHandle")
public func MCEEditorCreateMeshEntityFromHandle(_ contextPtr: UnsafeRawPointer?,
                                                _ meshHandle: UnsafePointer<CChar>?,
                                                _ outId: UnsafeMutablePointer<CChar>?,
                                                _ outIdSize: Int32) -> Int32 {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          let ecs = editorECS(context) else { return 0 }
    let meshString = meshHandle != nil ? String(cString: meshHandle!) : ""
    let meshHandleValue = handleFromString(meshString)
    let entity = ecs.createEntity(name: "Mesh")
    ecs.add(TransformComponent(), to: entity)
    ecs.add(MeshRendererComponent(meshHandle: meshHandleValue), to: entity)
    context.editorProjectManager.notifySceneMutation()
    return writeCString(entity.id.uuidString, to: outId, max: outIdSize)
}

@_cdecl("MCEEditorInstantiatePrefabFromHandle")
public func MCEEditorInstantiatePrefabFromHandle(_ contextPtr: UnsafeRawPointer?,
                                                 _ prefabHandle: UnsafePointer<CChar>?,
                                                 _ outId: UnsafeMutablePointer<CChar>?,
                                                 _ outIdSize: Int32) -> Int32 {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          let ecs = editorECS(context),
          let prefabHandle else { return 0 }
    let handleString = String(cString: prefabHandle)
    guard let url = prefabURL(from: handleString, context: context) else { return 0 }
    guard let prefabHandleValue = handleFromString(handleString) else { return 0 }
    do {
        let prefab = try PrefabSerializer.load(from: url)
        guard let scene = context.editorSceneController.activeScene() else { return 0 }
        let created = scene.instantiate(prefab: prefab, prefabHandle: prefabHandleValue)
        context.editorProjectManager.notifySceneMutation()
        if let first = created.first {
            return writeCString(first.id.uuidString, to: outId, max: outIdSize)
        }
        return 0
    } catch {
        context.editorAlertCenter.enqueueError("Failed to instantiate prefab: \(error.localizedDescription)")
        return 0
    }
}

@_cdecl("MCEEditorCreatePrefabFromEntity")
public func MCEEditorCreatePrefabFromEntity(_ contextPtr: UnsafeRawPointer?,
                                            _ entityId: UnsafePointer<CChar>?,
                                            _ outPath: UnsafeMutablePointer<CChar>?,
                                            _ outPathSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          let entity = entity(from: entityId, context: context),
          let scene = context.editorSceneController.activeScene() else { return 0 }
    let name = scene.ecs.get(NameComponent.self, for: entity)?.name ?? "Prefab"
    let components = componentsDocument(for: entity, ecs: scene.ecs)
    let prefabEntity = PrefabEntityDocument(localId: entity.id, parentLocalId: nil, components: components)
    let prefab = PrefabDocument(name: name, entities: [prefabEntity])
    guard let relativePath = AssetOps.createPrefab(context: contextPtr, prefab: prefab, relativePath: "Prefabs", name: name) else { return 0 }
    _ = writeCString(relativePath, to: outPath, max: outPathSize)
    return 1
}

@_cdecl("MCEEditorCreateLightEntity")
public func MCEEditorCreateLightEntity(_ contextPtr: UnsafeRawPointer?,
                                       _ lightType: Int32,
                                       _ outId: UnsafeMutablePointer<CChar>?,
                                       _ outIdSize: Int32) -> Int32 {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          let ecs = editorECS(context) else { return 0 }
    let entityName: String
    let lightTypeValue: LightType

    switch lightType {
    case 1:
        entityName = "Spot Light"
        lightTypeValue = .spot
    case 2:
        entityName = "Directional Light"
        lightTypeValue = .directional
    default:
        entityName = "Point Light"
        lightTypeValue = .point
    }

    let entity = ecs.createEntity(name: entityName)
    ecs.add(TransformComponent(), to: entity)
    ecs.add(LightComponent(type: lightTypeValue), to: entity)
    context.editorProjectManager.notifySceneMutation()
    return writeCString(entity.id.uuidString, to: outId, max: outIdSize)
}

@_cdecl("MCEEditorCreateSkyEntity")
public func MCEEditorCreateSkyEntity(_ contextPtr: UnsafeRawPointer?,
                                     _ outId: UnsafeMutablePointer<CChar>?,
                                     _ outIdSize: Int32) -> Int32 {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          let ecs = editorECS(context) else { return 0 }
    let entity = ecs.createEntity(name: "Sky")
    var sky = SkyLightComponent()
    sky.mode = .procedural
    sky.needsRegenerate = true
    ecs.add(sky, to: entity)
    setActiveSky(ecs: ecs, entity: entity, logCenter: context.editorLogCenter)
    context.editorProjectManager.notifySceneMutation()
    return writeCString(entity.id.uuidString, to: outId, max: outIdSize)
}

@_cdecl("MCEEditorCreateCameraEntity")
public func MCEEditorCreateCameraEntity(_ contextPtr: UnsafeRawPointer?,
                                        _ outId: UnsafeMutablePointer<CChar>?,
                                        _ outIdSize: Int32) -> Int32 {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          let ecs = editorECS(context) else { return 0 }
    let entity = ecs.createEntity(name: "Camera")
    var component = CameraComponent(isPrimary: false, isEditor: false)
    if !hasPrimaryRuntimeCamera(ecs: ecs) {
        component.isPrimary = true
    }
    ecs.add(component, to: entity)
    context.editorProjectManager.notifySceneMutation()
    return writeCString(entity.id.uuidString, to: outId, max: outIdSize)
}

@_cdecl("MCEEditorCreateCameraFromView")
public func MCEEditorCreateCameraFromView(_ contextPtr: UnsafeRawPointer?,
                                          _ outId: UnsafeMutablePointer<CChar>?,
                                          _ outIdSize: Int32) -> Int32 {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          let ecs = editorECS(context) else { return 0 }
    let entity = ecs.createEntity(name: "Camera")
    if let editorCamera = findEditorCamera(ecs: ecs) {
        ecs.add(editorCamera.1, to: entity)
    }
    var component = findEditorCamera(ecs: ecs)?.2 ?? CameraComponent()
    component.isEditor = false
    component.isPrimary = !hasPrimaryRuntimeCamera(ecs: ecs)
    ecs.add(component, to: entity)
    context.editorProjectManager.notifySceneMutation()
    return writeCString(entity.id.uuidString, to: outId, max: outIdSize)
}

@_cdecl("MCEEditorDestroyEntity")
public func MCEEditorDestroyEntity(_ contextPtr: UnsafeRawPointer?, _ entityId: UnsafePointer<CChar>?) {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return }
    ecs.destroyEntity(entity)
    context.editorProjectManager.notifySceneMutation()
}

@_cdecl("MCEEditorEntityHasComponent")
public func MCEEditorEntityHasComponent(_ contextPtr: UnsafeRawPointer?,
                                        _ entityId: UnsafePointer<CChar>?,
                                        _ componentType: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let type = EditorComponentType(rawValue: componentType) else { return 0 }
    switch type {
    case .name:
        return ecs.has(NameComponent.self, entity) ? 1 : 0
    case .transform:
        return ecs.has(TransformComponent.self, entity) ? 1 : 0
    case .meshRenderer:
        return ecs.has(MeshRendererComponent.self, entity) ? 1 : 0
    case .light:
        return ecs.has(LightComponent.self, entity) ? 1 : 0
    case .skyLight:
        return ecs.has(SkyLightComponent.self, entity) ? 1 : 0
    case .material:
        return ecs.has(MaterialComponent.self, entity) ? 1 : 0
    case .camera:
        return ecs.has(CameraComponent.self, entity) ? 1 : 0
    }
}

@_cdecl("MCEEditorAddComponent")
public func MCEEditorAddComponent(_ contextPtr: UnsafeRawPointer?,
                                  _ entityId: UnsafePointer<CChar>?,
                                  _ componentType: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let type = EditorComponentType(rawValue: componentType) else { return 0 }
    switch type {
    case .name:
        ecs.add(NameComponent(name: "Entity"), to: entity)
    case .transform:
        ecs.add(TransformComponent(), to: entity)
    case .meshRenderer:
        ecs.add(MeshRendererComponent(meshHandle: nil), to: entity)
    case .light:
        ecs.add(LightComponent(), to: entity)
    case .skyLight:
        var sky = SkyLightComponent()
        sky.mode = .procedural
        sky.needsRegenerate = true
        ecs.add(sky, to: entity)
        ecs.add(SkyLightTag(), to: entity)
    case .material:
        ecs.add(MaterialComponent(materialHandle: nil), to: entity)
    case .camera:
        var component = CameraComponent(isPrimary: false, isEditor: false)
        if !hasPrimaryRuntimeCamera(ecs: ecs) {
            component.isPrimary = true
        }
        ecs.add(component, to: entity)
    }
    context.editorProjectManager.notifySceneMutation()
    return 1
}

@_cdecl("MCEEditorRemoveComponent")
public func MCEEditorRemoveComponent(_ contextPtr: UnsafeRawPointer?,
                                     _ entityId: UnsafePointer<CChar>?,
                                     _ componentType: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let type = EditorComponentType(rawValue: componentType) else { return 0 }
    switch type {
    case .name:
        ecs.remove(NameComponent.self, from: entity)
    case .transform:
        ecs.remove(TransformComponent.self, from: entity)
    case .meshRenderer:
        ecs.remove(MeshRendererComponent.self, from: entity)
    case .light:
        ecs.remove(LightComponent.self, from: entity)
    case .skyLight:
        ecs.remove(SkyLightComponent.self, from: entity)
        ecs.remove(SkyLightTag.self, from: entity)
    case .material:
        ecs.remove(MaterialComponent.self, from: entity)
    case .camera:
        ecs.remove(CameraComponent.self, from: entity)
    }
    context.editorProjectManager.notifySceneMutation()
    return 1
}

@_cdecl("MCEEditorGetTransform")
public func MCEEditorGetTransform(_ contextPtr: UnsafeRawPointer?,
                                  _ entityId: UnsafePointer<CChar>?,
                                  _ px: UnsafeMutablePointer<Float>?, _ py: UnsafeMutablePointer<Float>?, _ pz: UnsafeMutablePointer<Float>?,
                                  _ rx: UnsafeMutablePointer<Float>?, _ ry: UnsafeMutablePointer<Float>?, _ rz: UnsafeMutablePointer<Float>?,
                                  _ sx: UnsafeMutablePointer<Float>?, _ sy: UnsafeMutablePointer<Float>?, _ sz: UnsafeMutablePointer<Float>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let transform = ecs.get(TransformComponent.self, for: entity) else { return 0 }
    px?.pointee = transform.position.x
    py?.pointee = transform.position.y
    pz?.pointee = transform.position.z
    rx?.pointee = transform.rotation.x
    ry?.pointee = transform.rotation.y
    rz?.pointee = transform.rotation.z
    sx?.pointee = transform.scale.x
    sy?.pointee = transform.scale.y
    sz?.pointee = transform.scale.z
    return 1
}

@_cdecl("MCEEditorSetTransform")
public func MCEEditorSetTransform(_ contextPtr: UnsafeRawPointer?,
                                  _ entityId: UnsafePointer<CChar>?,
                                  _ px: Float, _ py: Float, _ pz: Float,
                                  _ rx: Float, _ ry: Float, _ rz: Float,
                                  _ sx: Float, _ sy: Float, _ sz: Float) {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return }
    let transform = TransformComponent(
        position: SIMD3<Float>(px, py, pz),
        rotation: SIMD3<Float>(rx, ry, rz),
        scale: SIMD3<Float>(sx, sy, sz)
    )
    ecs.add(transform, to: entity)
    context.editorProjectManager.notifySceneMutation()
    context.editorLogCenter.logInfo("Transform updated: \(entity.id.uuidString)", category: .scene)
}

@_cdecl("MCEEditorSetTransformNoLog")
public func MCEEditorSetTransformNoLog(_ contextPtr: UnsafeRawPointer?,
                                       _ entityId: UnsafePointer<CChar>?,
                                       _ px: Float, _ py: Float, _ pz: Float,
                                       _ rx: Float, _ ry: Float, _ rz: Float,
                                       _ sx: Float, _ sy: Float, _ sz: Float) {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return }
    let transform = TransformComponent(
        position: SIMD3<Float>(px, py, pz),
        rotation: SIMD3<Float>(rx, ry, rz),
        scale: SIMD3<Float>(sx, sy, sz)
    )
    ecs.add(transform, to: entity)
    context.editorProjectManager.notifySceneMutation()
}

@_cdecl("MCEEditorGetCamera")
public func MCEEditorGetCamera(_ contextPtr: UnsafeRawPointer?,
                               _ entityId: UnsafePointer<CChar>?,
                               _ projectionType: UnsafeMutablePointer<Int32>?,
                               _ fovDegrees: UnsafeMutablePointer<Float>?,
                               _ orthoSize: UnsafeMutablePointer<Float>?,
                               _ nearPlane: UnsafeMutablePointer<Float>?,
                               _ farPlane: UnsafeMutablePointer<Float>?,
                               _ isPrimary: UnsafeMutablePointer<UInt32>?,
                               _ isEditor: UnsafeMutablePointer<UInt32>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let camera = ecs.get(CameraComponent.self, for: entity) else { return 0 }
    projectionType?.pointee = Int32(camera.projectionType.rawValue)
    fovDegrees?.pointee = camera.fovDegrees
    orthoSize?.pointee = camera.orthoSize
    nearPlane?.pointee = camera.nearPlane
    farPlane?.pointee = camera.farPlane
    isPrimary?.pointee = camera.isPrimary ? 1 : 0
    isEditor?.pointee = camera.isEditor ? 1 : 0
    return 1
}

@_cdecl("MCEEditorSetCamera")
public func MCEEditorSetCamera(_ contextPtr: UnsafeRawPointer?,
                               _ entityId: UnsafePointer<CChar>?,
                               _ projectionType: Int32,
                               _ fovDegrees: Float,
                               _ orthoSize: Float,
                               _ nearPlane: Float,
                               _ farPlane: Float,
                               _ isPrimary: UInt32) {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          var camera = ecs.get(CameraComponent.self, for: entity) else { return }

    camera.projectionType = ProjectionType(rawValue: UInt32(projectionType)) ?? .perspective
    camera.fovDegrees = fovDegrees
    camera.orthoSize = orthoSize
    camera.nearPlane = nearPlane
    camera.farPlane = farPlane
    camera.isPrimary = isPrimary != 0

    if camera.isPrimary && !camera.isEditor {
        setPrimaryCamera(ecs: ecs, entity: entity)
    } else {
        ecs.add(camera, to: entity)
    }
    context.editorProjectManager.notifySceneMutation()
    context.editorLogCenter.logInfo("Camera updated: \(entity.id.uuidString)", category: .scene)
}

@_cdecl("MCEEditorSetTransformFromMatrix")
public func MCEEditorSetTransformFromMatrix(_ contextPtr: UnsafeRawPointer?,
                                            _ entityId: UnsafePointer<CChar>?,
                                            _ matrix: UnsafePointer<Float>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let matrix else { return 0 }

    let col0 = SIMD3<Float>(matrix[0], matrix[1], matrix[2])
    let col1 = SIMD3<Float>(matrix[4], matrix[5], matrix[6])
    let col2 = SIMD3<Float>(matrix[8], matrix[9], matrix[10])
    let translation = SIMD3<Float>(matrix[12], matrix[13], matrix[14])

    var axisX = col0
    var axisY = col1
    var axisZ = col2

    var scaleX = simd_length(axisX)
    var scaleY = simd_length(axisY)
    var scaleZ = simd_length(axisZ)
    if scaleX <= 0.000001 || scaleY <= 0.000001 || scaleZ <= 0.000001 {
        return 0
    }

    axisX /= scaleX
    axisY /= scaleY
    axisZ /= scaleZ

    let determinant = simd_dot(axisX, simd_cross(axisY, axisZ))
    if determinant < 0 {
        scaleZ = -scaleZ
        axisZ = -axisZ
    }

    let m00 = axisX.x
    let m01 = axisY.x
    let m02 = axisZ.x
    let m10 = axisX.y
    let m11 = axisY.y
    let m12 = axisZ.y
    let m22 = axisZ.z

    var rotationX: Float = 0
    var rotationY: Float = 0
    var rotationZ: Float = 0

    if m02 < 1 {
        if m02 > -1 {
            rotationY = asinf(m02)
            rotationX = atan2f(-m12, m22)
            rotationZ = atan2f(-m01, m00)
        } else {
            rotationY = -Float.pi * 0.5
            rotationX = -atan2f(m10, m11)
            rotationZ = 0
        }
    } else {
        rotationY = Float.pi * 0.5
        rotationX = atan2f(m10, m11)
        rotationZ = 0
    }

    let transform = TransformComponent(
        position: translation,
        rotation: SIMD3<Float>(rotationX, rotationY, rotationZ),
        scale: SIMD3<Float>(scaleX, scaleY, scaleZ)
    )
    ecs.add(transform, to: entity)
    context.editorProjectManager.notifySceneMutation()
    return 1
}

@_cdecl("MCEEditorGetModelMatrix")
public func MCEEditorGetModelMatrix(_ contextPtr: UnsafeRawPointer?,
                                    _ entityId: UnsafePointer<CChar>?,
                                    _ matrixOut: UnsafeMutablePointer<Float>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let transform = ecs.get(TransformComponent.self, for: entity),
          let matrixOut else { return 0 }

    let matrix = buildModelMatrix(
        position: transform.position,
        rotation: transform.rotation,
        scale: transform.scale
    )
    withUnsafeBytes(of: matrix) { bytes in
        memcpy(matrixOut, bytes.baseAddress, MemoryLayout<Float>.size * 16)
    }

    return 1
}

private func buildModelMatrix(position: SIMD3<Float>, rotation: SIMD3<Float>, scale: SIMD3<Float>) -> matrix_float4x4 {
    let tx = position.x
    let ty = position.y
    let tz = position.z

    let sx = sin(rotation.x)
    let cx = cos(rotation.x)
    let sy = sin(rotation.y)
    let cy = cos(rotation.y)
    let sz = sin(rotation.z)
    let cz = cos(rotation.z)

    let m00 = cy * cz
    let m01 = -cy * sz
    let m02 = sy
    let m10 = sx * sy * cz + cx * sz
    let m11 = -sx * sy * sz + cx * cz
    let m12 = -sx * cy
    let m20 = -cx * sy * cz + sx * sz
    let m21 = cx * sy * sz + sx * cz
    let m22 = cx * cy

    return matrix_float4x4(columns: (
        SIMD4<Float>(m00 * scale.x, m10 * scale.x, m20 * scale.x, 0.0),
        SIMD4<Float>(m01 * scale.y, m11 * scale.y, m21 * scale.y, 0.0),
        SIMD4<Float>(m02 * scale.z, m12 * scale.z, m22 * scale.z, 0.0),
        SIMD4<Float>(tx, ty, tz, 1.0)
    ))
}

@_cdecl("MCEEditorGetEditorCameraMatrices")
public func MCEEditorGetEditorCameraMatrices(_ contextPtr: UnsafeRawPointer?,
                                             _ viewOut: UnsafeMutablePointer<Float>?,
                                             _ projectionOut: UnsafeMutablePointer<Float>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let scene = context.editorSceneController.activeScene() else { return 0 }
    let matrices = SceneRenderer.cameraMatrices(scene: scene)
    if let viewOut {
        withUnsafeBytes(of: matrices.view) { bytes in
            memcpy(viewOut, bytes.baseAddress, MemoryLayout<Float>.size * 16)
        }
    }
    if let projectionOut {
        withUnsafeBytes(of: matrices.projection) { bytes in
            memcpy(projectionOut, bytes.baseAddress, MemoryLayout<Float>.size * 16)
        }
    }
    return 1
}

@_cdecl("MCEEditorGetMeshRenderer")
public func MCEEditorGetMeshRenderer(_ contextPtr: UnsafeRawPointer?,
                                     _ entityId: UnsafePointer<CChar>?,
                                     _ meshHandle: UnsafeMutablePointer<CChar>?, _ meshHandleSize: Int32,
                                     _ materialHandle: UnsafeMutablePointer<CChar>?, _ materialHandleSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let meshRenderer = ecs.get(MeshRendererComponent.self, for: entity) else { return 0 }
    let meshString = meshRenderer.meshHandle?.rawValue.uuidString ?? ""
    let materialString = meshRenderer.materialHandle?.rawValue.uuidString ?? ""
    _ = writeCString(meshString, to: meshHandle, max: meshHandleSize)
    _ = writeCString(materialString, to: materialHandle, max: materialHandleSize)
    return 1
}

@_cdecl("MCEEditorSetMeshRenderer")
public func MCEEditorSetMeshRenderer(_ contextPtr: UnsafeRawPointer?,
                                     _ entityId: UnsafePointer<CChar>?,
                                     _ meshHandle: UnsafePointer<CChar>?,
                                     _ materialHandle: UnsafePointer<CChar>?) {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return }
    let meshString = meshHandle != nil ? String(cString: meshHandle!) : ""
    let materialString = materialHandle != nil ? String(cString: materialHandle!) : ""
    var component = ecs.get(MeshRendererComponent.self, for: entity) ?? MeshRendererComponent(meshHandle: nil)
    component.meshHandle = handleFromString(meshString)
    component.materialHandle = handleFromString(materialString)
    ecs.add(component, to: entity)
    context.editorProjectManager.notifySceneMutation()
    context.editorLogCenter.logInfo("Mesh updated: \(entity.id.uuidString)", category: .scene)
}

@_cdecl("MCEEditorAssignMaterialToEntity")
public func MCEEditorAssignMaterialToEntity(_ contextPtr: UnsafeRawPointer?,
                                            _ entityId: UnsafePointer<CChar>?,
                                            _ materialHandle: UnsafePointer<CChar>?) {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return }
    let materialString = materialHandle != nil ? String(cString: materialHandle!) : ""
    let handle = handleFromString(materialString)

    if var meshRenderer = ecs.get(MeshRendererComponent.self, for: entity) {
        meshRenderer.materialHandle = handle
        ecs.add(meshRenderer, to: entity)
    }

    if let handle {
        let materialComponent = MaterialComponent(materialHandle: handle)
        ecs.add(materialComponent, to: entity)
    } else {
        ecs.remove(MaterialComponent.self, from: entity)
    }

    context.editorProjectManager.notifySceneMutation()
    context.editorLogCenter.logInfo("Material updated: \(entity.id.uuidString)", category: .scene)
}

@_cdecl("MCEEditorGetMaterialComponent")
public func MCEEditorGetMaterialComponent(_ contextPtr: UnsafeRawPointer?,
                                          _ entityId: UnsafePointer<CChar>?,
                                          _ materialHandle: UnsafeMutablePointer<CChar>?,
                                          _ materialHandleSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let component = ecs.get(MaterialComponent.self, for: entity) else { return 0 }
    let materialString = component.materialHandle?.rawValue.uuidString ?? ""
    _ = writeCString(materialString, to: materialHandle, max: materialHandleSize)
    return 1
}

@_cdecl("MCEEditorSetMaterialComponent")
public func MCEEditorSetMaterialComponent(_ contextPtr: UnsafeRawPointer?,
                                          _ entityId: UnsafePointer<CChar>?,
                                          _ materialHandle: UnsafePointer<CChar>?) {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return }
    let materialString = materialHandle != nil ? String(cString: materialHandle!) : ""
    var component = ecs.get(MaterialComponent.self, for: entity) ?? MaterialComponent(materialHandle: nil)
    component.materialHandle = handleFromString(materialString)
    ecs.add(component, to: entity)
    context.editorProjectManager.notifySceneMutation()
    context.editorLogCenter.logInfo("Material updated: \(entity.id.uuidString)", category: .scene)
}

@_cdecl("MCEEditorGetLight")
public func MCEEditorGetLight(_ contextPtr: UnsafeRawPointer?,
                              _ entityId: UnsafePointer<CChar>?, _ type: UnsafeMutablePointer<Int32>?,
                              _ colorX: UnsafeMutablePointer<Float>?, _ colorY: UnsafeMutablePointer<Float>?, _ colorZ: UnsafeMutablePointer<Float>?,
                              _ brightness: UnsafeMutablePointer<Float>?, _ range: UnsafeMutablePointer<Float>?, _ innerCos: UnsafeMutablePointer<Float>?, _ outerCos: UnsafeMutablePointer<Float>?,
                              _ dirX: UnsafeMutablePointer<Float>?, _ dirY: UnsafeMutablePointer<Float>?, _ dirZ: UnsafeMutablePointer<Float>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let light = ecs.get(LightComponent.self, for: entity) else { return 0 }
    switch light.type {
    case .point:
        type?.pointee = 0
    case .spot:
        type?.pointee = 1
    case .directional:
        type?.pointee = 2
    @unknown default:
        type?.pointee = 0
    }
    colorX?.pointee = light.data.color.x
    colorY?.pointee = light.data.color.y
    colorZ?.pointee = light.data.color.z
    brightness?.pointee = light.data.brightness
    range?.pointee = light.range
    innerCos?.pointee = light.innerConeCos
    outerCos?.pointee = light.outerConeCos
    dirX?.pointee = light.direction.x
    dirY?.pointee = light.direction.y
    dirZ?.pointee = light.direction.z
    return 1
}

@_cdecl("MCEEditorSetLight")
public func MCEEditorSetLight(_ contextPtr: UnsafeRawPointer?,
                              _ entityId: UnsafePointer<CChar>?, _ type: Int32,
                              _ colorX: Float, _ colorY: Float, _ colorZ: Float,
                              _ brightness: Float, _ range: Float, _ innerCos: Float, _ outerCos: Float,
                              _ dirX: Float, _ dirY: Float, _ dirZ: Float) {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return }
    var light = ecs.get(LightComponent.self, for: entity) ?? LightComponent()
    switch type {
    case 1: light.type = .spot
    case 2: light.type = .directional
    default: light.type = .point
    }
    light.data.color = SIMD3<Float>(colorX, colorY, colorZ)
    light.data.brightness = max(0.0, brightness)
    light.range = max(0.0, range)
    light.innerConeCos = innerCos
    light.outerConeCos = outerCos
    light.direction = SIMD3<Float>(dirX, dirY, dirZ)
    ecs.add(light, to: entity)
    context.editorProjectManager.notifySceneMutation()
    context.editorLogCenter.logInfo("Light updated: \(entity.id.uuidString)", category: .scene)
}

@_cdecl("MCEEditorGetSkyLight")
public func MCEEditorGetSkyLight(_ contextPtr: UnsafeRawPointer?,
                                 _ entityId: UnsafePointer<CChar>?, _ mode: UnsafeMutablePointer<Int32>?, _ enabled: UnsafeMutablePointer<UInt32>?,
                                 _ intensity: UnsafeMutablePointer<Float>?, _ tintX: UnsafeMutablePointer<Float>?, _ tintY: UnsafeMutablePointer<Float>?, _ tintZ: UnsafeMutablePointer<Float>?,
                                 _ turbidity: UnsafeMutablePointer<Float>?, _ azimuth: UnsafeMutablePointer<Float>?, _ elevation: UnsafeMutablePointer<Float>?,
                                 _ hdriHandle: UnsafeMutablePointer<CChar>?, _ hdriHandleSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let sky = ecs.get(SkyLightComponent.self, for: entity) else { return 0 }
    mode?.pointee = Int32(sky.mode.rawValue)
    enabled?.pointee = sky.enabled ? 1 : 0
    intensity?.pointee = sky.intensity
    tintX?.pointee = sky.skyTint.x
    tintY?.pointee = sky.skyTint.y
    tintZ?.pointee = sky.skyTint.z
    turbidity?.pointee = sky.turbidity
    azimuth?.pointee = sky.azimuthDegrees
    elevation?.pointee = sky.elevationDegrees
    let hdriString = sky.hdriHandle?.rawValue.uuidString ?? ""
    _ = writeCString(hdriString, to: hdriHandle, max: hdriHandleSize)
    return 1
}

@_cdecl("MCEEditorSetSkyLight")
public func MCEEditorSetSkyLight(_ contextPtr: UnsafeRawPointer?,
                                 _ entityId: UnsafePointer<CChar>?, _ mode: Int32, _ enabled: UInt32,
                                 _ intensity: Float, _ tintX: Float, _ tintY: Float, _ tintZ: Float,
                                 _ turbidity: Float, _ azimuth: Float, _ elevation: Float,
                                 _ hdriHandle: UnsafePointer<CChar>?) {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return }
    var sky = ecs.get(SkyLightComponent.self, for: entity) ?? SkyLightComponent()
    sky.mode = SkyMode(rawValue: UInt32(max(0, mode))) ?? .hdri
    sky.enabled = enabled != 0
    sky.intensity = max(0.0, intensity)
    sky.skyTint = SIMD3<Float>(max(0.0, tintX), max(0.0, tintY), max(0.0, tintZ))
    sky.turbidity = max(1.0, turbidity)
    sky.azimuthDegrees = azimuth
    sky.elevationDegrees = elevation
    if let hdriHandle {
        let hdriString = String(cString: hdriHandle)
        sky.hdriHandle = handleFromString(hdriString)
    } else {
        sky.hdriHandle = nil
    }
    sky.needsRegenerate = true
    ecs.add(sky, to: entity)
    if sky.needsRegenerate {
        context.editorLogCenter.logInfo("Sky regenerate requested: \(entity.id.uuidString)", category: .scene)
    }
    context.editorProjectManager.notifySceneMutation()
}

@_cdecl("MCEEditorSkyEntityCount")
public func MCEEditorSkyEntityCount(_ contextPtr: UnsafeRawPointer?) -> Int32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context) else { return 0 }
    return Int32(allSkyEntities(ecs: ecs).count)
}

@_cdecl("MCEEditorGetActiveSkyId")
public func MCEEditorGetActiveSkyId(_ contextPtr: UnsafeRawPointer?,
                                   _ buffer: UnsafeMutablePointer<CChar>?,
                                   _ bufferSize: Int32) -> Int32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context) else { return 0 }
    guard let active = ensureActiveSkyEntity(ecs: ecs, logCenter: context.editorLogCenter) else { return 0 }
    return writeCString(active.id.uuidString, to: buffer, max: bufferSize)
}

@_cdecl("MCEEditorSetActiveSky")
public func MCEEditorSetActiveSky(_ contextPtr: UnsafeRawPointer?,
                                  _ entityId: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return 0 }
    setActiveSky(ecs: ecs, entity: entity, logCenter: context.editorLogCenter)
    context.editorProjectManager.notifySceneMutation()
    return 1
}
