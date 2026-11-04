#if os(macOS)
  import Foundation
  import Testing

  /// A recursive regression must fail in a child process, without taking down the test runner.
  @Suite(.serialized) struct DeepOutlineDiffTests {
    @Test(arguments: [false, true])
    func updatesDeepLoadedTreesWithoutExhaustingTheStack(optimized: Bool) throws {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: directory) }

      let fixture = directory.appendingPathComponent("DeepDiffProbe.swift")
      try Self.probe.write(to: fixture, atomically: true, encoding: .utf8)
      let executable = directory.appendingPathComponent("deep-diff-probe")
      let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      let core = root.appendingPathComponent("Sources/GMSnagNav/Core")
      let build = try run(
        "/usr/bin/xcrun",
        arguments: [
          "swiftc", "-swift-version", "6", optimized ? "-O" : "-Onone",
          "-whole-module-optimization", "-module-cache-path",
          directory.appendingPathComponent("module-cache").path,
          core.appendingPathComponent("OutlineTree.swift").path,
          core.appendingPathComponent("ExpansionChanges.swift").path,
          core.appendingPathComponent("OutlineDiff.swift").path,
          fixture.path, "-o", executable.path,
        ], directory: directory, name: "build")
      try #require(build.status == 0, "\(build.output)")

      let result = try run(executable.path, arguments: [], directory: directory, name: "probe")
      #expect(result.status == 0, "\(result.output)")
      #expect(result.output.contains("Completed deep diff checks"))
    }

    private func run(
      _ executable: String, arguments: [String], directory: URL, name: String
    ) throws -> (status: Int32, output: String) {
      let log = directory.appendingPathComponent("\(name).log")
      FileManager.default.createFile(atPath: log.path, contents: nil)
      let output = try FileHandle(forWritingTo: log)
      defer { try? output.close() }
      let process = Process()
      process.executableURL = URL(fileURLWithPath: executable)
      process.arguments = arguments
      process.standardOutput = output
      process.standardError = output
      try process.run()
      let deadline = Date().addingTimeInterval(30)
      while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
      let timedOut = process.isRunning
      if timedOut { process.terminate() }
      process.waitUntilExit()
      let diagnostic = try String(contentsOf: log, encoding: .utf8)
      return (
        process.terminationStatus,
        (timedOut ? "Timed out after 30 seconds.\n" : "") + String(diagnostic.suffix(4_000))
      )
    }

    private static let probe = """
      struct Item: Identifiable { let id: Int }

      @main struct DeepDiffProbe {
        static func main() {
          let count = 10_000
          let loaded = Set(0..<count)
          let flat = OutlineTree((0..<count).map(Item.init)) { _ in [Item]() }
          let deep = OutlineTree([Item(id: count - 1)]) { item in
            item.id > 0 ? [Item(id: item.id - 1)] : []
          }
          let nested = deep.changes(from: flat, loaded: loaded)
          precondition(nested.count == count * 2 - 1)
          precondition(deep.changes(from: deep, loaded: loaded).isEmpty)
          let trimmed = OutlineTree([Item(id: count - 1)]) { item in
            item.id > 1 ? [Item(id: item.id - 1)] : []
          }
          precondition(trimmed.changes(from: deep, loaded: loaded) == [
            .remove(parent: 1, index: 0), .reload(1)
          ])
          let empty = OutlineTree([Item]()) { _ in [Item]() }
          precondition(empty.changes(from: deep, loaded: loaded) == [
            .remove(parent: nil, index: 0)
          ])
          print("Completed deep diff checks")
        }
      }
      """
  }
#endif
