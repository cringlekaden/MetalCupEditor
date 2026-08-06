import Foundation
import simd
import MetalCupEngine

enum FbxSdkAdapter {
    private static var loggedActiveBridge = false

    static func scanFBX(url: URL, suggestedName: String) -> ImportedFBXData? {
        if let scene = extractScene(url: url) {
            if !loggedActiveBridge {
                loggedActiveBridge = true
                EngineLoggerContext.log("FBX SDK bridge active", level: .info, category: .assets)
            }

            let jointConversion = convertJoints(scene.joints)
            let scaleFactor = sanitizedImportScale(scene.importScaleFactor)
            let scaleSource = scene.importScaleSource.isEmpty ? "none" : scene.importScaleSource
            let joints = applyTranslationScale(to: jointConversion.joints, factor: scaleFactor)
            let inverseBindBuild = buildInverseBindMap(from: joints)
            let skeleton = joints.isEmpty
                ? nil
                : ImportedSkeletonData(
                    joints: joints,
                    inverseBindGlobalByJointName: inverseBindBuild.map
                )

            let clips = applyTranslationScale(
                to: convertClips(scene.clips,
                                 suggestedName: suggestedName,
                                 jointNames: joints.map(\.name)),
                factor: scaleFactor
            )
            let materials = convertMaterials(scene.materials, sourceURL: url)
            let meshes = applyTranslationScale(to: convertMeshes(scene.meshes), factor: scaleFactor)

            let hasMeshes = !meshes.isEmpty
            let hasClips = !clips.isEmpty
            let hasSkinnedMesh = meshes.contains(where: { $0.hasSkinning }) && skeleton != nil
            let mode: AssimpFBXImportMode
            if !hasMeshes && hasClips {
                mode = .animationOnly
            } else if hasSkinnedMesh {
                mode = .skeletalMesh
            } else {
                mode = .staticMesh
            }

            var warnings: [String] = []
            if !hasMeshes && mode != .animationOnly {
                warnings.append("No meshes found in FBX via FBX SDK.")
            }
            if hasMeshes && meshes.contains(where: { $0.hasSkinning }) && skeleton == nil {
                warnings.append("Skinned mesh detected but skeleton extraction failed.")
            }
            if jointConversion.stats.totalRepairs > 0 {
                let warning = "FBX joint names repaired: invalid=\(jointConversion.stats.invalidEncodingCount), empty=\(jointConversion.stats.emptyNameCount), duplicates=\(jointConversion.stats.duplicateNameCount)."
                warnings.append(warning)
                EngineLoggerContext.log(
                    "\(warning) source=\(url.lastPathComponent)",
                    level: .warning,
                    category: .assets
                )
            }
            if inverseBindBuild.collisions > 0 {
                let warning = "FBX inverse bind map collisions resolved by first-joint-wins: \(inverseBindBuild.collisions)."
                warnings.append(warning)
                EngineLoggerContext.log(
                    "\(warning) source=\(url.lastPathComponent)",
                    level: .warning,
                    category: .assets
                )
            }

            return ImportedFBXData(
                mode: mode,
                meshes: meshes,
                skeleton: skeleton,
                clips: clips,
                materials: materials,
                warnings: warnings,
                importScaleFactor: scaleFactor,
                importScaleNormalizationMode: scaleSource,
                importScaleSource: scaleSource
            )
        }

        guard let fallbackData = AssimpAdapter.scanFBX(url: url, suggestedName: suggestedName) else {
            return nil
        }
        var warnings = fallbackData.warnings
        warnings.append("FBX SDK bridge unavailable; using Assimp FBX fallback.")
        return ImportedFBXData(
            mode: fallbackData.mode,
            meshes: fallbackData.meshes,
            skeleton: fallbackData.skeleton,
            clips: fallbackData.clips,
            materials: fallbackData.materials,
            warnings: warnings,
            importScaleFactor: fallbackData.importScaleFactor,
            importScaleNormalizationMode: fallbackData.importScaleNormalizationMode,
            importScaleSource: fallbackData.importScaleSource
        )
    }

