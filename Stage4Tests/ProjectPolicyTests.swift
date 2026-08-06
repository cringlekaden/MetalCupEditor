import Foundation
import MetalCupEngine

@main
struct ProjectPolicyTests {
    static func main() throws {
        try missingShaderSettingDefaultsToCanonical()
        try explicitShaderOverrideDecodes()
        try newProjectUsesSelectedParent()
        try externalProjectOpensInPlace()
        try portableOverridePathsStayInsideProject()
        try validationProjectIsCanonical()
        try phase2ValidationLabScenesDecode()
        try phase3ValidationLabScenesDecode()
        print("Stage 4 Editor policy tests passed")
    }

    private static func missingShaderSettingDefaultsToCanonical() throws {
        let data = Data(#"{"name":"Legacy","rootPath":".","assetDirectory":"Assets","scenesDirectory":"Assets/Scenes","cacheDirectory":"Cache","intermediateDirectory":"Intermediate","savedDirectory":"Saved","startScene":"Assets/Scenes/Default.mcscene"}"#.utf8)
        let document = try JSONDecoder().decode(ProjectDocument.self, from: data)
        require(document.shaderSource == .canonical, "Missing shaderSource must decode as canonical")
    }

    private static func explicitShaderOverrideDecodes() throws {
        let data = Data(#"{"name":"Override","shaderSource":{"mode":"projectOverride","path":"Assets/Shaders"}}"#.utf8)
        let document = try JSONDecoder().decode(ProjectDocument.self, from: data)
        require(
            document.shaderSource == .projectOverride(path: "Assets/Shaders"),
            "Explicit project override must preserve its portable path"
        )
    }

    private static func newProjectUsesSelectedParent() throws {
        let root = temporaryDirectory(named: "NewProject")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let selected = root.appendingPathComponent("ChosenLocation.mcp")
        let locations = try ProjectLocationPolicy.createProjectDirectories(
            forSelectedProjectURL: selected
        )

        require(
            locations.projectFolder == root.appendingPathComponent("ChosenLocation").standardizedFileURL,
            "New project folder must be created under the selected parent"
        )
        require(locations.projectDocument.lastPathComponent == "Project.mcp", "Project document must use the canonical filename")
        for directory in [locations.assetsFolder, locations.scenesFolder, locations.cacheFolder, locations.intermediateFolder, locations.savedFolder] {
            var isDirectory: ObjCBool = false
            require(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) && isDirectory.boolValue,
                    "Expected project directory at \(directory.path)")
        }
    }

    private static func externalProjectOpensInPlace() throws {
        let root = temporaryDirectory(named: "OpenInPlace")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sentinel = root.appendingPathComponent("sentinel.txt")
        try Data("unchanged".utf8).write(to: sentinel)
        let project = root.appendingPathComponent("Project.mcp")
        try Data("{}".utf8).write(to: project)

        let resolved = ProjectLocationPolicy.openInPlaceURL(project)
        require(resolved == project.standardizedFileURL, "External project URL must be returned in place")
        let sentinelContents = try String(contentsOf: sentinel, encoding: .utf8)
        require(sentinelContents == "unchanged", "Opening in place must not alter sibling content")
        require(FileManager.default.fileExists(atPath: project.path), "Opening in place must not move the project document")
    }

    private static func portableOverridePathsStayInsideProject() throws {
        let root = temporaryDirectory(named: "PortablePaths")
        let valid = ProjectLocationPolicy.resolvePortableProjectPath("Assets/Shaders", projectRoot: root)
        require(valid == root.appendingPathComponent("Assets/Shaders").standardizedFileURL,
                "Portable shader path must resolve inside the project")
        require(ProjectLocationPolicy.resolvePortableProjectPath("../Shaders", projectRoot: root) == nil,
                "Parent traversal must be rejected")
        require(ProjectLocationPolicy.resolvePortableProjectPath("/tmp/Shaders", projectRoot: root) == nil,
                "Absolute shader path must be rejected")
    }

    private static func validationProjectIsCanonical() throws {
        guard CommandLine.arguments.count == 2 else {
            throw TestFailure("Pass the RendererValidation directory as the only argument")
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).standardizedFileURL
        let data = try Data(contentsOf: root.appendingPathComponent("Project.mcp"))
        let project = try JSONDecoder().decode(ProjectDocument.self, from: data)
        require(project.shaderSource == .canonical, "Validation project must explicitly use canonical shaders")
        require(project.rootPath == ".", "Validation project root must be portable")
        require(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Assets/Shaders").path),
                "Validation project must not contain a local shader copy")
        let sceneURL = root.appendingPathComponent(project.startScene)
        require(FileManager.default.fileExists(atPath: sceneURL.path),
                "Validation project start scene must exist")
        let scene = try JSONDecoder().decode(SceneDocument.self, from: Data(contentsOf: sceneURL))
        require(scene.entities.count >= 4, "Validation scene must contain its deterministic reference setup")
        guard let camera = scene.entities.compactMap({ $0.components.camera }).first else {
            throw TestFailure("Validation scene must contain a camera")
        }
        require(camera.autoExposureEnabled == false, "Validation camera must keep auto exposure disabled")
        require(camera.exposureEV == 0.0, "Validation camera must use 0 EV")
        guard let renderer = scene.rendererSettingsOverride?.makeRendererSettings() else {
            throw TestFailure("Validation scene must explicitly record Phase 1 renderer invariants")
        }
        require(renderer.iblEnabled != 0, "Validation scene must enable global IBL")
        require(renderer.effectiveGlobalIBLSamplingGain == 1.0, "Validation scene must sample captured IBL at unit gain")
        require(renderer.tonemap == TonemapType.filmic.rawValue, "Validation scene must resolve to MetalCup Filmic v1")
        require(renderer.gamma == 2.2, "Validation scene must retain neutral legacy gamma state")
        guard let validationLightEntity = scene.entities.first(where: { $0.components.name?.name == "Validation Sun" }),
              let validationLight = validationLightEntity.components.light,
              let validationTransform = validationLightEntity.components.transform else {
            throw TestFailure("Validation scene must contain its transform-authored directional light")
        }
        require(validationLight.schemaVersion == LightComponentDTO.currentSchemaVersion,
                "Validation Sun must use modern transform-authoritative serialization")
        require(validationLight.data.type == 2 && abs(validationLight.data.brightness - .pi) < 0.0001,
                "Validation Sun must persist directional illuminance pi")
        require(abs(validationTransform.rotationQuat.w) < 0.99,
                "Validation Sun must not retain an identity transform with a redundant diagonal direction")
    }

    private static func phase2ValidationLabScenesDecode() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).standardizedFileURL
        let scenes = root.appendingPathComponent("Assets/Scenes", isDirectory: true)

