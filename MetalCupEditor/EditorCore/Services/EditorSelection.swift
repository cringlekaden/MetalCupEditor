/// EditorSelection.swift
/// Defines selection state services for the editor.
/// Created by Kaden Cringle.

import Foundation

final class EditorSelection {
    private(set) var selectedMaterialHandle: String = ""
    private(set) var selectedAnimationGraphHandle: String = ""
    private var openMaterialEditorHandle: String = ""
    private var openAnimationGraphEditorHandle: String = ""

    init() {}

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

    func requestOpenAnimationGraphEditor(handle: String) {
        selectedAnimationGraphHandle = handle
        openAnimationGraphEditorHandle = handle
    }

    func consumeOpenAnimationGraphEditorHandle() -> String? {
        guard !openAnimationGraphEditorHandle.isEmpty else { return nil }
        defer { openAnimationGraphEditorHandle = "" }
        return openAnimationGraphEditorHandle
    }
}
