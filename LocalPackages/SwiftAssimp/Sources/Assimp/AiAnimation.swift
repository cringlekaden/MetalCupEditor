//
// AiAnimation.swift
// SwiftAssimp
//
// Copyright © 2019-2023 Christian Treffs. All rights reserved.
// Licensed under BSD 3-Clause License. See LICENSE file for details.

@_implementationOnly import CAssimp

public struct AiQuat {
    public let x: AiReal
    public let y: AiReal
    public let z: AiReal
    public let w: AiReal

    init(_ q: aiQuaternion) {
        x = q.x
        y = q.y
        z = q.z
        w = q.w
    }
}

public struct AiVectorKey {
    public let time: Double
    public let value: Vec3

    init(_ key: aiVectorKey) {
        time = key.mTime
        value = Vec3(key.mValue)
    }
}

public struct AiQuatKey {
    public let time: Double
    public let value: AiQuat

    init(_ key: aiQuatKey) {
        time = key.mTime
        value = AiQuat(key.mValue)
    }
}

public struct AiNodeAnimation {
    public let nodeName: String?
    public let positionKeys: [AiVectorKey]
    public let rotationKeys: [AiQuatKey]
    public let scalingKeys: [AiVectorKey]
    public let preState: UInt32
    public let postState: UInt32

    init(_ nodeAnim: aiNodeAnim) {
        nodeName = String(nodeAnim.mNodeName)

        let pCount = Int(nodeAnim.mNumPositionKeys)
        if pCount > 0, let base = nodeAnim.mPositionKeys {
            positionKeys = UnsafeBufferPointer(start: base, count: pCount).map(AiVectorKey.init)
        } else {
            positionKeys = []
        }

        let rCount = Int(nodeAnim.mNumRotationKeys)
        if rCount > 0, let base = nodeAnim.mRotationKeys {
            rotationKeys = UnsafeBufferPointer(start: base, count: rCount).map(AiQuatKey.init)
        } else {
            rotationKeys = []
        }

        let sCount = Int(nodeAnim.mNumScalingKeys)
        if sCount > 0, let base = nodeAnim.mScalingKeys {
            scalingKeys = UnsafeBufferPointer(start: base, count: sCount).map(AiVectorKey.init)
        } else {
            scalingKeys = []
        }

        preState = nodeAnim.mPreState.rawValue
        postState = nodeAnim.mPostState.rawValue
    }
}

public struct AiAnimation {
    public let name: String?
    public let duration: Double
    public let ticksPerSecond: Double
    public let channels: [AiNodeAnimation]

    init(_ animation: aiAnimation) {
        name = String(animation.mName)
        duration = animation.mDuration
        ticksPerSecond = animation.mTicksPerSecond
        let count = Int(animation.mNumChannels)
        if count > 0, let base = animation.mChannels {
            channels = UnsafeBufferPointer(start: base, count: count).compactMap { ptr in
                guard let channel = ptr?.pointee else { return nil }
                return AiNodeAnimation(channel)
            }
        } else {
            channels = []
        }
    }
}
