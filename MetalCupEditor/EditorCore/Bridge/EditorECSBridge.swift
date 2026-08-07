/// EditorECSBridge.swift
/// Defines ECS bridge helpers for editor UI integration.
/// Created by Kaden Cringle.

import Foundation
import MetalCupEngine
import simd

public struct MCEEnvironmentLookBridge {
    public var preset: Int32
    public var mood: Float
    public var warmth: Float
    public var cinematicAmount: Float
}

public struct MCEEnvironmentSourceBridge {
    public var enabled: UInt32
    public var mode: Int32
    public var hasHdriHandle: UInt32
    public var hdriHandleHigh: UInt64
    public var hdriHandleLow: UInt64
}

public struct MCEEnvironmentTimeBridge {
    public var defaultTimeOfDay: Float
    public var previewTimeOfDay: Float
    public var timeControlMode: Int32
    public var dayLengthSeconds: Float
    public var timeScale: Float
}

public struct MCEEnvironmentAtmosphereBridge {
    public var amount: Float
    public var haze: Float
    public var density: Float
    public var temperature: Float
    public var mood: Float
    public var sourceEV: Float
}

public struct MCEEnvironmentCelestialBridge {
    public var moonIntensity: Float
    public var moonSizeDegrees: Float
    public var starIntensity: Float
    public var starRichness: Float
    public var milkyWayIntensity: Float
    public var milkyWayChroma: Float
    public var milkyWayRotation: Float
    public var nightBrightness: Float
}

public struct MCEEnvironmentWeatherCloudBridge {
    public var weatherPrimary: Int32
    public var weatherSecondary: Int32
    public var weatherBlend: Float
    public var weatherAmount: Float
    public var cloudCoverage: Float
    public var cloudStyle: Int32
    public var cloudRenderMode: Int32
}

public struct MCEEnvironmentFogBridge {
    public var amount: Float
    public var height: Float
    public var distance: Float
}

public struct MCEEnvironmentIBLBridge {
    public var realtimeUpdate: UInt32
    public var autoRebuildOnChange: UInt32
    public var needsRebuild: UInt32
    public var dirty: UInt32
    public var isRebuilding: UInt32
    public var currentRebuildQuality: Int32
    public var lastBuiltQuality: Int32
    public var hasFailure: UInt32
    public var phase: Int32
    public var currentTimeOfDay: Float
    public var representedTimeOfDay: Float
    public var angularLagDegrees: Float
    public var lastBuildDuration: Float
    public var solarElevationDegrees: Float
    public var sunDirectionX: Float
    public var sunDirectionY: Float
    public var sunDirectionZ: Float
    public var sunIlluminance: Float
}

#if DEBUG
private var bridgeFacadeSanityChecked = false
private func runBridgeFacadeSanityCheckOnce() {
    guard !bridgeFacadeSanityChecked else { return }
    bridgeFacadeSanityChecked = true
    MC_ASSERT(EditorSceneQueries.getEntityCount(nil) == 0, "Bridge facade sanity failed: scene query")
    MC_ASSERT(EditorSelectionQueries.getSelectedEntityCount(nil) == 0, "Bridge facade sanity failed: selection query")
    MC_ASSERT(EditorComponentCommands.entityHasComponent(nil, nil, 0) == 0, "Bridge facade sanity failed: component query")
    MC_ASSERT(EditorTransformCommands.getTransform(nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil) == 0,
              "Bridge facade sanity failed: transform query")
}

private enum EditorBridgeThinRouteGuard {
    private static var activeRouteName: String?
    private static var activeFacadeInvocationCount: Int = 0

    static func route<T>(_ routeName: String, _ body: () -> T) -> T {
        activeRouteName = routeName
        activeFacadeInvocationCount = 0
        defer {
            MC_ASSERT(activeFacadeInvocationCount == 1,
                      "Bridge route \(routeName) should invoke exactly one facade (saw \(activeFacadeInvocationCount)).")
            activeRouteName = nil
            activeFacadeInvocationCount = 0
        }
        return body()
    }

    static func markFacadeInvocation(_ facadeMethod: String) {
        _ = facadeMethod
        guard activeRouteName != nil else { return }
        activeFacadeInvocationCount += 1
    }
}
#endif

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
    case skinnedMesh = 11
    case animator = 12
    case reflectionProbe = 13
    case environment = 14
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
    let object = Unmanaged<AnyObject>.fromOpaque(contextPtr).takeUnretainedValue()
    guard let context = object as? MCEContext else { return nil }
    #if DEBUG
    runBridgeFacadeSanityCheckOnce()
    if context.debugMagic != MCEContext.debugMagicExpected ||
        context.debugVersion != MCEContext.debugVersionExpected {
        assertionFailure("Invalid MCEContext pointer passed to bridge.")
        return nil
    }
    #endif
    return context
}


