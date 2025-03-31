/// A Flutter package for visualizing G-code in 3D with interactive controls.
///
/// The package provides a [GcodeViewer] widget for rendering G-code paths
/// with support for panning, zooming, and a controller API.
library;

export 'src/gcode_viewer.dart';
export 'src/gcode_viewer.dart' show GcodeViewer;
export 'src/controllers/gcode_viewer_controller.dart'
    show GcodeViewerController;
export 'src/configs/gcode_viewer_config.dart' show GcodeViewerConfig;
