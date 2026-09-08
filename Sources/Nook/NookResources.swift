import Foundation

/// SwiftPM's generated Bundle.module accessor for executables searches next to
/// the executable bundle, then the build machine. A distributed macOS app keeps
/// its copied resource bundle inside Contents/Resources instead.
enum NookResources {
    static func url(forResource name: String, withExtension ext: String) -> URL? {
        if Bundle.main.bundleURL.pathExtension == "app" {
            return packagedURL(forResource: name, withExtension: ext, resourceDirectory: Bundle.main.resourceURL)
        }
        return Bundle.module.url(forResource: name, withExtension: ext)
    }

    static func packagedURL(forResource name: String, withExtension ext: String, resourceDirectory: URL?) -> URL? {
        guard let resourceDirectory else { return nil }
        let url = resourceDirectory.appendingPathComponent("Nook_Nook.bundle", isDirectory: true)
            .appendingPathComponent(name).appendingPathExtension(ext)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