    static func writeBakedMeshAsset(from data: ImportedFBXData,
                                    name: String,
                                    to url: URL) -> Bool {
        guard !data.meshes.isEmpty else { return false }

        var bakedVertices: [FbxBakedMeshVertexDocument] = []
        bakedVertices.reserveCapacity(data.meshes.reduce(0) { $0 + $1.positions.count })
        var bakedSubmeshes: [FbxBakedMeshSubmeshDocument] = []
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
                    FbxBakedMeshVertexDocument(
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
                FbxBakedMeshSubmeshDocument(
                    name: mesh.name,
                    materialIndex: mesh.materialIndex,
                    indices: adjustedIndices
                )
            )
        }

        let document = FbxBakedMeshDocument(
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
        let skeletonInfo = data.skeleton.map { skel in
            MeshSkeletonScanInfo(jointCount: skel.joints.count, joints: skel.joints)
        }
        let clipInfos = data.clips.map { clip in
            MeshAnimationClipScanInfo(name: clip.name, durationSeconds: clip.durationSeconds, tracks: clip.tracks)
        }

        return MeshScanInfo(
            meshCount: data.meshes.count,
            submeshCount: data.meshes.count,
            submeshMaterialIndices: submeshMaterialIndices,
            materialNames: materialNames,
            textureNames: Array(Set(textureNames)).sorted(),
            hasUVs: data.meshes.contains(where: { $0.hasUVs }),
            hasNormals: data.meshes.contains(where: { $0.hasNormals }),
            hasTangents: data.meshes.contains(where: { $0.hasTangents }),
            suggestFlipNormalY: false,
            embeddedTextureCount: data.materials.reduce(into: 0) { count, material in
                count += material.embeddedTextureSemantics.count
            },
            isSkinned: data.mode == .skeletalMesh,
            skeletonInfo: skeletonInfo,
            clipInfos: clipInfos,
            hasRootMotion: data.clips.contains(where: { $0.hasRootMotion }),
            rootMotionBoneName: data.clips.compactMap(\.rootMotionJointName).first,
            warnings: data.warnings,
            materials: meshMaterials
        )
    }

    static func backendName(for data: ImportedFBXData) -> String {
        data.warnings.contains(where: { $0.contains("Assimp FBX fallback") }) ? "assimp-fallback" : "fbxsdk"
    }
}

private struct FbxBakedMeshVertexDocument: Codable {
    let position: [Float]
    let normal: [Float]?
    let tangent: [Float]?
    let texCoord0: [Float]?
    let jointIndices: [UInt16]?
    let jointWeights: [Float]?
}

private struct FbxBakedMeshSubmeshDocument: Codable {
    let name: String
    let materialIndex: Int
    let indices: [UInt32]
}

private struct FbxBakedMeshDocument: Codable {
    let schemaVersion: Int
    let name: String
    let hasSkinning: Bool
    let vertices: [FbxBakedMeshVertexDocument]
    let submeshes: [FbxBakedMeshSubmeshDocument]
}

private extension FbxSdkAdapter {
    struct SceneJointDTO {
        let rawName: String
        let hadInvalidEncoding: Bool
        let parentIndex: Int
        let bindLocalPosition: SIMD3<Float>
        let bindLocalRotation: SIMD4<Float>
        let bindLocalScale: SIMD3<Float>
        let inverseBindGlobal: [Float]?
    }

    struct SceneTranslationKeyDTO {
        let time: Float
        let value: SIMD3<Float>
    }

    struct SceneRotationKeyDTO {
        let time: Float
        let value: SIMD4<Float>
    }

    struct SceneScaleKeyDTO {
        let time: Float
        let value: SIMD3<Float>
    }

    struct SceneJointTrackDTO {
        let jointIndex: Int
        let translations: [SceneTranslationKeyDTO]
        let rotations: [SceneRotationKeyDTO]
        let scales: [SceneScaleKeyDTO]
    }

    struct SceneClipDTO {
        let name: String
        let durationSeconds: Float
        let tracks: [SceneJointTrackDTO]
    }

