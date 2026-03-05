import Foundation
import MetalCupEngine

enum EditorSceneQueries {
    static func getEntityCount(_ contextPtr: UnsafeRawPointer?) -> Int32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr), let ecs = EditorBridgeInternals.ecsValue(context) else { return 0 }
        return Int32(ecs.allEntities().count)
    }

    static func getRootEntityCount(_ contextPtr: UnsafeRawPointer?) -> Int32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr), let ecs = EditorBridgeInternals.ecsValue(context) else { return 0 }
        return Int32(ecs.rootLevelEntities().count)
    }

    static func getRootEntityIdAt(_ contextPtr: UnsafeRawPointer?, _ index: Int32,
                                  _ buffer: UnsafeMutablePointer<CChar>?, _ bufferSize: Int32) -> Int32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr), let ecs = EditorBridgeInternals.ecsValue(context), index >= 0 else { return 0 }
        let roots = ecs.rootLevelEntities()
        guard index < Int32(roots.count) else { return 0 }
        return EditorBridgeInternals.cStringWrite(roots[Int(index)].id.uuidString, to: buffer, max: bufferSize)
    }

    static func getChildEntityCount(_ contextPtr: UnsafeRawPointer?, _ parentId: UnsafePointer<CChar>?) -> Int32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              let ecs = EditorBridgeInternals.ecsValue(context),
              let parent = EditorBridgeInternals.entityValue(from: parentId, context: context) else { return 0 }
        return Int32(ecs.getChildren(parent).count)
    }

    static func getChildEntityIdAt(_ contextPtr: UnsafeRawPointer?, _ parentId: UnsafePointer<CChar>?, _ index: Int32,
                                   _ buffer: UnsafeMutablePointer<CChar>?, _ bufferSize: Int32) -> Int32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              let ecs = EditorBridgeInternals.ecsValue(context),
              let parent = EditorBridgeInternals.entityValue(from: parentId, context: context),
              index >= 0 else { return 0 }
        let children = ecs.getChildren(parent)
        guard index < Int32(children.count) else { return 0 }
        return EditorBridgeInternals.cStringWrite(children[Int(index)].id.uuidString, to: buffer, max: bufferSize)
    }

    static func getParentEntityId(_ contextPtr: UnsafeRawPointer?, _ childId: UnsafePointer<CChar>?,
                                  _ buffer: UnsafeMutablePointer<CChar>?, _ bufferSize: Int32) -> Int32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              let ecs = EditorBridgeInternals.ecsValue(context),
              let child = EditorBridgeInternals.entityValue(from: childId, context: context),
              let parent = ecs.getParent(child) else { return 0 }
        return EditorBridgeInternals.cStringWrite(parent.id.uuidString, to: buffer, max: bufferSize)
    }

    static func getEntityIdAt(_ contextPtr: UnsafeRawPointer?, _ index: Int32,
                              _ buffer: UnsafeMutablePointer<CChar>?, _ bufferSize: Int32) -> Int32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr), let ecs = EditorBridgeInternals.ecsValue(context), index >= 0 else { return 0 }
        let entities = ecs.allEntities()
        guard index < Int32(entities.count) else { return 0 }
        return EditorBridgeInternals.cStringWrite(entities[Int(index)].id.uuidString, to: buffer, max: bufferSize)
    }

    static func getEntityName(_ contextPtr: UnsafeRawPointer?, _ entityId: UnsafePointer<CChar>?,
                              _ buffer: UnsafeMutablePointer<CChar>?, _ bufferSize: Int32) -> Int32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              let ecs = EditorBridgeInternals.ecsValue(context),
              let entity = EditorBridgeInternals.entityValue(from: entityId, context: context) else { return 0 }
        let name = ecs.get(NameComponent.self, for: entity)?.name ?? ""
        return EditorBridgeInternals.cStringWrite(name, to: buffer, max: bufferSize)
    }

    static func entityExists(_ contextPtr: UnsafeRawPointer?, _ entityId: UnsafePointer<CChar>?) -> UInt32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr), let _ = EditorBridgeInternals.entityValue(from: entityId, context: context) else { return 0 }
        return 1
    }

    static func getColliderEntityCount(_ contextPtr: UnsafeRawPointer?) -> Int32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr), let ecs = EditorBridgeInternals.ecsValue(context) else { return 0 }
        let count = ecs.allEntities().filter { ecs.get(ColliderComponent.self, for: $0) != nil }.count
        return Int32(count)
    }

    static func getColliderEntityAt(_ contextPtr: UnsafeRawPointer?, _ index: Int32,
                                    _ buffer: UnsafeMutablePointer<CChar>?, _ bufferSize: Int32) -> UInt32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr), let ecs = EditorBridgeInternals.ecsValue(context), let buffer, bufferSize > 0 else { return 0 }
        let colliders = ecs.allEntities().filter { ecs.get(ColliderComponent.self, for: $0) != nil }
        guard index >= 0, index < Int32(colliders.count) else { return 0 }
        return EditorBridgeInternals.cStringWrite(colliders[Int(index)].id.uuidString, to: buffer, max: bufferSize) > 0 ? 1 : 0
    }

    static func getModelMatrix(_ contextPtr: UnsafeRawPointer?, _ entityId: UnsafePointer<CChar>?,
                               _ matrixOut: UnsafeMutablePointer<Float>?) -> UInt32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              let ecs = EditorBridgeInternals.ecsValue(context),
              let entity = EditorBridgeInternals.entityValue(from: entityId, context: context),
              ecs.get(TransformComponent.self, for: entity) != nil,
              let matrixOut else { return 0 }
        EditorBridgeInternals.matrixWrite(ecs.worldMatrix(for: entity), to: matrixOut)
        return 1
    }

    static func getEditorCameraMatrices(_ contextPtr: UnsafeRawPointer?, _ viewOut: UnsafeMutablePointer<Float>?,
                                        _ projectionOut: UnsafeMutablePointer<Float>?) -> UInt32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr), let scene = context.editorSceneController.activeScene() else { return 0 }
        let matrices = SceneRenderer.cameraMatrices(scene: scene)
        if let viewOut { EditorBridgeInternals.matrixWrite(matrices.view, to: viewOut) }
        if let projectionOut { EditorBridgeInternals.matrixWrite(matrices.projection, to: projectionOut) }
        return 1
    }
}
