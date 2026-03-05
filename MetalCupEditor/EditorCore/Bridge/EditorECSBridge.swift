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

private func isFinite(_ value: SIMD3<Float>) -> Bool {
    value.x.isFinite && value.y.isFinite && value.z.isFinite
}

private func isFinite(_ value: SIMD4<Float>) -> Bool {
    value.x.isFinite && value.y.isFinite && value.z.isFinite && value.w.isFinite
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
    case script = 9
    case characterController = 10
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

private func parseEntityIdCSV(_ csv: UnsafePointer<CChar>?) -> [UUID] {
    guard let csv else { return [] }
    let raw = String(cString: csv)
    guard !raw.isEmpty else { return [] }
    var ids: [UUID] = []
    for token in raw.split(separator: ",") {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = UUID(uuidString: trimmed), !ids.contains(id) else { continue }
        ids.append(id)
    }
    return ids
}

private func resolvePrefabInstance(_ context: MCEContext,
                                   _ entityId: UnsafePointer<CChar>?) -> (scene: EngineScene, entity: Entity, link: PrefabInstanceComponent)? {
    guard let scene = context.editorSceneController.activeScene(),
          let entity = entity(from: entityId, context: context),
          let link = scene.ecs.get(PrefabInstanceComponent.self, for: entity) else {
        return nil
    }
    return (scene, entity, link)
}

private func controllerCapsuleShape(radius: Float, height: Float) -> ColliderShape {
    let safeRadius = max(0.05, radius)
    let standingHalfHeight = max(safeRadius, height * 0.5)
    let capsuleHalfHeight = max(0.05, standingHalfHeight - safeRadius)
    return ColliderShape(isEnabled: true,
                         shapeType: .capsule,
                         boxHalfExtents: SIMD3<Float>(repeating: 0.5),
                         sphereRadius: safeRadius,
                         capsuleHalfHeight: capsuleHalfHeight,
                         capsuleRadius: safeRadius,
                         offset: .zero,
                         rotationOffset: .zero,
                         isTrigger: false,
                         collisionLayerOverride: nil,
                         physicsMaterial: nil)
}

private func controllerCapsuleShape(from controller: CharacterControllerComponent) -> ColliderShape {
    controllerCapsuleShape(radius: controller.radius, height: controller.height)
}

private func preferredCharacterCollisionLayer(context: MCEContext) -> Int32 {
    let names = context.engineContext.physicsSettings.collisionLayerNames
    if let index = names.firstIndex(where: { $0.lowercased() == "player" }) {
        return Int32(index)
    }
    if let index = names.firstIndex(where: { $0.lowercased().contains("player") }) {
        return Int32(index)
    }
    return 0
}

private func autoSizedControllerDimensions(context: MCEContext,
                                           ecs: SceneECS,
                                           entity: Entity,
                                           fallback: CharacterControllerComponent) -> (radius: Float, height: Float) {
    guard let renderer = ecs.get(MeshRendererComponent.self, for: entity),
          let meshHandle = renderer.meshHandle,
          let mesh = context.engineContext.assets.mesh(handle: meshHandle) else {
        return (max(0.05, fallback.radius), max(0.2, fallback.height))
    }
    // Use mesh bounding sphere to derive a practical capsule when explicit authored size is missing.
    let boundsRadius = max(0.001, mesh.editorBoundsRadius)
    let radius = min(1.5, max(0.2, boundsRadius * 0.35))
    let height = min(4.0, max(radius * 2.2, boundsRadius * 1.8))
    return (radius, height)
}

@discardableResult
private func ensureCharacterControllerRigidbody(context: MCEContext,
                                                ecs: SceneECS,
                                                entity: Entity) -> Bool {
    let collisionLayer = preferredCharacterCollisionLayer(context: context)
    if var rigidbody = ecs.get(RigidbodyComponent.self, for: entity) {
        var didMutate = false
        if rigidbody.motionType != .kinematic {
            rigidbody.motionType = .kinematic
            didMutate = true
        }
        if rigidbody.gravityFactor != 0.0 {
            rigidbody.gravityFactor = 0.0
            didMutate = true
        }
        if rigidbody.allowSleeping {
            rigidbody.allowSleeping = false
            didMutate = true
        }
        if rigidbody.collisionLayer != collisionLayer {
            rigidbody.collisionLayer = collisionLayer
            didMutate = true
        }
        if didMutate {
            ecs.add(rigidbody, to: entity)
        }
        return didMutate
    }

    let defaults = context.engineContext.physicsSettings
    let rigidbody = RigidbodyComponent(isEnabled: true,
                                       motionType: .kinematic,
                                       mass: 1.0,
                                       friction: defaults.defaultFriction,
                                       restitution: defaults.defaultRestitution,
                                       linearDamping: defaults.defaultLinearDamping,
                                       angularDamping: defaults.defaultAngularDamping,
                                       gravityFactor: 0.0,
                                       allowSleeping: false,
                                       ccdEnabled: false,
                                       collisionLayer: collisionLayer,
                                       bodyId: nil)
    ecs.add(rigidbody, to: entity)
    return true
}

@discardableResult
private func ensureCharacterControllerCapsuleCollider(context: MCEContext,
                                                      ecs: SceneECS,
                                                      entity: Entity,
                                                      controller: CharacterControllerComponent,
                                                      autoSizeFromMesh: Bool) -> Bool {
    let chosenDimensions: (radius: Float, height: Float) = autoSizeFromMesh
        ? autoSizedControllerDimensions(context: context, ecs: ecs, entity: entity, fallback: controller)
        : (radius: max(0.05, controller.radius), height: max(0.2, controller.height))
    let desiredShape = controllerCapsuleShape(radius: chosenDimensions.radius, height: chosenDimensions.height)

    if var collider = ecs.get(ColliderComponent.self, for: entity) {
        let hasSolidCapsule = collider.allShapes().contains {
            $0.isEnabled && !$0.isTrigger && $0.shapeType == .capsule
        }
        if hasSolidCapsule {
            return false
        }
        let preservedTriggers = collider.allShapes().filter { $0.isTrigger && $0.isEnabled }
        var shapes: [ColliderShape] = [desiredShape]
        shapes.append(contentsOf: preservedTriggers)
        collider.setShapes(shapes)
        ecs.add(collider, to: entity)
    } else {
        var collider = ColliderComponent()
        collider.setShapes([desiredShape])
        ecs.add(collider, to: entity)
    }

    var updatedController = controller
    updatedController.radius = chosenDimensions.radius
    updatedController.height = chosenDimensions.height
    ecs.add(updatedController, to: entity)
    return true
}

private func ensureCharacterControllerDependencies(context: MCEContext,
                                                   ecs: SceneECS,
                                                   entity: Entity,
                                                   controller: CharacterControllerComponent) -> Bool {
    _ = context
    _ = ecs
    _ = entity
    _ = controller
    return false
}

private func convertCharacterControllerColliderToCapsule(ecs: SceneECS,
                                                         entity: Entity,
                                                         controller: CharacterControllerComponent) -> Bool {
    guard var collider = ecs.get(ColliderComponent.self, for: entity) else { return false }
    let primary = controllerCapsuleShape(from: controller)
    let preservedTriggers = collider.allShapes().filter { $0.isTrigger && $0.isEnabled }
    var finalShapes: [ColliderShape] = [primary]
    finalShapes.append(contentsOf: preservedTriggers)
    collider.setShapes(finalShapes)
    ecs.add(collider, to: entity)
    return true
}

private func firstDirectChild(named name: String, parent: Entity, ecs: SceneECS) -> Entity? {
    ecs.getChildren(parent).first { child in
        (ecs.get(NameComponent.self, for: child)?.name ?? "") == name
    }
}

private func ensureNamedChild(named name: String,
                              parent: Entity,
                              ecs: SceneECS) -> (child: Entity, created: Bool) {
    if let existing = firstDirectChild(named: name, parent: parent, ecs: ecs) {
        return (existing, false)
    }
    let child = ecs.createEntity(name: name)
    _ = ecs.setParent(child, parent, keepWorldTransform: false)
    return (child, true)
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
        script: ecs.get(ScriptComponent.self, for: entity).map { component in
            ScriptComponentDTO(component: component)
        },
        characterController: ecs.get(CharacterControllerComponent.self, for: entity).map { component in
            CharacterControllerComponentDTO(component: component)
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

private func applyComponentsDocument(_ components: ComponentsDocument, to entity: Entity, ecs: SceneECS) {
    if let name = components.name {
        ecs.add(NameComponent(name: name.name), to: entity)
    }
    if let transform = components.transform {
        ecs.add(
            TransformComponent(
                position: transform.position.toSIMD(),
                rotation: transform.rotationQuat.toSIMD(),
                scale: transform.scale.toSIMD()
            ),
            to: entity
        )
    } else {
        ecs.add(TransformComponent(), to: entity)
    }
    if let layer = components.layer {
        ecs.add(LayerComponent(index: layer.layerIndex), to: entity)
    } else {
        ecs.add(LayerComponent(), to: entity)
    }
    if let meshRenderer = components.meshRenderer {
        ecs.add(
            MeshRendererComponent(
                meshHandle: meshRenderer.meshHandle,
                materialHandle: meshRenderer.materialHandle,
                submeshMaterialHandles: meshRenderer.submeshMaterialHandles,
                material: meshRenderer.material?.toMaterial(),
                albedoMapHandle: meshRenderer.albedoMapHandle,
                normalMapHandle: meshRenderer.normalMapHandle,
                metallicMapHandle: meshRenderer.metallicMapHandle,
                roughnessMapHandle: meshRenderer.roughnessMapHandle,
                mrMapHandle: meshRenderer.mrMapHandle,
                ormMapHandle: meshRenderer.ormMapHandle,
                aoMapHandle: meshRenderer.aoMapHandle,
                emissiveMapHandle: meshRenderer.emissiveMapHandle
            ),
            to: entity
        )
    }
    if let materialComponent = components.materialComponent {
        ecs.add(MaterialComponent(materialHandle: materialComponent.materialHandle), to: entity)
    }
    if let rigidbody = components.rigidbody {
        ecs.add(rigidbody.toComponent(), to: entity)
    }
    if let collider = components.collider {
        ecs.add(collider.toComponent(), to: entity)
    }
    if let light = components.light {
        ecs.add(
            LightComponent(
                type: light.type.toLightType(),
                data: light.data.toLightData(),
                direction: light.direction.toSIMD(),
                range: light.range,
                innerConeCos: light.innerConeCos,
                outerConeCos: light.outerConeCos,
                castsShadows: light.castsShadows
            ),
            to: entity
        )
    }
    if let lightOrbit = components.lightOrbit {
        ecs.add(lightOrbit.toComponent(), to: entity)
    }
    if let camera = components.camera {
        ecs.add(camera.toComponent(), to: entity)
    }
    if let script = components.script {
        ecs.add(script.toComponent(), to: entity)
    }
    if let characterController = components.characterController {
        ecs.add(characterController.toComponent(), to: entity)
    }
    if let sky = components.sky {
        ecs.add(SkyComponent(environmentMapHandle: sky.environmentMapHandle), to: entity)
    }
    if let skyLight = components.skyLight {
        ecs.add(
            SkyLightComponent(
                mode: SkyMode(rawValue: skyLight.mode) ?? .hdri,
                enabled: skyLight.enabled,
                intensity: skyLight.intensity,
                skyTint: skyLight.skyTint.toSIMD(),
                turbidity: skyLight.turbidity,
                azimuthDegrees: skyLight.azimuthDegrees,
                elevationDegrees: skyLight.elevationDegrees,
                sunSizeDegrees: skyLight.sunSizeDegrees,
                zenithTint: skyLight.zenithTint.toSIMD(),
                horizonTint: skyLight.horizonTint.toSIMD(),
                gradientStrength: skyLight.gradientStrength,
                hazeDensity: skyLight.hazeDensity,
                hazeFalloff: skyLight.hazeFalloff,
                hazeHeight: skyLight.hazeHeight,
                ozoneStrength: skyLight.ozoneStrength,
                ozoneTint: skyLight.ozoneTint.toSIMD(),
                sunHaloSize: skyLight.sunHaloSize,
                sunHaloIntensity: skyLight.sunHaloIntensity,
                sunHaloSoftness: skyLight.sunHaloSoftness,
                cloudsEnabled: skyLight.cloudsEnabled,
                cloudsCoverage: skyLight.cloudsCoverage,
                cloudsSoftness: skyLight.cloudsSoftness,
                cloudsScale: skyLight.cloudsScale,
                cloudsSpeed: skyLight.cloudsSpeed,
                cloudsWindDirection: SIMD2<Float>(skyLight.cloudsWindX, skyLight.cloudsWindY),
                cloudsHeight: skyLight.cloudsHeight,
                cloudsThickness: skyLight.cloudsThickness,
                cloudsBrightness: skyLight.cloudsBrightness,
                cloudsSunInfluence: skyLight.cloudsSunInfluence,
                hdriHandle: skyLight.hdriHandle,
                needsRebuild: true,
                rebuildRequested: false,
                realtimeUpdate: skyLight.realtimeUpdate,
                lastRebuildTime: 0.0
            ),
            to: entity
        )
    }
    if components.skyLightTag != nil {
        ecs.add(SkyLightTag(), to: entity)
    }
    if components.skySunTag != nil {
        ecs.add(SkySunTag(), to: entity)
    }
}

private func makeUniqueCopyName(_ base: String, existingLowerNames: Set<String>) -> String {
    let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
    let source = trimmed.isEmpty ? "Entity" : trimmed
    let initial = "\(source) (Copy)"
    if !existingLowerNames.contains(initial.lowercased()) {
        return initial
    }
    var index = 2
    while index < 10000 {
        let candidate = "\(source) (Copy \(index))"
        if !existingLowerNames.contains(candidate.lowercased()) {
            return candidate
        }
        index += 1
    }
    return "\(source) (Copy \(UUID().uuidString.prefix(4)))"
}

private func markHierarchyOverrideIfPrefabInstance(_ ecs: SceneECS, _ entity: Entity) {
    guard ecs.has(PrefabInstanceComponent.self, entity) else { return }
    var overrides = ecs.get(PrefabOverrideComponent.self, for: entity) ?? PrefabOverrideComponent()
    overrides.overridden.insert(.hierarchy)
    ecs.add(overrides, to: entity)
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

private func scriptFieldDescriptors(context: MCEContext, script: ScriptComponent) -> [ScriptFieldDescriptor] {
    guard let handle = script.scriptAssetHandle else { return [] }
    return ScriptMetadataCache.shared.descriptors(scriptAssetHandle: handle,
                                                  typeName: script.typeName,
                                                  assetDatabase: context.engineContext.assetDatabase)
}

private func scriptFieldValues(script: ScriptComponent, descriptors: [ScriptFieldDescriptor]) -> [String: ScriptFieldValue] {
    let decodedBlob = ScriptFieldBlobCodec.decodeFieldBlobV1(script.fieldData)
    var merged = ScriptFieldBlobCodec.mergedValues(from: script.fieldData, schemaDescriptors: descriptors)
    if script.serializedFields.isEmpty { return merged }
    for descriptor in descriptors {
        guard let value = script.serializedFields[descriptor.name] else { continue }
        let coercedLegacy = ScriptFieldBlobCodec.coerce(value, to: descriptor.type) ?? descriptor.defaultValue
        if decodedBlob[descriptor.name] == nil ||
            shouldPreferLegacyReferenceValue(type: descriptor.type,
                                             blobValue: merged[descriptor.name],
                                             legacyValue: coercedLegacy) {
            merged[descriptor.name] = coercedLegacy
        }
    }
    return merged
}

private func scriptFieldMetadataDictionary(from descriptors: [ScriptFieldDescriptor]) -> [String: ScriptFieldMetadata] {
    Dictionary(uniqueKeysWithValues: descriptors.map { ($0.name, $0.metadata) })
}

private extension ScriptFieldValue {
    var entityUUIDValue: UUID? {
        switch self {
        case let .entity(value):
            return value
        case let .string(text):
            return UUID(uuidString: text)
        default:
            return nil
        }
    }

    var prefabHandleValue: AssetHandle? {
        switch self {
        case let .prefab(handle):
            return handle
        case let .string(text):
            guard let uuid = UUID(uuidString: text) else { return nil }
            return AssetHandle(rawValue: uuid)
        default:
            return nil
        }
    }
}

private func shouldPreferLegacyReferenceValue(type: ScriptFieldType,
                                              blobValue: ScriptFieldValue?,
                                              legacyValue: ScriptFieldValue) -> Bool {
    switch type {
    case .entity:
        guard case .entity(nil)? = blobValue else { return false }
        if case .entity(let uuid?) = legacyValue { return !uuid.uuidString.isEmpty }
        return false
    case .prefab:
        guard case .prefab(nil)? = blobValue else { return false }
        if case .prefab(let handle?) = legacyValue { return !handle.rawValue.uuidString.isEmpty }
        return false
    default:
        return false
    }
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

@_cdecl("MCEEditorGetSelectedEntityCount")
public func MCEEditorGetSelectedEntityCount(_ contextPtr: UnsafeRawPointer?) -> Int32 {
    guard let context = resolveContext(contextPtr) else { return 0 }
    return Int32(context.editorSceneController.selectedEntityUUIDs().count)
}

@_cdecl("MCEEditorGetSelectedEntityIdAt")
public func MCEEditorGetSelectedEntityIdAt(_ contextPtr: UnsafeRawPointer?,
                                           _ index: Int32,
                                           _ buffer: UnsafeMutablePointer<CChar>?,
                                           _ bufferSize: Int32) -> Int32 {
    guard let context = resolveContext(contextPtr), index >= 0 else { return 0 }
    let ids = context.editorSceneController.selectedEntityUUIDs()
    guard index < Int32(ids.count) else { return 0 }
    return writeCString(ids[Int(index)].uuidString, to: buffer, max: bufferSize)
}

@_cdecl("MCEEditorSetSelectedEntitiesCSV")
public func MCEEditorSetSelectedEntitiesCSV(_ contextPtr: UnsafeRawPointer?,
                                            _ csv: UnsafePointer<CChar>?,
                                            _ primaryId: UnsafePointer<CChar>?) {
    guard let context = resolveContext(contextPtr) else { return }
    let requested = parseEntityIdCSV(csv)
    guard let scene = context.editorSceneController.activeScene() else {
        context.editorSceneController.setSelectedEntityIds([], primary: nil)
        return
    }
    var filtered: [UUID] = []
    filtered.reserveCapacity(requested.count)
    for id in requested where scene.ecs.entity(with: id) != nil {
        filtered.append(id)
    }
    let primary = primaryId.flatMap { UUID(uuidString: String(cString: $0)) }
    context.editorSceneController.setSelectedEntityIds(filtered, primary: primary)
}

@_cdecl("MCEEditorGetRootEntityCount")
public func MCEEditorGetRootEntityCount(_ contextPtr: UnsafeRawPointer?) -> Int32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context) else { return 0 }
    return Int32(ecs.rootLevelEntities().count)
}

@_cdecl("MCEEditorGetRootEntityIdAt")
public func MCEEditorGetRootEntityIdAt(_ contextPtr: UnsafeRawPointer?,
                                       _ index: Int32,
                                       _ buffer: UnsafeMutablePointer<CChar>?,
                                       _ bufferSize: Int32) -> Int32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          index >= 0 else { return 0 }
    let roots = ecs.rootLevelEntities()
    guard index < Int32(roots.count) else { return 0 }
    return writeCString(roots[Int(index)].id.uuidString, to: buffer, max: bufferSize)
}

@_cdecl("MCEEditorGetChildEntityCount")
public func MCEEditorGetChildEntityCount(_ contextPtr: UnsafeRawPointer?,
                                         _ parentId: UnsafePointer<CChar>?) -> Int32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let parent = entity(from: parentId, context: context) else { return 0 }
    return Int32(ecs.getChildren(parent).count)
}

@_cdecl("MCEEditorGetChildEntityIdAt")
public func MCEEditorGetChildEntityIdAt(_ contextPtr: UnsafeRawPointer?,
                                        _ parentId: UnsafePointer<CChar>?,
                                        _ index: Int32,
                                        _ buffer: UnsafeMutablePointer<CChar>?,
                                        _ bufferSize: Int32) -> Int32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let parent = entity(from: parentId, context: context),
          index >= 0 else { return 0 }
    let children = ecs.getChildren(parent)
    guard index < Int32(children.count) else { return 0 }
    return writeCString(children[Int(index)].id.uuidString, to: buffer, max: bufferSize)
}

