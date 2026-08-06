/// ProjectLocationPolicy.swift
/// Keeps project ownership at the user-selected filesystem location.

import Foundation

enum ProjectLocationPolicy {
    struct CreationLocations: Equatable {
        let projectFolder: URL
        let projectDocument: URL
        let assetsFolder: URL
        let scenesFolder: URL
        let cacheFolder: URL
        let intermediateFolder: URL
        let savedFolder: URL
    }

    static func projectFolder(forSelectedProjectURL selectedURL: URL) -> URL {
        let standardized = selectedURL.standardizedFileURL
        if standardized.lastPathComponent == "Project.mcp" {
            return standardized.deletingLastPathComponent()
        }
        let projectName = standardized.deletingPathExtension().lastPathComponent
        return standardized.deletingLastPathComponent()
            .appendingPathComponent(projectName, isDirectory: true)
            .standardizedFileURL
    }

    static func canonicalProjectURL(forSelectedProjectURL selectedURL: URL) -> URL {
        projectFolder(forSelectedProjectURL: selectedURL)
            .appendingPathComponent("Project.mcp")
            .standardizedFileURL
    }

    static func creationLocations(forSelectedProjectURL selectedURL: URL) -> CreationLocations {
        let projectFolder = projectFolder(forSelectedProjectURL: selectedURL)
        let assetsFolder = projectFolder.appendingPathComponent("Assets", isDirectory: true)
        return CreationLocations(
            projectFolder: projectFolder,
            projectDocument: projectFolder.appendingPathComponent("Project.mcp").standardizedFileURL,
            assetsFolder: assetsFolder,
            scenesFolder: assetsFolder.appendingPathComponent("Scenes", isDirectory: true),
            cacheFolder: projectFolder.appendingPathComponent("Cache", isDirectory: true),
            intermediateFolder: projectFolder.appendingPathComponent("Intermediate", isDirectory: true),
            savedFolder: projectFolder.appendingPathComponent("Saved", isDirectory: true)
        )
    }

    @discardableResult
    static func createProjectDirectories(forSelectedProjectURL selectedURL: URL,
                                         fileManager: FileManager = .default) throws -> CreationLocations {
        let locations = creationLocations(forSelectedProjectURL: selectedURL)
        for directory in [
            locations.scenesFolder,
            locations.cacheFolder,
            locations.intermediateFolder,
            locations.savedFolder
        ] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return locations
    }

    static func openInPlaceURL(_ selectedURL: URL) -> URL {
        selectedURL.standardizedFileURL
    }

    static func resolvePortableProjectPath(_ relativePath: String,
                                           projectRoot: URL) -> URL? {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("/"),
              !trimmed.hasPrefix("~") else {
            return nil
        }

        let root = projectRoot.standardizedFileURL
        let resolved = root.appendingPathComponent(trimmed).standardizedFileURL
        guard resolved.path == root.path || resolved.path.hasPrefix(root.path + "/") else {
            return nil
        }
        return resolved
    }
}
