/// AssetRegistry.swift
/// Defines the AssetRegistry types and helpers for the editor.
/// Created by Kaden Cringle.

import Foundation
import Dispatch
import Darwin
import MetalCupEngine

/// Editor-side asset discovery + metadata registry that backs the engine AssetDatabase protocol.
final class AssetRegistry: AssetDatabase {
    let assetRootURL: URL
    var onChange: (() -> Void)?
    private let logCenter: EngineLogger

    private var metadataByHandle: [AssetHandle: AssetMetadata] = [:]
    private var metadataByPath: [String: AssetMetadata] = [:]
    private var metadataBySourcePathAbs: [String: AssetMetadata] = [:]
    private var watcher: DispatchSourceFileSystemObject?
    private var watcherDescriptor: Int32 = -1

    init(projectAssetRootURL: URL, logCenter: EngineLogger) {
        self.assetRootURL = projectAssetRootURL.standardizedFileURL
        self.logCenter = logCenter
        scanAssets()
    }

    deinit {
        stopWatching()
    }

    func metadata(for handle: AssetHandle) -> AssetMetadata? {
        return metadataByHandle[handle]
    }

    func metadata(forSourcePath sourcePath: String) -> AssetMetadata? {
        return metadataByPath[sourcePath]
    }

    func assetURL(for handle: AssetHandle) -> URL? {
        guard let metadata = metadataByHandle[handle] else { return nil }
        return assetRootURL.appendingPathComponent(metadata.sourcePath)
    }

    func allMetadata() -> [AssetMetadata] {
        return Array(metadataByHandle.values)
    }

    func metadata(forSourcePathAbs sourcePathAbs: String) -> AssetMetadata? {
        return metadataBySourcePathAbs[sourcePathAbs]
    }

    func refresh() {
        scanAssets()
    }

