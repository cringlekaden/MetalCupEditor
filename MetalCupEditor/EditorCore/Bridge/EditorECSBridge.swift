/// EditorECSBridge.swift
/// Defines ECS bridge helpers for editor UI integration.
/// Created by Kaden Cringle.

import Foundation
import MetalCupEngine
import simd

private func writeColumnMajorMatrix(_ matrix: matrix_float4x4, to buffer: UnsafeMutablePointer<Float>) {
    buffer[0] = matrix.columns.0.x
    buffer[1] = matrix.columns.0.y
    buffer[2] = matrix.columns.0.z
    buffer[3] = matrix.columns.0.w
    buffer[4] = matrix.columns.1.x
    buffer[5] = matrix.columns.1.y
    buffer[6] = matrix.columns.1.z
    buffer[7] = matrix.columns.1.w
    buffer[8] = matrix.columns.2.x
    buffer[9] = matrix.columns.2.y
    buffer[10] = matrix.columns.2.z
    buffer[11] = matrix.columns.2.w
    buffer[12] = matrix.columns.3.x
    buffer[13] = matrix.columns.3.y
    buffer[14] = matrix.columns.3.z
    buffer[15] = matrix.columns.3.w
}

private func readColumnMajorMatrix(from buffer: UnsafePointer<Float>) -> matrix_float4x4 {
    matrix_float4x4(columns: (
        SIMD4<Float>(buffer[0], buffer[1], buffer[2], buffer[3]),
        SIMD4<Float>(buffer[4], buffer[5], buffer[6], buffer[7]),
        SIMD4<Float>(buffer[8], buffer[9], buffer[10], buffer[11]),
        SIMD4<Float>(buffer[12], buffer[13], buffer[14], buffer[15])
    ))
}

private enum EditorComponentType: Int32 {
    case name = 0
    case transform = 1
    case meshRenderer = 2
    case light = 3
    case skyLight = 4
    case material = 5
    case camera = 6
    case rigidbody = 7
    case collider = 8
}