private func editorECS(_ context: MCEContext) -> SceneECS? {
    return context.bridgeServices.activeScene()?.ecs
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

private func uuidParts(_ uuid: UUID) -> (high: UInt64, low: UInt64) {
    let raw = uuid.uuid
    let high = UInt64(raw.0) << 56
        | UInt64(raw.1) << 48
        | UInt64(raw.2) << 40
        | UInt64(raw.3) << 32
        | UInt64(raw.4) << 24
        | UInt64(raw.5) << 16
        | UInt64(raw.6) << 8
        | UInt64(raw.7)
    let low = UInt64(raw.8) << 56
        | UInt64(raw.9) << 48
        | UInt64(raw.10) << 40
        | UInt64(raw.11) << 32
        | UInt64(raw.12) << 24
        | UInt64(raw.13) << 16
        | UInt64(raw.14) << 8
        | UInt64(raw.15)
    return (high, low)
}

private func uuidFromParts(high: UInt64, low: UInt64) -> UUID {
    UUID(uuid: (
        UInt8((high >> 56) & 0xff),
        UInt8((high >> 48) & 0xff),
        UInt8((high >> 40) & 0xff),
        UInt8((high >> 32) & 0xff),
        UInt8((high >> 24) & 0xff),
        UInt8((high >> 16) & 0xff),
        UInt8((high >> 8) & 0xff),
        UInt8(high & 0xff),
        UInt8((low >> 56) & 0xff),
        UInt8((low >> 48) & 0xff),
        UInt8((low >> 40) & 0xff),
        UInt8((low >> 32) & 0xff),
        UInt8((low >> 24) & 0xff),
        UInt8((low >> 16) & 0xff),
        UInt8((low >> 8) & 0xff),
        UInt8(low & 0xff)
    ))
}

private func parseSubmeshMaterialHandles(_ raw: String) -> [AssetHandle?] {
    let parts = raw.components(separatedBy: ",")
    return parts.map { part in
        let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        return AssetHandle(string: trimmed)
    }
}

private func metadata(for handle: AssetHandle, in snapshot: [AssetMetadata]) -> AssetMetadata? {
    return snapshot.first { $0.handle == handle }
}

private func prefabURL(from handleString: String, context: MCEContext) -> URL? {
    guard let handle = handleFromString(handleString) else { return nil }
    return context.bridgeServices.assetURL(for: handle)
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
    guard let scene = context.bridgeServices.activeScene(),
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

private func firstAnimatorInSubtree(root: Entity, ecs: SceneECS) -> Entity? {
    var queue: [Entity] = [root]
    var cursor = 0
    while cursor < queue.count {
        let current = queue[cursor]
        cursor += 1
        if ecs.get(AnimatorComponent.self, for: current) != nil {
            return current
        }
        let children = ecs.getChildren(current)
        if !children.isEmpty {
            queue.append(contentsOf: children)
        }
    }
    return nil
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
        skyLight: ecs.get(SkyLightComponent.self, for: entity).map { component in
            SkyLightComponentDTO(
                mode: component.mode.rawValue,
                enabled: component.enabled,
                timeOfDay: component.timeOfDay,
                weatherType: component.weatherType.rawValue,
                secondaryWeatherType: component.secondaryWeatherType.rawValue,
                weatherBlend: component.weatherBlend,
                weatherAmount: component.weatherAmount,
                atmosphereAmount: component.atmosphereAmount,
                cloudCoverage: component.cloudCoverage,
                cloudStyle: component.cloudStyle.rawValue,
                temperature: component.temperature,
                mood: component.mood,
                moonIntensity: component.moonIntensity,
                moonSizeDegrees: component.moonSizeDegrees,
                starIntensity: component.starIntensity,
                fogAmount: component.fogAmount,
                fogHeight: component.fogHeight,
                fogDistance: component.fogDistance,
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
                hdriHandle: component.hdriHandle
            )
        },
        environmentState: ecs.get(EnvironmentStateComponent.self, for: entity).map {
            EnvironmentStateComponentDTO(component: $0)
        },
        skyIBLState: ecs.get(SkyIBLStateComponent.self, for: entity).map {
            SkyIBLStateComponentDTO(component: $0)
        },
        environment: ecs.get(EnvironmentComponent.self, for: entity).map {
            EnvironmentComponentDTO(component: $0)
        },
        skyLightTag: ecs.get(SkyLightTag.self, for: entity).map { _ in TagComponentDTO() },
        skySunTag: ecs.get(SkySunTag.self, for: entity).map { _ in TagComponentDTO() }
    )
}

private func applyComponentsDocument(_ components: ComponentsDocument,
                                     to entity: Entity,
                                     scene: EngineScene,
                                     ecs: SceneECS) {
    if let name = components.name {
        ecs.add(NameComponent(name: name.name), to: entity)
    }
    if let transform = components.transform {
        _ = scene.transformAuthority.ensureLocalTransform(
            entity: entity,
            default: TransformComponent(
                position: transform.position.toSIMD(),
                rotation: transform.rotationQuat.toSIMD(),
                scale: transform.scale.toSIMD()
            ),
            source: .editor
        )
    } else {
        _ = scene.transformAuthority.ensureLocalTransform(entity: entity,
                                                          default: TransformComponent(),
                                                          source: .editor)
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
    if let skyLight = components.skyLight {
        let component = SkyLightComponent(
            mode: SkyMode(rawValue: skyLight.mode) ?? .hdri,
            enabled: skyLight.enabled,
            hdriHandle: skyLight.hdriHandle,
            timeOfDay: skyLight.timeOfDay,
            weatherType: AtmosphereWeatherType(rawValue: skyLight.weatherType) ?? .clear,
            secondaryWeatherType: AtmosphereWeatherType(rawValue: skyLight.secondaryWeatherType) ?? .clear,
            weatherBlend: skyLight.weatherBlend,
            weatherAmount: skyLight.weatherAmount,
            atmosphereAmount: skyLight.atmosphereAmount,
            cloudCoverage: skyLight.cloudCoverage,
            cloudStyle: AtmosphereCloudStyle(rawValue: skyLight.cloudStyle) ?? .puffy,
            temperature: skyLight.temperature,
            mood: skyLight.mood,
            moonIntensity: skyLight.moonIntensity,
            moonSizeDegrees: skyLight.moonSizeDegrees,
            starIntensity: skyLight.starIntensity,
            fogAmount: skyLight.fogAmount,
            fogHeight: skyLight.fogHeight,
            fogDistance: skyLight.fogDistance,
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
            cloudsSunInfluence: skyLight.cloudsSunInfluence
        )
        ecs.add(component, to: entity)
        ecs.add(components.environmentState?.toComponent() ?? EnvironmentStateComponent(seededFromAuthored: component), to: entity)
        ecs.add(components.skyIBLState?.toComponent() ?? SkyIBLStateComponent(realtimeUpdate: skyLight.realtimeUpdate ?? true), to: entity)
    }
    if let environmentDTO = components.environment {
        let environment = environmentDTO.toComponent()
        ecs.add(environment, to: entity)
        ecs.add(EnvironmentRuntimeStateComponent.default(from: environment), to: entity)
        ecs.add(EnvironmentIBLStateComponent.defaultNeedsRebuild, to: entity)
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
    if var iblState = ecs.get(SkyIBLStateComponent.self, for: entity) {
        iblState.needsRebuild = true
        ecs.add(iblState, to: entity)
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

enum EditorBridgeInternals {
    static func contextValue(_ contextPtr: UnsafeRawPointer?) -> MCEContext? { resolveContext(contextPtr) }
    static func ecsValue(_ context: MCEContext) -> SceneECS? { editorECS(context) }
    static func entityValue(from idPointer: UnsafePointer<CChar>?, context: MCEContext) -> Entity? { entity(from: idPointer, context: context) }
    static func cStringWrite(_ string: String, to buffer: UnsafeMutablePointer<CChar>?, max: Int32) -> Int32 { writeCString(string, to: buffer, max: max) }
    static func assetHandleValue(_ string: String) -> AssetHandle? { handleFromString(string) }
    static func submeshMaterialHandlesValue(_ raw: String) -> [AssetHandle?] { parseSubmeshMaterialHandles(raw) }
    static func assetMetadataValue(for handle: AssetHandle, snapshot: [AssetMetadata]) -> AssetMetadata? { metadata(for: handle, in: snapshot) }
    static func prefabURLValue(from handleString: String, context: MCEContext) -> URL? { prefabURL(from: handleString, context: context) }
    static func entityIdsFromCSV(_ csv: UnsafePointer<CChar>?) -> [UUID] { parseEntityIdCSV(csv) }
    static func prefabInstanceValue(_ context: MCEContext,
                                    _ entityId: UnsafePointer<CChar>?) -> (scene: EngineScene, entity: Entity, link: PrefabInstanceComponent)? {
        resolvePrefabInstance(context, entityId)
    }
    static func matrixWrite(_ matrix: matrix_float4x4, to buffer: UnsafeMutablePointer<Float>) { writeColumnMajorMatrix(matrix, to: buffer) }
    static func matrixRead(from buffer: UnsafePointer<Float>) -> matrix_float4x4 { readColumnMajorMatrix(from: buffer) }
    static func finite(_ value: SIMD3<Float>) -> Bool { isFinite(value) }
    static func finite(_ value: SIMD4<Float>) -> Bool { isFinite(value) }
    static func hasPrimaryRuntimeCameraValue(ecs: SceneECS) -> Bool { hasPrimaryRuntimeCamera(ecs: ecs) }
    static func setPrimaryCameraValue(ecs: SceneECS, entity: Entity) { setPrimaryCamera(ecs: ecs, entity: entity) }
    static func markHierarchyOverrideValue(_ ecs: SceneECS, _ entity: Entity) { markHierarchyOverrideIfPrefabInstance(ecs, entity) }
    static func setActiveSkyValue(ecs: SceneECS, entity: Entity, logger: EngineLogger) { setActiveSky(ecs: ecs, entity: entity, logger: logger) }
    static func findEditorCameraValue(ecs: SceneECS) -> (Entity, TransformComponent, CameraComponent)? { findEditorCamera(ecs: ecs) }
    static func componentsDocumentValue(for entity: Entity, ecs: SceneECS) -> ComponentsDocument { componentsDocument(for: entity, ecs: ecs) }
    static func applyComponentsDocumentValue(_ components: ComponentsDocument, to entity: Entity, scene: EngineScene, ecs: SceneECS) {
        applyComponentsDocument(components, to: entity, scene: scene, ecs: ecs)
    }
    static func makeUniqueCopyNameValue(_ base: String, existingLowerNames: Set<String>) -> String {
        makeUniqueCopyName(base, existingLowerNames: existingLowerNames)
    }

#if DEBUG
    static func thinRoute<T>(_ routeName: String, _ body: () -> T) -> T {
        EditorBridgeThinRouteGuard.route(routeName, body)
    }

    static func markFacadeInvocation(_ facadeMethod: String) {
        EditorBridgeThinRouteGuard.markFacadeInvocation(facadeMethod)
    }
#else
    static func thinRoute<T>(_ routeName: String, _ body: () -> T) -> T {
        _ = routeName
        return body()
    }

    static func markFacadeInvocation(_ facadeMethod: String) {
        _ = facadeMethod
    }
#endif

    static func commitMutation(_ context: MCEContext, label: String) {
        if context.bridgeServices.supportsUndoTransactions {
            context.bridgeServices.recordUndoTransaction(label)
        }
        context.bridgeServices.notifySceneMutation()
    }
}

@_cdecl("MCEEditorGetEntityCount")
public func MCEEditorGetEntityCount(_ contextPtr: UnsafeRawPointer?) -> Int32 {
    EditorBridgeInternals.thinRoute("MCEEditorGetEntityCount") {
        EditorSceneQueries.getEntityCount(contextPtr)
    }
}

@_cdecl("MCEEditorGetSelectedEntityCount")
public func MCEEditorGetSelectedEntityCount(_ contextPtr: UnsafeRawPointer?) -> Int32 {
    EditorSelectionQueries.getSelectedEntityCount(contextPtr)
}

@_cdecl("MCEEditorGetSelectedEntityIdAt")
public func MCEEditorGetSelectedEntityIdAt(_ contextPtr: UnsafeRawPointer?,
                                           _ index: Int32,
                                           _ buffer: UnsafeMutablePointer<CChar>?,
                                           _ bufferSize: Int32) -> Int32 {
    EditorSelectionQueries.getSelectedEntityIdAt(contextPtr, index, buffer, bufferSize)
}

@_cdecl("MCEEditorSetSelectedEntitiesCSV")
public func MCEEditorSetSelectedEntitiesCSV(_ contextPtr: UnsafeRawPointer?,
                                            _ csv: UnsafePointer<CChar>?,
                                            _ primaryId: UnsafePointer<CChar>?) {
    EditorBridgeInternals.thinRoute("MCEEditorSetSelectedEntitiesCSV") {
        EditorSelectionCommands.setSelectedEntitiesCSV(contextPtr, csv, primaryId)
    }
}

@_cdecl("MCEEditorGetRootEntityCount")
public func MCEEditorGetRootEntityCount(_ contextPtr: UnsafeRawPointer?) -> Int32 {
    EditorSceneQueries.getRootEntityCount(contextPtr)
}

@_cdecl("MCEEditorGetRootEntityIdAt")
public func MCEEditorGetRootEntityIdAt(_ contextPtr: UnsafeRawPointer?,
                                       _ index: Int32,
                                       _ buffer: UnsafeMutablePointer<CChar>?,
                                       _ bufferSize: Int32) -> Int32 {
    EditorSceneQueries.getRootEntityIdAt(contextPtr, index, buffer, bufferSize)
}

@_cdecl("MCEEditorGetChildEntityCount")
public func MCEEditorGetChildEntityCount(_ contextPtr: UnsafeRawPointer?,
                                         _ parentId: UnsafePointer<CChar>?) -> Int32 {
    EditorSceneQueries.getChildEntityCount(contextPtr, parentId)
}

@_cdecl("MCEEditorGetChildEntityIdAt")
public func MCEEditorGetChildEntityIdAt(_ contextPtr: UnsafeRawPointer?,
                                        _ parentId: UnsafePointer<CChar>?,
                                        _ index: Int32,
                                        _ buffer: UnsafeMutablePointer<CChar>?,
                                        _ bufferSize: Int32) -> Int32 {
    EditorSceneQueries.getChildEntityIdAt(contextPtr, parentId, index, buffer, bufferSize)
}

@_cdecl("MCEEditorGetParentEntityId")
public func MCEEditorGetParentEntityId(_ contextPtr: UnsafeRawPointer?,
                                       _ childId: UnsafePointer<CChar>?,
                                       _ buffer: UnsafeMutablePointer<CChar>?,
                                       _ bufferSize: Int32) -> Int32 {
    EditorSceneQueries.getParentEntityId(contextPtr, childId, buffer, bufferSize)
}

@_cdecl("MCEEditorSetParent")
public func MCEEditorSetParent(_ contextPtr: UnsafeRawPointer?,
                               _ childId: UnsafePointer<CChar>?,
                               _ parentId: UnsafePointer<CChar>?,
                               _ keepWorldTransform: UInt32) -> UInt32 {
    EditorEntityCommands.setParent(contextPtr, childId, parentId, keepWorldTransform)
}

@_cdecl("MCEEditorUnparent")
public func MCEEditorUnparent(_ contextPtr: UnsafeRawPointer?,
                              _ childId: UnsafePointer<CChar>?,
                              _ keepWorldTransform: UInt32) -> UInt32 {
    EditorEntityCommands.unparent(contextPtr, childId, keepWorldTransform)
}

@_cdecl("MCEEditorReorderEntity")
public func MCEEditorReorderEntity(_ contextPtr: UnsafeRawPointer?,
                                   _ entityId: UnsafePointer<CChar>?,
                                   _ parentId: UnsafePointer<CChar>?,
                                   _ newIndex: Int32) -> UInt32 {
    EditorEntityCommands.reorderEntity(contextPtr, entityId, parentId, newIndex)
}

@_cdecl("MCEEditorGetEntityIdAt")
public func MCEEditorGetEntityIdAt(_ contextPtr: UnsafeRawPointer?,
                                   _ index: Int32,
                                   _ buffer: UnsafeMutablePointer<CChar>?,
                                   _ bufferSize: Int32) -> Int32 {
    EditorSceneQueries.getEntityIdAt(contextPtr, index, buffer, bufferSize)
}

@_cdecl("MCEEditorGetEntityName")
public func MCEEditorGetEntityName(_ contextPtr: UnsafeRawPointer?,
                                   _ entityId: UnsafePointer<CChar>?,
                                   _ buffer: UnsafeMutablePointer<CChar>?,
                                   _ bufferSize: Int32) -> Int32 {
    EditorSceneQueries.getEntityName(contextPtr, entityId, buffer, bufferSize)
}

@_cdecl("MCEEditorEntityExists")
public func MCEEditorEntityExists(_ contextPtr: UnsafeRawPointer?, _ entityId: UnsafePointer<CChar>?) -> UInt32 {
    EditorSceneQueries.entityExists(contextPtr, entityId)
}

@_cdecl("MCEEditorEntityIsAutoDrivenSkySun")
public func MCEEditorEntityIsAutoDrivenSkySun(_ contextPtr: UnsafeRawPointer?, _ entityId: UnsafePointer<CChar>?) -> UInt32 {
    EditorSceneQueries.entityIsAutoDrivenSkySun(contextPtr, entityId)
}

@_cdecl("MCEEditorSetEntityName")
public func MCEEditorSetEntityName(_ contextPtr: UnsafeRawPointer?,
                                   _ entityId: UnsafePointer<CChar>?,
                                   _ name: UnsafePointer<CChar>?) {
    EditorEntityCommands.setEntityName(contextPtr, entityId, name)
}

@_cdecl("MCEEditorCreateEntity")
public func MCEEditorCreateEntity(_ contextPtr: UnsafeRawPointer?,
                                  _ name: UnsafePointer<CChar>?,
                                  _ outId: UnsafeMutablePointer<CChar>?,
                                  _ outIdSize: Int32) -> Int32 {
    EditorBridgeInternals.thinRoute("MCEEditorCreateEntity") {
        EditorEntityCommands.createEntity(contextPtr, name, outId, outIdSize)
    }
}

@_cdecl("MCEEditorDuplicateSelectedEntities")
public func MCEEditorDuplicateSelectedEntities(_ contextPtr: UnsafeRawPointer?,
                                               _ outPrimaryId: UnsafeMutablePointer<CChar>?,
                                               _ outPrimaryIdSize: Int32) -> Int32 {
    EditorEntityCommands.duplicateSelectedEntities(contextPtr, outPrimaryId, outPrimaryIdSize)
}

@_cdecl("MCEEditorCreateMeshEntity")
public func MCEEditorCreateMeshEntity(_ contextPtr: UnsafeRawPointer?,
                                      _ meshType: Int32,
                                      _ outId: UnsafeMutablePointer<CChar>?,
                                      _ outIdSize: Int32) -> Int32 {
    EditorEntityCommands.createMeshEntity(contextPtr, meshType, outId, outIdSize)
}

@_cdecl("MCEEditorCreateMeshEntityFromHandle")
public func MCEEditorCreateMeshEntityFromHandle(_ contextPtr: UnsafeRawPointer?,
                                                _ meshHandle: UnsafePointer<CChar>?,
                                                _ outId: UnsafeMutablePointer<CChar>?,
                                                _ outIdSize: Int32) -> Int32 {
    EditorEntityCommands.createMeshEntityFromHandle(contextPtr, meshHandle, outId, outIdSize)
}

@_cdecl("MCEEditorCreateMeshEntityFromHandleWithMaterials")
public func MCEEditorCreateMeshEntityFromHandleWithMaterials(_ contextPtr: UnsafeRawPointer?,
                                                             _ meshHandle: UnsafePointer<CChar>?,
                                                             _ outId: UnsafeMutablePointer<CChar>?,
                                                             _ outIdSize: Int32) -> Int32 {
    EditorEntityCommands.createMeshEntityFromHandleWithMaterials(contextPtr, meshHandle, outId, outIdSize)
}

@_cdecl("MCEEditorCreateImportedMeshEntity")
public func MCEEditorCreateImportedMeshEntity(_ contextPtr: UnsafeRawPointer?,
                                              _ meshHandle: UnsafePointer<CChar>?,
                                              _ skeletonHandle: UnsafePointer<CChar>?,
                                              _ defaultClipHandle: UnsafePointer<CChar>?,
                                              _ submeshMaterialHandles: UnsafePointer<CChar>?,
                                              _ meshPath: UnsafePointer<CChar>?,
                                              _ outId: UnsafeMutablePointer<CChar>?,
                                              _ outIdSize: Int32) -> Int32 {
    EditorEntityCommands.createImportedMeshEntity(
        contextPtr,
        meshHandle,
        skeletonHandle,
        defaultClipHandle,
        submeshMaterialHandles,
        meshPath,
        outId,
        outIdSize
    )
}

@_cdecl("MCEEditorInstantiatePrefabFromHandle")
public func MCEEditorInstantiatePrefabFromHandle(_ contextPtr: UnsafeRawPointer?,
                                                 _ prefabHandle: UnsafePointer<CChar>?,
                                                 _ outId: UnsafeMutablePointer<CChar>?,
                                                 _ outIdSize: Int32) -> Int32 {
    EditorAssetReferenceResolver.instantiatePrefabFromHandle(contextPtr, prefabHandle, outId, outIdSize)
}

@_cdecl("MCEEditorCreatePrefabFromEntity")
public func MCEEditorCreatePrefabFromEntity(_ contextPtr: UnsafeRawPointer?,
                                            _ entityId: UnsafePointer<CChar>?,
                                            _ outPath: UnsafeMutablePointer<CChar>?,
                                            _ outPathSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          !context.bridgeServices.isPlaying,
          !context.bridgeServices.isSimulating,
          let entity = entity(from: entityId, context: context),
          let scene = context.bridgeServices.activeScene() else { return 0 }
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
    EditorAssetReferenceResolver.getPrefabInstanceInfo(
        contextPtr,
        entityId,
        prefabHandleOut,
        prefabHandleOutSize,
        prefabPathOut,
        prefabPathOutSize
    )
}

@_cdecl("MCEEditorApplyPrefabInstanceToAsset")
public func MCEEditorApplyPrefabInstanceToAsset(_ contextPtr: UnsafeRawPointer?,
                                                _ entityId: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          !context.bridgeServices.isPlaying,
          !context.bridgeServices.isSimulating,
          let resolved = resolvePrefabInstance(context, entityId),
          let prefabURL = context.bridgeServices.assetURL(for: resolved.link.prefabHandle) else { return 0 }

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

        let saved = context.bridgeServices.performAssetMutation {
            try PrefabSerializer.save(prefab: updatedPrefab, to: prefabURL)
            return true
        }
        guard saved else { return 0 }

        resolved.scene.ecs.remove(PrefabOverrideComponent.self, from: resolved.entity)
        context.engineContext.prefabSystem.applyPrefabs(handles: Set([resolved.link.prefabHandle]), to: resolved.scene)
        context.bridgeServices.notifySceneMutation()
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
          !context.bridgeServices.isPlaying,
          !context.bridgeServices.isSimulating,
          let resolved = resolvePrefabInstance(context, entityId) else { return 0 }

    do {
        guard let prefabURL = context.bridgeServices.assetURL(for: resolved.link.prefabHandle) else { return 0 }
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
    context.bridgeServices.notifySceneMutation()
    return 1
}

@_cdecl("MCEEditorCreateLightEntity")
public func MCEEditorCreateLightEntity(_ contextPtr: UnsafeRawPointer?,
                                       _ lightType: Int32,
                                       _ outId: UnsafeMutablePointer<CChar>?,
                                       _ outIdSize: Int32) -> Int32 {
    EditorEntityCommands.createLightEntity(contextPtr, lightType, outId, outIdSize)
}

@_cdecl("MCEEditorCreateSkyEntity")
public func MCEEditorCreateSkyEntity(_ contextPtr: UnsafeRawPointer?,
                                     _ outId: UnsafeMutablePointer<CChar>?,
                                     _ outIdSize: Int32) -> Int32 {
    EditorEntityCommands.createSkyEntity(contextPtr, outId, outIdSize)
}

@_cdecl("MCEEditorCreateEnvironmentEntity")
public func MCEEditorCreateEnvironmentEntity(_ contextPtr: UnsafeRawPointer?,
                                             _ outId: UnsafeMutablePointer<CChar>?,
                                             _ outIdSize: Int32) -> Int32 {
    EditorEntityCommands.createEnvironmentEntity(contextPtr, outId, outIdSize)
}

@_cdecl("MCEEditorCreateCameraEntity")
public func MCEEditorCreateCameraEntity(_ contextPtr: UnsafeRawPointer?,
                                        _ outId: UnsafeMutablePointer<CChar>?,
                                        _ outIdSize: Int32) -> Int32 {
    EditorEntityCommands.createCameraEntity(contextPtr, outId, outIdSize)
}

@_cdecl("MCEEditorCreateCameraFromView")
public func MCEEditorCreateCameraFromView(_ contextPtr: UnsafeRawPointer?,
                                          _ outId: UnsafeMutablePointer<CChar>?,
                                          _ outIdSize: Int32) -> Int32 {
    EditorEntityCommands.createCameraFromView(contextPtr, outId, outIdSize)
}

@_cdecl("MCEEditorDestroyEntity")
public func MCEEditorDestroyEntity(_ contextPtr: UnsafeRawPointer?, _ entityId: UnsafePointer<CChar>?) {
    EditorEntityCommands.destroyEntity(contextPtr, entityId)
}

@_cdecl("MCEEditorDestroySelectedEntities")
public func MCEEditorDestroySelectedEntities(_ contextPtr: UnsafeRawPointer?) {
    EditorEntityCommands.destroySelectedEntities(contextPtr)
}

@_cdecl("MCEEditorEntityHasComponent")
public func MCEEditorEntityHasComponent(_ contextPtr: UnsafeRawPointer?,
                                        _ entityId: UnsafePointer<CChar>?,
                                        _ componentType: Int32) -> UInt32 {
    EditorComponentCommands.entityHasComponent(contextPtr, entityId, componentType)
}

@_cdecl("MCEEditorAddComponent")
public func MCEEditorAddComponent(_ contextPtr: UnsafeRawPointer?,
                                  _ entityId: UnsafePointer<CChar>?,
                                  _ componentType: Int32) -> UInt32 {
    EditorComponentCommands.addComponent(contextPtr, entityId, componentType)
}

@_cdecl("MCEEditorRemoveComponent")
public func MCEEditorRemoveComponent(_ contextPtr: UnsafeRawPointer?,
                                     _ entityId: UnsafePointer<CChar>?,
                                     _ componentType: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          !context.bridgeServices.isPlaying,
          !context.bridgeServices.isSimulating,
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
    case .skinnedMesh:
        ecs.remove(SkinnedMeshComponent.self, from: entity)
    case .animator:
        ecs.remove(AnimatorComponent.self, from: entity)
    case .reflectionProbe:
        ecs.remove(ReflectionProbeComponent.self, from: entity)
    case .environment:
        ecs.remove(EnvironmentComponent.self, from: entity)
        ecs.remove(EnvironmentRuntimeStateComponent.self, from: entity)
        ecs.remove(EnvironmentIBLStateComponent.self, from: entity)
    }
    context.bridgeServices.notifySceneMutation()
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
          !context.bridgeServices.isSimulating,
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
    context.bridgeServices.notifySceneMutation()
    return 1
}

@_cdecl("MCEEditorClearScriptFieldData")
public func MCEEditorClearScriptFieldData(_ contextPtr: UnsafeRawPointer?,
                                          _ entityId: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          !context.bridgeServices.isSimulating,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          var script = ecs.get(ScriptComponent.self, for: entity) else { return 0 }
    script.fieldData = Data()
    script.fieldDataVersion = max(1, script.fieldDataVersion)
    script.serializedFields = [:]
    script.fieldMetadata = [:]
    ecs.add(script, to: entity)
    context.bridgeServices.notifySceneMutation()
    return 1
}

@_cdecl("MCEEditorResetScriptFieldsToDefaults")
public func MCEEditorResetScriptFieldsToDefaults(_ contextPtr: UnsafeRawPointer?,
                                                 _ entityId: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          !context.bridgeServices.isSimulating,
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
    context.bridgeServices.notifySceneMutation()
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
          !context.bridgeServices.isSimulating,
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
    context.bridgeServices.notifySceneMutation()
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
          context.bridgeServices.isPlaying,
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
          let scene = context.bridgeServices.activeScene(),
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
    debugDraw?.pointee = scene.isCharacterDebugDrawEnabled(entityId: entity.id) ? 1 : 0
    grounded?.pointee = controller.isGrounded ? 1 : 0
    speed?.pointee = simd_length(controller.velocity)
    velocityY?.pointee = controller.velocity.y
    groundBodyId?.pointee = controller.lastGroundBodyId
    let diagnostics = scene.latestFixedStepDiagnostics()
    fixedDeltaTime?.pointee = diagnostics.fixedDeltaTime
    interpolationAlpha?.pointee = diagnostics.interpolationAlpha
    return 1
}

@_cdecl("MCEEditorGetPhysicsScriptEventQueueTelemetry")
public func MCEEditorGetPhysicsScriptEventQueueTelemetry(_ contextPtr: UnsafeRawPointer?,
                                                         _ droppedCollisionEvents: UnsafeMutablePointer<UInt32>?,
                                                         _ droppedTriggerEvents: UnsafeMutablePointer<UInt32>?,
                                                         _ droppedStayEvents: UnsafeMutablePointer<UInt32>?,
                                                         _ totalDroppedCollisionEvents: UnsafeMutablePointer<UInt32>?,
                                                         _ totalDroppedTriggerEvents: UnsafeMutablePointer<UInt32>?,
                                                         _ totalDroppedStayEvents: UnsafeMutablePointer<UInt32>?,
                                                         _ triggerQueueCap: UnsafeMutablePointer<UInt32>?,
                                                         _ collisionQueueCap: UnsafeMutablePointer<UInt32>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let scene = context.bridgeServices.activeScene() else { return 0 }
    let telemetry = scene.physicsScriptEventQueueTelemetry()
    droppedCollisionEvents?.pointee = UInt32(max(0, telemetry.droppedCollisionEvents))
    droppedTriggerEvents?.pointee = UInt32(max(0, telemetry.droppedTriggerEvents))
    droppedStayEvents?.pointee = UInt32(max(0, telemetry.droppedStayEvents))
    totalDroppedCollisionEvents?.pointee = UInt32(max(0, telemetry.totalDroppedCollisionEvents))
    totalDroppedTriggerEvents?.pointee = UInt32(max(0, telemetry.totalDroppedTriggerEvents))
    totalDroppedStayEvents?.pointee = UInt32(max(0, telemetry.totalDroppedStayEvents))
    if let physicsSystem = scene.physicsSystem {
        let limits = physicsSystem.scriptEventQueueConfig()
        triggerQueueCap?.pointee = UInt32(max(0, limits.maxTriggerEventsPerFrame))
        collisionQueueCap?.pointee = UInt32(max(0, limits.maxCollisionEventsPerFrame))
    } else {
        triggerQueueCap?.pointee = 0
        collisionQueueCap?.pointee = 0
    }
    return 1
}

@_cdecl("MCEEditorSetPhysicsScriptEventQueueLimits")
public func MCEEditorSetPhysicsScriptEventQueueLimits(_ contextPtr: UnsafeRawPointer?,
                                                      _ triggerQueueCap: UInt32,
                                                      _ collisionQueueCap: UInt32) {
    guard let context = resolveContext(contextPtr),
          let scene = context.bridgeServices.activeScene(),
          let physicsSystem = scene.physicsSystem else { return }
    physicsSystem.setScriptEventQueueLimits(
        .init(maxTriggerEventsPerFrame: max(1, Int(triggerQueueCap)),
              maxCollisionEventsPerFrame: max(1, Int(collisionQueueCap)))
    )
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
          !context.bridgeServices.isPlaying,
          let scene = context.bridgeServices.activeScene(),
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
                                                  yawRadians: previous?.yawRadians ?? 0.0,
                                                  pitchRadians: previous?.pitchRadians ?? 0.0,
                                                  lookInitialized: previous?.lookInitialized ?? false)
    ecs.add(controller, to: entity)
    scene.setCharacterDebugDrawEnabled(entityId: entity.id, isEnabled: debugDraw != 0)
    context.bridgeServices.notifySceneMutation()
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
          !context.bridgeServices.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          var controller = ecs.get(CharacterControllerComponent.self, for: entity) else { return 0 }
    if let visualEntityId, visualEntityId.pointee != 0 {
        controller.visualEntityId = UUID(uuidString: String(cString: visualEntityId))
    } else {
        controller.visualEntityId = nil
    }
    if let visualID = controller.visualEntityId,
       let visualEntity = ecs.entity(with: visualID) {
        if ecs.get(AnimatorComponent.self, for: visualEntity) != nil {
            controller.animatorEntityId = visualEntity.id
        } else {
            controller.animatorEntityId = firstAnimatorInSubtree(root: visualEntity, ecs: ecs)?.id
        }
    } else {
        controller.animatorEntityId = nil
    }
    if let cameraPivotEntityId, cameraPivotEntityId.pointee != 0 {
        controller.cameraPivotEntityId = UUID(uuidString: String(cString: cameraPivotEntityId))
    } else {
        controller.cameraPivotEntityId = nil
    }
    ecs.add(controller, to: entity)
    context.bridgeServices.notifySceneMutation()
    return 1
}

@_cdecl("MCEEditorCharacterControllerEnsureDependencies")
public func MCEEditorCharacterControllerEnsureDependencies(_ contextPtr: UnsafeRawPointer?,
                                                           _ entityId: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          !context.bridgeServices.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let controller = ecs.get(CharacterControllerComponent.self, for: entity) else { return 0 }
    let changed = ensureCharacterControllerDependencies(context: context, ecs: ecs, entity: entity, controller: controller)
    if changed {
        context.bridgeServices.notifySceneMutation()
    }
    return changed ? 1 : 0
}

@_cdecl("MCEEditorCharacterControllerSetRigidbodyKinematic")
public func MCEEditorCharacterControllerSetRigidbodyKinematic(_ contextPtr: UnsafeRawPointer?,
                                                              _ entityId: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          !context.bridgeServices.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return 0 }
    guard ensureCharacterControllerRigidbody(context: context, ecs: ecs, entity: entity) else { return 0 }
    context.bridgeServices.notifySceneMutation()
    return 1
}

@_cdecl("MCEEditorCharacterControllerRemoveRigidbody")
public func MCEEditorCharacterControllerRemoveRigidbody(_ contextPtr: UnsafeRawPointer?,
                                                        _ entityId: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          !context.bridgeServices.isPlaying,
          !context.bridgeServices.isSimulating,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          ecs.get(RigidbodyComponent.self, for: entity) != nil else { return 0 }
    ecs.remove(RigidbodyComponent.self, from: entity)
    context.bridgeServices.notifySceneMutation()
    return 1
}

@_cdecl("MCEEditorCharacterControllerConvertColliderToCapsule")
public func MCEEditorCharacterControllerConvertColliderToCapsule(_ contextPtr: UnsafeRawPointer?,
                                                                 _ entityId: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          !context.bridgeServices.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let controller = ecs.get(CharacterControllerComponent.self, for: entity) else { return 0 }
    guard convertCharacterControllerColliderToCapsule(ecs: ecs, entity: entity, controller: controller) else { return 0 }
    context.bridgeServices.notifySceneMutation()
    return 1
}

@_cdecl("MCEEditorCharacterControllerAddCapsuleCollider")
public func MCEEditorCharacterControllerAddCapsuleCollider(_ contextPtr: UnsafeRawPointer?,
                                                           _ entityId: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          !context.bridgeServices.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let controller = ecs.get(CharacterControllerComponent.self, for: entity) else { return 0 }
    let changed = ensureCharacterControllerCapsuleCollider(context: context,
                                                           ecs: ecs,
                                                           entity: entity,
                                                           controller: controller,
                                                           autoSizeFromMesh: true)
    guard changed else { return 0 }
    context.bridgeServices.notifySceneMutation()
    return 1
}

@_cdecl("MCEEditorCharacterControllerCreateRecommendedHierarchy")
public func MCEEditorCharacterControllerCreateRecommendedHierarchy(_ contextPtr: UnsafeRawPointer?,
                                                                   _ entityId: UnsafePointer<CChar>?,
                                                                   _ createCamera: UInt32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          !context.bridgeServices.isPlaying,
          !context.bridgeServices.isSimulating,
          let scene = context.bridgeServices.activeScene(),
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
    if controller.animatorEntityId == nil || (controller.animatorEntityId.flatMap { ecs.entity(with: $0) } == nil) {
        if ecs.get(AnimatorComponent.self, for: visualEntity) != nil {
            controller.animatorEntityId = visualEntity.id
            didMutate = true
        } else if let discovered = firstAnimatorInSubtree(root: visualEntity, ecs: ecs) {
            controller.animatorEntityId = discovered.id
            didMutate = true
        }
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
                _ = scene.transformAuthority.ensureLocalTransform(entity: camera.child,
                                                                  default: TransformComponent(),
                                                                  source: .editor)
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
        context.bridgeServices.notifySceneMutation()
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
          !context.bridgeServices.isPlaying,
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
    context.bridgeServices.notifySceneMutation()
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
          !context.bridgeServices.isPlaying,
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
    context.bridgeServices.notifySceneMutation()
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
          !context.bridgeServices.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          var collider = ecs.get(ColliderComponent.self, for: entity) else { return }
    var shapes = collider.allShapes()
    shapes.append(ColliderShape())
    collider.setShapes(shapes)
    ecs.add(collider, to: entity)
    context.bridgeServices.notifySceneMutation()
}

@_cdecl("MCEEditorRemoveColliderShape")
public func MCEEditorRemoveColliderShape(_ contextPtr: UnsafeRawPointer?,
                                         _ entityId: UnsafePointer<CChar>?,
                                         _ shapeIndex: Int32) {
    guard let context = resolveContext(contextPtr),
          !context.bridgeServices.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          var collider = ecs.get(ColliderComponent.self, for: entity) else { return }
    var shapes = collider.allShapes()
    guard shapeIndex >= 0, shapeIndex < Int32(shapes.count) else { return }
    if shapes.count == 1 {
        ecs.remove(ColliderComponent.self, from: entity)
        context.bridgeServices.notifySceneMutation()
        return
    } else {
        shapes.remove(at: Int(shapeIndex))
    }
    collider.setShapes(shapes)
    ecs.add(collider, to: entity)
    context.bridgeServices.notifySceneMutation()
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
          !context.bridgeServices.isPlaying,
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
    context.bridgeServices.notifySceneMutation()
}

@_cdecl("MCEEditorRebuildPhysicsBody")
public func MCEEditorRebuildPhysicsBody(_ contextPtr: UnsafeRawPointer?,
                                        _ entityId: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          context.bridgeServices.isPlaying,
          let runtimeScene = context.bridgeServices.runtimeScene,
          let entityId else { return 0 }
    let idString = String(cString: entityId)
    guard let uuid = UUID(uuidString: idString),
          let entity = runtimeScene.ecs.entity(with: uuid) else { return 0 }
    let success = runtimeScene.rebuildPhysicsBody(for: entity)
    return success ? 1 : 0
}

@_cdecl("MCEEditorGetColliderEntityCount")
public func MCEEditorGetColliderEntityCount(_ contextPtr: UnsafeRawPointer?) -> Int32 {
    EditorSceneQueries.getColliderEntityCount(contextPtr)
}

@_cdecl("MCEEditorGetColliderEntityAt")
public func MCEEditorGetColliderEntityAt(_ contextPtr: UnsafeRawPointer?,
                                        _ index: Int32,
                                        _ buffer: UnsafeMutablePointer<CChar>?,
                                        _ bufferSize: Int32) -> UInt32 {
    EditorSceneQueries.getColliderEntityAt(contextPtr, index, buffer, bufferSize)
}

@_cdecl("MCEEditorGetTransform")
public func MCEEditorGetTransform(_ contextPtr: UnsafeRawPointer?,
                                  _ entityId: UnsafePointer<CChar>?,
                                  _ px: UnsafeMutablePointer<Float>?, _ py: UnsafeMutablePointer<Float>?, _ pz: UnsafeMutablePointer<Float>?,
                                  _ rx: UnsafeMutablePointer<Float>?, _ ry: UnsafeMutablePointer<Float>?, _ rz: UnsafeMutablePointer<Float>?,
                                  _ sx: UnsafeMutablePointer<Float>?, _ sy: UnsafeMutablePointer<Float>?, _ sz: UnsafeMutablePointer<Float>?) -> UInt32 {
    EditorBridgeInternals.thinRoute("MCEEditorGetTransform") {
        EditorTransformCommands.getTransform(contextPtr, entityId, px, py, pz, rx, ry, rz, sx, sy, sz)
    }
}

@_cdecl("MCEEditorSetTransform")
public func MCEEditorSetTransform(_ contextPtr: UnsafeRawPointer?,
                                  _ entityId: UnsafePointer<CChar>?,
                                  _ px: Float, _ py: Float, _ pz: Float,
                                  _ rx: Float, _ ry: Float, _ rz: Float,
                                  _ sx: Float, _ sy: Float, _ sz: Float) {
    EditorBridgeInternals.thinRoute("MCEEditorSetTransform") {
        EditorTransformCommands.setTransform(contextPtr, entityId, px, py, pz, rx, ry, rz, sx, sy, sz)
    }
}

/// Debug-only regression guard entrypoint.
/// Trigger from LLDB or a debug utility by calling `MCEEditorRunDebugRegressionGuards(contextPtr)`.
@_cdecl("MCEEditorRunDebugRegressionGuards")
public func MCEEditorRunDebugRegressionGuards(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let scene = context.bridgeServices.activeScene() else { return 0 }
#if DEBUG
    var entityIdBuffer = [CChar](repeating: 0, count: 64)
    let createdLength = MCEEditorCreateEntity(contextPtr, nil, &entityIdBuffer, Int32(entityIdBuffer.count))
    guard createdLength > 0 else { return 0 }
    let entityIdString = String(cString: entityIdBuffer)
    let beforeEditorMutations = scene.transformAuthority.debugSnapshotEditorMutationCount()
    let setResult = entityIdString.withCString { idPtr in
        MCEEditorSetTransform(contextPtr, idPtr, 1.0, 2.0, 3.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0)
        return MCEEditorGetTransform(contextPtr,
                                     idPtr,
                                     nil, nil, nil,
                                     nil, nil, nil,
                                     nil, nil, nil)
    }
    guard setResult == 1 else { return 0 }
    let afterEditorMutations = scene.transformAuthority.debugSnapshotEditorMutationCount()
    MC_ASSERT(afterEditorMutations > beforeEditorMutations,
              "Editor transform command did not route through TransformAuthority editor mutation path.")
#endif
    return 1
}

@_cdecl("MCEEditorSetTransformNoLog")
public func MCEEditorSetTransformNoLog(_ contextPtr: UnsafeRawPointer?,
                                       _ entityId: UnsafePointer<CChar>?,
                                       _ px: Float, _ py: Float, _ pz: Float,
                                       _ rx: Float, _ ry: Float, _ rz: Float,
                                       _ sx: Float, _ sy: Float, _ sz: Float) {
    EditorTransformCommands.setTransform(contextPtr, entityId, px, py, pz, rx, ry, rz, sx, sy, sz)
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
          !context.bridgeServices.isPlaying,
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
    context.bridgeServices.notifySceneMutation()
}

@_cdecl("MCEEditorGetCameraExposure")
public func MCEEditorGetCameraExposure(_ contextPtr: UnsafeRawPointer?,
                                       _ entityId: UnsafePointer<CChar>?,
                                       _ autoExposureEnabled: UnsafeMutablePointer<UInt32>?,
                                       _ exposureEV: UnsafeMutablePointer<Float>?,
                                       _ exposureCompensation: UnsafeMutablePointer<Float>?,
                                       _ autoExposureMin: UnsafeMutablePointer<Float>?,
                                       _ autoExposureMax: UnsafeMutablePointer<Float>?,
                                       _ adaptationSpeed: UnsafeMutablePointer<Float>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let camera = ecs.get(CameraComponent.self, for: entity) else { return 0 }
    autoExposureEnabled?.pointee = 0
    exposureEV?.pointee = camera.exposureEV
    exposureCompensation?.pointee = camera.exposureCompensation
    autoExposureMin?.pointee = camera.autoExposureMin
    autoExposureMax?.pointee = camera.autoExposureMax
    adaptationSpeed?.pointee = camera.adaptationSpeed
    return 1
}

@_cdecl("MCEEditorSetCameraExposure")
public func MCEEditorSetCameraExposure(_ contextPtr: UnsafeRawPointer?,
                                       _ entityId: UnsafePointer<CChar>?,
                                       _ autoExposureEnabled: UInt32,
                                       _ exposureEV: Float,
                                       _ exposureCompensation: Float,
                                       _ autoExposureMin: Float,
                                       _ autoExposureMax: Float,
                                       _ adaptationSpeed: Float) {
    guard let context = resolveContext(contextPtr),
          !context.bridgeServices.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          var camera = ecs.get(CameraComponent.self, for: entity) else { return }

    camera.autoExposureEnabled = false
    camera.exposureEV = min(max(exposureEV, -16.0), 16.0)
    ecs.add(camera, to: entity)
    context.bridgeServices.notifySceneMutation()
}

@_cdecl("MCEEditorSetTransformFromMatrix")
public func MCEEditorSetTransformFromMatrix(_ contextPtr: UnsafeRawPointer?,
                                            _ entityId: UnsafePointer<CChar>?,
                                            _ matrix: UnsafePointer<Float>?) -> UInt32 {
    EditorTransformCommands.setTransformFromMatrix(contextPtr, entityId, matrix)
}

@_cdecl("MCEEditorGetModelMatrix")
public func MCEEditorGetModelMatrix(_ contextPtr: UnsafeRawPointer?,
                                    _ entityId: UnsafePointer<CChar>?,
                                    _ matrixOut: UnsafeMutablePointer<Float>?) -> UInt32 {
    EditorSceneQueries.getModelMatrix(contextPtr, entityId, matrixOut)
}

@_cdecl("MCEEditorGetEditorCameraMatrices")
public func MCEEditorGetEditorCameraMatrices(_ contextPtr: UnsafeRawPointer?,
                                             _ viewOut: UnsafeMutablePointer<Float>?,
                                             _ projectionOut: UnsafeMutablePointer<Float>?) -> UInt32 {
    EditorSceneQueries.getEditorCameraMatrices(contextPtr, viewOut, projectionOut)
}

@_cdecl("MCEEditorDebugPhysicsRaycastFromCamera")
public func MCEEditorDebugPhysicsRaycastFromCamera(_ contextPtr: UnsafeRawPointer?,
                                                   _ maxDistance: Float) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let scene = context.bridgeServices.activeScene() else { return 0 }
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
        debugDraw.submitLine(category: .generic, hit.position - offsetX, hit.position + offsetX, color: color)
        debugDraw.submitLine(category: .generic, hit.position - offsetZ, hit.position + offsetZ, color: color)
        debugDraw.submitLine(category: .generic, hit.position, hit.position + hit.normal * normalLength, color: color)
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
          !context.bridgeServices.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return }
    let meshString = meshHandle != nil ? String(cString: meshHandle!) : ""
    let materialString = materialHandle != nil ? String(cString: materialHandle!) : ""
    var component = ecs.get(MeshRendererComponent.self, for: entity) ?? MeshRendererComponent(meshHandle: nil)
    component.meshHandle = handleFromString(meshString)
    component.materialHandle = handleFromString(materialString)
    ecs.add(component, to: entity)
    context.bridgeServices.notifySceneMutation()
}

@_cdecl("MCEEditorAssignMaterialToEntity")
public func MCEEditorAssignMaterialToEntity(_ contextPtr: UnsafeRawPointer?,
                                            _ entityId: UnsafePointer<CChar>?,
                                            _ materialHandle: UnsafePointer<CChar>?) {
    guard let context = resolveContext(contextPtr),
          !context.bridgeServices.isPlaying,
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

    context.bridgeServices.notifySceneMutation()
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
          !context.bridgeServices.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return }
    let materialString = materialHandle != nil ? String(cString: materialHandle!) : ""
    var component = ecs.get(MaterialComponent.self, for: entity) ?? MaterialComponent(materialHandle: nil)
    component.materialHandle = handleFromString(materialString)
    ecs.add(component, to: entity)
    context.bridgeServices.notifySceneMutation()
}

@_cdecl("MCEEditorGetSkinnedMesh")
public func MCEEditorGetSkinnedMesh(_ contextPtr: UnsafeRawPointer?,
                                    _ entityId: UnsafePointer<CChar>?,
                                    _ skeletonHandle: UnsafeMutablePointer<CChar>?,
                                    _ skeletonHandleSize: Int32,
                                    _ jointCount: UnsafeMutablePointer<Int32>?,
                                    _ isValid: UnsafeMutablePointer<UInt32>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let skinned = ecs.get(SkinnedMeshComponent.self, for: entity) else { return 0 }
    let skeletonString = skinned.skeletonHandle?.rawValue.uuidString ?? ""
    _ = writeCString(skeletonString, to: skeletonHandle, max: skeletonHandleSize)
    if let handle = skinned.skeletonHandle,
       let skeleton = context.engineContext.assets.skeleton(handle: handle) {
        jointCount?.pointee = Int32(skeleton.joints.count)
        isValid?.pointee = skeleton.joints.isEmpty ? 0 : 1
    } else {
        jointCount?.pointee = 0
        isValid?.pointee = 0
    }
    return 1
}

@_cdecl("MCEEditorSetSkinnedMesh")
public func MCEEditorSetSkinnedMesh(_ contextPtr: UnsafeRawPointer?,
                                    _ entityId: UnsafePointer<CChar>?,
                                    _ skeletonHandle: UnsafePointer<CChar>?) {
    guard let context = resolveContext(contextPtr),
          !context.bridgeServices.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return }
    let skeletonString = skeletonHandle != nil ? String(cString: skeletonHandle!) : ""
    var component = ecs.get(SkinnedMeshComponent.self, for: entity) ?? SkinnedMeshComponent()
    component.skeletonHandle = handleFromString(skeletonString)
    ecs.add(component, to: entity)
    context.bridgeServices.notifySceneMutation()
}

