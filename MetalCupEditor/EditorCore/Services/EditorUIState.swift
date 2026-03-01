/// EditorUIState.swift
/// Defines persisted UI state for the editor.
/// Created by Kaden Cringle.

import Foundation

final class EditorUIState {
    private let settingsStore: EditorSettingsStore

    init(settingsStore: EditorSettingsStore) {
        self.settingsStore = settingsStore
    }

    func panelIsVisible(_ panelId: String, defaultValue: Bool) -> Bool {
        settingsStore.panelIsVisible(panelId, defaultValue: defaultValue)
    }

    func setPanelVisible(_ panelId: String, visible: Bool) {
        settingsStore.setPanelVisible(panelId, visible: visible)
    }

    func headerIsOpen(_ headerId: String, defaultValue: Bool) -> Bool {
        settingsStore.headerIsOpen(headerId, defaultValue: defaultValue)
    }

    func setHeaderOpen(_ headerId: String, open: Bool) {
        settingsStore.setHeaderOpen(headerId, open: open)
    }

    func lastSelectedEntityId() -> String {
        settingsStore.lastSelectedEntityId
    }

    func setLastSelectedEntityId(_ entityId: String) {
        settingsStore.setLastSelectedEntityId(entityId)
    }

    func lastContentBrowserPath() -> String {
        settingsStore.lastContentBrowserPath
    }

    func setLastContentBrowserPath(_ path: String) {
        settingsStore.setLastContentBrowserPath(path)
    }

    func viewportGizmoOperation() -> Int {
        settingsStore.viewportGizmoOperation
    }

    func setViewportGizmoOperation(_ value: Int) {
        settingsStore.setViewportGizmoOperation(value)
    }

    func viewportGizmoSpaceMode() -> Int {
        settingsStore.viewportGizmoSpaceMode
    }

    func setViewportGizmoSpaceMode(_ value: Int) {
        settingsStore.setViewportGizmoSpaceMode(value)
    }

    func viewportSnapEnabled() -> Bool {
        settingsStore.viewportSnapEnabled
    }

    func setViewportSnapEnabled(_ value: Bool) {
        settingsStore.setViewportSnapEnabled(value)
    }

    func themeMode() -> Int { settingsStore.themeMode }
    func setThemeMode(_ value: Int) { settingsStore.setThemeMode(value) }
    func themeAccent() -> (Float, Float, Float) {
        (settingsStore.themeAccentR, settingsStore.themeAccentG, settingsStore.themeAccentB)
    }
    func setThemeAccent(r: Float, g: Float, b: Float) {
        settingsStore.setThemeAccent(r: r, g: g, b: b)
    }
    func themeUIScale() -> Float { settingsStore.themeUIScale }
    func setThemeUIScale(_ value: Float) { settingsStore.setThemeUIScale(value) }
    func themeRoundedUI() -> Bool { settingsStore.themeRoundedUI }
    func setThemeRoundedUI(_ value: Bool) { settingsStore.setThemeRoundedUI(value) }
    func themeCornerRounding() -> Float { settingsStore.themeCornerRounding }
    func setThemeCornerRounding(_ value: Float) { settingsStore.setThemeCornerRounding(value) }
    func themeSpacingPreset() -> Int { settingsStore.themeSpacingPreset }
    func setThemeSpacingPreset(_ value: Int) { settingsStore.setThemeSpacingPreset(value) }
    func viewportShowWorldIcons() -> Bool { settingsStore.viewportShowWorldIcons }
    func setViewportShowWorldIcons(_ value: Bool) { settingsStore.setViewportShowWorldIcons(value) }
    func viewportWorldIconBaseSize() -> Float { settingsStore.viewportWorldIconBaseSize }
    func setViewportWorldIconBaseSize(_ value: Float) { settingsStore.setViewportWorldIconBaseSize(value) }
    func viewportWorldIconDistanceScale() -> Float { settingsStore.viewportWorldIconDistanceScale }
    func setViewportWorldIconDistanceScale(_ value: Float) { settingsStore.setViewportWorldIconDistanceScale(value) }
    func viewportWorldIconMinSize() -> Float { settingsStore.viewportWorldIconMinSize }
    func setViewportWorldIconMinSize(_ value: Float) { settingsStore.setViewportWorldIconMinSize(value) }
    func viewportWorldIconMaxSize() -> Float { settingsStore.viewportWorldIconMaxSize }
    func setViewportWorldIconMaxSize(_ value: Float) { settingsStore.setViewportWorldIconMaxSize(value) }
    func viewportShowSelectedCameraFrustum() -> Bool { settingsStore.viewportShowSelectedCameraFrustum }
    func setViewportShowSelectedCameraFrustum(_ value: Bool) { settingsStore.setViewportShowSelectedCameraFrustum(value) }
    func viewportPreviewEnabled() -> Bool { settingsStore.viewportPreviewEnabled }
    func setViewportPreviewEnabled(_ value: Bool) { settingsStore.setViewportPreviewEnabled(value) }
    func viewportPreviewSize() -> Float { settingsStore.viewportPreviewSize }
    func setViewportPreviewSize(_ value: Float) { settingsStore.setViewportPreviewSize(value) }
    func viewportPreviewPosition() -> Int { settingsStore.viewportPreviewPosition }
    func setViewportPreviewPosition(_ value: Int) { settingsStore.setViewportPreviewPosition(value) }
    func editorDebugGridEnabled() -> Bool { settingsStore.editorDebugGridEnabled }
    func setEditorDebugGridEnabled(_ value: Bool) { settingsStore.setEditorDebugGridEnabled(value) }
    func editorDebugOutlineEnabled() -> Bool { settingsStore.editorDebugOutlineEnabled }
    func setEditorDebugOutlineEnabled(_ value: Bool) { settingsStore.setEditorDebugOutlineEnabled(value) }
    func editorDebugPhysicsEnabled() -> Bool { settingsStore.editorDebugPhysicsEnabled }
    func setEditorDebugPhysicsEnabled(_ value: Bool) { settingsStore.setEditorDebugPhysicsEnabled(value) }
}
