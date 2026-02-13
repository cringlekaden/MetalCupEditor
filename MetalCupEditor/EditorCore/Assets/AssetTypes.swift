/// AssetTypes.swift
/// Defines shared asset type conversions for the editor.
/// Created by Kaden Cringle.

import Foundation
import MetalCupEngine

enum AssetTypes {
    static func code(for type: AssetType) -> Int32 {
        switch type {
        case .texture: return 0
        case .model: return 1
        case .material: return 2
        case .environment: return 3
        case .scene: return 4
        case .prefab: return 5
        case .unknown: return 6
        @unknown default: return 6
        }
    }

    static func type(for url: URL) -> AssetType {
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "tga", "bmp":
            return .texture
        case "hdr", "exr":
            return .environment
        case "obj", "usdz", "fbx":
            return .model
        case "mcmat":
            return .material
        case "scene", "mcscene":
            return .scene
        case "prefab":
            return .prefab
        default:
            return .unknown
        }
    }
}

enum MaterialAlphaModeCodes {
    static func code(for mode: MaterialAlphaMode) -> Int32 {
        switch mode {
        case .opaque: return 0
        case .masked: return 1
        case .blended: return 2
        @unknown default: return 0
        }
    }

    static func mode(from code: Int32) -> MaterialAlphaMode {
        switch code {
        case 1: return .masked
        case 2: return .blended
        default: return .opaque
        }
    }
}