@_cdecl("MCEEditorGetParentEntityId")
public func MCEEditorGetParentEntityId(_ contextPtr: UnsafeRawPointer?,
                                       _ childId: UnsafePointer<CChar>?,
                                       _ buffer: UnsafeMutablePointer<CChar>?,
                                       _ bufferSize: Int32) -> Int32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let child = entity(from: childId, context: context),
          let parent = ecs.getParent(child) else { return 0 }
    return writeCString(parent.id.uuidString, to: buffer, max: bufferSize)
}

@_cdecl("MCEEditorSetParent")
public func MCEEditorSetParent(_ contextPtr: UnsafeRawPointer?,
                               _ childId: UnsafePointer<CChar>?,
                               _ parentId: UnsafePointer<CChar>?,
                               _ keepWorldTransform: UInt32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          !context.editorSceneController.isSimulating,
          let ecs = editorECS(context),
          let child = entity(from: childId, context: context) else { return 0 }
    let keepWorld = keepWorldTransform != 0
    let parent = entity(from: parentId, context: context)
    let success = ecs.setParent(child, parent, keepWorldTransform: keepWorld)
    if success {
        markHierarchyOverrideIfPrefabInstance(ecs, child)
        context.editorProjectManager.notifySceneMutation()
    }
    return success ? 1 : 0
}