private func resolveContext(_ contextPtr: UnsafeRawPointer?) -> MCEContext? {
    guard let contextPtr else { return nil }
    let raw = UInt(bitPattern: contextPtr)
    if raw < 0x1000 {
        #if DEBUG
        assertionFailure("Invalid MCEContext pointer (too small) passed to bridge.")
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
        assertionFailure("Invalid MCEContext pointer passed to bridge.")
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

private func parseSubmeshMaterialHandles(_ raw: String) -> [AssetHandle?] {
    let parts = raw.components(separatedBy: ",")
    return parts.map { part in
        let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        return AssetHandle(string: trimmed)
    }
}

private func metadata(for handle: AssetHandle, projectManager: EditorProjectManager) -> AssetMetadata? {
    return projectManager.assetMetadataSnapshot().first { $0.handle == handle }
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
                rotationQuat: Vector4DTO(component.rotation),
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
                submeshMaterialHandles: component.submeshMaterialHandles,
                material: component.material.map { MaterialDTO(material: $0) },
                albedoMapHandle: component.albedoMapHandle,
                normalMapHandle: component.normalMapHandle,
                metallicMapHandle: component.metallicMapHandle,
                roughnessMapHandle: component.roughnessMapHandle,
                mrMapHandle: component.mrMapHandle,
                ormMapHandle: component.ormMapHandle,
                aoMapHandle: component.aoMapHandle,
                emissiveMapHandle: component.emissiveMapHandle
            )
        },
        materialComponent: ecs.get(MaterialComponent.self, for: entity).map { component in
            MaterialComponentDTO(materialHandle: component.materialHandle)
        },
        rigidbody: ecs.get(RigidbodyComponent.self, for: entity).map { component in
            RigidbodyComponentDTO(
                enabled: component.isEnabled,
                motionType: component.motionType.rawValue,
                mass: component.mass,
                friction: component.friction,
                restitution: component.restitution,
                linearDamping: component.linearDamping,
                angularDamping: component.angularDamping,
                gravityFactor: component.gravityFactor,
                allowSleeping: component.allowSleeping,
                ccdEnabled: component.ccdEnabled,
                collisionLayer: component.collisionLayer
            )
        },
        collider: ecs.get(ColliderComponent.self, for: entity).map { component in
            ColliderComponentDTO(
                enabled: component.isEnabled,
                shapeType: component.shapeType.rawValue,
                boxHalfExtents: Vector3DTO(component.boxHalfExtents),
                sphereRadius: component.sphereRadius,
                capsuleHalfHeight: component.capsuleHalfHeight,
                capsuleRadius: component.capsuleRadius,
                offset: Vector3DTO(component.offset),
                rotationOffset: Vector3DTO(component.rotationOffset),
                isTrigger: component.isTrigger
            )
        },
        light: ecs.get(LightComponent.self, for: entity).map { component in
            LightComponentDTO(
                type: LightTypeDTO(from: component.type),
                data: LightDataDTO(from: component.data),
                direction: Vector3DTO(component.direction),
                range: component.range,
                innerConeCos: component.innerConeCos,
                outerConeCos: component.outerConeCos,
                castsShadows: component.castsShadows
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
                sunSizeDegrees: component.sunSizeDegrees,
                zenithTint: Vector3DTO(component.zenithTint),
                horizonTint: Vector3DTO(component.horizonTint),
                gradientStrength: component.gradientStrength,
                hazeDensity: component.hazeDensity,
                hazeFalloff: component.hazeFalloff,
                hazeHeight: component.hazeHeight,
                ozoneStrength: component.ozoneStrength,
                ozoneTint: Vector3DTO(component.ozoneTint),
                sunHaloSize: component.sunHaloSize,
                sunHaloIntensity: component.sunHaloIntensity,
                sunHaloSoftness: component.sunHaloSoftness,
                cloudsEnabled: component.cloudsEnabled,
                cloudsCoverage: component.cloudsCoverage,
                cloudsSoftness: component.cloudsSoftness,
                cloudsScale: component.cloudsScale,
                cloudsSpeed: component.cloudsSpeed,
                cloudsWindX: component.cloudsWindDirection.x,
                cloudsWindY: component.cloudsWindDirection.y,
                cloudsHeight: component.cloudsHeight,
                cloudsThickness: component.cloudsThickness,
                cloudsBrightness: component.cloudsBrightness,
                cloudsSunInfluence: component.cloudsSunInfluence,
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

private func ensureActiveSkyEntity(ecs: SceneECS, logger: EngineLogger) -> Entity? {
    if let active = ecs.activeSkyLight()?.0 {
        return active
    }
    let skyEntities = allSkyEntities(ecs: ecs)
    guard let first = skyEntities.first else { return nil }
    ecs.add(SkyLightTag(), to: first)
    logger.logInfo("Sky active assigned: \(first.id.uuidString)", category: .scene)
    return first
}

private func setActiveSky(ecs: SceneECS, entity: Entity, logger: EngineLogger) {
    for skyEntity in allSkyEntities(ecs: ecs) {
        if skyEntity.id != entity.id {
            ecs.remove(SkyLightTag.self, from: skyEntity)
        }
    }
    ecs.add(SkyLightTag(), to: entity)
    if var sky = ecs.get(SkyLightComponent.self, for: entity) {
        sky.needsRebuild = true
        ecs.add(sky, to: entity)
        logger.logInfo("Sky regenerate requested: \(entity.id.uuidString)", category: .scene)
    }
    logger.logInfo("Sky active set: \(entity.id.uuidString)", category: .scene)
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
    context.engineContext.log.logInfo("Entity renamed: \(entity.id.uuidString) \(newName)", category: .scene)
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
        meshHandle = context.engineContext.assets.handle(forSourcePath: "sphere/sphere.obj")
    case 2:
        entity = ecs.createEntity(name: "Plane")
        meshHandle = BuiltinAssets.editorPlaneMesh
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

@_cdecl("MCEEditorCreateMeshEntityFromHandleWithMaterials")
public func MCEEditorCreateMeshEntityFromHandleWithMaterials(_ contextPtr: UnsafeRawPointer?,
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

    var submeshMaterials: [AssetHandle?]? = nil
    var primaryMaterial: AssetHandle? = nil
    if let meshHandleValue,
       let meshMetadata = metadata(for: meshHandleValue, projectManager: context.editorProjectManager),
       let raw = meshMetadata.importSettings["submeshMaterials"],
       !raw.isEmpty {
        let parsed = parseSubmeshMaterialHandles(raw)
        if !parsed.isEmpty {
            submeshMaterials = parsed
            primaryMaterial = parsed.compactMap { $0 }.first
        }
    }

    var meshRenderer = MeshRendererComponent(meshHandle: meshHandleValue)
    meshRenderer.submeshMaterialHandles = submeshMaterials
    if let primaryMaterial {
        meshRenderer.materialHandle = primaryMaterial
    }
    ecs.add(meshRenderer, to: entity)
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
    sky.needsRebuild = true
    ecs.add(sky, to: entity)
    setActiveSky(ecs: ecs, entity: entity, logger: context.engineContext.log)
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
    case .rigidbody:
        return ecs.has(RigidbodyComponent.self, entity) ? 1 : 0
    case .collider:
        return ecs.has(ColliderComponent.self, entity) ? 1 : 0
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
        sky.needsRebuild = true
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
    case .rigidbody:
        let defaults = context.engineContext.physicsSettings
        let component = RigidbodyComponent(
            friction: defaults.defaultFriction,
            restitution: defaults.defaultRestitution,
            angularDamping: defaults.defaultAngularDamping
        )
        ecs.add(component, to: entity)
    case .collider:
        ecs.add(ColliderComponent(), to: entity)
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
    case .rigidbody:
        ecs.remove(RigidbodyComponent.self, from: entity)
    case .collider:
        ecs.remove(ColliderComponent.self, from: entity)
    }
    context.editorProjectManager.notifySceneMutation()
    return 1
}

@_cdecl("MCEEditorGetRigidbody")
public func MCEEditorGetRigidbody(_ contextPtr: UnsafeRawPointer?,
                                  _ entityId: UnsafePointer<CChar>?,
                                  _ enabled: UnsafeMutablePointer<UInt32>?,
                                  _ motionType: UnsafeMutablePointer<Int32>?,
                                  _ mass: UnsafeMutablePointer<Float>?,
                                  _ friction: UnsafeMutablePointer<Float>?,
                                  _ restitution: UnsafeMutablePointer<Float>?,
                                  _ linearDamping: UnsafeMutablePointer<Float>?,
                                  _ angularDamping: UnsafeMutablePointer<Float>?,
                                  _ gravityFactor: UnsafeMutablePointer<Float>?,
                                  _ allowSleeping: UnsafeMutablePointer<UInt32>?,
                                  _ ccdEnabled: UnsafeMutablePointer<UInt32>?,
                                  _ collisionLayer: UnsafeMutablePointer<Int32>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let rigidbody = ecs.get(RigidbodyComponent.self, for: entity) else { return 0 }
    enabled?.pointee = rigidbody.isEnabled ? 1 : 0
    motionType?.pointee = Int32(rigidbody.motionType.rawValue)
    mass?.pointee = rigidbody.mass
    friction?.pointee = rigidbody.friction
    restitution?.pointee = rigidbody.restitution
    linearDamping?.pointee = rigidbody.linearDamping
    angularDamping?.pointee = rigidbody.angularDamping
    gravityFactor?.pointee = rigidbody.gravityFactor
    allowSleeping?.pointee = rigidbody.allowSleeping ? 1 : 0
    ccdEnabled?.pointee = rigidbody.ccdEnabled ? 1 : 0
    collisionLayer?.pointee = rigidbody.collisionLayer
    return 1
}

@_cdecl("MCEEditorSetRigidbody")
public func MCEEditorSetRigidbody(_ contextPtr: UnsafeRawPointer?,
                                  _ entityId: UnsafePointer<CChar>?,
                                  _ enabled: UInt32,
                                  _ motionType: Int32,
                                  _ mass: Float,
                                  _ friction: Float,
                                  _ restitution: Float,
                                  _ linearDamping: Float,
                                  _ angularDamping: Float,
                                  _ gravityFactor: Float,
                                  _ allowSleeping: UInt32,
                                  _ ccdEnabled: UInt32,
                                  _ collisionLayer: Int32) {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return }
    let component = RigidbodyComponent(isEnabled: enabled != 0,
                                       motionType: RigidbodyMotionType(rawValue: UInt32(motionType)) ?? .dynamic,
                                       mass: mass,
                                       friction: friction,
                                       restitution: restitution,
                                       linearDamping: linearDamping,
                                       angularDamping: angularDamping,
                                       gravityFactor: gravityFactor,
                                       allowSleeping: allowSleeping != 0,
                                       ccdEnabled: ccdEnabled != 0,
                                       collisionLayer: collisionLayer)
    ecs.add(component, to: entity)
    context.editorProjectManager.notifySceneMutation()
}

@_cdecl("MCEEditorGetCollider")
public func MCEEditorGetCollider(_ contextPtr: UnsafeRawPointer?,
                                 _ entityId: UnsafePointer<CChar>?,
                                 _ enabled: UnsafeMutablePointer<UInt32>?,
                                 _ shapeType: UnsafeMutablePointer<Int32>?,
                                 _ boxX: UnsafeMutablePointer<Float>?,
                                 _ boxY: UnsafeMutablePointer<Float>?,
                                 _ boxZ: UnsafeMutablePointer<Float>?,
                                 _ sphereRadius: UnsafeMutablePointer<Float>?,
                                 _ capsuleHalfHeight: UnsafeMutablePointer<Float>?,
                                 _ capsuleRadius: UnsafeMutablePointer<Float>?,
                                 _ offsetX: UnsafeMutablePointer<Float>?,
                                 _ offsetY: UnsafeMutablePointer<Float>?,
                                 _ offsetZ: UnsafeMutablePointer<Float>?,
                                 _ rotX: UnsafeMutablePointer<Float>?,
                                 _ rotY: UnsafeMutablePointer<Float>?,
                                 _ rotZ: UnsafeMutablePointer<Float>?,
                                 _ isTrigger: UnsafeMutablePointer<UInt32>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let collider = ecs.get(ColliderComponent.self, for: entity) else { return 0 }
    enabled?.pointee = collider.isEnabled ? 1 : 0
    shapeType?.pointee = Int32(collider.shapeType.rawValue)
    boxX?.pointee = collider.boxHalfExtents.x
    boxY?.pointee = collider.boxHalfExtents.y
    boxZ?.pointee = collider.boxHalfExtents.z
    sphereRadius?.pointee = collider.sphereRadius
    capsuleHalfHeight?.pointee = collider.capsuleHalfHeight
    capsuleRadius?.pointee = collider.capsuleRadius
    offsetX?.pointee = collider.offset.x
    offsetY?.pointee = collider.offset.y
    offsetZ?.pointee = collider.offset.z
    rotX?.pointee = collider.rotationOffset.x
    rotY?.pointee = collider.rotationOffset.y
    rotZ?.pointee = collider.rotationOffset.z
    isTrigger?.pointee = collider.isTrigger ? 1 : 0
    return 1
}

@_cdecl("MCEEditorSetCollider")
public func MCEEditorSetCollider(_ contextPtr: UnsafeRawPointer?,
                                 _ entityId: UnsafePointer<CChar>?,
                                 _ enabled: UInt32,
                                 _ shapeType: Int32,
                                 _ boxX: Float,
                                 _ boxY: Float,
                                 _ boxZ: Float,
                                 _ sphereRadius: Float,
                                 _ capsuleHalfHeight: Float,
                                 _ capsuleRadius: Float,
                                 _ offsetX: Float,
                                 _ offsetY: Float,
                                 _ offsetZ: Float,
                                 _ rotX: Float,
                                 _ rotY: Float,
                                 _ rotZ: Float,
                                 _ isTrigger: UInt32) {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return }
    let component = ColliderComponent(isEnabled: enabled != 0,
                                      shapeType: ColliderShapeType(rawValue: UInt32(shapeType)) ?? .box,
                                      boxHalfExtents: SIMD3<Float>(boxX, boxY, boxZ),
                                      sphereRadius: sphereRadius,
                                      capsuleHalfHeight: capsuleHalfHeight,
                                      capsuleRadius: capsuleRadius,
                                      offset: SIMD3<Float>(offsetX, offsetY, offsetZ),
                                      rotationOffset: SIMD3<Float>(rotX, rotY, rotZ),
                                      isTrigger: isTrigger != 0)
    ecs.add(component, to: entity)
    context.editorProjectManager.notifySceneMutation()
}

@_cdecl("MCEEditorRebuildPhysicsBody")
public func MCEEditorRebuildPhysicsBody(_ contextPtr: UnsafeRawPointer?,
                                        _ entityId: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          context.editorSceneController.isPlaying,
          let runtimeScene = context.editorSceneController.runtimeScene,
          let entityId else { return 0 }
    let idString = String(cString: entityId)
    guard let uuid = UUID(uuidString: idString),
          let entity = runtimeScene.ecs.entity(with: uuid) else { return 0 }
    let success = runtimeScene.rebuildPhysicsBody(for: entity)
    return success ? 1 : 0
}

@_cdecl("MCEEditorGetColliderEntityCount")
public func MCEEditorGetColliderEntityCount(_ contextPtr: UnsafeRawPointer?) -> Int32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context) else { return 0 }
    let count = ecs.allEntities().filter { ecs.get(ColliderComponent.self, for: $0) != nil }.count
    return Int32(count)
}

