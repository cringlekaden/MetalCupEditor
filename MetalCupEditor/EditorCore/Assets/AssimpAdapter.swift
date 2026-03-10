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
    let vertexCount: Int
    let indexCount: Int
    let materialIndex: Int
    let hasNormals: Bool
    let hasTangents: Bool
    let hasUVs: Bool
    let hasSkinning: Bool
    let jointIndices: [SIMD4<UInt16>]
    let jointWeights: [SIMD4<Float>]
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
}

enum AssimpAdapter {
    static func scanFBX(url: URL, suggestedName: String) -> ImportedFBXData? {
        let flags: AiPostProcessStep = [
            .triangulate,
            .joinIdenticalVertices,
            .genSmoothNormals,
            .calcTangentSpace,
            .limitBoneWeights,
            .validateDataStructure
        ]

        let scene: AiScene
        do {
            scene = try AiScene(file: url.path, flags: flags)
        } catch {
#if DEBUG
            EngineLoggerContext.log(
                "Assimp failed to import FBX '\(url.lastPathComponent)': \(error)",
                level: .error,
                category: .assets
            )
#endif
            return nil
        }

        let importedMeshes = extractMeshes(from: scene)
        let importedMaterials = extractMaterials(from: scene, sourceURL: url)
        let skeleton = extractSkeleton(from: scene, meshes: importedMeshes)
        let clips = extractAnimations(from: scene, skeleton: skeleton, suggestedName: suggestedName)

        let hasMeshes = !importedMeshes.isEmpty
        let hasSkinnedMesh = importedMeshes.contains(where: { $0.hasSkinning }) && skeleton != nil
        let mode: AssimpFBXImportMode
        if !hasMeshes && !clips.isEmpty {
            mode = .animationOnly
        } else if hasSkinnedMesh {
            mode = .skeletalMesh
        } else {
            mode = .staticMesh
        }

        var warnings: [String] = []
        if !hasMeshes && mode != .animationOnly {
            warnings.append("No meshes found in FBX via Assimp.")
        }
        if hasMeshes && hasSkinnedMesh && skeleton == nil {
            warnings.append("Skinned mesh detected but skeleton extraction failed.")
        }
        if hasMeshes && importedMeshes.contains(where: { $0.hasSkinning }) && !hasSkinnedMesh {
            warnings.append("Joint streams found but skeleton hierarchy was incomplete.")
        }

        return ImportedFBXData(
            mode: mode,
            meshes: importedMeshes,
            skeleton: skeleton,
            clips: clips,
            materials: importedMaterials,
            warnings: warnings
        )
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
            warnings: data.warnings,
            materials: meshMaterials
        )
    }
}

