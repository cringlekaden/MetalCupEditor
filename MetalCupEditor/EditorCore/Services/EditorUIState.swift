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
}
