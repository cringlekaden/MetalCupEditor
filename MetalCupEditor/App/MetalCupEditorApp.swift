/// MetalCupEditorApp.swift
/// Defines the MetalCupEditorApp types and helpers for the editor.
/// Created by Kaden Cringle.

import Foundation
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
            preferredFramesPerSecond: 60,
            colorPixelFormat: .bgra8Unorm,
            depthStencilPixelFormat: .invalid,
            resourcesFolderName: "Resources",
            assetsRootURL: nil
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