@_cdecl("MCEEditorGetAnimator")
public func MCEEditorGetAnimator(_ contextPtr: UnsafeRawPointer?,
                                 _ entityId: UnsafePointer<CChar>?,
                                 _ clipHandle: UnsafeMutablePointer<CChar>?,
                                 _ clipHandleSize: Int32,
                                 _ playbackTime: UnsafeMutablePointer<Float>?,
                                 _ playbackSpeed: UnsafeMutablePointer<Float>?,
                                 _ isPlaying: UnsafeMutablePointer<UInt32>?,
                                 _ isLooping: UnsafeMutablePointer<UInt32>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let animator = ecs.get(AnimatorComponent.self, for: entity) else { return 0 }
    let clipString = animator.clipHandle?.rawValue.uuidString ?? ""
    _ = writeCString(clipString, to: clipHandle, max: clipHandleSize)
    playbackTime?.pointee = animator.playbackTime
    playbackSpeed?.pointee = animator.playbackSpeed
    isPlaying?.pointee = animator.isPlaying ? 1 : 0
    isLooping?.pointee = animator.isLooping ? 1 : 0
    return 1
}

@_cdecl("MCEEditorSetAnimator")
public func MCEEditorSetAnimator(_ contextPtr: UnsafeRawPointer?,
                                 _ entityId: UnsafePointer<CChar>?,
                                 _ clipHandle: UnsafePointer<CChar>?,
                                 _ playbackTime: Float,
                                 _ playbackSpeed: Float,
                                 _ isPlaying: UInt32,
                                 _ isLooping: UInt32) {
    guard let context = resolveContext(contextPtr),
          !context.bridgeServices.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return }
    let clipString = clipHandle != nil ? String(cString: clipHandle!) : ""
    var component = ecs.get(AnimatorComponent.self, for: entity) ?? AnimatorComponent()
    let previousClipHandle = component.clipHandle
    let resolvedClipHandle = handleFromString(clipString)
    component.evaluationMode = .clip
    component.clipHandle = resolvedClipHandle
    component.graphHandle = nil
    component.graphRuntimeState = nil
    component.playbackTime = max(0.0, playbackTime)
    component.playbackSpeed = max(0.0, playbackSpeed)
    component.isPlaying = isPlaying != 0
    component.isLooping = isLooping != 0
    ecs.add(component, to: entity)