    struct SceneMeshDTO {
        let name: String
        let materialIndex: Int
        let positions: [SIMD3<Float>]
        let normals: [SIMD3<Float>]
        let tangents: [SIMD3<Float>]
        let uv0: [SIMD2<Float>]
        let indices: [UInt32]
        let hasSkinning: Bool
        let jointIndices: [SIMD4<UInt16>]
        let jointWeights: [SIMD4<Float>]
    }

    struct SceneMaterialDTO {
        let name: String
        let baseColor: SIMD3<Float>
        let emissiveColor: SIMD3<Float>
        let metallicFactor: Float
        let roughnessFactor: Float
        let alpha: Float
        let alphaCutoff: Float
        let baseColorTexturePath: String?
        let baseColorTextureEmbedded: Bool
        let normalTexturePath: String?
        let normalTextureEmbedded: Bool
        let metallicTexturePath: String?
        let metallicTextureEmbedded: Bool
        let roughnessTexturePath: String?
        let roughnessTextureEmbedded: Bool
        let metallicRoughnessTexturePath: String?
        let metallicRoughnessTextureEmbedded: Bool
        let occlusionTexturePath: String?
        let occlusionTextureEmbedded: Bool
        let emissiveTexturePath: String?
        let emissiveTextureEmbedded: Bool
    }

    struct Scene {
        let joints: [SceneJointDTO]
        let clips: [SceneClipDTO]
        let meshes: [SceneMeshDTO]
        let materials: [SceneMaterialDTO]
        let importScaleFactor: Float
        let importScaleSource: String
    }

    struct JointNameRepairStats {
        var invalidEncodingCount: Int = 0
        var emptyNameCount: Int = 0
        var duplicateNameCount: Int = 0

        var totalRepairs: Int {
            invalidEncodingCount + emptyNameCount + duplicateNameCount
        }
    }

    struct JointConversionResult {
        let joints: [SkeletonAsset.Joint]
        let stats: JointNameRepairStats
    }

    struct InverseBindMapBuildResult {
        let map: [String: simd_float4x4]
        let collisions: Int
    }

