import Foundation
import MetalCupEngine

enum EditorComponentCommands {
    private enum BridgeComponentType: Int32 {
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

    static func entityHasComponent(_ contextPtr: UnsafeRawPointer?, _ entityId: UnsafePointer<CChar>?, _ componentType: Int32) -> UInt32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              let ecs = EditorBridgeInternals.ecsValue(context),
              let entity = EditorBridgeInternals.entityValue(from: entityId, context: context),
              let type = BridgeComponentType(rawValue: componentType) else { return 0 }
        switch type {
        case .name: return ecs.has(NameComponent.self, entity) ? 1 : 0
        case .transform: return ecs.has(TransformComponent.self, entity) ? 1 : 0
        case .meshRenderer: return ecs.has(MeshRendererComponent.self, entity) ? 1 : 0
        case .light: return ecs.has(LightComponent.self, entity) ? 1 : 0
        case .skyLight: return ecs.has(SkyLightComponent.self, entity) ? 1 : 0
        case .material: return ecs.has(MaterialComponent.self, entity) ? 1 : 0
        case .camera: return ecs.has(CameraComponent.self, entity) ? 1 : 0
        case .rigidbody: return ecs.has(RigidbodyComponent.self, entity) ? 1 : 0
        case .collider: return ecs.has(ColliderComponent.self, entity) ? 1 : 0
        case .script: return ecs.has(ScriptComponent.self, entity) ? 1 : 0
        case .characterController: return ecs.has(CharacterControllerComponent.self, entity) ? 1 : 0
        }
    }

    static func addComponent(_ contextPtr: UnsafeRawPointer?, _ entityId: UnsafePointer<CChar>?, _ componentType: Int32) -> UInt32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              !context.bridgeServices.isPlaying,
              !context.bridgeServices.isSimulating,
              let scene = context.bridgeServices.activeScene(),
              let ecs = EditorBridgeInternals.ecsValue(context),
              let entity = EditorBridgeInternals.entityValue(from: entityId, context: context),
              let type = BridgeComponentType(rawValue: componentType) else { return 0 }
        switch type {
        case .name:
            ecs.add(NameComponent(name: "Entity"), to: entity)
        case .transform:
            _ = scene.transformAuthority.ensureLocalTransform(entity: entity,
                                                              default: TransformComponent(),
                                                              source: .editor)
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
            if !EditorBridgeInternals.hasPrimaryRuntimeCameraValue(ecs: ecs) {
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
            ecs.add(CharacterControllerComponent(), to: entity)
        }
        EditorBridgeInternals.commitMutation(context, label: "EditorCommand")
        return 1
    }
}
