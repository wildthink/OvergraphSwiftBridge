import ArgumentParser
import Foundation
import OvergraphSwiftBridge

@main
struct OvergraphCLI: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "overgraph-cli",
    abstract: "Interactive REPL for an Overgraph database."
  )

  @Option(name: .shortAndLong, help: "Path to the database directory.")
  var db: String

  @Flag(help: "Do not create the database directory automatically.")
  var noCreateIfMissing = false

  @Option(help: "Run one command and exit instead of starting the interactive REPL.")
  var execute: String?

  @Option(help: "Run commands from a script file and exit.")
  var runScript: String?

  mutating func run() throws {
    let database = try OvergraphDatabase(
      path: db,
      options: DatabaseOptions(createIfMissing: !noCreateIfMissing)
    )
    defer { try? database.close() }

    let repl = DatabaseREPL(database: database)
    if let execute {
      _ = try repl.execute(line: execute)
      return
    }
    if let runScript {
      try ScriptRunner().runScript(atPath: runScript) { line in
        try repl.execute(line: line) != .exit
      }
      return
    }

    print("Connected to \(db)")
    print("Type 'help' for commands. Type 'exit' or 'quit' to leave.")
    while let line = repl.readLine(prompt: "overgraph> ") {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty { continue }
      do {
        if try repl.execute(line: trimmed) == .exit {
          break
        }
      } catch {
        fputs("error: \(error)\n", stderr)
      }
    }
  }
}