@_cdecl("MCEEditorUnparent")
public func MCEEditorUnparent(_ contextPtr: UnsafeRawPointer?,
                              _ childId: UnsafePointer<CChar>?,
                              _ keepWorldTransform: UInt32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          !context.editorSceneController.isSimulating,
          let ecs = editorECS(context),
          let child = entity(from: childId, context: context) else { return 0 }
    let success = ecs.unparent(child, keepWorldTransform: keepWorldTransform != 0)
    if success {
        markHierarchyOverrideIfPrefabInstance(ecs, child)
        context.editorProjectManager.notifySceneMutation()
    }
    return success ? 1 : 0
}

@_cdecl("MCEEditorReorderEntity")
public func MCEEditorReorderEntity(_ contextPtr: UnsafeRawPointer?,
                                   _ entityId: UnsafePointer<CChar>?,
                                   _ parentId: UnsafePointer<CChar>?,
                                   _ newIndex: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          !context.editorSceneController.isSimulating,
          let ecs = editorECS(context),
          let child = entity(from: entityId, context: context) else { return 0 }
    let parent = entity(from: parentId, context: context)
    let success = ecs.reorderChild(parent: parent, child: child, newIndex: Int(newIndex))
    if success {
        markHierarchyOverrideIfPrefabInstance(ecs, child)
        context.editorProjectManager.notifySceneMutation()
    }
    return success ? 1 : 0
}

@_cdecl("MCEEditorGetEntityIdAt")
public func MCEEditorGetEntityIdAt(_ contextPtr: UnsafeRawPointer?,
                                   _ index: Int32,
                                   _ buffer: UnsafeMutablePointer<CChar>?,
                                   _ bufferSize: Int32) -> Int32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          index >= 0 else { return 0 }
    let entities = ecs.allEntities()
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
          !context.editorSceneController.isSimulating,
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
          !context.editorSceneController.isSimulating,
          let ecs = editorECS(context) else { return 0 }
    let entityName = name != nil ? String(cString: name!) : "Entity"
    let entity = ecs.createEntity(name: entityName)
    context.editorProjectManager.notifySceneMutation()
    return writeCString(entity.id.uuidString, to: outId, max: outIdSize)
}

@_cdecl("MCEEditorDuplicateSelectedEntities")
public func MCEEditorDuplicateSelectedEntities(_ contextPtr: UnsafeRawPointer?,
                                               _ outPrimaryId: UnsafeMutablePointer<CChar>?,
                                               _ outPrimaryIdSize: Int32) -> Int32 {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          !context.editorSceneController.isSimulating,
          let ecs = editorECS(context) else { return 0 }

    let selected = context.editorSceneController.selectedEntityUUIDs().compactMap { ecs.entity(with: $0) }
    guard !selected.isEmpty else { return 0 }
    let selectedSet = Set(selected)
    let orderedAll = ecs.allEntities()
    let topLevel = orderedAll.filter { entity in
        guard selectedSet.contains(entity) else { return false }
        var current = ecs.getParent(entity)
        while let parent = current {
            if selectedSet.contains(parent) { return false }
            current = ecs.getParent(parent)
        }
        return true
    }
    guard !topLevel.isEmpty else { return 0 }

    var existingNamesLower = Set(orderedAll.compactMap { ecs.get(NameComponent.self, for: $0)?.name.lowercased() })
    var insertionOffsets: [Entity?: Int] = [:]
    var duplicatedRoots: [Entity] = []
    duplicatedRoots.reserveCapacity(topLevel.count)

    func cloneSubtree(_ source: Entity, newParent: Entity?, isRoot: Bool) -> Entity {
        let originalName = ecs.get(NameComponent.self, for: source)?.name ?? "Entity"
        let cloneName: String
        if isRoot {
            cloneName = makeUniqueCopyName(originalName, existingLowerNames: existingNamesLower)
            existingNamesLower.insert(cloneName.lowercased())
        } else {
            cloneName = originalName
        }

        let clone = ecs.createEntity(name: cloneName)
        let components = componentsDocument(for: source, ecs: ecs)
        applyComponentsDocument(components, to: clone, ecs: ecs)
        _ = ecs.setParent(clone, newParent, keepWorldTransform: false)

        for child in ecs.getChildren(source) {
            _ = cloneSubtree(child, newParent: clone, isRoot: false)
        }
        return clone
    }

    for sourceRoot in topLevel {
        let parent = ecs.getParent(sourceRoot)
        let siblingList = parent.map { ecs.getChildren($0) } ?? ecs.rootLevelEntities()
        let sourceIndex = siblingList.firstIndex(of: sourceRoot) ?? max(0, siblingList.count - 1)
        let offset = insertionOffsets[parent] ?? 0
        let desiredIndex = min(siblingList.count, sourceIndex + 1 + offset)

        let cloneRoot = cloneSubtree(sourceRoot, newParent: parent, isRoot: true)
        _ = ecs.reorderChild(parent: parent, child: cloneRoot, newIndex: desiredIndex)
        insertionOffsets[parent] = offset + 1
        duplicatedRoots.append(cloneRoot)
    }

    let newSelectionIds = duplicatedRoots.map { $0.id }
    context.editorSceneController.setSelectedEntityIds(newSelectionIds, primary: duplicatedRoots.last?.id)
    context.editorProjectManager.notifySceneMutation()
    if let primary = duplicatedRoots.last {
        return writeCString(primary.id.uuidString, to: outPrimaryId, max: outPrimaryIdSize)
    }
    return 0
}

