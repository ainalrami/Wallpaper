import ServiceManagement
import SwiftUI
import WallpaperCore

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            RotationSettingsView()
                .tabItem { Label("Cycling", systemImage: "arrow.triangle.2.circlepath") }
            WallhavenSettingsView()
                .tabItem { Label("Wallhaven", systemImage: "globe") }
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

struct RotationSettingsView: View {
    @Environment(AppController.self) private var controller

    var body: some View {
        @Bindable var controller = controller
        Form {
            Section {
                Picker("Change wallpaper using", selection: $controller.settings.rotationSource) {
                    ForEach(RotationSource.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Paused", isOn: $controller.settings.isRotationPaused)
                    .disabled(controller.settings.rotationSource == .off)
                if let next = controller.nextRotationDate {
                    LabeledContent("Next change") {
                        Text(next, style: .relative)
                    }
                }
            } footer: {
                Text("Only one source changes the wallpaper automatically. Each keeps its own settings.")
                    .foregroundStyle(.secondary)
            }

            Section("Local Cycling") {
                IntervalPicker(title: "Change every", interval: $controller.settings.cycling.interval)
                Picker("Order", selection: $controller.settings.cycling.order) {
                    ForEach(CyclingOrder.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Change wallpaper when the app starts", isOn: $controller.settings.cycling.changeAtStartup)
                LabeledContent("Included wallpapers") {
                    Text("\(WallpaperPicker.candidates(in: controller.library).count) of \(controller.library.wallpapers.count)")
                }
                HStack {
                    Button("Include All") {
                        controller.setIncludedInCycling(true, ids: controller.library.wallpapers.map(\.id))
                    }
                    Button("Exclude All") {
                        controller.setIncludedInCycling(false, ids: controller.library.wallpapers.map(\.id))
                    }
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// A period chosen from presets, or a custom number of minutes.
struct IntervalPicker: View {
    let title: String
    @Binding var interval: TimeInterval

    var body: some View {
        Picker(title, selection: presetSelection) {
            ForEach(IntervalPreset.all, id: \.self) { Text(IntervalPreset.title(for: $0)).tag(Optional($0)) }
            Divider()
            Text("Custom").tag(TimeInterval?.none)
        }
        if !IntervalPreset.all.contains(interval) {
            Stepper(value: minutes, in: 1...(60 * 24 * 30)) {
                LabeledContent("Minutes") {
                    TextField("Minutes", value: minutes, format: .number)
                        .frame(width: 70)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private var presetSelection: Binding<TimeInterval?> {
        Binding(
            get: { IntervalPreset.all.contains(interval) ? interval : nil },
            set: { interval = $0 ?? interval + 60 })
    }

    private var minutes: Binding<Int> {
        Binding(
            get: { Int(interval / 60) },
            set: { interval = TimeInterval(max(1, $0) * 60) })
    }
}
