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
      try repl.runScript(atPath: runScript)
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

private struct DatabaseREPL {
  enum Result {
    case `continue`
    case exit
  }

  let database: OvergraphDatabase
  private let encoder: JSONEncoder

  init(database: OvergraphDatabase) {
    self.database = database
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    self.encoder = encoder
  }

  func readLine(prompt: String) -> String? {
    print(prompt, terminator: "")
    fflush(stdout)
    return Swift.readLine()
  }

  func execute(line: String) throws -> Result {
    let tokens = try tokenize(line)
    guard let command = tokens.first else { return .continue }
    switch command {
    case "help":
      printHelp()
    case "exit", "quit":
      return .exit
    case "stats":
      try printJSON(database.stats())
    case "get-node":
      guard tokens.count == 2 else { throw CLIError.usage("get-node <id>") }
      try printJSON(database.getNode(id: try parseUInt64(tokens[1], name: "id")))
    case "get-edge":
      guard tokens.count == 2 else { throw CLIError.usage("get-edge <id>") }
      try printJSON(database.getEdge(id: try parseUInt64(tokens[1], name: "id")))
    case "get-node-by-key":
      guard tokens.count == 3 else { throw CLIError.usage("get-node-by-key <type-id> <key>") }
      try printJSON(database.getNodeByKey(typeID: try parseUInt32(tokens[1], name: "type-id"), key: tokens[2]))
    case "nodes-by-type":
      guard tokens.count == 2 else { throw CLIError.usage("nodes-by-type <type-id>") }
      try printJSON(database.getNodesByType(typeID: try parseUInt32(tokens[1], name: "type-id")))
    case "neighbors":
      try runNeighbors(tokens: Array(tokens.dropFirst()))
    case "upsert-node":
      try runUpsertNode(tokens: Array(tokens.dropFirst()))
    case "upsert-edge":
      try runUpsertEdge(tokens: Array(tokens.dropFirst()))
    case "delete-node":
      guard tokens.count == 2 else { throw CLIError.usage("delete-node <id>") }
      try database.deleteNode(id: try parseUInt64(tokens[1], name: "id"))
      print("ok")
    case "delete-edge":
      guard tokens.count == 2 else { throw CLIError.usage("delete-edge <id>") }
      try database.deleteEdge(id: try parseUInt64(tokens[1], name: "id"))
      print("ok")
    default:
      throw CLIError.usage("Unknown command '\(command)'. Type 'help'.")
    }
    return .continue
  }

  func runScript(atPath path: String) throws {
    let source = try String(contentsOfFile: path, encoding: .utf8)
    let stripped = stripComments(from: source)
    for rawLine in stripped.split(whereSeparator: \.isNewline) {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      if line.isEmpty { continue }
      if try execute(line: line) == .exit {
        return
      }
    }
  }

  private func runNeighbors(tokens: [String]) throws {
    guard let first = tokens.first else {
      throw CLIError.usage("neighbors <node-id> [--direction outgoing|incoming|both] [--limit N] [--types 10,11]")
    }
    let nodeID = try parseUInt64(first, name: "node-id")
    var direction: Direction = .outgoing
    var limit: Int?
    var types: [UInt32]?

    var index = 1
    while index < tokens.count {
      switch tokens[index] {
      case "--direction":
        index += 1
        guard index < tokens.count, let parsed = Direction(rawValue: tokens[index]) else {
          throw CLIError.usage("Expected outgoing, incoming, or both after --direction")
        }
        direction = parsed
      case "--limit":
        index += 1
        guard index < tokens.count, let parsed = Int(tokens[index]) else {
          throw CLIError.usage("Expected integer after --limit")
        }
        limit = parsed
      case "--types":
        index += 1
        guard index < tokens.count else {
          throw CLIError.usage("Expected comma-separated list after --types")
        }
        types = try tokens[index]
          .split(separator: ",")
          .map { part in
            guard let value = UInt32(part) else {
              throw CLIError.usage("Invalid edge type '\(part)'")
            }
            return value
          }
      default:
        throw CLIError.usage("Unknown neighbors option '\(tokens[index])'")
      }
      index += 1
    }

    try printJSON(
      database.neighbors(
        of: nodeID,
        options: NeighborOptions(direction: direction, typeFilter: types, limit: limit)
      )
    )
  }

  private func runUpsertNode(tokens: [String]) throws {
    guard tokens.count >= 2 else {
      throw CLIError.usage("upsert-node <type-id> <key> [--props '{\"name\":\"Alice\"}'] [--weight 1.0]")
    }
    let typeID = try parseUInt32(tokens[0], name: "type-id")
    let key = tokens[1]
    var props: [String: JSONValue] = [:]
    var weight: Float = 1.0

    var index = 2
    while index < tokens.count {
      switch tokens[index] {
      case "--props":
        index += 1
        guard index < tokens.count else {
          throw CLIError.usage("Expected JSON object after --props")
        }
        props = try parseJSONObject(tokens[index])
      case "--weight":
        index += 1
        guard index < tokens.count, let parsed = Float(tokens[index]) else {
          throw CLIError.usage("Expected number after --weight")
        }
        weight = parsed
      default:
        throw CLIError.usage("Unknown upsert-node option '\(tokens[index])'")
      }
      index += 1
    }

    let id = try database.upsertNode(
      typeID: typeID,
      key: key,
      options: UpsertNodeOptions(props: props, weight: weight)
    )
    print(id)
  }