@_cdecl("MCEEditorCreateMeshEntity")
public func MCEEditorCreateMeshEntity(_ contextPtr: UnsafeRawPointer?,
                                      _ meshType: Int32,
                                      _ outId: UnsafeMutablePointer<CChar>?,
                                      _ outIdSize: Int32) -> Int32 {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          !context.editorSceneController.isSimulating,
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
          !context.editorSceneController.isSimulating,
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
          !context.editorSceneController.isSimulating,
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
          !context.editorSceneController.isSimulating,
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
          !context.editorSceneController.isSimulating,
          let entity = entity(from: entityId, context: context),
          let scene = context.editorSceneController.activeScene() else { return 0 }
    let name = scene.ecs.get(NameComponent.self, for: entity)?.name ?? "Prefab"
    var prefabEntities: [PrefabEntityDocument] = []
    func appendSubtree(_ current: Entity, parentLocalId: UUID?) {
        let components = componentsDocument(for: current, ecs: scene.ecs)
        prefabEntities.append(
            PrefabEntityDocument(
                localId: current.id,
                parentLocalId: parentLocalId,
                components: components
            )
        )
        for child in scene.ecs.getChildren(current) {
            appendSubtree(child, parentLocalId: current.id)
        }
    }
    appendSubtree(entity, parentLocalId: nil)
    let prefab = PrefabDocument(name: name, entities: prefabEntities)
    guard let relativePath = AssetOps.createPrefab(context: contextPtr, prefab: prefab, relativePath: "Prefabs", name: name) else { return 0 }
    _ = writeCString(relativePath, to: outPath, max: outPathSize)
    return 1
}

@_cdecl("MCEEditorGetPrefabInstanceInfo")
public func MCEEditorGetPrefabInstanceInfo(_ contextPtr: UnsafeRawPointer?,
                                           _ entityId: UnsafePointer<CChar>?,
                                           _ prefabHandleOut: UnsafeMutablePointer<CChar>?,
                                           _ prefabHandleOutSize: Int32,
                                           _ prefabPathOut: UnsafeMutablePointer<CChar>?,
                                           _ prefabPathOutSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let resolved = resolvePrefabInstance(context, entityId) else { return 0 }
    let handleString = resolved.link.prefabHandle.rawValue.uuidString
    _ = writeCString(handleString, to: prefabHandleOut, max: prefabHandleOutSize)

    let metadataPath = context.editorProjectManager
        .assetMetadataSnapshot()
        .first(where: { $0.handle == resolved.link.prefabHandle })?
        .sourcePath
    let fallbackPath = context.editorProjectManager.assetURL(for: resolved.link.prefabHandle)?.lastPathComponent
    _ = writeCString(metadataPath ?? fallbackPath ?? "", to: prefabPathOut, max: prefabPathOutSize)
    return 1
}

@_cdecl("MCEEditorApplyPrefabInstanceToAsset")
public func MCEEditorApplyPrefabInstanceToAsset(_ contextPtr: UnsafeRawPointer?,
                                                _ entityId: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          !context.editorSceneController.isSimulating,
          let resolved = resolvePrefabInstance(context, entityId),
          let prefabURL = context.editorProjectManager.assetURL(for: resolved.link.prefabHandle) else { return 0 }

    do {
        let prefab = try PrefabSerializer.load(from: prefabURL)
        guard let entityIndex = prefab.entities.firstIndex(where: { $0.localId == resolved.link.prefabEntityId }) else {
            context.editorAlertCenter.enqueueError("Prefab entity could not be found for this instance.")
            return 0
        }

        let components = componentsDocument(for: resolved.entity, ecs: resolved.scene.ecs)
        var updatedEntities = prefab.entities
        let existing = updatedEntities[entityIndex]
        updatedEntities[entityIndex] = PrefabEntityDocument(
            localId: existing.localId,
            parentLocalId: existing.parentLocalId,
            components: components
        )
        let updatedPrefab = PrefabDocument(schemaVersion: prefab.schemaVersion, name: prefab.name, entities: updatedEntities)

        let saved = context.editorProjectManager.performAssetMutation {
            try PrefabSerializer.save(prefab: updatedPrefab, to: prefabURL)
            return true
        }
        guard saved else { return 0 }

        resolved.scene.ecs.remove(PrefabOverrideComponent.self, from: resolved.entity)
        context.engineContext.prefabSystem.applyPrefabs(handles: Set([resolved.link.prefabHandle]), to: resolved.scene)
        context.editorProjectManager.notifySceneMutation()
        return 1
    } catch {
        context.editorAlertCenter.enqueueError("Failed to apply prefab: \(error.localizedDescription)")
        return 0
    }
}

@_cdecl("MCEEditorRevertPrefabInstance")
public func MCEEditorRevertPrefabInstance(_ contextPtr: UnsafeRawPointer?,
                                          _ entityId: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          !context.editorSceneController.isSimulating,
          let resolved = resolvePrefabInstance(context, entityId) else { return 0 }

    do {
        guard let prefabURL = context.editorProjectManager.assetURL(for: resolved.link.prefabHandle) else { return 0 }
        let prefab = try PrefabSerializer.load(from: prefabURL)
        guard prefab.entities.contains(where: { $0.localId == resolved.link.prefabEntityId }) else {
            context.editorAlertCenter.enqueueError("Prefab entity could not be found for this instance.")
            return 0
        }
    } catch {
        context.editorAlertCenter.enqueueError("Failed to load prefab for revert: \(error.localizedDescription)")
        return 0
    }

    resolved.scene.ecs.remove(PrefabOverrideComponent.self, from: resolved.entity)
    guard context.engineContext.prefabSystem.reapplyInstance(entity: resolved.entity, in: resolved.scene) else { return 0 }
    context.editorProjectManager.notifySceneMutation()
    return 1
}

@_cdecl("MCEEditorCreateLightEntity")
public func MCEEditorCreateLightEntity(_ contextPtr: UnsafeRawPointer?,
                                       _ lightType: Int32,
                                       _ outId: UnsafeMutablePointer<CChar>?,
                                       _ outIdSize: Int32) -> Int32 {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          !context.editorSceneController.isSimulating,
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
          !context.editorSceneController.isSimulating,
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
          !context.editorSceneController.isSimulating,
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
          !context.editorSceneController.isSimulating,
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
          !context.editorSceneController.isSimulating,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return }
    ecs.destroyEntity(entity)
    context.editorProjectManager.notifySceneMutation()
}

@_cdecl("MCEEditorDestroySelectedEntities")
public func MCEEditorDestroySelectedEntities(_ contextPtr: UnsafeRawPointer?) {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          !context.editorSceneController.isSimulating,
          let ecs = editorECS(context) else { return }
    let selected = context.editorSceneController.selectedEntityUUIDs().compactMap { ecs.entity(with: $0) }
    guard !selected.isEmpty else { return }

    let selectedSet = Set(selected)
    let orderedAll = ecs.allEntities()
    let topLevel = orderedAll.filter { entity in
        guard selectedSet.contains(entity) else { return false }
        var current = ecs.getParent(entity)
        while let parent = current {
            if selectedSet.contains(parent) { return false }
            current = ecs.getParent(parent)
        }
        return true
    }

    for entity in topLevel.reversed() {
        ecs.destroyEntity(entity)
    }
    context.editorSceneController.setSelectedEntityIds([], primary: nil)
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
    case .script:
        return ecs.has(ScriptComponent.self, entity) ? 1 : 0
    case .characterController:
        return ecs.has(CharacterControllerComponent.self, entity) ? 1 : 0
    }
}

@_cdecl("MCEEditorAddComponent")
public func MCEEditorAddComponent(_ contextPtr: UnsafeRawPointer?,
                                  _ entityId: UnsafePointer<CChar>?,
                                  _ componentType: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          !context.editorSceneController.isSimulating,
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
            linearDamping: defaults.defaultLinearDamping,
            angularDamping: defaults.defaultAngularDamping
        )
        ecs.add(component, to: entity)
    case .collider:
        ecs.add(ColliderComponent(), to: entity)
    case .script:
        ecs.add(ScriptComponent(), to: entity)
    case .characterController:
        let controller = CharacterControllerComponent()
        ecs.add(controller, to: entity)
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
          !context.editorSceneController.isSimulating,
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
    case .script:
        ecs.remove(ScriptComponent.self, from: entity)
    case .characterController:
        ecs.remove(CharacterControllerComponent.self, from: entity)
    }
    context.editorProjectManager.notifySceneMutation()
    return 1
}

@_cdecl("MCEEditorGetScript")
public func MCEEditorGetScript(_ contextPtr: UnsafeRawPointer?,
                               _ entityId: UnsafePointer<CChar>?,
                               _ enabled: UnsafeMutablePointer<UInt32>?,
                               _ scriptHandle: UnsafeMutablePointer<CChar>?, _ scriptHandleSize: Int32,
                               _ typeName: UnsafeMutablePointer<CChar>?, _ typeNameSize: Int32,
                               _ fieldByteSize: UnsafeMutablePointer<UInt32>?,
                               _ fieldDataVersion: UnsafeMutablePointer<UInt32>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let script = ecs.get(ScriptComponent.self, for: entity) else { return 0 }
    enabled?.pointee = script.enabled ? 1 : 0
    if let handle = script.scriptAssetHandle {
        _ = writeCString(handle.rawValue.uuidString, to: scriptHandle, max: scriptHandleSize)
    } else {
        _ = writeCString("", to: scriptHandle, max: scriptHandleSize)
    }
    _ = writeCString(script.typeName, to: typeName, max: typeNameSize)
    fieldByteSize?.pointee = UInt32(script.fieldData.count)
    fieldDataVersion?.pointee = script.fieldDataVersion
    return 1
}

