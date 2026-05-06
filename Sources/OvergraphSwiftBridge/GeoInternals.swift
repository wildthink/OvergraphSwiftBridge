import Foundation

/// Internal sketch for a future geo query surface.
///
/// This is intentionally not public in the current Beta release. It exists to
/// document the intended Swift-side shape before the Rust bridge exposes an
/// efficient geo/radius query primitive.
struct GeoPoint: Codable, Sendable, Equatable {
  let latitude: Double
  let longitude: Double

  init(latitude: Double, longitude: Double) {
    self.latitude = latitude
    self.longitude = longitude
  }
}

/// Internal sketch for a future radius query request.
///
/// Candidate public shape once the backend can support it efficiently:
///
/// `nearbyNodes(center: GeoPoint, radiusMeters: Double, typeID: UInt32?, limit: Int?)`
///
/// Likely backend strategies under consideration:
/// - bounding-box prefilter on numeric lat/lon properties, then Haversine filter
/// - dedicated geo index in Overgraph
/// - vector approximation (least preferred for first release)
struct GeoRadiusQuery: Sendable, Equatable {
  let center: GeoPoint
  let radiusMeters: Double
  let typeID: UInt32?
  let limit: Int?
}
