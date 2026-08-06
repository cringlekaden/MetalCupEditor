//
// AiNode.swift
// SwiftAssimp
//
// Copyright © 2019-2023 Christian Treffs. All rights reserved.
// Licensed under BSD 3-Clause License. See LICENSE file for details.

@_implementationOnly import CAssimp

public struct AiNode {
    let nodePtr: UnsafePointer<aiNode>
    private let lifetime: AiSceneLifetime

    var node: aiNode { nodePtr.pointee }

    init(nodePtr: UnsafePointer<aiNode>, lifetime: AiSceneLifetime) {
        self.nodePtr = nodePtr
        self.lifetime = lifetime
    }

    init?(nodePtr: UnsafePointer<aiNode>?, lifetime: AiSceneLifetime) {
        guard let nodePtr else {
            return nil
        }
        self.init(nodePtr: nodePtr, lifetime: lifetime)
    }

    /// The name of the node.
    public var name: String? {
        String(node.mName)
    }

    /// The transformation relative to the node's parent.
    public var transformation: AiMatrix4x4 {
        AiMatrix4x4(node.mTransformation)
    }

    /// Parent node.
    ///
    /// NULL if this node is the root node.
    public var parent: AiNode? {
        AiNode(nodePtr: node.mParent, lifetime: lifetime)
    }

    /// The number of meshes of this node.
    public var numMeshes: Int {
        Int(node.mNumMeshes)
    }

    /// The number of child nodes of this node.
    public var numChildren: Int {
        Int(node.mNumChildren)
    }

    /// The meshes of this node.
    /// Each entry is an index into the mesh list of the #aiScene.
    public var meshes: [Int] {
        guard numMeshes > 0, let meshIndices = node.mMeshes else {
            return []
        }
        return (0 ..< numMeshes).map { Int(meshIndices[$0]) }
    }

    /// The child nodes of this node.
    ///
    /// NULL if mNumChildren is 0.
    public var children: [AiNode] {
        let count = numChildren
        guard count > 0, let childPtrs = node.mChildren else {
            return []
        }

        // Defensive clamp: malformed imports can report corrupt child counts.
        // Typical scene graphs (including Mixamo FBX) are far below this limit.
        let maxReasonableChildren = 16_384
        guard count <= maxReasonableChildren else { return [] }

        var result: [AiNode] = []
        result.reserveCapacity(count)
        for index in 0..<count {
            guard let ptr = childPtrs[index] else { continue }
            result.append(AiNode(nodePtr: ptr, lifetime: lifetime))
        }
        return result
    }

    /// Metadata associated with this node or NULL if there is no metadata.
    /// Whether any metadata is generated depends on the source file format.
    public var metaData: AiMetadata? {
        guard let meta = node.mMetaData else {
            return nil
        }
        return AiMetadata(meta.pointee)
    }
}

extension AiNode: CustomDebugStringConvertible {
    public var debugDescription: String {
        "<AiNode '\(name ?? "")' meshes:\(meshes) children:\(numChildren)>"
    }
}

/// Container for holding metadata.
/// Metadata is a key-value store using string keys and values.
public struct AiMetadata {
    init(_ meta: aiMetadata) {
        numProperties = Int(meta.mNumProperties)
        keys = UnsafeBufferPointer(start: meta.mKeys, count: numProperties).compactMap(String.init)
        values = UnsafeBufferPointer(start: meta.mValues, count: numProperties).compactMap(Entry.init)
    }

    /// Length of the mKeys and mValues arrays, respectively
    public var numProperties: Int

    /// Arrays of keys, may not be NULL.
    /// Entries in this array may not be NULL as well.
    public var keys: [String]

    /// Arrays of values, may not be NULL.
    /// Entries in this array may be NULL if the corresponding property key has no assigned value.
    public var values: [Entry]

    public var metadata: [String: Entry] {
        [String: Entry](uniqueKeysWithValues: (0 ..< numProperties).map { (keys[$0], values[$0]) })
    }

    public enum Entry {
        case bool(Bool)
        case int32(Int32)
        case uint64(UInt64)
        case float(Float)
        case double(Double)
        case string(String)
        case vec3(Vec3)
        case metadata(AiMetadata)

        init?(_ entry: aiMetadataEntry) {
            guard let pData = entry.mData else {
                return nil
            }

            switch entry.mType {
            case AI_BOOL:
                self = .bool(pData.bindMemory(to: Bool.self, capacity: 1).pointee)

            case AI_INT32:
                self = .int32(pData.bindMemory(to: Int32.self, capacity: 1).pointee)

            case AI_UINT64:
                self = .uint64(pData.bindMemory(to: UInt64.self, capacity: 1).pointee)

            case AI_FLOAT:
                self = .float(pData.bindMemory(to: Float.self, capacity: 1).pointee)

            case AI_DOUBLE:
                self = .double(pData.bindMemory(to: Double.self, capacity: 1).pointee)

            case AI_AISTRING:
                guard let string = String(pData.bindMemory(to: aiString.self, capacity: 1).pointee) else {
                    return nil
                }
                self = .string(string)

            case AI_AIVECTOR3D:
                self = .vec3(Vec3(pData.bindMemory(to: aiVector3D.self, capacity: 1).pointee))

            case AI_AIMETADATA:
                self = .metadata(AiMetadata(pData.bindMemory(to: aiMetadata.self, capacity: 1).pointee))

            case AI_META_MAX:
                return nil

            case FORCE_32BIT:
                return nil

            default:
                return nil
            }
        }
    }
}