#if DEBUG
    if previousClipHandle != resolvedClipHandle {
        let previousPath = previousClipHandle.flatMap { context.bridgeServices.assetURL(for: $0)?.path } ?? "<none>"
        let selectedPath = resolvedClipHandle.flatMap { context.bridgeServices.assetURL(for: $0)?.path } ?? "<none>"
        EngineLoggerContext.log(
            "Animator clip selection updated entity=\(entity.id.uuidString)\npreviousClipHandle=\(previousClipHandle?.rawValue.uuidString ?? "<none>")\npreviousClipPath=\(previousPath)\nselectedClipHandle=\(resolvedClipHandle?.rawValue.uuidString ?? "<none>")\nselectedClipPath=\(selectedPath)",
            level: .debug,
            category: .assets
        )
    }
#endif
    context.bridgeServices.notifySceneMutation()
}

@_cdecl("MCEEditorGetAnimatorMode")
public func MCEEditorGetAnimatorMode(_ contextPtr: UnsafeRawPointer?,
                                     _ entityId: UnsafePointer<CChar>?,
                                     _ modeOut: UnsafeMutablePointer<Int32>?,
                                     _ graphHandle: UnsafeMutablePointer<CChar>?,
                                     _ graphHandleSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let animator = ecs.get(AnimatorComponent.self, for: entity) else { return 0 }
    modeOut?.pointee = animator.evaluationMode == .graph ? 1 : 0
    _ = writeCString(animator.graphHandle?.rawValue.uuidString ?? "", to: graphHandle, max: graphHandleSize)
    return 1
}

@_cdecl("MCEEditorSetAnimatorGraph")
public func MCEEditorSetAnimatorGraph(_ contextPtr: UnsafeRawPointer?,
                                      _ entityId: UnsafePointer<CChar>?,
                                      _ graphHandle: UnsafePointer<CChar>?,
                                      _ playbackTime: Float,
                                      _ playbackSpeed: Float,
                                      _ isPlaying: UInt32,
                                      _ isLooping: UInt32) {
    guard let context = resolveContext(contextPtr),
          !context.bridgeServices.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return }
    let graphString = graphHandle != nil ? String(cString: graphHandle!) : ""
    var component = ecs.get(AnimatorComponent.self, for: entity) ?? AnimatorComponent()
    component.evaluationMode = .graph
    component.graphHandle = handleFromString(graphString)
    component.clipHandle = nil
    component.graphRuntimeState = nil
    component.playbackTime = max(0.0, playbackTime)
    component.playbackSpeed = max(0.0, playbackSpeed)
    component.isPlaying = isPlaying != 0
    component.isLooping = isLooping != 0
    ecs.add(component, to: entity)
    context.bridgeServices.notifySceneMutation()
}

private func graphRuntimeSnapshot(context: MCEContext,
                                  animator: AnimatorComponent) -> (CompiledAnimationGraph, AnimationGraphRuntimeInstanceState)? {
    guard animator.evaluationMode == .graph,
          let graphHandle = animator.graphHandle,
          let compiledGraph = context.engineContext.assets.compiledAnimationGraph(handle: graphHandle) else { return nil }
    var runtimeState = animator.graphRuntimeState ?? AnimationGraphRuntimeInstanceState()
    if runtimeState.graphHandle != graphHandle ||
        !runtimeState.hasStorage(parameterCount: compiledGraph.parameters.count,
                                 localVariableCount: compiledGraph.localVariables.count) {
        runtimeState.resetDefaults(from: compiledGraph, graphHandle: graphHandle)
    }
    return (compiledGraph, runtimeState)
}

@_cdecl("MCEEditorGetAnimatorGraphParameterCount")
public func MCEEditorGetAnimatorGraphParameterCount(_ contextPtr: UnsafeRawPointer?,
                                                    _ entityId: UnsafePointer<CChar>?) -> Int32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let animator = ecs.get(AnimatorComponent.self, for: entity),
          let (compiledGraph, _) = graphRuntimeSnapshot(context: context, animator: animator) else { return 0 }
    return Int32(compiledGraph.parameters.count)
}

@_cdecl("MCEEditorGetAnimatorGraphParameterAt")
public func MCEEditorGetAnimatorGraphParameterAt(_ contextPtr: UnsafeRawPointer?,
                                                 _ entityId: UnsafePointer<CChar>?,
                                                 _ index: Int32,
                                                 _ nameBuffer: UnsafeMutablePointer<CChar>?, _ nameBufferSize: Int32,
                                                 _ typeOut: UnsafeMutablePointer<Int32>?,
                                                 _ defaultFloatOut: UnsafeMutablePointer<Float>?,
                                                 _ defaultBoolOut: UnsafeMutablePointer<UInt32>?,
                                                 _ defaultIntOut: UnsafeMutablePointer<Int32>?,
                                                 _ floatValueOut: UnsafeMutablePointer<Float>?,
                                                 _ boolValueOut: UnsafeMutablePointer<UInt32>?,
                                                 _ intValueOut: UnsafeMutablePointer<Int32>?,
                                                 _ triggerValueOut: UnsafeMutablePointer<UInt32>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let animator = ecs.get(AnimatorComponent.self, for: entity),
          let (compiledGraph, runtimeState) = graphRuntimeSnapshot(context: context, animator: animator) else { return 0 }
    let i = Int(index)
    guard i >= 0, i < compiledGraph.parameters.count else { return 0 }
    let parameter = compiledGraph.parameters[i]
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
    floatValueOut?.pointee = runtimeState.floatParameterValues[i]
    boolValueOut?.pointee = runtimeState.boolParameterValues[i] ? 1 : 0
    intValueOut?.pointee = Int32(clamping: runtimeState.intParameterValues[i])
    let triggerValue = runtimeState.triggerParameterValues[i] || runtimeState.triggerLatchedParameterIndices.contains(i)
    triggerValueOut?.pointee = triggerValue ? 1 : 0
    return 1
}

private func mutateAnimatorGraphRuntime(context: MCEContext,
                                        entity: Entity,
                                        mutation: (_ runtimeState: inout AnimationGraphRuntimeInstanceState,
                                                   _ compiledGraph: CompiledAnimationGraph) -> Bool) -> Bool {
    guard let ecs = editorECS(context),
          var animator = ecs.get(AnimatorComponent.self, for: entity),
          let (compiledGraph, runtimeSnapshot) = graphRuntimeSnapshot(context: context, animator: animator) else { return false }
    var runtimeState = runtimeSnapshot
    guard mutation(&runtimeState, compiledGraph) else { return false }
    animator.graphRuntimeState = runtimeState
    ecs.add(animator, to: entity)
    return true
}

@_cdecl("MCEEditorSetAnimatorGraphParameterFloat")
public func MCEEditorSetAnimatorGraphParameterFloat(_ contextPtr: UnsafeRawPointer?,
                                                    _ entityId: UnsafePointer<CChar>?,
                                                    _ index: Int32,
                                                    _ value: Float) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return 0 }
    let didMutate = mutateAnimatorGraphRuntime(context: context, entity: entity) { runtimeState, compiledGraph in
        let i = Int(index)
        guard i >= 0, i < compiledGraph.parameters.count else { return false }
        runtimeState.setFloat(index: i, value: value)
        return true
    }
    return didMutate ? 1 : 0
}

@_cdecl("MCEEditorSetAnimatorGraphParameterBool")
public func MCEEditorSetAnimatorGraphParameterBool(_ contextPtr: UnsafeRawPointer?,
                                                   _ entityId: UnsafePointer<CChar>?,
                                                   _ index: Int32,
                                                   _ value: UInt32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return 0 }
    let didMutate = mutateAnimatorGraphRuntime(context: context, entity: entity) { runtimeState, compiledGraph in
        let i = Int(index)
        guard i >= 0, i < compiledGraph.parameters.count else { return false }
        runtimeState.setBool(index: i, value: value != 0)
        return true
    }
    return didMutate ? 1 : 0
}

@_cdecl("MCEEditorSetAnimatorGraphParameterInt")
public func MCEEditorSetAnimatorGraphParameterInt(_ contextPtr: UnsafeRawPointer?,
                                                  _ entityId: UnsafePointer<CChar>?,
                                                  _ index: Int32,
                                                  _ value: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return 0 }
    let didMutate = mutateAnimatorGraphRuntime(context: context, entity: entity) { runtimeState, compiledGraph in
        let i = Int(index)
        guard i >= 0, i < compiledGraph.parameters.count else { return false }
        runtimeState.setInt(index: i, value: Int(value))
        return true
    }
    return didMutate ? 1 : 0
}

@_cdecl("MCEEditorSetAnimatorGraphParameterTrigger")
public func MCEEditorSetAnimatorGraphParameterTrigger(_ contextPtr: UnsafeRawPointer?,
                                                      _ entityId: UnsafePointer<CChar>?,
                                                      _ index: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return 0 }
    let didMutate = mutateAnimatorGraphRuntime(context: context, entity: entity) { runtimeState, compiledGraph in
        let i = Int(index)
        guard i >= 0, i < compiledGraph.parameters.count else { return false }
        runtimeState.setTrigger(index: i)
        return true
    }
    return didMutate ? 1 : 0
}

@_cdecl("MCEEditorGetAnimatorGraphLocalVariableCount")
public func MCEEditorGetAnimatorGraphLocalVariableCount(_ contextPtr: UnsafeRawPointer?,
                                                        _ entityId: UnsafePointer<CChar>?) -> Int32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let animator = ecs.get(AnimatorComponent.self, for: entity),
          let (compiledGraph, _) = graphRuntimeSnapshot(context: context, animator: animator) else { return 0 }
    return Int32(compiledGraph.localVariables.count)
}

@_cdecl("MCEEditorGetAnimatorGraphLocalVariableAt")
public func MCEEditorGetAnimatorGraphLocalVariableAt(_ contextPtr: UnsafeRawPointer?,
                                                     _ entityId: UnsafePointer<CChar>?,
                                                     _ index: Int32,
                                                     _ nameBuffer: UnsafeMutablePointer<CChar>?, _ nameBufferSize: Int32,
                                                     _ typeOut: UnsafeMutablePointer<Int32>?,
                                                     _ defaultFloatOut: UnsafeMutablePointer<Float>?,
                                                     _ defaultBoolOut: UnsafeMutablePointer<UInt32>?,
                                                     _ defaultIntOut: UnsafeMutablePointer<Int32>?,
                                                     _ floatValueOut: UnsafeMutablePointer<Float>?,
                                                     _ boolValueOut: UnsafeMutablePointer<UInt32>?,
                                                     _ intValueOut: UnsafeMutablePointer<Int32>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let animator = ecs.get(AnimatorComponent.self, for: entity),
          let (compiledGraph, runtimeState) = graphRuntimeSnapshot(context: context, animator: animator) else { return 0 }
    let i = Int(index)
    guard i >= 0, i < compiledGraph.localVariables.count else { return 0 }
    let localVariable = compiledGraph.localVariables[i]
    _ = writeCString(localVariable.name, to: nameBuffer, max: nameBufferSize)
    switch localVariable.type {
    case .float: typeOut?.pointee = 0
    case .bool: typeOut?.pointee = 1
    case .int: typeOut?.pointee = 2
    }
    defaultFloatOut?.pointee = localVariable.defaultFloat
    defaultBoolOut?.pointee = localVariable.defaultBool ? 1 : 0
    defaultIntOut?.pointee = Int32(clamping: localVariable.defaultInt)
    floatValueOut?.pointee = runtimeState.floatLocalVariableValues[i]
    boolValueOut?.pointee = runtimeState.boolLocalVariableValues[i] ? 1 : 0
    intValueOut?.pointee = Int32(clamping: runtimeState.intLocalVariableValues[i])
    return 1
}

@_cdecl("MCEEditorGetAnimatorGraphStateMachineRuntime")
public func MCEEditorGetAnimatorGraphStateMachineRuntime(_ contextPtr: UnsafeRawPointer?,
                                                         _ entityId: UnsafePointer<CChar>?,
                                                         _ stateMachineNodeID: UnsafePointer<CChar>?,
                                                         _ currentStateBuffer: UnsafeMutablePointer<CChar>?,
                                                         _ currentStateBufferSize: Int32,
                                                         _ nextStateBuffer: UnsafeMutablePointer<CChar>?,
                                                         _ nextStateBufferSize: Int32,
                                                         _ transitionElapsedOut: UnsafeMutablePointer<Float>?,
                                                         _ transitionDurationOut: UnsafeMutablePointer<Float>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let animator = ecs.get(AnimatorComponent.self, for: entity),
          let (_, runtimeState) = graphRuntimeSnapshot(context: context, animator: animator),
          let stateMachineNodeID,
          let nodeUUID = UUID(uuidString: String(cString: stateMachineNodeID)) else { return 0 }
    guard let currentStateID = runtimeState.stateMachineCurrentStateByNodeID[nodeUUID] else { return 0 }
    _ = writeCString(currentStateID.uuidString, to: currentStateBuffer, max: currentStateBufferSize)
    let nextStateID = runtimeState.stateMachineNextStateByNodeID[nodeUUID]
    _ = writeCString(nextStateID?.uuidString ?? "", to: nextStateBuffer, max: nextStateBufferSize)
    transitionElapsedOut?.pointee = runtimeState.stateMachineTransitionElapsedByNodeID[nodeUUID] ?? 0.0
    transitionDurationOut?.pointee = runtimeState.stateMachineTransitionDurationByNodeID[nodeUUID] ?? 0.0
    return 1
}

@_cdecl("MCEEditorSetAnimatorGraphDebugTraceEnabled")
public func MCEEditorSetAnimatorGraphDebugTraceEnabled(_ contextPtr: UnsafeRawPointer?,
                                                       _ entityId: UnsafePointer<CChar>?,
                                                       _ enabled: UInt32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let entity = entity(from: entityId, context: context) else { return 0 }
    let didMutate = mutateAnimatorGraphRuntime(context: context, entity: entity) { runtimeState, _ in
        runtimeState.captureDebugTrace = (enabled != 0)
        if enabled == 0 {
            runtimeState.debugTraceEntries.removeAll(keepingCapacity: true)
        }
        return true
    }
    return didMutate ? 1 : 0
}

@_cdecl("MCEEditorGetAnimatorGraphDebugTraceCount")
public func MCEEditorGetAnimatorGraphDebugTraceCount(_ contextPtr: UnsafeRawPointer?,
                                                     _ entityId: UnsafePointer<CChar>?) -> Int32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let animator = ecs.get(AnimatorComponent.self, for: entity),
          let (_, runtimeState) = graphRuntimeSnapshot(context: context, animator: animator) else { return 0 }
    return Int32(runtimeState.debugTraceEntries.count)
}

@_cdecl("MCEEditorGetAnimatorGraphDebugTraceEntryAt")
public func MCEEditorGetAnimatorGraphDebugTraceEntryAt(_ contextPtr: UnsafeRawPointer?,
                                                       _ entityId: UnsafePointer<CChar>?,
                                                       _ index: Int32,
                                                       _ nodeIDBuffer: UnsafeMutablePointer<CChar>?, _ nodeIDBufferSize: Int32,
                                                       _ nodeTypeBuffer: UnsafeMutablePointer<CChar>?, _ nodeTypeBufferSize: Int32,
                                                       _ nodeTitleBuffer: UnsafeMutablePointer<CChar>?, _ nodeTitleBufferSize: Int32,
                                                       _ outputSummaryBuffer: UnsafeMutablePointer<CChar>?, _ outputSummaryBufferSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let animator = ecs.get(AnimatorComponent.self, for: entity),
          let (_, runtimeState) = graphRuntimeSnapshot(context: context, animator: animator) else { return 0 }
    let i = Int(index)
    guard i >= 0, i < runtimeState.debugTraceEntries.count else { return 0 }
    let entry = runtimeState.debugTraceEntries[i]
    _ = writeCString(entry.nodeID.uuidString, to: nodeIDBuffer, max: nodeIDBufferSize)
    _ = writeCString(entry.nodeType, to: nodeTypeBuffer, max: nodeTypeBufferSize)
    _ = writeCString(entry.nodeTitle, to: nodeTitleBuffer, max: nodeTitleBufferSize)
    _ = writeCString(entry.outputSummary, to: outputSummaryBuffer, max: outputSummaryBufferSize)
    return 1
}

