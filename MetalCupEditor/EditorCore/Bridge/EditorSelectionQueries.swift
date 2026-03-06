import Foundation
import MetalCupEngine

enum EditorSelectionQueries {
    static func getSelectedEntityCount(_ contextPtr: UnsafeRawPointer?) -> Int32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr) else { return 0 }
        return Int32(context.bridgeServices.selectedEntityIds().count)
    }

    static func getSelectedEntityIdAt(_ contextPtr: UnsafeRawPointer?,
                                      _ index: Int32,
                                      _ buffer: UnsafeMutablePointer<CChar>?,
                                      _ bufferSize: Int32) -> Int32 {
        guard let context = EditorBridgeInternals.contextValue(contextPtr), index >= 0 else { return 0 }
        let ids = context.bridgeServices.selectedEntityIds()
        guard index < Int32(ids.count) else { return 0 }
        return EditorBridgeInternals.cStringWrite(ids[Int(index)].uuidString, to: buffer, max: bufferSize)
    }

}
