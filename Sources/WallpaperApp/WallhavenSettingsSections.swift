import SwiftUI
import WallpaperCore

/// The Wallhaven sections of the Rotation settings form.
struct WallhavenSettingsSections: View {
    @Environment(AppController.self) private var controller

    static let resolutionPresets: [Resolution] = [
        Resolution(width: 1280, height: 720), Resolution(width: 1600, height: 900),
        Resolution(width: 1920, height: 1080), Resolution(width: 2560, height: 1080),
        Resolution(width: 2560, height: 1440), Resolution(width: 3440, height: 1440),
        Resolution(width: 3840, height: 2160), Resolution(width: 5120, height: 2880),
    ]

    var body: some View {
        @Bindable var controller = controller
        Group {
            Section {
                TextField("Keywords", text: keywords, prompt: Text("nature, mountains, space"))
                resolutionPicker
                LabeledContent("Categories") {
                    HStack {
                        ForEach(WallhavenSettings.Category.allCases) { category in
                            Toggle(category.title, isOn: membership(category, in: \.categories))
                        }
                    }
                }
                LabeledContent("Purity") {
                    HStack {
                        ForEach(WallhavenSettings.Purity.allCases) { purity in
                            Toggle(purity.title, isOn: membership(purity, in: \.purity))
                                .disabled(purity.requiresAPIKey && controller.wallhavenAPIKey.isEmpty)
                        }
                    }
                }
                SecureField("API key", text: $controller.wallhavenAPIKey, prompt: Text("Optional"))
            } header: {
                SourceHeader(title: "Wallhaven", isActive: controller.settings.rotationSource == .wallhaven)
            } footer: {
                Text("Each change searches one keyword at random; leave keywords empty for any wallpaper. An API key from your Wallhaven account settings is needed only for NSFW results.")
                    .foregroundStyle(.secondary)
            }

            Section {
                IntervalPicker(title: "Change every", interval: $controller.settings.wallhaven.interval)
                Toggle("Change wallpaper when the app starts", isOn: $controller.settings.wallhaven.changeAtStartup)
                HStack {
                    Button("Fetch Now") {
                        Task { await controller.fetchFromWallhaven() }
                    }
                    .buttonStyle(.glass)
                    .disabled(controller.isFetchingWallhaven)
                    if controller.isFetchingWallhaven {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                    if controller.settings.rotationSource != .wallhaven {
                        Button("Use for Automatic Changes") {
                            controller.settings.rotationSource = .wallhaven
                        }
                        .buttonStyle(.glassProminent)
                    }
                }
            } header: {
                Text("Wallhaven Changes")
            } footer: {
                if controller.targetContext.isPerSpace {
                    Text("With a wallpaper for each Space, every change downloads one image per Space or group.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Wallhaven Downloads") {
                Picker("Mode", selection: $controller.settings.wallhaven.defaultMode) {
                    ForEach(ScalingMode.allCases) { Text($0.title).tag($0) }
                }
                if controller.settings.wallhaven.defaultMode.usesFillColor {
                    ColorPicker("Fill color", selection: Binding(
                        get: { controller.settings.wallhaven.defaultFillColor.color },
                        set: { controller.settings.wallhaven.defaultFillColor = RGBAColor($0) }),
                        supportsOpacity: false)
                }
                LabeledContent("Folder") {
                    HStack {
                        Text(controller.settings.wallhaven.downloadFolder.path(percentEncoded: false))
                            .lineLimit(1)
                            .truncationMode(.head)
                            .foregroundStyle(.secondary)
                        Button("Choose…") {
                            if let folder = SourcePicker.chooseFolders(allowsMultiple: false).first {
                                controller.settings.wallhaven.downloadFolderPath = folder.path
                            }
                        }
                        .buttonStyle(.glass)
                    }
                }
                Stepper(value: $controller.settings.wallhaven.retentionLimit, in: 1...1000) {
                    LabeledContent("Keep recent downloads", value: "\(controller.settings.wallhaven.retentionLimit)")
                }
                Text("Older downloads are deleted automatically unless you choose Keep for them in the library.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Comma-separated keywords, kept exactly as typed; blanks are ignored when searching.
    private var keywords: Binding<String> {
        Binding(
            get: { controller.settings.wallhaven.keywords.joined(separator: ",") },
            set: { controller.settings.wallhaven.keywords = $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init) })
    }

    @ViewBuilder private var resolutionPicker: some View {
        let current = controller.settings.wallhaven.minimumResolution
        let isCustom = current.map { !Self.resolutionPresets.contains($0) } ?? false
        Picker("Minimum resolution", selection: Binding<String>(
            get: { isCustom ? "custom" : current?.description ?? "any" },
            set: { tag in
                switch tag {
                case "any": controller.settings.wallhaven.minimumResolution = nil
                case "custom": controller.settings.wallhaven.minimumResolution = Resolution(width: 2000, height: 1000)
                default:
                    controller.settings.wallhaven.minimumResolution = Self.resolutionPresets.first { $0.description == tag }
                }
            })) {
            Text("Any").tag("any")
            ForEach(Self.resolutionPresets, id: \.self) { Text($0.description.replacingOccurrences(of: "x", with: " × ")).tag($0.description) }
            Divider()
            Text("Custom").tag("custom")
        }
        if isCustom, let current {
            LabeledContent("Custom size") {
                HStack {
                    TextField("Width", value: Binding(
                        get: { current.width },
                        set: { controller.settings.wallhaven.minimumResolution?.width = max(1, $0) }), format: .number)
                    Text("×")
                    TextField("Height", value: Binding(
                        get: { current.height },
                        set: { controller.settings.wallhaven.minimumResolution?.height = max(1, $0) }), format: .number)
                }
                .frame(width: 160)
            }
        }
    }

    private func membership<T: Hashable>(_ value: T, in keyPath: WritableKeyPath<WallhavenSettings, Set<T>>) -> Binding<Bool> {
        Binding(
            get: { controller.settings.wallhaven[keyPath: keyPath].contains(value) },
            set: { isOn in
                if isOn {
                    controller.settings.wallhaven[keyPath: keyPath].insert(value)
                } else {
                    controller.settings.wallhaven[keyPath: keyPath].remove(value)
                }
            })
    }
}
