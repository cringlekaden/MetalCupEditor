/// ProjectDocuments.swift
/// Defines the ProjectDocuments types and helpers for the editor.
/// Created by Kaden Cringle.

import Foundation
import MetalCupEngine

enum ProjectSchema {
    static let currentVersion: Int = 6
}

struct ProjectRenderSettingsDocument: Codable, Equatable {
    var exposure: ExposureSettings

    init(exposure: ExposureSettings = ExposurePolicyResolver.engineFallback) {
        self.exposure = exposure
    }
}

enum ProjectShaderSource: Codable, Equatable {
    case canonical
    case projectOverride(path: String)

    private enum CodingKeys: String, CodingKey {
        case mode
        case path
    }

    private enum Mode: String, Codable {
        case canonical
        case projectOverride
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mode = try container.decodeIfPresent(Mode.self, forKey: .mode) ?? .canonical
        switch mode {
        case .canonical:
            self = .canonical
        case .projectOverride:
            self = .projectOverride(
                path: try container.decodeIfPresent(String.self, forKey: .path) ?? "Assets/Shaders"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .canonical:
            try container.encode(Mode.canonical, forKey: .mode)
        case .projectOverride(let path):
            try container.encode(Mode.projectOverride, forKey: .mode)
            try container.encode(path, forKey: .path)
        }
    }
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
    var shaderSource: ProjectShaderSource
    var renderSettings: ProjectRenderSettingsDocument

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
        layerNames: [String] = LayerCatalog.defaultNames(),
        shaderSource: ProjectShaderSource = .canonical,
        renderSettings: ProjectRenderSettingsDocument = ProjectRenderSettingsDocument()
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
        self.shaderSource = shaderSource
        self.renderSettings = renderSettings
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
        case shaderSource
        case renderSettings
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
        shaderSource = try container.decodeIfPresent(ProjectShaderSource.self, forKey: .shaderSource) ?? .canonical
        renderSettings = try container.decodeIfPresent(ProjectRenderSettingsDocument.self, forKey: .renderSettings)
            ?? ProjectRenderSettingsDocument()
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
