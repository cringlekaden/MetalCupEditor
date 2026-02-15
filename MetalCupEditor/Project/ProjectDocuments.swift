/// ProjectDocuments.swift
/// Defines the ProjectDocuments types and helpers for the editor.
/// Created by Kaden Cringle.

import Foundation
import MetalCupEngine

enum ProjectSchema {
    static let currentVersion: Int = 4
}

struct ProjectDocument: Codable {
    var schemaVersion: Int
    var id: UUID
    var name: String
    var rootPath: String
    var assetDirectory: String
    var scenesDirectory: String
    var cacheDirectory: String
    var intermediateDirectory: String
    var savedDirectory: String
    var startScene: String
    var layerNames: [String]

    init(
        schemaVersion: Int = ProjectSchema.currentVersion,
        id: UUID = UUID(),
        name: String,
        rootPath: String,
        assetDirectory: String,
        scenesDirectory: String,
        cacheDirectory: String,
        intermediateDirectory: String,
        savedDirectory: String,
        startScene: String,
        layerNames: [String] = LayerCatalog.defaultNames()
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.rootPath = rootPath
        self.assetDirectory = assetDirectory
        self.scenesDirectory = scenesDirectory
        self.cacheDirectory = cacheDirectory
        self.intermediateDirectory = intermediateDirectory
        self.savedDirectory = savedDirectory
        self.startScene = startScene
        self.layerNames = LayerCatalog.normalizedNames(layerNames)
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case name
        case rootPath
        case assetDirectory
        case scenesDirectory
        case cacheDirectory
        case intermediateDirectory
        case savedDirectory
        case startScene
        case layerNames
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? ProjectSchema.currentVersion
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        rootPath = try container.decodeIfPresent(String.self, forKey: .rootPath) ?? "."
        assetDirectory = try container.decodeIfPresent(String.self, forKey: .assetDirectory) ?? "Assets"
        scenesDirectory = try container.decodeIfPresent(String.self, forKey: .scenesDirectory) ?? "Assets/Scenes"
        cacheDirectory = try container.decodeIfPresent(String.self, forKey: .cacheDirectory) ?? "Cache"
        intermediateDirectory = try container.decodeIfPresent(String.self, forKey: .intermediateDirectory) ?? "Intermediate"
        savedDirectory = try container.decodeIfPresent(String.self, forKey: .savedDirectory) ?? "Saved"
        startScene = try container.decodeIfPresent(String.self, forKey: .startScene) ?? "Assets/Scenes/Default.mcscene"
        let decodedNames = try container.decodeIfPresent([String].self, forKey: .layerNames) ?? LayerCatalog.defaultNames()
        layerNames = LayerCatalog.normalizedNames(decodedNames)
    }
}

struct EditorStateDocument: Codable {
    var schemaVersion: Int
    var lastOpenedScenePath: String
    var viewportWidth: Double
    var viewportHeight: Double

    init(
        schemaVersion: Int = 1,
        lastOpenedScenePath: String,
        viewportWidth: Double = 0,
        viewportHeight: Double = 0
    ) {
        self.schemaVersion = schemaVersion
        self.lastOpenedScenePath = lastOpenedScenePath
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
    }
}