@_cdecl("MCEEditorSetScript")
public func MCEEditorSetScript(_ contextPtr: UnsafeRawPointer?,
                               _ entityId: UnsafePointer<CChar>?,
                               _ enabled: UInt32,
                               _ scriptHandle: UnsafePointer<CChar>?,
                               _ typeName: UnsafePointer<CChar>?,
                               _ keepFieldData: UInt32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isSimulating,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return 0 }
    var component = ecs.get(ScriptComponent.self, for: entity) ?? ScriptComponent()
    component.enabled = enabled != 0
    component.typeName = typeName.map { String(cString: $0) } ?? component.typeName
    if let scriptHandle {
        let parsed = handleFromString(String(cString: scriptHandle))
        component.scriptAssetHandle = parsed
        if let parsed {
            if component.typeName.isEmpty,
               let entryTypeName = context.engineContext.assetDatabase?.metadata(for: parsed)?.entryTypeName,
               !entryTypeName.isEmpty {
                component.typeName = entryTypeName
            }
            ScriptMetadataCache.shared.invalidate(handle: parsed)
            let descriptors = ScriptMetadataCache.shared.descriptors(scriptAssetHandle: parsed,
                                                                     typeName: component.typeName,
                                                                     assetDatabase: context.engineContext.assetDatabase)
            let mergedValues: [String: ScriptFieldValue]
            if keepFieldData == 0 {
                mergedValues = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.name, $0.defaultValue) })
            } else {
                let existingValues = ScriptFieldBlobCodec.decodeFieldBlobV1(component.fieldData)
                var values: [String: ScriptFieldValue] = [:]
                values.reserveCapacity(descriptors.count)
                for descriptor in descriptors {
                    values[descriptor.name] = existingValues[descriptor.name] ?? descriptor.defaultValue
                }
                mergedValues = values
            }
            component.serializedFields = mergedValues
            component.fieldMetadata = scriptFieldMetadataDictionary(from: descriptors)
            component.fieldData = ScriptFieldBlobCodec.encodeFieldBlobV1(mergedValues, schemaDescriptors: descriptors)
            component.fieldDataVersion = 1
        }
    } else {
        component.scriptAssetHandle = nil
    }
    component.typeName = typeName.map { String(cString: $0) } ?? component.typeName
    component.runtimeState = component.enabled ? .unloaded : .disabled
    component.hasInstance = false
    component.instanceHandle = 0
    component.lastError = ""
    if keepFieldData == 0 && component.scriptAssetHandle == nil {
        component.fieldData = Data()
        component.fieldDataVersion = max(1, component.fieldDataVersion)
        component.serializedFields = [:]
        component.fieldMetadata = [:]
    }
    ecs.add(component, to: entity)
    context.editorProjectManager.notifySceneMutation()
    return 1
}

@_cdecl("MCEEditorClearScriptFieldData")
public func MCEEditorClearScriptFieldData(_ contextPtr: UnsafeRawPointer?,
                                          _ entityId: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isSimulating,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          var script = ecs.get(ScriptComponent.self, for: entity) else { return 0 }
    script.fieldData = Data()
    script.fieldDataVersion = max(1, script.fieldDataVersion)
    script.serializedFields = [:]
    script.fieldMetadata = [:]
    ecs.add(script, to: entity)
    context.editorProjectManager.notifySceneMutation()
    return 1
}

@_cdecl("MCEEditorResetScriptFieldsToDefaults")
public func MCEEditorResetScriptFieldsToDefaults(_ contextPtr: UnsafeRawPointer?,
                                                 _ entityId: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isSimulating,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          var script = ecs.get(ScriptComponent.self, for: entity) else { return 0 }
    let descriptors = scriptFieldDescriptors(context: context, script: script)
    guard !descriptors.isEmpty else { return 0 }
    let values = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.name, $0.defaultValue) })
    script.serializedFields = values
    script.fieldMetadata = scriptFieldMetadataDictionary(from: descriptors)
    script.fieldData = ScriptFieldBlobCodec.encodeFieldBlobV1(values, schemaDescriptors: descriptors)
    script.fieldDataVersion = 1
    ecs.add(script, to: entity)
    context.editorProjectManager.notifySceneMutation()
    return 1
}

@_cdecl("MCEEditorGetScriptFieldCount")
public func MCEEditorGetScriptFieldCount(_ contextPtr: UnsafeRawPointer?,
                                         _ entityId: UnsafePointer<CChar>?) -> Int32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let script = ecs.get(ScriptComponent.self, for: entity) else { return 0 }
    return Int32(scriptFieldDescriptors(context: context, script: script).count)
}

@_cdecl("MCEEditorGetScriptFieldAt")
public func MCEEditorGetScriptFieldAt(_ contextPtr: UnsafeRawPointer?,
                                      _ entityId: UnsafePointer<CChar>?,
                                      _ index: Int32,
                                      _ fieldName: UnsafeMutablePointer<CChar>?,
                                      _ fieldNameSize: Int32,
                                      _ fieldType: UnsafeMutablePointer<Int32>?,
                                      _ intValue: UnsafeMutablePointer<Int32>?,
                                      _ numberValue: UnsafeMutablePointer<Float>?,
                                      _ boolValue: UnsafeMutablePointer<UInt32>?,
                                      _ stringValue: UnsafeMutablePointer<CChar>?,
                                      _ stringValueSize: Int32,
                                      _ vecX: UnsafeMutablePointer<Float>?,
                                      _ vecY: UnsafeMutablePointer<Float>?,
                                      _ vecZ: UnsafeMutablePointer<Float>?,
                                      _ entityValue: UnsafeMutablePointer<CChar>?,
                                      _ entityValueSize: Int32,
                                      _ prefabValue: UnsafeMutablePointer<CChar>?,
                                      _ prefabValueSize: Int32,
                                      _ hasMin: UnsafeMutablePointer<UInt32>?,
                                      _ minValue: UnsafeMutablePointer<Float>?,
                                      _ hasMax: UnsafeMutablePointer<UInt32>?,
                                      _ maxValue: UnsafeMutablePointer<Float>?,
                                      _ hasStep: UnsafeMutablePointer<UInt32>?,
                                      _ stepValue: UnsafeMutablePointer<Float>?,
                                      _ tooltip: UnsafeMutablePointer<CChar>?,
                                      _ tooltipSize: Int32,
                                      _ isMissingReference: UnsafeMutablePointer<UInt32>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let script = ecs.get(ScriptComponent.self, for: entity) else { return 0 }
    let descriptors = scriptFieldDescriptors(context: context, script: script)
    let values = scriptFieldValues(script: script, descriptors: descriptors)
    let idx = Int(index)
    guard idx >= 0, idx < descriptors.count else { return 0 }
    let descriptor = descriptors[idx]
    let value = ScriptFieldBlobCodec.coerce(values[descriptor.name] ?? descriptor.defaultValue, to: descriptor.type) ?? descriptor.defaultValue
    _ = writeCString(descriptor.name, to: fieldName, max: fieldNameSize)
    hasMin?.pointee = descriptor.minValue != nil ? 1 : 0
    minValue?.pointee = descriptor.minValue ?? 0
    hasMax?.pointee = descriptor.maxValue != nil ? 1 : 0
    maxValue?.pointee = descriptor.maxValue ?? 0
    hasStep?.pointee = descriptor.step != nil ? 1 : 0
    stepValue?.pointee = descriptor.step ?? 0.1
    _ = writeCString(descriptor.tooltip, to: tooltip, max: tooltipSize)
    isMissingReference?.pointee = 0

    switch descriptor.type {
    case .bool, .boolean:
        fieldType?.pointee = 0
        if case let .bool(flag) = value {
            boolValue?.pointee = flag ? 1 : 0
        } else {
            boolValue?.pointee = 0
        }
    case .int:
        fieldType?.pointee = 1
        if case let .int(number) = value {
            intValue?.pointee = number
        } else {
            intValue?.pointee = 0
        }
    case .float, .number:
        fieldType?.pointee = 2
        if case let .float(number) = value {
            numberValue?.pointee = number
        } else {
            numberValue?.pointee = 0
        }
    case .vec2:
        fieldType?.pointee = 3
        if case let .vec2(vec) = value {
            vecX?.pointee = vec.x
            vecY?.pointee = vec.y
        } else {
            vecX?.pointee = 0
            vecY?.pointee = 0
        }
        vecZ?.pointee = 0
    case .vec3:
        fieldType?.pointee = 4
        if case let .vec3(vec) = value {
            vecX?.pointee = vec.x
            vecY?.pointee = vec.y
            vecZ?.pointee = vec.z
        } else {
            vecX?.pointee = 0
            vecY?.pointee = 0
            vecZ?.pointee = 0
        }
    case .color3:
        fieldType?.pointee = 5
        if case let .color3(color) = value {
            vecX?.pointee = color.x
            vecY?.pointee = color.y
            vecZ?.pointee = color.z
        } else {
            vecX?.pointee = 1
            vecY?.pointee = 1
            vecZ?.pointee = 1
        }
    case .string:
        fieldType?.pointee = 6
        if case let .string(text) = value {
            _ = writeCString(text, to: stringValue, max: stringValueSize)
        } else {
            _ = writeCString("", to: stringValue, max: stringValueSize)
        }
    case .entity:
        fieldType?.pointee = 7
        let entityUUID = (value.entityUUIDValue)
        let raw = entityUUID?.uuidString ?? ""
        _ = writeCString(raw, to: entityValue, max: entityValueSize)
        if let entityUUID, ecs.entity(with: entityUUID) == nil {
            isMissingReference?.pointee = 1
        }
    case .prefab:
        fieldType?.pointee = 8
        let handle = value.prefabHandleValue
        let raw = handle?.rawValue.uuidString ?? ""
        _ = writeCString(raw, to: prefabValue, max: prefabValueSize)
        if let handle, context.engineContext.assetDatabase?.metadata(for: handle) == nil {
            isMissingReference?.pointee = 1
        }
    }
    return 1
}

