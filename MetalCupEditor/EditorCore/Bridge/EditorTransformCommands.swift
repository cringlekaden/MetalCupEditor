import Foundation
import MetalCupEngine
import simd

enum EditorTransformCommands {
    static func getTransform(_ contextPtr: UnsafeRawPointer?,
                             _ entityId: UnsafePointer<CChar>?,
                             _ px: UnsafeMutablePointer<Float>?, _ py: UnsafeMutablePointer<Float>?, _ pz: UnsafeMutablePointer<Float>?,
                             _ rx: UnsafeMutablePointer<Float>?, _ ry: UnsafeMutablePointer<Float>?, _ rz: UnsafeMutablePointer<Float>?,
                             _ sx: UnsafeMutablePointer<Float>?, _ sy: UnsafeMutablePointer<Float>?, _ sz: UnsafeMutablePointer<Float>?) -> UInt32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              let ecs = EditorBridgeInternals.ecsValue(context),
              let entity = EditorBridgeInternals.entityValue(from: entityId, context: context),
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

    static func setTransform(_ contextPtr: UnsafeRawPointer?, _ entityId: UnsafePointer<CChar>?,
                             _ px: Float, _ py: Float, _ pz: Float,
                             _ rx: Float, _ ry: Float, _ rz: Float,
                             _ sx: Float, _ sy: Float, _ sz: Float) {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              !context.editorSceneController.isPlaying,
              let scene = context.editorSceneController.activeScene(),
              let entity = EditorBridgeInternals.entityValue(from: entityId, context: context) else { return }
        let transform = TransformComponent(
            position: SIMD3<Float>(px, py, pz),
            rotation: TransformMath.quaternionFromEulerXYZ(SIMD3<Float>(rx, ry, rz)),
            scale: SIMD3<Float>(sx, sy, sz)
        )
        _ = scene.transformAuthority.setLocalTransform(entity: entity, transform: transform, source: .editor)
        context.editorProjectManager.notifySceneMutation()
    }

    static func setTransformFromMatrix(_ contextPtr: UnsafeRawPointer?,
                                       _ entityId: UnsafePointer<CChar>?,
                                       _ matrix: UnsafePointer<Float>?) -> UInt32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              !context.editorSceneController.isPlaying,
              let scene = context.editorSceneController.activeScene(),
              let entity = EditorBridgeInternals.entityValue(from: entityId, context: context),
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

        let worldMatrix = EditorBridgeInternals.matrixRead(from: matrix)
        let worldTransform = TransformMath.decomposeMatrix(worldMatrix)
        guard EditorBridgeInternals.finite(worldTransform.position),
              EditorBridgeInternals.finite(worldTransform.rotation),
              EditorBridgeInternals.finite(worldTransform.scale) else {
            return 0
        }
        let transform = TransformComponent(position: worldTransform.position,
                                           rotation: worldTransform.rotation,
                                           scale: worldTransform.scale)
        _ = scene.transformAuthority.setWorldTransform(entity: entity, transform: transform, source: .editor)
        context.editorProjectManager.notifySceneMutation()
        return 1
    }
}
