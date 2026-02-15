/// EditorApplication.swift
/// Defines the EditorApplication types and helpers for the editor.
/// Created by Kaden Cringle.

import AppKit
import MetalCupEngine
import MetalKit

final class EditorApplication: Application, NSWindowDelegate {
    private var isShuttingDown = false
    private var editorLayer: ImGuiLayer?

    nonisolated override init(specification: ApplicationSpecification) {
        super.init(specification: specification)
    }
    
    nonisolated override func willCreateWindow() {
        Graphics.initialize()
        ResourceRegistry.resourcesRootURL = EditorFileSystem.resourcesRootURL(preferredFolderName: specification.resourcesFolderName)
        EditorProjectManager.shared.bootstrap(resourcesRootURL: ResourceRegistry.resourcesRootURL)
        Graphics.build()
    }
    
    nonisolated override func didCreateWindow() {
        let layer = ImGuiLayer(name: "Sandbox")
        editorLayer = layer
        layerStack.pushLayer(layer)
        let appId = ObjectIdentifier(self)
        let layerId = ObjectIdentifier(layer)
        let stackId = ObjectIdentifier(layerStack)
        NSLog("[MC] EditorApplication.didCreateWindow app=\(appId) layer=\(layerId) layerStack=\(stackId)")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.mainWindow.nsWindow.delegate = self
        }
    }

    nonisolated override func activeScene() -> EngineScene? {
        let scene = editorLayer?.activeScene()
        let sceneId = scene.map { ObjectIdentifier($0) }
        let sceneInfo = scene.map { "\($0.id)/\($0.name)" } ?? "nil"
        return scene
    }

    nonisolated override func buildSceneView() -> SceneView {
        return editorLayer?.buildSceneView() ?? SceneView(viewportSize: Renderer.ViewportSize)
    }

    nonisolated override func handlePickResult(_ result: PickResult) {
        editorLayer?.handlePickResult(result)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isShuttingDown { return true }

        let hasProject = EditorProjectManager.shared.isProjectOpen
        let isDirty = EditorProjectManager.shared.isSceneDirty()

        if hasProject && isDirty {
            let alert = NSAlert()
            alert.messageText = "Save changes before closing?"
            alert.informativeText = "Your project has unsaved scene changes."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Don't Save")
            alert.addButton(withTitle: "Cancel")
            let response = alert.runModal()
            switch response {
            case .alertFirstButtonReturn:
                performShutdown(saveChanges: true)
            case .alertSecondButtonReturn:
                performShutdown(saveChanges: false)
            default:
                return false
            }
        } else {
            performShutdown(saveChanges: false)
        }

        return false
    }

    private func performShutdown(saveChanges: Bool) {
        guard !isShuttingDown else { return }
        isShuttingDown = true

        EditorProjectManager.shared.saveSettings()
        if saveChanges {
            EditorProjectManager.shared.saveAll()
        }

        if SceneManager.isPlaying {
            SceneManager.stop()
        }

        mainWindow.mtkView.delegate = nil
        mainWindow.nsWindow.delegate = nil

        EditorLogCenter.shared.logInfo("Editor exiting.", category: .editor)
        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
    }
}

@_cdecl("MCEEditorRequestQuit")
public func MCEEditorRequestQuit() {
    DispatchQueue.main.async {
        NSApp.mainWindow?.performClose(nil)
    }
}
