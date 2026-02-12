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
}

private func editorECS() -> SceneECS? {
    return SceneManager.getEditorScene()?.ecs
}

private func entity(from idPointer: UnsafePointer<CChar>?) -> Entity? {
    guard let idPointer else { return nil }
    let idString = String(cString: idPointer)
    guard let uuid = UUID(uuidString: idString) else { return nil }
    return editorECS()?.entity(with: uuid)
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

private func allSkyEntities(ecs: SceneECS) -> [Entity] {
    return ecs.allEntities().filter { ecs.get(SkyLightComponent.self, for: $0) != nil }
}

private func ensureActiveSkyEntity(ecs: SceneECS) -> Entity? {
    if let active = ecs.activeSkyLight()?.0 {
        return active
    }
    let skyEntities = allSkyEntities(ecs: ecs)
    guard let first = skyEntities.first else { return nil }
    ecs.add(SkyLightTag(), to: first)
    print("EDITOR::SKY::ACTIVE_ASSIGNED=\(first.id.uuidString)")
    return first
}

private func setActiveSky(ecs: SceneECS, entity: Entity) {
    for skyEntity in allSkyEntities(ecs: ecs) {
        if skyEntity.id != entity.id {
            ecs.remove(SkyLightTag.self, from: skyEntity)
        }
    }
    ecs.add(SkyLightTag(), to: entity)
    if var sky = ecs.get(SkyLightComponent.self, for: entity) {
        sky.needsRegenerate = true
        ecs.add(sky, to: entity)
        print("EDITOR::SKY::REGEN_REQUESTED=\(entity.id.uuidString)")
    }
    print("EDITOR::SKY::ACTIVE_SET=\(entity.id.uuidString)")
}

@_cdecl("MCEEditorGetEntityCount")
public func MCEEditorGetEntityCount() -> Int32 {
    guard let ecs = editorECS() else { return 0 }
    return Int32(ecs.allEntities().count)
}

@_cdecl("MCEEditorGetEntityIdAt")
public func MCEEditorGetEntityIdAt(_ index: Int32, _ buffer: UnsafeMutablePointer<CChar>?, _ bufferSize: Int32) -> Int32 {
    guard let ecs = editorECS(), index >= 0 else { return 0 }
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
public func MCEEditorGetEntityName(_ entityId: UnsafePointer<CChar>?, _ buffer: UnsafeMutablePointer<CChar>?, _ bufferSize: Int32) -> Int32 {
    guard let ecs = editorECS(), let entity = entity(from: entityId) else { return 0 }
    let name = ecs.get(NameComponent.self, for: entity)?.name ?? ""
    return writeCString(name, to: buffer, max: bufferSize)
}

@_cdecl("MCEEditorEntityExists")
public func MCEEditorEntityExists(_ entityId: UnsafePointer<CChar>?) -> UInt32 {
    guard let _ = entity(from: entityId) else { return 0 }
    return 1
}

@_cdecl("MCEEditorSetEntityName")
public func MCEEditorSetEntityName(_ entityId: UnsafePointer<CChar>?, _ name: UnsafePointer<CChar>?) {
    guard !SceneManager.isPlaying, let ecs = editorECS(), let entity = entity(from: entityId), let name else { return }
    let newName = String(cString: name)
    ecs.add(NameComponent(name: newName), to: entity)
    print("EDITOR::COMPONENT::NAME=\(entity.id.uuidString) \(newName)")
}

@_cdecl("MCEEditorCreateEntity")
public func MCEEditorCreateEntity(_ name: UnsafePointer<CChar>?, _ outId: UnsafeMutablePointer<CChar>?, _ outIdSize: Int32) -> Int32 {
    guard !SceneManager.isPlaying, let ecs = editorECS() else { return 0 }
    let entityName = name != nil ? String(cString: name!) : "Entity"
    let entity = ecs.createEntity(name: entityName)
    return writeCString(entity.id.uuidString, to: outId, max: outIdSize)
}

@_cdecl("MCEEditorCreateMeshEntity")
public func MCEEditorCreateMeshEntity(_ meshType: Int32, _ outId: UnsafeMutablePointer<CChar>?, _ outIdSize: Int32) -> Int32 {
    guard !SceneManager.isPlaying, let ecs = editorECS() else { return 0 }
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
    return writeCString(entity.id.uuidString, to: outId, max: outIdSize)
}

@_cdecl("MCEEditorCreateMeshEntityFromHandle")
public func MCEEditorCreateMeshEntityFromHandle(_ meshHandle: UnsafePointer<CChar>?, _ outId: UnsafeMutablePointer<CChar>?, _ outIdSize: Int32) -> Int32 {
    guard !SceneManager.isPlaying, let ecs = editorECS() else { return 0 }
    let meshString = meshHandle != nil ? String(cString: meshHandle!) : ""
    let meshHandleValue = handleFromString(meshString)
    let entity = ecs.createEntity(name: "Mesh")
    ecs.add(TransformComponent(), to: entity)
    ecs.add(MeshRendererComponent(meshHandle: meshHandleValue), to: entity)
    return writeCString(entity.id.uuidString, to: outId, max: outIdSize)
}

@_cdecl("MCEEditorCreateLightEntity")
public func MCEEditorCreateLightEntity(_ lightType: Int32, _ outId: UnsafeMutablePointer<CChar>?, _ outIdSize: Int32) -> Int32 {
    guard !SceneManager.isPlaying, let ecs = editorECS() else { return 0 }
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
    return writeCString(entity.id.uuidString, to: outId, max: outIdSize)
}

@_cdecl("MCEEditorCreateSkyEntity")
public func MCEEditorCreateSkyEntity(_ outId: UnsafeMutablePointer<CChar>?, _ outIdSize: Int32) -> Int32 {
    guard !SceneManager.isPlaying, let ecs = editorECS() else { return 0 }
    let entity = ecs.createEntity(name: "Sky")
    var sky = SkyLightComponent()
    sky.mode = .procedural
    sky.needsRegenerate = true
    ecs.add(sky, to: entity)
    setActiveSky(ecs: ecs, entity: entity)
    return writeCString(entity.id.uuidString, to: outId, max: outIdSize)
}

@_cdecl("MCEEditorDestroyEntity")
public func MCEEditorDestroyEntity(_ entityId: UnsafePointer<CChar>?) {
    guard !SceneManager.isPlaying, let ecs = editorECS(), let entity = entity(from: entityId) else { return }
    ecs.destroyEntity(entity)
}

@_cdecl("MCEEditorEntityHasComponent")
public func MCEEditorEntityHasComponent(_ entityId: UnsafePointer<CChar>?, _ componentType: Int32) -> UInt32 {
    guard let ecs = editorECS(), let entity = entity(from: entityId), let type = EditorComponentType(rawValue: componentType) else { return 0 }
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
    }
}

@_cdecl("MCEEditorAddComponent")
public func MCEEditorAddComponent(_ entityId: UnsafePointer<CChar>?, _ componentType: Int32) -> UInt32 {
    guard !SceneManager.isPlaying, let ecs = editorECS(), let entity = entity(from: entityId), let type = EditorComponentType(rawValue: componentType) else { return 0 }
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
    }
    return 1
}

