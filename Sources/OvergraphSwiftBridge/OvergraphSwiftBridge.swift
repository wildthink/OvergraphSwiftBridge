import COvergraphBridge
import Foundation

/// Swift wrapper around the local Overgraph Rust engine.
///
/// This package intentionally uses a JSON-oriented bridge layer between Swift and
/// Rust. Public option and record types are `Codable` so callers can work with a
/// small stable Swift surface while the underlying FFI remains simple.
///
/// Concurrency note:
/// `OvergraphDatabase` is marked `@unchecked Sendable`. The current Alpha/Beta
/// release keeps that contract narrow: concurrent use is allowed only to the
/// extent that the underlying Overgraph engine and this wrapper remain safe for
/// shared access. Callers should prefer external synchronization when in doubt.
public final class OvergraphDatabase: @unchecked Sendable {
  private var handle: UnsafeMutableRawPointer?
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  /// Opens a database at `path`.
  ///
  /// - Parameters:
  ///   - path: Filesystem path to the database directory.
  ///   - options: Database open options serialized to JSON for the Rust bridge.
  public init(path: String, options: DatabaseOptions = .init()) throws {
    var errorPointer: UnsafeMutablePointer<CChar>?
    let rawHandle = path.withCString { pathCString in
      options.jsonCString { optionsCString in
        og_db_open(pathCString, optionsCString, &errorPointer)
      }
    }
    if let rawHandle {
      self.handle = rawHandle
    } else {
      throw BridgeError.fromOwnedCString(errorPointer) ?? .unknown
    }
  }

  deinit {
    if let handle {
      og_db_destroy(handle)
    }
  }

  /// Closes the database handle.
  ///
  /// Calling `close()` more than once is allowed. Later calls do nothing after
  /// the handle has already been closed.
  public func close(force: Bool = false) throws {
    guard let handle else { return }
    var errorPointer: UnsafeMutablePointer<CChar>?
    let ok = og_db_close(handle, force, &errorPointer)
    if ok {
      og_db_destroy(handle)
      self.handle = nil
    } else {
      throw BridgeError.fromOwnedCString(errorPointer) ?? .unknown
    }
  }

  /// Inserts or updates a node and returns its numeric node ID.
  public func upsertNode(
    typeID: UInt32,
    key: String,
    options: UpsertNodeOptions = .init()
  ) throws -> UInt64 {
    let request = BridgeRequest(
      method: "upsertNode",
      params: .object([
        "type_id": .number(Double(typeID)),
        "key": .string(key),
        "options": try .encodable(options, encoder: encoder),
      ])
    )
    return try call(request, as: UInt64Response.self).value
  }

  /// Inserts or updates an edge and returns its numeric edge ID.
  public func upsertEdge(
    from: UInt64,
    to: UInt64,
    typeID: UInt32,
    options: UpsertEdgeOptions = .init()
  ) throws -> UInt64 {
    let request = BridgeRequest(
      method: "upsertEdge",
      params: .object([
        "from": .number(Double(from)),
        "to": .number(Double(to)),
        "type_id": .number(Double(typeID)),
        "options": try .encodable(options, encoder: encoder),
      ])
    )
    return try call(request, as: UInt64Response.self).value
  }

  /// Fetches a node by ID.
  public func getNode(id: UInt64) throws -> NodeRecord? {
    let request = BridgeRequest(
      method: "getNode",
      params: .object(["id": .number(Double(id))])
    )
    return try call(request, as: NodeRecordEnvelope.self).node
  }

  /// Fetches an edge by ID.
  public func getEdge(id: UInt64) throws -> EdgeRecord? {
    let request = BridgeRequest(
      method: "getEdge",
      params: .object(["id": .number(Double(id))])
    )
    return try call(request, as: EdgeRecordEnvelope.self).edge
  }

  /// Fetches a node by its `(typeID, key)` identity.
  public func getNodeByKey(typeID: UInt32, key: String) throws -> NodeRecord? {
    let request = BridgeRequest(
      method: "getNodeByKey",
      params: .object([
        "type_id": .number(Double(typeID)),
        "key": .string(key),
      ])
    )
    return try call(request, as: NodeRecordEnvelope.self).node
  }

