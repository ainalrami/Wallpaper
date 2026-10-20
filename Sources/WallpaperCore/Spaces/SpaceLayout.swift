import Foundation

/// A desktop Space (Mission Control's "Desktop N"). Full-screen app Spaces aren't included.
public struct DesktopSpace: Identifiable, Hashable, Sendable {
    /// The Space's UUID, which stays the same when Spaces are reordered.
    public var id: String
    /// Position among the desktops of its display, starting at 1.
    public var number: Int
    /// The display the Space belongs to. `nil` when Spaces span all displays.
    public var displayID: String?
    public var isCurrent: Bool

    public init(id: String, number: Int, displayID: String?, isCurrent: Bool) {
        self.id = id
        self.number = number
        self.displayID = displayID
        self.isCurrent = isCurrent
    }

    public var title: String { "Desktop \(number)" }
}

/// The desktops of every display, as reported by the window server.
public struct SpaceLayout: Equatable, Sendable {
    public var spaces: [DesktopSpace]
    /// `true` when "Displays have separate Spaces" is off, so every Space covers all displays.
    public var spansDisplays: Bool

    public init(spaces: [DesktopSpace], spansDisplays: Bool) {
        self.spaces = spaces
        self.spansDisplays = spansDisplays
    }

    /// Parses the result of `CGSCopyManagedDisplaySpaces`. Returns `nil` if it has no desktops.
    public init?(managedDisplaySpaces: [[String: Any]]) {
        var spaces: [DesktopSpace] = []
        var spansDisplays = false
        for display in managedDisplaySpaces {
            guard let identifier = display["Display Identifier"] as? String,
                  let list = display["Spaces"] as? [[String: Any]] else { continue }
            // With one set of Spaces for all displays, the identifier is "Main" rather than a display UUID.
            let displayID: String? = identifier == "Main" ? nil : identifier
            if displayID == nil {
                spansDisplays = true
            }
            let current = (display["Current Space"] as? [String: Any]).flatMap(Self.spaceID(of:))
            var number = 0
            for space in list where (space["type"] as? Int ?? 0) == Self.desktopType {
                guard let id = Self.spaceID(of: space) else { continue }
                number += 1
                spaces.append(DesktopSpace(id: id, number: number, displayID: displayID, isCurrent: id == current))
            }
        }
        guard !spaces.isEmpty else { return nil }
        self.init(spaces: spaces, spansDisplays: spansDisplays)
    }

    /// The desktops shown on `displayID`.
    public func spaces(on displayID: String) -> [DesktopSpace] {
        spansDisplays ? spaces : spaces.filter { $0.displayID == displayID }
    }

    public func currentSpace(on displayID: String) -> DesktopSpace? {
        spaces(on: displayID).first(where: \.isCurrent)
    }

    public func space(id: DesktopSpace.ID) -> DesktopSpace? {
        spaces.first { $0.id == id }
    }

    /// `type` of a regular desktop; full-screen app Spaces use other values.
    static let desktopType = 0

    /// The UUID, or the managed ID for Spaces that report an empty UUID (older macOS does this
    /// for the first desktop).
    static func spaceID(of space: [String: Any]) -> String? {
        if let uuid = space["uuid"] as? String, !uuid.isEmpty {
            return uuid
        }
        return (space["ManagedSpaceID"] as? Int).map { "managed-\($0)" }
    }
}