@_cdecl("MCEEditorGetColliderEntityAt")
public func MCEEditorGetColliderEntityAt(_ contextPtr: UnsafeRawPointer?,
                                        _ index: Int32,
                                        _ buffer: UnsafeMutablePointer<CChar>?,
                                        _ bufferSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let buffer,
          bufferSize > 0 else { return 0 }
    let colliders = ecs.allEntities().filter { ecs.get(ColliderComponent.self, for: $0) != nil }
    guard index >= 0, index < Int32(colliders.count) else { return 0 }
    let entity = colliders[Int(index)]
    return writeCString(entity.id.uuidString, to: buffer, max: bufferSize) > 0 ? 1 : 0
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
    let euler = TransformMath.eulerFromQuaternionXYZ(transform.rotation)
    rx?.pointee = euler.x
    ry?.pointee = euler.y
    rz?.pointee = euler.z
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
        rotation: TransformMath.quaternionFromEulerXYZ(SIMD3<Float>(rx, ry, rz)),
        scale: SIMD3<Float>(sx, sy, sz)
    )
    ecs.add(transform, to: entity)
    context.editorProjectManager.notifySceneMutation()
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
        rotation: TransformMath.quaternionFromEulerXYZ(SIMD3<Float>(rx, ry, rz)),
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

    let axisX = SIMD3<Float>(matrix[0], matrix[1], matrix[2])
    let axisY = SIMD3<Float>(matrix[4], matrix[5], matrix[6])
    let axisZ = SIMD3<Float>(matrix[8], matrix[9], matrix[10])
    let scaleX = simd_length(axisX)
    let scaleY = simd_length(axisY)
    let scaleZ = simd_length(axisZ)
    if scaleX <= 0.000001 || scaleY <= 0.000001 || scaleZ <= 0.000001 {
        return 0
    }

    let matrixValue = readColumnMajorMatrix(from: matrix)
    let decomposed = TransformMath.decomposeMatrix(matrixValue)
    let transform = TransformComponent(
        position: decomposed.position,
        rotation: decomposed.rotation,
        scale: decomposed.scale
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

    let matrix = TransformMath.makeMatrix(position: transform.position,
                                          rotation: transform.rotation,
                                          scale: transform.scale)
    writeColumnMajorMatrix(matrix, to: matrixOut)

    return 1
}

