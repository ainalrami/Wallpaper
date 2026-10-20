import SwiftUI
import WallpaperCore

/// Automatic changes: the active source, local cycling, and Wallhaven, in one form.
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

            Section {
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
                    if controller.settings.rotationSource != .local {
                        Button("Use for Automatic Changes") {
                            controller.settings.rotationSource = .local
                        }
                    }
                }
            } header: {
                SourceHeader(title: "Local Cycling", isActive: controller.settings.rotationSource == .local)
            }

            WallhavenSettingsSections()
        }
        .formStyle(.grouped)
    }
}

/// A section title with an "Active" tag for the source that changes the wallpaper.
struct SourceHeader: View {
    let title: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            if isActive {
                Text("Active")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .foregroundStyle(.white)
                    .background(Color.accentColor, in: Capsule())
            }
        }
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
