import 'dart:ui';

/// A controller class for managing the G-code viewer's view state and interactions.
///
/// This controller provides methods to programmatically control the viewer's camera
/// position and trigger view updates. It is typically used when you need to control
/// the viewer from outside the widget, such as in response to user actions or
/// application events.
class GcodeViewerController {
  VoidCallback? _resetViewCallback;
  VoidCallback? _refreshViewCallback;

  /// Resets the camera view (position, rotation, zoom) to its initial state.
  ///
  /// This method will restore the viewer to its default view position, which is
  /// typically set to show the entire G-code model centered in the view.
  void resetView() {
    _resetViewCallback?.call();
  }

  /// Forces a refresh of the view.
  ///
  /// This method can be called to force the viewer to redraw its contents,
  /// which is useful when the underlying G-code data has changed or when
  /// you need to ensure the view is up to date.
  void refreshView() {
    _refreshViewCallback?.call();
  }

  /// Internal method used by the widget to register its state's methods.
  ///
  /// This method is called by the [GcodeViewer] widget to provide the controller
  /// with callbacks to the widget's internal state. It should not be called directly
  /// by users of the package.
  void attach(VoidCallback resetCallback, VoidCallback refreshCallback) {
    _resetViewCallback = resetCallback;
    _refreshViewCallback = refreshCallback;
  }

  /// Internal method used by the widget to unregister its state's methods.
  ///
  /// This method is called by the [GcodeViewer] widget when it is disposed to
  /// clean up the controller's references. It should not be called directly by
  /// users of the package.
  void detach() {
    _resetViewCallback = null;
    _refreshViewCallback = null;
  }
}