@_cdecl("MCEEditorGetEditorCameraMatrices")
public func MCEEditorGetEditorCameraMatrices(_ contextPtr: UnsafeRawPointer?,
                                             _ viewOut: UnsafeMutablePointer<Float>?,
                                             _ projectionOut: UnsafeMutablePointer<Float>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let scene = context.editorSceneController.activeScene() else { return 0 }
    let matrices = SceneRenderer.cameraMatrices(scene: scene)
    if let viewOut {
        writeColumnMajorMatrix(matrices.view, to: viewOut)
    }
    if let projectionOut {
        writeColumnMajorMatrix(matrices.projection, to: projectionOut)
    }
    return 1
}

@_cdecl("MCEEditorDebugPhysicsRaycastFromCamera")
public func MCEEditorDebugPhysicsRaycastFromCamera(_ contextPtr: UnsafeRawPointer?,
                                                   _ maxDistance: Float) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let scene = context.editorSceneController.activeScene() else { return 0 }
    let settings = context.engineContext.physicsSettings
    let hadPhysics = scene.physicsSystem != nil
    if !hadPhysics {
        scene.startPhysics(settings: settings)
    }
    guard let physicsSystem = scene.physicsSystem else { return 0 }
    let matrices = SceneRenderer.cameraMatrices(scene: scene)
    let invView = simd_inverse(matrices.view)
    let origin = SIMD3<Float>(invView.columns.3.x, invView.columns.3.y, invView.columns.3.z)
    let forward = -SIMD3<Float>(invView.columns.2.x, invView.columns.2.y, invView.columns.2.z)
    let dirLength = simd_length(forward)
    if dirLength < 1e-5 {
        if !hadPhysics { scene.stopPhysics() }
        return 0
    }
    let direction = forward / dirLength
    let clampedDistance = max(Float(0.01), maxDistance)
    let result = physicsSystem.raycastClosest(origin: origin, direction: direction, maxDistance: clampedDistance)
    if let hit = result {
        let debugDraw = context.engineContext.debugDraw
        let pointSize = max(0.02, debugDraw.lineThickness * 2.0)
        let offsetX = SIMD3<Float>(pointSize, 0.0, 0.0)
        let offsetZ = SIMD3<Float>(0.0, 0.0, pointSize)
        let normalLength: Float = 0.25
        let color = SIMD4<Float>(0.95, 0.8, 0.2, 1.0)
        debugDraw.submitLine(hit.position - offsetX, hit.position + offsetX, color: color)
        debugDraw.submitLine(hit.position - offsetZ, hit.position + offsetZ, color: color)
        debugDraw.submitLine(hit.position, hit.position + hit.normal * normalLength, color: color)
    }
    if !hadPhysics {
        scene.stopPhysics()
    }
    return result == nil ? 0 : 1
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
}

