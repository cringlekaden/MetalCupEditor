//
//  MetalCupEditorApp.swift
//  MetalCupEditor
//
//  Created by Kaden Cringle on 2/3/26.
//

import Foundation
import SwiftUI
import MetalCupEngine

@main
struct MetalCupEditorApp: App {
    
    private let engineApp: Application

    init() {
        let env = ProcessInfo.processInfo.environment["METALCUP_ASSETS_ROOT"]
        var assetsRootURL = AssetAccessManager.resolvedAssetsRoot(envOverride: env)
        if assetsRootURL == nil {
            assetsRootURL = AssetAccessManager.promptForAssetsRoot()
        }

        let spec = ApplicationSpecification(
            title: "MetalCup Editor",
            resizable: true,
            centered: true,
            preferredFramesPerSecond: 60,
            colorPixelFormat: .bgra8Unorm,
            depthStencilPixelFormat: .invalid,
            resourcesFolderName: "Resources",
            assetsRootURL: assetsRootURL
        )
        self.engineApp = EditorApplication(specification: spec)
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
struct RootView: View {
    var body: some View {
        Text("MetalCup Editor")
            .padding()
    }
}
