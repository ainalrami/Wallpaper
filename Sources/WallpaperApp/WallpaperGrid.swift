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

    // `@State` is a macro in the macOS 27 SDK whose plugin ships only with Xcode, so State is stored directly.
    private let _isHovered = State(initialValue: false)
    private var isHovered: Bool {
        get { _isHovered.wrappedValue }
        nonmutating set { _isHovered.wrappedValue = newValue }
    }

    private let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ThumbnailView(path: wallpaper.path)
                .aspectRatio(16 / 10, contentMode: .fit)
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(isSelected ? Color.accentColor : .white.opacity(0.08), lineWidth: isSelected ? 3 : 1)
                }
                .overlay(alignment: .bottomTrailing) { badges }
                .shadow(color: .black.opacity(isHovered ? 0.28 : 0.12), radius: isHovered ? 12 : 4, y: isHovered ? 6 : 2)
                .scaleEffect(isHovered ? 1.025 : 1)
                .animation(.smooth(duration: 0.2), value: isHovered)
                .onHover { isHovered = $0 }
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
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .glassEffect(.regular, in: .capsule)
        .padding(7)
    }
}

/// Actions shared by the grid's context menu and the inspector.
struct WallpaperActions: View {
    @Environment(AppController.self) private var controller
    let wallpaper: Wallpaper

    var body: some View {
        if SetWallpaperMenuItems.hasChoices(controller) {
            Menu("Set as Wallpaper") {
                SetWallpaperMenuItems(wallpaper: wallpaper)
            }
        } else {
            Button("Set as Wallpaper") { controller.setWallpaper(id: wallpaper.id) }
        }
        Toggle("Include in Cycling", isOn: Binding(
            get: { wallpaper.includedInCycling },
            set: { controller.setIncludedInCycling($0, ids: [wallpaper.id]) }))
        if case .wallhaven(let id) = wallpaper.origin {
            Toggle("Keep", isOn: Binding(
                get: { wallpaper.isKept },
                set: { controller.setKept($0, ids: [wallpaper.id]) }))
            Link("Open on Wallhaven", destination: WallhavenLinks.page(for: id))
        }
        Divider()
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([wallpaper.url]) }
    }
}
