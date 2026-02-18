/// EditorApplication.swift
/// Defines the EditorApplication types and helpers for the editor.
/// Created by Kaden Cringle.

import AppKit
import MetalCupEngine
import MetalKit

final class EditorApplication: Application, NSWindowDelegate {
    private var isShuttingDown = false
    private var editorLayer: ImGuiLayer?
    private var context: MCEContext?
    private var contextPtr: UnsafeMutableRawPointer?

    nonisolated override init(specification: ApplicationSpecification) {
        super.init(specification: specification)
    }
    
    nonisolated override func willCreateWindow() {
        Graphics.initialize()
        ResourceRegistry.resourcesRootURL = EditorFileSystem.resourcesRootURL(preferredFolderName: specification.resourcesFolderName)
        let enginePtr = Unmanaged.passUnretained(engineContext).toOpaque()
        let contextPtr = MCEContextCreate(enginePtr)
        self.contextPtr = contextPtr
        let context = Unmanaged<MCEContext>.fromOpaque(contextPtr).takeUnretainedValue()
        self.context = context
        context.editorProjectManager.bootstrap(resourcesRootURL: ResourceRegistry.resourcesRootURL)
        Graphics.build()
    }
    
    nonisolated override func didCreateWindow() {
        guard let context, let contextPtr else {
            fatalError("MCEContext not initialized.")
        }
        let layer = ImGuiLayer(name: "Sandbox", context: context, contextPtr: contextPtr)
        editorLayer = layer
        layerStack.pushLayer(layer)
        let appId = ObjectIdentifier(self)
        let layerId = ObjectIdentifier(layer)
        let stackId = ObjectIdentifier(layerStack)
        engineContext.log.logDebug(
            "Editor window created app=\(appId) layer=\(layerId) layerStack=\(stackId)",
            category: .editor
        )
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.mainWindow.nsWindow.delegate = self
        }
    }

    nonisolated override func activeScene() -> EngineScene? {
        editorLayer?.activeScene()
    }

    nonisolated override func buildSceneView() -> SceneView {
        return editorLayer?.buildSceneView() ?? SceneView(viewportSize: Renderer.ViewportSize)
    }

    nonisolated override func handlePickResult(_ result: PickResult) {
        editorLayer?.handlePickResult(result)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isShuttingDown { return true }

        let manager = context?.editorProjectManager
        let hasProject = manager?.isProjectOpen ?? false
        let isDirty = manager?.isSceneDirty() ?? false

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

        context?.editorProjectManager.saveSettings()
        if saveChanges {
            context?.editorProjectManager.saveAll()
        }

        if context?.editorSceneController.isPlaying == true {
            context?.editorSceneController.stop()
        }

        mainWindow.mtkView.delegate = nil
        mainWindow.nsWindow.delegate = nil

        context?.engineContext.log.logInfo("Editor exiting.", category: .editor)
        if let contextPtr {
            MCEContextDestroy(contextPtr)
            self.contextPtr = nil
            self.context = nil
        }
        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
    }
}

@_cdecl("MCEEditorRequestQuit")
public func MCEEditorRequestQuit(_ contextPtr: UnsafeRawPointer?) {
    DispatchQueue.main.async {
        NSApp.mainWindow?.performClose(nil)
    }
}
