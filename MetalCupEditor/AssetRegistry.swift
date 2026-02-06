//
//  AssetRegistry.swift
//  MetalCupEditor
//
//  Created by Engine Scaffolding
//

import Foundation
import Dispatch
import Darwin
import MetalCupEngine

final class AssetRegistry: AssetDatabase {
    let assetRootURL: URL
    private let metaRootURL: URL?
    private let useSidecarMeta: Bool
    var onChange: (() -> Void)?
    private var metadataByHandle: [AssetHandle: AssetMetadata] = [:]
    private var metadataByPath: [String: AssetMetadata] = [:]
    private var watcher: DispatchSourceFileSystemObject?
    private var watcherDescriptor: Int32 = -1

    init(assetRootURL: URL) {
        let fm = FileManager.default
        var resolvedRoot = assetRootURL
        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: resolvedRoot.path, isDirectory: &isDir) || !isDir.boolValue || !fm.isReadableFile(atPath: resolvedRoot.path) {
            if let bundleRoot = Bundle.main.resourceURL {
                resolvedRoot = bundleRoot
                print("ASSET_REGISTRY::FALLBACK_ROOT=\(resolvedRoot.path)")
            }
        }

        self.assetRootURL = resolvedRoot
        let writable = fm.isWritableFile(atPath: resolvedRoot.path)
        self.useSidecarMeta = writable
        if writable {
            self.metaRootURL = nil
        } else {
            let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            let metaRoot = support?.appendingPathComponent("MetalCupEditor/AssetMeta", isDirectory: true)
            self.metaRootURL = metaRoot
            if let metaRoot {
                try? fm.createDirectory(at: metaRoot, withIntermediateDirectories: true)
            }
        }
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

    private func scanAssets() {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: assetRootURL, includingPropertiesForKeys: nil) else { return }

        var newByHandle: [AssetHandle: AssetMetadata] = [:]
        var newByPath: [String: AssetMetadata] = [:]

        for case let url as URL in enumerator {
            if url.hasDirectoryPath { continue }
            if url.pathExtension == "meta" { continue }
            if url.lastPathComponent.hasPrefix(".") { continue }

            let relativePath = url.path.replacingOccurrences(of: assetRootURL.path + "/", with: "")
            let metaURL = metaURLForAsset(assetURL: url, relativePath: relativePath)
            let metadata = loadOrCreateMetadata(for: url, relativePath: relativePath, metaURL: metaURL)
            newByHandle[metadata.handle] = metadata
            newByPath[relativePath] = metadata
        }

        metadataByHandle = newByHandle
        metadataByPath = newByPath
    }

    private func loadOrCreateMetadata(for assetURL: URL, relativePath: String, metaURL: URL) -> AssetMetadata {
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: metaURL),
           let meta = try? decoder.decode(AssetMetadata.self, from: data) {
            return meta
        }

        let meta = AssetMetadata(
            handle: AssetHandle(),
            type: assetType(for: assetURL),
            sourcePath: relativePath,
            importSettings: [:],
            dependencies: []
        )
        saveMetadata(meta, to: metaURL)
        return meta
    }

    private func metaURLForAsset(assetURL: URL, relativePath: String) -> URL {
        if useSidecarMeta {
            return URL(fileURLWithPath: assetURL.path + ".meta")
        }
        if let metaRootURL {
            let metaPath = relativePath + ".meta"
            let url = metaRootURL.appendingPathComponent(metaPath)
            let parent = url.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parent.path) {
                try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            }
            return url
        }
        return URL(fileURLWithPath: assetURL.path + ".meta")
    }

    private func saveMetadata(_ metadata: AssetMetadata, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(metadata)
            try data.write(to: url, options: [.atomic])
        } catch {
            print("WARN::ASSET::META::__\(url.lastPathComponent)__::\(error)")
        }
    }

    private func assetType(for url: URL) -> AssetType {
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "tga", "bmp":
            return .texture
        case "hdr", "exr":
            return .environment
        case "obj", "usdz", "fbx":
            return .model
        case "scene":
            return .scene
        case "prefab":
            return .prefab
        default:
            return .unknown
        }
    }
}
