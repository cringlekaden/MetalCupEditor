//
//  AssetAccessManager.swift
//  MetalCupEditor
//
//  Created by Engine Scaffolding
//

import AppKit
import Foundation

enum AssetAccessManager {
    private static let bookmarkKey = "MetalCupEditor.AssetRootBookmark"

    static func resolvedAssetsRoot(envOverride: String?) -> URL? {
        if let envOverride, let envURL = resolveEnvPath(envOverride) {
            return envURL
        }
        if let url = resolveBookmark() {
            return url
        }
        return nil
    }

    static func promptForAssetsRoot() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Select the MetalCup Assets folder"

        if panel.runModal() == .OK, let url = panel.url {
            if storeBookmark(for: url) {
                return url
            }
            return url
        }
        return nil
    }

    private static func resolveEnvPath(_ env: String) -> URL? {
        let expanded = NSString(string: env).expandingTildeInPath
        let candidate = URL(fileURLWithPath: expanded).standardizedFileURL
        let fm = FileManager.default

        func urlIfExists(_ url: URL) -> URL? {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                return url
            }
            return nil
        }

        if candidate.lastPathComponent == "Resources" {
            return urlIfExists(candidate.deletingLastPathComponent()) ?? candidate
        }

        if candidate.lastPathComponent == "Assets" {
            return urlIfExists(candidate)
        }

        let assetsChild = candidate.appendingPathComponent("Assets")
        if let url = urlIfExists(assetsChild) { return url }

        let editorAssets = candidate
            .appendingPathComponent("MetalCupEditor")
            .appendingPathComponent("MetalCupEditor")
            .appendingPathComponent("Assets")
        if let url = urlIfExists(editorAssets) { return url }

        return urlIfExists(candidate)
    }

    private static func storeBookmark(for url: URL) -> Bool {
        do {
            let data = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: bookmarkKey)
            return true
        } catch {
            return false
        }
    }

    private static func resolveBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
            if isStale {
                _ = storeBookmark(for: url)
            }
            _ = url.startAccessingSecurityScopedResource()
            return url
        } catch {
            return nil
        }
    }
}
