import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gcode_view/gcode_view.dart';
import 'package:gcode_view/src/configs/gcode_parser_config.dart';
import 'package:gcode_view/src/gcode_parser.dart';
import 'package:gcode_view/src/models/gcode_path.dart';
import 'package:gcode_view/src/models/parsed_gcode.dart';
import 'package:gcode_view/src/painter/gcode_painter.dart';
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
                      painter: GcodePainter(
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
