#!/usr/bin/swift
// generate_keys.swift
//
// One-time key generation for signed auto-updates.
// Generates a Curve25519 (EdDSA) signing key pair using CryptoKit.
//
//   - The private key (base64) is written to scripts/private_key.txt.
//     This file is git-ignored and MUST NEVER be committed or shared.
//     It is the only thing that can sign a release the app will accept.
//   - The public key (base64) is printed to stdout. Paste it into
//     UpdateChecker.swift as the `publicKeyBase64` constant so the app
//     can verify downloads against it.
//
// Usage:  swift scripts/generate_keys.swift
//
// Re-running this OVERWRITES the private key and invalidates every
// previously signed release, so only run it once.

import Foundation
import CryptoKit

let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let privateKeyURL = scriptDir.appendingPathComponent("private_key.txt")

if FileManager.default.fileExists(atPath: privateKeyURL.path) {
    FileHandle.standardError.write(Data("""
    Refusing to overwrite existing private key at:
      \(privateKeyURL.path)
    Delete it manually first if you really intend to rotate the key.

    """.utf8))
    exit(1)
}

let privateKey = Curve25519.Signing.PrivateKey()
let publicKey = privateKey.publicKey

let privateB64 = privateKey.rawRepresentation.base64EncodedString()
let publicB64 = publicKey.rawRepresentation.base64EncodedString()

// Write the private key with owner-only permissions (0600).
try privateB64.write(to: privateKeyURL, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: privateKeyURL.path)

print("""
Key pair generated.

Private key written to (git-ignored, keep secret):
  \(privateKeyURL.path)

Public key (paste into UpdateChecker.swift as publicKeyBase64):
  \(publicB64)
""")
