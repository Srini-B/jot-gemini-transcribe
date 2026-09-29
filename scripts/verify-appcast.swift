// Checks that an appcast offers this build the way Sparkle on a user's Mac
// will read it: the newest item is the app's CFBundleVersion, its enclosure is
// the expected URL and size, and its EdDSA signature verifies under the
// SUPublicEDKey inside the app.
//
//   swift scripts/verify-appcast.swift <appcast.xml> <VoiceiQ.app> <archive> <enclosure-url>
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("error: \(message)\n".data(using: .utf8)!)
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 5 else {
    fail("usage: verify-appcast.swift <appcast.xml> <VoiceiQ.app> <archive> <enclosure-url>")
}
let (appcastPath, appPath, archivePath, expectedURL) = (arguments[1], arguments[2], arguments[3], arguments[4])

guard let info = NSDictionary(contentsOfFile: "\(appPath)/Contents/Info.plist"),
      let build = info["CFBundleVersion"] as? String,
      let shortVersion = info["CFBundleShortVersionString"] as? String,
      let publicKeyBase64 = info["SUPublicEDKey"] as? String,
      let publicKeyData = Data(base64Encoded: publicKeyBase64),
      let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData) else {
    fail("\(appPath) has no CFBundleVersion, CFBundleShortVersionString or valid SUPublicEDKey")
}

let document: XMLDocument
do {
    document = try XMLDocument(contentsOf: URL(fileURLWithPath: appcastPath))
} catch {
    fail("cannot parse \(appcastPath): \(error.localizedDescription)")
}

func text(_ node: XMLNode, _ name: String) -> String? {
    (try? node.nodes(forXPath: "*[local-name()='\(name)']"))?.first?.stringValue?
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

let items = (try? document.nodes(forXPath: "//channel/item")) ?? []
let builds = items.compactMap { text($0, "version") }.compactMap(Int.init)
guard let item = items.first(where: { text($0, "version") == build }) else {
    fail("the appcast has no item for build \(build)")
}
guard builds.max() == Int(build) else {
    fail("build \(build) is not the newest in the appcast (\(builds.sorted()))")
}
guard text(item, "shortVersionString") == shortVersion else {
    fail("item \(build) shows version \(text(item, "shortVersionString") ?? "none"), the app is \(shortVersion)")
}
guard let enclosure = (try? item.nodes(forXPath: "enclosure"))?.first as? XMLElement,
      let url = enclosure.attribute(forName: "url")?.stringValue,
      let length = enclosure.attribute(forName: "length")?.stringValue,
      let signatureBase64 = enclosure.attribute(forName: "sparkle:edSignature")?.stringValue,
      let signature = Data(base64Encoded: signatureBase64) else {
    fail("item \(build) has no enclosure with url, length and sparkle:edSignature")
}
guard url == expectedURL else {
    fail("enclosure URL is \(url), expected \(expectedURL)")
}
guard let archive = FileManager.default.contents(atPath: archivePath) else {
    fail("cannot read \(archivePath)")
}
guard length == String(archive.count) else {
    fail("enclosure length \(length) does not match the archive (\(archive.count) bytes)")
}
guard publicKey.isValidSignature(signature, for: archive) else {
    fail("the archive's EdDSA signature does not verify under the app's SUPublicEDKey")
}
print("✓ appcast offers \(shortVersion) (\(build)) from \(url), signature verified")