@_cdecl("MCEEditorGetAnimatorGraphRuntimeDebug")
public func MCEEditorGetAnimatorGraphRuntimeDebug(_ contextPtr: UnsafeRawPointer?,
                                                  _ entityId: UnsafePointer<CChar>?,
                                                  _ currentStateBuffer: UnsafeMutablePointer<CChar>?,
                                                  _ currentStateBufferSize: Int32,
                                                  _ nextStateBuffer: UnsafeMutablePointer<CChar>?,
                                                  _ nextStateBufferSize: Int32,
                                                  _ rootMotionBoneBuffer: UnsafeMutablePointer<CChar>?,
                                                  _ rootMotionBoneBufferSize: Int32,
                                                  _ rootMotionTranslationBoneBuffer: UnsafeMutablePointer<CChar>?,
                                                  _ rootMotionTranslationBoneBufferSize: Int32,
                                                  _ rootMotionRotationBoneBuffer: UnsafeMutablePointer<CChar>?,
                                                  _ rootMotionRotationBoneBufferSize: Int32,
                                                  _ rootMotionConsumeBoneBuffer: UnsafeMutablePointer<CChar>?,
                                                  _ rootMotionConsumeBoneBufferSize: Int32,
                                                  _ speedOut: UnsafeMutablePointer<Float>?,
                                                  _ groundedOut: UnsafeMutablePointer<UInt32>?,
                                                  _ moveXOut: UnsafeMutablePointer<Float>?,
                                                  _ moveYOut: UnsafeMutablePointer<Float>?,
                                                  _ jumpTriggerOut: UnsafeMutablePointer<UInt32>?,
                                                  _ rootMotionEnabledOut: UnsafeMutablePointer<UInt32>?,
                                                  _ usesRootMotionOut: UnsafeMutablePointer<UInt32>?,
                                                  _ rootMotionDeltaMagnitudeOut: UnsafeMutablePointer<Float>?,
                                                  _ rootMotionJointIndexOut: UnsafeMutablePointer<Int32>?,
                                                  _ rootMotionTranslationJointIndexOut: UnsafeMutablePointer<Int32>?,
                                                  _ rootMotionRotationJointIndexOut: UnsafeMutablePointer<Int32>?,
                                                  _ rootMotionConsumeJointIndexOut: UnsafeMutablePointer<Int32>?,
                                                  _ rootMotionTrackConsumedOut: UnsafeMutablePointer<UInt32>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let animator = ecs.get(AnimatorComponent.self, for: entity),
          let (compiledGraph, runtimeState) = graphRuntimeSnapshot(context: context, animator: animator) else { return 0 }

    var stateNamesByID: [UUID: String] = [:]
    for node in compiledGraph.nodes {
        guard let machine = node.stateMachine else { continue }
        for state in machine.states {
            stateNamesByID[state.id] = state.name
        }
    }

    let sortedCurrentStates = runtimeState.stateMachineCurrentStateByNodeID.sorted { $0.key.uuidString < $1.key.uuidString }
    let currentStateName: String
    let nextStateName: String
    if let firstCurrent = sortedCurrentStates.first {
        currentStateName = stateNamesByID[firstCurrent.value] ?? firstCurrent.value.uuidString
        if let nextID = runtimeState.stateMachineNextStateByNodeID[firstCurrent.key] {
            nextStateName = stateNamesByID[nextID] ?? nextID.uuidString
        } else {
            nextStateName = ""
        }
    } else {
        currentStateName = ""
        nextStateName = ""
    }

    _ = writeCString(currentStateName, to: currentStateBuffer, max: currentStateBufferSize)
    _ = writeCString(nextStateName, to: nextStateBuffer, max: nextStateBufferSize)
    let rootMotionBoneName = animator.poseRuntimeState?.rootMotionBoneName ?? ""
    let rootMotionTranslationBoneName = animator.poseRuntimeState?.rootMotionTranslationBoneName ?? ""
    let rootMotionRotationBoneName = animator.poseRuntimeState?.rootMotionRotationBoneName ?? ""
    let rootMotionConsumeBoneName = animator.poseRuntimeState?.rootMotionConsumeBoneName ?? ""
    _ = writeCString(rootMotionBoneName, to: rootMotionBoneBuffer, max: rootMotionBoneBufferSize)
    _ = writeCString(rootMotionTranslationBoneName, to: rootMotionTranslationBoneBuffer, max: rootMotionTranslationBoneBufferSize)
    _ = writeCString(rootMotionRotationBoneName, to: rootMotionRotationBoneBuffer, max: rootMotionRotationBoneBufferSize)
    _ = writeCString(rootMotionConsumeBoneName, to: rootMotionConsumeBoneBuffer, max: rootMotionConsumeBoneBufferSize)

    func parameterIndex(named name: String) -> Int? {
        compiledGraph.parameters.firstIndex { $0.name == name }
    }

    let speedIndex = parameterIndex(named: "speed")
    let groundedIndex = parameterIndex(named: "grounded")
    let moveXIndex = parameterIndex(named: "moveX")
    let moveYIndex = parameterIndex(named: "moveY")
    let jumpTriggerIndex = parameterIndex(named: "jumpTrigger")

    speedOut?.pointee = speedIndex.map { runtimeState.floatParameterValues[$0] } ?? 0.0
    groundedOut?.pointee = (groundedIndex.map { runtimeState.boolParameterValues[$0] } ?? false) ? 1 : 0
    moveXOut?.pointee = moveXIndex.map { runtimeState.floatParameterValues[$0] } ?? 0.0
    moveYOut?.pointee = moveYIndex.map { runtimeState.floatParameterValues[$0] } ?? 0.0
    let jumpLatched: Bool = {
        guard let jumpTriggerIndex else { return false }
        return runtimeState.triggerParameterValues[jumpTriggerIndex]
            || runtimeState.triggerLatchedParameterIndices.contains(jumpTriggerIndex)
    }()
    jumpTriggerOut?.pointee = jumpLatched ? 1 : 0
    rootMotionEnabledOut?.pointee = animator.enableRootMotion ? 1 : 0
    usesRootMotionOut?.pointee = (animator.poseRuntimeState?.usesRootMotion ?? false) ? 1 : 0
    rootMotionDeltaMagnitudeOut?.pointee = simd_length(animator.poseRuntimeState?.rootMotionDelta.deltaPos ?? .zero)
    rootMotionJointIndexOut?.pointee = Int32(animator.poseRuntimeState?.rootMotionJointIndex ?? -1)
    rootMotionTranslationJointIndexOut?.pointee = Int32(animator.poseRuntimeState?.rootMotionTranslationJointIndex ?? -1)
    rootMotionRotationJointIndexOut?.pointee = Int32(animator.poseRuntimeState?.rootMotionRotationJointIndex ?? -1)
    rootMotionConsumeJointIndexOut?.pointee = Int32(animator.poseRuntimeState?.rootMotionConsumeJointIndex ?? -1)
    rootMotionTrackConsumedOut?.pointee = (animator.poseRuntimeState?.rootMotionTrackConsumed ?? false) ? 1 : 0
    return 1
}

@_cdecl("MCEEditorGetAnimatorRootMotionEnabled")
public func MCEEditorGetAnimatorRootMotionEnabled(_ contextPtr: UnsafeRawPointer?,
                                                   _ entityId: UnsafePointer<CChar>?,
                                                   _ enabledOut: UnsafeMutablePointer<UInt32>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let animator = ecs.get(AnimatorComponent.self, for: entity) else { return 0 }
    enabledOut?.pointee = animator.enableRootMotion ? 1 : 0
    return 1
}

@_cdecl("MCEEditorSetAnimatorRootMotionEnabled")
public func MCEEditorSetAnimatorRootMotionEnabled(_ contextPtr: UnsafeRawPointer?,
                                                   _ entityId: UnsafePointer<CChar>?,
                                                   _ enabled: UInt32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          var animator = ecs.get(AnimatorComponent.self, for: entity) else { return 0 }
    animator.enableRootMotion = enabled != 0
    ecs.add(animator, to: entity)
    if !context.bridgeServices.isPlaying {
        context.bridgeServices.notifySceneMutation()
    }
    return 1
}

@_cdecl("MCEEditorGetAnimatorRuntimeStats")
public func MCEEditorGetAnimatorRuntimeStats(_ contextPtr: UnsafeRawPointer?,
                                             _ entityId: UnsafePointer<CChar>?,
                                             _ evaluatedJointCount: UnsafeMutablePointer<Int32>?,
                                             _ hasPoseState: UnsafeMutablePointer<UInt32>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let animator = ecs.get(AnimatorComponent.self, for: entity) else { return 0 }
    let count = animator.poseRuntimeState?.globalPose.count ?? 0
    evaluatedJointCount?.pointee = Int32(count)
    hasPoseState?.pointee = animator.poseRuntimeState == nil ? 0 : 1
    return 1
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
          !context.bridgeServices.isPlaying,
          let scene = context.bridgeServices.activeScene(),
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
            _ = scene.transformAuthority.setLocalTransform(entity: entity, transform: transform, source: .editor)
        }
    }
    light.castsShadows = castsShadows != 0
    ecs.add(light, to: entity)
    if ecs.has(PrefabInstanceComponent.self, entity) {
        var overrides = ecs.get(PrefabOverrideComponent.self, for: entity) ?? PrefabOverrideComponent()
        overrides.overridden.insert(.light)
        ecs.add(overrides, to: entity)
    }
    context.bridgeServices.notifySceneMutation()
}

@_cdecl("MCEEditorGetSkyLight")
public func MCEEditorGetSkyLight(_ contextPtr: UnsafeRawPointer?,
                                 _ entityId: UnsafePointer<CChar>?, _ mode: UnsafeMutablePointer<Int32>?, _ enabled: UnsafeMutablePointer<UInt32>?,
                                 _ timeOfDay: UnsafeMutablePointer<Float>?, _ weatherType: UnsafeMutablePointer<Int32>?, _ secondaryWeatherType: UnsafeMutablePointer<Int32>?, _ weatherBlend: UnsafeMutablePointer<Float>?, _ weatherAmount: UnsafeMutablePointer<Float>?,
                                 _ atmosphereAmount: UnsafeMutablePointer<Float>?, _ cloudCoverage: UnsafeMutablePointer<Float>?, _ cloudStyle: UnsafeMutablePointer<Int32>?,
                                 _ temperature: UnsafeMutablePointer<Float>?, _ mood: UnsafeMutablePointer<Float>?,
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
                                 _ fogAmount: UnsafeMutablePointer<Float>?, _ fogHeight: UnsafeMutablePointer<Float>?, _ fogDistance: UnsafeMutablePointer<Float>?,
                                 _ autoRebuild: UnsafeMutablePointer<UInt32>?, _ needsRebuild: UnsafeMutablePointer<UInt32>?,
                                 _ hdriHandle: UnsafeMutablePointer<CChar>?, _ hdriHandleSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let sky = ecs.get(SkyLightComponent.self, for: entity) else { return 0 }
    mode?.pointee = Int32(sky.mode.rawValue)
    enabled?.pointee = sky.enabled ? 1 : 0
    timeOfDay?.pointee = sky.timeOfDay
    weatherType?.pointee = Int32(sky.weatherType.rawValue)
    secondaryWeatherType?.pointee = Int32(sky.secondaryWeatherType.rawValue)
    weatherBlend?.pointee = sky.weatherBlend
    weatherAmount?.pointee = sky.weatherAmount
    atmosphereAmount?.pointee = sky.atmosphereAmount
    cloudCoverage?.pointee = sky.cloudCoverage
    cloudStyle?.pointee = Int32(sky.cloudStyle.rawValue)
    temperature?.pointee = sky.temperature
    mood?.pointee = sky.mood
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
    fogAmount?.pointee = sky.fogAmount
    fogHeight?.pointee = sky.fogHeight
    fogDistance?.pointee = sky.fogDistance
    let iblState = ecs.get(SkyIBLStateComponent.self, for: entity) ?? SkyIBLStateComponent()
    autoRebuild?.pointee = iblState.realtimeUpdate ? 1 : 0
    needsRebuild?.pointee = iblState.needsRebuild ? 1 : 0
    let hdriString = sky.hdriHandle?.rawValue.uuidString ?? ""
    _ = writeCString(hdriString, to: hdriHandle, max: hdriHandleSize)
    return 1
}

private func clampSkyFacade(_ value: Float, min minValue: Float, max maxValue: Float) -> Float {
    Swift.max(minValue, Swift.min(maxValue, value))
}

/// Temporary compatibility bridge for edit-mode preview only.
/// Wave 1 treats authored sky state plus `EnvironmentStateComponent` as the
/// authoritative model. These legacy procedural fields are still populated here
/// only so the current shader-facing path can preview authored edits before the
/// renderer fully stops reading them.
private func applyAtmospherePreviewCompatibility(to sky: inout SkyLightComponent) {
    let timeOfDay = clampSkyFacade(sky.timeOfDay, min: 0.0, max: 24.0)
    let weatherBlend = clampSkyFacade(sky.weatherBlend, min: 0.0, max: 1.0)
    let weatherAmount = clampSkyFacade(sky.weatherAmount, min: 0.0, max: 1.0)
    let atmosphereAmount = clampSkyFacade(sky.atmosphereAmount, min: 0.0, max: 1.0)
    let cloudCoverage = clampSkyFacade(sky.cloudCoverage, min: 0.0, max: 1.0)
    let temperature = clampSkyFacade(sky.temperature, min: -1.0, max: 1.0)
    let mood = clampSkyFacade(sky.mood, min: -1.0, max: 1.0)
    let resolvedWeather = SkySystem.resolvedWeatherProfile(primary: sky.weatherType,
                                                           secondary: sky.secondaryWeatherType,
                                                           blend: weatherBlend)

    sky.timeOfDay = timeOfDay
    sky.weatherBlend = weatherBlend
    sky.weatherAmount = weatherAmount
    sky.atmosphereAmount = atmosphereAmount
    sky.cloudCoverage = cloudCoverage
    sky.temperature = temperature
    sky.mood = mood

    let normalizedTime = timeOfDay / 24.0
    sky.azimuthDegrees = fmodf(normalizedTime * 360.0 + 90.0, 360.0)
    let solarAngle = ((timeOfDay - 6.0) / 12.0) * Float.pi
    let solarHeight = sin(solarAngle)
    sky.elevationDegrees = clampSkyFacade(solarHeight * 88.0, min: -12.0, max: 88.0)
    sky.sunSizeDegrees = clampSkyFacade(0.52 + weatherAmount * 0.08, min: 0.35, max: 0.9)

    var targetTurbidity = simd_mix(2.0 + atmosphereAmount * 4.0,
                                   resolvedWeather.turbidity,
                                   weatherAmount)
    var targetCloudCoverage = simd_mix(cloudCoverage,
                                       max(cloudCoverage, resolvedWeather.cloudCoverageFloor),
                                       weatherAmount)
    var targetCloudSoftness = simd_mix(0.55, resolvedWeather.cloudSoftness, weatherAmount)
    var targetCloudScale = simd_mix(1.0, resolvedWeather.cloudScale, weatherAmount)
    var targetCloudThickness = simd_mix(0.32, resolvedWeather.cloudThickness, weatherAmount)
    var targetCloudBrightness = simd_mix(0.95, resolvedWeather.cloudBrightness, weatherAmount)
    var targetCloudSunInfluence = simd_mix(0.9, resolvedWeather.cloudSunInfluence, weatherAmount)
    var targetCloudSpeed = simd_mix(0.02, resolvedWeather.cloudSpeed, weatherAmount)
    var targetHaze = max(atmosphereAmount, resolvedWeather.hazeFloor * weatherAmount)
    var targetIntensity = simd_mix(1.0, resolvedWeather.intensity, weatherAmount)

    switch sky.cloudStyle {
    case .clear:
        targetCloudCoverage = 0.0
        targetCloudThickness = 0.22
    case .wispy:
        targetCloudSoftness = max(targetCloudSoftness, 0.68)
        targetCloudScale *= 1.5
        targetCloudThickness = min(targetCloudThickness, 0.24)
        targetCloudBrightness *= 1.05
    case .puffy:
        targetCloudSoftness = max(targetCloudSoftness, 0.55)
    case .layered:
        targetCloudSoftness = max(targetCloudSoftness, 0.72)
        targetCloudScale *= 1.25
        targetCloudThickness = max(targetCloudThickness, 0.44)
    case .overcast:
        targetCloudCoverage = max(targetCloudCoverage, 0.84)
        targetCloudSoftness = max(targetCloudSoftness, 0.82)
        targetCloudThickness = max(targetCloudThickness, 0.55)
        targetCloudSunInfluence = min(targetCloudSunInfluence, 0.4)
    case .storm:
        targetCloudCoverage = max(targetCloudCoverage, 0.88)
        targetCloudScale *= 1.35
        targetCloudThickness = max(targetCloudThickness, 0.65)
        targetCloudBrightness *= 0.88
        targetCloudSunInfluence = min(targetCloudSunInfluence, 0.28)
        targetCloudSpeed = max(targetCloudSpeed, 0.03)
    case .custom:
        break
    }

    let warmth = temperature * 0.18
    let moodShadow = clampSkyFacade(-mood, min: 0.0, max: 1.0)
    let moodLift = clampSkyFacade(mood, min: 0.0, max: 1.0)

    sky.intensity = clampSkyFacade(targetIntensity + mood * 0.16, min: 0.45, max: 1.35)
    sky.skyTint = SIMD3<Float>(1.0 + warmth * 0.45,
                               1.0 + moodLift * 0.04,
                               1.0 - warmth * 0.35 - moodShadow * 0.05)
    sky.zenithTint = SIMD3<Float>(0.24 + warmth * 0.05 - moodShadow * 0.08,
                                  0.42 + moodLift * 0.05 - moodShadow * 0.06,
                                  0.78 - warmth * 0.08 + moodLift * 0.08)
    sky.horizonTint = SIMD3<Float>(0.92 + warmth * 0.09,
                                   0.78 + warmth * 0.03 - moodShadow * 0.05,
                                   0.64 - warmth * 0.08 - moodShadow * 0.03)
    sky.gradientStrength = clampSkyFacade(0.82 + atmosphereAmount * 0.32 + moodLift * 0.12, min: 0.35, max: 1.5)
    sky.hazeDensity = clampSkyFacade(targetHaze * 1.15, min: 0.0, max: 1.25)
    sky.hazeFalloff = clampSkyFacade(1.8 + targetHaze * 1.7 + moodShadow * 0.35, min: 0.75, max: 4.5)
    sky.hazeHeight = clampSkyFacade((atmosphereAmount - 0.5) * 0.2, min: -0.3, max: 0.3)
    sky.turbidity = clampSkyFacade(targetTurbidity + atmosphereAmount * 1.2, min: 1.0, max: 10.0)
    sky.ozoneStrength = clampSkyFacade(0.42 - warmth * 0.12 + moodLift * 0.08, min: 0.0, max: 1.5)
    sky.ozoneTint = SIMD3<Float>(0.58 - warmth * 0.04,
                                 0.72 - warmth * 0.03,
                                 0.96 + moodLift * 0.05)

    let lowSunFactor = clampSkyFacade(1.0 - max(sky.elevationDegrees, 0.0) / 90.0, min: 0.0, max: 1.0)
    sky.sunHaloSize = clampSkyFacade(2.0 + atmosphereAmount * 0.9 + weatherAmount * 0.45, min: 0.5, max: 4.5)
    sky.sunHaloIntensity = clampSkyFacade(0.3 + atmosphereAmount * 0.22 + lowSunFactor * 0.25 - moodShadow * 0.08, min: 0.0, max: 1.5)
    sky.sunHaloSoftness = clampSkyFacade(1.1 + atmosphereAmount * 0.5 + weatherAmount * 0.25, min: 0.4, max: 2.4)

    sky.cloudsEnabled = targetCloudCoverage > 0.02 || sky.cloudStyle != .clear
    sky.cloudsCoverage = clampSkyFacade(targetCloudCoverage, min: 0.0, max: 1.0)
    sky.cloudsSoftness = clampSkyFacade(targetCloudSoftness, min: 0.01, max: 1.0)
    sky.cloudsScale = clampSkyFacade(targetCloudScale, min: 0.01, max: 4.0)
    sky.cloudsSpeed = clampSkyFacade(targetCloudSpeed, min: -0.25, max: 0.25)
    sky.cloudsHeight = clampSkyFacade(0.22 + moodLift * 0.04, min: 0.0, max: 1.0)
    sky.cloudsThickness = clampSkyFacade(targetCloudThickness, min: 0.08, max: 1.0)
    sky.cloudsBrightness = clampSkyFacade(targetCloudBrightness + moodLift * 0.06 - moodShadow * 0.05, min: 0.2, max: 1.6)
    sky.cloudsSunInfluence = clampSkyFacade(targetCloudSunInfluence, min: 0.0, max: 2.0)
}

