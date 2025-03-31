import 'package:flutter/foundation.dart';
import 'package:gcode_view/src/configs/gcode_parser_config.dart';
import 'package:gcode_view/src/models/gcode_path.dart';
import 'package:gcode_view/src/models/parsed_gcode.dart';
import 'package:vector_math/vector_math_64.dart' as vector;
import 'dart:math' as math;

/// Parses a G-code string into a structured format.
///
/// [gcode] The G-code string to parse.
/// [config] Configuration settings for the parser.
///
/// Returns a [ParsedGcode] object containing the parsed data.
ParsedGcode parseGcode(String gcode, {GcodeParserConfig? config}) {
  final parserConfig = config ?? const GcodeParserConfig();

  // Pre-allocate estimated capacity for collections to prevent frequent resizing
  final lines = gcode.split('\n');

  final List<vector.Vector3> allPoints = List.empty(growable: true)..length = 0;
  final List<bool> allIsTravelFlags = List.empty(growable: true)..length = 0;
  final List<double> allZValues = List.empty(growable: true)..length = 0;
  final List<GcodePath> pathSegments = [];

  // Force extremely detailed arc segments for critical features like tabs
  const double tabDetailSegmentThreshold = 0.005; // Much more detailed for tabs

  vector.Vector3 currentPosition = vector.Vector3.zero();
  bool absoluteMode = true; // G90 is usually default
  bool currentMoveIsTravel = false;

  // Store the last active G command - needed for implicit commands (lines with only X/Y/Z)
  int lastActiveGCode = 0; // Default to G0 if not specified

  // Track current plane selection (G17 = XY, G18 = ZX, G19 = YZ)
  String currentPlane = "G17"; // Default to XY plane (G17)

  // Keep track of encountered commands for debugging
  final Set<String> encounteredCommands = {};
  final Map<double, int> zLevelCounts = {};

  // Current path segment
  List<vector.Vector3> currentPathPoints = [];
  bool currentPathIsTravel = false;

  // Force the first point to (0,0,0) if no G92 is specified
  bool hasSetInitialPosition = false;

  // Performance optimization: Cache the trimmed lines to avoid multiple string operations
  final List<String> trimmedLines = List.generate(lines.length, (index) {
    String line = lines[index].trim();
    // Process comments
    if (line.contains(';')) {
      line = line.substring(0, line.indexOf(';')).trim();
    }
    if (line.startsWith('(') && line.endsWith(')')) {
      return '';
    }
    return line;
  });

  for (int lineIndex = 0; lineIndex < trimmedLines.length; lineIndex++) {
    final line = trimmedLines[lineIndex];
    if (line.isEmpty) continue;

    final parts = line.toUpperCase().split(' ');
    vector.Vector3 nextPosition = currentPosition.clone();
    bool motionCommandFound = false;
    double? iValue, jValue, kValue, rValue;
    int? gCode;
    bool hasCoordinates = false;

    // Check if line contains a G92 command (position definition)
    if (line.toUpperCase().contains('G92')) {
      hasSetInitialPosition = true;
    }

    for (var part in parts) {
      if (part.isEmpty) continue;
      final command = part[0];

      // Skip parts that don't start with valid command characters
      if (!'GXYZIJKRFMS'.contains(command)) continue;

      // Track all commands for debugging
      if (kDebugMode && command == 'G') {
        encounteredCommands.add(part);
      }

      final value = double.tryParse(part.substring(1));
      if (value == null && !['G', 'M'].contains(command)) continue;

      switch (command) {
        case 'G':
          if (value == null) continue;
          gCode = value.toInt();

          // Handle motion commands
          if (gCode == 0) {
            lastActiveGCode = gCode;
            currentMoveIsTravel = true; // G0 is always travel
            motionCommandFound = true;
          } else if (gCode == 1 || gCode == 2 || gCode == 3) {
            lastActiveGCode = gCode;
            currentMoveIsTravel = false; // G1/G2/G3 are always cut moves
            motionCommandFound = true;
          }
          // Handle plane selection
          else if (gCode == 17) {
            currentPlane = "G17"; // XY plane
          } else if (gCode == 18) {
            currentPlane = "G18"; // ZX plane
          } else if (gCode == 19) {
            currentPlane = "G19"; // YZ plane
          }
          // Handle coordinate system
          else if (gCode == 90) {
            absoluteMode = true;
          } else if (gCode == 91) {
            absoluteMode = false;
          }
          break;
        case 'X':
          hasCoordinates = true;
          nextPosition.x = absoluteMode ? value! : currentPosition.x + value!;
          break;
        case 'Y':
          hasCoordinates = true;
          nextPosition.y = absoluteMode ? value! : currentPosition.y + value!;
          break;
        case 'Z':
          hasCoordinates = true;
          nextPosition.z = absoluteMode ? value! : currentPosition.z + value!;
          break;
        case 'I':
          iValue = value;
          break;
        case 'J':
          jValue = value;
          break;
        case 'K':
          kValue = value;
          break;
        case 'R':
          rValue = value;
          break;
      }
    }

    // Handle implicit commands
    if (hasCoordinates && !motionCommandFound) {
      motionCommandFound = true;
      gCode = lastActiveGCode;
      currentMoveIsTravel = (gCode == 0);
    }

    // Process motion
    if (motionCommandFound) {
      const double epsilon = 0.001;
      final positionChanged =
          currentPosition.distanceToSquared(nextPosition) > epsilon * epsilon;

      // For the first movement, always treat it as a position change
      // even if coordinates are identical (0,0,0 -> 0,0,0)
      if (!hasSetInitialPosition && allPoints.isEmpty && gCode == 0) {
        if (kDebugMode) {
          print(
            'First G0 movement drawn highlighted: $currentPosition -> $nextPosition',
          );
        }

        // Ensure first point is always added
        allPoints.add(currentPosition.clone());
        allZValues.add(currentPosition.z);
        allIsTravelFlags.add(true); // First point is always a movement

        // Add to current path segment
        if (currentPathPoints.isEmpty) {
          currentPathPoints.add(currentPosition.clone());
          currentPathIsTravel = true;
        }

        // Consider next point
        currentPathPoints.add(nextPosition.clone());
        allPoints.add(nextPosition.clone());
        allZValues.add(nextPosition.z);
        allIsTravelFlags.add(true);

        // Update current position
        currentPosition = nextPosition.clone();

        // Continue with next line
        continue;
      }

      if (positionChanged) {
        // If current move type is different from current path, save the current path
        if (currentPathPoints.isNotEmpty &&
            (currentPathIsTravel != currentMoveIsTravel ||
                (currentMoveIsTravel && currentPathIsTravel))) {
          // Save the current path segment
          pathSegments.add(
            GcodePath(List.from(currentPathPoints), currentPathIsTravel),
          );

          // Start a new path with the current position
          currentPathPoints = [currentPosition.clone()];
        } else if (currentPathPoints.isEmpty) {
          // Start a fresh path
          currentPathPoints.add(currentPosition.clone());
        }

        // Update current path type
        currentPathIsTravel = currentMoveIsTravel;

        // Add all points for this move
        if (gCode == 2 || gCode == 3) {
          // Arc move - calculate intermediate points with optimization
          // Always use high detail for arc segments to ensure tabs are preserved
          final arcPoints = calculateArcPoints(
            currentPosition,
            nextPosition,
            iValue,
            jValue,
            kValue,
            rValue,
            gCode == 2,
            currentPlane,
            detailLevel:
                parserConfig.arcDetailLevel * 2.0, // Double the detail level
            maxSegments: parserConfig.maxArcSegments * 2, // Double the segments
            segmentThreshold:
                tabDetailSegmentThreshold, // Force very detailed segments
          );

          // Add all points after the first (which is already in the path)
          if (arcPoints.length > 1) {
            currentPathPoints.addAll(arcPoints.sublist(1));

            // Also add to the main point list for compatibility
            allPoints.addAll(arcPoints);
            allZValues.addAll(List.filled(arcPoints.length, nextPosition.z));
            allIsTravelFlags.addAll(
              List.filled(arcPoints.length - 1, currentMoveIsTravel),
            );
          }
        } else {
          // Linear move - add the endpoint
          currentPathPoints.add(nextPosition.clone());

          // Add to main point list
          allPoints.add(nextPosition.clone());
          allZValues.add(nextPosition.z);
          allIsTravelFlags.add(currentMoveIsTravel);
        }

        // Move to the next position
        currentPosition = nextPosition.clone();

        // Track Z levels for debugging
        if (kDebugMode) {
          zLevelCounts[currentPosition.z] =
              (zLevelCounts[currentPosition.z] ?? 0) + 1;
        }
      }
    }
  }

  // Add the final path if not empty
  if (currentPathPoints.isNotEmpty) {
    pathSegments.add(
      GcodePath(List.from(currentPathPoints), currentPathIsTravel),
    );
  }

  if (kDebugMode) {
    print(
      'Parsed ${allPoints.length} points from G-code with ${allZValues.toSet().length} different Z levels.',
    );
    print('Created ${pathSegments.length} separate path segments');
    print('Travel paths: ${pathSegments.where((p) => p.isTravel).length}');
    print('Cut paths: ${pathSegments.where((p) => !p.isTravel).length}');
    print('Z levels: ${allZValues.toSet().toList()..sort()}');
    print('Z level counts: $zLevelCounts');
    print('Encountered G commands: ${encounteredCommands.toList()..sort()}');
  }

  // Store path segments in the parsed result
  final parsedResult = ParsedGcode(allPoints, allIsTravelFlags, allZValues);
  parsedResult.pathSegments = pathSegments;
  return parsedResult;
}