@_cdecl("MCEEditorSetScriptField")
public func MCEEditorSetScriptField(_ contextPtr: UnsafeRawPointer?,
                                    _ entityId: UnsafePointer<CChar>?,
                                    _ fieldName: UnsafePointer<CChar>?,
                                    _ fieldType: Int32,
                                    _ intValue: Int32,
                                    _ numberValue: Float,
                                    _ boolValue: UInt32,
                                    _ stringValue: UnsafePointer<CChar>?,
                                    _ vecX: Float,
                                    _ vecY: Float,
                                    _ vecZ: Float,
                                    _ entityValue: UnsafePointer<CChar>?,
                                    _ prefabValue: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isSimulating,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let fieldName else { return 0 }
    var script = ecs.get(ScriptComponent.self, for: entity) ?? ScriptComponent()
    let descriptors = scriptFieldDescriptors(context: context, script: script)
    guard !descriptors.isEmpty else { return 0 }
    var values = scriptFieldValues(script: script, descriptors: descriptors)
    let key = String(cString: fieldName)
    guard descriptors.contains(where: { $0.name == key }) else { return 0 }
    switch fieldType {
    case 0:
        values[key] = .bool(boolValue != 0)
    case 1:
        values[key] = .int(intValue)
    case 2:
        values[key] = .float(numberValue)
    case 3:
        values[key] = .vec2(SIMD2<Float>(vecX, vecY))
    case 4:
        values[key] = .vec3(SIMD3<Float>(vecX, vecY, vecZ))
    case 5:
        values[key] = .color3(SIMD3<Float>(vecX, vecY, vecZ))
    case 6:
        values[key] = .string(stringValue.map { String(cString: $0) } ?? "")
    case 7:
        if let entityValue, let uuid = UUID(uuidString: String(cString: entityValue)) {
            values[key] = .entity(uuid)
        } else {
            values[key] = .entity(nil)
        }
    case 8:
        if let prefabValue, let uuid = UUID(uuidString: String(cString: prefabValue)) {
            values[key] = .prefab(AssetHandle(rawValue: uuid))
        } else {
            values[key] = .prefab(nil)
        }
    default:
        return 0
    }
    script.serializedFields = values
    script.fieldMetadata = scriptFieldMetadataDictionary(from: descriptors)
    script.fieldData = ScriptFieldBlobCodec.encodeFieldBlobV1(values, schemaDescriptors: descriptors)
    script.fieldDataVersion = 1
    ecs.add(script, to: entity)
    context.editorProjectManager.notifySceneMutation()
    return 1
}

@_cdecl("MCEEditorGetScriptRuntimeStatus")
public func MCEEditorGetScriptRuntimeStatus(_ contextPtr: UnsafeRawPointer?,
                                            _ entityId: UnsafePointer<CChar>?,
                                            _ runtimeStateOut: UnsafeMutablePointer<Int32>?,
                                            _ hasInstanceOut: UnsafeMutablePointer<UInt32>?,
                                            _ errorBuffer: UnsafeMutablePointer<CChar>?,
                                            _ errorBufferSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let script = ecs.get(ScriptComponent.self, for: entity) else { return 0 }
    runtimeStateOut?.pointee = Int32(script.runtimeState.rawValue)
    hasInstanceOut?.pointee = script.hasInstance ? 1 : 0
    _ = writeCString(script.lastError, to: errorBuffer, max: errorBufferSize)
    return 1
}

@_cdecl("MCEEditorReloadScriptInstance")
public func MCEEditorReloadScriptInstance(_ contextPtr: UnsafeRawPointer?,
                                          _ entityId: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          context.editorSceneController.isPlaying,
          let uuidString = entityId.map({ String(cString: $0) }),
          let uuid = UUID(uuidString: uuidString),
          let runtime = context.engineContext.scriptRuntime as? LuaScriptRuntime else {
        return 0
    }
    return runtime.reloadScriptInstance(entityId: uuid) ? 1 : 0
}

@_cdecl("MCEEditorGetCharacterController")
public func MCEEditorGetCharacterController(_ contextPtr: UnsafeRawPointer?,
                                            _ entityId: UnsafePointer<CChar>?,
                                            _ enabled: UnsafeMutablePointer<UInt32>?,
                                            _ height: UnsafeMutablePointer<Float>?,
                                            _ radius: UnsafeMutablePointer<Float>?,
                                            _ stepOffset: UnsafeMutablePointer<Float>?,
                                            _ moveSpeed: UnsafeMutablePointer<Float>?,
                                            _ sprintMultiplier: UnsafeMutablePointer<Float>?,
                                            _ jumpSpeed: UnsafeMutablePointer<Float>?,
                                            _ useGravityOverride: UnsafeMutablePointer<UInt32>?,
                                            _ gravity: UnsafeMutablePointer<Float>?,
                                            _ maxSlope: UnsafeMutablePointer<Float>?,
                                            _ pushStrength: UnsafeMutablePointer<Float>?,
                                            _ airControl: UnsafeMutablePointer<Float>?,
                                            _ lookSensitivity: UnsafeMutablePointer<Float>?,
                                            _ minPitchDegrees: UnsafeMutablePointer<Float>?,
                                            _ maxPitchDegrees: UnsafeMutablePointer<Float>?,
                                            _ debugDraw: UnsafeMutablePointer<UInt32>?,
                                            _ grounded: UnsafeMutablePointer<UInt32>?,
                                            _ speed: UnsafeMutablePointer<Float>?,
                                            _ velocityY: UnsafeMutablePointer<Float>?,
                                            _ groundBodyId: UnsafeMutablePointer<UInt64>?,
                                            _ fixedDeltaTime: UnsafeMutablePointer<Float>?,
                                            _ interpolationAlpha: UnsafeMutablePointer<Float>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let scene = context.editorSceneController.activeScene(),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let controller = ecs.get(CharacterControllerComponent.self, for: entity) else { return 0 }
    enabled?.pointee = controller.isEnabled ? 1 : 0
    height?.pointee = controller.height
    radius?.pointee = controller.radius
    stepOffset?.pointee = controller.stepOffset
    moveSpeed?.pointee = controller.moveSpeed
    sprintMultiplier?.pointee = controller.sprintMultiplier
    jumpSpeed?.pointee = controller.jumpSpeed
    useGravityOverride?.pointee = controller.useGravityOverride ? 1 : 0
    gravity?.pointee = controller.gravity
    maxSlope?.pointee = controller.maxSlope
    pushStrength?.pointee = controller.pushStrength
    airControl?.pointee = controller.airControl
    lookSensitivity?.pointee = controller.lookSensitivity
    minPitchDegrees?.pointee = controller.minPitchDegrees
    maxPitchDegrees?.pointee = controller.maxPitchDegrees
    debugDraw?.pointee = controller.debugDraw ? 1 : 0
    grounded?.pointee = controller.isGrounded ? 1 : 0
    speed?.pointee = simd_length(controller.velocity)
    velocityY?.pointee = controller.velocity.y
    groundBodyId?.pointee = controller.lastGroundBodyId
    let diagnostics = scene.latestFixedStepDiagnostics()
    fixedDeltaTime?.pointee = diagnostics.fixedDeltaTime
    interpolationAlpha?.pointee = diagnostics.interpolationAlpha
    return 1
}

