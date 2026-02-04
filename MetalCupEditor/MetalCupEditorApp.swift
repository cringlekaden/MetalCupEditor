//
//  MetalCupEditorApp.swift
//  MetalCupEditor
//
//  Created by Kaden Cringle on 2/3/26.
//

import SwiftUI
import MetalCupEngine

@main
struct MetalCupEditorApp: App {
    
    private let engineApp: Application

    init() {
        let spec = ApplicationSpecification(
            title: "MetalCup Editor",
            resizable: true,
            centered: true,
            preferredFramesPerSecond: 120,
            colorPixelFormat: .bgra8Unorm,
            depthStencilPixelFormat: .invalid,
            resourcesFolderName: "Resources",
            autoRegisterResources: true
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

