//
// AiScene.swift
// SwiftAssimp
//
// Copyright © 2019-2023 Christian Treffs. All rights reserved.
// Licensed under BSD 3-Clause License. See LICENSE file for details.

@_implementationOnly import CAssimp

final class AiSceneLifetime {
    let scenePtr: UnsafePointer<aiScene>

    init(scenePtr: UnsafePointer<aiScene>) {
        self.scenePtr = scenePtr
    }

    deinit {
        aiReleaseImport(scenePtr)
    }
}

public final class AiScene {
    public enum Error: Swift.Error {
        case importFailed(String)
        case importIncomplete(String)
    }

    public struct Flags: OptionSet {
        public var rawValue: Int32

        public init(rawValue: Int32) {
            self.rawValue = rawValue
        }

        public static let incomplete = Flags(rawValue: AI_SCENE_FLAGS_INCOMPLETE)
        public static let validated = Flags(rawValue: AI_SCENE_FLAGS_VALIDATED)
        public static let validationWarning = Flags(rawValue: AI_SCENE_FLAGS_VALIDATION_WARNING)
        public static let nonVerboseFormat = Flags(rawValue: AI_SCENE_FLAGS_NON_VERBOSE_FORMAT)
        public static let terrain = Flags(rawValue: AI_SCENE_FLAGS_TERRAIN)
        public static let allowShared = Flags(rawValue: AI_SCENE_FLAGS_ALLOW_SHARED)
    }

    let lifetime: AiSceneLifetime
    var scenePtr: UnsafePointer<aiScene> { lifetime.scenePtr }
    var scene: aiScene { scenePtr.pointee }

    public init(file filePath: String, flags: AiPostProcessStep = []) throws {
        guard let importedScene = aiImportFile(filePath, flags.rawValue) else {
            throw Error.importFailed(String(cString: aiGetErrorString()))
        }
        lifetime = AiSceneLifetime(scenePtr: importedScene)
        let flags = Flags(rawValue: Int32(importedScene.pointee.mFlags))

        self.flags = flags

        let numMeshes = Int(importedScene.pointee.mNumMeshes)
        self.numMeshes = numMeshes
        let numMaterials = Int(importedScene.pointee.mNumMaterials)
        self.numMaterials = numMaterials
        let numAnimations = Int(importedScene.pointee.mNumAnimations)
        self.numAnimations = numAnimations
        let numTextures = Int(importedScene.pointee.mNumTextures)
        self.numTextures = numTextures
        let numLights = Int(importedScene.pointee.mNumLights)
        self.numLights = numLights
        let numCameras = Int(importedScene.pointee.mNumCameras)
        self.numCameras = numCameras

        hasMeshes = importedScene.pointee.mMeshes != nil && numMeshes > 0
        hasMaterials = importedScene.pointee.mMaterials != nil && numMaterials > 0
        hasLights = importedScene.pointee.mLights != nil && numLights > 0
        hasTextures = importedScene.pointee.mTextures != nil && numTextures > 0
        hasCameras = importedScene.pointee.mCameras != nil && numCameras > 0
        hasAnimations = importedScene.pointee.mAnimations != nil && numAnimations > 0

        hasRootNode = importedScene.pointee.mRootNode != nil
    }

    /// Check whether the scene contains meshes
    /// Unless no special scene flags are set this will always be true.
    public var hasMeshes: Bool

    /// Check whether the scene contains materials
    /// Unless no special scene flags are set this will always be true.
    public var hasMaterials: Bool

    /// Check whether the scene contains lights
    public var hasLights: Bool

    /// Check whether the scene contains embedded textures
    public var hasTextures: Bool

    /// Check whether the scene contains cameras
    public var hasCameras: Bool

    /// Check whether the scene contains animations
    public var hasAnimations: Bool

    /// Any combination of the AI_SCENE_FLAGS_XXX flags.
    ///
    /// By default this value is 0, no flags are set.
    /// Most applications will want to reject all scenes with the AI_SCENE_FLAGS_INCOMPLETE bit set.
    public var flags: Flags

    /// The root node of the hierarchy.
    ///
    /// There will always be at least the root node if the import was successful (and no special flags have been set).
    /// Presence of further nodes depends on the format and content of the imported file.
    public var hasRootNode: Bool

    public var rootNode: AiNode? {
        guard let nodePtr = scenePtr.pointee.mRootNode else { return nil }
        return AiNode(nodePtr: nodePtr, lifetime: lifetime)
    }