private extension AssimpAdapter {
    static func extractMeshes(from scene: AiScene) -> [ImportedMeshData] {
        scene.meshes.map { mesh in
            var jointIndices = Array(repeating: SIMD4<UInt16>(repeating: 0), count: mesh.numVertices)
            var jointWeights = Array(repeating: SIMD4<Float>(repeating: 0), count: mesh.numVertices)

            if mesh.numBones > 0 {
                for (boneIndex, bone) in mesh.bones.enumerated() {
                    for weight in bone.weights where weight.vertexId >= 0 && weight.vertexId < mesh.numVertices {
                        let slot = nextWeightSlot(for: weight.vertexId, weights: jointWeights)
                        guard slot >= 0 && slot < 4 else { continue }
                        jointIndices[weight.vertexId][slot] = UInt16(clamping: boneIndex)
                        jointWeights[weight.vertexId][slot] = weight.weight
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

            let uv0 = mesh.texCoordsPacked.0
            let hasUVs = uv0 != nil && !(uv0?.isEmpty ?? true)
            let hasNormals = !mesh.normals.isEmpty
            let hasTangents = !mesh.tangents.isEmpty
            let indexCount = mesh.faces.reduce(0) { $0 + $1.indices.count }
            return ImportedMeshData(
                name: mesh.name ?? "",
                vertexCount: mesh.numVertices,
                indexCount: indexCount,
                materialIndex: mesh.materialIndex,
                hasNormals: hasNormals,
                hasTangents: hasTangents,
                hasUVs: hasUVs,
                hasSkinning: mesh.numBones > 0,
                jointIndices: jointIndices,
                jointWeights: jointWeights
            )
        }
    }

    static func extractMaterials(from scene: AiScene, sourceURL: URL) -> [ImportedMaterialReferenceData] {
        let sourceFolder = sourceURL.deletingLastPathComponent()
        return scene.materials.enumerated().map { index, material in
            let name = sanitizeName(material.name ?? "Material_\(index + 1)")
            let baseColor = material.getMaterialColor(.COLOR_DIFFUSE).map { SIMD3<Float>($0.x, $0.y, $0.z) } ?? SIMD3<Float>(repeating: 1)
            let emissiveColor = material.getMaterialColor(.COLOR_EMISSIVE).map { SIMD3<Float>($0.x, $0.y, $0.z) } ?? SIMD3<Float>(repeating: 0)
            let metallic = material.getMaterialProperty(.GLTF_PBRMETALLICROUGHNESS_METALLIC_FACTOR)?.float.first ?? 0.0
            let roughness = material.getMaterialProperty(.GLTF_PBRMETALLICROUGHNESS_ROUGHNESS_FACTOR)?.float.first ?? 1.0
            let alpha = material.getMaterialProperty(.OPACITY)?.float.first ?? 1.0
            let alphaMode: MaterialAlphaMode = alpha < 0.999 ? .blend : .opaque
            let alphaCutoff = material.getMaterialProperty(.GLTF_ALPHACUTOFF)?.float.first ?? 0.5

            var textures: [MeshTextureSemantic: URL] = [:]
            var embedded: Set<MeshTextureSemantic> = []
            resolveTexture(semantic: .baseColor, type: .baseColor, material: material, sourceFolder: sourceFolder, into: &textures, embeddedSemantics: &embedded)
            resolveTexture(semantic: .baseColor, type: .diffuse, material: material, sourceFolder: sourceFolder, into: &textures, embeddedSemantics: &embedded)
            resolveTexture(semantic: .normal, type: .normals, material: material, sourceFolder: sourceFolder, into: &textures, embeddedSemantics: &embedded)
            resolveTexture(semantic: .metallic, type: .metalness, material: material, sourceFolder: sourceFolder, into: &textures, embeddedSemantics: &embedded)
            resolveTexture(semantic: .roughness, type: .diffuseRoughness, material: material, sourceFolder: sourceFolder, into: &textures, embeddedSemantics: &embedded)
            resolveTexture(semantic: .occlusion, type: .ambientOcclusion, material: material, sourceFolder: sourceFolder, into: &textures, embeddedSemantics: &embedded)
            resolveTexture(semantic: .emissive, type: .emissive, material: material, sourceFolder: sourceFolder, into: &textures, embeddedSemantics: &embedded)
            resolveTexture(semantic: .emissive, type: .emissionColor, material: material, sourceFolder: sourceFolder, into: &textures, embeddedSemantics: &embedded)

            return ImportedMaterialReferenceData(
                name: name,
                baseColor: baseColor,
                emissiveColor: emissiveColor,
                metallicFactor: metallic,
                roughnessFactor: roughness,
                alphaMode: alphaMode,
                alphaCutoff: alphaCutoff,
                textures: textures,
                embeddedTextureSemantics: embedded
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

    static func extractSkeleton(from scene: AiScene, meshes: [ImportedMeshData]) -> ImportedSkeletonData? {
        let hasSkinnedMesh = meshes.contains(where: { $0.hasSkinning })
        let animationNodeNames = Set(scene.animations.flatMap { animation in
            animation.channels.compactMap { $0.nodeName }.filter { !$0.isEmpty }
        })

        var boneNames: Set<String> = []
        var inverseBindByName: [String: simd_float4x4] = [:]
        for mesh in scene.meshes where mesh.numBones > 0 {
            for bone in mesh.bones {
                guard let raw = bone.name, !raw.isEmpty else { continue }
                boneNames.insert(raw)
                inverseBindByName[raw] = simdMatrix(from: bone.offsetMatrix)
            }
        }

        if !hasSkinnedMesh && animationNodeNames.isEmpty {
            return nil
        }
        let requiredJointNames = boneNames.union(animationNodeNames)
        if requiredJointNames.isEmpty {
            return nil
        }

        var nodeByName: [String: AiNode] = [:]
        var parentByName: [String: String] = [:]
        collectNodes(scene.rootNode, parentName: nil, nodeByName: &nodeByName, parentByName: &parentByName)

        var included = Set<String>()
        for jointName in requiredJointNames where !jointName.isEmpty {
            var current: String? = jointName
            while let value = current, !value.isEmpty {
                if included.contains(value) { break }
                included.insert(value)
                current = parentByName[value]
            }
        }

        var orderedNames: [String] = []
        appendOrderedJointNames(scene.rootNode, included: included, output: &orderedNames)
        if orderedNames.isEmpty {
            orderedNames = Array(included).sorted()
        }

        var indexByName: [String: Int] = [:]
        var joints: [SkeletonAsset.Joint] = []
        joints.reserveCapacity(orderedNames.count)
        for name in orderedNames {
            let parentIndex: Int
            if let parentName = parentByName[name], let existing = indexByName[parentName] {
                parentIndex = existing
            } else {
                parentIndex = -1
            }
            let transform = nodeByName[name].map { simdMatrix(from: $0.transformation) } ?? matrix_identity_float4x4
            let decomp = TransformMath.decomposeMatrix(transform)
            let joint = SkeletonAsset.Joint(
                name: name,
                parentIndex: parentIndex,
                bindLocalPosition: decomp.position,
                bindLocalRotation: decomp.rotation,
                bindLocalScale: decomp.scale
            )
            indexByName[name] = joints.count
            joints.append(joint)
        }

        guard !joints.isEmpty else { return nil }
        return ImportedSkeletonData(joints: joints, inverseBindGlobalByJointName: inverseBindByName)
    }

    static func extractAnimations(from scene: AiScene,
                                  skeleton: ImportedSkeletonData?,
                                  suggestedName: String) -> [ImportedAnimationClipData] {
        guard !scene.animations.isEmpty else { return [] }
        let joints = skeleton?.joints ?? []
        let jointIndexByName = Dictionary(uniqueKeysWithValues: joints.enumerated().map { ($1.name, $0) })
        let fallbackJointIndexByName = Dictionary(uniqueKeysWithValues: Set(scene.animations.flatMap { $0.channels.compactMap(\.nodeName) })
            .sorted()
            .enumerated()
            .map { ($1, $0) })
        let jointLookup = jointIndexByName.isEmpty ? fallbackJointIndexByName : jointIndexByName

        var clips: [ImportedAnimationClipData] = []
        clips.reserveCapacity(scene.animations.count)
        for (clipIndex, animation) in scene.animations.enumerated() {
            let rawName = animation.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let clipName = sanitizeName(rawName.isEmpty ? "\(suggestedName)_Clip_\(clipIndex + 1)" : rawName)
            let tps = animation.ticksPerSecond > 0.0 ? animation.ticksPerSecond : 1.0
            let duration = max(0.0, animation.duration / tps)

            var tracks: [AnimationClipAsset.JointTrack] = []
            for channel in animation.channels {
                guard let nodeName = channel.nodeName,
                      let jointIndex = jointLookup[nodeName] else { continue }

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

            let hasRootMotion: Bool = tracks.contains { track in
                guard track.jointIndex == 0, track.translations.count > 1 else { return false }
                let first = track.translations[0].value
                return track.translations.contains { simd_length($0.value - first) > 0.001 }
            }

            clips.append(
                ImportedAnimationClipData(
                    name: clipName,
                    durationSeconds: Float(duration),
                    tracks: tracks,
                    interpolation: "linear",
                    hasRootMotion: hasRootMotion
                )
            )
        }
        return clips
    }

    static func collectNodes(_ node: AiNode,
                             parentName: String?,
                             nodeByName: inout [String: AiNode],
                             parentByName: inout [String: String]) {
        let name = node.name ?? ""
        if !name.isEmpty {
            if nodeByName[name] == nil {
                nodeByName[name] = node
            }
            if let parentName, !parentName.isEmpty, parentByName[name] == nil {
                parentByName[name] = parentName
            }
        }
        for child in node.children {
            collectNodes(child, parentName: name, nodeByName: &nodeByName, parentByName: &parentByName)
        }
    }

    static func appendOrderedJointNames(_ node: AiNode, included: Set<String>, output: inout [String]) {
        let name = node.name ?? ""
        if !name.isEmpty, included.contains(name) {
            output.append(name)
        }
        for child in node.children {
            appendOrderedJointNames(child, included: included, output: &output)
        }
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
        return 0
    }
}

