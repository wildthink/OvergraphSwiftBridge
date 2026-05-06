import Foundation
import Testing
@testable import OvergraphSwiftBridge

@Test
func basicLifecycleAndQueries() throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("overgraph-swift-bridge-tests-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

  let db = try OvergraphDatabase(path: root.path)
  let alice = try db.upsertNode(
    typeID: 1,
    key: "person:alice",
    options: .init(props: ["name": .string("Alice")])
  )
  let atlas = try db.upsertNode(
    typeID: 2,
    key: "project:atlas",
    options: .init(props: ["name": .string("Atlas")])
  )
  let edge = try db.upsertEdge(from: alice, to: atlas, typeID: 10)

  let fetchedAlice = try #require(try db.getNode(id: alice))
  #expect(fetchedAlice.key == "person:alice")
  #expect(fetchedAlice.props["name"] == .string("Alice"))

  let fetchedByKey = try #require(try db.getNodeByKey(typeID: 1, key: "person:alice"))
  #expect(fetchedByKey.id == alice)

  let neighbors = try db.neighbors(of: alice)
  #expect(neighbors.count == 1)
  #expect(neighbors.first?.nodeID == atlas)
  #expect(neighbors.first?.edgeID == edge)

  let projects = try db.getNodesByType(typeID: 2)
  #expect(projects.count == 1)
  #expect(projects.first?.id == atlas)

  let stats = try db.stats()
  #expect(stats.segmentCount >= 0)

  try db.close()
}
