/// ProjectMigration.swift
/// Defines the ProjectMigration types and helpers for the editor.
/// Created by Kaden Cringle.

import Foundation
import MetalCupEngine

// Canonical project layout:
// Projects/
//   <ProjectName>/
//     Project.mcp
//     Assets/
//       Scenes/
//     Cache/
//     Intermediate/
//     Saved/
//
// Sanity checklist:
// - create new project -> correct folders
// - open existing project -> resolves assets
// - migrate old layout -> moves files, registry correct
// - add/delete asset -> meta + registry correct
// - serialization load -> no absolute paths

enum ProjectMigration {
    struct Result {
        let projectURL: URL
        let document: ProjectDocument
    }

    static func migrateRecentProjects(_ paths: [String], projectsRoot: URL) -> [String] {
        var updated: [String] = []
        for path in paths {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let migrated = migrateProjectIfNeeded(url: url, projectsRoot: projectsRoot) ?? url
            updated.append(migrated.path)
        }
        return updated
    }

    static func migrateProjectIfNeeded(url: URL, projectsRoot: URL) -> URL? {
        let standardized = url.standardizedFileURL
        let projectsRootPath = projectsRoot.standardizedFileURL.path

        if standardized.path.hasPrefix(projectsRootPath) {
            return standardized
        }

        let sourceFolder = standardized.deletingLastPathComponent()
        let projectName = standardized.deletingPathExtension().lastPathComponent
        let destinationFolder = uniqueDestination(for: projectsRoot.appendingPathComponent(projectName, isDirectory: true))

        if moveOrCopyItem(from: sourceFolder, to: destinationFolder) == false {
            return standardized
        }

        let migratedURL = destinationFolder.appendingPathComponent("Project.mcp")
        if !FileManager.default.fileExists(atPath: migratedURL.path) {
            let legacyURL = destinationFolder.appendingPathComponent(standardized.lastPathComponent)
            if FileManager.default.fileExists(atPath: legacyURL.path) {
                try? FileManager.default.moveItem(at: legacyURL, to: migratedURL)
            }
        }

        if let data = try? Data(contentsOf: migratedURL),
           let document = try? JSONDecoder().decode(ProjectDocument.self, from: data) {
            let normalized = migrateDocumentIfNeeded(document, projectURL: migratedURL, projectsRoot: projectsRoot)
            _ = saveProject(normalized, to: migratedURL)
        }

        return migratedURL
    }

    static func migrateDocumentIfNeeded(_ project: ProjectDocument, projectURL: URL, projectsRoot: URL) -> ProjectDocument {
        var updated = project
        let projectRoot = projectURL.deletingLastPathComponent().standardizedFileURL
        if updated.rootPath.isEmpty || updated.rootPath == "." || isAbsolutePath(updated.rootPath) {
            updated.rootPath = "."
        }

        if updated.assetDirectory.isEmpty || updated.assetDirectory == "." || updated.assetDirectory == "../Assets" {
            updated.assetDirectory = "Assets"
        }
        if updated.assetDirectory.hasPrefix("Assets/Assets") {
            updated.assetDirectory = "Assets"
        }
        if updated.scenesDirectory.isEmpty { updated.scenesDirectory = "Assets/Scenes" }
        if updated.cacheDirectory.isEmpty { updated.cacheDirectory = "Cache" }
        if updated.intermediateDirectory.isEmpty { updated.intermediateDirectory = "Intermediate" }
        if updated.savedDirectory.isEmpty { updated.savedDirectory = "Saved" }
        if updated.startScene.isEmpty { updated.startScene = "Assets/Scenes/Default.mcscene" }
        updated.layerNames = LayerCatalog.normalizedNames(updated.layerNames)

        if isAbsolutePath(updated.startScene) {
            if let rel = PathUtils.relativePath(from: projectRoot, to: URL(fileURLWithPath: updated.startScene)) {
                updated.startScene = rel
            }
        }

        migrateLooseAssetsIfNeeded(projectRoot: projectRoot)
        migrateNestedAssetsIfNeeded(projectRoot: projectRoot)
        migrateScenesToAssetsIfNeeded(projectRoot: projectRoot, project: &updated)

        updated.schemaVersion = ProjectSchema.currentVersion
        return updated
    }

