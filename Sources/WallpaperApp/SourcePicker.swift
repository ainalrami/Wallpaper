import AppKit
import UniformTypeIdentifiers

/// Open panels for choosing library sources.
@MainActor enum SourcePicker {
    static func chooseFolders() -> [URL] {
        let panel = NSOpenPanel()
        panel.title = "Choose Wallpaper Folders"
        panel.prompt = "Add"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
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