    static func extractScene(url: URL) -> Scene? {
        var dto = MCEFbxSceneDTO()
        var errorBuffer = [CChar](repeating: 0, count: 1024)
        let ok = url.path.withCString { cPath in
            MCEFbxExtractScene(cPath, &dto, &errorBuffer, Int32(errorBuffer.count))
        }
        guard ok else {
            return nil
        }
        defer { MCEFbxFreeScene(&dto) }

        let joints: [SceneJointDTO] = {
            guard dto.jointCount > 0, let ptr = dto.joints else { return [] }
            return (0..<Int(dto.jointCount)).map { index in
                let src = ptr[index]
                let decodedName = decodeCStringLossy(src.name)
                let inverse: [Float]? = {
                    guard src.hasInverseBindGlobal, let matrixPtr = src.inverseBindGlobal else { return nil }
                    return Array(UnsafeBufferPointer(start: matrixPtr, count: 16))
                }()
                return SceneJointDTO(
                    rawName: decodedName.value,
                    hadInvalidEncoding: decodedName.hadInvalidEncoding,
                    parentIndex: Int(src.parentIndex),
                    bindLocalPosition: SIMD3<Float>(src.bindLocalPositionX, src.bindLocalPositionY, src.bindLocalPositionZ),
                    bindLocalRotation: SIMD4<Float>(src.bindLocalRotationX, src.bindLocalRotationY, src.bindLocalRotationZ, src.bindLocalRotationW),
                    bindLocalScale: SIMD3<Float>(src.bindLocalScaleX, src.bindLocalScaleY, src.bindLocalScaleZ),
                    inverseBindGlobal: inverse
                )
            }
        }()

        let clips: [SceneClipDTO] = {
            guard dto.clipCount > 0, let clipPtr = dto.clips else { return [] }
            return (0..<Int(dto.clipCount)).map { clipIndex in
                let srcClip = clipPtr[clipIndex]
                let tracks: [SceneJointTrackDTO] = {
                    guard srcClip.trackCount > 0, let trackPtr = srcClip.tracks else { return [] }
                    return (0..<Int(srcClip.trackCount)).map { trackIndex in
                        let srcTrack = trackPtr[trackIndex]
                        let translations: [SceneTranslationKeyDTO] = {
                            guard srcTrack.translationCount > 0, let keyPtr = srcTrack.translations else { return [] }
                            return (0..<Int(srcTrack.translationCount)).map { keyIndex in
                                let key = keyPtr[keyIndex]
                                return SceneTranslationKeyDTO(time: key.time,
                                                              value: SIMD3<Float>(key.valueX, key.valueY, key.valueZ))
                            }
                        }()
                        let rotations: [SceneRotationKeyDTO] = {
                            guard srcTrack.rotationCount > 0, let keyPtr = srcTrack.rotations else { return [] }
                            return (0..<Int(srcTrack.rotationCount)).map { keyIndex in
                                let key = keyPtr[keyIndex]
                                return SceneRotationKeyDTO(time: key.time,
                                                           value: SIMD4<Float>(key.valueX, key.valueY, key.valueZ, key.valueW))
                            }
                        }()
                        let scales: [SceneScaleKeyDTO] = {
                            guard srcTrack.scaleCount > 0, let keyPtr = srcTrack.scales else { return [] }
                            return (0..<Int(srcTrack.scaleCount)).map { keyIndex in
                                let key = keyPtr[keyIndex]
                                return SceneScaleKeyDTO(time: key.time,
                                                        value: SIMD3<Float>(key.valueX, key.valueY, key.valueZ))
                            }
                        }()
                        return SceneJointTrackDTO(
                            jointIndex: Int(srcTrack.jointIndex),
                            translations: translations,
                            rotations: rotations,
                            scales: scales
                        )
                    }
                }()
                return SceneClipDTO(
                    name: decodeCStringLossy(srcClip.name).value,
                    durationSeconds: srcClip.durationSeconds,
                    tracks: tracks
                )
            }
        }()

        let meshes: [SceneMeshDTO] = {
            guard dto.meshCount > 0, let meshPtr = dto.meshes else { return [] }
            return (0..<Int(dto.meshCount)).compactMap { meshIndex in
                let src = meshPtr[meshIndex]
                let vertexCount = Int(src.vertexCount)
                let indexCount = Int(src.indexCount)
                guard vertexCount > 0, indexCount > 0,
                      let positionsPtr = src.positions,
                      let indicesPtr = src.indices else {
                    return nil
                }

                let positionsRaw = Array(UnsafeBufferPointer(start: positionsPtr, count: vertexCount * 3))
                func vector3Array(_ raw: [Float]) -> [SIMD3<Float>] {
                    guard raw.count >= vertexCount * 3 else { return [] }
                    return stride(from: 0, to: vertexCount * 3, by: 3).map { offset in
                        SIMD3<Float>(raw[offset], raw[offset + 1], raw[offset + 2])
                    }
                }

                let positions = vector3Array(positionsRaw)
                let normals = src.normals.map {
                    vector3Array(Array(UnsafeBufferPointer(start: $0, count: vertexCount * 3)))
                } ?? []
                let tangents = src.tangents.map {
                    vector3Array(Array(UnsafeBufferPointer(start: $0, count: vertexCount * 3)))
                } ?? []

                let uv0: [SIMD2<Float>] = {
                    guard let uvPtr = src.uv0 else { return [] }
                    let uvRaw = Array(UnsafeBufferPointer(start: uvPtr, count: vertexCount * 2))
                    guard uvRaw.count >= vertexCount * 2 else { return [] }
                    return stride(from: 0, to: vertexCount * 2, by: 2).map { offset in
                        SIMD2<Float>(uvRaw[offset], uvRaw[offset + 1])
                    }
                }()

                let jointIndices: [SIMD4<UInt16>] = {
                    guard let jiPtr = src.jointIndices else { return [] }
                    let raw = Array(UnsafeBufferPointer(start: jiPtr, count: vertexCount * 4))
                    guard raw.count >= vertexCount * 4 else { return [] }
                    return stride(from: 0, to: vertexCount * 4, by: 4).map { offset in
                        SIMD4<UInt16>(raw[offset], raw[offset + 1], raw[offset + 2], raw[offset + 3])
                    }
                }()

                let jointWeights: [SIMD4<Float>] = {
                    guard let jwPtr = src.jointWeights else { return [] }
                    let raw = Array(UnsafeBufferPointer(start: jwPtr, count: vertexCount * 4))
                    guard raw.count >= vertexCount * 4 else { return [] }
                    return stride(from: 0, to: vertexCount * 4, by: 4).map { offset in
                        SIMD4<Float>(raw[offset], raw[offset + 1], raw[offset + 2], raw[offset + 3])
                    }
                }()

                let indices = Array(UnsafeBufferPointer(start: indicesPtr, count: indexCount))
                return SceneMeshDTO(
                    name: decodeCStringLossy(src.name).value,
                    materialIndex: Int(src.materialIndex),
                    positions: positions,
                    normals: normals,
                    tangents: tangents,
                    uv0: uv0,
                    indices: indices,
                    hasSkinning: src.hasSkinning,
                    jointIndices: jointIndices,
                    jointWeights: jointWeights
                )
            }
        }()

        let materials: [SceneMaterialDTO] = {
            guard dto.materialCount > 0, let materialPtr = dto.materials else { return [] }
            return (0..<Int(dto.materialCount)).map { materialIndex in
                let src = materialPtr[materialIndex]
                return SceneMaterialDTO(
                    name: decodeCStringLossy(src.name).value,
                    baseColor: SIMD3<Float>(src.baseColorR, src.baseColorG, src.baseColorB),
                    emissiveColor: SIMD3<Float>(src.emissiveColorR, src.emissiveColorG, src.emissiveColorB),
                    metallicFactor: src.metallicFactor,
                    roughnessFactor: src.roughnessFactor,
                    alpha: src.alpha,
                    alphaCutoff: src.alphaCutoff,
                    baseColorTexturePath: decodeCStringLossy(src.baseColorTexturePath).valueOrNil,
                    baseColorTextureEmbedded: src.baseColorTextureEmbedded,
                    normalTexturePath: decodeCStringLossy(src.normalTexturePath).valueOrNil,
                    normalTextureEmbedded: src.normalTextureEmbedded,
                    metallicTexturePath: decodeCStringLossy(src.metallicTexturePath).valueOrNil,
                    metallicTextureEmbedded: src.metallicTextureEmbedded,
                    roughnessTexturePath: decodeCStringLossy(src.roughnessTexturePath).valueOrNil,
                    roughnessTextureEmbedded: src.roughnessTextureEmbedded,
                    metallicRoughnessTexturePath: decodeCStringLossy(src.metallicRoughnessTexturePath).valueOrNil,
                    metallicRoughnessTextureEmbedded: src.metallicRoughnessTextureEmbedded,
                    occlusionTexturePath: decodeCStringLossy(src.occlusionTexturePath).valueOrNil,
                    occlusionTextureEmbedded: src.occlusionTextureEmbedded,
                    emissiveTexturePath: decodeCStringLossy(src.emissiveTexturePath).valueOrNil,
                    emissiveTextureEmbedded: src.emissiveTextureEmbedded
                )
            }
        }()

        return Scene(
            joints: joints,
            clips: clips,
            meshes: meshes,
            materials: materials,
            importScaleFactor: dto.importScaleFactor,
            importScaleSource: decodeCStringLossy(dto.importScaleSource).value
        )
    }

