import Foundation
import MetalCupEngine

enum EditorSelectionCommands {
    static func setSelectedEntitiesCSV(_ contextPtr: UnsafeRawPointer?,
                                       _ csv: UnsafePointer<CChar>?,
                                       _ primaryId: UnsafePointer<CChar>?) {
        EditorBridgeInternals.markFacadeInvocation("EditorSelectionCommands.setSelectedEntitiesCSV")
        guard let context = EditorBridgeInternals.contextValue(contextPtr) else { return }
        let requested = EditorBridgeInternals.entityIdsFromCSV(csv)
        guard let scene = context.bridgeServices.activeScene() else {
            context.bridgeServices.setSelectedEntityIds([], primary: nil)
            return
        }
        var filtered: [UUID] = []
        filtered.reserveCapacity(requested.count)
        for id in requested where scene.ecs.entity(with: id) != nil {
            filtered.append(id)
        }
        let primary = primaryId.flatMap { UUID(uuidString: String(cString: $0)) }
        context.bridgeServices.setSelectedEntityIds(filtered, primary: primary)
    }
}
