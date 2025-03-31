/// Parser configuration for controlling detail level and thus performance
class GcodeParserConfig {
  /// Detail level for arc rendering (1.0 = normal, higher = more detailed)
  final double arcDetailLevel;

  /// Minimum distance in units between points before simplification
  /// Smaller values = more detailed paths, larger values = more performance
  final double segmentThreshold;

  /// Maximum segments for arcs (prevent excessive detailing)
  final int maxArcSegments;

  /// Create a parser configuration
  const GcodeParserConfig({
    this.arcDetailLevel = 1.0,
    this.segmentThreshold = 0.05, // Default to 0.05mm threshold
    this.maxArcSegments = 300, // Cap for performance
  });
}
