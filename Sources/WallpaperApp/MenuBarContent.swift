import SwiftUI
import WallpaperCore

struct MenuBarContent: View {
    @Environment(AppController.self) private var controller
    @Environment(WindowCoordinator.self) private var windows

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(WallpaperCore.appName).font(.headline)

            ForEach(shownDisplays) { display in
                CurrentWallpaperRow(
                    title: controller.settings.displayMode == .perDisplay ? display.name : nil,
                    wallpaper: controller.currentWallpaper(on: display))
            }

            if let message = controller.statusMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()
            HStack {
                Button("Library…") { windows.showLibrary() }
                Button("Settings…") { windows.showSettings() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    /// One row in "same" mode, one per display otherwise.
    private var shownDisplays: [Display] {
        let displays = controller.displays
        guard controller.settings.displayMode == .perDisplay else {
            return Array((displays.first(where: \.isMain) ?? displays.first).map { [$0] } ?? [])
        }
        return displays
    }
}

struct CurrentWallpaperRow: View {
    let title: String?
    let wallpaper: Wallpaper?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title {
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            if let wallpaper {
                ThumbnailView(path: wallpaper.path)
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Label(wallpaper.fileName, systemImage: wallpaper.mode.systemImage)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("No wallpaper chosen yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
