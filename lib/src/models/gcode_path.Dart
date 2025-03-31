import 'package:vector_math/vector_math_64.dart' as vector;

/// Represents a path segment in G-code
class GcodePath {
  /// Points that constitute the path segment.
  final List<vector.Vector3> points;

  /// Whether this path represents a travel move (non-cutting).
  final bool isTravel;

  GcodePath(this.points, this.isTravel);
}
