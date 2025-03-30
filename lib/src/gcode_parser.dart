import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math_64.dart' as vector;
import 'dart:math' as math;

/// A class to hold path segments in G-code.
class GcodePath {
  /// Points that make up this path segment.
  final List<vector.Vector3> points;

  /// Whether this path represents a travel move (non-cutting).
  final bool isTravel;

  /// Creates a path segment with the specified points and travel flag.
  GcodePath(this.points, this.isTravel);
}

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

/// Parses a G-code string into a structured format.
///
/// [gcode] The G-code string to parse.
/// [arcDetailLevel] Detail level for arc rendering (1.0 = normal, higher = more detailed).
///
/// Returns a [ParsedGcode] object containing the parsed data.
ParsedGcode parseGcode(String gcode, {double arcDetailLevel = 1.5}) {
  final List<vector.Vector3> allPoints = [];
  final List<bool> allIsTravelFlags = [];
  final List<double> allZValues = [];

  // Also generate separate path segments for better rendering
  final List<GcodePath> pathSegments = [];

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

  final lines = gcode.split('\n');

  if (kDebugMode) {
    print('Processing ${lines.length} lines of G-code');
  }

  // Current path segment
  List<vector.Vector3> currentPathPoints = [];
  bool currentPathIsTravel = false;

  // Force le premier point à (0,0,0) si aucun G92 n'est spécifié
  bool hasSetInitialPosition = false;

  for (var line in lines) {
    line = line.trim();
    // Skip comments
    if (line.contains(';')) {
      line = line.substring(0, line.indexOf(';')).trim();
    }
    if (line.startsWith('(') && line.endsWith(')')) {
      line = '';
    }
    if (line.isEmpty) continue;

    final parts = line.toUpperCase().split(' ');
    vector.Vector3 nextPosition = currentPosition.clone();
    bool motionCommandFound = false;
    double? iValue, jValue, kValue, rValue;
    int? gCode;
    bool hasCoordinates = false;

    // Vérifier si cette ligne contient une commande G92 (définition de position)
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

      // Pour le premier déplacement, on le traite toujours comme un changement de position
      // même si les coordonnées sont identiques (0,0,0 -> 0,0,0)
      if (!hasSetInitialPosition && allPoints.isEmpty && gCode == 0) {
        if (kDebugMode) {
          print(
            'Premier déplacement G0 dessiné en surbrillance: $currentPosition -> $nextPosition',
          );
        }

        // Assurer que le premier point est toujours ajouté
        allPoints.add(currentPosition.clone());
        allZValues.add(currentPosition.z);
        allIsTravelFlags.add(true); // Premier point est toujours un déplacement

        // Ajouter au segment de chemin actuel
        if (currentPathPoints.isEmpty) {
          currentPathPoints.add(currentPosition.clone());
          currentPathIsTravel = true;
        }

        // Considérer le point suivant
        currentPathPoints.add(nextPosition.clone());
        allPoints.add(nextPosition.clone());
        allZValues.add(nextPosition.z);
        allIsTravelFlags.add(true);

        // Mettre à jour la position courante
        currentPosition = nextPosition.clone();

        // Continuer avec la ligne suivante
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
          // Arc move - calculate intermediate points
          final arcPoints = calculateArcPoints(
            currentPosition,
            nextPosition,
            iValue,
            jValue,
            kValue,
            rValue,
            gCode == 2,
            currentPlane,
            detailLevel: arcDetailLevel,
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
  double detailLevel = 2.5,
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

  // Calculate segments based on radius and arc length
  // Use more segments for small radii to ensure smooth rendering of tabs
  const double baseSegmentsPerRadian = 20.0; // Increased for better quality
  int segments;

  // Handle specific cases more carefully
  if (radius < 0.5) {
    // Extra segments for tiny arcs like tabs/chamfers
    segments = (150 * detailLevel).round();
  } else if (radius < 3.0) {
    // More segments for small to medium arcs
    segments =
        (radius * sweepAngle.abs() * baseSegmentsPerRadian * detailLevel * 3)
            .ceil();
  } else {
    // Standard calculation for larger arcs
    segments =
        (radius * sweepAngle.abs() * baseSegmentsPerRadian * detailLevel)
            .ceil();
  }

  // Ensure reasonable bounds
  segments = math.max(
    segments,
    (80 * detailLevel).round(),
  ); // Increased minimum
  segments = math.min(
    segments,
    (1200 * detailLevel).round(),
  ); // Increased maximum

  // Calculate points along the arc
  for (int i = 0; i <= segments; i++) {
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

    arcPoints.add(point);
  }

  return arcPoints;
}
