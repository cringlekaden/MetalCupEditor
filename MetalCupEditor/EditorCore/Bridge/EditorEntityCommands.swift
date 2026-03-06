import Foundation
import MetalCupEngine

enum EditorEntityCommands {
    static func setParent(_ contextPtr: UnsafeRawPointer?, _ childId: UnsafePointer<CChar>?, _ parentId: UnsafePointer<CChar>?, _ keepWorldTransform: UInt32) -> UInt32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              !context.bridgeServices.isPlaying,
              !context.bridgeServices.isSimulating,
              let ecs = EditorBridgeInternals.ecsValue(context),
              let child = EditorBridgeInternals.entityValue(from: childId, context: context) else { return 0 }
        let success = ecs.setParent(child, EditorBridgeInternals.entityValue(from: parentId, context: context), keepWorldTransform: keepWorldTransform != 0)
        if success {
            EditorBridgeInternals.markHierarchyOverrideValue(ecs, child)
            EditorBridgeInternals.commitMutation(context, label: "EditorCommand")
        }
        return success ? 1 : 0
    }

    static func unparent(_ contextPtr: UnsafeRawPointer?, _ childId: UnsafePointer<CChar>?, _ keepWorldTransform: UInt32) -> UInt32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              !context.bridgeServices.isPlaying,
              !context.bridgeServices.isSimulating,
              let ecs = EditorBridgeInternals.ecsValue(context),
              let child = EditorBridgeInternals.entityValue(from: childId, context: context) else { return 0 }
        let success = ecs.unparent(child, keepWorldTransform: keepWorldTransform != 0)
        if success {
            EditorBridgeInternals.markHierarchyOverrideValue(ecs, child)
            EditorBridgeInternals.commitMutation(context, label: "EditorCommand")
        }
        return success ? 1 : 0
    }

    static func reorderEntity(_ contextPtr: UnsafeRawPointer?, _ entityId: UnsafePointer<CChar>?, _ parentId: UnsafePointer<CChar>?, _ newIndex: Int32) -> UInt32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              !context.bridgeServices.isPlaying,
              !context.bridgeServices.isSimulating,
              let ecs = EditorBridgeInternals.ecsValue(context),
              let child = EditorBridgeInternals.entityValue(from: entityId, context: context) else { return 0 }
        let success = ecs.reorderChild(parent: EditorBridgeInternals.entityValue(from: parentId, context: context), child: child, newIndex: Int(newIndex))
        if success {
            EditorBridgeInternals.markHierarchyOverrideValue(ecs, child)
            EditorBridgeInternals.commitMutation(context, label: "EditorCommand")
        }
        return success ? 1 : 0
    }

    static func setEntityName(_ contextPtr: UnsafeRawPointer?, _ entityId: UnsafePointer<CChar>?, _ name: UnsafePointer<CChar>?) {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              !context.bridgeServices.isPlaying,
              !context.bridgeServices.isSimulating,
              let ecs = EditorBridgeInternals.ecsValue(context),
              let entity = EditorBridgeInternals.entityValue(from: entityId, context: context),
              let name else { return }
        let newName = String(cString: name)
        ecs.add(NameComponent(name: newName), to: entity)
        EditorBridgeInternals.commitMutation(context, label: "EditorCommand")
        context.engineContext.log.logInfo("Entity renamed: \(entity.id.uuidString) \(newName)", category: .scene)
    }

    static func createEntity(_ contextPtr: UnsafeRawPointer?, _ name: UnsafePointer<CChar>?, _ outId: UnsafeMutablePointer<CChar>?, _ outIdSize: Int32) -> Int32 {
        EditorBridgeInternals.markFacadeInvocation("EditorEntityCommands.createEntity")
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              !context.bridgeServices.isPlaying,
              !context.bridgeServices.isSimulating,
              let ecs = EditorBridgeInternals.ecsValue(context) else { return 0 }
        let entity = ecs.createEntity(name: name != nil ? String(cString: name!) : "Entity")
        EditorBridgeInternals.commitMutation(context, label: "EditorCommand")
        return EditorBridgeInternals.cStringWrite(entity.id.uuidString, to: outId, max: outIdSize)
    }

    static func createMeshEntity(_ contextPtr: UnsafeRawPointer?, _ meshType: Int32, _ outId: UnsafeMutablePointer<CChar>?, _ outIdSize: Int32) -> Int32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              !context.bridgeServices.isPlaying,
              !context.bridgeServices.isSimulating,
              let scene = context.bridgeServices.activeScene(),
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
        _ = scene.transformAuthority.ensureLocalTransform(entity: entity,
                                                          default: TransformComponent(),
                                                          source: .editor)
        ecs.add(MeshRendererComponent(meshHandle: meshHandle), to: entity)
        EditorBridgeInternals.commitMutation(context, label: "EditorCommand")
        return EditorBridgeInternals.cStringWrite(entity.id.uuidString, to: outId, max: outIdSize)
    }

    static func createMeshEntityFromHandle(_ contextPtr: UnsafeRawPointer?, _ meshHandle: UnsafePointer<CChar>?, _ outId: UnsafeMutablePointer<CChar>?, _ outIdSize: Int32) -> Int32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              !context.bridgeServices.isPlaying,
              !context.bridgeServices.isSimulating,
              let scene = context.bridgeServices.activeScene(),
              let ecs = EditorBridgeInternals.ecsValue(context) else { return 0 }
        let meshString = meshHandle != nil ? String(cString: meshHandle!) : ""
        let entity = ecs.createEntity(name: "Mesh")
        _ = scene.transformAuthority.ensureLocalTransform(entity: entity,
                                                          default: TransformComponent(),
                                                          source: .editor)
        ecs.add(MeshRendererComponent(meshHandle: EditorBridgeInternals.assetHandleValue(meshString)), to: entity)
        EditorBridgeInternals.commitMutation(context, label: "EditorCommand")
        return EditorBridgeInternals.cStringWrite(entity.id.uuidString, to: outId, max: outIdSize)
    }

    static func createMeshEntityFromHandleWithMaterials(_ contextPtr: UnsafeRawPointer?, _ meshHandle: UnsafePointer<CChar>?, _ outId: UnsafeMutablePointer<CChar>?, _ outIdSize: Int32) -> Int32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              !context.bridgeServices.isPlaying,
              !context.bridgeServices.isSimulating,
              let scene = context.bridgeServices.activeScene(),
              let ecs = EditorBridgeInternals.ecsValue(context) else { return 0 }
        let meshString = meshHandle != nil ? String(cString: meshHandle!) : ""
        let meshHandleValue = EditorBridgeInternals.assetHandleValue(meshString)
        let entity = ecs.createEntity(name: "Mesh")
        _ = scene.transformAuthority.ensureLocalTransform(entity: entity,
                                                          default: TransformComponent(),
                                                          source: .editor)

        var submeshMaterials: [AssetHandle?]? = nil
        var primaryMaterial: AssetHandle? = nil
        if let meshHandleValue,
           let meshMetadata = EditorBridgeInternals.assetMetadataValue(for: meshHandleValue,
                                                                       snapshot: context.bridgeServices.assetMetadataSnapshot()),
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
        EditorBridgeInternals.commitMutation(context, label: "EditorCommand")
        return EditorBridgeInternals.cStringWrite(entity.id.uuidString, to: outId, max: outIdSize)
    }

    static func createLightEntity(_ contextPtr: UnsafeRawPointer?, _ lightType: Int32, _ outId: UnsafeMutablePointer<CChar>?, _ outIdSize: Int32) -> Int32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              !context.bridgeServices.isPlaying,
              !context.bridgeServices.isSimulating,
              let scene = context.bridgeServices.activeScene(),
              let ecs = EditorBridgeInternals.ecsValue(context) else { return 0 }
        let (entityName, lightTypeValue): (String, LightType) = {
            switch lightType {
            case 1: return ("Spot Light", .spot)
            case 2: return ("Directional Light", .directional)
            default: return ("Point Light", .point)
            }
        }()
        let entity = ecs.createEntity(name: entityName)
        _ = scene.transformAuthority.ensureLocalTransform(entity: entity,
                                                          default: TransformComponent(),
                                                          source: .editor)
        ecs.add(LightComponent(type: lightTypeValue), to: entity)
        EditorBridgeInternals.commitMutation(context, label: "EditorCommand")
        return EditorBridgeInternals.cStringWrite(entity.id.uuidString, to: outId, max: outIdSize)
    }

    static func createSkyEntity(_ contextPtr: UnsafeRawPointer?, _ outId: UnsafeMutablePointer<CChar>?, _ outIdSize: Int32) -> Int32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              !context.bridgeServices.isPlaying,
              !context.bridgeServices.isSimulating,
              let ecs = EditorBridgeInternals.ecsValue(context) else { return 0 }
        let entity = ecs.createEntity(name: "Sky")
        var sky = SkyLightComponent()
        sky.mode = .procedural
        sky.needsRebuild = true
        ecs.add(sky, to: entity)
        EditorBridgeInternals.setActiveSkyValue(ecs: ecs, entity: entity, logger: context.engineContext.log)
        EditorBridgeInternals.commitMutation(context, label: "EditorCommand")
        return EditorBridgeInternals.cStringWrite(entity.id.uuidString, to: outId, max: outIdSize)
    }

    static func createCameraEntity(_ contextPtr: UnsafeRawPointer?, _ outId: UnsafeMutablePointer<CChar>?, _ outIdSize: Int32) -> Int32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              !context.bridgeServices.isPlaying,
              !context.bridgeServices.isSimulating,
              let ecs = EditorBridgeInternals.ecsValue(context) else { return 0 }
        let entity = ecs.createEntity(name: "Camera")
        var component = CameraComponent(isPrimary: false, isEditor: false)
        if !EditorBridgeInternals.hasPrimaryRuntimeCameraValue(ecs: ecs) {
            component.isPrimary = true
        }
        ecs.add(component, to: entity)
        EditorBridgeInternals.commitMutation(context, label: "EditorCommand")
        return EditorBridgeInternals.cStringWrite(entity.id.uuidString, to: outId, max: outIdSize)
    }

    static func createCameraFromView(_ contextPtr: UnsafeRawPointer?, _ outId: UnsafeMutablePointer<CChar>?, _ outIdSize: Int32) -> Int32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              !context.bridgeServices.isPlaying,
              !context.bridgeServices.isSimulating,
              let scene = context.bridgeServices.activeScene(),
              let ecs = EditorBridgeInternals.ecsValue(context) else { return 0 }
        let entity = ecs.createEntity(name: "Camera")
        if let editorCamera = EditorBridgeInternals.findEditorCameraValue(ecs: ecs) {
            _ = scene.transformAuthority.ensureLocalTransform(entity: entity,
                                                              default: editorCamera.1,
                                                              source: .editor)
        }
        var component = EditorBridgeInternals.findEditorCameraValue(ecs: ecs)?.2 ?? CameraComponent()
        component.isEditor = false
        component.isPrimary = !EditorBridgeInternals.hasPrimaryRuntimeCameraValue(ecs: ecs)
        ecs.add(component, to: entity)
        EditorBridgeInternals.commitMutation(context, label: "EditorCommand")
        return EditorBridgeInternals.cStringWrite(entity.id.uuidString, to: outId, max: outIdSize)
    }

    static func duplicateSelectedEntities(_ contextPtr: UnsafeRawPointer?,
                                          _ outPrimaryId: UnsafeMutablePointer<CChar>?,
                                          _ outPrimaryIdSize: Int32) -> Int32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              !context.bridgeServices.isPlaying,
              !context.bridgeServices.isSimulating,
              let scene = context.bridgeServices.activeScene(),
              let ecs = EditorBridgeInternals.ecsValue(context) else { return 0 }

        let selected = context.bridgeServices.selectedEntityIds().compactMap { ecs.entity(with: $0) }
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
                cloneName = EditorBridgeInternals.makeUniqueCopyNameValue(originalName, existingLowerNames: existingNamesLower)
                existingNamesLower.insert(cloneName.lowercased())
            } else {
                cloneName = originalName
            }

            let clone = ecs.createEntity(name: cloneName)
            let components = EditorBridgeInternals.componentsDocumentValue(for: source, ecs: ecs)
            EditorBridgeInternals.applyComponentsDocumentValue(components, to: clone, scene: scene, ecs: ecs)
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
        context.bridgeServices.setSelectedEntityIds(newSelectionIds, primary: duplicatedRoots.last?.id)
        EditorBridgeInternals.commitMutation(context, label: "EditorCommand")
        if let primary = duplicatedRoots.last {
            return EditorBridgeInternals.cStringWrite(primary.id.uuidString, to: outPrimaryId, max: outPrimaryIdSize)
        }
        return 0
    }

    static func destroyEntity(_ contextPtr: UnsafeRawPointer?, _ entityId: UnsafePointer<CChar>?) {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              !context.bridgeServices.isPlaying,
              !context.bridgeServices.isSimulating,
              let ecs = EditorBridgeInternals.ecsValue(context),
              let entity = EditorBridgeInternals.entityValue(from: entityId, context: context) else { return }
        ecs.destroyEntity(entity)
        EditorBridgeInternals.commitMutation(context, label: "EditorCommand")
    }

    static func destroySelectedEntities(_ contextPtr: UnsafeRawPointer?) {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              !context.bridgeServices.isPlaying,
              !context.bridgeServices.isSimulating,
              let ecs = EditorBridgeInternals.ecsValue(context) else { return }
        let selected = context.bridgeServices.selectedEntityIds().compactMap { ecs.entity(with: $0) }
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
        context.bridgeServices.setSelectedEntityIds([], primary: nil)
        EditorBridgeInternals.commitMutation(context, label: "EditorCommand")
    }
}
