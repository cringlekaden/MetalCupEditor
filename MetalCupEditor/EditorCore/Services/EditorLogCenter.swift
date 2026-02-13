/// EditorLogCenter.swift
/// Defines the EditorLogCenter types and helpers for the editor.
/// Created by Kaden Cringle.

import Foundation

enum EditorLogLevel: Int32 {
    case trace = 0
    case info = 1
    case warning = 2
    case error = 3
}

enum EditorLogCategory: Int32 {
    case editor = 0
    case project = 1
    case scene = 2
    case assets = 3
    case renderer = 4
    case serialization = 5
    case input = 6

    var label: String {
        switch self {
        case .editor: return "Editor"
        case .project: return "Project"
        case .scene: return "Scene"
        case .assets: return "Assets"
        case .renderer: return "Renderer"
        case .serialization: return "Serialization"
        case .input: return "Input"
        }
    }
}

struct EditorLogEntry {
    let timestamp: TimeInterval
    let level: EditorLogLevel
    let category: EditorLogCategory
    let message: String
}

final class EditorLogCenter {
    static let shared = EditorLogCenter()

    private let queue = DispatchQueue(label: "MetalCupEditor.LogCenter")
    private var entries: [EditorLogEntry] = []
    private let maxEntries = 5000
    private var revision: UInt64 = 0

    private init() {}

    func log(_ message: String, level: EditorLogLevel, category: EditorLogCategory) {
        let entry = EditorLogEntry(timestamp: Date().timeIntervalSince1970, level: level, category: category, message: message)
        queue.async {
            self.entries.append(entry)
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }
            self.revision &+= 1
        }
    }

    func logTrace(_ message: String, category: EditorLogCategory) {
        log(message, level: .trace, category: category)
    }

    func logInfo(_ message: String, category: EditorLogCategory) {
        log(message, level: .info, category: category)
    }

    func logWarning(_ message: String, category: EditorLogCategory) {
        log(message, level: .warning, category: category)
    }

    func logError(_ message: String, category: EditorLogCategory) {
        log(message, level: .error, category: category)
    }

    func snapshot() -> [EditorLogEntry] {
        return queue.sync {
            entries
        }
    }

    func revisionToken() -> UInt64 {
        return queue.sync {
            revision
        }
    }

    func clear() {
        queue.async {
            self.entries.removeAll()
            self.revision &+= 1
        }
    }
}

private enum LogSnapshotStore {
    static var entries: [EditorLogEntry] = []
    static var revision: UInt64 = 0
}

private func refreshLogSnapshotIfNeeded() {
    let revision = EditorLogCenter.shared.revisionToken()
    if revision == LogSnapshotStore.revision { return }
    LogSnapshotStore.entries = EditorLogCenter.shared.snapshot()
    LogSnapshotStore.revision = revision
}

@_cdecl("MCEEditorLogCount")
public func MCEEditorLogCount() -> Int32 {
    refreshLogSnapshotIfNeeded()
    return Int32(LogSnapshotStore.entries.count)
}

@_cdecl("MCEEditorLogEntryAt")
public func MCEEditorLogEntryAt(_ index: Int32,
                                _ levelOut: UnsafeMutablePointer<Int32>?,
                                _ categoryOut: UnsafeMutablePointer<Int32>?,
                                _ timestampOut: UnsafeMutablePointer<Double>?,
                                _ messageBuffer: UnsafeMutablePointer<CChar>?,
                                _ messageBufferSize: Int32) -> UInt32 {
    guard index >= 0, let messageBuffer, messageBufferSize > 0 else { return 0 }
    let idx = Int(index)
    guard idx >= 0, idx < LogSnapshotStore.entries.count else { return 0 }
    let entry = LogSnapshotStore.entries[idx]
    levelOut?.pointee = entry.level.rawValue
    categoryOut?.pointee = entry.category.rawValue
    timestampOut?.pointee = entry.timestamp
    let length = min(Int(messageBufferSize - 1), entry.message.count)
    entry.message.withCString { ptr in
        if length > 0 {
            memcpy(messageBuffer, ptr, length)
        }
    }
    messageBuffer[length] = 0
    return 1
}

@_cdecl("MCEEditorLogRevision")
public func MCEEditorLogRevision() -> UInt64 {
    EditorLogCenter.shared.revisionToken()
}

@_cdecl("MCEEditorLogClear")
public func MCEEditorLogClear() {
    EditorLogCenter.shared.clear()
}

@_cdecl("MCEEditorLogMessage")
public func MCEEditorLogMessage(_ level: Int32, _ category: Int32, _ message: UnsafePointer<CChar>?) {
    guard let message else { return }
    let value = String(cString: message)
    let resolvedLevel = EditorLogLevel(rawValue: level) ?? .info
    let resolvedCategory = EditorLogCategory(rawValue: category) ?? .editor
    EditorLogCenter.shared.log(value, level: resolvedLevel, category: resolvedCategory)
}
