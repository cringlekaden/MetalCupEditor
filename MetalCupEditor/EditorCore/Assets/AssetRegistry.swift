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

    private var metadataByHandle: [AssetHandle: AssetMetadata] = [:]
    private var metadataByPath: [String: AssetMetadata] = [:]
    private var watcher: DispatchSourceFileSystemObject?
    private var watcherDescriptor: Int32 = -1

    init(projectAssetRootURL: URL) {
        self.assetRootURL = projectAssetRootURL.standardizedFileURL
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
            EditorLogCenter.shared.logWarning("Asset meta write failed: \(url.lastPathComponent) (\(error.localizedDescription))", category: .assets)
        }
    }

    private func scanAssets() {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: assetRootURL, includingPropertiesForKeys: nil) else { return }

        var newByHandle: [AssetHandle: AssetMetadata] = [:]
        var newByPath: [String: AssetMetadata] = [:]

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
        }

        metadataByHandle = newByHandle
        metadataByPath = newByPath
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
            if didChange {
                saveMetadata(updated, to: metaURL)
            }
            return updated
        }

        let meta = AssetMetadata(
            handle: AssetHandle(),
            type: assetType,
            sourcePath: relativePath,
            importSettings: [:],
            dependencies: [],
            lastModified: lastModified
        )
        saveMetadata(meta, to: metaURL)
        return meta
    }

}
