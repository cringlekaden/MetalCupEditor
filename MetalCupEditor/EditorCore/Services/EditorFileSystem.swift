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

    static func resourcesRootURL(preferredFolderName: String?) -> URL? {
        if let folder = preferredFolderName,
           let url = Bundle.main.url(forResource: folder, withExtension: nil) {
            return url.standardizedFileURL
        }

        if let bundleRoot = Bundle.main.resourceURL {
            let candidate = bundleRoot.appendingPathComponent(appName, isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate.standardizedFileURL
            }
        }

        if let appSupport = Bundle.main.url(forResource: "ApplicationSupport", withExtension: nil) {
            let candidate = appSupport.appendingPathComponent(appName, isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate.standardizedFileURL
            }
        }

        if let direct = Bundle.main.url(forResource: "ApplicationSupport/\(appName)", withExtension: nil),
           FileManager.default.fileExists(atPath: direct.path) {
            return direct.standardizedFileURL
        }

        return nil
    }

    static func defaultAssetsTemplateURL(resourcesRootURL: URL?) -> URL? {
        guard let resourcesRootURL else { return nil }
        let sandboxTemplate = resourcesRootURL
            .appendingPathComponent("Projects", isDirectory: true)
            .appendingPathComponent("Sandbox", isDirectory: true)
            .appendingPathComponent("Assets", isDirectory: true)
        if FileManager.default.fileExists(atPath: sandboxTemplate.path) {
            return sandboxTemplate.standardizedFileURL
        }
        return nil
    }

    static func seedBaseFromBundleIfNeeded(projectsRoot: URL) {
        let baseRoot = projectsRoot.deletingLastPathComponent().standardizedFileURL
        if let contents = try? FileManager.default.contentsOfDirectory(at: projectsRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]),
           !contents.isEmpty {
            return
        }
        guard let bundleRoot = resourcesRootURL(preferredFolderName: nil) else { return }

        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: bundleRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return
        }
        for item in items {
            let destination = baseRoot.appendingPathComponent(item.lastPathComponent, isDirectory: item.hasDirectoryPath)
            if fm.fileExists(atPath: destination.path) { continue }
            try? fm.copyItem(at: item, to: destination)
        }
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
