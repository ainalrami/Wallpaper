import SwiftUI
import WallpaperCore

/// Shown when the library is empty: on first launch, or after every wallpaper was deleted.
struct OnboardingView: View {
    @Environment(AppController.self) private var controller
    // `@State` is a macro in the macOS 27 SDK whose plugin ships only with Xcode, so State is stored directly.
    private let _includeSubfolders = State<Bool>(initialValue: true)
    private var includeSubfolders: Bool {
        get { _includeSubfolders.wrappedValue }
        nonmutating set { _includeSubfolders.wrappedValue = newValue }
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "photo.stack")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text(controller.library.sources.isEmpty ? "Choose Your Wallpapers" : "Your Wallpapers Are Gone")
                .font(.title2.bold())
            Text(controller.library.sources.isEmpty
                 ? "Pick a folder of wallpapers or individual images. New images added to the folder appear here automatically."
                 : "The images in your sources were deleted or moved. Pick a folder or images to continue.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            HStack(spacing: 12) {
                Button("Choose Folder…") { add(SourcePicker.chooseFolders(), includeSubfolders: includeSubfolders) }
                    .buttonStyle(.borderedProminent)
                Button("Choose Images…") { add(SourcePicker.chooseImages(), includeSubfolders: false) }
            }
            .controlSize(.large)
            Toggle("Include subfolders", isOn: _includeSubfolders.projectedValue)
                .toggleStyle(.checkbox)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func add(_ urls: [URL], includeSubfolders: Bool) {
        guard !urls.isEmpty else { return }
        Task { await controller.addSources(urls, includeSubfolders: includeSubfolders) }
    }
}