@_cdecl("MCEEditorSetCharacterController")
public func MCEEditorSetCharacterController(_ contextPtr: UnsafeRawPointer?,
                                            _ entityId: UnsafePointer<CChar>?,
                                            _ enabled: UInt32,
                                            _ height: Float,
                                            _ radius: Float,
                                            _ stepOffset: Float,
                                            _ moveSpeed: Float,
                                            _ sprintMultiplier: Float,
                                            _ jumpSpeed: Float,
                                            _ useGravityOverride: UInt32,
                                            _ gravity: Float,
                                            _ maxSlope: Float,
                                            _ pushStrength: Float,
                                            _ airControl: Float,
                                            _ lookSensitivity: Float,
                                            _ minPitchDegrees: Float,
                                            _ maxPitchDegrees: Float,
                                            _ debugDraw: UInt32) {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return }
    let previous = ecs.get(CharacterControllerComponent.self, for: entity)
    let controller = CharacterControllerComponent(isEnabled: enabled != 0,
                                                  height: height,
                                                  radius: radius,
                                                  stepOffset: stepOffset,
                                                  moveSpeed: moveSpeed,
                                                  sprintMultiplier: sprintMultiplier,
                                                  airControl: simd_clamp(airControl, 0.0, 1.0),
                                                  jumpSpeed: jumpSpeed,
                                                  useGravityOverride: useGravityOverride != 0,
                                                  gravity: gravity,
                                                  maxSlope: maxSlope,
                                                  pushStrength: max(0.0, pushStrength),
                                                  lookSensitivity: lookSensitivity,
                                                  minPitchDegrees: minPitchDegrees,
                                                  maxPitchDegrees: maxPitchDegrees,
                                                  visualEntityId: previous?.visualEntityId,
                                                  cameraPivotEntityId: previous?.cameraPivotEntityId,
                                                  interpolateSubtree: previous?.interpolateSubtree ?? true,
                                                  debugDraw: debugDraw != 0,
                                                  yawRadians: previous?.yawRadians ?? 0.0,
                                                  pitchRadians: previous?.pitchRadians ?? 0.0,
                                                  lookInitialized: previous?.lookInitialized ?? false)
    ecs.add(controller, to: entity)
    context.editorProjectManager.notifySceneMutation()
}

@_cdecl("MCEEditorGetCharacterControllerEntityRefs")
public func MCEEditorGetCharacterControllerEntityRefs(_ contextPtr: UnsafeRawPointer?,
                                                      _ entityId: UnsafePointer<CChar>?,
                                                      _ visualEntityIdOut: UnsafeMutablePointer<CChar>?,
                                                      _ visualEntityIdSize: Int32,
                                                      _ cameraPivotEntityIdOut: UnsafeMutablePointer<CChar>?,
                                                      _ cameraPivotEntityIdSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let controller = ecs.get(CharacterControllerComponent.self, for: entity) else { return 0 }
    if let visual = controller.visualEntityId {
        _ = writeCString(visual.uuidString, to: visualEntityIdOut, max: visualEntityIdSize)
    } else {
        _ = writeCString("", to: visualEntityIdOut, max: visualEntityIdSize)
    }
    if let pivot = controller.cameraPivotEntityId {
        _ = writeCString(pivot.uuidString, to: cameraPivotEntityIdOut, max: cameraPivotEntityIdSize)
    } else {
        _ = writeCString("", to: cameraPivotEntityIdOut, max: cameraPivotEntityIdSize)
    }
    return 1
}

@_cdecl("MCEEditorSetCharacterControllerEntityRefs")
public func MCEEditorSetCharacterControllerEntityRefs(_ contextPtr: UnsafeRawPointer?,
                                                      _ entityId: UnsafePointer<CChar>?,
                                                      _ visualEntityId: UnsafePointer<CChar>?,
                                                      _ cameraPivotEntityId: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          var controller = ecs.get(CharacterControllerComponent.self, for: entity) else { return 0 }
    if let visualEntityId, visualEntityId.pointee != 0 {
        controller.visualEntityId = UUID(uuidString: String(cString: visualEntityId))
    } else {
        controller.visualEntityId = nil
    }
    if let cameraPivotEntityId, cameraPivotEntityId.pointee != 0 {
        controller.cameraPivotEntityId = UUID(uuidString: String(cString: cameraPivotEntityId))
    } else {
        controller.cameraPivotEntityId = nil
    }
    ecs.add(controller, to: entity)
    context.editorProjectManager.notifySceneMutation()
    return 1
}

@_cdecl("MCEEditorCharacterControllerEnsureDependencies")
public func MCEEditorCharacterControllerEnsureDependencies(_ contextPtr: UnsafeRawPointer?,
                                                           _ entityId: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let controller = ecs.get(CharacterControllerComponent.self, for: entity) else { return 0 }
    let changed = ensureCharacterControllerDependencies(context: context, ecs: ecs, entity: entity, controller: controller)
    if changed {
        context.editorProjectManager.notifySceneMutation()
    }
    return changed ? 1 : 0
}

@_cdecl("MCEEditorCharacterControllerSetRigidbodyKinematic")
public func MCEEditorCharacterControllerSetRigidbodyKinematic(_ contextPtr: UnsafeRawPointer?,
                                                              _ entityId: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return 0 }
    guard ensureCharacterControllerRigidbody(context: context, ecs: ecs, entity: entity) else { return 0 }
    context.editorProjectManager.notifySceneMutation()
    return 1
}

@_cdecl("MCEEditorCharacterControllerRemoveRigidbody")
public func MCEEditorCharacterControllerRemoveRigidbody(_ contextPtr: UnsafeRawPointer?,
                                                        _ entityId: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          !context.editorSceneController.isSimulating,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          ecs.get(RigidbodyComponent.self, for: entity) != nil else { return 0 }
    ecs.remove(RigidbodyComponent.self, from: entity)
    context.editorProjectManager.notifySceneMutation()
    return 1
}

@_cdecl("MCEEditorCharacterControllerConvertColliderToCapsule")
public func MCEEditorCharacterControllerConvertColliderToCapsule(_ contextPtr: UnsafeRawPointer?,
                                                                 _ entityId: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let controller = ecs.get(CharacterControllerComponent.self, for: entity) else { return 0 }
    guard convertCharacterControllerColliderToCapsule(ecs: ecs, entity: entity, controller: controller) else { return 0 }
    context.editorProjectManager.notifySceneMutation()
    return 1
}

@_cdecl("MCEEditorCharacterControllerAddCapsuleCollider")
public func MCEEditorCharacterControllerAddCapsuleCollider(_ contextPtr: UnsafeRawPointer?,
                                                           _ entityId: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let controller = ecs.get(CharacterControllerComponent.self, for: entity) else { return 0 }
    let changed = ensureCharacterControllerCapsuleCollider(context: context,
                                                           ecs: ecs,
                                                           entity: entity,
                                                           controller: controller,
                                                           autoSizeFromMesh: true)
    guard changed else { return 0 }
    context.editorProjectManager.notifySceneMutation()
    return 1
}

@_cdecl("MCEEditorCharacterControllerCreateRecommendedHierarchy")
public func MCEEditorCharacterControllerCreateRecommendedHierarchy(_ contextPtr: UnsafeRawPointer?,
                                                                   _ entityId: UnsafePointer<CChar>?,
                                                                   _ createCamera: UInt32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          !context.editorSceneController.isSimulating,
          let ecs = editorECS(context),
          let root = entity(from: entityId, context: context),
          var controller = ecs.get(CharacterControllerComponent.self, for: root) else { return 0 }

    var didMutate = false

    let visualRefEntity = controller.visualEntityId.flatMap { ecs.entity(with: $0) }
    let visualEntity: Entity
    if let visualRefEntity {
        visualEntity = visualRefEntity
    } else {
        let resolved = ensureNamedChild(named: "Visual", parent: root, ecs: ecs)
        visualEntity = resolved.child
        didMutate = didMutate || resolved.created
        controller.visualEntityId = visualEntity.id
        didMutate = true
    }
    if controller.visualEntityId != visualEntity.id {
        controller.visualEntityId = visualEntity.id
        didMutate = true
    }

    let pivotRefEntity = controller.cameraPivotEntityId.flatMap { ecs.entity(with: $0) }
    let pivotEntity: Entity
    if let pivotRefEntity {
        pivotEntity = pivotRefEntity
    } else {
        let resolved = ensureNamedChild(named: "CameraPivot", parent: root, ecs: ecs)
        pivotEntity = resolved.child
        didMutate = didMutate || resolved.created
        controller.cameraPivotEntityId = pivotEntity.id
        didMutate = true
    }
    if controller.cameraPivotEntityId != pivotEntity.id {
        controller.cameraPivotEntityId = pivotEntity.id
        didMutate = true
    }

    if createCamera != 0 {
        let existingCameraChild = ecs.getChildren(pivotEntity).first { child in
            ecs.get(CameraComponent.self, for: child) != nil
        }
        if existingCameraChild == nil {
            let camera = ensureNamedChild(named: "Camera", parent: pivotEntity, ecs: ecs)
            didMutate = didMutate || camera.created
            if ecs.get(TransformComponent.self, for: camera.child) == nil {
                ecs.add(TransformComponent(), to: camera.child)
                didMutate = true
            }
            if ecs.get(CameraComponent.self, for: camera.child) == nil {
                ecs.add(CameraComponent(isPrimary: false, isEditor: false), to: camera.child)
                didMutate = true
            }
        }
    }

    if didMutate {
        ecs.add(controller, to: root)
        context.editorProjectManager.notifySceneMutation()
    }
    return didMutate ? 1 : 0
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
    let shape = collider.primaryShape()
    enabled?.pointee = shape.isEnabled ? 1 : 0
    shapeType?.pointee = Int32(shape.shapeType.rawValue)
    boxX?.pointee = shape.boxHalfExtents.x
    boxY?.pointee = shape.boxHalfExtents.y
    boxZ?.pointee = shape.boxHalfExtents.z
    sphereRadius?.pointee = shape.sphereRadius
    capsuleHalfHeight?.pointee = shape.capsuleHalfHeight
    capsuleRadius?.pointee = shape.capsuleRadius
    offsetX?.pointee = shape.offset.x
    offsetY?.pointee = shape.offset.y
    offsetZ?.pointee = shape.offset.z
    rotX?.pointee = shape.rotationOffset.x
    rotY?.pointee = shape.rotationOffset.y
    rotZ?.pointee = shape.rotationOffset.z
    isTrigger?.pointee = shape.isTrigger ? 1 : 0
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
    var component = ecs.get(ColliderComponent.self, for: entity) ?? ColliderComponent()
    var shapes = component.allShapes()
    if shapes.isEmpty {
        shapes = [ColliderShape()]
    }
    shapes[0] = ColliderShape(isEnabled: enabled != 0,
                              shapeType: ColliderShapeType(rawValue: UInt32(shapeType)) ?? .box,
                              boxHalfExtents: SIMD3<Float>(boxX, boxY, boxZ),
                              sphereRadius: sphereRadius,
                              capsuleHalfHeight: capsuleHalfHeight,
                              capsuleRadius: capsuleRadius,
                              offset: SIMD3<Float>(offsetX, offsetY, offsetZ),
                              rotationOffset: SIMD3<Float>(rotX, rotY, rotZ),
                              isTrigger: isTrigger != 0,
                              collisionLayerOverride: shapes[0].collisionLayerOverride,
                              physicsMaterial: shapes[0].physicsMaterial)
    component.setShapes(shapes)
    ecs.add(component, to: entity)
    context.editorProjectManager.notifySceneMutation()
}