  /// Returns all nodes for a given type ID.
  public func getNodesByType(typeID: UInt32) throws -> [NodeRecord] {
    let request = BridgeRequest(
      method: "getNodesByType",
      params: .object(["type_id": .number(Double(typeID))])
    )
    return try call(request, as: NodesResponse.self).items
  }

  /// Returns adjacent nodes for `nodeID` using the provided query options.
  public func neighbors(
    of nodeID: UInt64,
    options: NeighborOptions = .init()
  ) throws -> [NeighborEntry] {
    let request = BridgeRequest(
      method: "neighbors",
      params: .object([
        "node_id": .number(Double(nodeID)),
        "options": try .encodable(options, encoder: encoder),
      ])
    )
    return try call(request, as: NeighborsResponse.self).items
  }

  /// Returns lightweight database runtime statistics.
  public func stats() throws -> DatabaseStats {
    try call(BridgeRequest(method: "stats", params: .object([:])), as: DatabaseStats.self)
  }

  /// Deletes a node by ID.
  public func deleteNode(id: UInt64) throws {
    let request = BridgeRequest(
      method: "deleteNode",
      params: .object(["id": .number(Double(id))])
    )
    _ = try call(request, as: EmptyResponse.self)
  }

  /// Deletes an edge by ID.
  public func deleteEdge(id: UInt64) throws {
    let request = BridgeRequest(
      method: "deleteEdge",
      params: .object(["id": .number(Double(id))])
    )
    _ = try call(request, as: EmptyResponse.self)
  }

  private func call<Response: Decodable>(_ request: BridgeRequest, as type: Response.Type) throws -> Response {
    guard let handle else {
      throw BridgeError.closed
    }
    let requestData = try encoder.encode(request)
    let requestJSON = String(decoding: requestData, as: UTF8.self)
    var errorPointer: UnsafeMutablePointer<CChar>?
    let responsePointer = requestJSON.withCString { requestCString in
      og_db_call(handle, requestCString, &errorPointer)
    }
    if let responsePointer {
      defer { og_string_free(responsePointer) }
      let data = Data(String(cString: responsePointer).utf8)
      return try decoder.decode(Response.self, from: data)
    }
    throw BridgeError.fromOwnedCString(errorPointer) ?? .unknown
  }
}

/// Options used when opening an `OvergraphDatabase`.
public struct DatabaseOptions: Codable, Sendable {
  public var createIfMissing: Bool
  public var memtableFlushThreshold: UInt
  public var edgeUniqueness: Bool
  public var compactAfterNFlushes: UInt32
  public var memtableHardCapBytes: UInt
  public var maxImmutableMemtables: UInt

  /// Creates a new set of database open options.
  public init(
    createIfMissing: Bool = true,
    memtableFlushThreshold: UInt = 128 * 1024 * 1024,
    edgeUniqueness: Bool = false,
    compactAfterNFlushes: UInt32 = 4,
    memtableHardCapBytes: UInt = 512 * 1024 * 1024,
    maxImmutableMemtables: UInt = 4
  ) {
    self.createIfMissing = createIfMissing
    self.memtableFlushThreshold = memtableFlushThreshold
    self.edgeUniqueness = edgeUniqueness
    self.compactAfterNFlushes = compactAfterNFlushes
    self.memtableHardCapBytes = memtableHardCapBytes
    self.maxImmutableMemtables = maxImmutableMemtables
  }

  fileprivate func jsonCString<R>(_ body: (UnsafePointer<CChar>?) -> R) -> R {
    guard let data = try? JSONEncoder().encode(self),
          let json = String(data: data, encoding: .utf8) else {
      return body(nil)
    }
    return json.withCString(body)
  }
}

/// Options for inserting or updating a node.
public struct UpsertNodeOptions: Codable, Sendable {
  public var props: [String: JSONValue]
  public var weight: Float
  public var denseVector: [Float]?
  public var sparseVector: [SparseVectorEntry]?