    /// The number of meshes in the scene.
    public var numMeshes: Int

    /// The array of meshes.
    /// Use the indices given in the aiNode structure to access this array.
    /// The array is mNumMeshes in size.
    ///
    /// If the AI_SCENE_FLAGS_INCOMPLETE flag is not set there will always be at least ONE material.
    public var meshes: [AiMesh] {
        guard numMeshes > 0, let base = scenePtr.pointee.mMeshes else { return [] }
        return UnsafeBufferPointer(start: base, count: numMeshes).compactMap { ptr in
            guard let meshPtr = ptr else { return nil }
            return AiMesh(meshPtr: meshPtr, lifetime: lifetime)
        }
    }

    /// The number of materials in the scene.
    public var numMaterials: Int

    /// The array of materials.
    /// Use the index given in each aiMesh structure to access this array.
    /// The array is mNumMaterials in size.
    ///
    /// If the AI_SCENE_FLAGS_INCOMPLETE flag is not set there will always be at least ONE material.
    ///
    /// <http://assimp.sourceforge.net/lib_html/materials.html>
    public var materials: [AiMaterial] {
        guard numMaterials > 0, let base = scenePtr.pointee.mMaterials else { return [] }
        return UnsafeBufferPointer(start: base, count: numMaterials).compactMap { ptr in
            guard let materialPtr = ptr else { return nil }
            return AiMaterial(materialPtr: materialPtr, lifetime: lifetime)
        }
    }

    /// The number of animations in the scene.
    public var numAnimations: Int

    /// The array of animations.
    /// All animations imported from the given file are listed here.
    /// The array is mNumAnimations in size.
    public var animations: [AiAnimation] {
        guard numAnimations > 0, let base = scenePtr.pointee.mAnimations else { return [] }
        return UnsafeBufferPointer(start: base, count: numAnimations).compactMap { ptr in
            guard let anim = ptr?.pointee else { return nil }
            return AiAnimation(anim)
        }
    }

    /// The number of textures embedded into the file
    public var numTextures: Int

    /// The array of embedded textures.
    ///
    /// Not many file formats embed their textures into the file.
    /// An example is Quake's MDL format (which is also used by some GameStudio versions)
    public var textures: [AiTexture] {
        guard numTextures > 0, let base = scenePtr.pointee.mTextures else { return [] }
        return UnsafeBufferPointer(start: base, count: numTextures).compactMap {
            guard let texturePtr = $0 else { return nil }
            return AiTexture(texturePtr: texturePtr, lifetime: lifetime)
        }
    }

    /// The number of light sources in the scene.
    /// Light sources are fully optional, in most cases this attribute will be 0.
    public var numLights: Int

    /// The array of light sources.
    /// All light sources imported from the given file are listed here.
    /// The array is mNumLights in size.
    public var lights: [AiLight] {
        UnsafeBufferPointer(start: scenePtr.pointee.mLights, count: numLights).compactMap { AiLight($0?.pointee) }
    }

    /// The number of cameras in the scene.
    /// Cameras are fully optional, in most cases this attribute will be 0.
    public var numCameras: Int

    /// The array of cameras.
    /// All cameras imported from the given file are listed here.
    /// The array is mNumCameras in size.
    /// The first camera in the array (if existing) is the default camera view into the scene.
    public var cameras: [AiCamera] {
        UnsafeBufferPointer(start: scenePtr.pointee.mCameras, count: numCameras).compactMap { AiCamera($0?.pointee) }
    }

    public func mesh(at index: Int) -> AiMesh? {
        guard index >= 0, index < numMeshes, let base = scenePtr.pointee.mMeshes else { return nil }
        guard let meshPtr = base[index] else { return nil }
        return AiMesh(meshPtr: meshPtr, lifetime: lifetime)
    }
}

extension AiScene {
    public struct NodeHierarchySnapshot {
        public struct Node {
            public let name: String
            public let localTransform: AiMatrix4x4
            public let parentIndex: Int?
            public let childIndices: [Int]

            public init(name: String,
                        localTransform: AiMatrix4x4,
                        parentIndex: Int?,
                        childIndices: [Int]) {
                self.name = name
                self.localTransform = localTransform
                self.parentIndex = parentIndex
                self.childIndices = childIndices
            }
        }

        public let nodes: [Node]
        public let rootIndices: [Int]
        public let truncated: Bool