@_cdecl("MCEEditorGetLight")
public func MCEEditorGetLight(_ contextPtr: UnsafeRawPointer?,
                              _ entityId: UnsafePointer<CChar>?, _ type: UnsafeMutablePointer<Int32>?,
                              _ colorX: UnsafeMutablePointer<Float>?, _ colorY: UnsafeMutablePointer<Float>?, _ colorZ: UnsafeMutablePointer<Float>?,
                              _ brightness: UnsafeMutablePointer<Float>?, _ range: UnsafeMutablePointer<Float>?, _ innerCos: UnsafeMutablePointer<Float>?, _ outerCos: UnsafeMutablePointer<Float>?,
                              _ dirX: UnsafeMutablePointer<Float>?, _ dirY: UnsafeMutablePointer<Float>?, _ dirZ: UnsafeMutablePointer<Float>?,
                              _ castsShadows: UnsafeMutablePointer<UInt32>?) -> UInt32 {
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
    castsShadows?.pointee = light.castsShadows ? 1 : 0
    return 1
}

@_cdecl("MCEEditorSetLight")
public func MCEEditorSetLight(_ contextPtr: UnsafeRawPointer?,
                              _ entityId: UnsafePointer<CChar>?, _ type: Int32,
                              _ colorX: Float, _ colorY: Float, _ colorZ: Float,
                              _ brightness: Float, _ range: Float, _ innerCos: Float, _ outerCos: Float,
                              _ dirX: Float, _ dirY: Float, _ dirZ: Float,
                              _ castsShadows: UInt32) {
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
    light.castsShadows = castsShadows != 0
    ecs.add(light, to: entity)
    if ecs.has(PrefabInstanceComponent.self, entity) {
        var overrides = ecs.get(PrefabOverrideComponent.self, for: entity) ?? PrefabOverrideComponent()
        overrides.overridden.insert(.light)
        ecs.add(overrides, to: entity)
    }
    context.editorProjectManager.notifySceneMutation()
}