        let material = try decodeScene(named: "MaterialReference", in: scenes)
        let materialLights = material.entities.compactMap { $0.components.light }
        require(materialLights.count == 1, "MaterialReference must have exactly one analytic light")
        require(abs(materialLights[0].data.brightness - .pi) < 0.0001,
                "MaterialReference directional illuminance must be pi")
        require(material.entities.compactMap { $0.components.environment }.isEmpty,
                "MaterialReference direct reference must not create an environment Sun")
        require(material.entities.compactMap { $0.components.meshRenderer?.material }.count >= 8,
                "MaterialReference must contain explicit dielectric and metal references")

        let analytic = try decodeScene(named: "AnalyticLightLab", in: scenes)
        let analyticLights = analytic.entities.compactMap { $0.components.light }
        require(analyticLights.count == 3, "AnalyticLightLab must contain directional, point, and spot rigs")
        require(analyticLights.filter { $0.data.brightness > 0 }.count == 1,
                "AnalyticLightLab must start with exactly one active rig")
        require(analyticLights.filter { $0.type != .directional }.allSatisfy { !$0.castsShadows },
                "Point and spot validation rigs must not claim shadow support")

        let shadow = try decodeScene(named: "ShadowValidation", in: scenes)
        let shadowCasters = shadow.entities.compactMap { $0.components.light }.filter { $0.castsShadows }
        require(shadowCasters.count == 1 && shadowCasters[0].type == .directional,
                "ShadowValidation must contain exactly one directional caster")
        require(shadow.entities.compactMap { $0.components.environment }.isEmpty,
                "ShadowValidation must not create an environment Sun")
        guard let shadowCamera = shadow.entities.compactMap({ $0.components.camera }).first else {
            throw TestFailure("ShadowValidation must contain a camera")
        }
        require(shadowCamera.nearPlane == 0.1 && shadowCamera.farPlane == 100,
                "ShadowValidation camera must use near 0.1 and far 100")
        guard let shadowSettings = shadow.rendererSettingsOverride?.makeRendererSettings().shadows else {
            throw TestFailure("ShadowValidation must persist hard-shadow settings")
        }
        require(shadowSettings.enabled != 0 && shadowSettings.filterMode == ShadowFilterMode.hard.rawValue,
                "ShadowValidation must start in hard-shadow mode")

