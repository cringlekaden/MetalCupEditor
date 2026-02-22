/// AssetIO.swift
/// Defines asset serialization helpers for the editor.
/// Created by Kaden Cringle.

import Foundation
import MetalCupEngine

enum AssetIO {
    static func metaURL(for assetURL: URL) -> URL {
        URL(fileURLWithPath: assetURL.path + ".meta")
    }

    static func assetDisplayName(for metadata: AssetMetadata, assetManager: AssetManager?) -> String {
        if metadata.type == .material,
           let material = assetManager?.material(handle: metadata.handle) {
            return material.name
        }
        let filename = URL(fileURLWithPath: metadata.sourcePath).deletingPathExtension().lastPathComponent
        return filename.isEmpty ? metadata.sourcePath : filename
    }

    static func displayNameForFile(url: URL, modifiedTime: TimeInterval) -> String {
        let ext = url.pathExtension.lowercased()
        var displayName = url.deletingPathExtension().lastPathComponent
        if ext == "mcmat" {
            if let data = try? Data(contentsOf: url),
               let document = try? JSONDecoder().decode(MaterialAssetDocument.self, from: data) {
                if let name = document.name, !name.isEmpty {
                    displayName = name
                }
            }
        } else if ext == "mcscene" || ext == "scene" {
            if let data = try? Data(contentsOf: url),
               let document = try? JSONDecoder().decode(SceneDocument.self, from: data) {
                if !document.name.isEmpty {
                    displayName = document.name
                }
            }
        }
        return displayName
    }

    static func updateMaterialNameIfNeeded(url: URL, newName: String) {
        guard url.pathExtension.lowercased() == "mcmat" else { return }
        if var material = MaterialSerializer.load(from: url, fallbackHandle: nil) {
            material.name = newName
            _ = MaterialSerializer.save(material, to: url)
        }
    }

    static func updateSceneNameIfNeeded(url: URL, newName: String) {
        let ext = url.pathExtension.lowercased()
        guard ext == "mcscene" || ext == "scene" else { return }
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: url),
           var document = try? decoder.decode(SceneDocument.self, from: data) {
            document.name = newName
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let updated = try? encoder.encode(document) {
                try? updated.write(to: url, options: [.atomic])
            }
        }
    }

    static func clearDisplayNameCache() {
        // Cache removed; intentionally empty.
    }
}