    func startWatching() {
        guard watcher == nil else { return }
        watcherDescriptor = open(assetRootURL.path, O_EVTONLY)
        guard watcherDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: watcherDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: DispatchQueue.global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            self?.scanAssets()
            self?.onChange?()
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.watcherDescriptor, fd >= 0 {
                close(fd)
            }
        }
        source.resume()
        watcher = source
    }

    func stopWatching() {
        watcher?.cancel()
        watcher = nil
        watcherDescriptor = -1
    }

    func metaURLForAsset(assetURL: URL, relativePath: String) -> URL {
        return URL(fileURLWithPath: assetURL.path + ".meta")
    }

    func saveMetadata(_ metadata: AssetMetadata, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(metadata)
            try data.write(to: url, options: [.atomic])
        } catch {
            logCenter.logWarning("Asset meta write failed: \(url.lastPathComponent) (\(error.localizedDescription))", category: .assets)
        }
    }

    private func scanAssets() {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: assetRootURL, includingPropertiesForKeys: nil) else { return }

        var newByHandle: [AssetHandle: AssetMetadata] = [:]
        var newByPath: [String: AssetMetadata] = [:]
        var newBySourceAbs: [String: AssetMetadata] = [:]

        for case let url as URL in enumerator {
            if url.hasDirectoryPath { continue }
            if url.pathExtension == "meta" { continue }
            if url.lastPathComponent.hasPrefix(".") { continue }
            let assetType = AssetTypes.type(for: url)
            if assetType == .unknown { continue }

            guard let relativePath = PathUtils.relativePath(from: assetRootURL, to: url) else { continue }
            let metaURL = metaURLForAsset(assetURL: url, relativePath: relativePath)
            let lastModified = (try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let metadata = loadOrCreateMetadata(
                for: url,
                relativePath: relativePath,
                metaURL: metaURL,
                assetType: assetType,
                lastModified: lastModified
            )
            newByHandle[metadata.handle] = metadata
            newByPath[relativePath] = metadata
            if let sourceAbs = metadata.importSettings["sourcePathAbs"], !sourceAbs.isEmpty {
                newBySourceAbs[sourceAbs] = metadata
            }
        }

        metadataByHandle = newByHandle
        metadataByPath = newByPath
        metadataBySourcePathAbs = newBySourceAbs
    }

    private func loadOrCreateMetadata(for assetURL: URL, relativePath: String, metaURL: URL, assetType: AssetType, lastModified: TimeInterval) -> AssetMetadata {
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: metaURL),
           let meta = try? decoder.decode(AssetMetadata.self, from: data) {
            var updated = meta
            var didChange = false
            if updated.type != assetType {
                updated.type = assetType
                didChange = true
            }
            if updated.sourcePath != relativePath {
                updated.sourcePath = relativePath
                didChange = true
            }
            if updated.lastModified != lastModified {
                updated.lastModified = lastModified
                didChange = true
            }
            let normalizedImport = normalizedImportSettings(
                for: relativePath,
                assetType: assetType,
                existing: updated.importSettings
            )
            if updated.importSettings != normalizedImport {
                updated.importSettings = normalizedImport
                didChange = true
            }
            let normalizedScriptLanguage = normalizedScriptLanguageForAsset(assetType: assetType,
                                                                            relativePath: relativePath,
                                                                            existing: updated.scriptLanguage)
            if updated.scriptLanguage != normalizedScriptLanguage {
                updated.scriptLanguage = normalizedScriptLanguage
                didChange = true
            }
            let normalizedEntryType = normalizedEntryTypeNameForAsset(assetType: assetType,
                                                                      relativePath: relativePath,
                                                                      existing: updated.entryTypeName)
            if updated.entryTypeName != normalizedEntryType {
                updated.entryTypeName = normalizedEntryType
                didChange = true
            }
            if didChange {
                saveMetadata(updated, to: metaURL)
            }
            return updated
        }

        let importSettings = normalizedImportSettings(
            for: relativePath,
            assetType: assetType,
            existing: [:]
        )
        let meta = AssetMetadata(
            handle: AssetHandle(),
            type: assetType,
            sourcePath: relativePath,
            importSettings: importSettings,
            scriptLanguage: normalizedScriptLanguageForAsset(assetType: assetType, relativePath: relativePath, existing: nil),
            entryTypeName: normalizedEntryTypeNameForAsset(assetType: assetType, relativePath: relativePath, existing: nil),
            dependencies: [],
            lastModified: lastModified
        )
        saveMetadata(meta, to: metaURL)
        return meta
    }

    private func normalizedImportSettings(for relativePath: String,
                                          assetType: AssetType,
                                          existing: [String: String]) -> [String: String] {
        var settings = existing
        switch assetType {
        case .texture:
            if settings["origin"] == nil {
                settings["origin"] = "topLeft"
            }
            let semantic = (settings["semantic"] ?? settings["meshTextureSemantic"])?.lowercased()
                ?? inferTextureSemantic(from: relativePath)
            settings["semantic"] = semantic
            if isColorSemantic(semantic) {
                if settings["srgb"] == nil {
                    settings["srgb"] = "true"
                }
            } else {
                settings["srgb"] = isColorSemantic(semantic) ? "true" : "false"
            }
        case .environment:
            settings["semantic"] = "environment"
            settings["srgb"] = "false"
            if settings["origin"] == nil {
                settings["origin"] = "topLeft"
            }
        case .script:
            if settings["scriptLanguage"] == nil {
                settings["scriptLanguage"] = inferScriptLanguage(from: relativePath)
            }
            if settings["entryTypeName"] == nil {
                settings["entryTypeName"] = defaultEntryTypeName(from: relativePath)
            }
        default:
            break
        }
        return settings
    }

    private func normalizedScriptLanguageForAsset(assetType: AssetType,
                                                  relativePath: String,
                                                  existing: String?) -> String? {
        guard assetType == .script else { return nil }
        if let existing, !existing.isEmpty {
            return existing
        }
        return inferScriptLanguage(from: relativePath)
    }

    private func normalizedEntryTypeNameForAsset(assetType: AssetType,
                                                 relativePath: String,
                                                 existing: String?) -> String? {
        guard assetType == .script else { return nil }
        if let existing, !existing.isEmpty {
            return existing
        }
        return defaultEntryTypeName(from: relativePath)
    }

    private func inferScriptLanguage(from relativePath: String) -> String {
        let ext = URL(fileURLWithPath: relativePath).pathExtension.lowercased()
        switch ext {
        case "lua", "mcscript":
            return "lua"
        case "cs":
            return "csharp"
        default:
            return "unknown"
        }
    }

    private func defaultEntryTypeName(from relativePath: String) -> String {
        URL(fileURLWithPath: relativePath).deletingPathExtension().lastPathComponent
    }

    private func inferTextureSemantic(from relativePath: String) -> String {
        let name = relativePath.lowercased()
        if name.contains("orm") || name.contains("arm") || name.contains("rma") { return "orm" }
        if name.contains("normal") { return "normal" }
        if name.contains("rough") { return "roughness" }
        if name.contains("metal") { return "metallic" }
        if name.contains("ao") || name.contains("occlusion") { return "ao" }
        if name.contains("height") || name.contains("displace") { return "height" }
        if name.contains("emissive") { return "emissive" }
        if name.contains("albedo") || name.contains("basecolor") || name.contains("diff") { return "basecolor" }
        return "basecolor"
    }

    private func isColorSemantic(_ semantic: String) -> Bool {
        switch semantic {
        case "basecolor", "albedo", "diffuse", "diff", "emissive":
            return true
        default:
            return false
        }
    }

}
