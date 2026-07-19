#!/usr/bin/swift
// sign_release.swift
//
// Signs a release archive with the update-signing private key.
//
// Reads the base64 private key from scripts/private_key.txt, signs the raw
// bytes of the given .zip using Curve25519 (EdDSA), and writes the base64
// signature to <zip>.sig next to it. The app verifies this signature against
// the embedded public key before unpacking any downloaded update.
//
// Usage:  swift scripts/sign_release.swift path/to/PerformanceApp.zip

import Foundation
import CryptoKit

let args = CommandLine.arguments
guard args.count == 2 else {
    FileHandle.standardError.write(Data("Usage: swift sign_release.swift <path-to-zip>\n".utf8))
    exit(1)
}

let zipURL = URL(fileURLWithPath: args[1])
let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let privateKeyURL = scriptDir.appendingPathComponent("private_key.txt")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

guard FileManager.default.fileExists(atPath: privateKeyURL.path) else {
    fail("Private key not found at \(privateKeyURL.path). Run generate_keys.swift first.")
}
guard FileManager.default.fileExists(atPath: zipURL.path) else {
    fail("Archive not found: \(zipURL.path)")
}

let privateB64 = try String(contentsOf: privateKeyURL, encoding: .utf8)
    .trimmingCharacters(in: .whitespacesAndNewlines)
guard let privateData = Data(base64Encoded: privateB64) else {
    fail("Private key file is not valid base64.")
}

let privateKey: Curve25519.Signing.PrivateKey
do {
    privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateData)
} catch {
    fail("Could not load private key: \(error)")
}

let zipData = try Data(contentsOf: zipURL)
let signature = try privateKey.signature(for: zipData)

let sigURL = zipURL.appendingPathExtension("sig")
try signature.base64EncodedString().write(to: sigURL, atomically: true, encoding: .utf8)

print("Signed \(zipURL.lastPathComponent) -> \(sigURL.lastPathComponent)")
