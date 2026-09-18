import Foundation

/// Loads test fixtures bundled with OpenBoardTests (synthetic data mirroring the
/// real API shape, and saved US Chess pages).

func fixture(_ name: String) throws -> Data {
    let bundle = Bundle(for: BundleToken.self)
    guard let url = bundle.url(forResource: name, withExtension: "json") else {
        throw NSError(domain: "fixture", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "missing fixture \(name)"])
    }
    return try Data(contentsOf: url)
}

final class BundleToken {}

func fixtureText(_ name: String, _ ext: String) throws -> String {
    let bundle = Bundle(for: BundleToken.self)
    guard let url = bundle.url(forResource: name, withExtension: ext) else {
        throw NSError(domain: "fixture", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "missing fixture \(name).\(ext)"])
    }
    return try String(contentsOf: url, encoding: .utf8)
}