        let ao = try decodeScene(named: "AOReference", in: scenes)
        require(ao.entities.compactMap { $0.components.environment }.count == 1,
                "AOReference must contain one controlled indirect environment")
        guard let aoSettings = ao.rendererSettingsOverride?.makeRendererSettings() else {
            throw TestFailure("AOReference must persist AO settings")
        }
        require(aoSettings.ssaoEnabled != 0, "AOReference must enable SAO")
        let aoNames = Set(ao.entities.compactMap { $0.components.name?.name })
        for role in ["Isolated Elevated Object", "Touching Pair Left", "Touching Pair Right",
                     "Wall Floor Corner", "Wedge Grazing Contact", "Isolated Silhouette"] {
            require(aoNames.contains(role), "AOReference is missing \(role)")
        }
    }

    private static func phase3ValidationLabScenesDecode() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).standardizedFileURL
        let scenes = root.appendingPathComponent("Assets/Scenes", isDirectory: true)

        let orientation = try decodeScene(named: "IBLOrientation", in: scenes)
        require(orientation.entities.compactMap { $0.components.light }.isEmpty,
                "IBLOrientation must not contain analytic lights")
        require(orientation.entities.compactMap { $0.components.environment }.count == 1,
                "IBLOrientation must contain one controlled environment")
        require(orientation.entities.compactMap { $0.components.meshRenderer?.material }.count >= 12,
                "IBLOrientation must contain material and six-axis marker references")

        let roughness = try decodeScene(named: "IBLRoughness", in: scenes)
        let roughnessMaterials = roughness.entities.compactMap { $0.components.meshRenderer?.material }
        require(roughnessMaterials.filter { $0.metallicScalar == 0 }.count == 7,
                "IBLRoughness must contain seven dielectric references")
        require(roughnessMaterials.filter { $0.metallicScalar == 1 }.count == 7,
                "IBLRoughness must contain seven metallic references")
        let expectedRoughness: Set<Float> = [0.06, 0.10, 0.20, 0.25, 0.50, 0.80, 1.00]
        require(Set(roughnessMaterials.map(\.roughnessScalar)) == expectedRoughness,
                "IBLRoughness must use the production reference sweep")

        let probes = try decodeScene(named: "ReflectionProbeValidation", in: scenes)
        let authoredProbes = probes.entities.compactMap { $0.components.reflectionProbe }
        require(authoredProbes.count == 1 && authoredProbes[0].enabled,
                "ReflectionProbeValidation must contain one enabled local probe")
        require(probes.entities.compactMap { $0.components.light }.isEmpty,
                "ReflectionProbeValidation must not contain analytic lights")
        let names = Set(probes.entities.compactMap { $0.components.name?.name })
        for role in ["+Z Blue Capture Marker", "-Z Yellow Capture Marker", "+Z Up-Right Narrow Marker",
                     "Global Only Smooth Metal Reference"] {
            require(names.contains(role), "ReflectionProbeValidation is missing \(role)")
        }
    }

    private static func decodeScene(named name: String, in scenes: URL) throws -> SceneDocument {
        let url = scenes.appendingPathComponent("\(name).mcscene")
        return try JSONDecoder().decode(SceneDocument.self, from: Data(contentsOf: url))
    }

    private static func temporaryDirectory(named name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MetalCupStage4-\(name)-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
    }

    private static func require(_ condition: @autoclosure () -> Bool,
                                _ message: String) {
        if !condition() {
            fatalError(message)
        }
    }

    private struct TestFailure: LocalizedError {
        let message: String

        init(_ message: String) {
            self.message = message
        }

        var errorDescription: String? { message }
    }
}
