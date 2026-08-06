import Foundation
import simd
import Assimp
import MetalCupEngine

enum AssimpFBXImportMode: String {
    case staticMesh
    case skeletalMesh
    case animationOnly
}

struct ImportedMeshData {
    let name: String
    let positions: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let tangents: [SIMD3<Float>]
    let uv0: [SIMD2<Float>]
    let indices: [UInt32]
    let materialIndex: Int
    let hasSkinning: Bool
    let jointIndices: [SIMD4<UInt16>]
    let jointWeights: [SIMD4<Float>]

    var vertexCount: Int { positions.count }
    var indexCount: Int { indices.count }
    var hasNormals: Bool { normals.count == positions.count && !normals.isEmpty }
    var hasTangents: Bool { tangents.count == positions.count && !tangents.isEmpty }
    var hasUVs: Bool { uv0.count == positions.count && !uv0.isEmpty }
}

struct ImportedSkeletonData {
    let joints: [SkeletonAsset.Joint]
    let inverseBindGlobalByJointName: [String: simd_float4x4]
}

struct ImportedAnimationClipData {
    let name: String
    let durationSeconds: Float
    let tracks: [AnimationClipAsset.JointTrack]
    let interpolation: String
    let hasRootMotion: Bool
    let rootMotionJointIndex: Int?
    let rootMotionJointName: String?
}

struct ImportedMaterialReferenceData {
    let name: String
    let baseColor: SIMD3<Float>
    let emissiveColor: SIMD3<Float>
    let metallicFactor: Float
    let roughnessFactor: Float
    let alphaMode: MaterialAlphaMode
    let alphaCutoff: Float
    let textures: [MeshTextureSemantic: URL]
    let embeddedTextureSemantics: Set<MeshTextureSemantic>
}

struct ImportedFBXData {
    let mode: AssimpFBXImportMode
    let meshes: [ImportedMeshData]
    let skeleton: ImportedSkeletonData?
    let clips: [ImportedAnimationClipData]
    let materials: [ImportedMaterialReferenceData]
    let warnings: [String]
    let importScaleFactor: Float
    let importScaleNormalizationMode: String
    let importScaleSource: String
}

private struct BakedMeshVertexDocument: Codable {
    let position: [Float]
    let normal: [Float]?
    let tangent: [Float]?
    let texCoord0: [Float]?
    let jointIndices: [UInt16]?
    let jointWeights: [Float]?
}

private struct BakedMeshSubmeshDocument: Codable {
    let name: String
    let materialIndex: Int
    let indices: [UInt32]
}

private struct BakedMeshDocument: Codable {
    let schemaVersion: Int
    let name: String
    let hasSkinning: Bool
    let vertices: [BakedMeshVertexDocument]
    let submeshes: [BakedMeshSubmeshDocument]
}

private struct AssimpSmokeDiagnostics {
    let filePath: String
    let loaded: Bool
    let hasRootNode: Bool
    let nativeMeshCount: Int
    let bridgedMeshCount: Int
    let animationCount: Int
    let hasBonesOnMeshes: Bool
    let chosenMode: String
    var error: String

    func formatted(prefix: String) -> String {
        let loadString = loaded ? "true" : "false"
        return "\(prefix) path=\(filePath)\nloaded=\(loadString)\nhasRoot=\(hasRootNode)\nnativeMeshes=\(nativeMeshCount)\nbridgedMeshes=\(bridgedMeshCount)\nanimations=\(animationCount)\nhasBonesOnMeshes=\(hasBonesOnMeshes)\nmode=\(chosenMode)\nerror=\(error)"
    }
}

private struct SkeletonExtractionDiagnostics {
    let jointCount: Int
    let rootJointCount: Int
    let unresolvedParentCount: Int
    let importedInverseBindCount: Int
    let helperNodeFilteredCount: Int
    let helperNodeCollapsedCount: Int
    let traversalTruncated: Bool
    let nodeSnapshotSize: Int
    let nodeSnapshotRootCount: Int
    let sampleJointParentEntries: [String]
}

private struct MeshMappingDiagnostics {
    let totalBoneNames: Int
    let mappedBoneNames: Int
    let unmappedBoneNames: [String]
}

private struct AnimationMappingDiagnostics {
    let totalChannels: Int
    let mappedChannels: Int
    let unmappedChannelNames: [String]
}

private struct FBXImportSummaryDiagnostics {
    let meshCount: Int
    let jointCount: Int
    let rootJointCount: Int
    let trackCount: Int
    let materialCount: Int
    let importedInverseBindCount: Int
}

private struct AssimpLoadAttempt {
    let label: String
    let flags: AiPostProcessStep
}

enum AssimpAdapter {
    private static var loggedDiagnostics: Set<String> = []

