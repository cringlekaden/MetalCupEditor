/// EditorSelection.swift
/// Defines selection state services for the editor.
/// Created by Kaden Cringle.

import Foundation

final class EditorSelection {
    static let shared = EditorSelection()

    private(set) var selectedMaterialHandle: String = ""
    private var openMaterialEditorHandle: String = ""

    private init() {}

    func setSelectedMaterial(handle: String?) {
        selectedMaterialHandle = handle ?? ""
    }

    func requestOpenMaterialEditor(handle: String) {
        selectedMaterialHandle = handle
        openMaterialEditorHandle = handle
    }

    func consumeOpenMaterialEditorHandle() -> String? {
        guard !openMaterialEditorHandle.isEmpty else { return nil }
        defer { openMaterialEditorHandle = "" }
        return openMaterialEditorHandle
    }
}
