//
//  EditorApplication.swift
//  MetalCupEditor
//
//  Created by Kaden Cringle on 2/4/26.
//

import MetalCupEngine
import MetalKit

class EditorApplication: Application {
    
    nonisolated override init(specification: ApplicationSpecification) {
        super.init(specification: specification)
    }
    
    nonisolated override func willCreateWindow() {
        Assets.initialize()
        Graphics.initialize()
        if let folder = specification.resourcesFolderName {
            ResourceRegistry.resourcesRootURL = Bundle.main.url(forResource: folder, withExtension: nil)
        } else {
            ResourceRegistry.resourcesRootURL = nil
        }
        if specification.autoRegisterResources {
            registerDefaultAssets()
        }
        Graphics.build()
    }
    
    nonisolated override func didCreateWindow() {
        layerStack.pushLayer(ImGuiLayer(name: "Sandbox"))
    }
}