    static func convertJoints(_ joints: [SceneJointDTO]) -> JointConversionResult {
        var stats = JointNameRepairStats()
        var usedNames: [String: Int] = [:]
        var converted: [SkeletonAsset.Joint] = []
        converted.reserveCapacity(joints.count)

        for (index, joint) in joints.enumerated() {
            if joint.hadInvalidEncoding {
                stats.invalidEncodingCount += 1
            }

            var baseName = sanitizeJointName(joint.rawName)
            if baseName.isEmpty {
                stats.emptyNameCount += 1
                baseName = "Joint"
            }

            let duplicateCount = usedNames[baseName, default: 0]
            let uniqueName: String
            if duplicateCount == 0 {
                uniqueName = baseName
            } else {
                uniqueName = "\(baseName)__\(duplicateCount)"
                stats.duplicateNameCount += 1
            }
            usedNames[baseName] = duplicateCount + 1

            let inverse: simd_float4x4? = {
                guard let matrix = joint.inverseBindGlobal, matrix.count >= 16 else { return nil }
                return simd_float4x4(
                    SIMD4<Float>(matrix[0], matrix[1], matrix[2], matrix[3]),
                    SIMD4<Float>(matrix[4], matrix[5], matrix[6], matrix[7]),
                    SIMD4<Float>(matrix[8], matrix[9], matrix[10], matrix[11]),
                    SIMD4<Float>(matrix[12], matrix[13], matrix[14], matrix[15])
                )
            }()

            let clampedParent: Int = {
                let parent = joint.parentIndex
                if parent < 0 { return -1 }
                if parent >= joints.count { return -1 }
                if parent == index { return -1 }
                return parent
            }()

            converted.append(
                SkeletonAsset.Joint(
                    name: uniqueName,
                    parentIndex: clampedParent,
                    bindLocalPosition: joint.bindLocalPosition,
                    bindLocalRotation: joint.bindLocalRotation,
                    bindLocalScale: joint.bindLocalScale,
                    inverseBindGlobalMatrix: inverse
                )
            )
        }

        return JointConversionResult(joints: converted, stats: stats)
    }