  /// Creates a new set of node upsert options.
  public init(
    props: [String: JSONValue] = [:],
    weight: Float = 1.0,
    denseVector: [Float]? = nil,
    sparseVector: [SparseVectorEntry]? = nil
  ) {
    self.props = props
    self.weight = weight
    self.denseVector = denseVector
    self.sparseVector = sparseVector
  }
}

/// Options for inserting or updating an edge.
public struct UpsertEdgeOptions: Codable, Sendable {
  public var props: [String: JSONValue]
  public var weight: Float
  public var validFrom: Int64?
  public var validTo: Int64?

  /// Creates a new set of edge upsert options.
  public init(
    props: [String: JSONValue] = [:],
    weight: Float = 1.0,
    validFrom: Int64? = nil,
    validTo: Int64? = nil
  ) {
    self.props = props
    self.weight = weight
    self.validFrom = validFrom
    self.validTo = validTo
  }
}

/// Options for neighbor traversal from a single node.
public struct NeighborOptions: Codable, Sendable {
  public var direction: Direction
  public var typeFilter: [UInt32]?
  public var limit: Int?
  public var atEpoch: Int64?
  public var decayLambda: Float?

  /// Creates a new set of neighbor query options.
  public init(
    direction: Direction = .outgoing,
    typeFilter: [UInt32]? = nil,
    limit: Int? = nil,
    atEpoch: Int64? = nil,
    decayLambda: Float? = nil
  ) {
    self.direction = direction
    self.typeFilter = typeFilter
    self.limit = limit
    self.atEpoch = atEpoch
    self.decayLambda = decayLambda
  }
}

/// Traversal direction for graph queries that walk edges.
public enum Direction: String, Codable, Sendable {
  case outgoing
  case incoming
  case both
}

/// Sparse vector entry used by node upsert options and records.
public struct SparseVectorEntry: Codable, Sendable {
  public var dimension: UInt32
  public var value: Float

  /// Creates a sparse vector entry.
  public init(dimension: UInt32, value: Float) {
    self.dimension = dimension
    self.value = value
  }
}

/// Node record returned by the public Swift API.
public struct NodeRecord: Codable, Sendable {
  public var id: UInt64
  public var typeID: UInt32
  public var key: String
  public var props: [String: JSONValue]
  public var createdAt: Int64
  public var updatedAt: Int64
  public var weight: Float
  public var denseVector: [Float]?
  public var sparseVector: [SparseVectorEntry]?
  public var lastWriteSequence: UInt64

  enum CodingKeys: String, CodingKey {
    case id
    case typeID = "typeId"
    case key
    case props
    case createdAt
    case updatedAt
    case weight
    case denseVector
    case sparseVector
    case lastWriteSequence
  }
}

/// Edge record returned by the public Swift API.
public struct EdgeRecord: Codable, Sendable {
  public var id: UInt64
  public var from: UInt64
  public var to: UInt64
  public var typeID: UInt32
  public var props: [String: JSONValue]
  public var createdAt: Int64
  public var updatedAt: Int64
  public var weight: Float
  public var validFrom: Int64
  public var validTo: Int64
  public var lastWriteSequence: UInt64

  enum CodingKeys: String, CodingKey {
    case id
    case from
    case to
    case typeID = "typeId"
    case props
    case createdAt
    case updatedAt
    case weight
    case validFrom
    case validTo
    case lastWriteSequence
  }
}

/// Neighbor traversal result entry.
public struct NeighborEntry: Codable, Sendable {
  public var nodeID: UInt64
  public var edgeID: UInt64
  public var edgeTypeID: UInt32
  public var weight: Float
  public var validFrom: Int64
  public var validTo: Int64

  enum CodingKeys: String, CodingKey {
    case nodeID = "nodeId"
    case edgeID = "edgeId"
    case edgeTypeID = "edgeTypeId"
    case weight
    case validFrom
    case validTo
  }
}

