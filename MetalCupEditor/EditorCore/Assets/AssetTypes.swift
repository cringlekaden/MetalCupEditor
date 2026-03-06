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
        case .script: return 6
        case .unknown: return 7
        case .skeleton: return 8
        case .animationClip: return 9
        case .audio: return 10
        @unknown default: return 7
        }
    }

    static func type(for url: URL) -> AssetType {
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "tga", "bmp", "tif", "tiff":
            return .texture
        case "hdr", "exr":
            return .environment
        case "obj", "usdz", "fbx", "gltf", "glb":
            return .model
        case "mcmat":
            return .material
        case "scene", "mcscene":
            return .scene
        case "prefab":
            return .prefab
        case "lua", "mcscript", "cs":
            return .script
        case "skeleton", "mcskeleton":
            return .skeleton
        case "anim", "animclip", "mcanim":
            return .animationClip
        case "wav", "ogg", "mp3", "aiff", "caf", "m4a":
            return .audio
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
