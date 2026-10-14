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

            HStack {
                Button {
                    Task { await controller.nextWallpaper() }
                } label: {
                    Label("Next Wallpaper", systemImage: "forward.fill")
                }
                .disabled(controller.library.wallpapers.isEmpty)
                Spacer()
                if controller.settings.rotationSource != .off {
                    Button {
                        controller.settings.isRotationPaused.toggle()
                    } label: {
                        Label(controller.settings.isRotationPaused ? "Resume" : "Pause",
                              systemImage: controller.settings.isRotationPaused ? "play.fill" : "pause.fill")
                    }
                }
            }
            rotationStatus
            if controller.isFetchingWallhaven {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Fetching from Wallhaven…").font(.caption)
                }
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

    @ViewBuilder private var rotationStatus: some View {
        let source = controller.settings.rotationSource
        Group {
            if source == .off {
                Text("Automatic changes are off")
            } else if controller.settings.isRotationPaused {
                Text("\(source.title) is paused")
            } else if let next = controller.nextRotationDate {
                Text("\(source.title): next change \(Text(next, style: .relative)) from now")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
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