/// Runtime statistics reported by the database engine.
public struct DatabaseStats: Codable, Sendable {
  public var pendingWalBytes: Int
  public var segmentCount: Int
  public var nodeTombstoneCount: Int
  public var edgeTombstoneCount: Int
  public var lastCompactionMs: Int64?
  public var walSyncMode: String
  public var activeMemtableBytes: Int
  public var immutableMemtableBytes: Int
  public var immutableMemtableCount: Int
  public var pendingFlushCount: Int
  public var activeWalGenerationID: UInt64
  public var oldestRetainedWalGenerationID: UInt64

  enum CodingKeys: String, CodingKey {
    case pendingWalBytes
    case segmentCount
    case nodeTombstoneCount
    case edgeTombstoneCount
    case lastCompactionMs
    case walSyncMode
    case activeMemtableBytes
    case immutableMemtableBytes
    case immutableMemtableCount
    case pendingFlushCount
    case activeWalGenerationID = "activeWalGenerationId"
    case oldestRetainedWalGenerationID = "oldestRetainedWalGenerationId"
  }
}

/// JSON value used by the public Swift bridge surface.
///
/// The library surface uses plain JSON values, while the CLI accepts JSON5 and
/// normalizes it before sending it to the bridge.
public enum JSONValue: Codable, Sendable, Equatable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([String: JSONValue].self) {
      self = .object(value)
    } else {
      self = .array(try container.decode([JSONValue].self))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null:
      try container.encodeNil()
    case let .bool(value):
      try container.encode(value)
    case let .number(value):
      try container.encode(value)
    case let .string(value):
      try container.encode(value)
    case let .array(value):
      try container.encode(value)
    case let .object(value):
      try container.encode(value)
    }
  }

  fileprivate static func encodable<T: Encodable>(_ value: T, encoder: JSONEncoder) throws -> JSONValue {
    let data = try encoder.encode(value)
    return try JSONDecoder().decode(JSONValue.self, from: data)
  }

  /// Converts a Foundation value into a `JSONValue`.
  public static func from(any value: Any) throws -> JSONValue {
    switch value {
    case is NSNull:
      return .null
    case let value as JSONValue:
      return value
    case let value as Bool:
      return .bool(value)
    case let value as String:
      return .string(value)
    case let value as NSNumber:
      if CFGetTypeID(value) == CFBooleanGetTypeID() {
        return .bool(value.boolValue)
      }
      return .number(value.doubleValue)
    case let value as [Any]:
      return .array(try value.map(JSONValue.from(any:)))
    case let value as [String: Any]:
      return .object(try value.mapValues(JSONValue.from(any:)))
    default:
      throw BridgeError.message("Unsupported JSON value: \(type(of: value))")
    }
  }

  /// Returns a pretty-printed JSON representation of the value.
  public func prettyPrinted() throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(self)
    return String(decoding: data, as: UTF8.self)
  }
}

/// Errors surfaced by the Swift bridge layer.
public enum BridgeError: Error, LocalizedError, Sendable {
  case message(String)
  case closed
  case unknown

  public var errorDescription: String? {
    switch self {
    case let .message(message):
      return message
    case .closed:
      return "Database handle is closed"
    case .unknown:
      return "Unknown bridge error"
    }
  }

  fileprivate static func fromOwnedCString(_ pointer: UnsafeMutablePointer<CChar>?) -> BridgeError? {
    guard let pointer else { return nil }
    defer { og_string_free(pointer) }
    return .message(String(cString: pointer))
  }
}

private struct BridgeRequest: Codable {
  var method: String
  var params: JSONValue
}

private struct UInt64Response: Decodable {
  var value: UInt64
}

private struct NodeRecordEnvelope: Decodable {
  var node: NodeRecord?
}

private struct EdgeRecordEnvelope: Decodable {
  var edge: EdgeRecord?
}

private struct NodesResponse: Decodable {
  var items: [NodeRecord]
}

private struct NeighborsResponse: Decodable {
  var items: [NeighborEntry]
}

private struct EmptyResponse: Decodable {}
