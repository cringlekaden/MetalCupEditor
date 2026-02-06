//
//  EditorApplication.swift
//  MetalCupEditor
//
//  Created by Kaden Cringle on 2/4/26.
//

import MetalCupEngine
import MetalKit

class EditorApplication: Application {
    private var assetRegistry: AssetRegistry?
    
    nonisolated override init(specification: ApplicationSpecification) {
        super.init(specification: specification)
    }
    
    nonisolated override func willCreateWindow() {
        Graphics.initialize()
        if let folder = specification.resourcesFolderName {
            ResourceRegistry.resourcesRootURL = Bundle.main.url(forResource: folder, withExtension: nil)
        } else {
            ResourceRegistry.resourcesRootURL = nil
        }
        let assetsRootURL = specification.assetsRootURL
            ?? ResourceRegistry.resourcesRootURL
            ?? Bundle.main.resourceURL
        if let rootURL = assetsRootURL {
            let registry = AssetRegistry(assetRootURL: rootURL)
            registry.startWatching()
            registry.onChange = {
                AssetManager.clearCache()
                AssetManager.preload(from: registry)
            }
            assetRegistry = registry
            Engine.assetDatabase = registry
            AssetManager.preload(from: registry)
        }
        Graphics.build()
    }
    
    nonisolated override func didCreateWindow() {
        layerStack.pushLayer(ImGuiLayer(name: "Sandbox"))
    }
}
