import SwiftUI
import WallpaperCore

/// Per-Space wallpapers and groups of Spaces that share one.
struct SpacesSettingsView: View {
    @Environment(AppController.self) private var controller

    var body: some View {
        @Bindable var controller = controller
        Form {
            Section {
                Toggle("Different wallpaper for each Space", isOn: $controller.settings.spaces.isEnabled)
                    .disabled(controller.spaceLayout == nil)
                if controller.spaceLayout == nil {
                    Label("Spaces can't be read on this version of macOS, so all Spaces share one wallpaper.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("macOS only lets apps change the wallpaper of the Space you're on, so each Space gets its wallpaper when you switch to it. Group Spaces to give them the same wallpaper.")
                    .foregroundStyle(.secondary)
            }

            if controller.targetContext.isPerSpace, let layout = controller.spaceLayout {
                ForEach(sections(layout), id: \.display.id) { section in
                    Section(section.title) {
                        ForEach(section.spaces) { space in
                            SpaceRow(space: space, display: section.display)
                        }
                    }
                }
                Section {
                    ForEach(controller.settings.spaces.groups) { group in
                        SpaceGroupRow(group: group)
                    }
                    Button("New Group", systemImage: "plus") {
                        controller.createSpaceGroup(named: "Group \(controller.settings.spaces.groups.count + 1)")
                    }
                    .buttonStyle(.glass)
                } header: {
                    Text("Groups")
                } footer: {
                    Text("Choose a group for a Space above. Spaces in a group always show the same wallpaper.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { controller.refreshDisplaysAndSpaces() }
    }

    private struct DisplaySection {
        var display: Display
        var title: String
        var spaces: [DesktopSpace]
    }

    /// One section per display, or a single one when Spaces span all displays.
    private func sections(_ layout: SpaceLayout) -> [DisplaySection] {
        let displays = controller.displays
        if layout.spansDisplays || displays.count <= 1, let main = displays.first(where: \.isMain) ?? displays.first {
            return [DisplaySection(display: main, title: "Spaces", spaces: layout.spaces)]
        }
        return displays.map { DisplaySection(display: $0, title: $0.name, spaces: layout.spaces(on: $0.id)) }
    }
}

struct SpaceRow: View {
    @Environment(AppController.self) private var controller
    let space: DesktopSpace
    let display: Display

    var body: some View {
        let target = controller.targetContext.target(display: display, space: space)
        HStack(spacing: 10) {
            Group {
                if let wallpaper = controller.wallpaper(for: target) {
                    ThumbnailView(path: wallpaper.path, maxPixelSize: 160)
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(width: 56, height: 35)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(space.title)
                if space.isCurrent {
                    Text("Current Space").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Picker("Group", selection: Binding(
                get: { controller.settings.spaces.group(containing: space.id)?.id },
                set: { controller.setSpaceGroup($0, forSpace: space.id) })) {
                Text("Own Wallpaper").tag(SpaceGroup.ID?.none)
                if !controller.settings.spaces.groups.isEmpty {
                    Divider()
                }
                ForEach(controller.settings.spaces.groups) { group in
                    Text(group.name).tag(Optional(group.id))
                }
            }
            .labelsHidden()
            .frame(width: 170)
        }
    }
}

struct SpaceGroupRow: View {
    @Environment(AppController.self) private var controller
    let group: SpaceGroup

    var body: some View {
        HStack {
            TextField("Name", text: Binding(
                get: { group.name },
                set: { controller.renameSpaceGroup(id: group.id, to: $0) }))
                .textFieldStyle(.plain)
            Spacer()
            Text(memberSummary)
                .foregroundStyle(.secondary)
            Button("Delete Group", systemImage: "trash", role: .destructive) {
                controller.deleteSpaceGroup(id: group.id)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
    }

    /// e.g. "Desktops 1, 2, 4"
    private var memberSummary: String {
        let numbers = (controller.spaceLayout?.spaces ?? [])
            .filter { group.spaceIDs.contains($0.id) }
            .map(\.number)
            .sorted()
        switch numbers.count {
        case 0: return "No Spaces"
        case 1: return "Desktop \(numbers[0])"
        default: return "Desktops " + numbers.map(String.init).joined(separator: ", ")
        }
    }
}

/// "Set as Wallpaper" choices: the current Space, all Spaces, a specific Space or group, and
/// the display in per-display mode.
struct SetWallpaperMenuItems: View {
    @Environment(AppController.self) private var controller
    let wallpaper: Wallpaper

    var body: some View {
        let context = controller.targetContext
        let multipleDisplays = controller.settings.displayMode == .perDisplay && controller.displays.count > 1
        if context.isPerSpace {
            Button("This Space") { controller.setWallpaper(id: wallpaper.id) }
            if multipleDisplays {
                ForEach(controller.displays) { display in
                    Button("This Space on \(display.name)") {
                        controller.setWallpaper(id: wallpaper.id, displayID: display.id)
                    }
                }
            }
            Button("All Spaces") { controller.setWallpaperOnAllSpaces(id: wallpaper.id) }
            Divider()
            Section("Spaces") {
                ForEach(context.spaceTargets()) { target in
                    Button(target.title) { controller.setWallpaper(id: wallpaper.id, target: target) }
                }
            }
        } else if multipleDisplays {
            Button("All Displays") { controller.setWallpaper(id: wallpaper.id) }
            Divider()
            ForEach(controller.displays) { display in
                Button(display.name) { controller.setWallpaper(id: wallpaper.id, displayID: display.id) }
            }
        }
    }

    /// Whether there are choices beyond setting it everywhere.
    static func hasChoices(_ controller: AppController) -> Bool {
        controller.targetContext.isPerSpace
            || (controller.settings.displayMode == .perDisplay && controller.displays.count > 1)
    }
}
