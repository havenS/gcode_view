import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gcode_view/gcode_view.dart';
import 'package:gcode_view/src/configs/gcode_parser_config.dart';
import 'package:gcode_view/src/gcode_parser.dart';
import 'package:gcode_view/src/models/gcode_path.dart';
import 'package:gcode_view/src/models/parsed_gcode.dart';
import 'package:vector_math/vector_math_64.dart' as vector;
import 'dart:math' as math;

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

  /// Detailed configuration for the viewer
  final GcodeViewerConfig? config;

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
    this.config,
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

  // Camera mode (true for rotation, false for movement)
  bool _isRotationMode = false;

  // Store parsed G-code results
  late ParsedGcode _parsedGcode;
  List<vector.Vector3> _pathPoints = [];
  List<bool> _isTravelFlags = [];
  List<double> _zValues = [];

  // Path caching for improved performance
  final Map<String, ui.Path> _pathCache = {};
  bool _needsPathRebuild = true;

  // Repaint timer
  Timer? _repaintTimer;

  // Configuration
  late GcodeViewerConfig _config;

  @override
  void initState() {
    super.initState();
    _transform = _initialTransform.clone();
    _config = widget.config ?? const GcodeViewerConfig();
    widget.controller?.attach(_resetView, _refreshView);
    _parseAndUpdatePath(); // Parse initial G-code
  }

  @override
  void didUpdateWidget(covariant GcodeViewer oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Update configuration if needed
    if (widget.config != oldWidget.config) {
      _config = widget.config ?? const GcodeViewerConfig();
    }

    bool controllerChanged = false;
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller?.detach();
      widget.controller?.attach(_resetView, _refreshView);
      controllerChanged = true;
    }

    // Re-parse if G-code string changes or if other key properties change
    if (widget.gcode != oldWidget.gcode ||
        widget.isMillimeters != oldWidget.isMillimeters ||
        controllerChanged) {
      _parseAndUpdatePath();
    }

    // Check if we need to invalidate path cache due to style changes
    if (widget.pathThickness != oldWidget.pathThickness ||
        widget.cutColor != oldWidget.cutColor ||
        widget.travelColor != oldWidget.travelColor) {
      _invalidatePathCache();
    }
  }

  void _parseAndUpdatePath() {
    if (widget.gcode.isEmpty) {
      setState(() {
        _pathPoints = [];
        _isTravelFlags = [];
        _zValues = [];
        _parsedGcode = ParsedGcode([], [], []);
        _invalidatePathCache();
      });
      return;
    }

    try {
      // Configure the parser with our performance settings
      final parserConfig = GcodeParserConfig(
        arcDetailLevel: _config.arcDetailLevel,
        maxArcSegments: 200, // Cap arc segments for performance
        segmentThreshold: 0.05, // 0.05mm minimum segment length
      );

      final parsedData = parseGcode(widget.gcode, config: parserConfig);

      setState(() {
        _parsedGcode = parsedData;
        _pathPoints = parsedData.points;
        _isTravelFlags = parsedData.isTravel;
        _zValues = parsedData.zValues;
        _invalidatePathCache();
      });
    } catch (e) {
      if (kDebugMode) {
        print("Error parsing G-code: $e");
      }
      // Clear path on error
      setState(() {
        _pathPoints = [];
        _isTravelFlags = [];
        _zValues = [];
        _parsedGcode = ParsedGcode([], [], []);
        _invalidatePathCache();
      });
    }
  }

  // Invalidates path cache to force rebuild
  void _invalidatePathCache() {
    _pathCache.clear();
    _needsPathRebuild = true;
  }

  @override
  void dispose() {
    _repaintTimer?.cancel();
    _pathCache.clear();
    widget.controller?.detach();
    super.dispose();
  }

  /// Resets the view to the initial state
  void _resetView() {
    setState(() {
      _transform = _initialTransform.clone();

      // Reset zoom and offset
      _zoom = 1.0;
      _offset = Offset.zero;
      _lastFocalPoint = null;

      _invalidatePathCache();
    });
  }

  /// Forces a refresh of the view
  void _refreshView() {
    setState(() {
      _invalidatePathCache();
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        // Center the view initially
        final initialOffset = Offset(size.width / 2, size.height / 2);

        return Column(
          children: [
            // Mode switch
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Move Mode'),
                  Switch(
                    value: _isRotationMode,
                    onChanged: (value) {
                      setState(() {
                        _isRotationMode = value;
                      });
                    },
                  ),
                  const Text('Rotate Mode'),
                ],
              ),
            ),
            // Viewer
            Expanded(
              child: GestureDetector(
                onScaleStart: (details) {
                  _lastFocalPoint = details.localFocalPoint;
                },
                onScaleUpdate: (details) {
                  if (_lastFocalPoint == null) return;

                  final focalPoint = details.localFocalPoint;
                  final delta = focalPoint - _lastFocalPoint!;
                  final scaleDelta = details.scale;

                  if (_isRotationMode) {
                    // Rotation mode: rotate the view based on drag direction
                    setState(() {
                      // Apply rotations around the focal point
                      final centerOffset =
                          Offset(size.width / 2, size.height / 2) + _offset;
                      final focalPointVec = vector.Vector3(
                        focalPoint.dx - centerOffset.dx,
                        focalPoint.dy - centerOffset.dy,
                        0,
                      );

                      // Calculate distance from focal point to affect rotation speed
                      final distance = focalPointVec.length;
                      final rotationFactor = math.max(
                        0.1,
                        math.min(1.0, distance / 100),
                      );

                      // Calculate rotation angles based on drag distance
                      // Use a smaller factor for more precise control
                      final rotationX =
                          delta.dy *
                          0.005 *
                          rotationFactor; // Up/down rotation around X
                      final rotationY =
                          -delta.dx *
                          0.005 *
                          rotationFactor; // Left/right rotation around Y

                      // Create rotation matrices
                      final rotateX = vector.Matrix4.rotationX(rotationX);
                      final rotateY = vector.Matrix4.rotationY(rotationY);

                      final translateToFocal = vector.Matrix4.translation(
                        -focalPointVec,
                      );
                      final translateBack = vector.Matrix4.translation(
                        focalPointVec,
                      );

                      // Apply transformations with rotation factor
                      // First rotate around Y (left/right) to maintain Z vertical
                      // Then rotate around X (up/down)
                      _transform =
                          translateBack *
                          rotateX *
                          rotateY *
                          translateToFocal *
                          _transform;
                      _invalidatePathCache();
                    });
                  } else {
                    // Movement mode: pan and zoom
                    if (scaleDelta == 1.0) {
                      // Pan operation (one-finger drag)
                      setState(() {
                        // Apply panning with a slight dampening for smoother movement
                        final panFactor = 0.8;
                        _offset += delta * panFactor;
                        _invalidatePathCache();
                      });
                    } else {
                      // Zoom operation (pinch)
                      setState(() {
                        _offset += delta;

                        // Adjust zoom sensitivity for more natural feel
                        final effectiveScaleDelta =
                            1.0 +
                            (scaleDelta - 1.0) * _config.zoomSensitivity * 0.5;
                        final newZoom = _zoom * effectiveScaleDelta;
                        final zoomFactor = newZoom / _zoom;
                        _zoom = newZoom;

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
                        final translateBack = vector.Matrix4.translation(
                          focalPointVec,
                        );

                        _transform =
                            translateBack *
                            scaleMatrix *
                            translateToFocal *
                            _transform;
                        _invalidatePathCache();
                      });
                    }
                  }

                  _lastFocalPoint = focalPoint;
                },
                onScaleEnd: (details) {
                  _lastFocalPoint = null;
                },
                child: RepaintBoundary(
                  child: ClipRect(
                    child: CustomPaint(
                      size: size,
                      painter: _GcodePainter(
                        transform: _transform,
                        zoom: _zoom,
                        offset: _offset + initialOffset,
                        parsedGcode: _parsedGcode,
                        pathPoints: _pathPoints,
                        isTravelFlags: _isTravelFlags,
                        zValues: _zValues,
                        pathThickness: widget.pathThickness,
                        cutColor: widget.cutColor,
                        travelColor: widget.travelColor,
                        gridColor: widget.gridColor,
                        showGrid: widget.showGrid,
                        isMillimeters: widget.isMillimeters,
                        useLevelOfDetail: _config.useLevelOfDetail,
                        usePathCaching: _config.usePathCaching,
                        maxPointsToRender: _config.maxPointsToRender,
                        pathCache: _pathCache,
                        needsPathRebuild: _needsPathRebuild,
                        onPathsBuilt: () {
                          _needsPathRebuild = false;
                        },
                        preserveSmallFeatures: _config.preserveSmallFeatures,
                        smallFeatureThreshold: _config.smallFeatureThreshold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GcodePainter extends CustomPainter {
  final vector.Matrix4 transform;
  final double zoom;
  final Offset offset;
  final ParsedGcode parsedGcode;
  final List<vector.Vector3> pathPoints;
  final List<bool> isTravelFlags;
  final List<double> zValues;
  final double pathThickness;
  final Color cutColor;
  final Color travelColor;
  final Color gridColor;
  final bool showGrid;
  final bool isMillimeters;
  final bool useLevelOfDetail;
  final bool usePathCaching;
  final int maxPointsToRender;
  final Map<String, ui.Path> pathCache;
  final bool needsPathRebuild;
  final VoidCallback onPathsBuilt;
  final bool preserveSmallFeatures;
  final double smallFeatureThreshold;

  _GcodePainter({
    required this.transform,
    required this.zoom,
    required this.offset,
    required this.parsedGcode,
    required this.pathPoints,
    required this.isTravelFlags,
    required this.zValues,
    required this.pathThickness,
    required this.cutColor,
    required this.travelColor,
    required this.gridColor,
    required this.showGrid,
    required this.isMillimeters,
    required this.useLevelOfDetail,
    required this.usePathCaching,
    required this.maxPointsToRender,
    required this.pathCache,
    required this.needsPathRebuild,
    required this.onPathsBuilt,
    required this.preserveSmallFeatures,
    required this.smallFeatureThreshold,
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
    // Simple orthographic projection with consistent offset handling
    vector.Vector3 project(vector.Vector3 p) {
      // Apply the 3D transform
      final p4 = vector.Vector4(p.x, p.y, p.z, 1.0);
      final transformed = transform.transformed(p4);
      final transformed3 = vector.Vector3(
        transformed.x,
        transformed.y,
        transformed.z,
      );

      // Apply zoom
      final scaled = transformed3 * zoom;

      // Apply offset consistently
      return vector.Vector3(
        scaled.x + offset.dx,
        scaled.y + offset.dy,
        scaled.z,
      );
    }

    // --- Draw Grid (if enabled) ---
    if (showGrid) {
      // Efficiently render grid with level-of-detail based on zoom
      _renderGrid(canvas, size, gridPaint, project);
    }

    // --- Draw Axes ---
    _renderAxes(canvas, size, axisPaint, project);

    // --- Draw Path Segments ---
    if (pathPoints.isEmpty) return;

    // Handle the case when we have too many points to render efficiently
    final shouldReduceDetail =
        useLevelOfDetail &&
        maxPointsToRender > 0 &&
        pathPoints.length > maxPointsToRender;

    // Generate cache key that includes offset to prevent cache reuse when panning
    final offsetKey =
        "${offset.dx.toStringAsFixed(0)},${offset.dy.toStringAsFixed(0)}";

    // Determine segments for drawing
    final List<GcodePath> pathSegments = parsedGcode.pathSegments;

    // Get/build paths from cache or create new ones if needed
    final cuttingPaths = _getCachedPaths(
      false, // Not travel paths (cutting paths)
      shouldReduceDetail,
      project,
      pathSegments,
      offsetKey, // Include offset in cache key
    );

    final travelPaths = _getCachedPaths(
      true, // Travel paths
      shouldReduceDetail,
      project,
      pathSegments,
      offsetKey, // Include offset in cache key
    );

    // Mark that paths are now built and cached
    if (needsPathRebuild) {
      onPathsBuilt();
    }

    // Draw cutting paths
    paint.color = cutColor;
    paint.strokeWidth = pathThickness;
    paint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.5);

    for (final path in cuttingPaths) {
      canvas.drawPath(path, paint);
    }

    // Draw travel paths
    paint.color = travelColor;
    paint.strokeWidth = pathThickness * 1.2;
    paint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.5);

    for (final path in travelPaths) {
      canvas.drawPath(path, paint);
    }

    // Special handling for first travel segment to highlight it
    if (pathSegments.isNotEmpty && pathSegments.any((seg) => seg.isTravel)) {
      _renderFirstTravelPath(canvas, paint, project, pathSegments);
    }
  }

  // Efficiently render the grid with level-of-detail based on zoom
  void _renderGrid(
    Canvas canvas,
    Size size,
    Paint gridPaint,
    Function project,
  ) {
    final double gridSpacing =
        isMillimeters ? 100.0 : 4.0 * 25.4; // 10cm or 4 inches in mm

    // Level of detail - adjust grid density based on zoom
    final gridDensity =
        zoom < 0.5
            ? 5
            : zoom < 1.0
            ? 10
            : zoom < 2.0
            ? 20
            : 30;

    final int gridLines = gridDensity;
    final double maxCoord = gridLines * gridSpacing;

    // Optimization: batch grid lines into paths rather than individual drawLine calls
    final Path horizontalGridPath = Path();
    final Path verticalGridPath = Path();

    for (int i = -gridLines; i <= gridLines; i++) {
      final double pos = i * gridSpacing;

      // Lines parallel to Y axis
      final p1Xy = project(vector.Vector3(pos, -maxCoord, 0));
      final p2Xy = project(vector.Vector3(pos, maxCoord, 0));

      horizontalGridPath.moveTo(p1Xy.x, p1Xy.y);
      horizontalGridPath.lineTo(p2Xy.x, p2Xy.y);

      // Lines parallel to X axis
      final p3Xy = project(vector.Vector3(-maxCoord, pos, 0));
      final p4Xy = project(vector.Vector3(maxCoord, pos, 0));

      verticalGridPath.moveTo(p3Xy.x, p3Xy.y);
      verticalGridPath.lineTo(p4Xy.x, p4Xy.y);
    }

    // Draw all grid lines at once
    canvas.drawPath(horizontalGridPath, gridPaint);
    canvas.drawPath(verticalGridPath, gridPaint);
  }

  // Render coordinate axes
  void _renderAxes(
    Canvas canvas,
    Size size,
    Paint axisPaint,
    Function project,
  ) {
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

      // Offset from axis endpoint
      final originOffset = Offset(origin.x, origin.y);
      final direction = position - originOffset;
      final offsetDistance = 10.0;
      final normalizedDirection = direction / direction.distance;
      final textOffsetPosition =
          position + (normalizedDirection * offsetDistance);

      // Center the text
      final finalPosition = Offset(
        textOffsetPosition.dx - textPainter.width / 2,
        textOffsetPosition.dy - textPainter.height / 2,
      );

      textPainter.paint(canvas, finalPosition);
    }

    // X Axis (Red)
    final xAxisEnd = project(vector.Vector3(50, 0, 0));
    canvas.drawLine(
      Offset(origin.x, origin.y),
      Offset(xAxisEnd.x, xAxisEnd.y),
      axisPaint..color = Colors.red,
    );
    paintAxisLabel('X', Offset(xAxisEnd.x, xAxisEnd.y), Colors.red);

    // Y Axis (Green)
    final yAxisEnd = project(vector.Vector3(0, 50, 0));
    canvas.drawLine(
      Offset(origin.x, origin.y),
      Offset(yAxisEnd.x, yAxisEnd.y),
      axisPaint..color = Colors.green,
    );
    paintAxisLabel('Y', Offset(yAxisEnd.x, yAxisEnd.y), Colors.green);

    // Z Axis (Blue)
    final zAxisEnd = project(vector.Vector3(0, 0, 50));
    canvas.drawLine(
      Offset(origin.x, origin.y),
      Offset(zAxisEnd.x, zAxisEnd.y),
      axisPaint..color = Colors.blue,
    );
    paintAxisLabel('Z', Offset(zAxisEnd.x, zAxisEnd.y), Colors.blue);
  }

  // Get cached paths or generate new ones
  List<ui.Path> _getCachedPaths(
    bool isTravel,
    bool reduceDetail,
    Function project,
    List<GcodePath> pathSegments,
    String offsetKey,
  ) {
    // Include offset in cache key to ensure paths are regenerated when panning
    final String cacheKey =
        "${isTravel ? "travel" : "cutting"}_${zoom.toStringAsFixed(2)}_$offsetKey";
    final List<ui.Path> resultPaths = [];

    // Return from cache if available and not needing rebuild
    if (usePathCaching &&
        !needsPathRebuild &&
        pathCache.containsKey(cacheKey)) {
      return [pathCache[cacheKey]!];
    }

    // Create new path
    final ui.Path combinedPath = Path();

    // Filtering function for segments
    bool shouldDrawSegment(GcodePath segment) {
      return segment.isTravel == isTravel;
    }

    // Apply path reduction if needed
    final filteredSegments = pathSegments.where(shouldDrawSegment).toList();

    // Apply level-of-detail reduction if needed
    final segmentsToRender =
        reduceDetail
            ? _applyLevelOfDetail(filteredSegments, maxPointsToRender)
            : filteredSegments;

    // Draw all segments
    for (final segment in segmentsToRender) {
      if (segment.points.length < 2) continue;

      final path = Path();
      final firstPoint = project(segment.points[0]);
      path.moveTo(firstPoint.x, firstPoint.y);

      // Add points to the path
      for (int i = 1; i < segment.points.length; i++) {
        final point = project(segment.points[i]);
        path.lineTo(point.x, point.y);
      }

      // Add to combined path
      combinedPath.addPath(path, Offset.zero);
    }

    // Store in cache if enabled
    if (usePathCaching) {
      pathCache[cacheKey] = combinedPath;
    }

    resultPaths.add(combinedPath);
    return resultPaths;
  }

  // Apply level-of-detail reduction to segments
  List<GcodePath> _applyLevelOfDetail(List<GcodePath> segments, int maxPoints) {
    // If we have few segments, just return them all
    if (segments.isEmpty) return segments;

    // Count total points
    int totalPoints = segments.fold(0, (sum, seg) => sum + seg.points.length);

    // If under limit, return all segments
    if (totalPoints <= maxPoints) return segments;

    // Create simplified segments
    final List<GcodePath> simplifiedSegments = [];

    for (final segment in segments) {
      if (segment.points.length < 2) continue;

      // For very short segments or segments with few points, keep them intact
      if (segment.points.length <= 8) {
        simplifiedSegments.add(segment);
        continue;
      }

      // Analyze the segment to detect small features like tabs, if enabled
      bool isSmallFeature =
          preserveSmallFeatures &&
          _isLikelySmallFeature(segment, smallFeatureThreshold);

      // Preserve small features (like tabs) with higher detail
      if (isSmallFeature) {
        // If it's a small feature, keep most points
        final skipFactor = math.max(2, (segment.points.length / 20).ceil());
        final List<vector.Vector3> simplifiedPoints = _simplifyWithSkipFactor(
          segment.points,
          skipFactor,
        );
        simplifiedSegments.add(GcodePath(simplifiedPoints, segment.isTravel));
      } else {
        // For regular segments, calculate skip factor based on total points
        final skipFactor = (totalPoints / maxPoints * 2).ceil();
        final List<vector.Vector3> simplifiedPoints = _simplifyWithSkipFactor(
          segment.points,
          skipFactor,
        );
        simplifiedSegments.add(GcodePath(simplifiedPoints, segment.isTravel));
      }
    }

    return simplifiedSegments;
  }

  // Helper function to detect if a feature is likely a small feature (like a tab)
  bool _isLikelySmallFeature(GcodePath segment, double threshold) {
    if (segment.points.length < 3) return false;

    // Find bounding box
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    for (final point in segment.points) {
      minX = math.min(minX, point.x);
      minY = math.min(minY, point.y);
      maxX = math.max(maxX, point.x);
      maxY = math.max(maxY, point.y);
    }

    // Calculate dimensions
    double width = maxX - minX;
    double height = maxY - minY;
    double area = width * height;

    // Calculate perimeter (approximate)
    double perimeter = 0;
    for (int i = 0; i < segment.points.length - 1; i++) {
      final p1 = segment.points[i];
      final p2 = segment.points[i + 1];
      final dx = p2.x - p1.x;
      final dy = p2.y - p1.y;
      perimeter += math.sqrt(dx * dx + dy * dy);
    }

    // Tab detection: Check for sharp corners - a sign of rectangular features like tabs
    int sharpCorners = 0;
    for (int i = 1; i < segment.points.length - 1; i++) {
      final prev = segment.points[i - 1];
      final curr = segment.points[i];
      final next = segment.points[i + 1];

      final v1x = curr.x - prev.x;
      final v1y = curr.y - prev.y;
      final v1len = math.sqrt(v1x * v1x + v1y * v1y);

      final v2x = next.x - curr.x;
      final v2y = next.y - curr.y;
      final v2len = math.sqrt(v2x * v2x + v2y * v2y);

      if (v1len > 0.0001 && v2len > 0.0001) {
        // Normalize vectors
        final v1nx = v1x / v1len;
        final v1ny = v1y / v1len;
        final v2nx = v2x / v2len;
        final v2ny = v2y / v2len;

        // Calculate dot product to find angle
        final dot = v1nx * v2nx + v1ny * v2ny;
        final angle = math.acos(dot.clamp(-1.0, 1.0));

        // If angle is close to 90 degrees (or less), count as sharp corner
        if (angle > math.pi / 4) {
          sharpCorners++;
        }
      }
    }

    // Ratio of perimeter squared to area - higher for complex shapes
    double complexity = (perimeter * perimeter) / (4 * math.pi * area);

    // Check if this is likely a tab:
    // 1. Small area compared to threshold
    // 2. Rectangular-ish (close to square or slightly elongated)
    // 3. Has some sharp corners (rectangular features have at least 3-4)
    return (area < threshold * threshold && // Small area
        (width < threshold ||
            height < threshold) && // At least one dimension is small
        complexity > 1.1 && // More complex than a simple circle
        sharpCorners >= 2); // Has some sharp corners
  }

  // Simplify a segment by skipping points based on a skip factor
  List<vector.Vector3> _simplifyWithSkipFactor(
    List<vector.Vector3> points,
    int skipFactor,
  ) {
    if (skipFactor <= 1 || points.length <= 3) return List.from(points);

    final List<vector.Vector3> simplified = [];

    // Always include first point
    simplified.add(points.first);

    // Add interior points based on skip factor
    for (int i = 1; i < points.length - 1; i++) {
      // Include point if it's a multiple of skip factor, or if it's a sharp turn
      bool isSharpTurn = false;

      if (i > 1 && i < points.length - 2) {
        final prev = points[i - 1];
        final curr = points[i];
        final next = points[i + 1];

        // Calculate vectors between points
        final v1 = vector.Vector2(curr.x - prev.x, curr.y - prev.y);
        final v2 = vector.Vector2(next.x - curr.x, next.y - curr.y);

        // Normalize vectors
        if (v1.length > 0.0001 && v2.length > 0.0001) {
          v1.normalize();
          v2.normalize();

          // Calculate dot product to find angle between vectors
          final dotProduct = v1.dot(v2);

          // If dot product is small or negative, it's a sharp turn
          isSharpTurn = dotProduct < 0.7; // Approx 45 degrees or more
        }
      }

      // Include the point if it's at a skip index, a sharp turn, or key positional point
      if (i % skipFactor == 0 || isSharpTurn) {
        simplified.add(points[i]);
      }
    }

    // Always include last point
    if (points.length > 1) {
      simplified.add(points.last);
    }

    return simplified;
  }

  // Special rendering for the first travel path to highlight it
  void _renderFirstTravelPath(
    Canvas canvas,
    Paint paint,
    Function project,
    List<GcodePath> pathSegments,
  ) {
    // Find the first travel segment
    final firstTravelSegment = pathSegments.firstWhere(
      (seg) => seg.isTravel,
      orElse: () => pathSegments.first,
    );

    if (firstTravelSegment.isTravel && firstTravelSegment.points.length >= 2) {
      // Use a more visible paint style
      final specialPaint =
          Paint()
            ..color = travelColor
            ..strokeWidth =
                pathThickness *
                1.5 // Thicker
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round;

      final path = Path();
      final firstPoint = project(firstTravelSegment.points[0]);
      path.moveTo(firstPoint.x, firstPoint.y);

      for (int i = 1; i < firstTravelSegment.points.length; i++) {
        final point = project(firstTravelSegment.points[i]);
        path.lineTo(point.x, point.y);
      }

      // Draw with a double stroke for better visibility
      canvas.drawPath(path, specialPaint);

      if (kDebugMode) {
        print(
          "First travel movement drawn highlighted: ${firstTravelSegment.points.first} -> ${firstTravelSegment.points.last}",
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GcodePainter oldDelegate) {
    // Optimize repaint decisions
    return oldDelegate.transform != transform ||
        oldDelegate.zoom != zoom ||
        oldDelegate.offset != offset ||
        oldDelegate.pathThickness != pathThickness ||
        oldDelegate.cutColor != cutColor ||
        oldDelegate.travelColor != travelColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.showGrid != showGrid ||
        oldDelegate.isMillimeters != isMillimeters ||
        needsPathRebuild ||
        oldDelegate.parsedGcode != parsedGcode;
  }
}
