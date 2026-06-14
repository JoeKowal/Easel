//
//  QuickSitesPublisher.swift
//  Easel
//

import Foundation

protocol QuickSitesPublishing {
  func publish(
    projectDirectory: String,
    site: String?,
    metadata: QuickSitesPublishMetadata
  ) async throws -> QuickSitesPublishResult
}

struct QuickSitesPublishResult: Decodable, Equatable {
  let status: String
  let site: String
  let serviceUrl: URL
  let compatibilityUrl: URL
  let output: String
  let proofPack: String?
  let closeout: QuickSitesCloseoutResult?

  enum CodingKeys: String, CodingKey {
    case status
    case site
    case serviceUrl
    case compatibilityUrl
    case output
    case proofPack
    case closeout
  }
}

struct QuickSitesCloseoutResult: Decodable, Equatable {
  let packet: String?
  let closeout: String?
}

struct QuickSitesPublishMetadata: Equatable {
  var title: String
  var description: String
  var tags: [String]
  var owner: String
  var purpose: String
  var audience: String
  var sensitivity: String
  var lifecycleStatus: String
  var template: String
  var shareNotes: String
}

enum QuickSitesPublisherError: LocalizedError, Equatable {
  case jkNotFound(String)
  case commandFailed(status: Int32, message: String)
  case invalidOutput(String)

  var errorDescription: String? {
    switch self {
    case .jkNotFound(let path):
      return "Quick Sites CLI was not found at \(path)."
    case .commandFailed(_, let message):
      return message.isEmpty ? "Quick Sites publish failed." : message
    case .invalidOutput(let output):
      return "Quick Sites returned invalid output: \(output)"
    }
  }
}

struct DefaultQuickSitesPublisher: QuickSitesPublishing {
  var jkPath = "/Users/jk/bin/jk"

  func publish(
    projectDirectory: String,
    site: String? = nil,
    metadata: QuickSitesPublishMetadata
  ) async throws -> QuickSitesPublishResult {
    guard FileManager.default.isExecutableFile(atPath: jkPath) else {
      throw QuickSitesPublisherError.jkNotFound(jkPath)
    }

    var arguments = ["quick", "easel-publish", projectDirectory]
    if let site, !site.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      arguments.append(site)
    }
    arguments.append(contentsOf: [
      "--title", metadata.title,
      "--description", metadata.description,
      "--owner", metadata.owner,
      "--purpose", metadata.purpose,
      "--audience", metadata.audience,
      "--sensitivity", metadata.sensitivity,
      "--status", metadata.lifecycleStatus,
      "--template", metadata.template,
      "--share-notes", metadata.shareNotes,
    ])
    for tag in metadata.tags where !tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      arguments.append(contentsOf: ["--tag", tag])
    }
    arguments.append("--json")

    let output = try await runProcess(
      executableURL: URL(fileURLWithPath: jkPath),
      arguments: arguments,
      workingDirectory: URL(fileURLWithPath: projectDirectory, isDirectory: true)
    )

    guard output.status == 0 else {
      throw QuickSitesPublisherError.commandFailed(
        status: output.status,
        message: output.errorText
      )
    }

    do {
      return try JSONDecoder().decode(QuickSitesPublishResult.self, from: output.outputData)
    } catch {
      let text = String(data: output.outputData, encoding: .utf8) ?? ""
      throw QuickSitesPublisherError.invalidOutput(text)
    }
  }

  private func runProcess(
    executableURL: URL,
    arguments: [String],
    workingDirectory: URL
  ) async throws -> QuickSitesProcessOutput {
    try await withCheckedThrowingContinuation { continuation in
      let process = Process()
      let outputPipe = Pipe()
      let errorPipe = Pipe()

      process.executableURL = executableURL
      process.arguments = arguments
      process.environment = Self.processEnvironment(for: executableURL)
      process.currentDirectoryURL = workingDirectory
      process.standardOutput = outputPipe
      process.standardError = errorPipe
      process.terminationHandler = { terminatedProcess in
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        continuation.resume(returning: QuickSitesProcessOutput(
          status: terminatedProcess.terminationStatus,
          outputData: outputData,
          errorData: errorData
        ))
      }

      do {
        try process.run()
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }

  private static func processEnvironment(
    for executableURL: URL,
    baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
  ) -> [String: String] {
    var environment = baseEnvironment
    let executableDirectoryPath = executableURL.deletingLastPathComponent().path
    let defaultPaths = ["/Users/jk/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
    let currentPath = baseEnvironment["PATH"] ?? ""
    let pathParts = ([executableDirectoryPath] + defaultPaths + currentPath.split(separator: ":").map(String.init))
      .filter { !$0.isEmpty }

    var seenPaths: Set<String> = []
    environment["PATH"] = pathParts.filter { path in
      guard !seenPaths.contains(path) else { return false }
      seenPaths.insert(path)
      return true
    }.joined(separator: ":")

    return environment
  }
}

extension DefaultQuickSitesPublisher {
  static func suggestedSiteSlug(for projectDirectory: String) -> String {
    let name = URL(fileURLWithPath: projectDirectory, isDirectory: true).lastPathComponent
    let lowered = name.lowercased()
    var slug = ""
    var previousWasSeparator = false

    for scalar in lowered.unicodeScalars {
      if CharacterSet.alphanumerics.contains(scalar) {
        slug.unicodeScalars.append(scalar)
        previousWasSeparator = false
      } else if !previousWasSeparator {
        slug.append("-")
        previousWasSeparator = true
      }
    }

    let trimmed = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    if trimmed.hasPrefix("quick-") {
      return trimmed
    }
    return "quick-easel-\(trimmed.isEmpty ? "project" : trimmed)"
  }

  static func suggestedMetadata(
    projectName: String,
    projectDirectory: String,
    projectKind: String
  ) -> QuickSitesPublishMetadata {
    let slug = suggestedSiteSlug(for: projectDirectory)
    return QuickSitesPublishMetadata(
      title: projectName.isEmpty ? URL(fileURLWithPath: projectDirectory).lastPathComponent : projectName,
      description: "Dogfood import from an Easel-authored \(projectKind) project.",
      tags: ["easel", "dogfood", "playground", projectKind],
      owner: "Codex",
      purpose: "Easel-authored Quick Sites experiment for rapid internal review and proof capture.",
      audience: "Joe and Codex operators",
      sensitivity: "internal",
      lifecycleStatus: "watch",
      template: "easel-\(projectKind)",
      shareNotes: "Published from Easel through jk quick easel-publish as \(slug)."
    )
  }
}

private struct QuickSitesProcessOutput {
  let status: Int32
  let outputData: Data
  let errorData: Data

  var errorText: String {
    let text = String(data: errorData, encoding: .utf8)
      ?? String(data: outputData, encoding: .utf8)
      ?? "Quick Sites publish failed."
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