    static func buildInverseBindMap(from joints: [SkeletonAsset.Joint]) -> InverseBindMapBuildResult {
        var map: [String: simd_float4x4] = [:]
        var collisions = 0
        for joint in joints {
            guard let inverse = joint.inverseBindGlobalMatrix else { continue }
            if map[joint.name] != nil {
                collisions += 1
                continue
            }
            map[joint.name] = inverse
        }
        return InverseBindMapBuildResult(map: map, collisions: collisions)
    }

    static func convertClips(_ clips: [SceneClipDTO],
                             suggestedName: String,
                             jointNames: [String]) -> [ImportedAnimationClipData] {
        var usedNames: Set<String> = []
        return clips.enumerated().map { clipIndex, clip in
            let clipName = makeReadableClipName(
                rawName: clip.name,
                suggestedName: suggestedName,
                clipIndex: clipIndex,
                usedNames: &usedNames
            )

            let tracks: [AnimationClipAsset.JointTrack] = clip.tracks.map { track in
                AnimationClipAsset.JointTrack(
                    jointIndex: track.jointIndex,
                    translations: track.translations.map {
                        AnimationClipAsset.TranslationKeyframe(time: $0.time, value: $0.value)
                    },
                    rotations: track.rotations.map {
                        AnimationClipAsset.RotationKeyframe(time: $0.time, value: $0.value)
                    },
                    scales: track.scales.map {
                        AnimationClipAsset.ScaleKeyframe(time: $0.time, value: $0.value)
                    }
                )
            }

            let rootMotionJointIndex = detectRootMotionSourceJointIndex(tracks: tracks)
            let rootMotionJointName: String? = {
                guard let rootMotionJointIndex,
                      rootMotionJointIndex >= 0,
                      rootMotionJointIndex < jointNames.count else {
                    return nil
                }
                return jointNames[rootMotionJointIndex]
            }()
            return ImportedAnimationClipData(
                name: clipName,
                durationSeconds: max(0, clip.durationSeconds),
                tracks: tracks,
                interpolation: "linear",
                hasRootMotion: rootMotionJointIndex != nil,
                rootMotionJointIndex: rootMotionJointIndex,
                rootMotionJointName: rootMotionJointName
            )
        }
    }

