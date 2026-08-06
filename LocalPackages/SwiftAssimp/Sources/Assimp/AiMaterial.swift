//
// AiMaterial.swift
// SwiftAssimp
//
// Copyright © 2019-2023 Christian Treffs. All rights reserved.
// Licensed under BSD 3-Clause License. See LICENSE file for details.

@_implementationOnly import CAssimp

// Ref: https://github.com/helix-toolkit/helix-toolkit/blob/master/Source/HelixToolkit.SharpDX.Assimp.Shared/ImporterPartial_Material.cs
public struct AiMaterial {
    let materialPtr: UnsafePointer<aiMaterial>
    private let lifetime: AiSceneLifetime

    init(materialPtr: UnsafePointer<aiMaterial>, lifetime: AiSceneLifetime) {
        self.materialPtr = materialPtr
        self.lifetime = lifetime
        let material = materialPtr.pointee
        let numProperties = Int(material.mNumProperties)
        self.numProperties = numProperties
        let numAllocated = Int(material.mNumAllocated)
        self.numAllocated = numAllocated
        properties = {
            guard numProperties > 0, let propertyPtrs = material.mProperties else {
                return []
            }
            return UnsafeBufferPointer(start: propertyPtrs, count: numProperties).compactMap { propPtr in
                guard let propPtr else { return nil }
                return AiMaterialProperty(propPtr.pointee)
            }
        }()
    }

    init?(materialPtr matPtr: UnsafePointer<aiMaterial>?, lifetime: AiSceneLifetime) {
        guard let matPtr = matPtr else {
            return nil
        }
        self.init(materialPtr: matPtr, lifetime: lifetime)
    }

    /// Number of properties in the data base
    public var numProperties: Int

    /// Storage allocated
    public var numAllocated: Int

    /// List of all material properties loaded.
    public var properties: [AiMaterialProperty]

    public lazy var typedProperties: [AiMaterialPropertyIdentifiable] = properties.compactMap { prop -> AiMaterialPropertyIdentifiable? in
        switch prop.type {
        case .string:
            return AiMaterialPropertyString(prop)

        case .float:
            return AiMaterialPropertyFloat(prop)

        case .int:
            return AiMaterialPropertyInt(prop)

        case .buffer:
            return AiMaterialPropertyBuffer(prop)

        case .double:
            return AiMaterialPropertyDouble(prop)

        default:
            return nil
        }
    }

    /*
     - aiGetMaterialProperty
     - aiGetMaterialTextureCount
     - aiGetMaterialTexture
     - aiGetMaterialString
     - aiGetMaterialColor

     - aiGetMaterialFloat
     - aiGetMaterialFloatArray
     - aiGetMaterialInteger
     - aiGetMaterialIntegerArray
     - aiGetMaterialUVTransform
     - aiGetMaterialXXX
    */
    public func getMaterialProperty(_ key: AiMatKey) -> AiMaterialProperty? {
        var matPropPtr: UnsafePointer<aiMaterialProperty>?
        let result = aiGetMaterialProperty(materialPtr,
                                           key.baseName,
                                           key.texType,
                                           key.texIndex,
                                           &matPropPtr)

        guard result == aiReturn_SUCCESS, let property = matPropPtr?.pointee else {
            return nil
        }
        return AiMaterialProperty(property)
    }

    /// Get the number of textures for a particular texture type.
    public func getMaterialTextureCount(texType: AiTextureType) -> Int {
        Int(aiGetMaterialTextureCount(materialPtr, texType.type))
    }

    public func getMaterialTexture(texType: AiTextureType, texIndex: Int) -> String? {
        var path = aiString()
        // NOTE: the properties do not seem to be working
        var mapping: aiTextureMapping = aiTextureMapping_UV
        var uvIndex: UInt32 = 0
        var blend: ai_real = 0.0
        var texOp: aiTextureOp = aiTextureOp_Multiply
        var mapmode: [aiTextureMapMode] = [aiTextureMapMode_Wrap, aiTextureMapMode_Wrap]
        var flags: UInt32 = 0
        let result = aiGetMaterialTexture(materialPtr,
                                          texType.type,
                                          UInt32(texIndex),
                                          &path,
                                          &mapping,
                                          &uvIndex,
                                          &blend,
                                          &texOp,
                                          &mapmode,
                                          &flags)

        guard result == aiReturn_SUCCESS else {
            return nil
        }

        return String(path)
    }

