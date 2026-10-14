import AppKit
import UniformTypeIdentifiers

/// Open panels for choosing library sources.
@MainActor enum SourcePicker {
    static func chooseFolders(allowsMultiple: Bool = true) -> [URL] {
        let panel = NSOpenPanel()
        panel.title = allowsMultiple ? "Choose Wallpaper Folders" : "Choose Folder"
        panel.prompt = allowsMultiple ? "Add" : "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = !allowsMultiple
        panel.allowsMultipleSelection = allowsMultiple
        return panel.runModal() == .OK ? panel.urls : []
    }

    static func chooseImages() -> [URL] {
        let panel = NSOpenPanel()
        panel.title = "Choose Wallpapers"
        panel.prompt = "Add"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image]
        return panel.runModal() == .OK ? panel.urls : []
    }
}
