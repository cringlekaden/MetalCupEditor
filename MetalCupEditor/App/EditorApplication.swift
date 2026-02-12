//
//  EditorApplication.swift
//  MetalCupEditor
//
//  Created by Kaden Cringle on 2/4/26.
//

import MetalCupEngine
import MetalKit

final class EditorApplication: Application {
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
        layerStack.pushLayer(ImGuiLayer(name: "Sandbox"))
    }
}