        public init(nodes: [Node],
                    rootIndices: [Int],
                    truncated: Bool) {
            self.nodes = nodes
            self.rootIndices = rootIndices
            self.truncated = truncated
        }
    }

    public struct ImportDiagnostics {
        public let hasRootNode: Bool
        public let meshCount: Int
        public let materialCount: Int
        public let animationCount: Int
        public let hasBonesOnMeshes: Bool
    }

    @inlinable
    public func meshes(for node: AiNode) -> [AiMesh] {
        node.meshes.compactMap { mesh(at: $0) }
    }

    /// Minimal importer-facing smoke diagnostics for debug logging.
    public func importDiagnostics() -> ImportDiagnostics {
        var hasBones = false
        for meshIndex in 0..<numMeshes {
            if let mesh = mesh(at: meshIndex), mesh.numBones > 0 {
                hasBones = true
                break
            }
        }
        return ImportDiagnostics(
            hasRootNode: hasRootNode,
            meshCount: numMeshes,
            materialCount: numMaterials,
            animationCount: numAnimations,
            hasBonesOnMeshes: hasBones
        )
    }

    public func rootMetadata() -> [String: AiMetadata.Entry]? {
        guard let rootNodePtr = scenePtr.pointee.mRootNode,
              let metadataPtr = rootNodePtr.pointee.mMetaData else {
            return nil
        }
        return AiMetadata(metadataPtr.pointee).metadata
    }

    public func nodeHierarchySnapshot(maxNodeCount: Int = 131_072,
                                      maxChildrenPerNode: Int = 16_384) -> NodeHierarchySnapshot {
        guard let rootNodePtr = scenePtr.pointee.mRootNode else {
            return NodeHierarchySnapshot(nodes: [], rootIndices: [], truncated: false)
        }

        var nodes: [NodeHierarchySnapshot.Node] = []
        var rootIndices: [Int] = []
        var indexByPointerAddress: [UInt: Int] = [:]
        var stack: [(UnsafePointer<aiNode>, Int?)] = [(UnsafePointer(rootNodePtr), nil)]
        var truncated = false
        var visitedCount = 0

        while let (nodePtr, parentIndex) = stack.popLast() {
            let address = UInt(bitPattern: nodePtr)
            if address < 0x1000 {
                truncated = true
                continue
            }
            if let existing = indexByPointerAddress[address] {
                if let parentIndex,
                   parentIndex >= 0,
                   parentIndex < nodes.count {
                    var parent = nodes[parentIndex]
                    if !parent.childIndices.contains(existing) {
                        var children = parent.childIndices
                        children.append(existing)
                        parent = NodeHierarchySnapshot.Node(
                            name: parent.name,
                            localTransform: parent.localTransform,
                            parentIndex: parent.parentIndex,
                            childIndices: children
                        )
                        nodes[parentIndex] = parent
                    }
                }
                continue
            }

            visitedCount += 1
            if visitedCount > maxNodeCount {
                truncated = true
                break
            }

            let node = nodePtr.pointee
            let nodeIndex = nodes.count
            let nodeName = String(node.mName) ?? ""
            let snapshotNode = NodeHierarchySnapshot.Node(
                name: nodeName,
                localTransform: AiMatrix4x4(node.mTransformation),
                parentIndex: parentIndex,
                childIndices: []
            )
            nodes.append(snapshotNode)
            indexByPointerAddress[address] = nodeIndex

            if let parentIndex,
               parentIndex >= 0,
               parentIndex < nodes.count {
                var parent = nodes[parentIndex]
                var children = parent.childIndices
                children.append(nodeIndex)
                parent = NodeHierarchySnapshot.Node(
                    name: parent.name,
                    localTransform: parent.localTransform,
                    parentIndex: parent.parentIndex,
                    childIndices: children
                )
                nodes[parentIndex] = parent
            } else {
                rootIndices.append(nodeIndex)
            }

            let childCount = Int(node.mNumChildren)
            if childCount <= 0 {
                continue
            }
            if childCount > maxChildrenPerNode {
                truncated = true
                continue
            }
            guard let childPtrArray = node.mChildren else {
                continue
            }
            for childIndex in stride(from: childCount - 1, through: 0, by: -1) {
                guard let childPtr = childPtrArray[childIndex] else { continue }
                stack.append((UnsafePointer<aiNode>(childPtr), nodeIndex))
            }
        }

        return NodeHierarchySnapshot(nodes: nodes, rootIndices: rootIndices, truncated: truncated)
    }
}
