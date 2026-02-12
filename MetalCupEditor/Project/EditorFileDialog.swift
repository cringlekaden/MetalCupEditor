import AppKit
import Foundation

enum EditorFileDialog {
    static func chooseFolder(prompt: String, message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        panel.message = message
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func openFile(allowedExtensions: [String], directoryURL: URL? = nil, message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = allowedExtensions
        panel.message = message
        if let directoryURL {
            panel.directoryURL = directoryURL
        }
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func saveFile(defaultName: String, allowedExtensions: [String], directoryURL: URL? = nil, message: String) -> URL? {
        let panel = NSSavePanel()
        panel.allowedFileTypes = allowedExtensions
        panel.nameFieldStringValue = defaultName
        panel.message = message
        if let directoryURL {
            panel.directoryURL = directoryURL
        }
        return panel.runModal() == .OK ? panel.url : nil
    }
}
