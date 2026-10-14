import SwiftUI
import WallpaperCore

struct WallpaperInspector: View {
    @Environment(AppController.self) private var controller
    let wallpaper: Wallpaper
    // `@State` is a macro in the macOS 27 SDK whose plugin ships only with Xcode, so State is stored directly.
    private let _previewDisplayID = State<Display.ID?>(initialValue: nil)
    private var previewDisplayID: Display.ID? {
        get { _previewDisplayID.wrappedValue }
        nonmutating set { _previewDisplayID.wrappedValue = newValue }
    }
    private let _imageSize = State<CGSize?>(initialValue: nil)
    private var imageSize: CGSize? {
        get { _imageSize.wrappedValue }
        nonmutating set { _imageSize.wrappedValue = newValue }
    }

    var body: some View {
        Form {
            Section {
                ModePreview(wallpaper: wallpaper, display: previewDisplay, imageSize: imageSize)
                if controller.displays.count > 1 {
                    Picker("Preview on", selection: _previewDisplayID.projectedValue) {
                        ForEach(controller.displays) { display in
                            Text(display.name).tag(Optional(display.id))
                        }
                    }
                }
            }

            Section("Placement") {
                Picker("Mode", selection: binding(\.mode)) {
                    ForEach(ScalingMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage).tag(mode)
                    }
                }
                if wallpaper.mode.usesFillColor {
                    ColorPicker("Fill color", selection: Binding(
                        get: { wallpaper.fillColor.color },
                        set: { color in controller.updateWallpaper(id: wallpaper.id) { $0.fillColor = RGBAColor(color) } }),
                        supportsOpacity: false)
                }
                Toggle("Include in cycling", isOn: binding(\.includedInCycling))
            }

            Section {
                setButton
            }

            Section("Info") {
                LabeledContent("Name", value: wallpaper.fileName)
                if let imageSize {
                    LabeledContent("Size", value: "\(Int(imageSize.width)) × \(Int(imageSize.height))")
                }
                LabeledContent("Added", value: wallpaper.dateAdded.formatted(date: .abbreviated, time: .shortened))
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([wallpaper.url]) }
            }
        }
        .formStyle(.grouped)
        .task(id: wallpaper.path) {
            let path = wallpaper.path
            imageSize = await Task.detached { ImageInfo.pixelSize(of: URL(fileURLWithPath: path)) }.value
        }
    }

    private var previewDisplay: Display? {
        controller.displays.first { $0.id == previewDisplayID }
            ?? controller.displays.first(where: \.isMain)
            ?? controller.displays.first
    }

    @ViewBuilder private var setButton: some View {
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
                .buttonStyle(.borderedProminent)
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<Wallpaper, Value>) -> Binding<Value> {
        Binding(
            get: { wallpaper[keyPath: keyPath] },
            set: { value in controller.updateWallpaper(id: wallpaper.id) { $0[keyPath: keyPath] = value } })
    }
}

/// Shows how the wallpaper looks on a display with its current mode.
struct ModePreview: View {
    let wallpaper: Wallpaper
    let display: Display?
    let imageSize: CGSize?

    // `@State` is a macro in the macOS 27 SDK whose plugin ships only with Xcode, so State is stored directly.
    private let _image = State<NSImage?>(initialValue: nil)
    private var image: NSImage? {
        get { _image.wrappedValue }
        nonmutating set { _image.wrappedValue = newValue }
    }

    var body: some View {
        let aspectRatio = display?.aspectRatio ?? 16 / 10
        Canvas { context, size in
            let canvas = CGRect(origin: .zero, size: size)
            let background = wallpaper.mode.usesFillColor ? wallpaper.fillColor.color : .black
            context.fill(Path(canvas), with: .color(background))
            guard let image, let imageSize else { return }

            let displaySize = CGSize(width: display?.pixelWidth ?? 2880, height: display?.pixelHeight ?? 1800)
            let resolved = context.resolve(Image(nsImage: image))
            context.clip(to: Path(canvas))
            for rect in WallpaperLayout.imageRects(
                mode: wallpaper.mode, imageSize: imageSize, canvas: canvas, displayPixelSize: displaySize) {
                context.draw(resolved, in: rect)
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
        .task(id: wallpaper.path) {
            image = await ThumbnailCache.shared.image(for: wallpaper.path, maxPixelSize: 1400)
        }
    }
}
