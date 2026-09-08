#!/usr/bin/env swift
import CryptoKit
import Foundation

// Independent verification against the public key shipped in Nook. No signing
// key is needed, so this can also verify assets downloaded from GitHub.
func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw NSError(domain: "NookRelease", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

do {
    let args = CommandLine.arguments
    try require(args.count == 5, "Usage: verify-appcast.swift APPCAST ZIP INFO_PLIST VERSION")
    let feed = try Data(contentsOf: URL(fileURLWithPath: args[1]))
    let archive = try Data(contentsOf: URL(fileURLWithPath: args[2]), options: .mappedIfSafe)
    let plistData = try Data(contentsOf: URL(fileURLWithPath: args[3]))
    let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
    guard let keyText = plist?["SUPublicEDKey"] as? String, let keyData = Data(base64Encoded: keyText) else {
        throw NSError(domain: "NookRelease", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing Ed25519 public key"])
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
    let marker = Data("<!-- sparkle-signatures:\n".utf8)
    guard let boundary = feed.range(of: marker, options: .backwards),
          let suffix = feed.range(of: Data("-->".utf8), in: boundary.upperBound..<feed.endIndex),
          let signatureBlock = String(data: feed[boundary.upperBound..<suffix.lowerBound], encoding: .utf8) else {
        throw NSError(domain: "NookRelease", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing signed feed block"])
    }
    let content = Data(feed[..<boundary.lowerBound])
    let fields = signatureBlock.split(separator: "\n").reduce(into: [String: String]()) { fields, line in
        let parts = line.split(separator: ":", maxSplits: 1)
        if parts.count == 2 { fields[String(parts[0])] = parts[1].trimmingCharacters(in: .whitespaces) }
    }
    guard let signature = fields["edSignature"].flatMap({ Data(base64Encoded: $0) }) else {
        throw NSError(domain: "NookRelease", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid feed signature"])
    }
    try require(Int(fields["length"] ?? "") == content.count, "Feed length mismatch")
    try require(key.isValidSignature(signature, for: content), "Feed signature mismatch")

    let doc = try XMLDocument(data: content, options: [])
    let items = try doc.nodes(forXPath: "/rss/channel/item")
    try require(items.count == 1, "Expected exactly one full update")
    guard let item = items.first as? XMLElement,
          let enclosure = item.elements(forName: "enclosure").first,
          let archiveSignature = enclosure.attribute(forName: "sparkle:edSignature")?.stringValue.flatMap({ Data(base64Encoded: $0) }) else {
        throw NSError(domain: "NookRelease", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing archive signature"])
    }
    let expectedURL = "https://github.com/eminuckan/Nook/releases/download/v\(args[4])/\(URL(fileURLWithPath: args[2]).lastPathComponent)"
    try require(enclosure.attribute(forName: "url")?.stringValue == expectedURL, "Unexpected update URL")
    try require(item.elements(forName: "sparkle:version").first?.stringValue == args[4], "Update build version mismatch")
    try require(item.elements(forName: "sparkle:shortVersionString").first?.stringValue == args[4], "Update display version mismatch")
    try require(Int(enclosure.attribute(forName: "length")?.stringValue ?? "") == archive.count, "Archive length mismatch")
    try require(key.isValidSignature(archiveSignature, for: archive), "Archive signature mismatch")

    // Prove rejection with the actual shipped signatures, independently of
    // archive length checks, for changed content and for a different signer.
    var changedContent = content
    changedContent[0] ^= 1
    var changedArchive = archive
    changedArchive[0] ^= 1
    try require(!key.isValidSignature(signature, for: changedContent), "Changed feed accepted")
    try require(!key.isValidSignature(archiveSignature, for: changedArchive), "Changed archive accepted")
    let wrongKey = Curve25519.Signing.PrivateKey().publicKey
    try require(!wrongKey.isValidSignature(signature, for: content), "Wrong feed signer accepted")
    try require(!wrongKey.isValidSignature(archiveSignature, for: archive), "Wrong archive signer accepted")
    print("Verified feed and archive against shipped public key; modified content and wrong signers rejected.")
} catch {
    fputs("Release verification failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