/// Calculates intermediate points for an arc move.
///
/// [start] Starting point of the arc.
/// [end] Ending point of the arc.
/// [i] I offset from current position to center.
/// [j] J offset from current position to center.
/// [k] K offset from current position to center.
/// [r] Radius of the arc.
/// [clockwise] Whether the arc should be drawn clockwise.
/// [plane] Current plane for the arc (G17=XY, G18=ZX, G19=YZ).
/// [detailLevel] Detail level for rendering (higher = more points).
/// [maxSegments] Maximum number of segments to generate.
/// [segmentThreshold] Minimum distance between points to prevent overly detailed paths.
///
/// Returns a list of Vector3 points representing the arc.
List<vector.Vector3> calculateArcPoints(
  vector.Vector3 start,
  vector.Vector3 end,
  double? i,
  double? j,
  double? k,
  double? r,
  bool clockwise,
  String plane, {
  double detailLevel = 1.0,
  int maxSegments = 300,
  double segmentThreshold = 0.05,
}) {
  final List<vector.Vector3> arcPoints = [];

  // Always add the start point first
  arcPoints.add(start.clone());

  // For G18/G19 plane selection, we need to handle differently
  bool isDefaultPlane = plane == "G17"; // XY is default

  // Check if we have the required parameters
  bool hasOffsets = false;
  if (isDefaultPlane && (i != null || j != null)) hasOffsets = true;
  if (plane == "G18" && (i != null || k != null)) hasOffsets = true;
  if (plane == "G19" && (j != null || k != null)) hasOffsets = true;

  if (!hasOffsets && r == null) {
    // Missing required parameters, just return a straight line
    arcPoints.add(end.clone());
    return arcPoints;
  }

  double centerX, centerY, centerZ;

  // Extract the appropriate coordinate values based on the plane
  if (plane == "G17") {
    // XY plane
    centerX = start.x + (i ?? 0);
    centerY = start.y + (j ?? 0);
    centerZ = start.z; // Z is constant in XY plane
  } else if (plane == "G18") {
    // ZX plane
    centerZ = start.z + (i ?? 0);
    centerX = start.x + (k ?? 0);
    centerY = start.y; // Y is constant in ZX plane
  } else {
    // G19 (YZ plane)
    centerY = start.y + (j ?? 0);
    centerZ = start.z + (k ?? 0);
    centerX = start.x; // X is constant in YZ plane
  }

  // Calculate radius
  double radius;
  if (r != null) {
    // Use explicit radius if provided
    radius = r.abs();
  } else {
    // Calculate radius from center based on the current plane
    double dx1, dx2;
    if (plane == "G17") {
      dx1 = start.x - centerX;
      dx2 = start.y - centerY;
    } else if (plane == "G18") {
      dx1 = start.z - centerZ;
      dx2 = start.x - centerX;
    } else {
      // G19
      dx1 = start.y - centerY;
      dx2 = start.z - centerZ;
    }
    radius = math.sqrt(dx1 * dx1 + dx2 * dx2);
  }

  // Check if radius is too small - avoid division by zero
  if (radius < 0.0001) {
    arcPoints.add(end.clone());
    return arcPoints;
  }

  // Calculate start and end angles based on the appropriate plane
  double startAngle, endAngle;
  if (plane == "G17") {
    startAngle = math.atan2(start.y - centerY, start.x - centerX);
    endAngle = math.atan2(end.y - centerY, end.x - centerX);
  } else if (plane == "G18") {
    startAngle = math.atan2(start.x - centerX, start.z - centerZ);
    endAngle = math.atan2(end.x - centerX, end.z - centerZ);
  } else {
    // G19
    startAngle = math.atan2(start.z - centerZ, start.y - centerY);
    endAngle = math.atan2(end.z - centerZ, end.y - centerY);
  }

  // Normalize end angle based on direction
  if (clockwise) {
    while (endAngle > startAngle) {
      endAngle -= 2 * math.pi;
    }
    while (endAngle <= startAngle - 2 * math.pi) {
      endAngle += 2 * math.pi;
    }
  } else {
    while (endAngle < startAngle) {
      endAngle += 2 * math.pi;
    }
    while (endAngle >= startAngle + 2 * math.pi) {
      endAngle -= 2 * math.pi;
    }
  }

  // Determine sweep angle
  double sweepAngle = endAngle - startAngle;

  // Handle zero or near-zero sweep angles
  if (sweepAngle.abs() < 0.0001) {
    // If sweep angle is nearly zero but endpoints differ, make a straight line
    if ((start - end).length > 0.001) {
      arcPoints.add(end.clone());
      return arcPoints;
    }
    // Otherwise, it's intended to be a full circle
    sweepAngle = clockwise ? -2 * math.pi : 2 * math.pi;
  }

  // Handle full circles - calculate using endpoint distance
  double endpointDistance;
  if (plane == "G17") {
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    endpointDistance = math.sqrt(dx * dx + dy * dy);
  } else if (plane == "G18") {
    final dx = end.x - start.x;
    final dz = end.z - start.z;
    endpointDistance = math.sqrt(dx * dx + dz * dz);
  } else {
    // G19
    final dy = end.y - start.y;
    final dz = end.z - start.z;
    endpointDistance = math.sqrt(dy * dy + dz * dz);
  }

  // If endpoints are the same and sweep angle is very small, it's a full circle
  if (endpointDistance < 0.001 && sweepAngle.abs() < 0.0001) {
    sweepAngle = clockwise ? -2 * math.pi : 2 * math.pi;
  }

  // Calculate segments based on arc length and radius
  // Smaller radius arcs need more segments per unit length to maintain quality
  double arcLength = radius * sweepAngle.abs();

  // Adjust segment count based on radius - smaller radius = more detail needed
  double segmentFactor;
  if (radius < 1.0) {
    // For very small radii like tabs, use extremely high detail
    segmentFactor = 0.005; // 0.005mm per segment for small features
  } else if (radius < 3.0) {
    // For small radii, use very high detail
    segmentFactor = 0.01; // 0.01mm per segment
  } else if (radius < 10.0) {
    // For medium radii, use high detail
    segmentFactor = 0.03; // 0.03mm per segment
  } else {
    // For normal/large arcs, use standard detail
    segmentFactor = segmentThreshold;
  }

  // Apply detail level adjustment
  segmentFactor /= detailLevel;

  // Calculate segment count
  int segments = (arcLength / segmentFactor).ceil();

  // Ensure reasonable bounds
  segments = math.max(segments, 12); // Minimum of 12 segments for any arc
  segments = math.min(segments, maxSegments); // Cap maximum segments

  // Special case for small features that might be tabs
  // If the arc has a small radius and spans close to 90 degrees, it might be a tab corner
  if (radius < 3.0 &&
      sweepAngle.abs() > math.pi / 4 &&
      sweepAngle.abs() < math.pi / 2 + 0.2) {
    // Ensure we have enough segments for a smooth corner (at least 12 for quarter circles)
    segments = math.max(segments, 12);
  }

  // Generate more equidistant points
  vector.Vector3? lastPoint = arcPoints.first;
  for (int i = 1; i <= segments; i++) {
    final t = i / segments;
    final angle = startAngle + t * sweepAngle;

    // Calculate coordinates based on the current plane
    vector.Vector3 point;
    if (plane == "G17") {
      // XY plane
      final x = centerX + radius * math.cos(angle);
      final y = centerY + radius * math.sin(angle);
      point = vector.Vector3(x, y, start.z); // Z remains constant
    } else if (plane == "G18") {
      // ZX plane
      final z = centerZ + radius * math.cos(angle);
      final x = centerX + radius * math.sin(angle);
      point = vector.Vector3(x, start.y, z); // Y remains constant
    } else {
      // G19 (YZ plane)
      final y = centerY + radius * math.cos(angle);
      final z = centerZ + radius * math.sin(angle);
      point = vector.Vector3(start.x, y, z); // X remains constant
    }

    // Small radius features (likely tabs and corners) - always add the point
    // For larger features, apply distance-based filtering
    if (radius < 3.0 ||
        i == segments || // Always include end point
        lastPoint == null ||
        (point - lastPoint).length >= segmentFactor * 2) {
      // Use double the threshold for filtering

      arcPoints.add(point);
      lastPoint = point;
    }
  }

  // Ensure we always include the exact end point for precision
  if ((arcPoints.last - end).length > 0.001) {
    arcPoints.add(end.clone());
  }

  return arcPoints;
}
