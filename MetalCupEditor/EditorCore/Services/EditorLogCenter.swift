/// EditorLogCenter.swift
/// Defines the EditorLogCenter types and helpers for the editor.
/// Created by Kaden Cringle.

import Foundation
import MetalCupEngine

typealias EditorLogLevel = MCLogLevel
typealias EditorLogCategory = MCLogCategory

final class EditorLogCenter {
    private let engineLog: EngineLog

    init(engineLog: EngineLog) {
        self.engineLog = engineLog
    }

    func log(_ message: String, level: EditorLogLevel, category: EditorLogCategory) {
        engineLog.log(message, level: level, category: category)
    }

    func logTrace(_ message: String, category: EditorLogCategory) {
        log(message, level: .debug, category: category)
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

    func revisionToken() -> UInt64 {
        return engineLog.revisionToken()
    }

    func clear() {
        engineLog.clear()
    }
}

@_cdecl("MCEEditorLogCount")
public func MCEEditorLogCount(_ contextPtr: UnsafeMutableRawPointer) -> Int32 {
    let context = Unmanaged<MCEContext>.fromOpaque(contextPtr).takeUnretainedValue()
    return Int32(context.engineContext.log.entryCount())
}

@_cdecl("MCEEditorLogEntryAt")
public func MCEEditorLogEntryAt(_ contextPtr: UnsafeMutableRawPointer,
                                _ index: Int32,
                                _ levelOut: UnsafeMutablePointer<Int32>?,
                                _ categoryOut: UnsafeMutablePointer<Int32>?,
                                _ timestampOut: UnsafeMutablePointer<Double>?,
                                _ messageBuffer: UnsafeMutablePointer<CChar>?,
                                _ messageBufferSize: Int32) -> UInt32 {
    guard index >= 0, let messageBuffer, messageBufferSize > 0 else { return 0 }
    let idx = Int(index)
    let context = Unmanaged<MCEContext>.fromOpaque(contextPtr).takeUnretainedValue()
    guard let entry = context.engineContext.log.entry(at: idx) else { return 0 }
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
public func MCEEditorLogRevision(_ contextPtr: UnsafeMutableRawPointer) -> UInt64 {
    let context = Unmanaged<MCEContext>.fromOpaque(contextPtr).takeUnretainedValue()
    return context.editorLogCenter.revisionToken()
}

@_cdecl("MCEEditorLogClear")
public func MCEEditorLogClear(_ contextPtr: UnsafeMutableRawPointer) {
    let context = Unmanaged<MCEContext>.fromOpaque(contextPtr).takeUnretainedValue()
    context.editorLogCenter.clear()
}

@_cdecl("MCEEditorLogMessage")
public func MCEEditorLogMessage(_ contextPtr: UnsafeMutableRawPointer,
                                _ level: Int32,
                                _ category: Int32,
                                _ message: UnsafePointer<CChar>?) {
    guard let message else { return }
    let value = String(cString: message)
    let resolvedLevel = EditorLogLevel(rawValue: level) ?? .info
    let resolvedCategory = EditorLogCategory(rawValue: category) ?? .editor
    let context = Unmanaged<MCEContext>.fromOpaque(contextPtr).takeUnretainedValue()
    context.editorLogCenter.log(value, level: resolvedLevel, category: resolvedCategory)
}