@_cdecl("MCEEditorGetSkyLight")
public func MCEEditorGetSkyLight(_ contextPtr: UnsafeRawPointer?,
                                 _ entityId: UnsafePointer<CChar>?, _ mode: UnsafeMutablePointer<Int32>?, _ enabled: UnsafeMutablePointer<UInt32>?,
                                 _ intensity: UnsafeMutablePointer<Float>?, _ tintX: UnsafeMutablePointer<Float>?, _ tintY: UnsafeMutablePointer<Float>?, _ tintZ: UnsafeMutablePointer<Float>?,
                                 _ turbidity: UnsafeMutablePointer<Float>?, _ azimuth: UnsafeMutablePointer<Float>?, _ elevation: UnsafeMutablePointer<Float>?, _ sunSize: UnsafeMutablePointer<Float>?,
                                 _ zenithTintX: UnsafeMutablePointer<Float>?, _ zenithTintY: UnsafeMutablePointer<Float>?, _ zenithTintZ: UnsafeMutablePointer<Float>?,
                                 _ horizonTintX: UnsafeMutablePointer<Float>?, _ horizonTintY: UnsafeMutablePointer<Float>?, _ horizonTintZ: UnsafeMutablePointer<Float>?,
                                 _ gradientStrength: UnsafeMutablePointer<Float>?,
                                 _ hazeDensity: UnsafeMutablePointer<Float>?, _ hazeFalloff: UnsafeMutablePointer<Float>?, _ hazeHeight: UnsafeMutablePointer<Float>?,
                                 _ ozoneStrength: UnsafeMutablePointer<Float>?, _ ozoneTintX: UnsafeMutablePointer<Float>?, _ ozoneTintY: UnsafeMutablePointer<Float>?, _ ozoneTintZ: UnsafeMutablePointer<Float>?,
                                 _ sunHaloSize: UnsafeMutablePointer<Float>?, _ sunHaloIntensity: UnsafeMutablePointer<Float>?, _ sunHaloSoftness: UnsafeMutablePointer<Float>?,
                                 _ cloudsEnabled: UnsafeMutablePointer<UInt32>?, _ cloudsCoverage: UnsafeMutablePointer<Float>?, _ cloudsSoftness: UnsafeMutablePointer<Float>?,
                                 _ cloudsScale: UnsafeMutablePointer<Float>?, _ cloudsSpeed: UnsafeMutablePointer<Float>?,
                                 _ cloudsWindX: UnsafeMutablePointer<Float>?, _ cloudsWindY: UnsafeMutablePointer<Float>?,
                                 _ cloudsHeight: UnsafeMutablePointer<Float>?, _ cloudsThickness: UnsafeMutablePointer<Float>?,
                                 _ cloudsBrightness: UnsafeMutablePointer<Float>?, _ cloudsSunInfluence: UnsafeMutablePointer<Float>?,
                                 _ autoRebuild: UnsafeMutablePointer<UInt32>?, _ needsRebuild: UnsafeMutablePointer<UInt32>?,
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
    sunSize?.pointee = sky.sunSizeDegrees
    zenithTintX?.pointee = sky.zenithTint.x
    zenithTintY?.pointee = sky.zenithTint.y
    zenithTintZ?.pointee = sky.zenithTint.z
    horizonTintX?.pointee = sky.horizonTint.x
    horizonTintY?.pointee = sky.horizonTint.y
    horizonTintZ?.pointee = sky.horizonTint.z
    gradientStrength?.pointee = sky.gradientStrength
    hazeDensity?.pointee = sky.hazeDensity
    hazeFalloff?.pointee = sky.hazeFalloff
    hazeHeight?.pointee = sky.hazeHeight
    ozoneStrength?.pointee = sky.ozoneStrength
    ozoneTintX?.pointee = sky.ozoneTint.x
    ozoneTintY?.pointee = sky.ozoneTint.y
    ozoneTintZ?.pointee = sky.ozoneTint.z
    sunHaloSize?.pointee = sky.sunHaloSize
    sunHaloIntensity?.pointee = sky.sunHaloIntensity
    sunHaloSoftness?.pointee = sky.sunHaloSoftness
    cloudsEnabled?.pointee = sky.cloudsEnabled ? 1 : 0
    cloudsCoverage?.pointee = sky.cloudsCoverage
    cloudsSoftness?.pointee = sky.cloudsSoftness
    cloudsScale?.pointee = sky.cloudsScale
    cloudsSpeed?.pointee = sky.cloudsSpeed
    cloudsWindX?.pointee = sky.cloudsWindDirection.x
    cloudsWindY?.pointee = sky.cloudsWindDirection.y
    cloudsHeight?.pointee = sky.cloudsHeight
    cloudsThickness?.pointee = sky.cloudsThickness
    cloudsBrightness?.pointee = sky.cloudsBrightness
    cloudsSunInfluence?.pointee = sky.cloudsSunInfluence
    autoRebuild?.pointee = sky.realtimeUpdate ? 1 : 0
    needsRebuild?.pointee = sky.needsRebuild ? 1 : 0
    let hdriString = sky.hdriHandle?.rawValue.uuidString ?? ""
    _ = writeCString(hdriString, to: hdriHandle, max: hdriHandleSize)
    return 1
}

