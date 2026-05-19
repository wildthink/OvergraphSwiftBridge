import Foundation
import OvergraphSwiftBridge

struct DatabaseREPL {
  enum Result {
    case `continue`
    case exit
  }

  let database: OvergraphDatabase
  private let encoder: JSONEncoder
  private let dateParser: HumanDateParser

  init(database: OvergraphDatabase) {
    self.database = database
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    self.encoder = encoder
    self.dateParser = HumanDateParser()
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
      guard tokens.count == 3 else { throw CLIError.usage("get-node-by-key <label> <key>") }
      try printJSON(database.getNodeByKey(label: tokens[1], key: tokens[2]))
    case "nodes-by-label":
      guard tokens.count == 2 else { throw CLIError.usage("nodes-by-label <label>") }
      try printJSON(database.getNodesByLabels([tokens[1]]))
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

  private func runNeighbors(tokens: [String]) throws {
    guard let first = tokens.first else {
      throw CLIError.usage("neighbors <node-id> [--direction outgoing|incoming|both] [--limit N] [--edge-labels KNOWS,WORKS_ON] [--at-epoch <date>|--asof <date>] [--decay-lambda λ]")
    }
    let nodeID = try parseUInt64(first, name: "node-id")
    var direction: Direction = .outgoing
    var limit: Int?
    var edgeLabels: [String]?
    var atEpoch: Int64?
    var decayLambda: Float?

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
      case "--edge-labels":
        index += 1
        guard index < tokens.count else {
          throw CLIError.usage("Expected comma-separated list after --edge-labels")
        }
        edgeLabels = tokens[index]
          .split(separator: ",")
          .map(String.init)
      case "--at-epoch", "--asof":
        index += 1
        guard index < tokens.count else {
          throw CLIError.usage("Expected date after \(tokens[index - 1])")
        }
        atEpoch = try dateParser.parseEpochMilliseconds(tokens[index])
      case "--decay-lambda":
        index += 1
        guard index < tokens.count, let parsed = Float(tokens[index]) else {
          throw CLIError.usage("Expected number after --decay-lambda")
        }
        decayLambda = parsed
      default:
        throw CLIError.usage("Unknown neighbors option '\(tokens[index])'")
      }
      index += 1
    }

    try printJSON(
      database.neighbors(
        of: nodeID,
        options: NeighborOptions(
          direction: direction,
          edgeLabelFilter: edgeLabels,
          limit: limit,
          atEpoch: atEpoch,
          decayLambda: decayLambda
        )
      )
    )
  }

  private func runUpsertNode(tokens: [String]) throws {
    guard tokens.count >= 2 else {
      throw CLIError.usage("upsert-node <label> <key> [--props '{name: \"Alice\"}'] [--weight 1.0]")
    }
    let label = tokens[0]
    let key = tokens[1]
    var props: [String: JSONValue] = [:]
    var weight: Float = 1.0

    var index = 2
    while index < tokens.count {
      switch tokens[index] {
      case "--props":
        index += 1
        guard index < tokens.count else {
          throw CLIError.usage("Expected JSON5 object after --props")
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
      label: label,
      key: key,
      options: UpsertNodeOptions(props: props, weight: weight)
    )
    print(id)
  }

  private func runUpsertEdge(tokens: [String]) throws {
    guard tokens.count >= 3 else {
      throw CLIError.usage("upsert-edge <from> <to> <label> [--props '{role: \"lead\"}'] [--weight 1.0] [--valid-from <date>] [--valid-to <date>]")
    }
    let from = try parseUInt64(tokens[0], name: "from")
    let to = try parseUInt64(tokens[1], name: "to")
    let label = tokens[2]
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
          throw CLIError.usage("Expected JSON5 object after --props")
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
        guard index < tokens.count else {
          throw CLIError.usage("Expected date after --valid-from")
        }
        validFrom = try dateParser.parseEpochMilliseconds(tokens[index])
      case "--valid-to":
        index += 1
        guard index < tokens.count else {
          throw CLIError.usage("Expected date after --valid-to")
        }
        validTo = try dateParser.parseEpochMilliseconds(tokens[index])
      default:
        throw CLIError.usage("Unknown upsert-edge option '\(tokens[index])'")
      }
      index += 1
    }

    let id = try database.upsertEdge(
      from: from,
      to: to,
      label: label,
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
        get-node-by-key <label> <key>
        nodes-by-label <label>
        neighbors <node-id> [--direction outgoing|incoming|both] [--limit N] [--edge-labels KNOWS,WORKS_ON] [--at-epoch <date>|--asof <date>] [--decay-lambda λ]
        upsert-node <label> <key> [--props '{name: "Alice"}'] [--weight 1.0]
        upsert-edge <from> <to> <label> [--props '{role: "lead"}'] [--weight 1.0] [--valid-from <date>] [--valid-to <date>]
        delete-node <id>
        delete-edge <id>

      Date examples:
        now
        today
        tomorrow
        2024-06-01
        2024-06-01T12:30:00Z
        2024-06-01 12:30

      Decay note:
        neighbors supports `--decay-lambda <lambda>` for time-decayed scoring
      """
    )
  }

  private func printJSON<T: Encodable>(_ value: T) throws {
    let data = try encoder.encode(value)
    print(String(decoding: data, as: UTF8.self))
  }

  private func parseJSONObject(_ text: String) throws -> [String: JSONValue] {
    let data = Data(text.utf8)
    let object = try JSONSerialization.jsonObject(with: data, options: [.json5Allowed])
    guard let dictionary = object as? [String: Any] else {
      throw CLIError.usage("Expected a JSON5 object")
    }
    return try dictionary.mapValues(JSONValue.from(any:))
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

  private func flushTokenIfNeeded(_ current: inout String, into tokens: inout [String]) {
    if !current.isEmpty {
      tokens.append(current)
      current = ""
    }
  }
}

enum CLIError: LocalizedError {
  case usage(String)

  var errorDescription: String? {
    switch self {
    case let .usage(message):
      return message
    }
  }
}
