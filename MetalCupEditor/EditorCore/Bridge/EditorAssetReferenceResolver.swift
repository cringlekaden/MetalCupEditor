import Foundation
import MetalCupEngine

enum EditorAssetReferenceResolver {
    static func instantiatePrefabFromHandle(_ contextPtr: UnsafeRawPointer?,
                                            _ prefabHandle: UnsafePointer<CChar>?,
                                            _ outId: UnsafeMutablePointer<CChar>?,
                                            _ outIdSize: Int32) -> Int32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              !context.bridgeServices.isPlaying,
              !context.bridgeServices.isSimulating,
              let ecs = EditorBridgeInternals.ecsValue(context),
              let prefabHandle else { return 0 }
        _ = ecs
        let handleString = String(cString: prefabHandle)
        guard let url = EditorBridgeInternals.prefabURLValue(from: handleString, context: context) else { return 0 }
        guard let prefabHandleValue = EditorBridgeInternals.assetHandleValue(handleString) else { return 0 }
        do {
            let prefab = try PrefabSerializer.load(from: url)
            guard let scene = context.bridgeServices.activeScene() else { return 0 }
            let created = scene.instantiate(prefab: prefab, prefabHandle: prefabHandleValue)
            EditorBridgeInternals.commitMutation(context, label: "EditorCommand")
            if let first = created.first {
                return EditorBridgeInternals.cStringWrite(first.id.uuidString, to: outId, max: outIdSize)
            }
            return 0
        } catch {
            context.editorAlertCenter.enqueueError("Failed to instantiate prefab: \(error.localizedDescription)")
            return 0
        }
    }

    static func getPrefabInstanceInfo(_ contextPtr: UnsafeRawPointer?,
                                      _ entityId: UnsafePointer<CChar>?,
                                      _ prefabHandleOut: UnsafeMutablePointer<CChar>?,
                                      _ prefabHandleOutSize: Int32,
                                      _ prefabPathOut: UnsafeMutablePointer<CChar>?,
                                      _ prefabPathOutSize: Int32) -> UInt32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr),
              let resolved = EditorBridgeInternals.prefabInstanceValue(context, entityId) else { return 0 }
        let handleString = resolved.link.prefabHandle.rawValue.uuidString
        _ = EditorBridgeInternals.cStringWrite(handleString, to: prefabHandleOut, max: prefabHandleOutSize)

        let metadataPath = context.bridgeServices
            .assetMetadataSnapshot()
            .first(where: { $0.handle == resolved.link.prefabHandle })?
            .sourcePath
        let fallbackPath = context.bridgeServices.assetURL(for: resolved.link.prefabHandle)?.lastPathComponent
        _ = EditorBridgeInternals.cStringWrite(metadataPath ?? fallbackPath ?? "", to: prefabPathOut, max: prefabPathOutSize)
        return 1
    }
}