/// Keeps edit-time preview state aligned with the authored atmosphere owner
/// without requiring the editor to own the runtime simulation model.
private func syncEnvironmentPreviewState(for sky: SkyLightComponent,
                                         previous: EnvironmentStateComponent?) -> EnvironmentStateComponent {
    var environment = previous ?? EnvironmentStateComponent(seededFromAuthored: sky)
    environment.currentTimeOfDay = clampSkyFacade(sky.timeOfDay, min: 0.0, max: 24.0)
    environment.currentWeatherType = sky.weatherType
    environment.targetWeatherType = sky.secondaryWeatherType
    environment.weatherTransitionProgress = clampSkyFacade(sky.weatherBlend, min: 0.0, max: 1.0)
    environment.weatherAmount = clampSkyFacade(sky.weatherAmount, min: 0.0, max: 1.0)
    if environment.timeControlMode != .scripted {
        environment.scriptedTimeOfDayOverride = nil
    }
    return environment
}

@_cdecl("MCEEditorSetSkyLight")
public func MCEEditorSetSkyLight(_ contextPtr: UnsafeRawPointer?,
                                 _ entityId: UnsafePointer<CChar>?, _ mode: Int32, _ enabled: UInt32,
                                 _ timeOfDay: Float, _ weatherType: Int32, _ secondaryWeatherType: Int32, _ weatherBlend: Float, _ weatherAmount: Float,
                                 _ atmosphereAmount: Float, _ cloudCoverage: Float, _ cloudStyle: Int32,
                                 _ temperature: Float, _ mood: Float,
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
                                 _ fogAmount: Float, _ fogHeight: Float, _ fogDistance: Float,
                                 _ autoRebuild: UInt32,
                                 _ hdriHandle: UnsafePointer<CChar>?) {
    guard let context = resolveContext(contextPtr),
          !context.bridgeServices.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return }
    let previous = ecs.get(SkyLightComponent.self, for: entity) ?? SkyLightComponent()
    var sky = previous
    sky.mode = SkyMode(rawValue: UInt32(max(0, mode))) ?? .hdri
    sky.enabled = enabled != 0
    sky.timeOfDay = clampSkyFacade(timeOfDay, min: 0.0, max: 24.0)
    sky.weatherType = AtmosphereWeatherType(rawValue: UInt32(max(0, weatherType))) ?? .clear
    sky.secondaryWeatherType = AtmosphereWeatherType(rawValue: UInt32(max(0, secondaryWeatherType))) ?? .clear
    sky.weatherBlend = clampSkyFacade(weatherBlend, min: 0.0, max: 1.0)
    sky.weatherAmount = clampSkyFacade(weatherAmount, min: 0.0, max: 1.0)
    sky.atmosphereAmount = clampSkyFacade(atmosphereAmount, min: 0.0, max: 1.0)
    sky.cloudCoverage = clampSkyFacade(cloudCoverage, min: 0.0, max: 1.0)
    sky.cloudStyle = AtmosphereCloudStyle(rawValue: UInt32(max(0, cloudStyle))) ?? .puffy
    sky.temperature = clampSkyFacade(temperature, min: -1.0, max: 1.0)
    sky.mood = clampSkyFacade(mood, min: -1.0, max: 1.0)
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
    sky.fogAmount = max(0.0, min(fogAmount, 1.0))
    sky.fogHeight = fogHeight
    sky.fogDistance = max(0.0, fogDistance)
    let preserveLegacyProceduralOverrides = sky.weatherType == .custom
        && sky.secondaryWeatherType == .custom
        && sky.cloudStyle == .custom
    if sky.mode == .procedural && !preserveLegacyProceduralOverrides {
        applyAtmospherePreviewCompatibility(to: &sky)
    }
    if let hdriHandle {
        let hdriString = String(cString: hdriHandle)
        sky.hdriHandle = handleFromString(hdriString)
    } else {
        sky.hdriHandle = nil
    }
    ecs.add(sky, to: entity)
    let previousEnvironment = ecs.get(EnvironmentStateComponent.self, for: entity)
    let updatedEnvironment = syncEnvironmentPreviewState(for: sky, previous: previousEnvironment)
    ecs.add(updatedEnvironment, to: entity)
    var iblState = ecs.get(SkyIBLStateComponent.self, for: entity) ?? SkyIBLStateComponent()
    iblState.realtimeUpdate = autoRebuild != 0
    if SkySystem.requiresIBLRebuild(previous: previous, next: sky) {
        iblState.needsRebuild = true
        iblState.rebuildRequested = false
    }
    ecs.add(iblState, to: entity)
    if iblState.needsRebuild {
        context.engineContext.log.logInfo("Sky regenerate requested: \(entity.id.uuidString)", category: .scene)
    }
    context.bridgeServices.notifySceneMutation()
}

@_cdecl("MCEEditorRequestSkyRebuild")
public func MCEEditorRequestSkyRebuild(_ contextPtr: UnsafeRawPointer?,
                                       _ entityId: UnsafePointer<CChar>?) {
    guard let context = resolveContext(contextPtr),
          !context.bridgeServices.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return }
    var iblState = ecs.get(SkyIBLStateComponent.self, for: entity) ?? SkyIBLStateComponent()
    iblState.needsRebuild = true
    iblState.rebuildRequested = true
    ecs.add(iblState, to: entity)
    context.bridgeServices.notifySceneMutation()
}

@_cdecl("MCEEditorRequestActiveSkyRebuild")
public func MCEEditorRequestActiveSkyRebuild(_ contextPtr: UnsafeRawPointer?) {
    guard let context = resolveContext(contextPtr),
          !context.bridgeServices.isPlaying,
          let ecs = editorECS(context),
          let (entity, _) = ecs.activeSkyLight() else { return }
    var updated = ecs.get(SkyIBLStateComponent.self, for: entity) ?? SkyIBLStateComponent()
    updated.needsRebuild = true
    ecs.add(updated, to: entity)
    context.bridgeServices.notifySceneMutation()
}

private func ensureEnvironmentRuntimeState(_ ecs: SceneECS, entity: Entity, environment: EnvironmentComponent) -> EnvironmentRuntimeStateComponent {
    if let runtime = ecs.get(EnvironmentRuntimeStateComponent.self, for: entity) {
        return runtime
    }
    let runtime = EnvironmentRuntimeStateComponent.default(from: environment)
    ecs.add(runtime, to: entity)
    return runtime
}

private func markEnvironmentIBLNeedsRebuild(_ ecs: SceneECS, entity: Entity, requested: Bool = false) {
    var state = ecs.get(EnvironmentIBLStateComponent.self, for: entity) ?? EnvironmentIBLStateComponent.defaultNeedsRebuild
    state.dirty = true
    state.needsRebuild = true
    state.rebuildRequested = state.rebuildRequested || requested
    state.lastFailureMessage = nil
    ecs.add(state, to: entity)
}

private func markEnvironmentIBLDirty(_ ecs: SceneECS, entity: Entity) {
    var state = ecs.get(EnvironmentIBLStateComponent.self, for: entity) ?? EnvironmentIBLStateComponent.defaultNeedsRebuild
    state.dirty = true
    state.lastFailureMessage = nil
    ecs.add(state, to: entity)
}

@_cdecl("MCEEditorGetEnvironmentLookBridge")
public func MCEEditorGetEnvironmentLookBridge(_ contextPtr: UnsafeRawPointer?,
                                              _ entityId: UnsafePointer<CChar>?,
                                              _ outValue: UnsafeMutableRawPointer?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let environment = ecs.get(EnvironmentComponent.self, for: entity),
          let outValue else { return 0 }
    let output = outValue.assumingMemoryBound(to: MCEEnvironmentLookBridge.self)
    output.pointee = MCEEnvironmentLookBridge(
        preset: Int32(environment.look.preset.rawValue),
        mood: environment.look.mood,
        warmth: environment.look.warmth,
        cinematicAmount: environment.look.cinematicAmount
    )
    return 1
}

@_cdecl("MCEEditorSetEnvironmentLookBridge")
public func MCEEditorSetEnvironmentLookBridge(_ contextPtr: UnsafeRawPointer?,
                                              _ entityId: UnsafePointer<CChar>?,
                                              _ value: UnsafeRawPointer?) {
    guard let context = resolveContext(contextPtr),
          !context.bridgeServices.isPlaying,
          !context.bridgeServices.isSimulating,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let value else { return }
    let input = value.assumingMemoryBound(to: MCEEnvironmentLookBridge.self).pointee
    var environment = ecs.get(EnvironmentComponent.self, for: entity) ?? EnvironmentComponent()
    environment.look = EnvironmentLookConfig(
        preset: EnvironmentLookPreset(rawValue: UInt32(max(0, input.preset))) ?? .custom,
        mood: clampSkyFacade(input.mood, min: -1.0, max: 1.0),
        warmth: clampSkyFacade(input.warmth, min: -1.0, max: 1.0),
        cinematicAmount: clampSkyFacade(input.cinematicAmount, min: 0.0, max: 1.0)
    )
    ecs.add(environment, to: entity)
    _ = ensureEnvironmentRuntimeState(ecs, entity: entity, environment: environment)
    if environment.source.mode == .procedural {
        markEnvironmentIBLDirty(ecs, entity: entity)
    }
    context.bridgeServices.notifySceneMutation()
}

@_cdecl("MCEEditorGetEnvironmentSourceBridge")
public func MCEEditorGetEnvironmentSourceBridge(_ contextPtr: UnsafeRawPointer?,
                                                _ entityId: UnsafePointer<CChar>?,
                                                _ outValue: UnsafeMutableRawPointer?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let environment = ecs.get(EnvironmentComponent.self, for: entity),
          let outValue else { return 0 }
    let parts = environment.source.hdriTextureHandle.map { uuidParts($0.rawValue) } ?? (0, 0)
    let output = outValue.assumingMemoryBound(to: MCEEnvironmentSourceBridge.self)
    output.pointee = MCEEnvironmentSourceBridge(
        enabled: environment.enabled ? 1 : 0,
        mode: Int32(environment.source.mode.rawValue),
        hasHdriHandle: environment.source.hdriTextureHandle == nil ? 0 : 1,
        hdriHandleHigh: parts.high,
        hdriHandleLow: parts.low
    )
    return 1
}

@_cdecl("MCEEditorSetEnvironmentSourceBridge")
public func MCEEditorSetEnvironmentSourceBridge(_ contextPtr: UnsafeRawPointer?,
                                                _ entityId: UnsafePointer<CChar>?,
                                                _ value: UnsafeRawPointer?) {
    guard let context = resolveContext(contextPtr),
          !context.bridgeServices.isPlaying,
          !context.bridgeServices.isSimulating,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let value else { return }
    let input = value.assumingMemoryBound(to: MCEEnvironmentSourceBridge.self).pointee
    var environment = ecs.get(EnvironmentComponent.self, for: entity) ?? EnvironmentComponent()
    environment.look.preset = .custom
    environment.enabled = input.enabled != 0
    environment.source.mode = EnvironmentSourceMode(rawValue: UInt32(max(0, input.mode))) ?? .hdri
    environment.source.hdriTextureHandle = input.hasHdriHandle == 0
        ? nil
        : AssetHandle(rawValue: uuidFromParts(high: input.hdriHandleHigh, low: input.hdriHandleLow))
    ecs.add(environment, to: entity)
    _ = ensureEnvironmentRuntimeState(ecs, entity: entity, environment: environment)
    markEnvironmentIBLDirty(ecs, entity: entity)
    context.bridgeServices.notifySceneMutation()
}

@_cdecl("MCEEditorGetEnvironmentTimeBridge")
public func MCEEditorGetEnvironmentTimeBridge(_ contextPtr: UnsafeRawPointer?,
                                              _ entityId: UnsafePointer<CChar>?,
                                              _ outValue: UnsafeMutableRawPointer?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let environment = ecs.get(EnvironmentComponent.self, for: entity),
          let outValue else { return 0 }
    let runtime = ensureEnvironmentRuntimeState(ecs, entity: entity, environment: environment)
    let output = outValue.assumingMemoryBound(to: MCEEnvironmentTimeBridge.self)
    output.pointee = MCEEnvironmentTimeBridge(
        defaultTimeOfDay: environment.celestial.defaultTimeOfDay,
        previewTimeOfDay: runtime.currentTimeOfDay,
        timeControlMode: Int32(runtime.timeControlMode.rawValue),
        dayLengthSeconds: runtime.dayLengthSeconds,
        timeScale: runtime.timeScale
    )
    return 1
}

@_cdecl("MCEEditorSetEnvironmentTimeBridge")
public func MCEEditorSetEnvironmentTimeBridge(_ contextPtr: UnsafeRawPointer?,
                                              _ entityId: UnsafePointer<CChar>?,
                                              _ value: UnsafeRawPointer?) {
    guard let context = resolveContext(contextPtr),
          !context.bridgeServices.isPlaying,
          !context.bridgeServices.isSimulating,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let value else { return }
    let input = value.assumingMemoryBound(to: MCEEnvironmentTimeBridge.self).pointee
    var environment = ecs.get(EnvironmentComponent.self, for: entity) ?? EnvironmentComponent()
    environment.look.preset = .custom
    environment.celestial.defaultTimeOfDay = clampSkyFacade(input.defaultTimeOfDay, min: 0.0, max: 24.0)
    environment.celestial.timeControlMode = EnvironmentTimeControlMode(rawValue: UInt32(max(0, input.timeControlMode))) ?? .fixed
    environment.celestial.dayLengthSeconds = max(1.0, input.dayLengthSeconds)
    environment.celestial.timeScale = input.timeScale.isFinite ? max(input.timeScale, 0) : 1.0
    ecs.add(environment, to: entity)

    var runtime = ensureEnvironmentRuntimeState(ecs, entity: entity, environment: environment)
    runtime.currentTimeOfDay = clampSkyFacade(input.previewTimeOfDay, min: 0.0, max: 24.0)
    runtime.timeControlMode = EnvironmentTimeControlMode(rawValue: UInt32(max(0, input.timeControlMode))) ?? .fixed
    runtime.dayLengthSeconds = max(1.0, input.dayLengthSeconds)
    runtime.timeScale = input.timeScale.isFinite ? input.timeScale : 1.0
    if runtime.timeControlMode != .scripted {
        runtime.scriptedTimeOfDayOverride = nil
    }
    ecs.add(runtime, to: entity)
    if environment.source.mode == .procedural {
        markEnvironmentIBLDirty(ecs, entity: entity)
    }
    context.bridgeServices.notifySceneMutation()
}

@_cdecl("MCEEditorGetEnvironmentAtmosphereBridge")
public func MCEEditorGetEnvironmentAtmosphereBridge(_ contextPtr: UnsafeRawPointer?,
                                                    _ entityId: UnsafePointer<CChar>?,
                                                    _ outValue: UnsafeMutableRawPointer?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let environment = ecs.get(EnvironmentComponent.self, for: entity),
          let outValue else { return 0 }
    let output = outValue.assumingMemoryBound(to: MCEEnvironmentAtmosphereBridge.self)
    output.pointee = MCEEnvironmentAtmosphereBridge(
        amount: environment.atmosphere.amount,
        haze: environment.atmosphere.haze,
        density: environment.atmosphere.density,
        temperature: environment.atmosphere.temperature,
        mood: environment.atmosphere.mood,
        sourceEV: environment.atmosphere.sourceEV
    )
    return 1
}

@_cdecl("MCEEditorSetEnvironmentAtmosphereBridge")
public func MCEEditorSetEnvironmentAtmosphereBridge(_ contextPtr: UnsafeRawPointer?,
                                                    _ entityId: UnsafePointer<CChar>?,
                                                    _ value: UnsafeRawPointer?) {
    guard let context = resolveContext(contextPtr),
          !context.bridgeServices.isPlaying,
          !context.bridgeServices.isSimulating,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let value else { return }
    let input = value.assumingMemoryBound(to: MCEEnvironmentAtmosphereBridge.self).pointee
    var environment = ecs.get(EnvironmentComponent.self, for: entity) ?? EnvironmentComponent()
    environment.look.preset = .custom
    environment.atmosphere.amount = clampSkyFacade(input.amount, min: 0.0, max: 1.0)
    environment.atmosphere.haze = clampSkyFacade(input.haze, min: 0.0, max: 1.0)
    environment.atmosphere.density = max(0.0, input.density)
    environment.atmosphere.temperature = clampSkyFacade(input.temperature, min: -1.0, max: 1.0)
    environment.atmosphere.mood = clampSkyFacade(input.mood, min: -1.0, max: 1.0)
    environment.atmosphere.sourceEV = clampSkyFacade(input.sourceEV, min: -2.0, max: 1.0)
    ecs.add(environment, to: entity)
    _ = ensureEnvironmentRuntimeState(ecs, entity: entity, environment: environment)
    if environment.source.mode == .procedural {
        markEnvironmentIBLDirty(ecs, entity: entity)
    }
    context.bridgeServices.notifySceneMutation()
}

