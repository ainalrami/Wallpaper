import Foundation

extension KeyedDecodingContainer {
    /// Decodes a value, or returns `defaultValue` if the key is missing or null.
    /// Lets saved files written by older versions load after fields are added.
    func decode<T: Decodable>(_ type: T.Type, forKey key: Key, default defaultValue: T) throws -> T {
        try decodeIfPresent(type, forKey: key) ?? defaultValue
    }
}