    static func scanFBX(url: URL, suggestedName: String) -> ImportedFBXData? {
        let attempts: [AssimpLoadAttempt] = [
            AssimpLoadAttempt(
                label: "full",
                flags: [
                    .triangulate,
                    .joinIdenticalVertices,
                    .genSmoothNormals,
                    .calcTangentSpace,
                    .limitBoneWeights
                ]
            ),
            AssimpLoadAttempt(
                label: "safe",
                flags: [
                    .triangulate,
                    .limitBoneWeights
                ]
            ),
            AssimpLoadAttempt(
                label: "minimal",
                flags: []
            )
        ]

        let scene: AiScene
        var diagnostics = AssimpSmokeDiagnostics(
            filePath: url.path,
            loaded: false,
            hasRootNode: false,
            nativeMeshCount: 0,
            bridgedMeshCount: 0,
            animationCount: 0,
            hasBonesOnMeshes: false,
            chosenMode: "<unresolved>",
            error: ""
        )
        var loadedScene: AiScene?
        var loadErrors: [String] = []
        for attempt in attempts {
            do {
                let candidate = try AiScene(file: url.path, flags: attempt.flags)
                loadedScene = candidate
                let hasBonesOnMeshes = (0..<candidate.numMeshes).contains { index in
                    (candidate.mesh(at: index)?.numBones ?? 0) > 0
                }
                diagnostics = AssimpSmokeDiagnostics(
                    filePath: url.path,
                    loaded: true,
                    hasRootNode: candidate.hasRootNode,
                    nativeMeshCount: candidate.numMeshes,
                    bridgedMeshCount: candidate.meshes.count,
                    animationCount: candidate.numAnimations,
                    hasBonesOnMeshes: hasBonesOnMeshes,
                    chosenMode: "<pending>",
                    error: ""
                )
                break
            } catch {
                loadErrors.append("\(attempt.label): \(error)")
            }
        }
        guard let loadedScene else {
            diagnostics.error = loadErrors.joined(separator: " | ")
#if DEBUG
            logDiagnosticsOnce(diagnostics, level: .error, prefix: "FBX Assimp load failed")
#endif
            return nil
        }
        scene = loadedScene

        let (skeleton, skeletonDiagnostics) = extractSkeleton(from: scene)
        let jointIndexByName = Dictionary(uniqueKeysWithValues: (skeleton?.joints ?? []).enumerated().map { ($1.name, $0) })
        let (importedMeshes, meshMappingDiagnostics) = extractMeshes(from: scene, jointIndexByName: jointIndexByName)
        let importedMaterials = extractMaterials(from: scene, sourceURL: url)
#if DEBUG
        if scene.numMaterials > 0 && importedMaterials.isEmpty {
            logMaterialWarningOnce(path: url.path, reason: "All material extraction failed; continuing import with mesh/skeleton/animation data.")
        } else if importedMaterials.count < scene.numMaterials {
            logMaterialWarningOnce(path: url.path, reason: "Material extraction was partial (\(importedMaterials.count)/\(scene.numMaterials)); continuing import.")
        }
#endif
        let (clips, animationMappingDiagnostics) = extractAnimations(from: scene, skeleton: skeleton, suggestedName: suggestedName)
        let normalization = detectFBXScaleNormalization(scene: scene, meshes: importedMeshes, modeHint: skeleton != nil ? .skeletalMesh : .staticMesh)
        let normalizedMeshes = applyScaleNormalization(to: importedMeshes, factor: normalization.factor)
        let normalizedSkeleton = applyScaleNormalization(to: skeleton, factor: normalization.factor)
        let normalizedClips = applyScaleNormalization(to: clips, factor: normalization.factor)

        let hasMeshes = !normalizedMeshes.isEmpty
        let hasSkinnedMesh = normalizedMeshes.contains(where: { $0.hasSkinning }) && normalizedSkeleton != nil
        let mode: AssimpFBXImportMode
        if !hasMeshes && !clips.isEmpty {
            mode = .animationOnly
        } else if hasSkinnedMesh {
            mode = .skeletalMesh
        } else {
            mode = .staticMesh
        }
        diagnostics = AssimpSmokeDiagnostics(
            filePath: diagnostics.filePath,
            loaded: diagnostics.loaded,
            hasRootNode: diagnostics.hasRootNode,
            nativeMeshCount: diagnostics.nativeMeshCount,
            bridgedMeshCount: diagnostics.bridgedMeshCount,
            animationCount: diagnostics.animationCount,
            hasBonesOnMeshes: diagnostics.hasBonesOnMeshes,
            chosenMode: mode.rawValue,
            error: diagnostics.error
        )

        var warnings: [String] = []
        if !hasMeshes && mode != .animationOnly {
            warnings.append("No meshes found in FBX via Assimp.")
        }
        if hasMeshes && hasSkinnedMesh && normalizedSkeleton == nil {
            warnings.append("Skinned mesh detected but skeleton extraction failed.")
        }
        if hasMeshes && normalizedMeshes.contains(where: { $0.hasSkinning }) && !hasSkinnedMesh {
            warnings.append("Joint streams found but skeleton hierarchy was incomplete.")
        }
#if DEBUG
        logMeshDiagnosticsOnce(filePath: url.path, scene: scene)
        let importSummary = FBXImportSummaryDiagnostics(
            meshCount: normalizedMeshes.count,
            jointCount: skeletonDiagnostics.jointCount,
            rootJointCount: skeletonDiagnostics.rootJointCount,
            trackCount: normalizedClips.reduce(into: 0) { count, clip in
                count += clip.tracks.count
            },
            materialCount: importedMaterials.count,
            importedInverseBindCount: skeletonDiagnostics.importedInverseBindCount
        )
        logImportSummaryOnce(filePath: url.path, summary: importSummary)
        logNodeSnapshotDiagnosticsOnce(
            filePath: url.path,
            snapshotSize: skeletonDiagnostics.nodeSnapshotSize,
            rootCount: skeletonDiagnostics.nodeSnapshotRootCount,
            truncated: skeletonDiagnostics.traversalTruncated
        )
        logSkeletonMappingDiagnosticsOnce(
            filePath: url.path,
            skeleton: skeleton,
            skeletonDiagnostics: skeletonDiagnostics,
            meshDiagnostics: meshMappingDiagnostics,
            animationDiagnostics: animationMappingDiagnostics
        )
        if importedMeshes.isEmpty || !diagnostics.error.isEmpty {
            logDiagnosticsOnce(diagnostics, level: .error, prefix: "FBX Assimp mesh extraction produced zero meshes")
        }
        logScaleNormalizationOnce(filePath: url.path, normalization: normalization)
#endif

        return ImportedFBXData(
            mode: mode,
            meshes: normalizedMeshes,
            skeleton: normalizedSkeleton,
            clips: normalizedClips,
            materials: importedMaterials,
            warnings: warnings,
            importScaleFactor: normalization.factor,
            importScaleNormalizationMode: normalization.mode,
            importScaleSource: "assimpNormalization"
        )
    }

    static func writeBakedMeshAsset(from data: ImportedFBXData,
                                    name: String,
                                    to url: URL) -> Bool {
        guard !data.meshes.isEmpty else { return false }

        var bakedVertices: [BakedMeshVertexDocument] = []
        bakedVertices.reserveCapacity(data.meshes.reduce(0) { $0 + $1.positions.count })
        var bakedSubmeshes: [BakedMeshSubmeshDocument] = []
        bakedSubmeshes.reserveCapacity(data.meshes.count)
        var hasSkinning = false

        for mesh in data.meshes {
            let baseVertex = bakedVertices.count
            let vertexCount = mesh.positions.count
            hasSkinning = hasSkinning || mesh.hasSkinning

            for index in 0..<vertexCount {
                let position = mesh.positions[index]
                let normal = index < mesh.normals.count ? mesh.normals[index] : SIMD3<Float>(0, 1, 0)
                let tangent = index < mesh.tangents.count ? mesh.tangents[index] : SIMD3<Float>(1, 0, 0)
                let uv = index < mesh.uv0.count ? mesh.uv0[index] : SIMD2<Float>(0, 0)
                let jointIndex = index < mesh.jointIndices.count ? mesh.jointIndices[index] : SIMD4<UInt16>(0, 0, 0, 0)
                let jointWeight = index < mesh.jointWeights.count ? mesh.jointWeights[index] : SIMD4<Float>(1, 0, 0, 0)

                bakedVertices.append(
                    BakedMeshVertexDocument(
                        position: [position.x, position.y, position.z],
                        normal: [normal.x, normal.y, normal.z],
                        tangent: [tangent.x, tangent.y, tangent.z, 1.0],
                        texCoord0: [uv.x, uv.y],
                        jointIndices: [jointIndex.x, jointIndex.y, jointIndex.z, jointIndex.w],
                        jointWeights: [jointWeight.x, jointWeight.y, jointWeight.z, jointWeight.w]
                    )
                )
            }

            let adjustedIndices = mesh.indices.map { UInt32(baseVertex) + $0 }
            bakedSubmeshes.append(
                BakedMeshSubmeshDocument(
                    name: mesh.name,
                    materialIndex: mesh.materialIndex,
                    indices: adjustedIndices
                )
            )
        }

        let document = BakedMeshDocument(
            schemaVersion: 1,
            name: sanitizeName(name),
            hasSkinning: hasSkinning,
            vertices: bakedVertices,
            submeshes: bakedSubmeshes
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let encoded = try encoder.encode(document)
            try encoded.write(to: url, options: .atomic)
#if DEBUG
            let skinnedVertices = bakedVertices.reduce(into: 0) { count, vertex in
                if let weights = vertex.jointWeights, weights.contains(where: { $0 > 0.0001 }) {
                    count += 1
                }
            }
            EngineLoggerContext.log(
                "FBX baked mesh write path=\(url.path)\nvertices=\(bakedVertices.count)\nsubmeshes=\(bakedSubmeshes.count)\nhasSkinning=\(hasSkinning)\nskinnedVertices=\(skinnedVertices)",
                level: .debug,
                category: .assets
            )
#endif
            return true
        } catch {
            EngineLoggerContext.log(
                "Failed to write baked FBX mesh path=\(url.path): \(error.localizedDescription)",
                level: .error,
                category: .assets
            )
            return false
        }
    }