@_cdecl("MCEEditorGetColliderShapeCount")
public func MCEEditorGetColliderShapeCount(_ contextPtr: UnsafeRawPointer?,
                                           _ entityId: UnsafePointer<CChar>?) -> Int32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let collider = ecs.get(ColliderComponent.self, for: entity) else { return 0 }
    return Int32(collider.allShapes().count)
}

@_cdecl("MCEEditorAddColliderShape")
public func MCEEditorAddColliderShape(_ contextPtr: UnsafeRawPointer?,
                                      _ entityId: UnsafePointer<CChar>?) {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          var collider = ecs.get(ColliderComponent.self, for: entity) else { return }
    var shapes = collider.allShapes()
    shapes.append(ColliderShape())
    collider.setShapes(shapes)
    ecs.add(collider, to: entity)
    context.editorProjectManager.notifySceneMutation()
}

@_cdecl("MCEEditorRemoveColliderShape")
public func MCEEditorRemoveColliderShape(_ contextPtr: UnsafeRawPointer?,
                                         _ entityId: UnsafePointer<CChar>?,
                                         _ shapeIndex: Int32) {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          var collider = ecs.get(ColliderComponent.self, for: entity) else { return }
    var shapes = collider.allShapes()
    guard shapeIndex >= 0, shapeIndex < Int32(shapes.count) else { return }
    if shapes.count == 1 {
        ecs.remove(ColliderComponent.self, from: entity)
        context.editorProjectManager.notifySceneMutation()
        return
    } else {
        shapes.remove(at: Int(shapeIndex))
    }
    collider.setShapes(shapes)
    ecs.add(collider, to: entity)
    context.editorProjectManager.notifySceneMutation()
}

@_cdecl("MCEEditorGetColliderShape")
public func MCEEditorGetColliderShape(_ contextPtr: UnsafeRawPointer?,
                                      _ entityId: UnsafePointer<CChar>?,
                                      _ shapeIndex: Int32,
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
                                      _ isTrigger: UnsafeMutablePointer<UInt32>?,
                                      _ hasLayerOverride: UnsafeMutablePointer<UInt32>?,
                                      _ layerOverride: UnsafeMutablePointer<Int32>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let collider = ecs.get(ColliderComponent.self, for: entity) else { return 0 }
    let shapes = collider.allShapes()
    guard shapeIndex >= 0, shapeIndex < Int32(shapes.count) else { return 0 }
    let shape = shapes[Int(shapeIndex)]
    enabled?.pointee = shape.isEnabled ? 1 : 0
    shapeType?.pointee = Int32(shape.shapeType.rawValue)
    boxX?.pointee = shape.boxHalfExtents.x
    boxY?.pointee = shape.boxHalfExtents.y
    boxZ?.pointee = shape.boxHalfExtents.z
    sphereRadius?.pointee = shape.sphereRadius
    capsuleHalfHeight?.pointee = shape.capsuleHalfHeight
    capsuleRadius?.pointee = shape.capsuleRadius
    offsetX?.pointee = shape.offset.x
    offsetY?.pointee = shape.offset.y
    offsetZ?.pointee = shape.offset.z
    rotX?.pointee = shape.rotationOffset.x
    rotY?.pointee = shape.rotationOffset.y
    rotZ?.pointee = shape.rotationOffset.z
    isTrigger?.pointee = shape.isTrigger ? 1 : 0
    if let override = shape.collisionLayerOverride {
        hasLayerOverride?.pointee = 1
        layerOverride?.pointee = override
    } else {
        hasLayerOverride?.pointee = 0
        layerOverride?.pointee = 0
    }
    return 1
}

@_cdecl("MCEEditorSetColliderShape")
public func MCEEditorSetColliderShape(_ contextPtr: UnsafeRawPointer?,
                                      _ entityId: UnsafePointer<CChar>?,
                                      _ shapeIndex: Int32,
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
                                      _ isTrigger: UInt32,
                                      _ hasLayerOverride: UInt32,
                                      _ layerOverride: Int32) {
    guard let context = resolveContext(contextPtr),
          !context.editorSceneController.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          var collider = ecs.get(ColliderComponent.self, for: entity) else { return }
    var shapes = collider.allShapes()
    guard shapeIndex >= 0, shapeIndex < Int32(shapes.count) else { return }
    let index = Int(shapeIndex)
    shapes[index] = ColliderShape(isEnabled: enabled != 0,
                                  shapeType: ColliderShapeType(rawValue: UInt32(shapeType)) ?? .box,
                                  boxHalfExtents: SIMD3<Float>(boxX, boxY, boxZ),
                                  sphereRadius: sphereRadius,
                                  capsuleHalfHeight: capsuleHalfHeight,
                                  capsuleRadius: capsuleRadius,
                                  offset: SIMD3<Float>(offsetX, offsetY, offsetZ),
                                  rotationOffset: SIMD3<Float>(rotX, rotY, rotZ),
                                  isTrigger: isTrigger != 0,
                                  collisionLayerOverride: hasLayerOverride != 0 ? layerOverride : nil,
                                  physicsMaterial: shapes[index].physicsMaterial)
    collider.setShapes(shapes)
    ecs.add(collider, to: entity)
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
          let scene = context.editorSceneController.activeScene(),
          let entity = entity(from: entityId, context: context) else { return }
    let transform = TransformComponent(
        position: SIMD3<Float>(px, py, pz),
        rotation: TransformMath.quaternionFromEulerXYZ(SIMD3<Float>(rx, ry, rz)),
        scale: SIMD3<Float>(sx, sy, sz)
    )
    _ = scene.setLocalTransform(transform, for: entity, source: .editor)
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
          let scene = context.editorSceneController.activeScene(),
          let entity = entity(from: entityId, context: context) else { return }
    let transform = TransformComponent(
        position: SIMD3<Float>(px, py, pz),
        rotation: TransformMath.quaternionFromEulerXYZ(SIMD3<Float>(rx, ry, rz)),
        scale: SIMD3<Float>(sx, sy, sz)
    )
    _ = scene.setLocalTransform(transform, for: entity, source: .editor)
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

    let worldMatrix = readColumnMajorMatrix(from: matrix)
    let localMatrix: matrix_float4x4
    if let parent = ecs.getParent(entity) {
        localMatrix = simd_inverse(ecs.worldMatrix(for: parent)) * worldMatrix
    } else {
        localMatrix = worldMatrix
    }
    let decomposed = TransformMath.decomposeMatrix(localMatrix)
    guard isFinite(decomposed.position),
          isFinite(decomposed.rotation),
          isFinite(decomposed.scale) else {
        return 0
    }
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
          ecs.get(TransformComponent.self, for: entity) != nil,
          let matrixOut else { return 0 }

    let matrix = ecs.worldMatrix(for: entity)
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
    let result = physicsSystem.raycastForEditorPicking(origin: origin, direction: direction, maxDistance: clampedDistance)
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
    let direction: SIMD3<Float>
    if (light.type == .directional || light.type == .spot),
       let transform = ecs.get(TransformComponent.self, for: entity) {
        direction = TransformMath.directionalLightDirection(from: transform.rotation)
    } else {
        direction = light.direction
    }
    dirX?.pointee = direction.x
    dirY?.pointee = direction.y
    dirZ?.pointee = direction.z
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
    if light.type != .directional && light.type != .spot {
        light.direction = SIMD3<Float>(dirX, dirY, dirZ)
    } else if var transform = ecs.get(TransformComponent.self, for: entity) {
        let requestedDirection = SIMD3<Float>(dirX, dirY, dirZ)
        if simd_length_squared(requestedDirection) > 0.000001 {
            transform.rotation = TransformMath.rotationForDirectionalLight(direction: simd_normalize(requestedDirection))
            ecs.add(transform, to: entity)
        }
    }
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