  private func runUpsertEdge(tokens: [String]) throws {
    guard tokens.count >= 3 else {
      throw CLIError.usage("upsert-edge <from> <to> <type-id> [--props '{\"role\":\"lead\"}'] [--weight 1.0] [--valid-from ms] [--valid-to ms]")
    }
    let from = try parseUInt64(tokens[0], name: "from")
    let to = try parseUInt64(tokens[1], name: "to")
    let typeID = try parseUInt32(tokens[2], name: "type-id")
    var props: [String: JSONValue] = [:]
    var weight: Float = 1.0
    var validFrom: Int64?
    var validTo: Int64?

    var index = 3
    while index < tokens.count {
      switch tokens[index] {
      case "--props":
        index += 1
        guard index < tokens.count else {
          throw CLIError.usage("Expected JSON object after --props")
        }
        props = try parseJSONObject(tokens[index])
      case "--weight":
        index += 1
        guard index < tokens.count, let parsed = Float(tokens[index]) else {
          throw CLIError.usage("Expected number after --weight")
        }
        weight = parsed
      case "--valid-from":
        index += 1
        guard index < tokens.count, let parsed = Int64(tokens[index]) else {
          throw CLIError.usage("Expected integer after --valid-from")
        }
        validFrom = parsed
      case "--valid-to":
        index += 1
        guard index < tokens.count, let parsed = Int64(tokens[index]) else {
          throw CLIError.usage("Expected integer after --valid-to")
        }
        validTo = parsed
      default:
        throw CLIError.usage("Unknown upsert-edge option '\(tokens[index])'")
      }
      index += 1
    }

    let id = try database.upsertEdge(
      from: from,
      to: to,
      typeID: typeID,
      options: UpsertEdgeOptions(props: props, weight: weight, validFrom: validFrom, validTo: validTo)
    )
    print(id)
  }

  private func printHelp() {
    print(
      """
      Commands:
        help
        exit | quit
        stats
        get-node <id>
        get-edge <id>
        get-node-by-key <type-id> <key>
        nodes-by-type <type-id>
        neighbors <node-id> [--direction outgoing|incoming|both] [--limit N] [--types 10,11]
        upsert-node <type-id> <key> [--props '{"k":"v"}'] [--weight 1.0]
        upsert-edge <from> <to> <type-id> [--props '{"k":"v"}'] [--weight 1.0] [--valid-from ms] [--valid-to ms]
        delete-node <id>
        delete-edge <id>
      """
    )
  }

  private func printJSON<T: Encodable>(_ value: T) throws {
    let data = try encoder.encode(value)
    print(String(decoding: data, as: UTF8.self))
  }

  private func parseJSONObject(_ text: String) throws -> [String: JSONValue] {
    let data = Data(text.utf8)
    let object = try JSONSerialization.jsonObject(with: data)
    guard let dictionary = object as? [String: Any] else {
      throw CLIError.usage("Expected a JSON object")
    }
    return try dictionary.mapValues(JSONValue.from(any:))
  }

  private func parseUInt32(_ text: String, name: String) throws -> UInt32 {
    guard let value = UInt32(text) else {
      throw CLIError.usage("Invalid \(name): \(text)")
    }
    return value
  }

  private func parseUInt64(_ text: String, name: String) throws -> UInt64 {
    guard let value = UInt64(text) else {
      throw CLIError.usage("Invalid \(name): \(text)")
    }
    return value
  }

  private func tokenize(_ line: String) throws -> [String] {
    var tokens: [String] = []
    var current = ""
    var quote: Character?
    var escaping = false

    for character in line {
      if escaping {
        current.append(character)
        escaping = false
        continue
      }
      if character == "\\" {
        escaping = true
        continue
      }
      if let activeQuote = quote {
        if character == activeQuote {
          quote = nil
        } else {
          current.append(character)
        }
        continue
      }
      if character == "\"" || character == "'" {
        quote = character
        continue
      }
      if character.isWhitespace {
        flushTokenIfNeeded(&current, into: &tokens)
      } else {
        current.append(character)
      }
    }

    if escaping || quote != nil {
      throw CLIError.usage("Unterminated escape or quote")
    }
    flushTokenIfNeeded(&current, into: &tokens)
    return tokens
  }

  private func stripComments(from source: String) -> String {
    enum State {
      case normal
      case lineComment
      case blockComment
      case string(Character)
    }

    var result = ""
    var state: State = .normal
    var index = source.startIndex
    var escaping = false

    while index < source.endIndex {
      let character = source[index]
      let nextIndex = source.index(after: index)
      let nextCharacter = nextIndex < source.endIndex ? source[nextIndex] : nil

      switch state {
      case .normal:
        if character == "/", nextCharacter == "/" {
          state = .lineComment
          index = source.index(after: nextIndex)
          continue
        }
        if character == "/", nextCharacter == "*" {
          state = .blockComment
          index = source.index(after: nextIndex)
          continue
        }
        if character == "\"" || character == "'" {
          state = .string(character)
        }
        result.append(character)

      case .lineComment:
        if character.isNewline {
          state = .normal
          result.append(character)
        }

      case .blockComment:
        if character == "*", nextCharacter == "/" {
          state = .normal
          index = source.index(after: nextIndex)
          continue
        }
        if character.isNewline {
          result.append(character)
        }

      case let .string(quote):
        result.append(character)
        if escaping {
          escaping = false
        } else if character == "\\" {
          escaping = true
        } else if character == quote {
          state = .normal
        }
      }

      index = nextIndex
    }

    return result
  }

  private func flushTokenIfNeeded(_ current: inout String, into tokens: inout [String]) {
    if !current.isEmpty {
      tokens.append(current)
      current = ""
    }
  }
}

private enum CLIError: LocalizedError {
  case usage(String)

  var errorDescription: String? {
    switch self {
    case let .usage(message):
      return message
    }
  }
}
