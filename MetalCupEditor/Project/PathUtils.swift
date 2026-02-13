/// PathUtils.swift
/// Defines the PathUtils types and helpers for the editor.
/// Created by Kaden Cringle.

import Foundation

enum PathUtils {
    static func normalizeURL(_ url: URL) -> URL {
        return url.standardizedFileURL
    }

    static func normalizePath(_ path: String) -> String {
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }

    static func isAbsolutePath(_ path: String) -> Bool {
        return path.hasPrefix("/")
    }

    static func ensureDirectoryExists(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    static func relativePath(from base: URL, to target: URL) -> String? {
        let basePath = base.standardizedFileURL.path
        let targetPath = target.standardizedFileURL.path
        if targetPath == basePath {
            return ""
        }
        guard targetPath.hasPrefix(basePath + "/") else { return nil }
        return String(targetPath.dropFirst(basePath.count + 1))
    }

    static func sanitizeRelativePath(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        if trimmed.hasPrefix("/") { return nil }
        let cleaned = trimmed.replacingOccurrences(of: "\\", with: "/")
        let parts = cleaned.split(separator: "/")
        for part in parts {
            if part == "." || part == ".." { return nil }
        }
        return parts.joined(separator: "/")
    }
}

struct ProjectPaths {
    let projectRoot: URL
    let assetsRoot: URL
    let scenesRoot: URL
    let cacheRoot: URL
    let intermediateRoot: URL
    let savedRoot: URL

    init(projectRoot: URL, document: ProjectDocument) {
        let root = projectRoot.standardizedFileURL
        let assetsRel = document.assetDirectory.isEmpty || document.assetDirectory == "." ? "Assets" : document.assetDirectory
        let scenesRel = document.scenesDirectory.isEmpty ? "Scenes" : document.scenesDirectory
        let cacheRel = document.cacheDirectory.isEmpty ? "Cache" : document.cacheDirectory
        let intermediateRel = document.intermediateDirectory.isEmpty ? "Intermediate" : document.intermediateDirectory
        let savedRel = document.savedDirectory.isEmpty ? "Saved" : document.savedDirectory

        self.projectRoot = root
        self.assetsRoot = root.appendingPathComponent(assetsRel, isDirectory: true)
        self.scenesRoot = root.appendingPathComponent(scenesRel, isDirectory: true)
        self.cacheRoot = root.appendingPathComponent(cacheRel, isDirectory: true)
        self.intermediateRoot = root.appendingPathComponent(intermediateRel, isDirectory: true)
        self.savedRoot = root.appendingPathComponent(savedRel, isDirectory: true)
    }

    func ensureDirectoriesExist() {
        PathUtils.ensureDirectoryExists(assetsRoot)
        PathUtils.ensureDirectoryExists(scenesRoot)
        PathUtils.ensureDirectoryExists(cacheRoot)
        PathUtils.ensureDirectoryExists(intermediateRoot)
        PathUtils.ensureDirectoryExists(savedRoot)
    }

    func makeAbsolute(relativeToAssets path: String) -> URL {
        return assetsRoot.appendingPathComponent(path)
    }

    func makeAbsolute(relativeToScenes path: String) -> URL {
        return scenesRoot.appendingPathComponent(path)
    }

    func makeAbsolute(relativeToProject path: String) -> URL {
        return projectRoot.appendingPathComponent(path)
    }

    func makeRelativeToAssets(absolute url: URL) -> String? {
        return PathUtils.relativePath(from: assetsRoot, to: url)
    }

    func makeRelativeToProject(absolute url: URL) -> String? {
        return PathUtils.relativePath(from: projectRoot, to: url)
    }
}
