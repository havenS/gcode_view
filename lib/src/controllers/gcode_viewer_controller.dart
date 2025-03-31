import 'dart:ui';

class GcodeViewerController {
  VoidCallback? _resetViewCallback;
  VoidCallback? _refreshViewCallback;

  /// Resets the camera view (position, rotation, zoom) to its initial state.
  void resetView() {
    _resetViewCallback?.call();
  }

  /// Forces a refresh of the view.
  void refreshView() {
    _refreshViewCallback?.call();
  }

  // Internal methods for the widget to register its state's methods
  void attach(VoidCallback resetCallback, VoidCallback refreshCallback) {
    _resetViewCallback = resetCallback;
    _refreshViewCallback = refreshCallback;
  }

  void detach() {
    _resetViewCallback = null;
    _refreshViewCallback = null;
  }
}
