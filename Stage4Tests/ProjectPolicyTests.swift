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
        try phase4ValidationLabScenesDecode()
        try phase5ValidationLabScenesDecode()
        try phase6ValidationLabScenesDecode()
        try phase1ExposureValidationDecodes()
        print("Stage 4 Editor policy tests passed")
    }

    private static func missingShaderSettingDefaultsToCanonical() throws {
        let data = Data(#"{"name":"Legacy","rootPath":".","assetDirectory":"Assets","scenesDirectory":"Assets/Scenes","cacheDirectory":"Cache","intermediateDirectory":"Intermediate","savedDirectory":"Saved","startScene":"Assets/Scenes/Default.mcscene"}"#.utf8)
        let document = try JSONDecoder().decode(ProjectDocument.self, from: data)
        require(document.shaderSource == .canonical, "Missing shaderSource must decode as canonical")
        require(document.renderSettings.exposure.mode == .automaticHistogram,
                "New and legacy projects without exposure settings must inherit Automatic Histogram")
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
        require(project.renderSettings.exposure.mode == .manualEV100
                    && project.renderSettings.exposure.manualEV100 == 15,
                "Deterministic validation defaults must explicitly use Manual EV100 15")
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
        requireManualReference(camera, context: "RendererValidation")
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
        require(aoSettings.ssaoThickness == 0.22 && aoSettings.ssaoBlurSharpness == 24,
                "AOReference must persist the deterministic production thickness and blur settings")
        let aoNames = Set(ao.entities.compactMap { $0.components.name?.name })
        for role in ["Isolated Elevated Object", "Touching Pair Left", "Touching Pair Right",
                     "Wall Floor Corner", "Wedge Grazing Contact", "Isolated Silhouette",
                     "Convex Rounded Edge", "Thin Silhouette Stress", "AO Distance Marker Near",
                     "AO Distance Marker Mid", "AO Distance Marker Far"] {
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

    private static func phase4ValidationLabScenesDecode() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).standardizedFileURL
        let scenes = root.appendingPathComponent("Assets/Scenes", isDirectory: true)
        let sky = try decodeScene(named: "SkySunReference", in: scenes)
        require(sky.entities.compactMap { $0.components.light }.isEmpty,
                "SkySunReference must use only the Environment-owned analytic Sun")
        guard let camera = sky.entities.compactMap({ $0.components.camera }).first else {
            throw TestFailure("SkySunReference must contain a camera")
        }
        requireManualReference(camera, context: "SkySunReference")
        guard let environment = sky.entities.compactMap({ $0.components.environment }).first else {
            throw TestFailure("SkySunReference must contain one Environment")
        }
        require(environment.atmosphere.sourceEV == 0,
                "SkySunReference must use Environment Source EV 0")

        let sphereRoles = [
            "White Diffuse Reference", "18 Percent Gray Diffuse Reference",
            "Smooth Dielectric", "Rough Dielectric", "Smooth Metal",
            "Rough Neutral Metal", "Copper Metal"
        ]
        for role in sphereRoles {
            guard let entity = sky.entities.first(where: { $0.components.name?.name == role }),
                  let renderer = entity.components.meshRenderer,
                  let material = renderer.material else {
                throw TestFailure("SkySunReference is missing \(role)")
            }
            require(renderer.meshHandle == BuiltinAssets.sphereMesh,
                    "\(role) must use the built-in smooth sphere")
            require(material.emissiveScalar == 0,
                    "Reference materials must not be emissive")
        }
        guard let rounded = sky.entities.first(where: { $0.components.name?.name == "Rounded Neutral Box" }),
              let roundedRenderer = rounded.components.meshRenderer else {
            throw TestFailure("SkySunReference is missing its rounded box")
        }
        require(roundedRenderer.meshHandle == BuiltinAssets.roundedCubeMesh,
                "Rounded Neutral Box must use the built-in rounded geometry")
    }

    private static func phase5ValidationLabScenesDecode() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).standardizedFileURL
        let scenes = root.appendingPathComponent("Assets/Scenes", isDirectory: true)
        for name in ["FogReference", "AerialPerspectiveValidation"] {
            let scene = try decodeScene(named: name, in: scenes)
            guard let camera = scene.entities.compactMap({ $0.components.camera }).first,
                  let environment = scene.entities.compactMap({ $0.components.environment }).first,
                  let settings = scene.rendererSettingsOverride?.makeRendererSettings() else {
                throw TestFailure("\(name) must contain camera, Environment, and renderer settings")
            }
            requireManualReference(camera, context: name)
            require(environment.atmosphere.sourceEV == 0,
                    "\(name) must use Environment Source EV 0")
            require(environment.fog.enabled && environment.fog.extinction > 0,
                    "\(name) must explicitly enable the Phase 5 local medium")
            require(environment.fog.scaleHeight > 0,
                    "\(name) must use a positive world-unit fog scale height")
            require(settings.ssaoEnabled == 0 && settings.bloomEnabled == 0,
                    "\(name) must disable unresolved SAO and bloom")
            require(scene.entities.compactMap { $0.components.light }.isEmpty,
                    "\(name) must use only the Environment-owned analytic Sun")
        }

        let fog = try decodeScene(named: "FogReference", in: scenes)
        let names = Set(fog.entities.compactMap { $0.components.name?.name })
        for distance in ["1", "5", "10", "25", "50", "100"] {
            require(names.contains(where: { $0.contains("Distance \(distance) ") }),
                    "FogReference is missing distance marker \(distance)")
        }
        let aerial = try decodeScene(named: "AerialPerspectiveValidation", in: scenes)
        let aerialNames = Set(aerial.entities.compactMap { $0.components.name?.name })
        require(aerialNames.contains("Horizon Crossing Receiver"),
                "AerialPerspectiveValidation needs a sky/object continuity silhouette")
        require(aerialNames.contains("Below Base Height Geometry"),
                "AerialPerspectiveValidation needs a below-layer sample")
    }

    private static func phase6ValidationLabScenesDecode() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).standardizedFileURL
        let scenes = root.appendingPathComponent("Assets/Scenes", isDirectory: true)
        let scene = try decodeScene(named: "SkyTimeValidation", in: scenes)
        guard let camera = scene.entities.compactMap({ $0.components.camera }).first,
              let environment = scene.entities.compactMap({ $0.components.environment }).first,
              let settings = scene.rendererSettingsOverride?.makeRendererSettings() else {
            throw TestFailure("SkyTimeValidation must contain its camera, Environment, and settings")
        }
        requireManualReference(camera, context: "SkyTimeValidation")
        require(environment.atmosphere.sourceEV == 0,
                "Phase 6 must keep Environment Source EV 0")
        require(environment.celestial.moonIntensity == 0.12,
                "Phase 6 reference must use the documented effective lunar albedo")
        require(environment.celestial.moonSizeDegrees == 0.54,
                "Phase 6 reference must use the physical lunar angular diameter")
        require(environment.celestial.moonPhase == 0.5,
                "Phase 6 reference must begin with a deterministic full Moon")
        require(environment.celestial.starIntensity > 0 && environment.celestial.milkyWayIntensity > 0,
                "Phase 6 reference must exercise stars and the Milky Way")
        require(environment.fog.enabled && environment.fog.extinction > 0,
                "Phase 2 exterior cycle must exercise live-radiance fog")
        require(environment.clouds.coverage > 0
                    && environment.clouds.renderMode == EnvironmentCloudRenderMode.procedural.rawValue,
                "Phase 2 exterior cycle must exercise procedural radiometric clouds")
        require(!environment.ibl.realtimeUpdate && !environment.ibl.autoRebuildOnChange,
                "Phase 2 static checkpoints must require explicit final-quality IBL rebuilds")
        require(settings.ssaoEnabled == 0 && settings.bloomEnabled == 0 && settings.iblEnabled != 0,
                "Phase 6 reference must isolate celestial lighting with IBL enabled")
        require(settings.shadows.enabled != 0 && settings.shadows.directionalEnabled != 0,
                "Phase 6 reference must exercise the selected celestial shadow caster")
        require(scene.entities.compactMap { $0.components.light }.isEmpty,
                "Phase 6 must use only the Environment-owned Sun/Moon key light")
        let names = Set(scene.entities.compactMap { $0.components.name?.name })
        for role in ["Diffuse Dielectric", "Rough Dielectric", "Smooth Dielectric",
                     "Rough Metal", "Smooth Metal", "Accelerated Shadow Receiver Floor",
                     "Accelerated Celestial Shadow Caster",
                     "CHECKPOINTS — 12 Midday | 17 Golden | 18 Sunset | 18.5 Civil | 19 Nautical | 19.5 Astronomical | 0 Deep Night | 5.5 Dawn",
                     "ISOLATION — toggle Clouds/Fog; use Direct, Diffuse IBL, Global/Local Probe, and Fog diagnostics; rebuild Final IBL after each checkpoint"] {
            require(names.contains(role), "SkyTimeValidation is missing \(role)")
        }
    }

    private static func phase1ExposureValidationDecodes() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).standardizedFileURL
        let scenes = root.appendingPathComponent("Assets/Scenes", isDirectory: true)
        let scene = try decodeScene(named: "ExposureValidation", in: scenes)
        let cameras = scene.entities.compactMap { $0.components.camera }
        require(cameras.count == 3, "ExposureValidation must contain automatic, manual, and physical cameras")
        require(cameras.contains { $0.exposurePolicy.mode == .automaticHistogram },
                "ExposureValidation must exercise Automatic Histogram")
        require(cameras.contains { $0.exposurePolicy.mode == .manualEV100 && $0.exposurePolicy.manualEV100 == 15 },
                "ExposureValidation must include Manual EV100 15")
        guard let physical = cameras.first(where: { $0.exposurePolicy.mode == .physicalCamera }),
              let aperture = physical.exposurePolicy.aperture,
              let shutter = physical.exposurePolicy.shutterSeconds,
              let iso = physical.exposurePolicy.iso else {
            throw TestFailure("ExposureValidation must include a complete physical camera")
        }
        require(abs(ExposureCalibration.physicalEV100(aperture: aperture,
                                                      shutterSeconds: shutter,
                                                      iso: iso) - 15) < 0.0001,
                "ExposureValidation physical camera must equal EV100 15")
        let volumes = scene.entities.compactMap { $0.components.postProcessVolume }
        require(volumes.count == 1 && !volumes[0].isGlobal && volumes[0].blendDistance > 0,
                "ExposureValidation must exercise a blended indoor/outdoor override volume")
        require(scene.entities.compactMap { $0.components.environment }.count == 1,
                "ExposureValidation must exercise a procedural accelerated weather cycle")
        require(scene.entities.compactMap { $0.components.reflectionProbe }.count == 1,
                "ExposureValidation must exercise radiometric capture isolation")
        let names = Set(scene.entities.compactMap { $0.components.name?.name })
        for role in ["AUTO PRIMARY - exterior to interior route", "Tiny HDR Emissive Stress",
                     "Indoor Blend Volume - walk through box edge", "Capture Isolation Probe"] {
            require(names.contains(role), "ExposureValidation is missing \(role)")
        }
    }

    private static func requireManualReference(_ camera: CameraComponentDTO, context: String) {
        require(camera.exposurePolicy.mode == .manualEV100 && camera.exposurePolicy.manualEV100 == 15,
                "\(context) must explicitly use deterministic Manual EV100 15")
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