@_cdecl("MCEEditorRemoveComponent")
public func MCEEditorRemoveComponent(_ entityId: UnsafePointer<CChar>?, _ componentType: Int32) -> UInt32 {
    guard !SceneManager.isPlaying, let ecs = editorECS(), let entity = entity(from: entityId), let type = EditorComponentType(rawValue: componentType) else { return 0 }
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
    }
    return 1
}

@_cdecl("MCEEditorGetTransform")
public func MCEEditorGetTransform(_ entityId: UnsafePointer<CChar>?,
                                  _ px: UnsafeMutablePointer<Float>?, _ py: UnsafeMutablePointer<Float>?, _ pz: UnsafeMutablePointer<Float>?,
                                  _ rx: UnsafeMutablePointer<Float>?, _ ry: UnsafeMutablePointer<Float>?, _ rz: UnsafeMutablePointer<Float>?,
                                  _ sx: UnsafeMutablePointer<Float>?, _ sy: UnsafeMutablePointer<Float>?, _ sz: UnsafeMutablePointer<Float>?) -> UInt32 {
    guard let ecs = editorECS(), let entity = entity(from: entityId), let transform = ecs.get(TransformComponent.self, for: entity) else { return 0 }
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
public func MCEEditorSetTransform(_ entityId: UnsafePointer<CChar>?,
                                  _ px: Float, _ py: Float, _ pz: Float,
                                  _ rx: Float, _ ry: Float, _ rz: Float,
                                  _ sx: Float, _ sy: Float, _ sz: Float) {
    guard !SceneManager.isPlaying, let ecs = editorECS(), let entity = entity(from: entityId) else { return }
    let transform = TransformComponent(
        position: SIMD3<Float>(px, py, pz),
        rotation: SIMD3<Float>(rx, ry, rz),
        scale: SIMD3<Float>(sx, sy, sz)
    )
    ecs.add(transform, to: entity)
    print("EDITOR::COMPONENT::TRANSFORM=\(entity.id.uuidString)")
}

@_cdecl("MCEEditorGetMeshRenderer")
public func MCEEditorGetMeshRenderer(_ entityId: UnsafePointer<CChar>?,
                                     _ meshHandle: UnsafeMutablePointer<CChar>?, _ meshHandleSize: Int32,
                                     _ materialHandle: UnsafeMutablePointer<CChar>?, _ materialHandleSize: Int32) -> UInt32 {
    guard let ecs = editorECS(), let entity = entity(from: entityId), let meshRenderer = ecs.get(MeshRendererComponent.self, for: entity) else { return 0 }
    let meshString = meshRenderer.meshHandle?.rawValue.uuidString ?? ""
    let materialString = meshRenderer.materialHandle?.rawValue.uuidString ?? ""
    _ = writeCString(meshString, to: meshHandle, max: meshHandleSize)
    _ = writeCString(materialString, to: materialHandle, max: materialHandleSize)
    return 1
}

@_cdecl("MCEEditorSetMeshRenderer")
public func MCEEditorSetMeshRenderer(_ entityId: UnsafePointer<CChar>?, _ meshHandle: UnsafePointer<CChar>?, _ materialHandle: UnsafePointer<CChar>?) {
    guard !SceneManager.isPlaying, let ecs = editorECS(), let entity = entity(from: entityId) else { return }
    let meshString = meshHandle != nil ? String(cString: meshHandle!) : ""
    let materialString = materialHandle != nil ? String(cString: materialHandle!) : ""
    var component = ecs.get(MeshRendererComponent.self, for: entity) ?? MeshRendererComponent(meshHandle: nil)
    component.meshHandle = handleFromString(meshString)
    component.materialHandle = handleFromString(materialString)
    ecs.add(component, to: entity)
    print("EDITOR::COMPONENT::MESH=\(entity.id.uuidString)")
}

@_cdecl("MCEEditorAssignMaterialToEntity")
public func MCEEditorAssignMaterialToEntity(_ entityId: UnsafePointer<CChar>?, _ materialHandle: UnsafePointer<CChar>?) {
    guard !SceneManager.isPlaying, let ecs = editorECS(), let entity = entity(from: entityId) else { return }
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

    print("EDITOR::COMPONENT::MATERIAL=\(entity.id.uuidString)")
}

@_cdecl("MCEEditorGetMaterialComponent")
public func MCEEditorGetMaterialComponent(_ entityId: UnsafePointer<CChar>?, _ materialHandle: UnsafeMutablePointer<CChar>?, _ materialHandleSize: Int32) -> UInt32 {
    guard let ecs = editorECS(), let entity = entity(from: entityId), let component = ecs.get(MaterialComponent.self, for: entity) else { return 0 }
    let materialString = component.materialHandle?.rawValue.uuidString ?? ""
    _ = writeCString(materialString, to: materialHandle, max: materialHandleSize)
    return 1
}

@_cdecl("MCEEditorSetMaterialComponent")
public func MCEEditorSetMaterialComponent(_ entityId: UnsafePointer<CChar>?, _ materialHandle: UnsafePointer<CChar>?) {
    guard !SceneManager.isPlaying, let ecs = editorECS(), let entity = entity(from: entityId) else { return }
    let materialString = materialHandle != nil ? String(cString: materialHandle!) : ""
    var component = ecs.get(MaterialComponent.self, for: entity) ?? MaterialComponent(materialHandle: nil)
    component.materialHandle = handleFromString(materialString)
    ecs.add(component, to: entity)
    print("EDITOR::COMPONENT::MATERIAL=\(entity.id.uuidString)")
}

@_cdecl("MCEEditorGetLight")
public func MCEEditorGetLight(_ entityId: UnsafePointer<CChar>?, _ type: UnsafeMutablePointer<Int32>?,
                              _ colorX: UnsafeMutablePointer<Float>?, _ colorY: UnsafeMutablePointer<Float>?, _ colorZ: UnsafeMutablePointer<Float>?,
                              _ brightness: UnsafeMutablePointer<Float>?, _ range: UnsafeMutablePointer<Float>?, _ innerCos: UnsafeMutablePointer<Float>?, _ outerCos: UnsafeMutablePointer<Float>?,
                              _ dirX: UnsafeMutablePointer<Float>?, _ dirY: UnsafeMutablePointer<Float>?, _ dirZ: UnsafeMutablePointer<Float>?) -> UInt32 {
    guard let ecs = editorECS(), let entity = entity(from: entityId), let light = ecs.get(LightComponent.self, for: entity) else { return 0 }
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
public func MCEEditorSetLight(_ entityId: UnsafePointer<CChar>?, _ type: Int32,
                              _ colorX: Float, _ colorY: Float, _ colorZ: Float,
                              _ brightness: Float, _ range: Float, _ innerCos: Float, _ outerCos: Float,
                              _ dirX: Float, _ dirY: Float, _ dirZ: Float) {
    guard !SceneManager.isPlaying, let ecs = editorECS(), let entity = entity(from: entityId) else { return }
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
    print("EDITOR::COMPONENT::LIGHT=\(entity.id.uuidString)")
}

@_cdecl("MCEEditorGetSkyLight")
public func MCEEditorGetSkyLight(_ entityId: UnsafePointer<CChar>?, _ mode: UnsafeMutablePointer<Int32>?, _ enabled: UnsafeMutablePointer<UInt32>?,
                                 _ intensity: UnsafeMutablePointer<Float>?, _ tintX: UnsafeMutablePointer<Float>?, _ tintY: UnsafeMutablePointer<Float>?, _ tintZ: UnsafeMutablePointer<Float>?,
                                 _ turbidity: UnsafeMutablePointer<Float>?, _ azimuth: UnsafeMutablePointer<Float>?, _ elevation: UnsafeMutablePointer<Float>?,
                                 _ hdriHandle: UnsafeMutablePointer<CChar>?, _ hdriHandleSize: Int32) -> UInt32 {
    guard let ecs = editorECS(), let entity = entity(from: entityId), let sky = ecs.get(SkyLightComponent.self, for: entity) else { return 0 }
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
public func MCEEditorSetSkyLight(_ entityId: UnsafePointer<CChar>?, _ mode: Int32, _ enabled: UInt32,
                                 _ intensity: Float, _ tintX: Float, _ tintY: Float, _ tintZ: Float,
                                 _ turbidity: Float, _ azimuth: Float, _ elevation: Float,
                                 _ hdriHandle: UnsafePointer<CChar>?) {
    guard !SceneManager.isPlaying, let ecs = editorECS(), let entity = entity(from: entityId) else { return }
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
    sky.needsRegenerate = (sky.mode == .procedural)
    ecs.add(sky, to: entity)
    if sky.needsRegenerate {
        print("EDITOR::SKY::REGEN_REQUESTED=\(entity.id.uuidString)")
    }
}

@_cdecl("MCEEditorSkyEntityCount")
public func MCEEditorSkyEntityCount() -> Int32 {
    guard let ecs = editorECS() else { return 0 }
    return Int32(allSkyEntities(ecs: ecs).count)
}

@_cdecl("MCEEditorGetActiveSkyId")
public func MCEEditorGetActiveSkyId(_ buffer: UnsafeMutablePointer<CChar>?, _ bufferSize: Int32) -> Int32 {
    guard let ecs = editorECS() else { return 0 }
    guard let active = ensureActiveSkyEntity(ecs: ecs) else { return 0 }
    return writeCString(active.id.uuidString, to: buffer, max: bufferSize)
}

@_cdecl("MCEEditorSetActiveSky")
public func MCEEditorSetActiveSky(_ entityId: UnsafePointer<CChar>?) -> UInt32 {
    guard !SceneManager.isPlaying, let ecs = editorECS(), let entity = entity(from: entityId) else { return 0 }
    setActiveSky(ecs: ecs, entity: entity)
    return 1
}

@_cdecl("MCEEditorLogSelection")
public func MCEEditorLogSelection(_ entityId: UnsafePointer<CChar>?) {
    guard let entityId else { return }
    let idString = String(cString: entityId)
    print("EDITOR::SELECTION=\(idString)")
}
