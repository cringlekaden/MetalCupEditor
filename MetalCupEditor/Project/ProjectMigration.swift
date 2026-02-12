import Foundation

// Canonical project layout:
// Projects/
//   <ProjectName>/
//     Project.mcp
//     Assets/
//     Scenes/
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
        if updated.scenesDirectory.isEmpty { updated.scenesDirectory = "Scenes" }
        if updated.cacheDirectory.isEmpty { updated.cacheDirectory = "Cache" }
        if updated.intermediateDirectory.isEmpty { updated.intermediateDirectory = "Intermediate" }
        if updated.savedDirectory.isEmpty { updated.savedDirectory = "Saved" }
        if updated.startScene.isEmpty { updated.startScene = "Scenes/Default.scene" }

        if isAbsolutePath(updated.startScene) {
            if let rel = PathUtils.relativePath(from: projectRoot, to: URL(fileURLWithPath: updated.startScene)) {
                updated.startScene = rel
            }
        }

        migrateLooseAssetsIfNeeded(projectRoot: projectRoot)

        updated.schemaVersion = ProjectSchema.currentVersion
        return updated
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
