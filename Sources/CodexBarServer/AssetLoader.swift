import Foundation

enum AssetLoader {
    static func loadStaticText(_ name: String) -> String? {
        // SwiftPM copies resources into the module bundle root by default.
        guard let url = Bundle.module.url(forResource: name, withExtension: nil) else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
