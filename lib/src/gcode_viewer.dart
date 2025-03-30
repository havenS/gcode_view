import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vector;
import 'gcode_parser.dart';

/// Controller to interact with a [GcodeViewer] instance.
class GcodeViewerController {
  VoidCallback? _resetViewCallback;

  /// Resets the camera view (position, rotation, zoom) to its initial state.
  void resetView() {
    _resetViewCallback?.call();
  }

  // Internal methods for the widget to register its state's methods
  void _attach(VoidCallback resetCallback) {
    _resetViewCallback = resetCallback;
  }

  void _detach() {
    _resetViewCallback = null;
  }
}

/// A widget for visualizing G-code paths in 3D.
class GcodeViewer extends StatefulWidget {
  /// The G-code string to parse and display.
  final String gcode;

  /// The thickness of the path lines.
  final double pathThickness;

  /// The color of the cutting moves.
  final Color cutColor;

  /// The color of the travel moves (moves without cutting).
  final Color travelColor;

  /// The color of the grid lines.
  final Color gridColor;

  /// Whether to display the grid.
  final bool showGrid;

  /// Whether the units are millimeters (true) or inches (false).
  final bool isMillimeters;

  /// Detail level for arc rendering (1.0 = normal, higher = more detailed)
  final double arcDetailLevel;

  /// Controls the sensitivity of zooming gestures.
  ///
  /// Values between 0.1 and 2.0 are recommended:
  /// - Lower values (< 1.0) make zooming less sensitive and more controlled
  /// - Higher values (> 1.0) make zooming more responsive but potentially harder to control
  ///
  /// Default is 0.5 for smoother zoom control.
  final double zoomSensitivity;

  /// Optional controller to programmatically interact with the viewer.
  final GcodeViewerController? controller;

  const GcodeViewer({
    super.key,
    required this.gcode,
    this.controller,
    this.pathThickness = 2.5,
    this.cutColor = Colors.lightBlue,
    this.travelColor = Colors.grey,
    this.gridColor = Colors.black12,
    this.showGrid = true,
    this.isMillimeters = true,
    this.arcDetailLevel = 2.5,
    this.zoomSensitivity = 0.5,
  });

  @override
  State<GcodeViewer> createState() => _GcodeViewerState();
}

class _GcodeViewerState extends State<GcodeViewer> {
  // Store the initial transform
  static final vector.Matrix4 _initialTransform =
      vector.Matrix4.identity()
        ..rotateX(vector.radians(90)) // Initial view: X right, Y depth, Z up
        ..rotateX(
          vector.radians(30),
        ) // Tilt down (look from "up") by 30 degrees
        ..rotateZ(
          vector.radians(30),
        ) // Rotate horizontally ("right") by 30 degrees
        ..rotateZ(
          vector.radians(-75), // Change last horizontal rotation to -45 degrees
        );

  // Transformation matrix for camera view (rotation, zoom)
  late vector.Matrix4 _transform;

  // Zoom level
  double _zoom = 1.0;

  // Offset for panning
  Offset _offset = Offset.zero;

  // Previous focal point for scaling/panning
  Offset? _lastFocalPoint;

  // Store parsed G-code results
  List<vector.Vector3> _pathPoints = [];
  List<bool> _isTravelFlags = [];
  List<double> _zValues = []; // Add Z-values storage

  @override
  void initState() {
    super.initState();
    _transform = _initialTransform.clone();
    widget.controller?._attach(_resetView);
    _parseAndUpdatePath(); // Parse initial G-code
  }

