import SwiftUI
import WallpaperCore

struct WallpaperGrid: View {
    @Environment(AppController.self) private var controller
    let wallpapers: [Wallpaper]
    @Binding var selection: Wallpaper.ID?

    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 260), spacing: 14)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(wallpapers) { wallpaper in
                    WallpaperCell(wallpaper: wallpaper, isSelected: selection == wallpaper.id,
                                  isCurrent: currentIDs.contains(wallpaper.id))
                        .onTapGesture(count: 2) { controller.setWallpaper(id: wallpaper.id) }
                        .onTapGesture { selection = wallpaper.id }
                        .contextMenu { WallpaperActions(wallpaper: wallpaper) }
                }
            }
            .padding(16)
        }
        .overlay {
            if wallpapers.isEmpty {
                ContentUnavailableView("No Wallpapers", systemImage: "photo",
                                       description: Text("Images added to this source appear here."))
            }
        }
    }

    private var currentIDs: Set<Wallpaper.ID> {
        Set(controller.displays.compactMap { controller.currentWallpaper(on: $0)?.id })
    }
}

struct WallpaperCell: View {
    let wallpaper: Wallpaper
    let isSelected: Bool
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ThumbnailView(path: wallpaper.path)
                .aspectRatio(16 / 10, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                }
                .overlay(alignment: .bottomTrailing) { badges }
            Text(wallpaper.fileName)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .contentShape(Rectangle())
        .help(wallpaper.path)
    }

    private var badges: some View {
        HStack(spacing: 4) {
            if isCurrent {
                Image(systemName: "checkmark.circle.fill").help("On the desktop")
            }
            if wallpaper.isWallhaven {
                Image(systemName: wallpaper.isKept ? "pin.fill" : "globe")
                    .help(wallpaper.isKept ? "Kept Wallhaven download" : "Wallhaven download")
            }
            if !wallpaper.includedInCycling {
                Image(systemName: "pause.circle").help("Excluded from cycling")
            }
            Image(systemName: wallpaper.mode.systemImage).help(wallpaper.mode.title)
        }
        .font(.caption)
        .padding(5)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(6)
    }
}

/// Actions shared by the grid's context menu and the inspector.
struct WallpaperActions: View {
    @Environment(AppController.self) private var controller
    let wallpaper: Wallpaper

    var body: some View {
        if controller.settings.displayMode == .perDisplay, controller.displays.count > 1 {
            Menu("Set as Wallpaper") {
                Button("All Displays") { controller.setWallpaper(id: wallpaper.id) }
                Divider()
                ForEach(controller.displays) { display in
                    Button(display.name) { controller.setWallpaper(id: wallpaper.id, displayID: display.id) }
                }
            }
        } else {
            Button("Set as Wallpaper") { controller.setWallpaper(id: wallpaper.id) }
        }
        Toggle("Include in Cycling", isOn: Binding(
            get: { wallpaper.includedInCycling },
            set: { controller.setIncludedInCycling($0, ids: [wallpaper.id]) }))
        Divider()
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([wallpaper.url]) }
    }
}
