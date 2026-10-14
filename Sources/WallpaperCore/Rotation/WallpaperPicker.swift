import Foundation

/// Chooses the next wallpaper for local cycling.
public enum WallpaperPicker {
    public struct Pick: Equatable, Sendable {
        public var wallpaperID: Wallpaper.ID
        /// The updated random-cycle history to save.
        public var history: [Wallpaper.ID]
    }

    /// Wallpapers that local cycling can show: included local images, plus Wallhaven downloads
    /// the user chose to keep.
    public static func candidates(in library: LibraryState) -> [Wallpaper] {
        library.wallpapers.filter { $0.includedInCycling && (!$0.isWallhaven || $0.isKept) }
    }

    /// - Parameters:
    ///   - current: the wallpaper shown now; it isn't picked again unless it is the only candidate.
    ///   - avoiding: wallpapers to skip when possible, e.g. those already shown on other displays.
    ///   - history: wallpapers already shown in the current random cycle.
    public static func next<R: RandomNumberGenerator>(
        from candidates: [Wallpaper],
        order: CyclingOrder,
        current: Wallpaper.ID?,
        avoiding: Set<Wallpaper.ID> = [],
        history: [Wallpaper.ID],
        using generator: inout R
    ) -> Pick? {
        guard !candidates.isEmpty else { return nil }

        switch order {
        case .sequential:
            let sorted = candidates.sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
            let start = current.flatMap { id in sorted.firstIndex { $0.id == id } }.map { $0 + 1 } ?? 0
            // Walk forward from the current wallpaper, wrapping around, skipping avoided ones if possible.
            let ordered = (0..<sorted.count).map { sorted[(start + $0) % sorted.count] }
            let pick = ordered.first { !avoiding.contains($0.id) && $0.id != current } ?? ordered[0]
            return Pick(wallpaperID: pick.id, history: history)

        case .random:
            let ids = Set(candidates.map(\.id))
            var history = history.filter(ids.contains)
            var pool = candidates.filter { !history.contains($0.id) && $0.id != current }
            if pool.isEmpty {
                // Every wallpaper has been shown: start a new cycle.
                history = []
                pool = candidates.filter { $0.id != current }
                if pool.isEmpty { pool = candidates }
            }
            let preferred = pool.filter { !avoiding.contains($0.id) }
            let choice = (preferred.isEmpty ? pool : preferred).randomElement(using: &generator)!
            history.append(choice.id)
            return Pick(wallpaperID: choice.id, history: history)
        }
    }
}