  @override
  void didUpdateWidget(covariant GcodeViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    bool controllerChanged = false;
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller?._detach();
      widget.controller?._attach(_resetView);
      controllerChanged = true;
    }
    // Re-parse if G-code string changes
    if (widget.gcode != oldWidget.gcode ||
        controllerChanged /* Also reset on controller change? Might not be needed */ ) {
      _parseAndUpdatePath();
    }
    // TODO: Handle changes in other widget properties (colors, thickness etc.)
    // if they affect parsing or require repaint
  }

  void _parseAndUpdatePath() {
    if (widget.gcode.isEmpty) {
      setState(() {
        _pathPoints = [];
        _isTravelFlags = [];
        _zValues = [];
      });
      return;
    }
    try {
      final parsedData = parseGcode(
        widget.gcode,
        arcDetailLevel: widget.arcDetailLevel,
      );
      setState(() {
        _pathPoints = parsedData.points;
        _isTravelFlags = parsedData.isTravel;
        _zValues = parsedData.zValues; // Store Z-values
      });
    } catch (e) {
      if (kDebugMode) {
        print("Error parsing G-code: $e");
      }
      // Optionally show an error message to the user
      setState(() {
        _pathPoints = []; // Clear path on error
        _isTravelFlags = [];
        _zValues = [];
      });
    }
  }

  @override
  void dispose() {
    // Detach controller
    widget.controller?._detach();
    super.dispose();
  }

  /// Resets the view to the initial state (internal method)
  void _resetView() {
    setState(() {
      _transform = _initialTransform.clone();
      _zoom = 1.0;
      _offset = Offset.zero;
      _lastFocalPoint = null; // Reset gesture state too
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        // Center the view initially
        final initialOffset = Offset(size.width / 2, size.height / 2);

        return GestureDetector(
          onScaleStart: (details) {
            _lastFocalPoint = details.localFocalPoint;
          },
          onScaleUpdate: (details) {
            if (_lastFocalPoint == null) return;

            final focalPoint = details.localFocalPoint;
            final delta =
                focalPoint - _lastFocalPoint!; // Use this delta for rotation
            final scaleDelta = details.scale;

            setState(() {
              if (scaleDelta == 1.0) {
                // --- Handle Pan (One-finger drag) ---
                // Update the offset based on the drag delta
                _offset += delta;
              } else {
                // --- Handle Zoom (Two-finger pinch) ---

                // Panning adjustment during zoom - Keep this for smoother zoom?
                _offset += delta;

                // --- Zooming Calculation ---
                // Dampen the scaleDelta
                final effectiveScaleDelta =
                    1.0 + (scaleDelta - 1.0) * widget.zoomSensitivity;

                final newZoom =
                    _zoom * effectiveScaleDelta; // Use dampened scale

                final zoomFactor =
                    newZoom / _zoom; // Use newZoom based on dampened scale
                _zoom = newZoom;

                // Translate origin to focal point relative to current view center + offset
                final centerOffset =
                    Offset(size.width / 2, size.height / 2) + _offset;
                final focalPointVec = vector.Vector3(
                  focalPoint.dx - centerOffset.dx,
                  focalPoint.dy - centerOffset.dy,
                  0,
                );

                final translateToFocal = vector.Matrix4.translation(
                  -focalPointVec,
                );
                final scaleMatrix =
                    vector.Matrix4.identity()..scale(zoomFactor);
                final translateBack = vector.Matrix4.translation(focalPointVec);

                // Apply zoom centered around the focal point
                _transform =
                    translateBack * scaleMatrix * translateToFocal * _transform;
              }

              _lastFocalPoint = focalPoint;
            });
          },
          onScaleEnd: (details) {
            _lastFocalPoint = null;
          },
          child: ClipRect(
            // Prevent drawing outside bounds
            child: CustomPaint(
              size: size,
              painter: _GcodePainter(
                transform: _transform,
                zoom: _zoom,
                offset: _offset + initialOffset, // Apply centering offset
                pathPoints: _pathPoints, // Pass parsed points
                isTravelFlags: _isTravelFlags, // Pass travel flags
                zValues: _zValues, // Pass Z-values
                pathThickness: widget.pathThickness,
                cutColor: widget.cutColor,
                travelColor: widget.travelColor,
                gridColor: widget.gridColor,
                showGrid: widget.showGrid,
                isMillimeters: widget.isMillimeters,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GcodePainter extends CustomPainter {
  final vector.Matrix4 transform;
  final double zoom;
  final Offset offset;
  final List<vector.Vector3> pathPoints;
  final List<bool> isTravelFlags;
  final List<double> zValues;
  final double pathThickness;
  final Color cutColor;
  final Color travelColor;
  final Color gridColor;
  final bool showGrid;
  final bool isMillimeters;

  _GcodePainter({
    required this.transform,
    required this.zoom,
    required this.offset,
    required this.pathPoints,
    required this.isTravelFlags,
    required this.zValues,
    required this.pathThickness,
    required this.cutColor,
    required this.travelColor,
    required this.gridColor,
    required this.showGrid,
    required this.isMillimeters,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..strokeWidth = pathThickness
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;

    final gridPaint =
        Paint()
          ..color = gridColor
          ..strokeWidth = 0.5
          ..style = PaintingStyle.stroke;

    final axisPaint =
        Paint()
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke;

    // --- Projection Logic ---
    // Simple orthographic projection for now
    // Perspective would require a different projection matrix calculation
    vector.Vector3 project(vector.Vector3 p) {
      // Convert Vector3 to Vector4 (w=1 for points)
      final p4 = vector.Vector4(p.x, p.y, p.z, 1.0);
      // Apply the 3D transformation (rotation, etc.)
      final transformed = transform.transformed(p4);
      // Apply perspective division if needed (for perspective projection)
      // For orthographic, w remains 1 (or should be handled)
      // Let's assume orthographic for now, just use x, y, z
      final transformed3 = vector.Vector3(
        transformed.x,
        transformed.y,
        transformed.z,
      );

      // Apply zoom (scaling)
      final scaled = transformed3 * zoom;
      // Apply panning offset
      return vector.Vector3(
        scaled.x + offset.dx,
        scaled.y + offset.dy,
        scaled.z,
      ); // Keep z for potential future use (depth sorting, etc.)
    }

    // --- Draw Grid (if enabled) ---
    if (showGrid) {
      final double gridSpacing =
          isMillimeters ? 100.0 : 4.0 * 25.4; // 10cm or 4 inches in mm
      final int gridLines = 20; // Number of lines each side of origin
      final double maxCoord = gridLines * gridSpacing;

      for (int i = -gridLines; i <= gridLines; i++) {
        final double pos = i * gridSpacing;

        // Lines parallel to Y axis (on XY plane, z=0)
        final p1Xy = project(vector.Vector3(pos, -maxCoord, 0));
        final p2Xy = project(vector.Vector3(pos, maxCoord, 0));
        canvas.drawLine(
          Offset(p1Xy.x, p1Xy.y),
          Offset(p2Xy.x, p2Xy.y),
          gridPaint,
        );

        // Lines parallel to X axis (on XY plane, z=0)
        final p3Xy = project(vector.Vector3(-maxCoord, pos, 0));
        final p4Xy = project(vector.Vector3(maxCoord, pos, 0));
        canvas.drawLine(
          Offset(p3Xy.x, p3Xy.y),
          Offset(p4Xy.x, p4Xy.y),
          gridPaint,
        );
      }
    }

    // --- Draw Axes ---
    final origin = project(vector.Vector3(0, 0, 0));

    // Function to prepare and paint text labels
    void paintAxisLabel(String label, Offset position, Color color) {
      final textStyle = TextStyle(
        color: color,
        fontSize: 14,
        fontWeight: FontWeight.bold,
      );
      final textSpan = TextSpan(text: label, style: textStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout(minWidth: 0, maxWidth: size.width);

      // Offset slightly from the axis end point
      // Calculate direction vector from origin to endpoint
      final originOffset = Offset(origin.x, origin.y);
      final direction = position - originOffset;
      // Normalize direction and multiply by desired offset distance
      final offsetDistance = 10.0;
      final normalizedDirection = direction / direction.distance;
      final textOffsetPosition =
          position + (normalizedDirection * offsetDistance);

      // Adjust position to center the text
      final finalPosition = Offset(
        textOffsetPosition.dx - textPainter.width / 2,
        textOffsetPosition.dy - textPainter.height / 2,
      );

      textPainter.paint(canvas, finalPosition);
    }

    // X Axis (Red) - Reverted to positive X direction
    final xAxisEnd = project(
      vector.Vector3(50, 0, 0),
    ); // Use a fixed world length in positive X
    canvas.drawLine(
      Offset(origin.x, origin.y),
      Offset(xAxisEnd.x, xAxisEnd.y),
      axisPaint..color = Colors.red,
    );
    paintAxisLabel('X', Offset(xAxisEnd.x, xAxisEnd.y), Colors.red);

    // Y Axis (Green)
    final yAxisEnd = project(
      vector.Vector3(0, 50, 0),
    ); // Use a fixed world length
    canvas.drawLine(
      Offset(origin.x, origin.y),
      Offset(yAxisEnd.x, yAxisEnd.y),
      axisPaint..color = Colors.green,
    );
    paintAxisLabel('Y', Offset(yAxisEnd.x, yAxisEnd.y), Colors.green);

    // Z Axis (Blue)
    final zAxisEnd = project(
      vector.Vector3(0, 0, 50),
    ); // Use a fixed world length
    canvas.drawLine(
      Offset(origin.x, origin.y),
      Offset(
        zAxisEnd.x,
        zAxisEnd.y,
      ), // Draw Z axis based on its projected position
      axisPaint..color = Colors.blue,
    );
    paintAxisLabel('Z', Offset(zAxisEnd.x, zAxisEnd.y), Colors.blue);

    // --- Draw Path Segments ---
    if (pathPoints.isEmpty) return; // No points to draw

    // Create path segments list
    List<GcodePath> pathSegments = [];

    // If we have precalculated path segments, use them
    if (kDebugMode) {
      print("Drawing G-code with ${pathPoints.length} points");
    }

    // If segments not provided, rebuild from scratch
    if (pathSegments.isEmpty) {
      // Create a simple travel/cutting path split for visualization
      if (kDebugMode) {
        print("No path segments found - creating from flags");
      }

      List<vector.Vector3> currentPath = [];
      bool isCurrentPathTravel = false;
      bool pathStarted = false;

      for (int i = 0; i < pathPoints.length; i++) {
        bool isPointTravel =
            i < isTravelFlags.length ? isTravelFlags[i] : false;

        if (!pathStarted) {
          // Start first path
          currentPath.add(pathPoints[i]);
          isCurrentPathTravel = isPointTravel;
          pathStarted = true;
        } else if (isPointTravel != isCurrentPathTravel) {
          // When travel status changes, finish the current path
          pathSegments.add(
            GcodePath(List.from(currentPath), isCurrentPathTravel),
          );

          // Start a new path
          currentPath = [pathPoints[i - 1].clone(), pathPoints[i].clone()];
          isCurrentPathTravel = isPointTravel;
        } else {
          // Continue current path
          currentPath.add(pathPoints[i]);
        }
      }

      // Add the final path segment
      if (currentPath.isNotEmpty) {
        pathSegments.add(GcodePath(currentPath, isCurrentPathTravel));
      }
    }

    if (kDebugMode) {
      print("Drawing ${pathSegments.length} path segments");
      print("Cut paths: ${pathSegments.where((p) => !p.isTravel).length}");
      print("Travel paths: ${pathSegments.where((p) => p.isTravel).length}");
    }

    // Draw all cutting paths first
    paint.color = cutColor;
    paint.strokeWidth = pathThickness;
    paint.maskFilter = const MaskFilter.blur(
      BlurStyle.normal,
      0.5,
    ); // Shadow for depth

    for (final segment in pathSegments) {
      if (segment.isTravel) continue; // Skip travel paths for now
      if (segment.points.length < 2) continue; // Need at least 2 points to draw

      final path = Path();
      var firstPoint = project(segment.points[0]);
      path.moveTo(firstPoint.x, firstPoint.y);

      for (int i = 1; i < segment.points.length; i++) {
        final point = project(segment.points[i]);
        path.lineTo(point.x, point.y);
      }

      canvas.drawPath(path, paint);
    }

    // Then draw all travel paths
    paint.color = travelColor;
    paint.strokeWidth =
        pathThickness * 1.2; // Plus épais que les déplacements de coupe
    paint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.5);
    paint.strokeCap = StrokeCap.round;
    paint.strokeJoin = StrokeJoin.round;

    // Dessiner d'abord le premier déplacement avec une couleur accentuée si disponible
    if (pathSegments.isNotEmpty && pathSegments.any((seg) => seg.isTravel)) {
      // Trouver le premier déplacement
      final firstTravelSegment = pathSegments.firstWhere(
        (seg) => seg.isTravel,
        orElse: () => pathSegments.first,
      );

      if (firstTravelSegment.isTravel &&
          firstTravelSegment.points.length >= 2) {
        // Dessiner le premier déplacement avec une couleur plus vive
        final specialPaint =
            Paint()
              ..color = travelColor
              ..strokeWidth =
                  pathThickness *
                  1.5 // Encore plus épais
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round;

        final path = Path();
        var firstPoint = project(firstTravelSegment.points[0]);
        path.moveTo(firstPoint.x, firstPoint.y);

        for (int i = 1; i < firstTravelSegment.points.length; i++) {
          final point = project(firstTravelSegment.points[i]);
          path.lineTo(point.x, point.y);
        }

        // Dessiner avec un double trait pour le rendre plus visible
        canvas.drawPath(path, specialPaint);

        if (kDebugMode) {
          print(
            "Premier déplacement dessiné en surbrillance: ${firstTravelSegment.points.first} -> ${firstTravelSegment.points.last}",
          );
        }
      }
    }

    // Dessiner les autres déplacements rapides
    for (final segment in pathSegments) {
      if (!segment.isTravel) continue; // Skip cutting paths
      if (segment.points.length < 2) continue; // Need at least 2 points to draw

      final path = Path();
      var firstPoint = project(segment.points[0]);
      path.moveTo(firstPoint.x, firstPoint.y);

      for (int i = 1; i < segment.points.length; i++) {
        final point = project(segment.points[i]);
        path.lineTo(point.x, point.y);
      }

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GcodePainter oldDelegate) {
    // Repaint if any of the parameters change
    return oldDelegate.transform != transform ||
        oldDelegate.zoom != zoom ||
        oldDelegate.offset != offset ||
        !listEquals(oldDelegate.pathPoints, pathPoints) ||
        !listEquals(oldDelegate.isTravelFlags, isTravelFlags) ||
        !listEquals(oldDelegate.zValues, zValues) ||
        oldDelegate.pathThickness != pathThickness ||
        oldDelegate.cutColor != cutColor ||
        oldDelegate.travelColor != travelColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.showGrid != showGrid ||
        oldDelegate.isMillimeters != isMillimeters;
  }
}