    static func makeMeshScanInfo(from data: ImportedFBXData) -> MeshScanInfo {
        let materialNames = data.materials.map(\.name)
        var textureNames: [String] = []
        var meshMaterials: [MeshScanMaterial] = []
        for material in data.materials {
            var textures: [MeshTextureSemantic: MeshScanTexture] = [:]
            for (semantic, resolvedURL) in material.textures {
                let isEmbedded = material.embeddedTextureSemantics.contains(semantic)
                textures[semantic] = MeshScanTexture(
                    semantic: semantic,
                    url: isEmbedded ? nil : resolvedURL,
                    name: resolvedURL.lastPathComponent,
                    isEmbedded: isEmbedded,
                    mdlTexture: nil
                )
                textureNames.append(resolvedURL.lastPathComponent)
            }
            meshMaterials.append(
                MeshScanMaterial(
                    name: material.name,
                    baseColor: material.baseColor,
                    emissiveColor: material.emissiveColor,
                    metallicFactor: material.metallicFactor,
                    roughnessFactor: material.roughnessFactor,
                    aoFactor: 1.0,
                    alphaMode: material.alphaMode,
                    alphaCutoff: material.alphaCutoff,
                    doubleSided: false,
                    unlit: false,
                    textures: textures
                )
            )
        }

        let submeshMaterialIndices = data.meshes.map { mesh in
            mesh.materialIndex >= 0 && mesh.materialIndex < materialNames.count ? mesh.materialIndex : -1
        }
        let hasNormals = data.meshes.contains(where: { $0.hasNormals })
        let hasTangents = data.meshes.contains(where: { $0.hasTangents })
        let hasUVs = data.meshes.contains(where: { $0.hasUVs })
        let isSkinned = data.mode == .skeletalMesh
        let embeddedCount = data.materials.reduce(into: 0) { partialResult, material in
            partialResult += material.embeddedTextureSemantics.count
        }
        let skeletonInfo = data.skeleton.map { skel in
            MeshSkeletonScanInfo(jointCount: skel.joints.count, joints: skel.joints)
        }
        let clipInfos = data.clips.map { clip in
            MeshAnimationClipScanInfo(
                name: clip.name,
                durationSeconds: clip.durationSeconds,
                tracks: clip.tracks
            )
        }
        let hasRootMotion = data.clips.contains(where: { $0.hasRootMotion })
        let rootMotionBoneName = data.clips.compactMap(\.rootMotionJointName).first

        return MeshScanInfo(
            meshCount: data.meshes.count,
            submeshCount: data.meshes.count,
            submeshMaterialIndices: submeshMaterialIndices,
            materialNames: materialNames,
            textureNames: Array(Set(textureNames)).sorted(),
            hasUVs: hasUVs,
            hasNormals: hasNormals,
            hasTangents: hasTangents,
            suggestFlipNormalY: false,
            embeddedTextureCount: embeddedCount,
            isSkinned: isSkinned,
            skeletonInfo: skeletonInfo,
            clipInfos: clipInfos,
            hasRootMotion: hasRootMotion,
            rootMotionBoneName: rootMotionBoneName,
            warnings: data.warnings,
            materials: meshMaterials
        )
    }
}

private extension AssimpAdapter {
    struct FBXScaleNormalization {
        let factor: Float
        let mode: String
        let reason: String
    }

    struct NodeHierarchyRecord {
        let displayName: String
        let canonicalName: String
        let parentCanonicalName: String?
        let localTransform: matrix_float4x4
    }

    struct NodeHierarchySnapshot {
        let nodes: [AiScene.NodeHierarchySnapshot.Node]
        let rootIndices: [Int]

        var rootCount: Int { rootIndices.count }
    }

    struct NodeHierarchyExtraction {
        let snapshot: NodeHierarchySnapshot
        let nodesByName: [String: NodeHierarchyRecord]
        let traversalOrder: [String]
        let truncated: Bool
    }

    static func matrixIsFinite(_ matrix: matrix_float4x4) -> Bool {
        for column in 0..<4 {
            let value = matrix[column]
            if !value.x.isFinite || !value.y.isFinite || !value.z.isFinite || !value.w.isFinite {
                return false
            }
        }
        return true
    }

    static func sanitizedVertexStream<T>(_ stream: [T], expectedCount: Int) -> [T] {
        guard stream.count == expectedCount else { return [] }
        return stream
    }