@_cdecl("MCEEditorSetSkyLight")
public func MCEEditorSetSkyLight(_ contextPtr: UnsafeRawPointer?,
                                 _ entityId: UnsafePointer<CChar>?, _ mode: Int32, _ enabled: UInt32,
                                 _ intensity: Float, _ tintX: Float, _ tintY: Float, _ tintZ: Float,
                                 _ turbidity: Float, _ azimuth: Float, _ elevation: Float, _ sunSize: Float,
                                 _ zenithTintX: Float, _ zenithTintY: Float, _ zenithTintZ: Float,
                                 _ horizonTintX: Float, _ horizonTintY: Float, _ horizonTintZ: Float,
                                 _ gradientStrength: Float,
                                 _ hazeDensity: Float, _ hazeFalloff: Float, _ hazeHeight: Float,
                                 _ ozoneStrength: Float, _ ozoneTintX: Float, _ ozoneTintY: Float, _ ozoneTintZ: Float,
                                 _ sunHaloSize: Float, _ sunHaloIntensity: Float, _ sunHaloSoftness: Float,
                                 _ cloudsEnabled: UInt32, _ cloudsCoverage: Float, _ cloudsSoftness: Float,
                                 _ cloudsScale: Float, _ cloudsSpeed: Float,
                                 _ cloudsWindX: Float, _ cloudsWindY: Float,
                                 _ cloudsHeight: Float, _ cloudsThickness: Float,
                                 _ cloudsBrightness: Float, _ cloudsSunInfluence: Float,
                                 _ autoRebuild: UInt32,
                                 _ hdriHandle: UnsafePointer<CChar>?) {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return }
    let previous = ecs.get(SkyLightComponent.self, for: entity) ?? SkyLightComponent()
    var sky = previous
    sky.mode = SkyMode(rawValue: UInt32(max(0, mode))) ?? .hdri
    sky.enabled = enabled != 0
    sky.intensity = max(0.0, intensity)
    sky.skyTint = SIMD3<Float>(max(0.0, tintX), max(0.0, tintY), max(0.0, tintZ))
    sky.turbidity = max(1.0, turbidity)
    sky.azimuthDegrees = azimuth
    sky.elevationDegrees = elevation
    sky.sunSizeDegrees = max(0.01, sunSize)
    sky.zenithTint = SIMD3<Float>(max(0.0, zenithTintX), max(0.0, zenithTintY), max(0.0, zenithTintZ))
    sky.horizonTint = SIMD3<Float>(max(0.0, horizonTintX), max(0.0, horizonTintY), max(0.0, horizonTintZ))
    sky.gradientStrength = max(0.0, gradientStrength)
    sky.hazeDensity = max(0.0, hazeDensity)
    sky.hazeFalloff = max(0.01, hazeFalloff)
    sky.hazeHeight = hazeHeight
    sky.ozoneStrength = max(0.0, ozoneStrength)
    sky.ozoneTint = SIMD3<Float>(max(0.0, ozoneTintX), max(0.0, ozoneTintY), max(0.0, ozoneTintZ))
    sky.sunHaloSize = max(0.1, sunHaloSize)
    sky.sunHaloIntensity = max(0.0, sunHaloIntensity)
    sky.sunHaloSoftness = max(0.05, sunHaloSoftness)
    sky.cloudsEnabled = cloudsEnabled != 0
    sky.cloudsCoverage = max(0.0, min(cloudsCoverage, 1.0))
    sky.cloudsSoftness = max(0.01, min(cloudsSoftness, 1.0))
    sky.cloudsScale = max(0.01, cloudsScale)
    sky.cloudsSpeed = cloudsSpeed
    sky.cloudsWindDirection = SIMD2<Float>(cloudsWindX, cloudsWindY)
    sky.cloudsHeight = max(0.0, min(cloudsHeight, 1.0))
    sky.cloudsThickness = max(0.0, min(cloudsThickness, 1.0))
    sky.cloudsBrightness = max(0.0, cloudsBrightness)
    sky.cloudsSunInfluence = max(0.0, cloudsSunInfluence)
    sky.realtimeUpdate = autoRebuild != 0
    if let hdriHandle {
        let hdriString = String(cString: hdriHandle)
        sky.hdriHandle = handleFromString(hdriString)
    } else {
        sky.hdriHandle = nil
    }
    if SkySystem.requiresIBLRebuild(previous: previous, next: sky) {
        sky.needsRebuild = true
        sky.rebuildRequested = false
    }
    ecs.add(sky, to: entity)
    if sky.needsRebuild {
        context.engineContext.log.logInfo("Sky regenerate requested: \(entity.id.uuidString)", category: .scene)
    }
    context.editorProjectManager.notifySceneMutation()
}

