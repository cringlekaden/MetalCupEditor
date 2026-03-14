import Foundation
import simd
import MetalCupEngine

enum FbxSdkAdapter {
    static func scanFBX(url: URL, suggestedName: String) -> ImportedFBXData? {
        // Keep current mesh/material extraction behavior while replacing skeleton/clip
        // extraction with FBX SDK results when available.
        guard let baseData = AssimpAdapter.scanFBX(url: url, suggestedName: suggestedName) else {
            return nil
        }

        guard let scene = extractScene(url: url) else {
            return baseData
        }

        let joints = convertJoints(scene.joints)
        let clips = convertClips(scene.clips, suggestedName: suggestedName)
        let skeleton = joints.isEmpty
            ? nil
            : ImportedSkeletonData(
                joints: joints,
                inverseBindGlobalByJointName: Dictionary(uniqueKeysWithValues: joints.compactMap { joint in
                    guard let inverse = joint.inverseBindGlobalMatrix else { return nil }
                    return (joint.name, inverse)
                })
            )

        let hasMeshes = !baseData.meshes.isEmpty
        let hasSkinnedMesh = baseData.meshes.contains(where: { $0.hasSkinning }) && skeleton != nil
        let resolvedMode: AssimpFBXImportMode
        if !hasMeshes && !clips.isEmpty {
            resolvedMode = .animationOnly
        } else if hasSkinnedMesh {
            resolvedMode = .skeletalMesh
        } else {
            resolvedMode = .staticMesh
        }

        return ImportedFBXData(
            mode: resolvedMode,
            meshes: baseData.meshes,
            skeleton: skeleton ?? baseData.skeleton,
            clips: clips.isEmpty ? baseData.clips : clips,
            materials: baseData.materials,
            warnings: baseData.warnings,
            importScaleFactor: baseData.importScaleFactor,
            importScaleNormalizationMode: baseData.importScaleNormalizationMode
        )
    }
}

private extension FbxSdkAdapter {
    struct Scene {
        let joints: [MCEFbxJointDTO]
        let clips: [MCEFbxClipDTO]
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

        let joints = dto.jointCount > 0
            ? Array(UnsafeBufferPointer(start: dto.joints, count: Int(dto.jointCount)))
            : []
        let clips = dto.clipCount > 0
            ? Array(UnsafeBufferPointer(start: dto.clips, count: Int(dto.clipCount)))
            : []
        return Scene(joints: joints, clips: clips)
    }

    static func convertJoints(_ joints: [MCEFbxJointDTO]) -> [SkeletonAsset.Joint] {
        joints.map { joint in
            let name = joint.name.flatMap { String(cString: $0) } ?? "Joint"
            let inverse: simd_float4x4? = joint.hasInverseBindGlobal
                ? simd_float4x4(
                    SIMD4<Float>(joint.inverseBindGlobal[0], joint.inverseBindGlobal[1], joint.inverseBindGlobal[2], joint.inverseBindGlobal[3]),
                    SIMD4<Float>(joint.inverseBindGlobal[4], joint.inverseBindGlobal[5], joint.inverseBindGlobal[6], joint.inverseBindGlobal[7]),
                    SIMD4<Float>(joint.inverseBindGlobal[8], joint.inverseBindGlobal[9], joint.inverseBindGlobal[10], joint.inverseBindGlobal[11]),
                    SIMD4<Float>(joint.inverseBindGlobal[12], joint.inverseBindGlobal[13], joint.inverseBindGlobal[14], joint.inverseBindGlobal[15])
                )
                : nil
            return SkeletonAsset.Joint(
                name: name,
                parentIndex: Int(joint.parentIndex),
                bindLocalPosition: SIMD3<Float>(joint.bindLocalPosition[0], joint.bindLocalPosition[1], joint.bindLocalPosition[2]),
                bindLocalRotation: SIMD4<Float>(joint.bindLocalRotation[0], joint.bindLocalRotation[1], joint.bindLocalRotation[2], joint.bindLocalRotation[3]),
                bindLocalScale: SIMD3<Float>(joint.bindLocalScale[0], joint.bindLocalScale[1], joint.bindLocalScale[2]),
                inverseBindGlobalMatrix: inverse
            )
        }
    }

    static func convertClips(_ clips: [MCEFbxClipDTO], suggestedName: String) -> [ImportedAnimationClipData] {
        var usedNames: Set<String> = []
        return clips.enumerated().map { clipIndex, clip in
            let rawName = clip.name.flatMap { String(cString: $0) } ?? ""
            let clipName = AssimpAdapter.makeReadableClipName(
                rawName: rawName,
                suggestedName: suggestedName,
                clipIndex: clipIndex,
                usedNames: &usedNames
            )
            let tracks: [AnimationClipAsset.JointTrack]
            if clip.trackCount > 0, let rawTracks = clip.tracks {
                tracks = Array(UnsafeBufferPointer(start: rawTracks, count: Int(clip.trackCount))).map { track in
                    let translations: [AnimationClipAsset.TranslationKeyframe]
                    if track.translationCount > 0, let raw = track.translations {
                        translations = Array(UnsafeBufferPointer(start: raw, count: Int(track.translationCount))).map {
                            AnimationClipAsset.TranslationKeyframe(
                                time: $0.time,
                                value: SIMD3<Float>($0.value[0], $0.value[1], $0.value[2])
                            )
                        }
                    } else {
                        translations = []
                    }
                    let rotations: [AnimationClipAsset.RotationKeyframe]
                    if track.rotationCount > 0, let raw = track.rotations {
                        rotations = Array(UnsafeBufferPointer(start: raw, count: Int(track.rotationCount))).map {
                            AnimationClipAsset.RotationKeyframe(
                                time: $0.time,
                                value: SIMD4<Float>($0.value[0], $0.value[1], $0.value[2], $0.value[3])
                            )
                        }
                    } else {
                        rotations = []
                    }
                    let scales: [AnimationClipAsset.ScaleKeyframe]
                    if track.scaleCount > 0, let raw = track.scales {
                        scales = Array(UnsafeBufferPointer(start: raw, count: Int(track.scaleCount))).map {
                            AnimationClipAsset.ScaleKeyframe(
                                time: $0.time,
                                value: SIMD3<Float>($0.value[0], $0.value[1], $0.value[2])
                            )
                        }
                    } else {
                        scales = []
                    }
                    return AnimationClipAsset.JointTrack(
                        jointIndex: Int(track.jointIndex),
                        translations: translations,
                        rotations: rotations,
                        scales: scales
                    )
                }
            } else {
                tracks = []
            }

            let rootMotionJointIndex = AssimpAdapter.detectRootMotionSourceJointIndex(tracks: tracks, joints: nil)
            return ImportedAnimationClipData(
                name: clipName,
                durationSeconds: max(0, clip.durationSeconds),
                tracks: tracks,
                interpolation: "linear",
                hasRootMotion: rootMotionJointIndex != nil,
                rootMotionJointIndex: rootMotionJointIndex,
                rootMotionJointName: nil
            )
        }
    }
}
