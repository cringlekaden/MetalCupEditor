//
// String+aiString.swift
// SwiftAssimp
//
// Copyright © 2019-2023 Christian Treffs. All rights reserved.
// Licensed under BSD 3-Clause License. See LICENSE file for details.

@_implementationOnly import CAssimp

private func decodeAssimpString(_ source: aiString) -> String? {
    let declaredLength = Int(source.length)
    guard declaredLength > 0 else { return nil }
    let sourceData = source.data

    let bytes: [UInt8] = withUnsafeBytes(of: sourceData) { rawBuffer in
        guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
            return []
        }

        // aiString stores explicit byte length; do not rely on null termination.
        let boundedLength = min(declaredLength, rawBuffer.count)
        let prefix = UnsafeBufferPointer(start: baseAddress, count: boundedLength)
        if let firstNull = prefix.firstIndex(of: 0) {
            return Array(prefix.prefix(firstNull))
        }
        return Array(prefix)
    }

    guard !bytes.isEmpty else { return nil }
    return String(decoding: bytes, as: UTF8.self)
}

extension String {
    init?(_ aiString: aiString) {
        guard let decoded = decodeAssimpString(aiString) else { return nil }
        self = decoded
    }

    init?(bytes: UnsafeMutablePointer<Int8>, length: Int) {
        let bufferPtr = UnsafeMutableBufferPointer(start: bytes,
                                                   count: length)

        let codeUnits: [UTF8.CodeUnit] = bufferPtr
            // .map { $0 > 0 ? $0 : Int8(0x20) } // this replaces all invalid characters with blank space
            .map { UTF8.CodeUnit($0) }

        self.init(decoding: codeUnits, as: UTF8.self)
    }
}