    static func canonicalJointName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        var normalized = trimmed.replacingOccurrences(of: "\\", with: "/")
        if let lastPath = normalized.split(separator: "/").last {
            normalized = String(lastPath)
        }
        if let lastNode = normalized.split(separator: "|").last {
            normalized = String(lastNode)
        }
        if let namespaceSplit = normalized.split(separator: ":").last {
            normalized = String(namespaceSplit)
        }
        return normalized.lowercased()
    }

    static func isHelperJointCandidate(canonicalName: String) -> Bool {
        if canonicalName.hasSuffix("_end") || canonicalName.hasSuffix("end") {
            return true
        }
        if canonicalName.contains("endsite") {
            return true
        }
        if canonicalName.contains("ik") || canonicalName.contains("pole") {
            return true
        }
        if canonicalName.contains("ctrl") || canonicalName.contains("control") {
            return true
        }
        return false
    }

    static func extractNodeHierarchy(from scene: AiScene) -> NodeHierarchyExtraction {
        let sourceSnapshot = scene.nodeHierarchySnapshot(maxNodeCount: 131_072, maxChildrenPerNode: 16_384)
        let snapshotNodes = sourceSnapshot.nodes
        var nodesByName: [String: NodeHierarchyRecord] = [:]
        var traversalOrder: [String] = []
        traversalOrder.reserveCapacity(snapshotNodes.count)
        nodesByName.reserveCapacity(snapshotNodes.count)
        for snapshotNode in snapshotNodes {
            let displayName = snapshotNode.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let canonicalName = canonicalJointName(displayName)
            guard !canonicalName.isEmpty else { continue }
            traversalOrder.append(canonicalName)
            let parentCanonicalName: String?
            if let parentIndex = snapshotNode.parentIndex,
               parentIndex >= 0,
               parentIndex < snapshotNodes.count {
                parentCanonicalName = canonicalJointName(snapshotNodes[parentIndex].name)
            } else {
                parentCanonicalName = nil
            }
            let record = NodeHierarchyRecord(
                displayName: displayName.isEmpty ? canonicalName : displayName,
                canonicalName: canonicalName,
                parentCanonicalName: parentCanonicalName,
                localTransform: simdMatrix(from: snapshotNode.localTransform)
            )
            nodesByName[canonicalName] = record
        }

        return NodeHierarchyExtraction(
            snapshot: NodeHierarchySnapshot(nodes: snapshotNodes, rootIndices: sourceSnapshot.rootIndices),
            nodesByName: nodesByName,
            traversalOrder: traversalOrder,
            truncated: sourceSnapshot.truncated
        )
    }

    static func detectFBXScaleNormalization(scene: AiScene,
                                            meshes: [ImportedMeshData],
                                            modeHint: AssimpFBXImportMode) -> FBXScaleNormalization {
        if let metadataFactor = scaleFactorFromRootMetadata(scene: scene),
           abs(metadataFactor - 1.0) > 0.0001 {
            return FBXScaleNormalization(factor: metadataFactor,
                                         mode: "fbxUnitScaleMetadata",
                                         reason: "root metadata unit scale")
        }

        if modeHint == .skeletalMesh,
           let maxExtent = maximumMeshExtent(meshes: meshes),
           maxExtent > 10.0 {
            return FBXScaleNormalization(factor: 0.01,
                                         mode: "skeletalBoundsHeuristicCmToM",
                                         reason: "max extent \(String(format: "%.3f", maxExtent)) > 10")
        }

        return FBXScaleNormalization(factor: 1.0,
                                     mode: "none",
                                     reason: "no normalization needed")
    }

    static func scaleFactorFromRootMetadata(scene: AiScene) -> Float? {
        guard let metadata = scene.rootMetadata() else { return nil }
        let candidateKeys = ["UnitScaleFactor", "OriginalUnitScaleFactor", "UnitScale"]
        for key in candidateKeys {
            guard let entry = metadata[key],
                  let raw = numericValue(from: entry),
                  raw > 0 else { continue }
            if raw > 1.5 || raw < 0.75 {
                return 1.0 / raw
            }
            return 1.0
        }
        return nil
    }

    static func numericValue(from entry: AiMetadata.Entry) -> Float? {
        switch entry {
        case let .float(value):
            return value
        case let .double(value):
            return Float(value)
        case let .int32(value):
            return Float(value)
        case let .uint64(value):
            return Float(value)
        case let .string(value):
            return Float(value)
        default:
            return nil
        }
    }

    static func maximumMeshExtent(meshes: [ImportedMeshData]) -> Float? {
        guard !meshes.isEmpty else { return nil }
        var minBounds = SIMD3<Float>(repeating: Float.greatestFiniteMagnitude)
        var maxBounds = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
        var hasAny = false
        for mesh in meshes {
            for position in mesh.positions {
                hasAny = true
                minBounds = simd.min(minBounds, position)
                maxBounds = simd.max(maxBounds, position)
            }
        }
        guard hasAny else { return nil }
        let extent = maxBounds - minBounds
        return max(extent.x, max(extent.y, extent.z))
    }

    static func applyScaleNormalization(to meshes: [ImportedMeshData], factor: Float) -> [ImportedMeshData] {
        guard abs(factor - 1.0) > 0.0001 else { return meshes }
        return meshes.map { mesh in
            ImportedMeshData(
                name: mesh.name,
                positions: mesh.positions.map { $0 * factor },
                normals: mesh.normals,
                tangents: mesh.tangents,
                uv0: mesh.uv0,
                indices: mesh.indices,
                materialIndex: mesh.materialIndex,
                hasSkinning: mesh.hasSkinning,
                jointIndices: mesh.jointIndices,
                jointWeights: mesh.jointWeights
            )
        }
    }

    static func applyScaleNormalization(to skeleton: ImportedSkeletonData?, factor: Float) -> ImportedSkeletonData? {
        guard let skeleton else { return nil }
        guard abs(factor - 1.0) > 0.0001 else { return skeleton }
        let scaledInverseBindByName: [String: simd_float4x4] = Dictionary(uniqueKeysWithValues: skeleton.inverseBindGlobalByJointName.map { entry in
            let bindGlobal = simd_inverse(entry.value)
            var scaledBindGlobal = bindGlobal
            scaledBindGlobal.columns.3.x *= factor
            scaledBindGlobal.columns.3.y *= factor
            scaledBindGlobal.columns.3.z *= factor
            let scaledInverse = simd_inverse(scaledBindGlobal)
            return (entry.key, scaledInverse)
        })
        let scaledJoints = skeleton.joints.map { joint in
            let inverseBind = scaledInverseBindByName[joint.name] ?? joint.inverseBindGlobalMatrix
            return SkeletonAsset.Joint(
                name: joint.name,
                parentIndex: joint.parentIndex,
                bindLocalPosition: joint.bindLocalPosition * factor,
                bindLocalRotation: joint.bindLocalRotation,
                bindLocalScale: joint.bindLocalScale,
                inverseBindGlobalMatrix: inverseBind
            )
        }
        return ImportedSkeletonData(joints: scaledJoints, inverseBindGlobalByJointName: scaledInverseBindByName)
    }

    static func applyScaleNormalization(to clips: [ImportedAnimationClipData], factor: Float) -> [ImportedAnimationClipData] {
        guard abs(factor - 1.0) > 0.0001 else { return clips }
        return clips.map { clip in
            let scaledTracks = clip.tracks.map { track in
                AnimationClipAsset.JointTrack(
                    jointIndex: track.jointIndex,
                    translations: track.translations.map { .init(time: $0.time, value: $0.value * factor) },
                    rotations: track.rotations,
                    scales: track.scales
                )
            }
            let hasRootMotion: Bool
            if let rootJointIndex = clip.rootMotionJointIndex {
                hasRootMotion = scaledTracks.contains { track in
                    guard track.jointIndex == rootJointIndex, track.translations.count > 1 else { return false }
                    let first = track.translations[0].value
                    return track.translations.contains { simd_length($0.value - first) > 0.001 }
                }
            } else {
                hasRootMotion = scaledTracks.contains { track in
                    guard track.translations.count > 1 else { return false }
                    let first = track.translations[0].value
                    return track.translations.contains { simd_length($0.value - first) > 0.001 }
                }
            }
            return ImportedAnimationClipData(
                name: clip.name,
                durationSeconds: clip.durationSeconds,
                tracks: scaledTracks,
                interpolation: clip.interpolation,
                hasRootMotion: hasRootMotion,
                rootMotionJointIndex: clip.rootMotionJointIndex,
                rootMotionJointName: clip.rootMotionJointName
            )
        }
    }

    static func extractMeshes(from scene: AiScene,
                              jointIndexByName: [String: Int]) -> ([ImportedMeshData], MeshMappingDiagnostics) {
        let jointIndexByCanonicalName = Dictionary(uniqueKeysWithValues: jointIndexByName.map { (canonicalJointName($0.key), $0.value) })
        let indices = Array(0..<scene.numMeshes)
        var mappedBoneNames = Set<String>()
        var totalBoneNames = Set<String>()
        var unmappedBoneNames = Set<String>()
        let meshes: [ImportedMeshData] = indices.compactMap { meshIndex in
            guard let mesh = scene.mesh(at: meshIndex) else { return nil }
            let positions = unpackVector3Array(mesh.vertices)
            let normals = unpackVector3Array(mesh.normals)
            let tangents = unpackVector3Array(mesh.tangents)
            let uv0Raw = mesh.texCoordsPacked.0 ?? []
            let uv0 = unpackVector2Array(uv0Raw)
            guard !positions.isEmpty else { return nil }
            let indices = mesh.faces.flatMap(\.indices).filter { $0 >= 0 && $0 < positions.count }

            var jointIndices = Array(repeating: SIMD4<UInt16>(repeating: 0), count: positions.count)
            var jointWeights = Array(repeating: SIMD4<Float>(repeating: 0), count: positions.count)

            if mesh.numBones > 0 {
                for bone in mesh.bones {
                    guard let boneName = bone.name, !boneName.isEmpty else { continue }
                    totalBoneNames.insert(boneName)
                    let resolvedJointIndex = jointIndexByName[boneName]
                        ?? jointIndexByCanonicalName[canonicalJointName(boneName)]
                    guard let jointIndex = resolvedJointIndex else {
                        unmappedBoneNames.insert(boneName)
                        continue
                    }
                    mappedBoneNames.insert(boneName)
                    for weight in bone.weights where weight.vertexId >= 0 && weight.vertexId < positions.count {
                        guard weight.weight.isFinite, weight.weight > 0 else { continue }
                        let slot = nextWeightSlot(for: weight.vertexId, weights: jointWeights)
                        if slot >= 0 && slot < 4 {
                            jointIndices[weight.vertexId][slot] = UInt16(clamping: jointIndex)
                            jointWeights[weight.vertexId][slot] = weight.weight
                            continue
                        }
                        var smallestSlot = 0
                        var smallestWeight = jointWeights[weight.vertexId][0]
                        for candidate in 1..<4 where jointWeights[weight.vertexId][candidate] < smallestWeight {
                            smallestSlot = candidate
                            smallestWeight = jointWeights[weight.vertexId][candidate]
                        }
                        if weight.weight > smallestWeight {
                            jointIndices[weight.vertexId][smallestSlot] = UInt16(clamping: jointIndex)
                            jointWeights[weight.vertexId][smallestSlot] = weight.weight
                        }
                    }
                }
                for i in 0..<jointWeights.count {
                    let sum = simd_reduce_add(jointWeights[i])
                    if sum > 0.0001 {
                        jointWeights[i] /= sum
                    } else {
                        jointWeights[i] = SIMD4<Float>(1, 0, 0, 0)
                        jointIndices[i] = SIMD4<UInt16>(0, 0, 0, 0)
                    }
                }
            }

            return ImportedMeshData(
                name: mesh.name ?? "",
                positions: positions,
                normals: sanitizedVertexStream(normals, expectedCount: positions.count),
                tangents: sanitizedVertexStream(tangents, expectedCount: positions.count),
                uv0: sanitizedVertexStream(uv0, expectedCount: positions.count),
                indices: indices,
                materialIndex: mesh.materialIndex,
                hasSkinning: mesh.numBones > 0,
                jointIndices: jointIndices,
                jointWeights: jointWeights
            )
        }
        let diagnostics = MeshMappingDiagnostics(
            totalBoneNames: totalBoneNames.count,
            mappedBoneNames: mappedBoneNames.count,
            unmappedBoneNames: Array(unmappedBoneNames).sorted()
        )
        return (meshes, diagnostics)
    }

    static func extractMaterials(from scene: AiScene, sourceURL: URL) -> [ImportedMaterialReferenceData] {
        // NOTE: SwiftAssimp material accessors are still unstable for some FBX files.
        // Keep FBX import unblocked by emitting conservative placeholder material metadata.
        return (0..<scene.numMaterials).map { index in
            ImportedMaterialReferenceData(
                name: "Material_\(index + 1)",
                baseColor: SIMD3<Float>(repeating: 1),
                emissiveColor: SIMD3<Float>(repeating: 0),
                metallicFactor: 0.0,
                roughnessFactor: 1.0,
                alphaMode: .opaque,
                alphaCutoff: 0.5,
                textures: [:],
                embeddedTextureSemantics: []
            )
        }
    }

    static func resolveTexture(semantic: MeshTextureSemantic,
                               type: AiTextureType,
                               material: AiMaterial,
                               sourceFolder: URL,
                               into textureMap: inout [MeshTextureSemantic: URL],
                               embeddedSemantics: inout Set<MeshTextureSemantic>) {
        guard textureMap[semantic] == nil else { return }
        let count = material.getMaterialTextureCount(texType: type)
        guard count > 0, let texturePath = material.getMaterialTexture(texType: type, texIndex: 0), !texturePath.isEmpty else { return }
        if texturePath.hasPrefix("*") {
            embeddedSemantics.insert(semantic)
            textureMap[semantic] = sourceFolder.appendingPathComponent("embedded_\(semantic.rawValue).png")
            return
        }
        let url: URL
        if texturePath.hasPrefix("/") {
            url = URL(fileURLWithPath: texturePath)
        } else {
            url = sourceFolder.appendingPathComponent(texturePath)
        }
        textureMap[semantic] = url.standardizedFileURL
    }

    static func extractSkeleton(from scene: AiScene) -> (ImportedSkeletonData?, SkeletonExtractionDiagnostics) {
        let hasSkinnedMesh = (0..<scene.numMeshes).contains { index in
            (scene.mesh(at: index)?.numBones ?? 0) > 0
        }
        let animationNodeNames = Set(scene.animations.flatMap { animation in
            animation.channels.compactMap { $0.nodeName }.filter { !$0.isEmpty }
        })

        var boneNames: Set<String> = []
        var inverseBindByName: [String: simd_float4x4] = [:]
        for index in 0..<scene.numMeshes {
            guard let mesh = scene.mesh(at: index), mesh.numBones > 0 else { continue }
            for bone in mesh.bones {
                guard let raw = bone.name, !raw.isEmpty else { continue }
                boneNames.insert(raw)
                let matrix = simdMatrix(from: bone.offsetMatrix)
                if matrixIsFinite(matrix) {
                    inverseBindByName[raw] = matrix
                }
            }
        }

        if !hasSkinnedMesh && animationNodeNames.isEmpty {
            return (nil, SkeletonExtractionDiagnostics(jointCount: 0,
                                                       rootJointCount: 0,
                                                       unresolvedParentCount: 0,
                                                       importedInverseBindCount: 0,
                                                       helperNodeFilteredCount: 0,
                                                       helperNodeCollapsedCount: 0,
                                                       traversalTruncated: false,
                                                       nodeSnapshotSize: 0,
                                                       nodeSnapshotRootCount: 0,
                                                       sampleJointParentEntries: []))
        }
        let hasBoneDrivenSkeleton = !boneNames.isEmpty
        var requiredJointNames: Set<String> = hasBoneDrivenSkeleton ? boneNames : animationNodeNames
        var helperNodeFilteredCount = 0
        requiredJointNames = Set(requiredJointNames.filter { rawName in
            if boneNames.contains(rawName) {
                return true
            }
            let canonical = canonicalJointName(rawName)
            guard !canonical.isEmpty else { return false }
            if isHelperJointCandidate(canonicalName: canonical) {
                helperNodeFilteredCount += 1
                return false
            }
            return true
        })
        if requiredJointNames.isEmpty {
            return (nil, SkeletonExtractionDiagnostics(jointCount: 0,
                                                       rootJointCount: 0,
                                                       unresolvedParentCount: 0,
                                                       importedInverseBindCount: 0,
                                                       helperNodeFilteredCount: helperNodeFilteredCount,
                                                       helperNodeCollapsedCount: 0,
                                                       traversalTruncated: false,
                                                       nodeSnapshotSize: 0,
                                                       nodeSnapshotRootCount: 0,
                                                       sampleJointParentEntries: []))
        }

        let hierarchyExtraction = extractNodeHierarchy(from: scene)
        if hierarchyExtraction.snapshot.nodes.isEmpty {
            let orderedNames = Array(requiredJointNames).sorted()
            let joints = orderedNames.map { name in
                SkeletonAsset.Joint(name: name,
                                    parentIndex: -1,
                                    bindLocalPosition: SIMD3<Float>(repeating: 0),
                                    bindLocalRotation: SIMD4<Float>(0, 0, 0, 1),
                                    bindLocalScale: SIMD3<Float>(repeating: 1),
                                    inverseBindGlobalMatrix: inverseBindByName[name])
            }
            let diagnostics = SkeletonExtractionDiagnostics(
                jointCount: joints.count,
                rootJointCount: joints.count,
                unresolvedParentCount: joints.count,
                importedInverseBindCount: inverseBindByName.count,
                helperNodeFilteredCount: helperNodeFilteredCount,
                helperNodeCollapsedCount: 0,
                traversalTruncated: true,
                nodeSnapshotSize: 0,
                nodeSnapshotRootCount: 0,
                sampleJointParentEntries: joints.prefix(8).enumerated().map { index, joint in
                    "\(index):\(joint.name)<-ROOT"
                }
            )
            let inverseByJointName = Dictionary(uniqueKeysWithValues: joints.compactMap { joint -> (String, simd_float4x4)? in
                guard let inverse = joint.inverseBindGlobalMatrix else { return nil }
                return (joint.name, inverse)
            })
            return (ImportedSkeletonData(joints: joints, inverseBindGlobalByJointName: inverseByJointName), diagnostics)
        }
        let nodesByName = hierarchyExtraction.nodesByName
        let requiredCanonicalNames = Set(requiredJointNames.map(canonicalJointName))
        let rootCanonical: String = {
            guard let rootIndex = hierarchyExtraction.snapshot.rootIndices.first,
                  rootIndex >= 0,
                  rootIndex < hierarchyExtraction.snapshot.nodes.count else {
                return ""
            }
            return canonicalJointName(hierarchyExtraction.snapshot.nodes[rootIndex].name)
        }()

        var includedCanonicalNames: Set<String> = []
        for canonical in requiredCanonicalNames {
            var current: String? = canonical
            var guardCounter = 0
            while let nodeName = current, !nodeName.isEmpty {
                guard guardCounter < 8192 else { break }
                guardCounter += 1
                let inserted = includedCanonicalNames.insert(nodeName).inserted
                if !inserted { break }
                if nodeName == rootCanonical { break }
                current = nodesByName[nodeName]?.parentCanonicalName
            }
        }

        if includedCanonicalNames.isEmpty, !rootCanonical.isEmpty {
            includedCanonicalNames.insert(rootCanonical)
        }

        let orderedCanonicalNames = hierarchyExtraction.traversalOrder.filter { includedCanonicalNames.contains($0) }
        var indexByCanonicalName: [String: Int] = [:]
        indexByCanonicalName.reserveCapacity(orderedCanonicalNames.count)
        for (index, name) in orderedCanonicalNames.enumerated() {
            indexByCanonicalName[name] = index
        }

        guard !orderedCanonicalNames.isEmpty else {
            return (nil, SkeletonExtractionDiagnostics(jointCount: 0,
                                                       rootJointCount: 0,
                                                       unresolvedParentCount: 0,
                                                       importedInverseBindCount: 0,
                                                       helperNodeFilteredCount: helperNodeFilteredCount,
                                                       helperNodeCollapsedCount: 0,
                                                       traversalTruncated: hierarchyExtraction.truncated,
                                                       nodeSnapshotSize: hierarchyExtraction.snapshot.nodes.count,
                                                       nodeSnapshotRootCount: hierarchyExtraction.snapshot.rootCount,
                                                       sampleJointParentEntries: []))
        }

        let inverseBindByCanonicalName = Dictionary(uniqueKeysWithValues: inverseBindByName.map { (canonicalJointName($0.key), $0.value) })
        var bindGlobalByCanonicalName: [String: matrix_float4x4] = [:]
        bindGlobalByCanonicalName.reserveCapacity(orderedCanonicalNames.count)
        for name in orderedCanonicalNames {
            if let inverseBind = inverseBindByCanonicalName[name] {
                bindGlobalByCanonicalName[name] = simd_inverse(inverseBind)
            }
        }
        for name in orderedCanonicalNames where bindGlobalByCanonicalName[name] == nil {
            guard let record = nodesByName[name], matrixIsFinite(record.localTransform) else { continue }
            if let parentName = record.parentCanonicalName,
               let parentGlobal = bindGlobalByCanonicalName[parentName] {
                bindGlobalByCanonicalName[name] = parentGlobal * record.localTransform
            } else {
                bindGlobalByCanonicalName[name] = record.localTransform
            }
        }

        var joints: [SkeletonAsset.Joint] = []
        joints.reserveCapacity(orderedCanonicalNames.count)
        var unresolvedParentCount = 0
        for name in orderedCanonicalNames {
            let record = nodesByName[name]
            let parentIndex: Int
            if let parentName = record?.parentCanonicalName,
               let resolvedParent = indexByCanonicalName[parentName],
               resolvedParent != joints.count {
                parentIndex = resolvedParent
            } else {
                parentIndex = -1
                if record?.parentCanonicalName != nil {
                    unresolvedParentCount += 1
                }
            }

            var bindLocalMatrix = record?.localTransform
            if bindLocalMatrix == nil || !(matrixIsFinite(bindLocalMatrix ?? matrix_identity_float4x4)) {
                if let global = bindGlobalByCanonicalName[name] {
                    if parentIndex >= 0, parentIndex < joints.count,
                       let parentGlobal = bindGlobalByCanonicalName[orderedCanonicalNames[parentIndex]] {
                        bindLocalMatrix = simd_inverse(parentGlobal) * global
                    } else {
                        bindLocalMatrix = global
                    }
                } else {
                    bindLocalMatrix = matrix_identity_float4x4
                }
            }

            let decomposed = TransformMath.decomposeMatrix(bindLocalMatrix ?? matrix_identity_float4x4)
            let canonicalInverseBind = inverseBindByCanonicalName[name]
            let joint = SkeletonAsset.Joint(
                name: record?.displayName ?? name,
                parentIndex: parentIndex,
                bindLocalPosition: decomposed.position,
                bindLocalRotation: decomposed.rotation,
                bindLocalScale: decomposed.scale,
                inverseBindGlobalMatrix: canonicalInverseBind
            )
            joints.append(joint)
        }

        let rootJointCount = joints.reduce(into: 0) { count, joint in
            if joint.parentIndex < 0 {
                count += 1
            }
        }
        let sampleEntries = joints.prefix(8).enumerated().map { index, joint in
            let parentLabel: String
            if joint.parentIndex >= 0 && joint.parentIndex < joints.count {
                parentLabel = joints[joint.parentIndex].name
            } else {
                parentLabel = "ROOT"
            }
            return "\(index):\(joint.name)<-\(parentLabel)"
        }
        let diagnostics = SkeletonExtractionDiagnostics(
            jointCount: joints.count,
            rootJointCount: rootJointCount,
            unresolvedParentCount: unresolvedParentCount,
            importedInverseBindCount: inverseBindByName.count,
            helperNodeFilteredCount: helperNodeFilteredCount,
            helperNodeCollapsedCount: 0,
            traversalTruncated: hierarchyExtraction.truncated,
            nodeSnapshotSize: hierarchyExtraction.snapshot.nodes.count,
            nodeSnapshotRootCount: hierarchyExtraction.snapshot.rootCount,
            sampleJointParentEntries: sampleEntries
        )
        let inverseByJointName = Dictionary(uniqueKeysWithValues: joints.compactMap { joint -> (String, simd_float4x4)? in
            guard let inverse = joint.inverseBindGlobalMatrix else { return nil }
            return (joint.name, inverse)
        })
        return (ImportedSkeletonData(joints: joints, inverseBindGlobalByJointName: inverseByJointName), diagnostics)
    }

    static func extractAnimations(from scene: AiScene,
                                  skeleton: ImportedSkeletonData?,
                                  suggestedName: String) -> ([ImportedAnimationClipData], AnimationMappingDiagnostics) {
        guard !scene.animations.isEmpty else {
            return ([], AnimationMappingDiagnostics(totalChannels: 0, mappedChannels: 0, unmappedChannelNames: []))
        }
        let joints = skeleton?.joints ?? []
        let jointIndexByName = Dictionary(uniqueKeysWithValues: joints.enumerated().map { ($1.name, $0) })
        let jointIndexByCanonicalName = Dictionary(uniqueKeysWithValues: joints.enumerated().map { (canonicalJointName($1.name), $0) })
        let fallbackJointIndexByName = Dictionary(uniqueKeysWithValues: Set(scene.animations.flatMap { $0.channels.compactMap(\.nodeName) })
            .sorted()
            .enumerated()
            .map { ($1, $0) })
        let fallbackJointIndexByCanonicalName = Dictionary(uniqueKeysWithValues: fallbackJointIndexByName.map { (canonicalJointName($0.key), $0.value) })
        let usesFallbackLookup = jointIndexByName.isEmpty

        var clips: [ImportedAnimationClipData] = []
        clips.reserveCapacity(scene.animations.count)
        var usedClipNames: Set<String> = []
        var totalChannels = 0
        var mappedChannels = 0
        var unmappedChannels = Set<String>()
        for (clipIndex, animation) in scene.animations.enumerated() {
            let rawName = animation.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let clipName = makeReadableClipName(
                rawName: rawName,
                suggestedName: suggestedName,
                clipIndex: clipIndex,
                usedNames: &usedClipNames
            )
            let tps = animation.ticksPerSecond > 0.0 ? animation.ticksPerSecond : 1.0
            let duration = max(0.0, animation.duration / tps)

            var tracks: [AnimationClipAsset.JointTrack] = []
            for channel in animation.channels {
                totalChannels += 1
                guard let nodeName = channel.nodeName else {
                    continue
                }
                let canonicalName = canonicalJointName(nodeName)
                let jointIndex = usesFallbackLookup
                    ? (fallbackJointIndexByName[nodeName] ?? fallbackJointIndexByCanonicalName[canonicalName])
                    : (jointIndexByName[nodeName] ?? jointIndexByCanonicalName[canonicalName])
                guard let jointIndex else {
                    if let nodeName = channel.nodeName, !nodeName.isEmpty {
                        unmappedChannels.insert(nodeName)
                    }
                    continue
                }
                mappedChannels += 1

                let translations = channel.positionKeys
                    .map { AnimationClipAsset.TranslationKeyframe(time: Float($0.time / tps), value: SIMD3<Float>($0.value.x, $0.value.y, $0.value.z)) }
                    .sorted { $0.time < $1.time }
                let rotations = channel.rotationKeys
                    .map { AnimationClipAsset.RotationKeyframe(time: Float($0.time / tps), value: SIMD4<Float>($0.value.x, $0.value.y, $0.value.z, $0.value.w)) }
                    .sorted { $0.time < $1.time }
                let scales = channel.scalingKeys
                    .map { AnimationClipAsset.ScaleKeyframe(time: Float($0.time / tps), value: SIMD3<Float>($0.value.x, $0.value.y, $0.value.z)) }
                    .sorted { $0.time < $1.time }

                if translations.isEmpty && rotations.isEmpty && scales.isEmpty { continue }
                tracks.append(
                    AnimationClipAsset.JointTrack(
                        jointIndex: jointIndex,
                        translations: translations,
                        rotations: rotations,
                        scales: scales
                    )
                )
            }

            let rootMotionJointIndex = detectRootMotionSourceJointIndex(tracks: tracks, joints: skeleton?.joints)
            let hasRootMotion: Bool
            if let rootMotionJointIndex {
                hasRootMotion = tracks.contains { track in
                    guard track.jointIndex == rootMotionJointIndex, track.translations.count > 1 else { return false }
                    let first = track.translations[0].value
                    return track.translations.contains { simd_length($0.value - first) > 0.001 }
                }
            } else {
                hasRootMotion = false
            }
            let rootMotionJointName: String? = rootMotionJointIndex.flatMap { index in
                guard let joints = skeleton?.joints, index >= 0, index < joints.count else { return nil }
                return joints[index].name
            }

            clips.append(
                ImportedAnimationClipData(
                    name: clipName,
                    durationSeconds: Float(duration),
                    tracks: tracks,
                    interpolation: "linear",
                    hasRootMotion: hasRootMotion,
                    rootMotionJointIndex: rootMotionJointIndex,
                    rootMotionJointName: rootMotionJointName
                )
            )
        }
        let diagnostics = AnimationMappingDiagnostics(
            totalChannels: totalChannels,
            mappedChannels: mappedChannels,
            unmappedChannelNames: Array(unmappedChannels).sorted()
        )
        return (clips, diagnostics)
    }

    private static func detectRootMotionSourceJointIndex(tracks: [AnimationClipAsset.JointTrack],
                                                         joints: [SkeletonAsset.Joint]?) -> Int? {
        struct Candidate {
            let jointIndex: Int
            let depth: Int
            let motion: Float
            let nameBias: Int
        }

        func translationMotion(_ translations: [AnimationClipAsset.TranslationKeyframe]) -> Float {
            guard translations.count > 1 else { return 0.0 }
            let first = translations[0].value
            var maxDistance: Float = 0.0
            for sample in translations {
                maxDistance = max(maxDistance, simd_length(sample.value - first))
            }
            return maxDistance
        }

        func hierarchyDepth(_ jointIndex: Int, joints: [SkeletonAsset.Joint]) -> Int {
            guard jointIndex >= 0, jointIndex < joints.count else { return Int.max / 2 }
            var depth = 0
            var cursor = jointIndex
            var visited: Set<Int> = []
            while cursor >= 0, cursor < joints.count, !visited.contains(cursor) {
                visited.insert(cursor)
                let parent = joints[cursor].parentIndex
                if parent < 0 { break }
                depth += 1
                cursor = parent
            }
            return depth
        }

        func rootNameBias(_ name: String) -> Int {
            let lowered = name.lowercased()
            if lowered.contains("translation") { return 3 }
            if lowered.contains("root") { return 2 }
            if lowered.contains("hips") || lowered.contains("pelvis") { return 1 }
            return 0
        }

        let candidates: [Candidate] = tracks.compactMap { track in
            let motion = translationMotion(track.translations)
            guard motion > 0.001 else { return nil }
            let depth: Int
            let nameBias: Int
            if let joints, track.jointIndex >= 0, track.jointIndex < joints.count {
                depth = hierarchyDepth(track.jointIndex, joints: joints)
                nameBias = rootNameBias(joints[track.jointIndex].name)
            } else {
                depth = track.jointIndex
                nameBias = 0
            }
            return Candidate(jointIndex: track.jointIndex, depth: depth, motion: motion, nameBias: nameBias)
        }
        guard !candidates.isEmpty else { return nil }
        let minDepth = candidates.map(\.depth).min() ?? 0
        let depthWindow = candidates.filter { $0.depth <= (minDepth + 1) }
        let ranked = depthWindow.isEmpty ? candidates : depthWindow
        let best = ranked.max { lhs, rhs in
            if lhs.nameBias != rhs.nameBias { return lhs.nameBias < rhs.nameBias }
            if abs(lhs.motion - rhs.motion) > 1.0e-5 { return lhs.motion < rhs.motion }
            if lhs.depth != rhs.depth { return lhs.depth > rhs.depth }
            return lhs.jointIndex > rhs.jointIndex
        }
        return best?.jointIndex
    }

    static func makeReadableClipName(rawName: String,
                                     suggestedName: String,
                                     clipIndex: Int,
                                     usedNames: inout Set<String>) -> String {
        let preferredBase: String
        if isMeaningfulAnimationName(rawName) {
            preferredBase = sanitizeName(rawName)
        } else if clipIndex == 0 {
            preferredBase = sanitizeName(suggestedName)
        } else {
            preferredBase = sanitizeName("\(suggestedName)_Clip_\(clipIndex + 1)")
        }

        var candidate = preferredBase.isEmpty ? "Clip_\(clipIndex + 1)" : preferredBase
        if !usedNames.contains(candidate) {
            usedNames.insert(candidate)
            return candidate
        }

        var suffix = 2
        while usedNames.contains("\(candidate)_\(suffix)") {
            suffix += 1
        }
        let uniqued = "\(candidate)_\(suffix)"
        usedNames.insert(uniqued)
        return uniqued
    }

    static func isMeaningfulAnimationName(_ rawName: String) -> Bool {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lower = trimmed.lowercased()
        let genericNames: Set<String> = [
            "mixamo.com",
            "mixamo",
            "default",
            "animation",
            "anim",
            "take",
            "take 001",
            "take001",
            "armature",
            "scene"
        ]
        if genericNames.contains(lower) {
            return false
        }
        let hasLetters = lower.unicodeScalars.contains { CharacterSet.letters.contains($0) }
        return hasLetters
    }

    static func simdMatrix(from matrix: AiMatrix4x4) -> simd_float4x4 {
        simd_float4x4(
            SIMD4<Float>(matrix.a1, matrix.b1, matrix.c1, matrix.d1),
            SIMD4<Float>(matrix.a2, matrix.b2, matrix.c2, matrix.d2),
            SIMD4<Float>(matrix.a3, matrix.b3, matrix.c3, matrix.d3),
            SIMD4<Float>(matrix.a4, matrix.b4, matrix.c4, matrix.d4)
        )
    }

    static func sanitizeName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Asset" }
        let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|")
        let cleaned = trimmed.components(separatedBy: invalid).joined(separator: "_")
        return cleaned.isEmpty ? "Asset" : cleaned
    }

    static func nextWeightSlot(for vertex: Int, weights: [SIMD4<Float>]) -> Int {
        let vertexWeights = weights[vertex]
        for index in 0..<4 where vertexWeights[index] <= 0.0 {
            return index
        }
        return -1
    }

    static func unpackVector3Array(_ values: [AiReal]) -> [SIMD3<Float>] {
        guard values.count >= 3 else { return [] }
        return stride(from: 0, to: values.count - 2, by: 3).compactMap { offset in
            let candidate = SIMD3<Float>(values[offset], values[offset + 1], values[offset + 2])
            if !candidate.x.isFinite || !candidate.y.isFinite || !candidate.z.isFinite {
                return nil
            }
            return candidate
        }
    }

    static func unpackVector2Array(_ values: [AiReal]) -> [SIMD2<Float>] {
        guard values.count >= 2 else { return [] }
        return stride(from: 0, to: values.count - 1, by: 2).compactMap { offset in
            let candidate = SIMD2<Float>(values[offset], values[offset + 1])
            if !candidate.x.isFinite || !candidate.y.isFinite {
                return nil
            }
            return candidate
        }
    }

    static func logDiagnosticsOnce(_ diagnostics: AssimpSmokeDiagnostics,
                                   level: MCLogLevel,
                                   prefix: String) {
        let key = "\(prefix)|\(diagnostics.filePath)"
        if loggedDiagnostics.contains(key) { return }
        loggedDiagnostics.insert(key)
        EngineLoggerContext.log(
            diagnostics.formatted(prefix: prefix),
            level: level,
            category: .assets
        )
    }

    static func logMaterialWarningOnce(path: String, reason: String) {
        let key = "materialwarn|\(path)|\(reason)"
        if loggedDiagnostics.contains(key) { return }
        loggedDiagnostics.insert(key)
        EngineLoggerContext.log(
            "FBX material extraction warning path=\(path)\nreason=\(reason)",
            level: .warning,
            category: .assets
        )
    }

    static func logMeshDiagnosticsOnce(filePath: String, scene: AiScene) {
        let key = "meshdiag|\(filePath)"
        if loggedDiagnostics.contains(key) { return }
        loggedDiagnostics.insert(key)

        var lines: [String] = []
        for meshIndex in 0..<scene.numMeshes {
            guard let mesh = scene.mesh(at: meshIndex) else {
                lines.append("mesh[\(meshIndex)]: <unavailable>")
                continue
            }
            let vertexCount = mesh.numVertices
            let faceCount = mesh.numFaces
            let indexCount = mesh.faces.reduce(0) { $0 + $1.indices.count }
            let normals = !mesh.normals.isEmpty
            let tangents = !mesh.tangents.isEmpty
            let uv0 = !((mesh.texCoordsPacked.0 ?? []).isEmpty)
            let hasBones = mesh.numBones > 0
            let boneCount = mesh.numBones
            let materialIndex = mesh.materialIndex
            lines.append("mesh[\(meshIndex)] vtx=\(vertexCount) face=\(faceCount) idx=\(indexCount) normals=\(normals) tangents=\(tangents) uv0=\(uv0) hasBones=\(hasBones) boneCount=\(boneCount) material=\(materialIndex)")
        }
        if lines.isEmpty {
            lines.append("no meshes reported by scene")
        }
        EngineLoggerContext.log(
            "FBX mesh diagnostics path=\(filePath)\n" + lines.joined(separator: "\n"),
            level: .debug,
            category: .assets
        )
    }

    static func logImportSummaryOnce(filePath: String, summary: FBXImportSummaryDiagnostics) {
        let key = "fbxsummary|\(filePath)"
        if loggedDiagnostics.contains(key) { return }
        loggedDiagnostics.insert(key)
        EngineLoggerContext.log(
            "FBX import summary path=\(filePath)\nmeshCount=\(summary.meshCount)\njointCount=\(summary.jointCount)\nrootJointCount=\(summary.rootJointCount)\ntrackCount=\(summary.trackCount)\nmaterialCount=\(summary.materialCount)\nimportedInverseBindCount=\(summary.importedInverseBindCount)",
            level: .debug,
            category: .assets
        )
    }

    static func logNodeSnapshotDiagnosticsOnce(filePath: String,
                                               snapshotSize: Int,
                                               rootCount: Int,
                                               truncated: Bool) {
        let key = "fbxnodesnapshot|\(filePath)"
        if loggedDiagnostics.contains(key) { return }
        loggedDiagnostics.insert(key)
        EngineLoggerContext.log(
            "FBX node snapshot diagnostics path=\(filePath)\nnodeSnapshotSize=\(snapshotSize)\nnodeSnapshotRootCount=\(rootCount)\ntruncated=\(truncated)",
            level: .debug,
            category: .assets
        )
    }

    static func logSkeletonMappingDiagnosticsOnce(filePath: String,
                                                  skeleton: ImportedSkeletonData?,
                                                  skeletonDiagnostics: SkeletonExtractionDiagnostics,
                                                  meshDiagnostics: MeshMappingDiagnostics,
                                                  animationDiagnostics: AnimationMappingDiagnostics) {
        let key = "skeletondiag|\(filePath)"
        if loggedDiagnostics.contains(key) { return }
        loggedDiagnostics.insert(key)

        let nonRootUnresolved = max(0, skeletonDiagnostics.unresolvedParentCount)
        let sample = skeletonDiagnostics.sampleJointParentEntries.isEmpty
            ? "<none>"
            : skeletonDiagnostics.sampleJointParentEntries.joined(separator: ", ")
        let unmappedBonePreview = meshDiagnostics.unmappedBoneNames.prefix(8).joined(separator: ", ")
        let unmappedChannelPreview = animationDiagnostics.unmappedChannelNames.prefix(8).joined(separator: ", ")
        EngineLoggerContext.log(
            """
            FBX skeleton mapping diagnostics path=\(filePath)
            jointCount=\(skeletonDiagnostics.jointCount)
            rootJointCount=\(skeletonDiagnostics.rootJointCount)
            sampleJoints=\(sample)
            nonRootParentUnresolvedCount=\(nonRootUnresolved)
            traversalTruncated=\(skeletonDiagnostics.traversalTruncated)
            nodeSnapshotSize=\(skeletonDiagnostics.nodeSnapshotSize)
            nodeSnapshotRootCount=\(skeletonDiagnostics.nodeSnapshotRootCount)
            hasSkeleton=\(skeleton != nil)
            meshBoneNamesMapped=\(meshDiagnostics.mappedBoneNames)/\(meshDiagnostics.totalBoneNames)
            meshBoneNamesUnmapped=\(meshDiagnostics.unmappedBoneNames.count)
            unmappedBoneNames=\(unmappedBonePreview.isEmpty ? "<none>" : unmappedBonePreview)
            animationChannelsMapped=\(animationDiagnostics.mappedChannels)/\(animationDiagnostics.totalChannels)
            animationChannelsUnmapped=\(animationDiagnostics.unmappedChannelNames.count)
            unmappedChannelNames=\(unmappedChannelPreview.isEmpty ? "<none>" : unmappedChannelPreview)
            helperNodesFiltered=\(skeletonDiagnostics.helperNodeFilteredCount)
            helperNodesCollapsed=\(skeletonDiagnostics.helperNodeCollapsedCount)
            importedInverseBindPresent=\(skeletonDiagnostics.importedInverseBindCount > 0)
            importedInverseBindCount=\(skeletonDiagnostics.importedInverseBindCount)
            paletteSourcePolicy=\(skeletonDiagnostics.importedInverseBindCount > 0 ? "importedInverseBindPreferred" : "reconstructedBindInverseFallback")
            """,
            level: .debug,
            category: .assets
        )
    }

    static func logScaleNormalizationOnce(filePath: String, normalization: FBXScaleNormalization) {
        let key = "fbxscale|\(filePath)"
        if loggedDiagnostics.contains(key) { return }
        loggedDiagnostics.insert(key)
        EngineLoggerContext.log(
            "FBX scale normalization path=\(filePath)\nmode=\(normalization.mode)\nfactor=\(String(format: "%.6f", normalization.factor))\nreason=\(normalization.reason)",
            level: .debug,
            category: .assets
        )
    }
}
