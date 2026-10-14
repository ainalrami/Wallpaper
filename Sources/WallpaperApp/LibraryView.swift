import SwiftUI
import WallpaperCore

enum SidebarItem: Hashable {
    case all
    case wallhaven
    case source(LibrarySource.ID)
}

struct LibraryView: View {
    @Environment(AppController.self) private var controller
    // `@State` is a macro in the macOS 27 SDK whose plugin ships only with Xcode, so State is stored directly.
    private let _sidebarSelection = State<SidebarItem?>(initialValue: .all)
    private var sidebarSelection: SidebarItem? {
        get { _sidebarSelection.wrappedValue }
        nonmutating set { _sidebarSelection.wrappedValue = newValue }
    }
    private let _selectedWallpaperID = State<Wallpaper.ID?>(initialValue: nil)
    private var selectedWallpaperID: Wallpaper.ID? {
        get { _selectedWallpaperID.wrappedValue }
        nonmutating set { _selectedWallpaperID.wrappedValue = newValue }
    }
    private let _showsInspector = State<Bool>(initialValue: true)
    private var showsInspector: Bool {
        get { _showsInspector.wrappedValue }
        nonmutating set { _showsInspector.wrappedValue = newValue }
    }

    var body: some View {
        NavigationSplitView {
            LibrarySidebar(selection: _sidebarSelection.projectedValue)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } detail: {
            if controller.needsOnboarding {
                OnboardingView()
            } else {
                WallpaperGrid(wallpapers: visibleWallpapers, selection: _selectedWallpaperID.projectedValue)
                    .inspector(isPresented: _showsInspector.projectedValue) {
                        Group {
                            if let id = selectedWallpaperID, let wallpaper = controller.library.wallpaper(id: id) {
                                WallpaperInspector(wallpaper: wallpaper)
                            } else {
                                ContentUnavailableView("No Selection", systemImage: "photo",
                                                       description: Text("Select a wallpaper to see its settings."))
                            }
                        }
                        .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
                    }
                    .toolbar {
                        ToolbarItem {
                            Button {
                                showsInspector.toggle()
                            } label: {
                                Label("Inspector", systemImage: "sidebar.trailing")
                            }
                        }
                    }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let message = controller.statusMessage {
                StatusBanner(message: message) { controller.statusMessage = nil }
            }
        }
        .frame(minWidth: 760, minHeight: 480)
    }

    private var visibleWallpapers: [Wallpaper] {
        let wallpapers: [Wallpaper]
        switch sidebarSelection {
        case .all, nil:
            wallpapers = controller.library.wallpapers
        case .wallhaven:
            wallpapers = controller.library.wallpapers.filter(\.isWallhaven)
        case .source(let id):
            wallpapers = controller.library.sources.first { $0.id == id }
                .map(controller.library.wallpapers(in:)) ?? []
        }
        return wallpapers.sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
    }
}

struct StatusBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text(message).lineLimit(2)
            Spacer()
            Button("Dismiss", action: dismiss)
        }
        .padding(10)
        .background(.bar)
    }
}

struct LibrarySidebar: View {
    @Environment(AppController.self) private var controller
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Label("All Wallpapers", systemImage: "photo.on.rectangle")
                .badge(controller.library.wallpapers.count)
                .tag(SidebarItem.all)
            if controller.library.wallpapers.contains(where: \.isWallhaven) {
                Label("Wallhaven", systemImage: "globe")
                    .tag(SidebarItem.wallhaven)
            }
            Section("Sources") {
                ForEach(controller.library.sources) { source in
                    SourceRow(source: source)
                        .tag(SidebarItem.source(source.id))
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                AddSourceMenu()
                Spacer()
            }
            .padding(8)
        }
    }
}

struct AddSourceMenu: View {
    @Environment(AppController.self) private var controller

    var body: some View {
        Menu {
            Button("Add Folder…") { add(SourcePicker.chooseFolders()) }
            Button("Add Folder with Subfolders…") { add(SourcePicker.chooseFolders(), includeSubfolders: true) }
            Button("Add Images…") { add(SourcePicker.chooseImages()) }
        } label: {
            Label("Add Source", systemImage: "plus")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func add(_ urls: [URL], includeSubfolders: Bool = false) {
        guard !urls.isEmpty else { return }
        Task { await controller.addSources(urls, includeSubfolders: includeSubfolders) }
    }
}

struct SourceRow: View {
    @Environment(AppController.self) private var controller
    let source: LibrarySource

    var body: some View {
        Label(source.displayName, systemImage: source.kind == .folder ? "folder" : "photo")
            .badge(controller.library.wallpapers(in: source).count)
            .help(source.path)
            .contextMenu {
                if source.kind == .folder {
                    Toggle("Include Subfolders", isOn: Binding(
                        get: { source.includeSubfolders },
                        set: { value in Task { await controller.setIncludeSubfolders(value, for: source.id) } }))
                }
                Button("Include All in Cycling") { setCycling(true) }
                Button("Exclude All from Cycling") { setCycling(false) }
                Divider()
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([source.url]) }
                Button("Remove Source", role: .destructive) {
                    Task { await controller.removeSource(id: source.id) }
                }
            }
    }

    private func setCycling(_ included: Bool) {
        controller.setIncludedInCycling(included, ids: controller.library.wallpapers(in: source).map(\.id))
    }
}
