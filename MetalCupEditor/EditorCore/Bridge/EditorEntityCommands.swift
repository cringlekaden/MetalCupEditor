import Foundation
import MetalCupEngine

enum EditorEntityCommands {
    static func setParent(_ contextPtr: UnsafeRawPointer?, _ childId: UnsafePointer<CChar>?, _ parentId: UnsafePointer<CChar>?, _ keepWorldTransform: UInt32) -> UInt32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              !context.editorSceneController.isPlaying,
              !context.editorSceneController.isSimulating,
              let ecs = EditorBridgeInternals.ecsValue(context),
              let child = EditorBridgeInternals.entityValue(from: childId, context: context) else { return 0 }
        let success = ecs.setParent(child, EditorBridgeInternals.entityValue(from: parentId, context: context), keepWorldTransform: keepWorldTransform != 0)
        if success {
            EditorBridgeInternals.markHierarchyOverrideValue(ecs, child)
            context.editorProjectManager.notifySceneMutation()
        }
        return success ? 1 : 0
    }

    static func unparent(_ contextPtr: UnsafeRawPointer?, _ childId: UnsafePointer<CChar>?, _ keepWorldTransform: UInt32) -> UInt32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              !context.editorSceneController.isPlaying,
              !context.editorSceneController.isSimulating,
              let ecs = EditorBridgeInternals.ecsValue(context),
              let child = EditorBridgeInternals.entityValue(from: childId, context: context) else { return 0 }
        let success = ecs.unparent(child, keepWorldTransform: keepWorldTransform != 0)
        if success {
            EditorBridgeInternals.markHierarchyOverrideValue(ecs, child)
            context.editorProjectManager.notifySceneMutation()
        }
        return success ? 1 : 0
    }

    static func reorderEntity(_ contextPtr: UnsafeRawPointer?, _ entityId: UnsafePointer<CChar>?, _ parentId: UnsafePointer<CChar>?, _ newIndex: Int32) -> UInt32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              !context.editorSceneController.isPlaying,
              !context.editorSceneController.isSimulating,
              let ecs = EditorBridgeInternals.ecsValue(context),
              let child = EditorBridgeInternals.entityValue(from: entityId, context: context) else { return 0 }
        let success = ecs.reorderChild(parent: EditorBridgeInternals.entityValue(from: parentId, context: context), child: child, newIndex: Int(newIndex))
        if success {
            EditorBridgeInternals.markHierarchyOverrideValue(ecs, child)
            context.editorProjectManager.notifySceneMutation()
        }
        return success ? 1 : 0
    }

    static func setEntityName(_ contextPtr: UnsafeRawPointer?, _ entityId: UnsafePointer<CChar>?, _ name: UnsafePointer<CChar>?) {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              !context.editorSceneController.isPlaying,
              !context.editorSceneController.isSimulating,
              let ecs = EditorBridgeInternals.ecsValue(context),
              let entity = EditorBridgeInternals.entityValue(from: entityId, context: context),
              let name else { return }
        let newName = String(cString: name)
        ecs.add(NameComponent(name: newName), to: entity)
        context.editorProjectManager.notifySceneMutation()
        context.engineContext.log.logInfo("Entity renamed: \(entity.id.uuidString) \(newName)", category: .scene)
    }

    static func createEntity(_ contextPtr: UnsafeRawPointer?, _ name: UnsafePointer<CChar>?, _ outId: UnsafeMutablePointer<CChar>?, _ outIdSize: Int32) -> Int32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              !context.editorSceneController.isPlaying,
              !context.editorSceneController.isSimulating,
              let ecs = EditorBridgeInternals.ecsValue(context) else { return 0 }
        let entity = ecs.createEntity(name: name != nil ? String(cString: name!) : "Entity")
        context.editorProjectManager.notifySceneMutation()
        return EditorBridgeInternals.cStringWrite(entity.id.uuidString, to: outId, max: outIdSize)
    }

    static func createMeshEntity(_ contextPtr: UnsafeRawPointer?, _ meshType: Int32, _ outId: UnsafeMutablePointer<CChar>?, _ outIdSize: Int32) -> Int32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              !context.editorSceneController.isPlaying,
              !context.editorSceneController.isSimulating,
              let ecs = EditorBridgeInternals.ecsValue(context) else { return 0 }
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
        return EditorBridgeInternals.cStringWrite(entity.id.uuidString, to: outId, max: outIdSize)
    }

    static func createMeshEntityFromHandle(_ contextPtr: UnsafeRawPointer?, _ meshHandle: UnsafePointer<CChar>?, _ outId: UnsafeMutablePointer<CChar>?, _ outIdSize: Int32) -> Int32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              !context.editorSceneController.isPlaying,
              !context.editorSceneController.isSimulating,
              let ecs = EditorBridgeInternals.ecsValue(context) else { return 0 }
        let meshString = meshHandle != nil ? String(cString: meshHandle!) : ""
        let entity = ecs.createEntity(name: "Mesh")
        ecs.add(TransformComponent(), to: entity)
        ecs.add(MeshRendererComponent(meshHandle: EditorBridgeInternals.assetHandleValue(meshString)), to: entity)
        context.editorProjectManager.notifySceneMutation()
        return EditorBridgeInternals.cStringWrite(entity.id.uuidString, to: outId, max: outIdSize)
    }

    static func createMeshEntityFromHandleWithMaterials(_ contextPtr: UnsafeRawPointer?, _ meshHandle: UnsafePointer<CChar>?, _ outId: UnsafeMutablePointer<CChar>?, _ outIdSize: Int32) -> Int32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              !context.editorSceneController.isPlaying,
              !context.editorSceneController.isSimulating,
              let ecs = EditorBridgeInternals.ecsValue(context) else { return 0 }
        let meshString = meshHandle != nil ? String(cString: meshHandle!) : ""
        let meshHandleValue = EditorBridgeInternals.assetHandleValue(meshString)
        let entity = ecs.createEntity(name: "Mesh")
        ecs.add(TransformComponent(), to: entity)

        var submeshMaterials: [AssetHandle?]? = nil
        var primaryMaterial: AssetHandle? = nil
        if let meshHandleValue,
           let meshMetadata = EditorBridgeInternals.assetMetadataValue(for: meshHandleValue, projectManager: context.editorProjectManager),
           let raw = meshMetadata.importSettings["submeshMaterials"],
           !raw.isEmpty {
            let parsed = EditorBridgeInternals.submeshMaterialHandlesValue(raw)
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
        return EditorBridgeInternals.cStringWrite(entity.id.uuidString, to: outId, max: outIdSize)
    }

    static func createLightEntity(_ contextPtr: UnsafeRawPointer?, _ lightType: Int32, _ outId: UnsafeMutablePointer<CChar>?, _ outIdSize: Int32) -> Int32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              !context.editorSceneController.isPlaying,
              !context.editorSceneController.isSimulating,
              let ecs = EditorBridgeInternals.ecsValue(context) else { return 0 }
        let (entityName, lightTypeValue): (String, LightType) = {
            switch lightType {
            case 1: return ("Spot Light", .spot)
            case 2: return ("Directional Light", .directional)
            default: return ("Point Light", .point)
            }
        }()
        let entity = ecs.createEntity(name: entityName)
        ecs.add(TransformComponent(), to: entity)
        ecs.add(LightComponent(type: lightTypeValue), to: entity)
        context.editorProjectManager.notifySceneMutation()
        return EditorBridgeInternals.cStringWrite(entity.id.uuidString, to: outId, max: outIdSize)
    }

    static func createSkyEntity(_ contextPtr: UnsafeRawPointer?, _ outId: UnsafeMutablePointer<CChar>?, _ outIdSize: Int32) -> Int32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              !context.editorSceneController.isPlaying,
              !context.editorSceneController.isSimulating,
              let ecs = EditorBridgeInternals.ecsValue(context) else { return 0 }
        let entity = ecs.createEntity(name: "Sky")
        var sky = SkyLightComponent()
        sky.mode = .procedural
        sky.needsRebuild = true
        ecs.add(sky, to: entity)
        EditorBridgeInternals.setActiveSkyValue(ecs: ecs, entity: entity, logger: context.engineContext.log)
        context.editorProjectManager.notifySceneMutation()
        return EditorBridgeInternals.cStringWrite(entity.id.uuidString, to: outId, max: outIdSize)
    }

    static func createCameraEntity(_ contextPtr: UnsafeRawPointer?, _ outId: UnsafeMutablePointer<CChar>?, _ outIdSize: Int32) -> Int32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              !context.editorSceneController.isPlaying,
              !context.editorSceneController.isSimulating,
              let ecs = EditorBridgeInternals.ecsValue(context) else { return 0 }
        let entity = ecs.createEntity(name: "Camera")
        var component = CameraComponent(isPrimary: false, isEditor: false)
        if !EditorBridgeInternals.hasPrimaryRuntimeCameraValue(ecs: ecs) {
            component.isPrimary = true
        }
        ecs.add(component, to: entity)
        context.editorProjectManager.notifySceneMutation()
        return EditorBridgeInternals.cStringWrite(entity.id.uuidString, to: outId, max: outIdSize)
    }

    static func createCameraFromView(_ contextPtr: UnsafeRawPointer?, _ outId: UnsafeMutablePointer<CChar>?, _ outIdSize: Int32) -> Int32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              !context.editorSceneController.isPlaying,
              !context.editorSceneController.isSimulating,
              let ecs = EditorBridgeInternals.ecsValue(context) else { return 0 }
        let entity = ecs.createEntity(name: "Camera")
        if let editorCamera = EditorBridgeInternals.findEditorCameraValue(ecs: ecs) {
            ecs.add(editorCamera.1, to: entity)
        }
        var component = EditorBridgeInternals.findEditorCameraValue(ecs: ecs)?.2 ?? CameraComponent()
        component.isEditor = false
        component.isPrimary = !EditorBridgeInternals.hasPrimaryRuntimeCameraValue(ecs: ecs)
        ecs.add(component, to: entity)
        context.editorProjectManager.notifySceneMutation()
        return EditorBridgeInternals.cStringWrite(entity.id.uuidString, to: outId, max: outIdSize)
    }

    static func destroyEntity(_ contextPtr: UnsafeRawPointer?, _ entityId: UnsafePointer<CChar>?) {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              !context.editorSceneController.isPlaying,
              !context.editorSceneController.isSimulating,
              let ecs = EditorBridgeInternals.ecsValue(context),
              let entity = EditorBridgeInternals.entityValue(from: entityId, context: context) else { return }
        ecs.destroyEntity(entity)
        context.editorProjectManager.notifySceneMutation()
    }

    static func destroySelectedEntities(_ contextPtr: UnsafeRawPointer?) {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              !context.editorSceneController.isPlaying,
              !context.editorSceneController.isSimulating,
              let ecs = EditorBridgeInternals.ecsValue(context) else { return }
        let selected = context.editorSceneController.selectedEntityUUIDs().compactMap { ecs.entity(with: $0) }
        guard !selected.isEmpty else { return }
        let selectedSet = Set(selected)
        let topLevel = ecs.allEntities().filter { entity in
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
}