    private static func migrateScenesToAssetsIfNeeded(projectRoot: URL, project: inout ProjectDocument) {
        let desiredScenesRel = "Assets/Scenes"
        let currentScenesRel = project.scenesDirectory.isEmpty ? "Scenes" : project.scenesDirectory
        if currentScenesRel == desiredScenesRel {
            project.scenesDirectory = desiredScenesRel
            if project.startScene.hasPrefix("Scenes/") {
                project.startScene = "Assets/Scenes/" + project.startScene.dropFirst("Scenes/".count)
            }
            return
        }

        let legacyURL = projectRoot.appendingPathComponent(currentScenesRel, isDirectory: true)
        let targetURL = projectRoot.appendingPathComponent(desiredScenesRel, isDirectory: true)

        var didMove = false
        if FileManager.default.fileExists(atPath: legacyURL.path) {
            PathUtils.ensureDirectoryExists(targetURL)
            if let enumerator = FileManager.default.enumerator(at: legacyURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                for case let url as URL in enumerator {
                    let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                    if values?.isDirectory == true { continue }
                    guard let relative = PathUtils.relativePath(from: legacyURL, to: url) else { continue }
                    let destination = targetURL.appendingPathComponent(relative)
                    PathUtils.ensureDirectoryExists(destination.deletingLastPathComponent())
                    if moveOrCopyItem(from: url, to: destination) {
                        didMove = true
                    }
                }
            }
        }

        project.scenesDirectory = desiredScenesRel
        if project.startScene.hasPrefix(currentScenesRel + "/") {
            let suffix = project.startScene.dropFirst(currentScenesRel.count + 1)
            project.startScene = desiredScenesRel + "/" + suffix
        } else if project.startScene.hasPrefix("Scenes/") {
            project.startScene = "Assets/Scenes/" + project.startScene.dropFirst("Scenes/".count)
        }

        if didMove {
            print("PROJECT_MIGRATION::Scenes -> Assets/Scenes")
        }
    }

    private static func migrateLooseAssetsIfNeeded(projectRoot: URL) {
        let assetsRoot = projectRoot.appendingPathComponent("Assets", isDirectory: true)
        if !FileManager.default.fileExists(atPath: assetsRoot.path) {
            PathUtils.ensureDirectoryExists(assetsRoot)
        }

        guard let contents = try? FileManager.default.contentsOfDirectory(at: projectRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return
        }

        let reserved: Set<String> = ["Assets", "Scenes", "Cache", "Intermediate", "Saved", "Project.mcp"]
        for item in contents {
            let name = item.lastPathComponent
            if reserved.contains(name) { continue }
            if name.hasSuffix(".mcp") { continue }
            if name.hasPrefix(".") { continue }

            let destination = uniqueDestination(for: assetsRoot.appendingPathComponent(name, isDirectory: item.hasDirectoryPath))
            if moveOrCopyItem(from: item, to: destination) {
                print("PROJECT_MIGRATION::Moved \(name) -> Assets/\(destination.lastPathComponent)")
            }
        }
    }

    private static func migrateNestedAssetsIfNeeded(projectRoot: URL) {
        let assetsRoot = projectRoot.appendingPathComponent("Assets", isDirectory: true)
        let nestedRoot = assetsRoot.appendingPathComponent("Assets", isDirectory: true)
        guard FileManager.default.fileExists(atPath: nestedRoot.path) else { return }

        guard let contents = try? FileManager.default.contentsOfDirectory(at: nestedRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return
        }

        var movedAny = false
        for item in contents {
            let destination = assetsRoot.appendingPathComponent(item.lastPathComponent, isDirectory: item.hasDirectoryPath)
            if FileManager.default.fileExists(atPath: destination.path) {
                EditorLogCenter.shared.logWarning("Assets repair skipped existing item: \(item.lastPathComponent)", category: .assets)
                continue
            }
            if moveOrCopyItem(from: item, to: destination) {
                movedAny = true
                EditorLogCenter.shared.logInfo("Assets repair moved: Assets/Assets/\(item.lastPathComponent) -> Assets/\(item.lastPathComponent)", category: .assets)
            }
        }

        if movedAny {
            let remaining = (try? FileManager.default.contentsOfDirectory(atPath: nestedRoot.path)) ?? []
            if remaining.isEmpty {
                try? FileManager.default.removeItem(at: nestedRoot)
            }
        }
    }

    private static func moveOrCopyItem(from source: URL, to destination: URL) -> Bool {
        do {
            try FileManager.default.moveItem(at: source, to: destination)
            return true
        } catch {
            do {
                try FileManager.default.copyItem(at: source, to: destination)
                return true
            } catch {
                EditorAlertCenter.shared.enqueueError("Failed to migrate item: \(error.localizedDescription)")
                return false
            }
        }
    }

    private static func uniqueDestination(for base: URL) -> URL {
        let fm = FileManager.default
        if !fm.fileExists(atPath: base.path) { return base }
        var suffix = 1
        while true {
            let candidate = base.deletingLastPathComponent()
                .appendingPathComponent("\(base.lastPathComponent)_migrated_\(suffix)")
            if !fm.fileExists(atPath: candidate.path) {
                return candidate
            }
            suffix += 1
        }
    }

    private static func isAbsolutePath(_ path: String) -> Bool {
        return path.hasPrefix("/")
    }

    private static func saveProject(_ project: ProjectDocument, to url: URL) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(project)
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            EditorAlertCenter.shared.enqueueError("Failed to save project: \(error.localizedDescription)")
            return false
        }
    }
}
