import ServiceManagement
import SwiftUI
import WallpaperCore

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            RotationSettingsView()
                .tabItem { Label("Rotation", systemImage: "arrow.triangle.2.circlepath") }
        }
        .frame(width: 580, height: 560)
    }
}

struct GeneralSettingsView: View {
    @Environment(AppController.self) private var controller
    // `@State` is a macro in the macOS 27 SDK whose plugin ships only with Xcode, so State is stored directly.
    private let _loginStatus = State(initialValue: LaunchAtLogin.status)
    private var loginStatus: SMAppService.Status {
        get { _loginStatus.wrappedValue }
        nonmutating set { _loginStatus.wrappedValue = newValue }
    }

    var body: some View {
        @Bindable var controller = controller
        Form {
            Section {
                Toggle("Open at login", isOn: Binding(
                    get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                    set: { enabled in
                        do {
                            try LaunchAtLogin.setEnabled(enabled)
                        } catch {
                            controller.statusMessage = "Couldn't change the login item: \(error.localizedDescription)"
                        }
                        loginStatus = LaunchAtLogin.status
                    }))
                if loginStatus == .requiresApproval {
                    HStack {
                        Text("Allow Wallpaper Manager in Login Items to finish.")
                            .foregroundStyle(.secondary)
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
            } footer: {
                Text("Keeps cycling and Wallhaven running after you log in. \"Change at startup\" applies whenever the app opens.")
                    .foregroundStyle(.secondary)
            }
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
