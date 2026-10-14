import SwiftUI
import WallpaperCore

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct GeneralSettingsView: View {
    @Environment(AppController.self) private var controller

    var body: some View {
        @Bindable var controller = controller
        Form {
            Section("Displays") {
                Picker("Wallpaper", selection: $controller.settings.displayMode) {
                    ForEach(DisplayMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
            }
            Section {
                Picker("Mode", selection: $controller.settings.defaultMode) {
                    ForEach(ScalingMode.allCases) { Text($0.title).tag($0) }
                }
                ColorPicker("Fill color", selection: Binding(
                    get: { controller.settings.defaultFillColor.color },
                    set: { controller.settings.defaultFillColor = RGBAColor($0) }),
                    supportsOpacity: false)
            } header: {
                Text("New Wallpapers")
            } footer: {
                Text("Applied to images the first time they are found. Each wallpaper keeps its own mode afterwards.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