    static func convertMeshes(_ meshes: [SceneMeshDTO]) -> [ImportedMeshData] {
        meshes.compactMap { mesh in
            guard !mesh.positions.isEmpty, !mesh.indices.isEmpty else { return nil }
            return ImportedMeshData(
                name: sanitizeName(mesh.name),
                positions: mesh.positions,
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

    static func convertMaterials(_ materials: [SceneMaterialDTO], sourceURL: URL) -> [ImportedMaterialReferenceData] {
        materials.map { material in
            var textures: [MeshTextureSemantic: URL] = [:]
            var embeddedSemantics: Set<MeshTextureSemantic> = []

            func resolveTexture(_ rawPath: String?, semantic: MeshTextureSemantic, embedded: Bool) {
                guard let rawPath else { return }
                let raw = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty else { return }
                let url: URL
                if raw.hasPrefix("/") {
                    url = URL(fileURLWithPath: raw)
                } else {
                    url = sourceURL.deletingLastPathComponent().appendingPathComponent(raw).standardizedFileURL
                }
                textures[semantic] = url
                if embedded {
                    embeddedSemantics.insert(semantic)
                }
            }

            resolveTexture(material.baseColorTexturePath, semantic: .baseColor, embedded: material.baseColorTextureEmbedded)
            resolveTexture(material.normalTexturePath, semantic: .normal, embedded: material.normalTextureEmbedded)
            resolveTexture(material.metallicTexturePath, semantic: .metallic, embedded: material.metallicTextureEmbedded)
            resolveTexture(material.roughnessTexturePath, semantic: .roughness, embedded: material.roughnessTextureEmbedded)
            resolveTexture(material.metallicRoughnessTexturePath, semantic: .metallicRoughness, embedded: material.metallicRoughnessTextureEmbedded)
            resolveTexture(material.occlusionTexturePath, semantic: .occlusion, embedded: material.occlusionTextureEmbedded)
            resolveTexture(material.emissiveTexturePath, semantic: .emissive, embedded: material.emissiveTextureEmbedded)

            let alpha = max(0, min(1, material.alpha))
            let alphaMode: MaterialAlphaMode = alpha < 0.99 ? .transparent : .opaque

            return ImportedMaterialReferenceData(
                name: sanitizeName(material.name),
                baseColor: material.baseColor,
                emissiveColor: material.emissiveColor,
                metallicFactor: material.metallicFactor,
                roughnessFactor: material.roughnessFactor,
                alphaMode: alphaMode,
                alphaCutoff: material.alphaCutoff,
                textures: textures,
                embeddedTextureSemantics: embeddedSemantics
            )
        }
    }

    static func makeReadableClipName(rawName: String,
                                     suggestedName: String,
                                     clipIndex: Int,
                                     usedNames: inout Set<String>) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedRaw = normalizeClipNameForPolicy(trimmed)
        let isGeneric = isGenericClipName(normalizedRaw)
        let preferredBase: String
        if !trimmed.isEmpty, !isGeneric {
            preferredBase = sanitizeName(trimmed)
        } else if clipIndex == 0 {
            preferredBase = sanitizeName(suggestedName)
        } else {
            preferredBase = sanitizeName("\(suggestedName)_Clip_\(clipIndex + 1)")
        }

        let base = preferredBase.isEmpty ? "Clip_\(clipIndex + 1)" : preferredBase
        if !usedNames.contains(base) {
            usedNames.insert(base)
            return base
        }
        var suffix = 2
        while usedNames.contains("\(base)_\(suffix)") {
            suffix += 1
        }
        let uniqued = "\(base)_\(suffix)"
        usedNames.insert(uniqued)
        return uniqued
    }

    static func normalizeClipNameForPolicy(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    static func isGenericClipName(_ normalized: String) -> Bool {
        if normalized.isEmpty { return true }
        let genericNames: Set<String> = [
            "mixamo.com",
            "take001",
            "defaulttake",
            "animstack",
            "animation"
        ]
        if genericNames.contains(normalized) {
            return true
        }
        if normalized.hasPrefix("take00") {
            return true
        }
        return false
    }

    static func sanitizeName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Asset" }
        let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|")
        let cleaned = trimmed.components(separatedBy: invalid).joined(separator: "_")
        return cleaned.isEmpty ? "Asset" : cleaned
    }

    static func sanitizeJointName(_ raw: String) -> String {
        if raw.isEmpty { return "" }
        let filteredScalars = raw.unicodeScalars.filter { scalar in
            let value = scalar.value
            if value == 0xFFFD { return false }
            if value < 0x20 || value == 0x7F { return false }
            if (0xD800...0xDFFF).contains(value) { return false }
            return true
        }
        let filtered = String(String.UnicodeScalarView(filteredScalars))
        let trimmed = filtered.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        return sanitizeName(trimmed)
    }

    static func sanitizedImportScale(_ raw: Float) -> Float {
        guard raw.isFinite, raw > 0 else { return 1.0 }
        return raw
    }

    static func applyTranslationScale(to meshes: [ImportedMeshData], factor: Float) -> [ImportedMeshData] {
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

    static func applyTranslationScale(to joints: [SkeletonAsset.Joint], factor: Float) -> [SkeletonAsset.Joint] {
        guard abs(factor - 1.0) > 0.0001 else { return joints }
        return joints.map { joint in
            let scaledInverse: simd_float4x4? = joint.inverseBindGlobalMatrix.map { inverseBind in
                let bindGlobal = simd_inverse(inverseBind)
                var scaledBindGlobal = bindGlobal
                scaledBindGlobal.columns.3.x *= factor
                scaledBindGlobal.columns.3.y *= factor
                scaledBindGlobal.columns.3.z *= factor
                return simd_inverse(scaledBindGlobal)
            }
            return SkeletonAsset.Joint(
                name: joint.name,
                parentIndex: joint.parentIndex,
                bindLocalPosition: joint.bindLocalPosition * factor,
                bindLocalRotation: joint.bindLocalRotation,
                bindLocalScale: joint.bindLocalScale,
                inverseBindGlobalMatrix: scaledInverse
            )
        }
    }

    static func applyTranslationScale(to clips: [ImportedAnimationClipData], factor: Float) -> [ImportedAnimationClipData] {
        guard abs(factor - 1.0) > 0.0001 else { return clips }
        return clips.map { clip in
            let scaledTracks = clip.tracks.map { track in
                AnimationClipAsset.JointTrack(
                    jointIndex: track.jointIndex,
                    translations: track.translations.map { key in
                        AnimationClipAsset.TranslationKeyframe(time: key.time, value: key.value * factor)
                    },
                    rotations: track.rotations,
                    scales: track.scales
                )
            }
            let hasRootMotion = scaledTracks.contains { track in
                guard track.translations.count > 1 else { return false }
                let first = track.translations[0].value
                return track.translations.contains { simd_length($0.value - first) > 0.001 }
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

    struct DecodedCString {
        let value: String
        let hadInvalidEncoding: Bool

        var valueOrNil: String? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    static func decodeCStringLossy(_ ptr: UnsafeMutablePointer<CChar>?) -> DecodedCString {
        guard let ptr else {
            return DecodedCString(value: "", hadInvalidEncoding: false)
        }
        if let valid = String(validatingUTF8: ptr) {
            return DecodedCString(value: valid, hadInvalidEncoding: false)
        }
        let length = Int(strlen(ptr))
        let bytes = UnsafeRawPointer(ptr).assumingMemoryBound(to: UInt8.self)
        let value = String(decoding: UnsafeBufferPointer(start: bytes, count: max(0, length)), as: UTF8.self)
        return DecodedCString(value: value, hadInvalidEncoding: true)
    }

    static func detectRootMotionSourceJointIndex(tracks: [AnimationClipAsset.JointTrack]) -> Int? {
        struct Candidate {
            let jointIndex: Int
            let motion: Float
        }

        let candidates: [Candidate] = tracks.compactMap { track in
            guard track.translations.count > 1 else { return nil }
            let first = track.translations[0].value
            let motion = track.translations.reduce(into: Float(0)) { partial, key in
                partial = max(partial, simd_length(key.value - first))
            }
            guard motion > 0.001 else { return nil }
            return Candidate(jointIndex: track.jointIndex, motion: motion)
        }
        guard !candidates.isEmpty else { return nil }
        return candidates.max { lhs, rhs in
            if abs(lhs.motion - rhs.motion) > 1.0e-5 {
                return lhs.motion < rhs.motion
            }
            return lhs.jointIndex > rhs.jointIndex
        }?.jointIndex
    }
}
