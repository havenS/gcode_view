class GcodeViewerConfig {
  /// Controls the sensitivity of zooming gestures
  final double zoomSensitivity;

  /// Whether to use path caching for better performance
  final bool usePathCaching;

  /// Whether to use level-of-detail rendering based on zoom
  final bool useLevelOfDetail;

  /// Maximum points to render at once for performance (0 = no limit)
  final int maxPointsToRender;

  /// Detail level for arc rendering
  final double arcDetailLevel;

  /// Whether to enable enhanced small feature detection (tabs, slots)
  final bool preserveSmallFeatures;

  /// Threshold in mm below which features are considered "small" and preserved
  final double smallFeatureThreshold;

  /// Create a viewer configuration
  const GcodeViewerConfig({
    this.zoomSensitivity = 0.5,
    this.usePathCaching = true,
    this.useLevelOfDetail = true,
    this.maxPointsToRender = 10000,
    this.arcDetailLevel = 1.0,
    this.preserveSmallFeatures = true,
    this.smallFeatureThreshold = 5.0,
  });

  /// Returns a high detail configuration optimized for small feature rendering
  factory GcodeViewerConfig.highDetail() {
    return const GcodeViewerConfig(
      zoomSensitivity: 0.5,
      usePathCaching: true,
      useLevelOfDetail: false, // Disable LOD for high detail rendering
      maxPointsToRender: 100000, // Allow many more points to render
      arcDetailLevel: 4.0, // Very high arc detail
      preserveSmallFeatures: true, // Always preserve small features
      smallFeatureThreshold: 20.0, // More aggressive small feature detection
    );
  }
}