@_cdecl("MCEEditorGetEnvironmentCelestialBridge")
public func MCEEditorGetEnvironmentCelestialBridge(_ contextPtr: UnsafeRawPointer?,
                                                   _ entityId: UnsafePointer<CChar>?,
                                                   _ outValue: UnsafeMutableRawPointer?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let environment = ecs.get(EnvironmentComponent.self, for: entity),
          let outValue else { return 0 }
    let output = outValue.assumingMemoryBound(to: MCEEnvironmentCelestialBridge.self)
    output.pointee = MCEEnvironmentCelestialBridge(
        moonIntensity: environment.celestial.moonIntensity,
        moonSizeDegrees: environment.celestial.moonSizeDegrees,
        starIntensity: environment.celestial.starIntensity,
        starRichness: environment.celestial.starRichness,
        milkyWayIntensity: environment.celestial.milkyWayIntensity,
        milkyWayChroma: environment.celestial.milkyWayChroma,
        milkyWayRotation: environment.celestial.milkyWayRotation,
        nightBrightness: environment.celestial.nightBrightness
    )
    return 1
}

@_cdecl("MCEEditorSetEnvironmentCelestialBridge")
public func MCEEditorSetEnvironmentCelestialBridge(_ contextPtr: UnsafeRawPointer?,
                                                   _ entityId: UnsafePointer<CChar>?,
                                                   _ value: UnsafeRawPointer?) {
    guard let context = resolveContext(contextPtr),
          !context.bridgeServices.isPlaying,
          !context.bridgeServices.isSimulating,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let value else { return }
    let input = value.assumingMemoryBound(to: MCEEnvironmentCelestialBridge.self).pointee
    var environment = ecs.get(EnvironmentComponent.self, for: entity) ?? EnvironmentComponent()
    environment.look.preset = .custom
    environment.celestial.moonIntensity = max(0.0, input.moonIntensity)
    environment.celestial.moonSizeDegrees = max(0.01, input.moonSizeDegrees)
    environment.celestial.starIntensity = max(0.0, input.starIntensity)
    environment.celestial.starRichness = clampSkyFacade(input.starRichness, min: 0.0, max: 3.0)
    environment.celestial.milkyWayIntensity = clampSkyFacade(input.milkyWayIntensity, min: 0.0, max: 3.0)
    environment.celestial.milkyWayChroma = clampSkyFacade(input.milkyWayChroma, min: 0.0, max: 3.0)
    environment.celestial.milkyWayRotation = input.milkyWayRotation.isFinite ? input.milkyWayRotation : 0.0
    environment.celestial.nightBrightness = clampSkyFacade(input.nightBrightness, min: 0.0, max: 3.0)
    ecs.add(environment, to: entity)
    _ = ensureEnvironmentRuntimeState(ecs, entity: entity, environment: environment)
    if environment.source.mode == .procedural {
        markEnvironmentIBLDirty(ecs, entity: entity)
    }
    context.bridgeServices.notifySceneMutation()
}

@_cdecl("MCEEditorGetEnvironmentWeatherCloudBridge")
public func MCEEditorGetEnvironmentWeatherCloudBridge(_ contextPtr: UnsafeRawPointer?,
                                                      _ entityId: UnsafePointer<CChar>?,
                                                      _ outValue: UnsafeMutableRawPointer?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let environment = ecs.get(EnvironmentComponent.self, for: entity),
          let outValue else { return 0 }
    let output = outValue.assumingMemoryBound(to: MCEEnvironmentWeatherCloudBridge.self)
    output.pointee = MCEEnvironmentWeatherCloudBridge(
        weatherPrimary: Int32(environment.weather.primaryType.rawValue),
        weatherSecondary: Int32(environment.weather.secondaryType.rawValue),
        weatherBlend: environment.weather.blend,
        weatherAmount: environment.weather.amount,
        cloudCoverage: environment.clouds.coverage,
        cloudStyle: Int32(environment.clouds.style.rawValue),
        cloudRenderMode: Int32(environment.clouds.renderMode.rawValue)
    )
    return 1
}

@_cdecl("MCEEditorSetEnvironmentWeatherCloudBridge")
public func MCEEditorSetEnvironmentWeatherCloudBridge(_ contextPtr: UnsafeRawPointer?,
                                                      _ entityId: UnsafePointer<CChar>?,
                                                      _ value: UnsafeRawPointer?) {
    guard let context = resolveContext(contextPtr),
          !context.bridgeServices.isPlaying,
          !context.bridgeServices.isSimulating,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let value else { return }
    let input = value.assumingMemoryBound(to: MCEEnvironmentWeatherCloudBridge.self).pointee
    var environment = ecs.get(EnvironmentComponent.self, for: entity) ?? EnvironmentComponent()
    environment.look.preset = .custom
    environment.weather.primaryType = EnvironmentWeatherType(rawValue: UInt32(max(0, input.weatherPrimary))) ?? .clear
    environment.weather.secondaryType = EnvironmentWeatherType(rawValue: UInt32(max(0, input.weatherSecondary))) ?? .clear
    environment.weather.blend = clampSkyFacade(input.weatherBlend, min: 0.0, max: 1.0)
    environment.weather.amount = clampSkyFacade(input.weatherAmount, min: 0.0, max: 1.0)
    environment.clouds.coverage = clampSkyFacade(input.cloudCoverage, min: 0.0, max: 1.0)
    environment.clouds.style = EnvironmentCloudStyle(rawValue: UInt32(max(0, input.cloudStyle))) ?? .puffy
    environment.clouds.renderMode = EnvironmentCloudRenderMode(rawValue: UInt32(max(0, input.cloudRenderMode))) ?? .both
    ecs.add(environment, to: entity)

    var runtime = ensureEnvironmentRuntimeState(ecs, entity: entity, environment: environment)
    runtime.currentWeatherType = environment.weather.primaryType
    runtime.targetWeatherType = environment.weather.secondaryType
    runtime.weatherBlend = environment.weather.blend
    runtime.weatherAmount = environment.weather.amount
    ecs.add(runtime, to: entity)
    if environment.source.mode == .procedural {
        markEnvironmentIBLDirty(ecs, entity: entity)
    }
    context.bridgeServices.notifySceneMutation()
}

@_cdecl("MCEEditorGetEnvironmentFogBridge")
public func MCEEditorGetEnvironmentFogBridge(_ contextPtr: UnsafeRawPointer?,
                                             _ entityId: UnsafePointer<CChar>?,
                                             _ outValue: UnsafeMutableRawPointer?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let environment = ecs.get(EnvironmentComponent.self, for: entity),
          let outValue else { return 0 }
    let output = outValue.assumingMemoryBound(to: MCEEnvironmentFogBridge.self)
    output.pointee = MCEEnvironmentFogBridge(
        amount: environment.fog.amount,
        height: environment.fog.height,
        distance: environment.fog.distance
    )
    return 1
}

@_cdecl("MCEEditorSetEnvironmentFogBridge")
public func MCEEditorSetEnvironmentFogBridge(_ contextPtr: UnsafeRawPointer?,
                                             _ entityId: UnsafePointer<CChar>?,
                                             _ value: UnsafeRawPointer?) {
    guard let context = resolveContext(contextPtr),
          !context.bridgeServices.isPlaying,
          !context.bridgeServices.isSimulating,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let value else { return }
    let input = value.assumingMemoryBound(to: MCEEnvironmentFogBridge.self).pointee
    var environment = ecs.get(EnvironmentComponent.self, for: entity) ?? EnvironmentComponent()
    environment.look.preset = .custom
    environment.fog.amount = clampSkyFacade(input.amount, min: 0.0, max: 1.0)
    environment.fog.height = input.height
    environment.fog.distance = max(0.0, input.distance)
    ecs.add(environment, to: entity)
    _ = ensureEnvironmentRuntimeState(ecs, entity: entity, environment: environment)
    context.bridgeServices.notifySceneMutation()
}

@_cdecl("MCEEditorGetEnvironmentIBLStatusBridge")
public func MCEEditorGetEnvironmentIBLStatusBridge(_ contextPtr: UnsafeRawPointer?,
                                                   _ entityId: UnsafePointer<CChar>?,
                                                   _ outValue: UnsafeMutableRawPointer?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let environment = ecs.get(EnvironmentComponent.self, for: entity),
          let outValue else { return 0 }
    let state = ecs.get(EnvironmentIBLStateComponent.self, for: entity) ?? EnvironmentIBLStateComponent.defaultNeedsRebuild
    let renderState = ecs.get(EnvironmentFrameStateComponent.self, for: entity)?.renderState
        ?? EnvironmentRenderStateBuilder.build(
            environment: environment,
            runtime: ecs.get(EnvironmentRuntimeStateComponent.self, for: entity)
        )
    let freshness = EnvironmentIBLRebuildLifecycle.freshness(state: state, current: renderState)
    let phaseCode: Int32
    switch state.phase {
    case .dirty: phaseCode = 0
    case .rebuildingInteractive: phaseCode = 1
    case .interactiveReady: phaseCode = 2
    case .rebuildingFinal: phaseCode = 3
    case .finalReady: phaseCode = 4
    }
    let output = outValue.assumingMemoryBound(to: MCEEnvironmentIBLBridge.self)
    output.pointee = MCEEnvironmentIBLBridge(
        realtimeUpdate: environment.ibl.realtimeUpdate ? 1 : 0,
        autoRebuildOnChange: environment.ibl.autoRebuildOnChange ? 1 : 0,
        needsRebuild: state.needsRebuild ? 1 : 0,
        dirty: state.dirty ? 1 : 0,
        isRebuilding: state.isRebuilding ? 1 : 0,
        currentRebuildQuality: environmentIBLQualityCode(state.currentRebuildQuality),
        lastBuiltQuality: environmentIBLQualityCode(state.lastBuiltQuality),
        hasFailure: (state.lastFailureMessage?.isEmpty == false) ? 1 : 0,
        phase: phaseCode,
        currentTimeOfDay: renderState.finalTimeOfDay,
        representedTimeOfDay: freshness.representedTimeOfDay ?? -1,
        angularLagDegrees: freshness.angularLagDegrees ?? -1,
        lastBuildDuration: Float(freshness.lastBuildDuration ?? -1),
        solarElevationDegrees: renderState.solarElevationDegrees,
        sunDirectionX: renderState.sunDirection.x,
        sunDirectionY: renderState.sunDirection.y,
        sunDirectionZ: renderState.sunDirection.z,
        sunIlluminance: renderState.sunIntensity
    )
    return 1
}

@_cdecl("MCEEditorSetEnvironmentIBLConfigBridge")
public func MCEEditorSetEnvironmentIBLConfigBridge(_ contextPtr: UnsafeRawPointer?,
                                                  _ entityId: UnsafePointer<CChar>?,
                                                  _ value: UnsafeRawPointer?) {
    guard let context = resolveContext(contextPtr),
          !context.bridgeServices.isPlaying,
          !context.bridgeServices.isSimulating,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let value else { return }
    let input = value.assumingMemoryBound(to: MCEEnvironmentIBLBridge.self).pointee
    var environment = ecs.get(EnvironmentComponent.self, for: entity) ?? EnvironmentComponent()
    environment.ibl.realtimeUpdate = input.realtimeUpdate != 0
    environment.ibl.autoRebuildOnChange = input.autoRebuildOnChange != 0
    ecs.add(environment, to: entity)
    _ = ensureEnvironmentRuntimeState(ecs, entity: entity, environment: environment)
    if ecs.get(EnvironmentIBLStateComponent.self, for: entity) == nil {
        ecs.add(EnvironmentIBLStateComponent.defaultNeedsRebuild, to: entity)
    }
    context.bridgeServices.notifySceneMutation()
}

@_cdecl("MCEEditorGetEnvironmentLook")
public func MCEEditorGetEnvironmentLook(_ contextPtr: UnsafeRawPointer?,
                                        _ entityId: UnsafePointer<CChar>?,
                                        _ preset: UnsafeMutablePointer<Int32>?,
                                        _ mood: UnsafeMutablePointer<Float>?,
                                        _ warmth: UnsafeMutablePointer<Float>?,
                                        _ cinematicAmount: UnsafeMutablePointer<Float>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let environment = ecs.get(EnvironmentComponent.self, for: entity) else { return 0 }
    preset?.pointee = Int32(environment.look.preset.rawValue)
    mood?.pointee = environment.look.mood
    warmth?.pointee = environment.look.warmth
    cinematicAmount?.pointee = environment.look.cinematicAmount
    return 1
}

@_cdecl("MCEEditorApplyEnvironmentPreset")
public func MCEEditorApplyEnvironmentPreset(_ contextPtr: UnsafeRawPointer?,
                                            _ entityId: UnsafePointer<CChar>?,
                                            _ presetRawValue: Int32) {
    guard let context = resolveContext(contextPtr),
          !context.bridgeServices.isPlaying,
          !context.bridgeServices.isSimulating,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return }
    let preset = EnvironmentLookPreset(rawValue: UInt32(max(0, presetRawValue))) ?? .custom
    var environment = ecs.get(EnvironmentComponent.self, for: entity) ?? EnvironmentComponent()
    if preset == .custom {
        environment.look.preset = .custom
        ecs.add(environment, to: entity)
        _ = ensureEnvironmentRuntimeState(ecs, entity: entity, environment: environment)
        context.bridgeServices.notifySceneMutation()
        return
    }
    preset.apply(to: &environment)
    ecs.add(environment, to: entity)
    ecs.add(EnvironmentRuntimeStateComponent.default(from: environment), to: entity)
    if environment.source.mode == .procedural {
        markEnvironmentIBLNeedsRebuild(ecs, entity: entity)
    } else {
        markEnvironmentIBLDirty(ecs, entity: entity)
    }
    context.bridgeServices.notifySceneMutation()
}

@_cdecl("MCEEditorGetEnvironmentSource")
public func MCEEditorGetEnvironmentSource(_ contextPtr: UnsafeRawPointer?,
                                          _ entityId: UnsafePointer<CChar>?,
                                          _ enabled: UnsafeMutablePointer<UInt32>?,
                                          _ mode: UnsafeMutablePointer<Int32>?,
                                          _ hdriHandle: UnsafeMutablePointer<CChar>?,
                                          _ hdriHandleSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let environment = ecs.get(EnvironmentComponent.self, for: entity) else { return 0 }
    enabled?.pointee = environment.enabled ? 1 : 0
    mode?.pointee = Int32(environment.source.mode.rawValue)
    _ = writeCString(environment.source.hdriTextureHandle?.rawValue.uuidString ?? "", to: hdriHandle, max: hdriHandleSize)
    return 1
}

@_cdecl("MCEEditorSetEnvironmentSource")
public func MCEEditorSetEnvironmentSource(_ contextPtr: UnsafeRawPointer?,
                                          _ entityId: UnsafePointer<CChar>?,
                                          _ enabled: UInt32,
                                          _ mode: Int32,
                                          _ hdriHandle: UnsafePointer<CChar>?) {
    guard let context = resolveContext(contextPtr),
          !context.bridgeServices.isPlaying,
          !context.bridgeServices.isSimulating,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return }
    var environment = ecs.get(EnvironmentComponent.self, for: entity) ?? EnvironmentComponent()
    environment.look.preset = .custom
    environment.enabled = enabled != 0
    environment.source.mode = EnvironmentSourceMode(rawValue: UInt32(max(0, mode))) ?? .hdri
    if let hdriHandle {
        environment.source.hdriTextureHandle = handleFromString(String(cString: hdriHandle))
    } else {
        environment.source.hdriTextureHandle = nil
    }
    ecs.add(environment, to: entity)
    _ = ensureEnvironmentRuntimeState(ecs, entity: entity, environment: environment)
    markEnvironmentIBLDirty(ecs, entity: entity)
    context.bridgeServices.notifySceneMutation()
}

@_cdecl("MCEEditorGetEnvironmentCelestial")
public func MCEEditorGetEnvironmentCelestial(_ contextPtr: UnsafeRawPointer?,
                                             _ entityId: UnsafePointer<CChar>?,
                                             _ defaultTimeOfDay: UnsafeMutablePointer<Float>?,
                                             _ previewTimeOfDay: UnsafeMutablePointer<Float>?,
                                             _ moonIntensity: UnsafeMutablePointer<Float>?,
                                             _ moonSizeDegrees: UnsafeMutablePointer<Float>?,
                                             _ starIntensity: UnsafeMutablePointer<Float>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let environment = ecs.get(EnvironmentComponent.self, for: entity) else { return 0 }
    let runtime = ensureEnvironmentRuntimeState(ecs, entity: entity, environment: environment)
    defaultTimeOfDay?.pointee = environment.celestial.defaultTimeOfDay
    previewTimeOfDay?.pointee = runtime.currentTimeOfDay
    moonIntensity?.pointee = environment.celestial.moonIntensity
    moonSizeDegrees?.pointee = environment.celestial.moonSizeDegrees
    starIntensity?.pointee = environment.celestial.starIntensity
    return 1
}

@_cdecl("MCEEditorSetEnvironmentCelestial")
public func MCEEditorSetEnvironmentCelestial(_ contextPtr: UnsafeRawPointer?,
                                             _ entityId: UnsafePointer<CChar>?,
                                             _ defaultTimeOfDay: Float,
                                             _ moonIntensity: Float,
                                             _ moonSizeDegrees: Float,
                                             _ starIntensity: Float) {
    guard let context = resolveContext(contextPtr),
          !context.bridgeServices.isPlaying,
          !context.bridgeServices.isSimulating,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return }
    var environment = ecs.get(EnvironmentComponent.self, for: entity) ?? EnvironmentComponent()
    environment.look.preset = .custom
    environment.celestial.defaultTimeOfDay = clampSkyFacade(defaultTimeOfDay, min: 0.0, max: 24.0)
    environment.celestial.moonIntensity = max(0.0, moonIntensity)
    environment.celestial.moonSizeDegrees = max(0.01, moonSizeDegrees)
    environment.celestial.starIntensity = max(0.0, starIntensity)
    ecs.add(environment, to: entity)
    _ = ensureEnvironmentRuntimeState(ecs, entity: entity, environment: environment)
    if environment.source.mode == .procedural {
        markEnvironmentIBLDirty(ecs, entity: entity)
    }
    context.bridgeServices.notifySceneMutation()
}