@_cdecl("MCEEditorRequestSkyRebuild")
public func MCEEditorRequestSkyRebuild(_ contextPtr: UnsafeRawPointer?,
                                       _ entityId: UnsafePointer<CChar>?) {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          var sky = ecs.get(SkyLightComponent.self, for: entity) else { return }
    sky.needsRebuild = true
    sky.rebuildRequested = true
    ecs.add(sky, to: entity)
    context.editorProjectManager.notifySceneMutation()
}

@_cdecl("MCEEditorRequestActiveSkyRebuild")
public func MCEEditorRequestActiveSkyRebuild(_ contextPtr: UnsafeRawPointer?) {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          let ecs = editorECS(context),
          let (entity, sky) = ecs.activeSkyLight() else { return }
    var updated = sky
    updated.needsRebuild = true
    ecs.add(updated, to: entity)
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
    guard let active = ensureActiveSkyEntity(ecs: ecs, logger: context.engineContext.log) else { return 0 }
    return writeCString(active.id.uuidString, to: buffer, max: bufferSize)
}

@_cdecl("MCEEditorSetActiveSky")
public func MCEEditorSetActiveSky(_ contextPtr: UnsafeRawPointer?,
                                  _ entityId: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return 0 }
    setActiveSky(ecs: ecs, entity: entity, logger: context.engineContext.log)
    context.editorProjectManager.notifySceneMutation()
    return 1
}
