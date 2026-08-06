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