@_cdecl("MCEEditorSetEnvironmentPreviewTime")
public func MCEEditorSetEnvironmentPreviewTime(_ contextPtr: UnsafeRawPointer?,
                                               _ entityId: UnsafePointer<CChar>?,
                                               _ previewTimeOfDay: Float) {
    guard let context = resolveContext(contextPtr),
          !context.bridgeServices.isPlaying,
          !context.bridgeServices.isSimulating,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let environment = ecs.get(EnvironmentComponent.self, for: entity) else { return }
    var runtime = ensureEnvironmentRuntimeState(ecs, entity: entity, environment: environment)
    runtime.currentTimeOfDay = clampSkyFacade(previewTimeOfDay, min: 0.0, max: 24.0)
    if runtime.timeControlMode != .scripted {
        runtime.scriptedTimeOfDayOverride = nil
    }
    ecs.add(runtime, to: entity)
    if environment.source.mode == .procedural, environment.ibl.realtimeUpdate {
        markEnvironmentIBLDirty(ecs, entity: entity)
    }
    context.bridgeServices.notifySceneMutation()
}

@_cdecl("MCEEditorGetEnvironmentWeather")
public func MCEEditorGetEnvironmentWeather(_ contextPtr: UnsafeRawPointer?,
                                           _ entityId: UnsafePointer<CChar>?,
                                           _ primaryType: UnsafeMutablePointer<Int32>?,
                                           _ secondaryType: UnsafeMutablePointer<Int32>?,
                                           _ blend: UnsafeMutablePointer<Float>?,
                                           _ amount: UnsafeMutablePointer<Float>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let environment = ecs.get(EnvironmentComponent.self, for: entity) else { return 0 }
    primaryType?.pointee = Int32(environment.weather.primaryType.rawValue)
    secondaryType?.pointee = Int32(environment.weather.secondaryType.rawValue)
    blend?.pointee = environment.weather.blend
    amount?.pointee = environment.weather.amount
    return 1
}

@_cdecl("MCEEditorSetEnvironmentWeather")
public func MCEEditorSetEnvironmentWeather(_ contextPtr: UnsafeRawPointer?,
                                           _ entityId: UnsafePointer<CChar>?,
                                           _ primaryType: Int32,
                                           _ secondaryType: Int32,
                                           _ blend: Float,
                                           _ amount: Float) {
    guard let context = resolveContext(contextPtr),
          !context.bridgeServices.isPlaying,
          !context.bridgeServices.isSimulating,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return }
    var environment = ecs.get(EnvironmentComponent.self, for: entity) ?? EnvironmentComponent()
    environment.look.preset = .custom
    environment.weather.primaryType = EnvironmentWeatherType(rawValue: UInt32(max(0, primaryType))) ?? .clear
    environment.weather.secondaryType = EnvironmentWeatherType(rawValue: UInt32(max(0, secondaryType))) ?? .clear
    environment.weather.blend = clampSkyFacade(blend, min: 0.0, max: 1.0)
    environment.weather.amount = clampSkyFacade(amount, min: 0.0, max: 1.0)
    ecs.add(environment, to: entity)
    var runtime = ensureEnvironmentRuntimeState(ecs, entity: entity, environment: environment)
    runtime.currentWeatherType = environment.weather.primaryType
    runtime.targetWeatherType = environment.weather.secondaryType
    runtime.weatherBlend = environment.weather.blend
    runtime.weatherAmount = environment.weather.amount
    ecs.add(runtime, to: entity)
    if environment.source.mode == .procedural {
        markEnvironmentIBLDirty(ecs, entity: entity)
    }
    context.bridgeServices.notifySceneMutation()
}

@_cdecl("MCEEditorGetEnvironmentAtmosphere")
public func MCEEditorGetEnvironmentAtmosphere(_ contextPtr: UnsafeRawPointer?,
                                              _ entityId: UnsafePointer<CChar>?,
                                              _ amount: UnsafeMutablePointer<Float>?,
                                              _ haze: UnsafeMutablePointer<Float>?,
                                              _ density: UnsafeMutablePointer<Float>?,
                                              _ temperature: UnsafeMutablePointer<Float>?,
                                              _ mood: UnsafeMutablePointer<Float>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let environment = ecs.get(EnvironmentComponent.self, for: entity) else { return 0 }
    amount?.pointee = environment.atmosphere.amount
    haze?.pointee = environment.atmosphere.haze
    density?.pointee = environment.atmosphere.density
    temperature?.pointee = environment.atmosphere.temperature
    mood?.pointee = environment.atmosphere.mood
    return 1
}

@_cdecl("MCEEditorSetEnvironmentAtmosphere")
public func MCEEditorSetEnvironmentAtmosphere(_ contextPtr: UnsafeRawPointer?,
                                              _ entityId: UnsafePointer<CChar>?,
                                              _ amount: Float,
                                              _ haze: Float,
                                              _ density: Float,
                                              _ temperature: Float,
                                              _ mood: Float) {
    guard let context = resolveContext(contextPtr),
          !context.bridgeServices.isPlaying,
          !context.bridgeServices.isSimulating,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return }
    var environment = ecs.get(EnvironmentComponent.self, for: entity) ?? EnvironmentComponent()
    environment.look.preset = .custom
    environment.atmosphere.amount = clampSkyFacade(amount, min: 0.0, max: 1.0)
    environment.atmosphere.haze = clampSkyFacade(haze, min: 0.0, max: 1.0)
    environment.atmosphere.density = max(0.0, density)
    environment.atmosphere.temperature = clampSkyFacade(temperature, min: -1.0, max: 1.0)
    environment.atmosphere.mood = clampSkyFacade(mood, min: -1.0, max: 1.0)
    ecs.add(environment, to: entity)
    _ = ensureEnvironmentRuntimeState(ecs, entity: entity, environment: environment)
    if environment.source.mode == .procedural {
        markEnvironmentIBLDirty(ecs, entity: entity)
    }
    context.bridgeServices.notifySceneMutation()
}

@_cdecl("MCEEditorGetEnvironmentClouds")
public func MCEEditorGetEnvironmentClouds(_ contextPtr: UnsafeRawPointer?,
                                          _ entityId: UnsafePointer<CChar>?,
                                          _ coverage: UnsafeMutablePointer<Float>?,
                                          _ style: UnsafeMutablePointer<Int32>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let environment = ecs.get(EnvironmentComponent.self, for: entity) else { return 0 }
    coverage?.pointee = environment.clouds.coverage
    style?.pointee = Int32(environment.clouds.style.rawValue)
    return 1
}

@_cdecl("MCEEditorSetEnvironmentClouds")
public func MCEEditorSetEnvironmentClouds(_ contextPtr: UnsafeRawPointer?,
                                          _ entityId: UnsafePointer<CChar>?,
                                          _ coverage: Float,
                                          _ style: Int32) {
    guard let context = resolveContext(contextPtr),
          !context.bridgeServices.isPlaying,
          !context.bridgeServices.isSimulating,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return }
    var environment = ecs.get(EnvironmentComponent.self, for: entity) ?? EnvironmentComponent()
    environment.look.preset = .custom
    environment.clouds.coverage = clampSkyFacade(coverage, min: 0.0, max: 1.0)
    environment.clouds.style = EnvironmentCloudStyle(rawValue: UInt32(max(0, style))) ?? .puffy
    ecs.add(environment, to: entity)
    _ = ensureEnvironmentRuntimeState(ecs, entity: entity, environment: environment)
    if environment.source.mode == .procedural {
        markEnvironmentIBLDirty(ecs, entity: entity)
    }
    context.bridgeServices.notifySceneMutation()
}

@_cdecl("MCEEditorGetEnvironmentFog")
public func MCEEditorGetEnvironmentFog(_ contextPtr: UnsafeRawPointer?,
                                       _ entityId: UnsafePointer<CChar>?,
                                       _ amount: UnsafeMutablePointer<Float>?,
                                       _ height: UnsafeMutablePointer<Float>?,
                                       _ distance: UnsafeMutablePointer<Float>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let environment = ecs.get(EnvironmentComponent.self, for: entity) else { return 0 }
    amount?.pointee = environment.fog.amount
    height?.pointee = environment.fog.height
    distance?.pointee = environment.fog.distance
    return 1
}

@_cdecl("MCEEditorSetEnvironmentFog")
public func MCEEditorSetEnvironmentFog(_ contextPtr: UnsafeRawPointer?,
                                       _ entityId: UnsafePointer<CChar>?,
                                       _ amount: Float,
                                       _ height: Float,
                                       _ distance: Float) {
    guard let context = resolveContext(contextPtr),
          !context.bridgeServices.isPlaying,
          !context.bridgeServices.isSimulating,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return }
    var environment = ecs.get(EnvironmentComponent.self, for: entity) ?? EnvironmentComponent()
    environment.look.preset = .custom
    environment.fog.amount = clampSkyFacade(amount, min: 0.0, max: 1.0)
    environment.fog.height = height
    environment.fog.distance = max(0.0, distance)
    ecs.add(environment, to: entity)
    _ = ensureEnvironmentRuntimeState(ecs, entity: entity, environment: environment)
    context.bridgeServices.notifySceneMutation()
}

@_cdecl("MCEEditorGetEnvironmentIBL")
public func MCEEditorGetEnvironmentIBL(_ contextPtr: UnsafeRawPointer?,
                                       _ entityId: UnsafePointer<CChar>?,
                                       _ realtimeUpdate: UnsafeMutablePointer<UInt32>?,
                                       _ autoRebuildOnChange: UnsafeMutablePointer<UInt32>?,
                                       _ needsRebuild: UnsafeMutablePointer<UInt32>?,
                                       _ dirty: UnsafeMutablePointer<UInt32>?,
                                       _ isRebuilding: UnsafeMutablePointer<UInt32>?,
                                       _ currentRebuildQuality: UnsafeMutablePointer<Int32>?,
                                       _ lastBuiltQuality: UnsafeMutablePointer<Int32>?,
                                       _ lastFailureMessage: UnsafeMutablePointer<CChar>?,
                                       _ lastFailureMessageSize: Int32) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let environment = ecs.get(EnvironmentComponent.self, for: entity) else { return 0 }
    let state = ecs.get(EnvironmentIBLStateComponent.self, for: entity) ?? EnvironmentIBLStateComponent.defaultNeedsRebuild
    realtimeUpdate?.pointee = environment.ibl.realtimeUpdate ? 1 : 0
    autoRebuildOnChange?.pointee = environment.ibl.autoRebuildOnChange ? 1 : 0
    needsRebuild?.pointee = state.needsRebuild ? 1 : 0
    dirty?.pointee = state.dirty ? 1 : 0
    isRebuilding?.pointee = state.isRebuilding ? 1 : 0
    currentRebuildQuality?.pointee = environmentIBLQualityCode(state.currentRebuildQuality)
    lastBuiltQuality?.pointee = environmentIBLQualityCode(state.lastBuiltQuality)
    _ = writeCString(state.lastFailureMessage ?? "", to: lastFailureMessage, max: lastFailureMessageSize)
    return 1
}

private func environmentIBLQualityCode(_ quality: EnvironmentIBLRebuildQuality?) -> Int32 {
    guard let quality else { return -1 }
    switch quality {
    case .interactive:
        return 0
    case .final:
        return 1
    }
}

@_cdecl("MCEEditorSetEnvironmentIBL")
public func MCEEditorSetEnvironmentIBL(_ contextPtr: UnsafeRawPointer?,
                                       _ entityId: UnsafePointer<CChar>?,
                                       _ realtimeUpdate: UInt32,
                                       _ autoRebuildOnChange: UInt32) {
    guard let context = resolveContext(contextPtr),
          !context.bridgeServices.isPlaying,
          !context.bridgeServices.isSimulating,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return }
    var environment = ecs.get(EnvironmentComponent.self, for: entity) ?? EnvironmentComponent()
    environment.ibl.realtimeUpdate = realtimeUpdate != 0
    environment.ibl.autoRebuildOnChange = autoRebuildOnChange != 0
    ecs.add(environment, to: entity)
    _ = ensureEnvironmentRuntimeState(ecs, entity: entity, environment: environment)
    if ecs.get(EnvironmentIBLStateComponent.self, for: entity) == nil {
        ecs.add(EnvironmentIBLStateComponent.defaultNeedsRebuild, to: entity)
    }
    context.bridgeServices.notifySceneMutation()
}

@_cdecl("MCEEditorRequestEnvironmentIBLRebuild")
public func MCEEditorRequestEnvironmentIBLRebuild(_ contextPtr: UnsafeRawPointer?,
                                                 _ entityId: UnsafePointer<CChar>?) {
    guard let context = resolveContext(contextPtr),
          !context.bridgeServices.isPlaying,
          !context.bridgeServices.isSimulating,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return }
    markEnvironmentIBLNeedsRebuild(ecs, entity: entity, requested: true)
    context.bridgeServices.notifySceneMutation()
}

@_cdecl("MCEEditorGetReflectionProbe")
public func MCEEditorGetReflectionProbe(_ contextPtr: UnsafeRawPointer?,
                                        _ entityId: UnsafePointer<CChar>?,
                                        _ enabled: UnsafeMutablePointer<UInt32>?,
                                        _ boxExtentsX: UnsafeMutablePointer<Float>?,
                                        _ boxExtentsY: UnsafeMutablePointer<Float>?,
                                        _ boxExtentsZ: UnsafeMutablePointer<Float>?,
                                        _ blendDistance: UnsafeMutablePointer<Float>?,
                                        _ priority: UnsafeMutablePointer<Int32>?,
                                        _ intensity: UnsafeMutablePointer<Float>?,
                                        _ captureResolution: UnsafeMutablePointer<Int32>?,
                                        _ rebuildMode: UnsafeMutablePointer<Int32>?,
                                        _ includeSky: UnsafeMutablePointer<UInt32>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          let probe = ecs.get(ReflectionProbeComponent.self, for: entity) else { return 0 }
    enabled?.pointee = probe.enabled ? 1 : 0
    boxExtentsX?.pointee = probe.boxExtents.x
    boxExtentsY?.pointee = probe.boxExtents.y
    boxExtentsZ?.pointee = probe.boxExtents.z
    blendDistance?.pointee = probe.blendDistance
    priority?.pointee = probe.priority
    intensity?.pointee = probe.intensity
    captureResolution?.pointee = probe.captureResolution
    rebuildMode?.pointee = Int32(probe.rebuildMode.rawValue)
    includeSky?.pointee = probe.includeSky ? 1 : 0
    return 1
}

@_cdecl("MCEEditorSetReflectionProbe")
public func MCEEditorSetReflectionProbe(_ contextPtr: UnsafeRawPointer?,
                                        _ entityId: UnsafePointer<CChar>?,
                                        _ enabled: UInt32,
                                        _ boxExtentsX: Float,
                                        _ boxExtentsY: Float,
                                        _ boxExtentsZ: Float,
                                        _ blendDistance: Float,
                                        _ priority: Int32,
                                        _ intensity: Float,
                                        _ captureResolution: Int32,
                                        _ rebuildMode: Int32,
                                        _ includeSky: UInt32) {
    guard let context = resolveContext(contextPtr),
          !context.bridgeServices.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context),
          var probe = ecs.get(ReflectionProbeComponent.self, for: entity) else { return }

    probe.enabled = enabled != 0
    probe.boxExtents = SIMD3<Float>(max(boxExtentsX, 0.0), max(boxExtentsY, 0.0), max(boxExtentsZ, 0.0))
    probe.blendDistance = max(blendDistance, 0.0)
    probe.priority = priority
    probe.intensity = max(intensity, 0.0)
    probe.captureResolution = max(captureResolution, 16)
    probe.rebuildMode = ReflectionProbeRebuildMode(rawValue: UInt32(max(rebuildMode, 0))) ?? .onPlay
    probe.includeSky = includeSky != 0
    ecs.add(probe, to: entity)
    if ecs.has(PrefabInstanceComponent.self, entity) {
        var overrides = ecs.get(PrefabOverrideComponent.self, for: entity) ?? PrefabOverrideComponent()
        overrides.overridden.insert(.reflectionProbe)
        ecs.add(overrides, to: entity)
    }
    context.bridgeServices.notifySceneMutation()
}

@_cdecl("MCEEditorGetReflectionProbeRuntimeStatus")
public func MCEEditorGetReflectionProbeRuntimeStatus(_ contextPtr: UnsafeRawPointer?,
                                                     _ entityId: UnsafePointer<CChar>?,
                                                     _ statusOut: UnsafeMutablePointer<Int32>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          context.bridgeServices.isPlaying,
          let runtimeScene = context.bridgeServices.runtimeScene,
          let renderer = context.engineContext.renderer,
          let entity = entity(from: entityId, context: context),
          let status = renderer.reflectionProbeBakeStatus(scene: runtimeScene, entityID: entity.id) else {
        return 0
    }
    statusOut?.pointee = status.rawValue
    return 1
}

@_cdecl("MCEEditorRequestReflectionProbeRebuild")
public func MCEEditorRequestReflectionProbeRebuild(_ contextPtr: UnsafeRawPointer?,
                                                   _ entityId: UnsafePointer<CChar>?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          context.bridgeServices.isPlaying,
          let runtimeScene = context.bridgeServices.runtimeScene,
          let renderer = context.engineContext.renderer,
          let entity = entity(from: entityId, context: context) else { return 0 }
    renderer.queueReflectionProbeRebuilds(scene: runtimeScene, entities: [entity], force: true)
    return 1
}

@_cdecl("MCEEditorRequestAllReflectionProbeRebuilds")
public func MCEEditorRequestAllReflectionProbeRebuilds(_ contextPtr: UnsafeRawPointer?) -> UInt32 {
    guard let context = resolveContext(contextPtr),
          context.bridgeServices.isPlaying,
          let runtimeScene = context.bridgeServices.runtimeScene,
          let renderer = context.engineContext.renderer else { return 0 }
    renderer.queueReflectionProbeRebuilds(scene: runtimeScene, entities: nil, force: true)
    return 1
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
          !context.bridgeServices.isPlaying,
          let ecs = editorECS(context),
          let entity = entity(from: entityId, context: context) else { return 0 }
    setActiveSky(ecs: ecs, entity: entity, logger: context.engineContext.log)
    context.bridgeServices.notifySceneMutation()
    return 1
}