    public func getMaterialString(_ key: AiMatKey) -> String? {
        var string = aiString()
        let result = aiGetMaterialString(materialPtr,
                                         key.baseName,
                                         key.texType,
                                         key.texIndex,
                                         &string)

        guard result == aiReturn_SUCCESS else {
            return nil
        }

        return String(string)
    }

    public func getMaterialColor(_ key: AiMatKey) -> SIMD4<AiReal>? {
        var color = aiColor4D()
        let result = aiGetMaterialColor(materialPtr,
                                        key.baseName,
                                        key.texType,
                                        key.texIndex,
                                        &color)
        guard result == aiReturn_SUCCESS else {
            return nil
        }
        return SIMD4<Float>(color.r, color.g, color.b, color.a)
    }

    public func getMaterialFloatArray(_ key: AiMatKey) -> [AiReal]? {
        let count = MemoryLayout<aiUVTransform>.stride / MemoryLayout<ai_real>.stride
        return [ai_real](unsafeUninitializedCapacity: count) { buffer, written in
            var pMax: UInt32 = 0
            let result = aiGetMaterialFloatArray(materialPtr,
                                                 key.baseName,
                                                 key.texType,
                                                 key.texIndex,
                                                 buffer.baseAddress!,
                                                 &pMax)
            guard result == aiReturn_SUCCESS else {
                return
            }

            written = Int(pMax)
        }
    }

    public func getMaterialIntegerArray(_ key: AiMatKey) -> [Int32] {
        [Int32](unsafeUninitializedCapacity: 4) { buffer, written in
            var pMax: UInt32 = 0
            let result = aiGetMaterialIntegerArray(materialPtr,
                                                   key.baseName,
                                                   key.texType,
                                                   key.texIndex,
                                                   buffer.baseAddress!,
                                                   &pMax)

            guard result == aiReturn_SUCCESS, pMax > 0 else {
                return
            }

            written = Int(pMax)
        }
    }
}

extension AiMaterial {
    @inlinable public var name: String? { getMaterialString(.NAME) }

    @inlinable public var shadingModel: AiShadingMode? {
        guard let int = getMaterialProperty(.SHADING_MODEL)?.int.first else {
            return nil
        }
        return AiShadingMode(rawValue: UInt32(int))
    }

    @inlinable public var cullBackfaces: Bool? {
        guard let int = getMaterialProperty(.TWOSIDED)?.int.first else {
            return nil
        }

        return !(int == 1)
    }

    public var blendMode: AiBlendMode? {
        guard let int = getMaterialProperty(.BLEND_FUNC)?.int.first else {
            return nil
        }

        return AiBlendMode(aiBlendMode(UInt32(int)))
    }
}

/// Defines alpha-blend flags.
///
/// If you're familiar with OpenGL or D3D, these flags aren't new to you.
/// They define *how* the final color value of a pixel is computed, basing
/// on the previous color at that pixel and the new color value from the
/// material.
/// The blend formula is:
/// ```
///   SourceColor * SourceBlend + DestColor * DestBlend
/// ```
/// where DestColor is the previous color in the frame-buffer at this
/// position and SourceColor is the material color before the transparency
/// calculation.<br>
/// This corresponds to the #AI_MATKEY_BLEND_FUNC property.
///
public enum AiBlendMode {
    /// Default blend mode
    ///
    /// Formula:
    /// ```
    /// SourceColor*SourceAlpha + DestColor*(1-SourceAlpha)
    /// ```
    case `default`

    ///  Additive blending
    ///
    /// Formula:
    /// ```
    /// SourceColor*1 + DestColor*1
    /// ```
    case additive

    init?(_ blendMode: aiBlendMode) {
        switch blendMode {
        case aiBlendMode_Default:
            self = .default

        case aiBlendMode_Additive:
            self = .additive

        default:
            return nil
        }
    }
}
