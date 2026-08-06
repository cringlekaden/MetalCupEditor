/// EditorFileSystem.swift
/// Defines the EditorFileSystem types and helpers for the editor.
/// Created by Kaden Cringle.

import Foundation

enum EditorFileSystem {
    static let appName = "MetalCupEditor"
    static let projectsFolderName = "Projects"

    static func appSupportRootURL(ensureExists: Bool = true) -> URL? {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let root = appSupport?.appendingPathComponent(appName, isDirectory: true) else { return nil }
        if ensureExists {
            PathUtils.ensureDirectoryExists(root)
        }
        return root.standardizedFileURL
    }

    static func projectsRootURL(ensureExists: Bool = true) -> URL? {
        guard let base = appSupportRootURL(ensureExists: ensureExists) else { return nil }
        let projects = base.appendingPathComponent(projectsFolderName, isDirectory: true)
        if ensureExists {
            PathUtils.ensureDirectoryExists(projects)
        }
        return projects.standardizedFileURL
    }

    static func editorSettingsURL() -> URL {
        let fallback = URL(fileURLWithPath: NSTemporaryDirectory())
        let base = appSupportRootURL(ensureExists: true) ?? fallback
        return base.appendingPathComponent("EditorSettings.json")
    }

    static func imguiConfigURL() -> URL? {
        guard let base = appSupportRootURL(ensureExists: true) else { return nil }
        return base.appendingPathComponent("imgui.ini")
    }

}
@_cdecl("MCEEditorGetImGuiIniPath")
public func MCEEditorGetImGuiIniPath(_ contextPtr: UnsafeRawPointer?,
                                     _ buffer: UnsafeMutablePointer<CChar>?,
                                     _ bufferSize: Int32) -> UInt32 {
    guard let buffer, bufferSize > 0 else { return 0 }
    guard let url = EditorFileSystem.imguiConfigURL() else { return 0 }
    let path = url.path
    return path.withCString { ptr in
        let length = min(Int(bufferSize - 1), strlen(ptr))
        if length > 0 { memcpy(buffer, ptr, length) }
        buffer[length] = 0
        return 1
    }
}
