import Foundation

struct ScriptRunner {
  func runScript(
    atPath path: String,
    executeLine: (String) throws -> Bool
  ) throws {
    let source = try String(contentsOfFile: path, encoding: .utf8)
    let stripped = stripComments(from: source)
    for rawLine in stripped.split(whereSeparator: \.isNewline) {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      if line.isEmpty { continue }
      let shouldContinue = try executeLine(line)
      if !shouldContinue {
        return
      }
    }
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
}
