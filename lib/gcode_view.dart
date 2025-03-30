/// A Flutter package for visualizing G-code in 3D with interactive controls.
///
/// The package provides a [GcodeViewer] widget for rendering G-code paths
/// with support for panning, zooming, and a controller API.
library;

export 'src/gcode_viewer.dart';
export 'src/gcode_parser.dart'
    show GcodePath, ParsedGcode, parseGcode, GcodeParserConfig;
export 'src/gcode_viewer.dart'
    show GcodeViewerController, GcodeViewerConfig, GcodeViewer;
