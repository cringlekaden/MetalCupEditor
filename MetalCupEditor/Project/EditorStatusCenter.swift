import Foundation

enum EditorStatusKind: Int32 {
    case info = 0
    case warning = 1
    case error = 2
}

struct EditorStatusMessage {
    let kind: EditorStatusKind
    let message: String
}

final class EditorStatusCenter {
    static let shared = EditorStatusCenter()

    private var messages: [EditorStatusMessage] = []

    private init() {}

    func enqueue(_ message: String, kind: EditorStatusKind) {
        messages.append(EditorStatusMessage(kind: kind, message: message))
    }

    func enqueueInfo(_ message: String) {
        enqueue(message, kind: .info)
    }

    func enqueueWarning(_ message: String) {
        enqueue(message, kind: .warning)
    }

    func enqueueError(_ message: String) {
        enqueue(message, kind: .error)
    }

    func popNext() -> EditorStatusMessage? {
        if messages.isEmpty { return nil }
        return messages.removeFirst()
    }
}

@_cdecl("MCEEditorPopNextStatus")
public func MCEEditorPopNextStatus(_ buffer: UnsafeMutablePointer<CChar>?, _ bufferSize: Int32, _ kindOut: UnsafeMutablePointer<Int32>?) -> UInt32 {
    guard let buffer, bufferSize > 0 else { return 0 }
    guard let status = EditorStatusCenter.shared.popNext() else { return 0 }
    let message = status.message
    let copied = message.withCString { ptr -> Int in
        let length = min(Int(bufferSize - 1), strlen(ptr))
        if length > 0 {
            memcpy(buffer, ptr, length)
        }
        buffer[length] = 0
        return length
    }
    if copied > 0 {
        kindOut?.pointee = status.kind.rawValue
        return 1
    }
    return 0
}
