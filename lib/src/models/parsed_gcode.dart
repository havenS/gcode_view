import 'package:gcode_view/src/models/gcode_path.dart';
import 'package:vector_math/vector_math_64.dart' as vector;

/// Result of parsing G-code containing points, flags, and metadata.
class ParsedGcode {
  /// All points in the G-code path.
  final List<vector.Vector3> points;

  /// Flags indicating whether each point is part of a travel move.
  final List<bool> isTravel;

  /// Z-values for all points.
  final List<double> zValues;

  /// Path segments extracted from the G-code.
  List<GcodePath> pathSegments = [];

  /// Creates a new parsed G-code result.
  ParsedGcode(this.points, this.isTravel, this.zValues);

  /// Analyze and determine the actual Z-levels used for operations.
  /// Returns a Map of Z-values to normalized values (0.0-1.0).
  Map<double, double> getNormalizedZLevels() {
    if (zValues.isEmpty) return {};

    // Get unique Z values
    final Set<double> uniqueZValues = zValues.toSet();
    final List<double> sortedZ = uniqueZValues.toList()..sort();

    // Create map of actual Z values to normalized values (0-1)
    final Map<double, double> zToNormalized = {};
    if (sortedZ.length == 1) {
      // Only one Z level, set it to middle of range
      zToNormalized[sortedZ.first] = 0.5;
    } else {
      // Multiple Z levels - map each to normalized value
      final double minZ = sortedZ.first;
      final double maxZ = sortedZ.last;
      final double range = maxZ - minZ;

      if (range < 0.0001) {
        // If range is too small, treat as single level
        for (final z in sortedZ) {
          zToNormalized[z] = 0.5;
        }
      } else {
        // Normal case - map to 0.0-1.0 range
        for (final z in sortedZ) {
          zToNormalized[z] = (z - minZ) / range;
        }
      }
    }

    return zToNormalized;
  }
}
